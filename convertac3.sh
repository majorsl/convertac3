#!/usr/bin/env bash
# Version 1.8.1 - Emoji output, per-stream AC3 conversion, channel preservation

# SET YOUR OPTIONS HERE -------------------------------------------------------------------------
FFMPEG="/usr/bin/"
DETOX="/usr/bin/"
LOCKFILE="/tmp/ac3_convert.lock"
# -----------------------------------------------------------------------------------------------
IFS=$'\n'

# Acquire lock or wait up to 10 minutes
exec 200>"$LOCKFILE"
flock -w 600 200 || {
  echo "⏳ Timeout waiting for lock (10 minutes). Another instance may be stuck. Exiting."
  exit 1
}

# Validate directory argument
if [ -n "$1" ]; then
  WORKINGDIRECTORY="$1"
else
  echo "⚠️  Please call the script with a trailing directory part to process."
  exit 1
fi

if [ ! -d "$WORKINGDIRECTORY" ]; then
  echo "❌ $WORKINGDIRECTORY doesn't exist, aborting."
  exit 1
fi

# Detoxify filenames
find "$WORKINGDIRECTORY" -mindepth 1 -exec "${DETOX}detox" -r -v {} \;
echo -e "🧼 Filenames sanitized with detox."

# Process .mkv files
find "$WORKINGDIRECTORY" -type f -name "*.mkv" | while read -r file; do
  base_name="${file%.*}"
  echo "🎞️  Processing $file"

  # Get audio stream info: alternating codec_name and channels
  file_info=$("${FFMPEG}ffprobe" -v error -select_streams a \
              -show_entries stream=codec_name,channels \
              -of default=nokey=1:noprint_wrappers=1 "$file")

  # Check for subtitle streams
  subtitle_info=$("${FFMPEG}ffprobe" -v error -select_streams s \
                  -show_entries stream=index -of default=nokey=1:noprint_wrappers=1 "$file")

  # Map video stream
  map_str=("-map" "0:v")
  [ -n "$subtitle_info" ] && map_str+=("-map" "0:s")

  # Prepare to process audio streams
  readarray -t lines <<< "$file_info"

  codec_args=()
  has_non_ac3=0
  track_num=0

  for ((i = 0; i < ${#lines[@]}; i+=2)); do
    acodec="${lines[i]}"
    channels="${lines[i+1]}"

    # Validate channel number
    if ! [[ "$channels" =~ ^[0-9]+$ ]]; then
      echo "⚠️  Unable to read channel count for track $track_num, defaulting to 2 channels."
      channels=2
    fi

    [ "$channels" -gt 6 ] && channels=6

    # Always map the audio track
    map_str+=("-map" "0:a:$track_num?")

    if [[ "$acodec" == "ac3" || "$acodec" == "eac3" ]]; then
      codec_args+=("-c:a:$track_num" "copy")
    else
      codec_args+=("-c:a:$track_num" "ac3" "-ac:$track_num" "$channels" "-b:a:$track_num" "448k")
      has_non_ac3=1
    fi

    ((track_num++))
  done

  if [ "$has_non_ac3" -eq 1 ]; then
    newfile="${base_name}-AC3-.mkv"
    echo "🎧 Converting non-AC3 audio tracks to AC3..."

    "${FFMPEG}ffmpeg" -i "$file" "${map_str[@]}" \
      -c:v copy -c:s copy "${codec_args[@]}" "$newfile"

    if [ $? -eq 0 ]; then
      rm "$file"
      mv "$newfile" "$file"
      echo -e "✅ Successfully converted and replaced the original file."
    else
      echo -e "❌ Error: Conversion of $file failed. Skipping."
      rm -f "$newfile"
    fi
  else
    echo -e "✅ Skipping $file — all audio streams are already AC3/EAC3."
  fi
done

unset IFS
