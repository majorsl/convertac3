# Information

These scripts will determine if a file has audio tracks that aren't ac3 or eac3 and attempt to re-encode the audio track(s) to eac3.

*NOTE: due to the current limitations of ffmpeg, eac3 conversion is limited to 5.1 audio and formats with more channels will be downmixed.*

Lossy sources are not inflated: the E-AC-3 bitrate is capped at 1.5x the source bitrate (lossless sources use a fixed table).

Track titles are normalized and undefined languages are fixed.

The original file will be removed after the new file is successfully processed only if a re-encode took place, otherwise the metadata will be added or updated in place.

# convertac3

This script will locate all mkv files in a directory, recursively looking in sub-directories as well. Call the script with a trailing directory path and it will process the items in that location.

# convertac3single

This script will convert a single file. Call the script with a trailing directory path and it will process the items in that location. This one is useful to call with a tool like Tdarr for use in a flow. Your Tdarr OS will still require the below dependencies.  If Tdarr ever includes the below items available to flows, I'd probably do a proper plug-in for it.

*Requirements*

1. ffmpeg
2. mkvpropedit
3. ffprobe
