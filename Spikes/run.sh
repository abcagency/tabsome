#!/bin/zsh
# Runs one spike inside TabsomeSpikes.app, launched through LaunchServices so macOS
# attributes Accessibility / Screen Recording to TabsomeSpikes itself (not the parent shell).
#   ./run.sh <spike> [args...]      e.g. ./run.sh zorder --hold 30
# Spikes: trust grant ax-matrix window-id zorder drag-detect stacking proxy hung metrics drag-dest
set -euo pipefail
cd "${0:A:h}"
spike=${1:-trust}; shift || true
log=out/logs/$spike.log
open -n -W out/TabsomeSpikes.app --args $spike "$@"
cat $log
