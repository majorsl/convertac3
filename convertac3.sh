#!/usr/bin/env bash
# Version 1.6.2 *See README.md for requirements*

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
  echo "Processing $file"
  
  # Get all audio stream info (codec_name and channels)
  file_info=$("$FFMPEG"ffprobe -v error -select_streams a -show_entries stream=codec_name,channels -of default=nokey=1:noprint_wrappers=1 "$file")
  
  # Start constructing the map_str for video and subtitle streams
  map_str=()
  map_str+=("-map" "0:v" "-map" "0:s")  # Always map video and subtitle streams

  # Initialize a flag for whether we found any AC3 streams
  has_ac3=0
  
  # Loop through each audio track and add it to map_str
  track_num=0
  while read -r line; do
    acodec=$(echo "$line" | cut -d' ' -f1)
    achannels=$(echo "$line" | cut -d' ' -f2)
    
    # Add the current audio track to the map, ensuring it exists
    map_str+=("-map" "0:a:$track_num?")  # Add '?' to ignore missing streams

    # Limit channels to 6 if more than 6
    if [ "$achannels" -gt "6" ]; then
      achannels="6"
    fi
    
    # Check if the codec is AC3
    if [[ "$acodec" == "ac3" || "$acodec" == "eac3" ]]; then
      has_ac3=1
    fi

    # Increment track number for the next loop
    ((track_num++))

  done <<< "$file_info"

  # Only convert if no AC3 streams are found
  if [ "$has_ac3" -eq 0 ]; then
    # Prepare new file name for output
    newfile="${file%.*}"
    echo "Converting $file to AC3..."

    # Perform the conversion with ffmpeg
    "$FFMPEG"ffmpeg -i "$file" "${map_str[@]}" -vcodec copy -scodec copy -acodec ac3 -ac "$achannels" -ab 448k "$newfile"-AC3-.mkv

    # Move the original file to trash
    rm "$file"

    # Log the processing
    echo "$(date): Processed $file" >> "$LOG_FILE"
  else
    echo "Skipping $file as it already contains AC3/EAC3 audio."
  fi
done

unset IFS
