#!/bin/sh
# Version 0.3
# This script will attempt to convert mkv files without an existing ac3 track to one with.

#Directory to parse files in recursively.
WORKINGDIRECTORY="/Volumes/Drobo/Media Center/Unsorted-TV Shows/"
#Directory to move original file to (used for testing the script until version 1.0).
BACKUPDIRECTORY="/Volumes/Drobo/Media Center/Backups/"

cd $WORKINGDIRECTORY
IFS=$'\n'
find . -type f -name "*.mkv" -print0 | while IFS= read -r -d $'\0' file; do
echo $line
acodec=$(ffprobe -v error -select_streams a -show_entries stream=codec_name -of default=nokey=1:noprint_wrappers=1 $line)
echo $acodec
if [ "$acodec" != "ac3" ]; then
	newfile=${file%.*}
	ffmpeg -i "$file" -vcodec copy -scodec copy -acodec ac3 -ac 6 -ab 448k "$newfile"-AC3-.mkv
	mv $file $BACKUPDIRECTORY
fi
done