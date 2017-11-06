#!/usr/bin/env bash
# Version 0.4 *See README.md for requirements*
#
# SET YOUR OPTIONS HERE -------------------------------------------------------------------------
# directory to parse files recursively.
WORKINGDIRECTORY="/Volumes/Drobo/Media Center/Unsorted-TV Shows/"

# path to terminal-notifier
TERMINALNOTIFIER="/usr/local/bin/"

# path to ffmpeg
FFMPEG="/usr/local/opt/ffmpeg/bin/"

# path to detox
DETOX="/usr/local/opt/detox/bin/"

#path to tag
TAG="/usr/local/bin/"

#path to trash (trash is a binary that trashes files using the OS X API)
TRASH="/usr/local/bin/"

# -----------------------------------------------------------------------------------------------
IFS=$'\n'

if [ ! -d "$WORKINGDIRECTORY" ]; then
  "$TERMINALNOTIFIER"terminal-notifier -title 'Convert AC3' -message "$WORKINGDIRECTORY doesn't exist, aborting." -activate -timeout 10
  exit
fi

"$DETOX"detox -r -v "$WORKINGDIRECTORY"
for file in $(find "$WORKINGDIRECTORY" -type f -name "*.mkv")
do
echo "$file"
acodec=$("$FFMPEG"ffprobe -v error -select_streams a -show_entries stream=codec_name -of default=nokey=1:noprint_wrappers=1 "$file")
echo "$acodec"
if [ "$acodec" = "aac" ]; then
	newfile=${file%.*}
	"$TERMINALNOTIFIER"terminal-notifier -title 'Convert AC3' -message "Processing $file" -activate -timeout 10
	"$FFMPEG"ffmpeg -i "$file" -vcodec copy -scodec copy -acodec ac3 -ac 6 -ab 448k "$newfile"-AC3-.mkv
	"$TAG"tag -a Blue "$newfile"-AC3-.mkv
	"$TRASH"trash -a "$file"
fi
done

unset IFS
