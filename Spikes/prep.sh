#!/bin/zsh
# Opens one window in each test app used by the spikes.
cd "${0:A:h}"
mkdir -p out
echo "Tabsome spike scratch document. Safe to close without saving." > out/scratch.txt
open -a Terminal ~
open -a Finder ~
open -a Safari
open -a "Google Chrome" 2>/dev/null || true
open -a Firefox 2>/dev/null || true
open -a "Visual Studio Code" . 2>/dev/null || true
open -a Notes
open -a TextEdit out/scratch.txt
sleep 3
