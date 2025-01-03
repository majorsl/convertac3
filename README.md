*What it does*

This script will locate all mkv files in a directory, recursively looking in sub-
directories as well. If found, it will use ffmpeg to determine if it doesn't have
an ac3 or eac3 audio track and attempt to re-encode the file's existing audio track to
ac3. Additionally, it will remove any non-English tracks. You could modify the script for
your preferred language.

The original file will be moved to the directory of your choosing, if something goes
wrong you can look there to reclaim the original.

*Requirements*

1. ffmpeg.
2. detox
