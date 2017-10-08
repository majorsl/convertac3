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
