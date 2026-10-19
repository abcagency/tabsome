# Phase 0 spikes

Throwaway code that answers the Phase 0 questions in `PLAN.md` §7. **Not product code**: it
breaks product rules on purpose (AX calls on the main thread and outside `AXWindow.swift`,
reading app content for measurements). Don't copy it into the app.

- `TabsomeSpikes/`: one menu-less host app (`LSUIElement`) with one file per spike, so
  Accessibility and Screen Recording are granted once, to `com.tabsome.spikes`.
- `SpikeHelper/`: a cooperative test app. In the `main` role it can hang its main thread on
  request and acts as a drag source; in the `sink` role it shows a drop target behind a decoy.
- `Findings/`: measured values (e.g. the draft `Metrics.swift`) carried into Phase 1.

```bash
./build.sh            # builds out/TabsomeSpikes.app + out/SpikeHelper.app, signs with Apple Development
./prep.sh             # opens a window in each test app
./helpers.sh          # starts SpikeHelper (main + sink); ./helpers.sh stop
./run.sh grant        # triggers the Accessibility / Screen Recording prompts once
./run.sh <spike> ...  # runs a spike; the log is printed and kept in out/logs/<spike>.log
```

| # | Spike | Command | Needs |
|---|---|---|---|
| 1 | AX move/resize matrix | `./run.sh ax-matrix` | AX |
| 2 | `_AXUIElementGetWindow` mapping | `./run.sh window-id` | AX |
| 3 | Overlay z-order | `./run.sh zorder [targetBID coverBID] [--hold 30 [--follow-mouse]]` | AX |
| 3b | Window position vs cursor during a drag | `./run.sh drag-follow` | AX |
| 4 | Title-bar drag detection | `./run.sh drag-detect --tap` / `drag-detect manual 90` | AX |
| 5 | Stacking concealment | `./run.sh stacking` / `stacking demo` (4 labelled variants) | AX |
| 6 | Proxy animation | `./run.sh proxy` / `proxy compare` (stretch vs cross-fade) | AX + Screen Recording |
| 7 | Hung-app isolation | `./helpers.sh && ./run.sh hung` | AX |
| 8 | macOS metrics | `./run.sh metrics` | (AX, Screen Recording for parts B, C) |
| 9 | Cross-app drag destination | `./helpers.sh && ./run.sh drag-dest` / `drag-dest manual 60` | AX (automated part) |

Automated spikes move the test apps' windows and synthesize mouse input: don't touch the
mouse while one runs. Every spike restores the windows' original frames at the end.
Logs never contain window titles (PLAN.md §6.1 S4).
