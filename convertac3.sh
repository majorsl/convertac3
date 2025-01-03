#!/usr/bin/env bash
# Version 1.3 *See README.md for requirements*
#
# SET YOUR OPTIONS HERE -------------------------------------------------------------------------
# Default directory to parse files recursively.
DEFAULT_WORKINGDIRECTORY="/media/majorsl/e9ef2c72-9134-4418-86dc-10742b12d0ed/Downloads/Sonarr/"
# path to ffmpeg
FFMPEG="/usr/bin/"
# path to detox
DETOX="/usr/bin/"
# path to trash converted files
TRASH="/home/majorsl/.local/share/Trash/"
# -----------------------------------------------------------------------------------------------
IFS=$'\n'

# Check if a directory is passed as an argument
if [ -n "$1" ]; then
  WORKINGDIRECTORY="$1"
else
  WORKINGDIRECTORY="$DEFAULT_WORKINGDIRECTORY"
fi

if [ ! -d "$WORKINGDIRECTORY" ]; then
  echo "$WORKINGDIRECTORY doesn't exist, aborting."
  exit
fi

"$DETOX"detox -r -v "$WORKINGDIRECTORY"
for file in $(find "$WORKINGDIRECTORY" -type f -name "*.mkv")
do
  echo "$file"
  acodec=$("$FFMPEG"ffprobe -v error -select_streams a -show_entries stream=codec_name -of default=nokey=1:noprint_wrappers=1 "$file")
  echo "$acodec"
  
  # Check for English audio tracks
  eng_tracks=$("$FFMPEG"ffprobe -v error -select_streams a -show_entries stream_tags=language -of csv=p=0 "$file" | grep -n "eng" | cut -d: -f1)
  
  if [[ -z "$eng_tracks" ]]; then
    echo "No English audio tracks found in $file, skipping."
    continue
  fi
  
  if [[ "$acodec" != *"ac3" ]]; then
    achannels=$("$FFMPEG"ffprobe -v error -select_streams a -show_entries stream=channels -of default=nokey=1:noprint_wrappers=1 "$file")
    if [ "$achannels" -gt "6" ]; then
      achannels="6"
    fi
    echo "$achannels"
    newfile=${file%.*}
    echo "Processing $file" -activate -timeout 10
    
    # Create a map string for English audio tracks
    map_str="-map 0:v -map 0:s"
    for track in $eng_tracks; do
      map_str="$map_str -map 0:a:$((track-1))"
    done
    
    "$FFMPEG"ffmpeg -i "$file" $map_str -vcodec copy -scodec copy -acodec ac3 -ac "$achannels" -ab 448k "${newfile}-AC3-.mkv"
    mv "$file" $TRASH
  fi
done

unset IFS