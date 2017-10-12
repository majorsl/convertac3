*What it does*

This script will attempt to locate all mkv files in a directory, recursively looking in
sub-directories as well. If found, it will use ffmpeg to determine if it has an aac
audio track and attempt to re-encode the file's existing audio track to ac3.

Geared towards OS X, but could easily be adapted for most *nix distros.

Until 1.0, a backup of the original file will be maintained while testing for bugs.

*Requirements*

1. Working Homebrew installed.
2. Homebrew: brew tap caskroom/cask
3. Homebrew: brew install ffmpeg
4. Homebrew: brew install terminal-notifier
5. Homebrew: brew install tag
6. Homebrew: brew install detox

*Current Limitations*

Files with multiple audio tracks are ignored for now. Options I'm considering 1) convert
them all if even one is acc or 2) ignoring them all of only one is ac3 as my research
indicates that will likely the track with the highest quality and the primary audio track.

