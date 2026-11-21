#!/usr/bin/env bash
# Version 3.0.0
#
# Audio normalization/conversion for every MKV under a directory.
#
# Usage: ./eac3convert.sh [-n|--dry-run] [--] /path/to/directory
#
# - Audio tracks that are not AC-3/E-AC-3 are converted to E-AC-3
#   (Dolby Digital Plus). Anything with more than 6 channels is
#   downmixed to 5.1 as part of the conversion.
# - Existing AC-3/E-AC-3 tracks are never re-encoded and never remuxed
#   on their own; only their metadata is updated in place via
#   mkvpropedit.
# - Track titles are normalized and undefined languages are fixed.
# - Lossy sources are not inflated: the E-AC-3 bitrate is capped at
#   1.5x the source bitrate (lossless sources use a fixed table).
# - A lock file keeps two instances from running at once.
#
# Environment overrides:
#   FFMPEG_BIN, FFPROBE_BIN, MKVPROPEDIT_BIN, LANG_OVERRIDE (default: eng)
#
# Exit codes:
#   0  finished with no failures
#   1  one or more files failed, or the lock could not be acquired
#   2  usage or missing-directory error
#   3  missing dependency

set -uo pipefail

FFMPEG_BIN="${FFMPEG_BIN:-$(command -v ffmpeg || true)}"
FFPROBE_BIN="${FFPROBE_BIN:-$(command -v ffprobe || true)}"
MKVPROPEDIT_BIN="${MKVPROPEDIT_BIN:-$(command -v mkvpropedit || true)}"
LANG_OVERRIDE="${LANG_OVERRIDE:-eng}"
LOCKFILE="/tmp/eac3_convert.lock"

DRY_RUN=0
WORKINGDIRECTORY=""
newfile=""

usage() {
  echo "Usage: $0 [-n|--dry-run] [--] <directory>"
}

# --- Argument handling ---
while (( $# > 0 )); do
  case "$1" in
    -n|--dry-run) DRY_RUN=1 ;;
    -h|--help)    usage; exit 0 ;;
    --)           shift; WORKINGDIRECTORY="${1:-}"; break ;;
    -*)           echo "❌ Unknown option: $1"; usage; exit 2 ;;
    *)            WORKINGDIRECTORY="$1" ;;
  esac
  shift
done

if [[ -z "$WORKINGDIRECTORY" ]]; then
  echo "⚠️  Please call this script with a trailing directory part to process."
  usage
  exit 2
fi

# Guard against directory names that look like options.
[[ "$WORKINGDIRECTORY" == -* ]] && WORKINGDIRECTORY="./$WORKINGDIRECTORY"

if [[ ! -d "$WORKINGDIRECTORY" ]]; then
  echo "❌ $WORKINGDIRECTORY doesn't exist, aborting."
  exit 2
fi

# --- Verify required tools ---
if [[ ! -x "$FFPROBE_BIN" ]]; then
  echo "❌ ffprobe not found (set FFPROBE_BIN to override)"
  exit 3
fi

if [[ ! -x "$FFMPEG_BIN" ]]; then
  echo "❌ ffmpeg not found (set FFMPEG_BIN to override)"
  exit 3
fi

if [[ ! -x "$MKVPROPEDIT_BIN" ]]; then
  echo "❌ mkvpropedit not found (set MKVPROPEDIT_BIN to override)"
  exit 3
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq not found in PATH"
  exit 3
fi

# --- Acquire lock ---
exec 200>"$LOCKFILE"
flock -w 600 200 || {
  echo "⏳ Timeout waiting for lock (10 minutes). Another instance may be stuck. Exiting."
  exit 1
}

