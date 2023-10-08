*What it does*

This script will attempt to locate all mkv/m4v files in a directory, recursively looking
in sub-directories as well. If found, it will use ffmpeg to determine if it doesn't have
and ac3 or eac3 audio track and attempt to re-encode the file's existing audio track to
ac3. The file will also be converted to mkv if it was an m4v.

Converted files are tagged with a blue Finder label so they can be found easily.

Geared towards OS X, but could easily be adapted for most *nix distros.

The original file will be moved to the directory of your choosing, if something goes
wrong you can look there to reclaim the original.

*Requirements*

1. Working Homebrew installed.
2. Homebrew: brew tap caskroom/cask
3. Homebrew: brew install ffmpeg
4. Homebrew: brew install terminal-notifier
5. Homebrew: brew install tag
6. Homebrew: brew install detox

*Current Limitations*

Files with multiple audio tracks are ignored for now. Options I'm considering 1) convert
all if even one is acc or 2) ignoring them all if only one is an ac3 as my research
indicates it will likely the track with the highest quality and the primary audio track.

