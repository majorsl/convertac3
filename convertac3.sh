#!/usr/bin/env bash
# Version 1.7.0 - Adds 10-minute wait on lock

# SET YOUR OPTIONS HERE -------------------------------------------------------------------------
FFMPEG="/usr/bin/"
DETOX="/usr/bin/"
LOCKFILE="/tmp/ac3_convert.lock"
# -----------------------------------------------------------------------------------------------
IFS=$'\n'

# Acquire lock or wait up to 10 minutes
exec 200>"$LOCKFILE"
flock -w 600 200 || {
  echo "Timeout waiting for lock (10 minutes). Another instance may be stuck. Exiting."
  exit 1
}

# Validate directory argument
if [ -n "$1" ]; then
  WORKINGDIRECTORY="$1"
else
  echo "Please call the script with a trailing directory part to process."
  exit 1
fi

if [ ! -d "$WORKINGDIRECTORY" ]; then
  echo "$WORKINGDIRECTORY doesn't exist, aborting."
  exit 1
fi

# Detoxify filenames
find "$WORKINGDIRECTORY" -mindepth 1 -exec "${DETOX}detox" -r -v {} \;

# Process .mkv files
find "$WORKINGDIRECTORY" -type f -name "*.mkv" | while read -r file; do
  base_name="${file%.*}"
  echo "Processing $file"

  # Get audio stream info
  file_info=$("${FFMPEG}ffprobe" -v error -select_streams a \
              -show_entries stream=codec_name,channels \
              -of default=nokey=1:noprint_wrappers=1 "$file")

  # Check for subtitle streams
  subtitle_info=$("${FFMPEG}ffprobe" -v error -select_streams s \
                  -show_entries stream=index -of default=nokey=1:noprint_wrappers=1 "$file")

  # Map video stream
  map_str=("-map" "0:v")
  [ -n "$subtitle_info" ] && map_str+=("-map" "0:s")

  has_ac3=0
  track_num=0

  while read -r line; do
    acodec=$(echo "$line" | cut -d' ' -f1)
    achannels=$(echo "$line" | cut -d' ' -f2)

    [ "$achannels" -gt 6 ] && achannels=6
    map_str+=("-map" "0:a:$track_num?")

    [[ "$acodec" == "ac3" || "$acodec" == "eac3" ]] && has_ac3=1
    ((track_num++))
  done <<< "$file_info"

  if [ "$has_ac3" -eq 0 ]; then
    newfile="${base_name}-AC3-.mkv"
    echo "Converting $file to AC3..."

    "${FFMPEG}ffmpeg" -i "$file" "${map_str[@]}" \
      -vcodec copy -scodec copy -acodec ac3 -ac "$achannels" -ab 448k "$newfile"

    if [ $? -eq 0 ]; then
      rm "$file"
      mv "$newfile" "$file"
      echo "Successfully converted and replaced the original file."
    else
      echo "Error: Conversion of $file failed. Skipping."
      rm -f "$newfile"
    fi
  else
    echo "Skipping $file — already contains AC3/EAC3 audio."
  fi
done

unset IFS
