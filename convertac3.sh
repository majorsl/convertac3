#!/bin/sh
# Version 0.3.1 *REQUIREMENTS BELOW*
#
# 1. Working Homebrew installed.
# 2. Homebrew: brew tap caskroom/cask
# 3. Homebrew: brew install ffmpeg
# 4. Homebrew: brew install terminal-notifier

# This script will attempt to convert mkv files without an existing ac3 track to one with.

# SET YOUR OPTIONS HERE -------------------------------------------------------------------------
# directory to parse files recursively.
WORKINGDIRECTORY="/Volumes/Drobo/Media Center/Unsorted-TV Shows/"

# directory to move original file to (used for testing the script until version 1.0).
BACKUPDIRECTORY="/Volumes/Drobo/Media Center/Backups/"

# path to terminal-notifier
TERMINALNOTIFIER="/usr/local/bin/"

# -----------------------------------------------------------------------------------------------
IFS=$'\n'

find "$WORKINGDIRECTORY" -type f -name "*.mkv" -print0 | while IFS= read -r -d $'\0' file; do
echo $file
acodec=$(ffprobe -v error -select_streams a -show_entries stream=codec_name -of default=nokey=1:noprint_wrappers=1 $file)
echo $acodec
if [ "$acodec" != "ac3" ]; then
	newfile=${file%.*}
	"$TERMINALNOTIFIER"terminal-notifier -title 'Convert AC3' -message "Processing $file" -activate -timeout 10
	#ffmpeg -i "$file" -vcodec copy -scodec copy -acodec ac3 -ac 6 -ab 448k "$newfile"-AC3-.mkv
	echo $file $BACKUPDIRECTORY
fi
done

unset IFS
