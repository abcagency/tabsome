<p align="center">
  <img src="Design/Icon/Tabsome-appicon-1024.png" alt="Tabsome app icon" width="128" height="128">
</p>

# Tabsome

A macOS menu bar app that turns any windows, from any apps, into browser-style tabs of one window.

**[Download Tabsome](https://abcagency.github.io/tabsome/)** (macOS 26 or later). The build plan
and every design decision are in [PLAN.md](PLAN.md).

## Build, run, test

Requires macOS 26+, Xcode 26+, and an Apple Development certificate in the login keychain
(see PLAN.md §3, "Prerequisites").

```bash
xcodebuild -project Tabsome.xcodeproj -scheme Tabsome -configuration Debug -derivedDataPath build build
```

```bash
open "build/Build/Products/Debug/Tabsome Dev.app"
```

```bash
xcodebuild -project Tabsome.xcodeproj -scheme Tabsome -configuration Debug -derivedDataPath build test
```

Or open `Tabsome.xcodeproj` in Xcode and press ⌘R / ⌘U.

Debug builds are **Tabsome Dev** (`com.tabsome.app.dev`): a separate app from the release Tabsome,
with its own Privacy & Security entries, settings, and logs, and with updates turned off. The first
launch walks through granting Accessibility (System Settings › Privacy & Security ›
Accessibility). Builds are signed with the same Apple Development identity, so the permission
survives rebuilds.

**Debug builds** add "Dump Window Registry (Debug)" to the menu. For a scripted check:

```bash
open "build/Build/Products/Debug/Tabsome Dev.app" --args -TabsomeDebugDumpAfter 3 -TabsomeDebugQuitAfterDump YES
```

The dump is written to `~/Library/Application Support/Tabsome Dev/Debug/registry-dump.txt`. It is
the only place window titles appear; logs (`~/Library/Logs/Tabsome Dev`) never contain them.

## Releasing

Release builds are signed with the company team's Developer ID and notarized (PLAN.md §7, Phase 7).
Write the notes in `docs/releases/<version>.md`, then:

```bash
scripts/release.sh 0.1.2
```

That archives, exports, notarizes, and staples the app and the DMG, and adds the release to the
signed update feed (`docs/appcast.xml`), without publishing anything. It needs the `tabsome`
notarytool profile and the Sparkle key in the login keychain. To publish (it asks first):

```bash
scripts/publish.sh 0.1.2
```

The website and the update feed are served by GitHub Pages from `docs/`.

## Layout

| Path | What's there |
|---|---|
| `Tabsome/App` | App entry, menu bar, onboarding, Settings, appearance, debug dump |
| `Tabsome/Core/AX` | The only code that talks to Accessibility (`AXWindow`, `AXApp`), the window registry, permissions |
| `Tabsome/Core/Support` | Logging and the app's own folders |
| `Tabsome/UI` | Motion tokens, metrics, system accessibility settings |
| `TabsomeTests` | Unit tests (Swift Testing) |
| `scripts/check-ax-usage.sh` | Build-phase check that AX APIs stay in `AXWindow`/`AXApp` (PLAN.md §6.1 S1) |
| `Spikes/` | Phase 0 throwaway spikes and their findings |
| `Design/Icon` | Icon sources |
