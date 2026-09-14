#!/usr/bin/env bash
# Version 2.8.0

FFMPEG="/usr/bin"
MKVPROPEDIT="/usr/bin/mkvpropedit"
LOCKFILE="/tmp/eac3_convert.lock"
LANG_OVERRIDE="eng"
MAX_EAC3_BITRATE=960  # maximum allowed kbps for E-AC3

# Acquire lock
exec 200>"$LOCKFILE"
flock -w 600 200 || {
  echo "⏳ Timeout waiting for lock (10 minutes). Another instance may be stuck. Exiting."
  exit 1
}

# Working directory
if [ -n "$1" ]; then
  WORKINGDIRECTORY="$1"
else
  echo "⚠️  Please call this script with a trailing directory part to process."
  exit 1
fi

if [ ! -d "$WORKINGDIRECTORY" ]; then
  echo "❌ $WORKINGDIRECTORY doesn't exist, aborting."
  exit 1
fi

# Verify required tools
if [ ! -x "$FFMPEG/ffprobe" ]; then
  echo "❌ ffprobe not found at $FFMPEG/ffprobe"
  exit 1
fi

if [ ! -x "$FFMPEG/ffmpeg" ]; then
  echo "❌ ffmpeg not found at $FFMPEG/ffmpeg"
  exit 1
fi

if [ ! -x "$MKVPROPEDIT" ]; then
  echo "❌ mkvpropedit not found at $MKVPROPEDIT"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq not found in PATH"
  exit 1
fi

# Counters
converted=0
skipped=0
failed=0
metadata_only=0

# Helper functions
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
    6)       echo "5.1" ;;
    8)       echo "7.1" ;;
    0|"")    echo "" ;;
    *)       echo "${1}ch" ;;
  esac
}

