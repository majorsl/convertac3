*What it does*

This script will locate all mkv files in a directory, recursively looking in sub-
directories as well. If found, it will use ffmpeg to determine if it doesn't have
an ac3 or eac3 audio track and attempt to re-encode the file's existing audio track to
ac3.

The original file will be removed after the new files is successfully processed.

*Requirements*

1. ffmpeg
2. detox
