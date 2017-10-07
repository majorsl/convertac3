This script will attempt to locate all mkv files in a directory, recursively looking in
sub-directories as well. If found, it will use ffmpeg to determine if it does not have an
ac3 audio track and attempt to re-encode the file's existing audio track to ac3.