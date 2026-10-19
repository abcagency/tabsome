#!/bin/zsh
# Starts (or stops with "stop") the SpikeHelper instances used by spikes 7 and 9.
cd "${0:A:h}"
if [[ ${1:-} == stop ]]; then
  osascript -e 'tell application "System Events" to set p to every process whose bundle identifier is "com.tabsome.spikehelper"' -e 'repeat with x in p' -e 'do shell script "kill " & (unix id of x)' -e 'end repeat' 2>/dev/null || pkill -f SpikeHelper.app || true
  exit 0
fi
rm -f out/logs/helper-*.log(N)
open -n out/SpikeHelper.app --args main
open -n out/SpikeHelper.app --args sink
sleep 1.5
cat out/logs/helper-*.log 2>/dev/null
