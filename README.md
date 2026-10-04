*What it does*

This script will locate all mkv files in a directory, recursively looking in sub-
directories as well. It will use ffmpeg to determine if a file has audio tracks that aren't
ac3 or eac3 and attempt to re-encode the audio track(s) to eac3.

NOTE: due to the current limitations of ffmpeg, eac3 conversion is limited to 5.1 audio and
formats with more channels will be downmixed. Existing AC3/EAC3 channels are untouched
so if they were professionally encoded with more channels only their metadata information
is updated.

The original file will be removed after the new file is successfully processed only if a
re-encode took place, otherwise the metadata will be added or updated in place.

Call the script with a trailing directory path and it will process the items in that location.

*Requires ffmpeg