# --- Cleanup of the in-progress temp file on any exit / interrupt ---
cleanup() {
  if [[ -n "$newfile" ]]; then
    rm -f -- "$newfile"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# --- Counters ---
converted=0
skipped=0
failed=0
metadata_only=0

# --- Helper functions ---
language_name() {
  case "${1,,}" in
    en|eng)        echo "English" ;;
    ja|jpn)        echo "Japanese" ;;
    fr|fra|fre)    echo "French" ;;
    de|ger|deu)    echo "German" ;;
    es|spa)        echo "Spanish" ;;
    it|ita)        echo "Italian" ;;
    pt|por)        echo "Portuguese" ;;
    ru|rus)        echo "Russian" ;;
    zh|zho|chi|cn) echo "Chinese" ;;
    ko|kor)        echo "Korean" ;;
    ar|ara)        echo "Arabic" ;;
    nl|dut|nld)    echo "Dutch" ;;
    sv|swe)        echo "Swedish" ;;
    no|nor)        echo "Norwegian" ;;
    da|dan)        echo "Danish" ;;
    fi|fin)        echo "Finnish" ;;
    pl|pol)        echo "Polish" ;;
    cs|ces|cze)    echo "Czech" ;;
    tr|tur)        echo "Turkish" ;;
    el|gre|ell)    echo "Greek" ;;
    he|heb)        echo "Hebrew" ;;
    hi|hin)        echo "Hindi" ;;
    *)             echo "$1" ;;
  esac
}

channel_name() {
  case "$1" in
    1)       echo "Mono" ;;
    2)       echo "Stereo" ;;
    3)       echo "3.0" ;;
    4)       echo "4.0" ;;
    5)       echo "5.0" ;;
    6)       echo "5.1" ;;
    7)       echo "6.1" ;;
    8)       echo "7.1" ;;
    0|"")    echo "" ;;
    *)       echo "${1}ch" ;;
  esac
}

# True (0) for lossless sources, which never get a bitrate cap.
is_lossless() {
  local codec="$1" profile="$2"
  case "$codec" in
    truehd|mlp|flac|alac|wavpack|tta|pcm_*) return 0 ;;
    dts) [[ "$profile" == *"DTS-HD MA"* ]] && return 0 ;;
  esac
  return 1
}

# Target E-AC-3 bitrate (kbps).
#
# Start from a fixed table by output channel count, then, for lossy
# sources with a known bitrate, cap it at 1.5x the source bitrate rounded
# up to the next standard step. Re-encoding lossy audio at a higher bitrate
# only makes the file bigger without improving quality. The cap can lower
# the table value but never raise it.
#
# Args: out_ch source_bits_per_second lossless(0/1)
eac3_bitrate_k() {
  local out_ch="$1" src_bps="$2" lossless="$3"
  local table src_k cap step chosen

  case "$out_ch" in
    1)     table=128 ;;
    2)     table=224 ;;
    3|4|5) table=384 ;;
    *)     table=640 ;;
  esac

  if (( lossless )) || [[ ! "$src_bps" =~ ^[0-9]+$ ]] || (( src_bps <= 0 )); then
    echo "$table"
    return
  fi

  src_k=$(( src_bps / 1000 ))
  cap=$(( src_k * 3 / 2 ))
  chosen=640
  for step in 96 128 160 192 224 256 320 384 448 512 576 640; do
    if (( step >= cap )); then
      chosen=$step
      break
    fi
  done

  (( chosen > table )) && chosen=$table
  echo "$chosen"
}

# Trim leading/trailing whitespace without xargs.
trim_whitespace() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

