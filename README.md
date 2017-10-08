This script will attempt to locate all mkv files in a directory, recursively looking in
sub-directories as well. If found, it will use ffmpeg to determine if it has an aac
audio track and attempt to re-encode the file's existing audio track to ac3.

Until 1.0, a backup of the original file will be maintained while testing for bugs.