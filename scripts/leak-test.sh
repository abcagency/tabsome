#!/bin/zsh
# The Phase 5d leak test (PLAN.md §6.2 P6): launches and quits SpikeHelper N times (default 100),
# hidden and without taking focus, while Tabsome runs. Each launch gives Tabsome a new app to
# track (an AX thread, an observer, window handles); each quit must release all of it. Compares
# Tabsome's threads, open files, memory footprint, and leaks before and after.
#   scripts/leak-test.sh [cycles]        needs Tabsome running and Spikes/build.sh built
set -euo pipefail
cd "${0:A:h}/.."
N=${1:-100}
HELPER=Spikes/out/SpikeHelper.app
pid=$(pgrep -x "Tabsome Dev" || pgrep -x Tabsome) || { echo "Tabsome isn't running"; exit 1; }
[[ -d $HELPER ]] || { echo "build the helper first: Spikes/build.sh"; exit 1; }

measure() {
  local threads=$(ps -M -p $pid | tail -n +2 | wc -l | tr -d ' ')
  local files=$(lsof -p $pid 2>/dev/null | wc -l | tr -d ' ')
  local fp=$(footprint $pid 2>/dev/null | sed -n 's/.*Footprint: \([0-9.]* [KMG]*B\).*/\1/p' | head -1)
  echo "$1: threads=$threads files=$files footprint=$fp"
}

cycle() {
  open -g -j -n $HELPER --args quiet
  local hp=""
  for _ in {1..60}; do
    hp=$(pgrep -n -f "SpikeHelper.app/Contents/MacOS/SpikeHelper quiet" || true)
    [[ -n $hp ]] && break
    sleep 0.05
  done
  [[ -n $hp ]] || { echo "helper didn't start"; return 1; }
  sleep 0.6 # Tabsome notices the launch and reads the helper's window
  [[ ${1:-} == sample ]] && measure "  while a helper runs"
  kill $hp
  for _ in {1..60}; do kill -0 $hp 2>/dev/null || break; sleep 0.05; done
}

echo "warming up (3 cycles)"
for _ in 1 2 3; do cycle; done
sleep 2
measure "before"
start=$SECONDS
for i in $(seq 1 $N); do
  if (( i == N / 2 )); then cycle sample; else cycle; fi
  (( i % 25 == 0 )) && echo "  $i/$N"
done
echo "$N cycles in $((SECONDS - start)) s; settling"
sleep 5
measure "after"
leaks $pid 2>&1 | grep -E "^Process [0-9]+: [0-9]+ leaks" || true
