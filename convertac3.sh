#!/usr/bin/env bash
# Version 1.6.5 *See README.md for requirements*

# SET YOUR OPTIONS HERE -------------------------------------------------------------------------
# Path to ffmpeg
FFMPEG="/usr/bin/"
# Path to detox
DETOX="/usr/bin/"
# -----------------------------------------------------------------------------------------------
IFS=$'\n'

# Check if a directory is passed as an argument
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
find "$WORKINGDIRECTORY" -mindepth 1 -exec "$DETOX"detox -r -v {} \;

# Process .mkv files
for file in $(find "$WORKINGDIRECTORY" -type f -name "*.mkv")
do
  # Extract base name without extension to compare
  base_name="${file%.*}"
  # Construct the temporary file and original file paths
  temp_file="${base_name}.-AC3-.${file##*.}"  # e.g., file.tmp.mkv
  original_file="${base_name}.${file##*.}"  # e.g., file.mkv or file.mp4
  # Skip both the temporary file and the original file if the temporary file exists
  if [[ -f "$temp_file" ]]; then
    echo "Skipping $file as the temporary file exists (original file being processed)."
    continue
  fi

  echo "Processing $file"
  
  # Get all audio and subtitle stream info
  file_info=$("$FFMPEG"ffprobe -v error -select_streams a -show_entries stream=codec_name,channels -of default=nokey=1:noprint_wrappers=1 "$file")
  
  # Check if there are subtitle streams
  subtitle_info=$("$FFMPEG"ffprobe -v error -select_streams s -show_entries stream=index -of default=nokey=1:noprint_wrappers=1 "$file")
  
  # Start constructing the map_str for video streams
  map_str=("-map" "0:v")  # Always map video stream

  # Add subtitle streams only if they exist
  if [ -n "$subtitle_info" ]; then
    map_str+=("-map" "0:s")  # Map subtitle stream if it exists
  fi

  # Initialize a flag for whether we found any AC3 streams
  has_ac3=0
  
# Loop through each audio track and add it to map_str
track_num=0
while read -r line; do
  acodec=$(echo "$line" | cut -d' ' -f1)
  achannels=$(echo "$line" | cut -d' ' -f2)

  # Check if the codec is AC3 or EAC3
  if [[ "$acodec" == "ac3" || "$acodec" == "eac3" ]]; then
    has_ac3=1
  fi

  # Only check achannels if it's numeric
  if [[ "$achannels" =~ ^[0-9]+$ ]]; then
    # Add the current audio track to the map, ensuring it exists
    map_str+=("-map" "0:a:$track_num?")  # Add '?' to ignore missing streams

    # Limit channels to 6 if more than 6
    if [ "$achannels" -gt "6" ]; then
      achannels="6"
    fi
  fi

  # Increment track number for the next loop
  ((track_num++))
done <<< "$file_info"

  # Only convert if no AC3 streams are found
  if [ "$has_ac3" -eq 0 ]; then
    # Prepare new file name for output with -AC3- suffix
    newfile="${base_name}-AC3-.mkv"
    echo "Converting $file to AC3..."

    # Perform the conversion with ffmpeg
    "$FFMPEG"ffmpeg -nostdin -i "$file" "${map_str[@]}" -vcodec copy -scodec copy -acodec ac3 -ac "$achannels" -ab 448k "$newfile"

    # Move the original file to trash
    rm "$file"

  else
    echo "Skipping $file as it already contains AC3/EAC3 audio."
  fi
done

unset IFS
