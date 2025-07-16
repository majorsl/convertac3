#!/usr/bin/env bash
# Version 1.9.2 - Added -nostdin to suppress ffmpeg runtime prompts

FFMPEG="/usr/bin/"
LOCKFILE="/tmp/ac3_convert.lock"
IFS=$'\n'

# Lock to avoid concurrent runs
exec 200>"$LOCKFILE"
flock -w 600 200 || {
  echo "⏳ Timeout waiting for lock (10 minutes). Another instance may be stuck. Exiting."
  exit 1
}

# Validate input path
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

# Find and process .mkv files
find "$WORKINGDIRECTORY" -type f -name "*.mkv" | while read -r file; do
  base_name="${file%.*}"
  echo "🎬 Processing \"$file\""

  # Gather audio stream info
  file_info=$("${FFMPEG}ffprobe" -v error -select_streams a \
              -show_entries stream=codec_name,channels \
              -of default=nokey=1:noprint_wrappers=1 "$file")
  readarray -t lines <<< "$file_info"

  map_str=("-map" "0")  # Include all streams
  codec_args=()
  has_non_ac3=0
  track_num=0

  for ((i = 0; i < ${#lines[@]}; i+=2)); do
    acodec="${lines[i]}"
    channels="${lines[i+1]}"

    if ! [[ "$channels" =~ ^[0-9]+$ ]]; then
      echo "⚠️  Unable to read channel count for track $track_num, defaulting to 2."
      channels=2
    fi

    if [[ "$acodec" == "ac3" || "$acodec" == "eac3" ]]; then
      codec_args+=("-c:a:$track_num" "copy")
    else
      if [ "$channels" -gt 6 ]; then
        echo "🎧 Track $track_num has $channels channels — converting to EAC3."
        codec_args+=("-c:a:$track_num" "eac3" "-ac:$track_num" "$channels" "-b:a:$track_num" "768k")
      else
        echo "🎧 Track $track_num has $channels channels — converting to AC3."
        codec_args+=("-c:a:$track_num" "ac3" "-ac:$track_num" "$channels" "-b:a:$track_num" "448k")
      fi
      has_non_ac3=1
    fi

    ((track_num++))
  done

  if [ "$has_non_ac3" -eq 1 ]; then
    newfile="${base_name}-AC3.mkv"
    echo "🔄 Converting non-AC3 audio tracks..."

    "${FFMPEG}ffmpeg" -nostdin -i "$file" "${map_str[@]}" \
      -c:v copy -c:s copy "${codec_args[@]}" "$newfile"

    if [ $? -eq 0 ]; then
      rm "$file"
      mv "$newfile" "$file"
      echo "✅ Successfully converted and replaced \"$file\"."
    else
      echo "❌ Error: Conversion of \"$file\" failed. Skipping."
      rm -f "$newfile"
    fi
  else
    echo "✅ Skipping \"$file\" — all audio streams are already AC3/EAC3."
  fi
done

unset IFS