# Build the normalized title for a track.
#
# The existing title is first reduced to its "core" by stripping a leading
# language name and a trailing codec/channel suffix that this script may have
# added on a previous run. That makes the result idempotent: running the
# script twice produces the same title, and named commentary is preserved.
#
# Args: current_title language_display codec_display channel_display
build_title() {
  local title="$1" lang_disp="$2" codec_disp="$3" ch_disp="$4"
  local core pfx suffix_re named_re
  local prefix connector name result

  shopt -s nocasematch

  core="$(trim_whitespace "$title")"

  pfx="${lang_disp} "
  if [[ "${core,,}" == "${pfx,,}"* ]]; then
    core="$(trim_whitespace "${core:${#pfx}}")"
  fi

  suffix_re='^(.*[^[:space:]])[[:space:]]+Dolby[[:space:]]+Digital([[:space:]]+Plus)?([[:space:]]+Atmos)?([[:space:]]+(Mono|Stereo|[0-9]+\.[0-9]|[0-9]+ch))?$'
  if [[ "$core" =~ $suffix_re ]]; then
    core="${BASH_REMATCH[1]}"
  fi

  named_re='^((Director|Cast|Producer|Writer)[[:space:]]+)?Commentary[[:space:]]+(by|with|featuring)[[:space:]]+(.+)$'

  if [[ "$core" =~ $named_re ]]; then
    prefix="${BASH_REMATCH[2]}"
    connector="${BASH_REMATCH[3]}"
    name="${BASH_REMATCH[4]}"
    name="$(trim_whitespace "$name")"
    result="$lang_disp ${prefix:+$prefix }Commentary $connector $name $codec_disp $ch_disp"
  elif [[ "$core" =~ Commentary ]]; then
    result="$lang_disp Commentary $codec_disp $ch_disp"
  else
    result="$lang_disp $codec_disp $ch_disp"
  fi

  shopt -u nocasematch

  trim_whitespace "$result"
}

print_cmd() {
  printf '   '
  printf '%q ' "$@"
  printf '\n'
}

# Sanity-check the remuxed file before it replaces the original.
verify_output() {
  local src="$1" out="$2" s o sd od

  s=$("$FFPROBE_BIN" -v error -show_entries stream=index -of csv=p=0 "$src" | wc -l) || return 1
  o=$("$FFPROBE_BIN" -v error -show_entries stream=index -of csv=p=0 "$out" | wc -l) || return 1

  if (( s != o )); then
    echo "   stream count mismatch (source $s, output $o)"
    return 1
  fi

  sd=$("$FFPROBE_BIN" -v error -show_entries format=duration -of csv=p=0 "$src") || return 1
  od=$("$FFPROBE_BIN" -v error -show_entries format=duration -of csv=p=0 "$out") || return 1

  if ! awk -v a="$sd" -v b="$od" \
       'BEGIN { d = a - b; if (d < 0) d = -d; exit !(a != "" && b != "" && d <= 2) }'; then
    echo "   duration mismatch (source ${sd}s, output ${od}s)"
    return 1
  fi

  return 0
}

# Apply the collected (caller's) propedit_args to a file in place.
run_propedit() {
  local f="$1"

  if (( DRY_RUN )); then
    echo "🏷️  [dry-run] would run:"
    print_cmd "$MKVPROPEDIT_BIN" "$f" "${propedit_args[@]}"
    return 0
  fi

  echo "🏷️  Updating metadata in place..."
  "$MKVPROPEDIT_BIN" "$f" "${propedit_args[@]}"
  local rc=$?

  if (( rc == 0 )); then
    echo "✅ Metadata updated in place for \"$f\"."
    return 0
  elif (( rc == 1 )); then
    echo "⚠️ Metadata updated with warnings for \"$f\"."
    return 0
  else
    echo "❌ Error: Metadata update for \"$f\" failed."
    return 1
  fi
}

# Process a single MKV. Updates the global counters.
process_file() {
  local file="$1"
  local dir streams_json streams_tsv need avail
  local codec profile ch lang src_bps title lossless
  local language_display audio_codec_display channel_display new_title
  local out_ch downmix target_bitrate is_atmos
  local -a codec_args=() propedit_args=() track_edits=() ffmpeg_cmd=()
  local encoded_any=0 track_num=0

  echo "🎬 Processing \"$file\""

  streams_json=$("$FFPROBE_BIN" -v error -select_streams a \
                  -show_entries stream=index,codec_name,profile,channels,bit_rate:stream_tags \
                  -of json "$file") || {
    echo "❌ ffprobe failed on \"$file\""
    failed=$((failed + 1))
    return
  }

  # One line per audio stream, tab-separated. Every field except the last
  # (title) is guaranteed non-empty so `read` cannot collapse columns.
  streams_tsv=$(jq -r '
    .streams[]
    | [ (.codec_name // "unknown"),
        (.profile // "-"),
        (.channels // 2),
        (.tags.language // "und"),
        (.bit_rate // .tags.BPS // .tags["BPS-eng"] // "0"),
        ((.tags.title // "") | gsub("[\\t\\r\\n]"; " "))
      ]
    | map(tostring) | join("\t")
  ' <<<"$streams_json") || {
    echo "❌ Failed to parse ffprobe output for \"$file\""
    failed=$((failed + 1))
    return
  }

  if [[ -z "$streams_tsv" ]]; then
    echo "✅ Skipping \"$file\" — no audio tracks."
    skipped=$((skipped + 1))
    return
  fi

  while IFS=$'\t' read -r codec profile ch lang src_bps title; do
    lang="${lang,,}"
    [[ -z "$lang" ]] && lang="und"

    if [[ ! "$ch" =~ ^[0-9]+$ ]] || (( ch < 1 )); then
      ch=2
    fi

    # If language is undefined, use the override for the generated title
    # so title and language metadata stay consistent.
    if [[ "$lang" == "und" ]]; then
      language_display=$(language_name "$LANG_OVERRIDE")
    else
      language_display=$(language_name "$lang")
    fi

    is_atmos=0
    if [[ "$codec" == "eac3" && "$profile" == "Dolby Digital Plus + Dolby Atmos" ]]; then
      is_atmos=1
    fi

    if [[ "$codec" == "ac3" ]]; then
      audio_codec_display="Dolby Digital"
    elif (( is_atmos == 1 )); then
      audio_codec_display="Dolby Digital Plus Atmos"
    else
      audio_codec_display="Dolby Digital Plus"
    fi

    if [[ "$codec" == "ac3" || "$codec" == "eac3" ]]; then
      # ----------------------------------------------------------
      # Already AC-3 / E-AC-3: never re-encode. Metadata only,
      # edited in place.
      # ----------------------------------------------------------
      channel_display=$(channel_name "$ch")
      new_title=$(build_title "$title" "$language_display" "$audio_codec_display" "$channel_display")

      track_edits=()

      if [[ "$title" != "$new_title" ]]; then
        echo "🏷️  Track $track_num title -> \"$new_title\""
        (( is_atmos == 1 )) && echo "   🔊 Dolby Atmos detected"
        track_edits+=(--set "name=$new_title")
      fi

      if [[ "$lang" == "und" ]]; then
        echo "🌐 Track $track_num language is undefined — setting to $LANG_OVERRIDE."
        track_edits+=(--set "language=$LANG_OVERRIDE")
      fi

      if (( ${#track_edits[@]} > 0 )); then
        propedit_args+=(--edit "track:a$((track_num + 1))" "${track_edits[@]}")
      fi

      # Explicit per-track copy (avoids overlapping -c options in the remux).
      codec_args+=("-c:a:$track_num" "copy")
    else
      # ----------------------------------------------------------
      # Anything else: convert to E-AC-3, downmixing to 5.1 if needed.
      # ----------------------------------------------------------
      out_ch=$ch
      downmix=0
      if (( ch > 6 )); then
        out_ch=6
        downmix=1
      fi

      lossless=0
      is_lossless "$codec" "$profile" && lossless=1
      target_bitrate="$(eac3_bitrate_k "$out_ch" "$src_bps" "$lossless")k"
      channel_display=$(channel_name "$out_ch")
      new_title=$(build_title "$title" "$language_display" "$audio_codec_display" "$channel_display")

      if (( downmix )); then
        echo "🎧 Track $track_num: $codec, $ch channels — converting to E-AC3 5.1 (downmix) at ${target_bitrate}."
      else
        echo "🎧 Track $track_num: $codec, $ch channels — converting to E-AC3 at ${target_bitrate}."
      fi

      codec_args+=(
        "-c:a:$track_num" "eac3"
        "-b:a:$track_num" "$target_bitrate"
        "-metadata:s:a:$track_num" "title=$new_title"
      )

      if (( downmix )); then
        codec_args+=("-ac:a:$track_num" "6")
      fi

      if [[ "$lang" == "und" ]]; then
        echo "🌐 Track $track_num language is undefined — setting to $LANG_OVERRIDE."
        codec_args+=("-metadata:s:a:$track_num" "language=$LANG_OVERRIDE")
      fi

      encoded_any=1
    fi

    track_num=$((track_num + 1))
  done <<<"$streams_tsv"

  # --- Apply changes ---
  if (( encoded_any == 1 )); then
    # A remux is required. Video, subtitles, attachments, data and
    # untouched audio tracks are stream-copied; only the tracks
    # identified above are encoded.
    dir=$(dirname -- "$file")
    ffmpeg_cmd=(
      "$FFMPEG_BIN" -hide_banner -loglevel warning -stats -nostdin -y
      -i "$file"
      -map 0
      -c:v copy -c:s copy -c:t copy -c:d copy
      "${codec_args[@]}"
      -f matroska
    )

    if (( DRY_RUN )); then
      echo "🔄 [dry-run] would run:"
      print_cmd "${ffmpeg_cmd[@]}" "<temp file in $dir>"
      if (( ${#propedit_args[@]} > 0 )); then
        run_propedit "$file"
      fi
      converted=$((converted + 1))
      return
    fi

    # A remux needs roughly the size of the file in free space.
    need=$(stat -c %s -- "$file")
    avail=$(df --output=avail -B1 -- "$dir" | tail -n 1 | tr -d ' ')
    if [[ "$avail" =~ ^[0-9]+$ ]] && (( avail < need )); then
      echo "❌ Not enough free space in \"$dir\" for the remux (need ~$((need / 1048576)) MiB)."
      failed=$((failed + 1))
      return
    fi

    newfile=$(mktemp --suffix=.mkv "$dir/.eac3convert.XXXXXX") || {
      echo "❌ Could not create temp file in \"$dir\""
      newfile=""
      failed=$((failed + 1))
      return
    }

    echo "🔄 Converting audio and writing updated file..."

    if ! "${ffmpeg_cmd[@]}" "$newfile"; then
      echo "❌ Error: Processing \"$file\" failed. Keeping original."
      rm -f -- "$newfile"
      newfile=""
      failed=$((failed + 1))
      return
    fi

    if ! verify_output "$file" "$newfile"; then
      echo "❌ Error: Output verification failed for \"$file\". Keeping original."
      rm -f -- "$newfile"
      newfile=""
      failed=$((failed + 1))
      return
    fi

    mv -f -- "$newfile" "$file"
    newfile=""
    echo "✅ Converted and updated \"$file\"."

    # Metadata fixes for the untouched AC-3/E-AC-3 tracks. Audio track
    # order is preserved by the remux, so the a1, a2... selectors still match.
    if (( ${#propedit_args[@]} > 0 )); then
      if ! run_propedit "$file"; then
        failed=$((failed + 1))
        return
      fi
    fi

    converted=$((converted + 1))

  elif (( ${#propedit_args[@]} > 0 )); then
    # No conversion needed. mkvpropedit edits the Matroska headers in
    # place, so the file is not rebuilt.
    if run_propedit "$file"; then
      metadata_only=$((metadata_only + 1))
    else
      failed=$((failed + 1))
    fi

  else
    echo "✅ Skipping \"$file\" — nothing to change."
    skipped=$((skipped + 1))
  fi
}

# --- Walk the directory ---
# Files are read on fd 3 so nothing inside the loop can consume the list.
# Leftover temp files from an interrupted run are excluded.
while IFS= read -r -d '' -u 3 file; do
  process_file "$file"
done 3< <(find "$WORKINGDIRECTORY" -type f -iname "*.mkv" ! -name ".eac3convert.*" -print0 | sort -z)

# --- Final summary ---
prefix=""
(( DRY_RUN )) && prefix="[dry-run] "
echo "📊 ${prefix}Summary: Converted=$converted  Metadata-only=$metadata_only  Skipped=$skipped  Failed=$failed"

(( failed > 0 )) && exit 1
exit 0