# Trim leading/trailing whitespace without xargs.
trim_whitespace() {
  local value="$1"

  # Remove leading whitespace
  value="${value#"${value%%[![:space:]]*}"}"

  # Remove trailing whitespace
  value="${value%"${value##*[![:space:]]}"}"

  printf '%s' "$value"
}

# Process MKVs using process substitution (avoids subshell)
while IFS= read -r -d '' file; do
  base_name="${file%.*}"
  echo "🎬 Processing \"$file\""

  streams_json=$("$FFMPEG/ffprobe" -v error -select_streams a \
                  -show_entries stream=index,codec_name,profile,channels:stream_tags=language,title,bit_rate \
                  -of json "$file") || {
    echo "❌ ffprobe failed on \"$file\""
    ((failed++))
    continue
  }

  # Parse via jq
  mapfile -t indexes   < <(echo "$streams_json" | jq -r '.streams[].index')
  mapfile -t codecs    < <(echo "$streams_json" | jq -r '.streams[].codec_name // ""')
  mapfile -t profiles  < <(echo "$streams_json" | jq -r '.streams[].profile // ""')
  mapfile -t channels  < <(echo "$streams_json" | jq -r '(.streams[].channels // 2) | tonumber? // 2')
  mapfile -t languages < <(echo "$streams_json" | jq -r '.streams[].tags.language // "und"')
  mapfile -t titles    < <(echo "$streams_json" | jq -r '.streams[].tags.title // ""')
  mapfile -t bitrates  < <(echo "$streams_json" | jq -r '(.streams[].bit_rate // 0) | tonumber? // 0')

  map_str=("-map" "0")
  codec_args=()
  propedit_args=()

  encoded_any=0
  metadata_changed=0

  for ((track_num=0; track_num<${#indexes[@]}; track_num++)); do
    codec="${codecs[$track_num]}"
    profile="${profiles[$track_num]}"
    ch="${channels[$track_num]}"
    lang="${languages[$track_num]}"
    title="${titles[$track_num]}"
    src_bitrate="${bitrates[$track_num]}"

    # Defensive numeric validation.
    # ffprobe can occasionally return null, empty, N/A, or other
    # non-numeric values for these fields.
    if [[ ! "$src_bitrate" =~ ^[0-9]+$ ]]; then
      src_bitrate=0
    fi

    if [[ ! "$ch" =~ ^[0-9]+$ ]] || (( ch < 1 )); then
      ch=2
    fi

    # Determine source bitrate in kbps.
    if (( src_bitrate > 0 )); then
      src_bitrate_k=$((src_bitrate / 1000))
    else
      src_bitrate_k=192  # default if not reported
    fi

    # Determine target bitrate dynamically.
    if (( ch == 1 )); then
      target_bitrate=$src_bitrate_k
    elif (( ch <= 6 )); then
      target_bitrate=$((src_bitrate_k * 3))  # 5.1
    elif (( ch == 8 )); then
      target_bitrate=$((src_bitrate_k * 4))  # 7.1
    else
      target_bitrate=$((src_bitrate_k * ch / 2))  # generic scaling
    fi

    (( target_bitrate > MAX_EAC3_BITRATE )) && target_bitrate=$MAX_EAC3_BITRATE
    target_bitrate="${target_bitrate}k"

    language_display=$(language_name "$lang")

    # If language is undefined, the script will fix it below.
    # Use the override for the generated title as well so the title
    # and language metadata stay consistent.
    if [[ "$lang" == "und" || -z "$lang" ]]; then
      language_display=$(language_name "$LANG_OVERRIDE")
    fi

    is_atmos=0

    if [[ "$codec" == "eac3" &&
          "$profile" == "Dolby Digital Plus + Dolby Atmos" ]]; then
      is_atmos=1
    fi

    # Set the correct codec display name for the existing track.
    #
    # AC-3 remains AC-3 and is metadata-edited in place.
    # E-AC-3 remains E-AC-3 and is metadata-edited in place.
    # Other codecs are converted to E-AC-3.
    if [[ "$codec" == "ac3" ]]; then
      audio_codec_display="Dolby Digital"
    elif (( is_atmos == 1 )); then
      audio_codec_display="Dolby Digital Plus Atmos"
    elif [[ "$codec" == "eac3" ]]; then
      audio_codec_display="Dolby Digital Plus"
    else
      audio_codec_display="Dolby Digital Plus"
    fi

    channel_display=$(channel_name "$ch")

    # Generate appropriate track title.
    #
    # Named commentary is preserved while adding the normalized
    # language, codec, and channel information.
    #
    # Examples:
    #   "Commentary by Joe Smith"
    #       -> "English Commentary by Joe Smith Dolby Digital 5.1"
    #
    #   "Commentary by Joe Smith and Jane Doe"
    #       -> "English Commentary by Joe Smith and Jane Doe Dolby Digital 5.1"
    #
    #   "Director Commentary by Joe Smith"
    #       -> "English Director Commentary by Joe Smith Dolby Digital 5.1"
    #
    # Generic commentary continues to be normalized as before.

    shopt -s nocasematch

    if [[ "$title" =~ ^[[:space:]]*((Director|Cast|Producer|Writer)[[:space:]]+)?Commentary[[:space:]]+(by|with|featuring)[[:space:]]+(.+)[[:space:]]*$ ]]; then
      commentary_prefix="${BASH_REMATCH[1]}"
      commentary_connector="${BASH_REMATCH[3]}"
      commentary_name="${BASH_REMATCH[4]}"

      # Remove leading/trailing whitespace without xargs.
      # This safely handles apostrophes and other shell-special characters.
      commentary_name="$(trim_whitespace "$commentary_name")"

      if [[ -n "$commentary_prefix" ]]; then
        commentary_prefix="$(trim_whitespace "$commentary_prefix")"

        new_title="$language_display $commentary_prefix Commentary $commentary_connector $commentary_name $audio_codec_display $channel_display"
      else
        new_title="$language_display Commentary $commentary_connector $commentary_name $audio_codec_display $channel_display"
      fi

    elif [[ "$title" =~ Commentary ]]; then
      new_title="$language_display Commentary $audio_codec_display $channel_display"

    else
      new_title="$language_display $audio_codec_display $channel_display"
    fi

    shopt -u nocasematch

    # Remove accidental leading/trailing whitespace without xargs.
    new_title="$(trim_whitespace "$new_title")"

    # Existing AC-3 or E-AC-3:
    #
    # These codecs are already acceptable, so NEVER remux the file just
    # to change metadata. Use mkvpropedit to modify the existing track
    # header in place.
    if [[ "$codec" == "ac3" || "$codec" == "eac3" ]]; then

      if [[ "$title" != "$new_title" ]]; then
        echo "🏷️  Track $track_num title -> \"$new_title\""

        if (( is_atmos == 1 )); then
          echo "   🔊 Dolby Atmos detected"
        fi

        propedit_args+=(
          --edit "track:a$((track_num + 1))"
          --set "name=$new_title"
        )

        metadata_changed=1
      fi

    # Non-AC-3 / Non-E-AC-3 -> convert to E-AC-3
    else
      echo "🎧 Track $track_num has $ch channels — converting $codec to E-AC3 at ${target_bitrate}."

      codec_args+=(
        "-c:a:$track_num" "eac3"
        "-b:a:$track_num" "$target_bitrate"
        "-metadata:s:a:$track_num" "title=$new_title"
      )

      # Explicitly set layout for 5.1 or 7.1.
      if (( ch == 8 )); then
        codec_args+=("-channel_layout:$track_num" "7.1")
      elif (( ch == 6 )); then
        codec_args+=("-channel_layout:$track_num" "5.1")
      fi

      encoded_any=1
    fi

    # Language fix
    if [[ "$lang" == "und" || -z "$lang" ]]; then
      echo "🌐 Track $track_num language is undefined — setting to $LANG_OVERRIDE."

      # Existing AC-3/E-AC-3 tracks can have their language changed
      # without a remux. Converted tracks get the language through
      # FFmpeg below.
      if [[ "$codec" == "ac3" || "$codec" == "eac3" ]]; then
        propedit_args+=(
          --edit "track:a$((track_num + 1))"
          --set "language=$LANG_OVERRIDE"
        )
      else
        codec_args+=(
          "-metadata:s:a:$track_num"
          "language=$LANG_OVERRIDE"
        )
      fi

      metadata_changed=1
    fi

  done

  # If any track actually needs conversion, FFmpeg must remux the file.
  #
  # Existing AC-3/E-AC-3 tracks are explicitly copied during this
  # remux. Only the tracks identified above are encoded.
  if (( encoded_any == 1 )); then
    newfile="${base_name}-tmp.mkv"

    echo "🔄 Converting audio and writing updated file..."

    "$FFMPEG/ffmpeg" \
      -nostdin \
      -i "$file" \
      "${map_str[@]}" \
      -c:v copy \
      -c:s copy \
      "${codec_args[@]}" \
      "$newfile"

    if [ $? -eq 0 ]; then
      mv -f "$newfile" "$file"
      echo "✅ Converted and updated \"$file\"."

      ((converted++))
    else
      echo "❌ Error: Processing \"$file\" failed. Keeping original."
      rm -f "$newfile"
      ((failed++))
    fi

  # No conversion required, but metadata needs changing.
  #
  # This is the important Syncthing optimization:
  # mkvpropedit modifies the Matroska headers in place instead of
  # forcing FFmpeg to rebuild the entire container.
  elif (( metadata_changed == 1 )); then
    echo "🏷️  Updating metadata in place..."

    "$MKVPROPEDIT" \
      "$file" \
      "${propedit_args[@]}"

    result=$?

    if [ "$result" -eq 0 ]; then
      echo "✅ Metadata updated in place for \"$file\"."
      ((metadata_only++))
    elif [ "$result" -eq 1 ]; then
      echo "⚠️ Metadata updated with warnings for \"$file\"."
      ((metadata_only++))
    else
      echo "❌ Error: Metadata update for \"$file\" failed."
      ((failed++))
    fi

  else
    echo "✅ Skipping \"$file\" — nothing to change."
    ((skipped++))
  fi

done < <(find "$WORKINGDIRECTORY" -type f -name "*.mkv" -print0)

# Print final summary
echo "📊 Summary: Converted=$converted  Metadata-only=$metadata_only  Skipped=$skipped  Failed=$failed"
