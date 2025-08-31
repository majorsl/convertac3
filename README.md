*What it does*

This script will locate all mkv files in a directory, recursively looking in sub-
directories as well. It will use ffmpeg to determine if a file has audio tracks that aren't
ac3 or eac3 and attempt to re-encode the audio track(s) to eac3.

If an existing ac3 or eac3 track is found, it will remain untouched. There is no benefit to
converting an existing ac3 track to eac3.

The original file will be removed after the new file is successfully processed.

Call the script with a trailing directory path and it will process the items in that location.

*Requiremes ffmpeg
