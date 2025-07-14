*What it does*

This script will locate all mkv files in a directory, recursively looking in sub-
directories as well. It will use ffmpeg to determine if a file has an audio track that isn't
an ac3 or eac3 audio track and attempt to re-encode the file's existing audio track(s) to
ac3. If an existing ac3 or eac3 track is found, it will remain untouched.

The original file will be removed after the new file is successfully processed.

Call the script with a trailing directory path and it will process the items in that location.

*Requiremes ffmpeg
