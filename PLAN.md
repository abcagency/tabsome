# Tabsome — Build Plan

> Working name. Bundle ID placeholder: `com.tabsome.app`.

> **Terminology.** In this plan, a **"group"** just means **one tabbed window**: the set of app windows that have been tabbed together. Code names like `TabGroup` and `GroupManager` use the word the same way.
> - **Not a feature:** browser-style **Tab Groups** (named, colored, or collapsible sets of tabs inside a window) are **out of scope**. Tabsome only puts apps' windows together as tabs.
> - **Not in the UI:** Tabsome never shows users the word "group". On screen it's always "tabs" and "window", e.g. "Close 4 tabs?" and "Move Tab to New Window".

## 1. What we're building

A macOS **menu bar app** that lets you group any windows (from any apps) into one tabbed window:

1. Drag a window by its title bar over the **middle** of another window.
2. **Pause** for a moment, and the target highlights with a "drop to tab" preview.
3. **Let go**, and the two windows become tabs of one window, with a tab strip attached to the window.
4. Keep going: a group can hold **any number of tabs**, from any mix of apps. Dropping a window straight onto an existing tab strip adds it right away, at the spot you drop it.

**Tab position** (Settings › Tabs, applies to all groups live):
- **Top** (default): a horizontal strip above the window. Each tab shows the app icon and the **full app name** (e.g. "Safari", "Visual Studio Code").
- **Left**: a narrow vertical strip down the window's left side. Each tab shows **only the app icon**. Hovering a tab shows the app name and window title as a tooltip.

### Design principle: it works like browser tabs
Everyone already knows how tabs work in Safari and Chrome. Tabsome should need **no instructions beyond "drag a window onto another one."** After that, every behavior should be exactly what a browser user expects. If we're ever unsure how something should behave, the answer is **"what does Safari or Chrome do?"** The one gesture browsers don't have (merging two plain windows) is the drag-and-pause from steps 1–3. Everything after that copies browsers:

| Browser behavior | Tabsome equivalent |
|---|---|
| Click a tab to switch | Same |
| × on a tab closes it | Same. It closes that window, and the app shows its own "Save changes?" prompt if needed |
| Closing a tab activates the **tab to its right** (or left, if it was last) | Same |
| Close buttons stay put under the cursor while you close several tabs in a row | Same: tab widths are frozen while the pointer stays in the strip, then reflow when it leaves (Chrome's behavior) |
| Drag a tab sideways to reorder | Same |
| Drag a tab out of the strip to get its own window | Same |
| Drag a tab onto **another window's tab strip** to move it there, at that exact position | Same: an insertion marker shows where it will land. **No pause needed** on a tab strip, just like browsers |
| Drag a whole window by its title bar | Moves the window with all of its tabs |
| Middle-click a tab closes it | Same |
| Right-click menu: Close Tab, Close Other Tabs, Close Tabs to the Right, Move Tab to New Window | Same, plus Rename Tab |
| ⌃Tab / ⌃⇧Tab, ⌘1–⌘9 (⌘9 = last tab), ⌘W | Same layout, with ⌃⌥ in place of ⌘/⌃ so the shortcuts never collide with the apps' own (§5.7) |
| Hover a tab to see its full title | Same, as a tooltip |
| Hover a background tab to see a preview (Safari) | Same (§5.14) |
| Drag a file over a tab and it switches to that tab (Safari, Finder spring-loading) | Same (§5.14) |
| A favicon shows unread counts | The app's Dock badge shows on its tab (§5.14) |
| Safari/Chrome put the red, yellow, and green window buttons **in the tab bar, left of the tabs**, and they act on the whole window | Same in Top mode: **close all tabs, minimize the group to the Dock, and fill the screen**. Hovering green opens the macOS-style **Move & Resize** flyout for the group (§5.11) |
| Active tab looks attached to the page; background tabs look recessed | Same: the active tab blends into the window below it, and the others are dimmer |
| "+" opens a new tab | The **"+" button** opens a menu of your other open windows; pick one to add it as a tab. It's the click alternative to dragging, and it makes the feature discoverable |
| Double-click empty space in the tab bar | Does what double-clicking a title bar does on this Mac (zoom or minimize, per System Settings) |

The one deliberate difference: **renaming** (double-click a tab). Browsers don't have it, but it's the same gesture as renaming in Finder.

Inside a group, then:
- **Window buttons** (Top mode): the usual red, yellow, and green buttons sit at the left end of the tab strip and act on the **whole group**. Red closes all tabs, yellow minimizes the group to the Dock, and green fills the screen. Hover green for the Move & Resize flyout (§5.11).
- **Click a tab** to switch to that window. **×** or middle-click closes it.
- **Rename a tab inline**: double-click it and type. By default a tab is named after its app; a custom name replaces that until you clear it.
- **Tear a tab out**: drag it away from the strip to make it a normal, separate window again.
- **Drag a tab** sideways to reorder it, or onto another group's tab strip to move it there.
- **When only one window is left** (after tearing out or closing the others), the group dissolves. The last window goes back to being a normal window, with no tab strip, and gets back the space the strip used.
- **Drag the window** (title bar or empty tab-strip area) to move the whole group. Resizing the window resizes the group.

Reference UX: TrellisWM's tabs (https://trelliswm.app/docs/#tabs). In Top mode, the tab strip sits *above* the window's own title bar.

### Menu bar presence
- The app runs only as a **menu bar extra**, with no Dock icon and no app menu (`LSUIElement = YES`, `MenuBarExtra` in SwiftUI).
- **Clicking the menu bar icon shows a short menu with two items:**
  - **Settings…** (⌘,) opens the Settings window, where everything else lives: pause, excluded apps, shortcuts, updates, About, and Report a Problem.
  - **Quit Tabsome** (⌘Q) **untabs every group and leaves all the windows open** (§5.12).
- Kept short on purpose, so the icon is a simple way into Settings or out of the app.
- The menu bar icon dims when tabbing is paused (Settings › General) and shows a warning badge if the Accessibility permission is missing. When the badge is showing, the menu adds a third item at the top, **"Grant Accessibility Permission…"**, which opens onboarding.

### Quitting
Quitting Tabsome **never closes an app or a window**. Every group is undone, so each tabbed window goes back to being a normal, separate window. Each app keeps running, untouched. Details are in §5.12.

## 2. The core technical reality (read this first)

macOS **does not let one app take over another app's windows**. You can't move a Safari window inside a Tabsome window. So every cross-app tabbing tool fakes it, and we will too:

| Illusion | How it's actually done |
|---|---|
| "Windows are tabs of one window" | Every window in a group gets the **same frame** (position and size), set through the Accessibility (AX) API. |
| "Only one tab's content is visible" | The active window is **raised to the top** of the stack. The inactive members sit directly behind it at the identical frame, so they're fully covered. |
| "There's a tab bar" | Tabsome draws its own **borderless, non-activating overlay panel** (`NSPanel`) just above the group's frame, kept in sync as the window moves. |
| "Switching tabs" | Raise the chosen window with `AXRaise` and activate its app. |

Consequences that shape the whole design:
- **Requires the Accessibility permission.** Without it there's no reading or moving other apps' windows. This is non-negotiable.
- **Can't be sandboxed**, so it **can't ship on the Mac App Store**. Distribution is a Developer ID-signed, notarized DMG with Sparkle auto-updates. Every serious Mac window manager ships this way (Rectangle, AeroSpace, Amethyst, TrellisWM).
- **No SIP-disabling or code injection.** We only use public AX/AppKit/CoreGraphics APIs, plus one widely used private symbol, `_AXUIElementGetWindow`, which maps an AX window to its `CGWindowID`. Rectangle, AltTab, and AeroSpace all depend on it.
- Some windows won't cooperate: fixed-size windows, apps with poor AX support, and native full screen. The plan handles these explicitly (§8).

## 3. Tech stack

| Concern | Choice |
|---|---|
| Language | Swift 6 (strict concurrency, with the AX layer on `@MainActor`) |
| UI | **AppKit** for overlay windows (precise control over level, ordering, and click-through); **SwiftUI** for the tab strip contents, menu bar menu, Settings, and onboarding |
| Minimum macOS | **26 Tahoe**. One visual style, Liquid Glass, matching current macOS exactly, with the SwiftUI `glassEffect` APIs, `MenuBarExtra`, `SMAppService`, and current ScreenCaptureKit available without fallbacks |
| Look | **Liquid Glass** throughout (§5.15): the tab strip, flyout, highlight, and menus use the system glass materials, not custom imitations |
| Window control | `ApplicationServices` AX API (`AXUIElement`, `AXObserver`) |
| Window discovery / z-order | `CGWindowListCopyWindowInfo` |
| Mouse tracking | `NSEvent.addGlobalMonitorForEvents` (left mouse down/dragged/up) |
| Animation | SwiftUI springs (`.snappy`, `.smooth`) for our views; `CASpringAnimation` for overlay panels; ScreenCaptureKit snapshots for window proxies (§5.9) |
| Global hotkeys | [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) (SPM) |
| Launch at login | `SMAppService.mainApp` |
| Updates | [Sparkle 2](https://sparkle-project.org) (SPM) |
| Settings storage | `UserDefaults` / `@AppStorage` |
| Logging | `os.Logger`, plus a rotating file log for bug reports |
| Project | Xcode project (needed for signing, entitlements, and the Info.plist), with SPM dependencies |

**Prerequisites:**
- Install **full Xcode** from the App Store. This Mac currently has only the Command Line Tools. Then run `sudo xcode-select -s /Applications/Xcode.app`.
- Sign in to Xcode (Settings › Accounts) with your **free Apple ID**. That creates a free "Personal Team" with an **Apple Development** signing certificate.

**Signing with a free Apple ID:**
- **During development, the free account is all we need.** Every build is signed with the same Apple Development certificate, which gives Tabsome a **stable identity**. That matters: macOS ties the Accessibility (and Screen Recording) permission to the app's signature. With unsigned or ad-hoc builds, macOS forgets the permission after every rebuild and you'd have to re-grant it each time.
- Tabsome uses no restricted entitlements (no sandbox, no iCloud, no push), so there's no expiring provisioning profile to renew. Phase 1 confirms this.
- **Sharing Tabsome with anyone else needs the paid Apple Developer Program ($99/yr)** for a Developer ID certificate and notarization. Without those, macOS blocks the app on other Macs, and each person has to approve it manually in System Settings › Privacy & Security. Phase 7 is the point to enroll (§7). Nothing before Phase 7 depends on it.

**Prior art worth reading:** AeroSpace (AX wrappers, hiding windows), Rectangle (detecting drags for snap zones), AltTab (window enumeration, `_AXUIElementGetWindow`, Spaces handling), Amethyst.

## 4. Architecture

```
Tabsome.app  (LSUIElement menu bar app)
│
├── App/
│   ├── TabsomeApp.swift          @main, MenuBarExtra, Settings scene
│   ├── MenuBarMenu.swift         menu contents: Settings…, Quit Tabsome (plus the permission item when needed)
│   ├── AppearanceController.swift  System / Light / Dark setting → NSApp.appearance (§5.13)
│   ├── Onboarding/               permission walkthrough
│   └── Settings/                 General · Tabs · Apps (exclusions) · Shortcuts · About
│
├── Core/AX/
│   ├── AXWindow.swift            typed wrapper: frame get/set, title, subrole, raise, close, minimized
│   ├── AXApp.swift               per-app element plus its AXObserver
│   ├── WindowRegistry.swift      live map of CGWindowID → AXWindow; tracks create/destroy/move/resize/title/focus
│   ├── DockBadges.swift          reads only the Dock items' badge text, every 3 s while groups exist (§5.14)
│   ├── WindowSystem.swift        protocol over the AX and CG calls (lets us unit-test with a fake)
│   └── Permissions.swift         AXIsProcessTrustedWithOptions, polling for grant/revoke
│
├── Core/Drag/
│   ├── DragMonitor.swift         global mouse monitor plus AX "moved" events → "window W is being dragged"
│   ├── DropTargetResolver.swift  topmost eligible window under the cursor (excluding the dragged one)
│   ├── DropZone.swift            "middle" rect geometry (pure and testable)
│   └── DwellStateMachine.swift   idle → hovering(target) → armed(target) → drop/cancel (pure and testable)
│
├── Core/Groups/
│   ├── TabGroup.swift            ordered [WindowRef], activeIndex, frame
│   ├── LayoutPresets.swift       halves, quarters, fill, center, arrange, margins (pure, tested)
│   ├── TabNaming.swift           label rules: custom name > same-app tiebreaker > app name (pure, tested)
│   ├── GroupManager.swift        merge, add, remove, reorder, activate, dissolve, move/resize sync
│   ├── FrameSync.swift           applies the group frame to members (debounced and coalesced)
│   └── Concealment.swift         keeps inactive tabs hidden (stacking, plus corner parking for misfits)
│
└── UI/Overlays/
    ├── OverlayPanel.swift        shared NSPanel subclass: borderless, non-activating, no shadow
    ├── DropHighlightWindow.swift the "drop here to tab" highlight and ghost tab
    ├── TabBarWindow.swift        one per group, hosting the SwiftUI TabStripView
    ├── TabStripView.swift        tabs for both placements: Top (icon + app name) or Left (icon only)
    ├── StripLayout.swift         TabPlacement enum; pure strip and content frame math (unit-tested)
    ├── TabDragController.swift   tab drag: reorder, tear-off, and drop onto another target
    ├── TabRenameField.swift      inline rename field (in-tab for Top, attached popover for Left)
    ├── WindowControlsView.swift  group red/yellow/green buttons, drawn to match macOS (§5.11)
    ├── ArrangeFlyout.swift       Move & Resize flyout replica shown from the green button
    ├── HoverPreview.swift        background-tab preview popover and its one-window capture stream (§5.14)
    ├── SpringLoading.swift       drag-destination handling on the strip that switches tabs mid-drag (§5.14)
    ├── Metrics.swift             every size, spacing, and radius, measured from current macOS (§5.15)
    ├── Motion.swift              the only place animation timings live (§5.9); Reduce Motion fallbacks
    └── WindowProxy.swift         snapshot or icon-card overlay used to animate real windows (§5.9)
```

Data flow:

```
mouse events ─┐
AX moved ─────┴─► DragMonitor ─► DropTargetResolver ─► DwellStateMachine ─► DropHighlightWindow
                                                             │ (mouse up while armed)
                                                             ▼
AX notifications ─► WindowRegistry ─────────────────────► GroupManager ─► FrameSync / Concealment (AX writes)
                                                             │
                                                             └─► TabBarWindow (per group)
```

## 5. Key mechanisms in detail

### 5.1 Detecting that the user is dragging a window
- Watch global `leftMouseDown`, `leftMouseDragged`, and `leftMouseUp` events.
- On mouse down, record the window under the cursor (CGWindowList hit test, then a WindowRegistry lookup).
- If that window fires `kAXMovedNotification` while the button is still down, it's a **title-bar drag** of that window.
- This ignores text selection, scrolling, and resizing. A resize fires `kAXResizedNotification`, which we ignore for merge purposes.

### 5.2 Finding the drop target and the "middle"
- During the drag, read the on-screen window list front to back (`CGWindowListCopyWindowInfo(.optionOnScreenOnly)`, `kCGWindowLayer == 0`). Pick the first window under the cursor that:
  - isn't the dragged window
  - isn't in the dragged window's own group
  - isn't a Tabsome overlay
  - isn't excluded
  - is an `AXStandardWindow`
- If the target is a tabbed window, the target is its **group**.
- **Middle zone** = the target frame inset by 25% on each side, so it's the central 50% × 50% (configurable). Keeping the zone central leaves window edges free for future docking and snapping, and stops a drag that merely passes over a window from triggering.
- **Tab strip zone (browser-style):** if the cursor is over an existing group's **tab strip**, that's an immediate target with **no dwell**, exactly like dragging a tab into another browser window. An insertion marker shows between the tabs where the window will land, and dropping inserts it at that index. This applies to plain windows dragged by their title bar and to tabs dragged out of another strip.
- The strip zone wins over the middle zone when both apply.

### 5.3 Dwell ("pause for a moment")
States:
- `idle` → `hovering(target, since)`
  - Moves out of the zone or onto a new target reset the state.
  - Cursor jitter under 6 pt doesn't count as movement.
- After **450 ms** (configurable from 200 to 1000 ms) → `armed(target)`, which shows the highlight:
  - a translucent rounded rect over the target
  - a ghost tab strip previewing the result, with the dragged window's icon and title appended
- If the cursor leaves the zone while armed → back to `idle` (the highlight fades out).
- Mouse up while armed → **merge**, adding the new tab at the end of the strip. Mouse up any other time → do nothing.
- Over a tab strip, the machine goes straight to `armed(target, insertIndex)` with no wait (§5.2), and the insertion marker replaces the full-window highlight.

The state machine is pure. It takes `(cursorPoint, timestamp, targetUnderCursor)` and returns a new state plus effects, so it can be unit-tested without a GUI.

### 5.4 Merge
1. If the target isn't yet in a group, create one with the target's frame, **shrunk on the strip's side by the strip's thickness** so the strip doesn't cover app content:
   - Top: 28 pt off the top
   - Left: 40 pt off the left

   The outer bounds (window plus strip) stay where the original window was.
2. Append the dragged window (or, if the dragged window is itself a group's active window, all of that group's tabs).
3. Use `FrameSync` to set each new member's frame to the group frame, with the size → position → size pattern for reliability.
4. Make the dropped window the active tab: raise it and activate its app.
5. Create or update the group's `TabBarWindow`.
6. Animate the snap-in with the proxy technique in §5.9.

### 5.5 Keeping inactive tabs hidden (`Concealment`)
- **Default (stacking):** inactive members share the exact frame and sit directly beneath the active window. Switching is instant (just `AXRaise`), and Mission Control still shows real windows.
- **Corner parking** handles members that can't match the group frame (fixed-size windows, or a minimum size larger than the group). They're moved to the screen's bottom-right corner, leaving 1 px on screen, while inactive. This is the approach AeroSpace uses. They return to the group frame when activated.
- **Rejected options:**
  - *Minimize*: slow genie animation and Dock clutter.
  - *App hide*: hides all of that app's windows, which breaks two tabs from the same app.

### 5.6 The tab strip overlay (`TabBarWindow`)
- One `NSPanel` per group:
  - style: `.borderless` + `.nonactivatingPanel`
  - `isFloatingPanel = false`
  - `collectionBehavior = [.managed, .fullScreenNone]`
  - `hidesOnDeactivate = false`
  - clicks don't steal focus from the tabbed app
- **Z-order:** the strip must sit right above the group's window but *below* any other window covering it, so we can't use a floating level. Keep it at normal level and call `order(.above, relativeTo: activeWindowCGWindowID)` whenever focus or order changes. ⚠️ Validate in the Phase 0 spike (§7). Fallback: compute occlusion from CGWindowList and hide or clip the strip whenever another window overlaps it.
- **Placement** is a `TabPlacement` enum (`.top`, `.left`) stored in settings. One `TabStripView` takes the placement and lays out horizontally or vertically. The strip panel's frame and the group's content frame both come from one pure function, `StripLayout.frames(outer:placement:)`, so the geometry is unit-tested once for both modes.
- **Top mode contents (SwiftUI):**
  - the **group window buttons** (red, yellow, green) at the far left, laid out like Safari's tab bar, with the **exact size, spacing, and inset of the system's own buttons on the running macOS** (measured from a real window in Phase 0, not hard-coded from memory; §5.11). Tabs start after them
  - each tab has an app icon (`NSRunningApplication.icon`), its **label**, and a close ×. The label is the **full app name** (`localizedName`) unless the user has renamed the tab (§5.10)
  - close × follows Chrome: always visible on the active tab, shown on hover for the others
  - the window title appears as a tooltip; it's also the tiebreaker label when two tabs are the same app (see §10)
  - **browser look:** the active tab shares a title-bar color (from Tabsome's appearance setting, §5.13) and visually connects to the window below it; background tabs are recessed and dimmer, with thin separators between them
  - tabs share the width evenly with a minimum of about 90 pt, and the name truncates with an ellipsis only when there's no room
  - past that minimum, tabs shrink to icon-only, then show an overflow `»` menu
  - a **"+" button** after the last tab opens a menu of open windows that aren't in this group (icon, app name, window title); choosing one adds it as a tab at the end
  - **width freeze while closing** (Chrome's behavior): after a tab is closed, the remaining tabs keep their widths while the pointer stays in the strip, so the next × lands under the cursor. They reflow with `Motion.smooth` when the pointer leaves
- **Left mode contents (SwiftUI):**
  - a 40 pt wide column of 28 pt app icons, one per tab, with no text
  - hover tooltip: the tab's label (custom name or app name) and window title
  - active tab: a highlight pill behind the icon plus an accent bar on the inner edge
  - close × appears as a small badge on the icon's corner on hover
  - the "+" button sits below the last icon and works the same as in Top mode
  - when the tabs outgrow the window height, the column scrolls, with an overflow `»` menu at the bottom
  - "to the right" in menus and close behavior means "below" in this mode
- **Changing placement in Settings** re-lays out every live group right away: give back the old strip's space, take the new side's space, and rebuild each strip.
- **Colors** come from Tabsome's Appearance setting (System, Light, or Dark; §5.13) and change live.
- Both modes support **unlimited tabs** through the overflow behavior above.
- Follows the active window live during moves and resizes. The strip tracks on every `kAXMovedNotification`, and inactive members are re-synced on mouse up so we don't flood other apps with AX writes mid-drag.

### 5.7 Tab interactions
Every row matches Safari/Chrome unless it says otherwise (§1, "works like browser tabs").

| Action | Behavior |
|---|---|
| Click tab | Activate that member: raise it, activate its app, and reorder the strip above it |
| Click × or middle-click tab | **Close Tab:** presses the window's AX close button, so the app closes the window (and asks to save if it needs to). Then the **tab to the right** becomes active, or the one to the left if it was the last |
| Drag tab along the strip | Reorder: sideways in Top mode, up and down in Left mode. Neighbors slide out of the way |
| **Tear out:** drag a tab more than 20 pt away from the strip (down in Top mode, right in Left mode) | A ghost of the window follows the cursor. On drop, that window leaves the group at the drop point as a **normal, untabbed window** at the group's size. If only one window is left, the group dissolves (see §5.8) |
| Drag tab onto another group's tab strip | Insert it at that position right away, no pause (§5.2) |
| Drag tab over another window's middle and pause | Same dwell and highlight as §5.3, then move the tab into a group with that window |
| Drag empty strip area | Moves the whole group |
| Double-click empty strip area | Same as double-clicking a title bar on this Mac (zoom or minimize, per System Settings) |
| Click "+" | Menu of other open windows; choosing one adds it as the last tab |
| Double-click tab | **Rename inline** (§5.10). The first click still switches to the tab. *(Not a browser behavior; matches Finder renaming)* |
| Right-click tab | Same order as Chrome: **Close Tab**, **Close Other Tabs**, **Close Tabs to the Right**, separator, **Move Tab to New Window** (tear it out in place), separator, **Rename Tab…**, **Reset Name** (only when renamed) |

**Keyboard shortcuts.** Same layout as browser shortcuts. ⌘ and ⌃Tab can't be used globally because they'd steal the apps' own shortcuts (Safari's ⌃Tab, every app's ⌘W). So Tabsome uses ⌃⌥ in their place. All are rebindable in Settings › Shortcuts.

| Shortcut | Browser equivalent | Action (in the focused group) |
|---|---|---|
| ⌃⌥Tab / ⌃⌥⇧Tab | ⌃Tab / ⌃⇧Tab | Next / previous tab (wraps around) |
| ⌃⌥1 … ⌃⌥8 | ⌘1 … ⌘8 | Go to tab 1–8 |
| ⌃⌥9 | ⌘9 | Go to the last tab |
| ⌃⌥W | ⌘W | Close the active tab |
| ⌃⌥⇧N | (Move Tab to New Window) | Move the active tab out of its group |
| ⌃⌥R | (none) | Rename the active tab |

### 5.8 Staying in sync with the outside world
| Event | Response |
|---|---|
| Active member moved or resized by the user | Update the group frame. Re-sync the other members on mouse up. Move the strip live |
| Active member tiled by macOS (its own green-button flyout, Window › Move & Resize, the fn-⌃ arrow shortcuts, or edge drag) | The window lands on a screen tile with no room for the strip. Detect a frame that matches a tile of `NSScreen.visibleFrame`, then **re-fit the group so the outer frame (strip plus window) fills that tile**, shrinking the window by the strip's thickness. The result looks the same as using Tabsome's own flyout |
| Member window closed (`kAXUIElementDestroyed`), from the tab's × or from inside the app | Remove the tab. If it was active, activate the **tab to its right** (or left, if it was last), like a browser. If only one tab is left, **dissolve** the group |
| **Group drops to one window** (tear-out, close, Move Out, app quit) | **Dissolve:** remove the strip panel, un-park the last window if it was corner-parked, grow it back into the strip's space (height in Top mode, width in Left mode), and stop tracking it as a group. It's an ordinary window again and can be dragged into a new group later |
| Member's app quits or crashes (`NSWorkspace.didTerminateApplication`) | Remove all of that app's tabs |
| Window title changes | Update the tooltip, the "+" menu entry, and the same-app tiebreaker label |
| User Cmd-Tabs or clicks into an inactive member (`kAXFocusedWindowChanged` / `kAXMainWindowChanged`) | Treat it as a tab switch: make that member active |
| Member minimized (its own yellow button or ⌘M) | Treat it like the group's yellow button: minimize the whole group (§5.11). On restore, bring the whole group back |
| Member enters native full screen | Remove it from the group (full screen moves it to its own Space) |
| Group's windows move to another Space or display | Strip follows the active window. Hide the strip when the window isn't on screen (CGWindowList on-screen check) |
| **Tabsome quits, is paused, or crashes** | **Untab everything, close nothing** (§5.12). Persist a recovery file so the next launch can repair state after a crash |
| Sleep/wake, display change | Rebuild the registry and re-validate all groups |
| Accessibility permission revoked | Stop all behavior, hide overlays, and badge the menu bar icon |

### 5.9 Motion: animations that feel like Apple's
**Rule:** every animation in Tabsome should look and feel like macOS itself:
- **Spring-based, not fixed-duration curves.** Use the same springs AppKit and SwiftUI use, not hand-tuned linear or ease-in-out timings.
- **Interruptible.** A new gesture picks up from the current position and velocity; nothing has to finish before the next thing starts.
- **Gesture velocity carries through.** When you let go mid-drag, motion continues from your hand's speed, the way windows and Safari tabs behave.
- **Quiet.** Fades and slides that confirm what happened, with no bounce for show and no attention-seeking effects.

**One shared motion vocabulary:** a single `Motion.swift` file defines named animations, and nothing else in the codebase picks its own timing:

| Token | Built on | Used for |
|---|---|---|
| `Motion.snappy` | SwiftUI `.snappy` (CA: `CASpringAnimation(perceptualDuration: 0.3, bounce: 0.15)`) | Window snapping into a group, tear-out landing, tab reorder slide |
| `Motion.smooth` | SwiftUI `.smooth` (no bounce) | Tab strip appearing and disappearing, group dissolving, placement changes |
| `Motion.quickFade` | `.easeOut`, 0.15 s | Drop highlight fade in/out, hover states, close × appearing |
| `Motion.interactive` | `.interactiveSpring` | Anything following the cursor (tab drag, ghost window) |

**Matching specific macOS behaviors:**

| Tabsome moment | Modeled on |
|---|---|
| Drop highlight after the dwell | The current macOS window-tiling preview: a translucent glass rounded rect that fades and scales in slightly (0.97 → 1.0) |
| Window snapping into the group | A window settling into a tile: one spring from where you let go to the group frame |
| Tab appearing in the strip | Safari adding a tab: existing tabs slide over and the new one grows in from zero width |
| Tab reorder | Safari/Finder tab reorder: neighbors slide out of the way as the dragged tab passes their midpoint |
| Tear-out | Safari tearing a tab into a window: the tab lifts off with a shadow, becomes a window-shaped proxy that follows the cursor, then springs into place on drop |
| Group dissolving | The strip slides away toward its edge and fades while the last window springs into the freed space |
| Switching tabs | Instant, like native tabs. No cross-fade on the content |
| Top ↔ Left change | The strip slides out on one edge and in on the other with `Motion.smooth` |

**How it's technically possible:** we can't run Core Animation on another app's window, and AX frame writes can't be driven at 60–120 fps reliably. So window motion uses **proxies**:
1. Capture a snapshot of the window with ScreenCaptureKit (`SCScreenshotManager`).
2. Show the snapshot in a borderless overlay at the window's current frame, and animate the overlay with the spring.
3. Underneath, move the real window to its final frame with one AX write while it's covered.
4. When the spring settles, cross-fade the proxy out over 0.1 s to reveal the real window.

This needs the **Screen Recording permission**, which is **optional** and requested in onboarding with a plain explanation (nothing is saved or sent). Without it, the proxy is a glass card showing the app's icon and name. That's still smooth, just not a live picture. Tabsome's own overlays (highlight, strip, tabs) are ours, so they animate natively with no permission needed.

**Respecting system settings:**
- **Reduce Motion** (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`, observed live): replace springs and slides with short cross-fades, which is what macOS does.
- **Reduce Transparency:** glass becomes solid fills (the system glass APIs do this automatically).
- **Increase Contrast:** strip and highlight borders get stronger.

No separate "animations" setting in Tabsome. We follow the system, like Apple's own apps.

**Performance budget for motion:** every animation holds the display's refresh rate (60 or 120 Hz on ProMotion). Use `CADisplayLink` (`NSView.displayLink`) for anything driven per-frame. Check with Instruments' Animation Hitches template before shipping each phase.

### 5.10 Renaming tabs
**Default name:** the app's full name, so "Safari" or "Visual Studio Code" (with the same-app tiebreaker from §10). Users can rename any tab to whatever they like, and it's quick and inline, like renaming a file in Finder.

**Starting a rename** (any of these):
- Double-click the tab.
- Right-click → **Rename Tab**.
- ⌃⌥R renames the active tab of the focused group.

**Top mode:** the tab's label turns into a text field in place, at the same font and position, with the whole name selected so typing replaces it. The tab widens with `Motion.snappy` as the text grows, up to the strip's available width.

**Left mode:** tabs are icon-only, so a small text field pops out to the right of the icon, attached to it (a borderless popover styled like the strip). The name still isn't shown in the strip afterwards. It appears in the tab's hover tooltip and the "+" menus of other groups.

**Editing rules:**
- **Return** or clicking anywhere else saves. **Esc** cancels and keeps the old name.
- Leading and trailing spaces are trimmed. A maximum of 60 characters.
- Saving an **empty name** resets the tab to the app's name. Right-click → **Reset Name** does the same.
- A custom name always wins over the default label and the same-app tiebreaker.

**Where the name lives:** on the window's `WindowRegistry` entry, not on the group. So the name follows that window when it's torn out and later dropped into another group. It goes away when the window closes. (Keeping names across app or Mac restarts is part of the open persistence decision in §10.)

**Typing into an overlay without stealing focus:** the strip is a non-activating panel, so for the rename it becomes the key window (`canBecomeKey = true`) without activating Tabsome or deactivating the tabbed app, the same way Spotlight takes typing. When the edit ends, key focus returns to the active tab's window.

**Motion:** the field fades in with `Motion.quickFade`, and the tab width springs to fit the new name with `Motion.snappy`.

### 5.11 Group window buttons and the Move & Resize flyout
In Top mode, the left end of the tab strip has the three standard macOS window buttons, like Safari's and Chrome's tab bars. They act on the **group**, not one tab.

**Look and behavior (identical to macOS):**
- The same size, spacing, and colors as the system's buttons on the running macOS (measured in Phase 0). They turn grey when the group isn't the focused window.
- Hovering any of the three shows all three glyphs (×, −, and the green button's arrows), like macOS.
- Built as our own SwiftUI views drawn to match Apple's. We can't borrow the system's real buttons, because those control the window that owns them, which here would be Tabsome's strip panel.
- The area around the buttons still drags the group, like a title bar.

| Button | Action | Notes |
|---|---|---|
| 🔴 **Close** | **Close all tabs:** presses the AX close button on every member window | Like Safari, it first asks "Close *N* tabs?" with a "Don't ask again" checkbox (Settings › Tabs, "Ask before closing all tabs", on by default). Apps that need to save show their own prompts. Windows that stay open (the user hit Cancel) stay in the group |
| 🟡 **Minimize** | **Minimize the group to the Dock as one item** | Only the active window is minimized with the AX minimized attribute, so the Dock gets **one** thumbnail (macOS's genie animation, for free). The other members are corner-parked and the strip is hidden. Clicking that Dock thumbnail (or switching to that app with ⌘Tab) un-minimizes the window. Tabsome sees that and brings back the whole group and strip. The Dock thumbnail shows the active tab's window only; there's no way to give the Dock a combined picture |
| 🟢 **Maximize** (click) | **Fill the screen:** the group's outer frame fills the screen's usable area (`NSScreen.visibleFrame`, which leaves out the menu bar and Dock). Clicking again **returns to the previous size and position** | ⌥-click does the same. This is "Fill", **not native full screen**: macOS full screen gives each window its own Space, which can't hold a cross-app group |
| 🟢 **Maximize** (hover about 0.5 s, or click and hold) | Opens the **Move & Resize flyout** (below) | Same timing as macOS |

**The Move & Resize flyout** is a replica of the macOS green-button menu that moves and resizes the **group**. It's our own popover (the system's menu only works on the window that owns it), styled to match the current macOS menu: a Liquid Glass background, small layout tiles, and section headers. Its items and layout follow what the system menu offers on macOS 26+.
- **Move & Resize:**
  - Halves: Left, Right, Top, Bottom
  - Quarters: Top Left, Top Right, Bottom Left, Bottom Right
- **Fill & Arrange:**
  - Fill
  - Center
  - Arrange with the most recent other window or group:
    - side by side (left/right)
    - stacked (top/bottom)
- **Move to *Display Name***: one item per other display, keeping the same relative size and position.
- **Return to Previous Size**: shown only after a move or resize from this flyout or the green button.
- **Full Screen** is left out on purpose (see the Fill note above).

**Matching macOS details:**
- Every preset applies to the group's **outer** frame (strip plus window), so a left-half group has its strip at the top of the left half. All the math lives in one pure, unit-tested `LayoutPresets` function.
- Respects System Settings › Desktop & Dock › "Tiled windows have margins": gaps between tiles if it's on, edge to edge if it's off.
- The group moves with `Motion.snappy` through the proxy technique (§5.9), the same spring as macOS window tiling.
- Each group remembers its frame from before the last preset, for "Return to Previous Size" and the second green click.

**The app windows' own buttons:** each tabbed window still has its own red, yellow, and green buttons in its title bar just below the strip. Apps own those, and Tabsome can't remove or hide them. They keep working, mapped to browser-like meanings:
- **Red** closes just that tab (like closing one tab).
- **Yellow** minimizes the whole group (§5.8), the same as the group's yellow button.
- **Green** hover menu: macOS tiles that one window, and Tabsome re-fits the whole group to the tile (§5.8).
- **Green** click into native full screen: removes that window from the group (§5.8).

**Left mode:** no group buttons in the strip (the icon column stays icon-only). The windows' own buttons still behave as above. Group close, minimize, and fill are available from right-clicking empty space in the icon column (see §10).

### 5.12 Quitting: untab everything, close nothing
**Rule:** quitting Tabsome must **never close an app or a window** and must never lose anything. It only undoes Tabsome's own changes, so every window ends up as an ordinary window again, as if Tabsome had never been running.

**What happens on Quit Tabsome (⌘Q, or the menu bar item):**
1. Stop watching drags so no new groups can form, and hide every drop highlight.
2. For each group, **dissolve** it as §5.8 describes:
   - Remove the tab strip.
   - Grow each window back into the strip's space (height in Top mode, width in Left mode).
   - **Un-park** any corner-parked windows.
3. **Fan the windows out so none are hidden.** While grouped, the tabs sit exactly on top of each other. Leaving them that way would make a group look like one window and "hide" the rest. So the windows are **cascaded** like macOS's own window cascade: the active tab stays where it is and on top, and each other tab is offset 22 pt right and down from the one before. They stay within the screen's usable area and wrap back to the start if they'd run off it.
4. **Minimized groups:** the minimized window stays in the Dock where the user put it. Its parked group-mates are brought back and cascaded on screen, so nothing ends up out of sight.
5. Delete the recovery file (a clean exit leaves nothing to repair) and exit.

**Timing:** all of this happens in `applicationShouldTerminate`. Tabsome replies `.terminateLater`, then confirms once the windows are restored. The restore is capped at **2 seconds** in total, so a hung app (§6.2 P1) can't stop Tabsome from quitting; any window that didn't respond is fixed by the recovery file on the next launch. The windows move with `Motion.smooth` (instant under Reduce Motion).

**Every way Tabsome can stop:**

| How it stops | What happens |
|---|---|
| Quit Tabsome from the menu, or ⌘Q in Settings | The full restore above |
| Logout, restart, or shutdown | The same restore, within the time macOS allows |
| Paused in Settings › General | The same restore, but Tabsome keeps running. Groups don't come back when it's unpaused; the user re-forms them |
| Tabsome is updated by Sparkle | The same restore before the relaunch |
| Crash or Force Quit (no chance to run any code) | Windows may be left stacked or parked. **On next launch**, Tabsome reads the recovery file and does the restore then, before anything else |

**No confirmation dialog on Quit.** Nothing is lost, so there's nothing to confirm. That matches how quitting other menu bar utilities works.

### 5.13 Appearance: System, Light, or Dark
A setting in **Settings › General** with three choices, shown as three thumbnails like System Settings › Appearance:

| Choice | Behavior |
|---|---|
| **System** (default) | Follows whatever macOS is set to, **including Auto**: when macOS switches between light and dark during the day, Tabsome switches with it, live |
| **Light** | Tabsome always uses light, whatever macOS is set to |
| **Dark** | Tabsome always uses dark, whatever macOS is set to |

**What it affects:** everything Tabsome draws:
- tab strips (both placements), the "+" menu, and right-click menus
- the group window buttons and the Move & Resize flyout
- the drop highlight, insertion marker, ghost tab, and icon-card proxies
- the inline rename field
- the Settings window, onboarding, and the menu bar menu

**What it doesn't affect:** other apps' windows. Tabsome can't change another app's appearance. So with Tabsome on Dark and macOS on Light, a dark tab strip sits on top of a light app window. That's the user's choice, and the strip still looks deliberate: the active tab uses the chosen scheme's title-bar color.

**How it's built:**
- One `AppearanceController` sets `NSApp.appearance`:
  - `nil` for System (AppKit then follows macOS on its own, including Auto)
  - `NSAppearance(named: .aqua)` for Light
  - `NSAppearance(named: .darkAqua)` for Dark
- Setting it once on `NSApp` covers every Tabsome window and panel, and SwiftUI views inherit it, so no view picks its own scheme. All colors are semantic (system colors and asset-catalog colors with light and dark variants). Nothing is hard-coded to one scheme.
- Changes apply **instantly** to everything already on screen, with no relaunch. A quick `Motion.quickFade` cross-fade on the strips smooths the switch, the same way macOS does it.
- The system's traffic-light colors and the accessibility settings (Increase Contrast, Reduce Transparency; §5.9) keep working in all three modes.
- The menu bar icon is a template image, so it always follows the **menu bar's** look, which macOS controls, whatever this setting says.

### 5.14 Browser-style extras
Three more behaviors borrowed from Safari, Chrome, and Finder.

**1. Spring-loaded tabs (switching tabs while dragging a file)**
- While you drag a file, text, image, or anything else, hovering it over a **background tab** for a moment switches to that tab. You can then drop the item into that window. Safari tabs and Finder folders work the same way.
- **How:** the tab strip registers as a drag destination for every data type (`NSDraggingDestination`). macOS sends it `draggingEntered` and `draggingUpdated` for drags from any app. Over a tab, a timer starts; when it fires, that tab is activated. The strip **never accepts the drop itself** (it returns no drag operation), so the item still lands in the app's window.
- **Timing follows the system:** it uses the Finder spring-loading delay from System Settings › Accessibility › Pointer Control, and turns off if spring-loading is turned off there.
- The tab blinks once just before it switches, like Finder's spring-loaded folders.
- Works in both Top and Left modes. Content drags never set off the window-merge gesture (§5.1), because no window is being moved.

**2. App badges on tabs**
- When an app shows a badge on its Dock icon (Mail's unread count, Slack's mentions, a "!" from a download), the same badge appears on its tab or tabs.
  - **Top mode:** a small red pill after the tab's name.
  - **Left mode:** a red badge on the icon's top-right corner, like the Dock.
- Badges belong to the app, not to one window, so every tab from that app shows the same badge.
- **How:** the Dock's own items expose their badge text through Accessibility (the status label of each Dock item). macOS sends no notification when a badge changes, so this is the one place Tabsome checks on a timer: **every 3 seconds, only while at least one group exists, on a background thread, reading only the Dock's item list** (a single call). The timer stops when the last group dissolves. This is a deliberate, narrow exception to the "no polling" rule (§6.2 P2) and the "window attributes only" rule (§6.1 S1).
- Settings › Tabs › "Show app badges on tabs" (on by default).

**3. Hover previews**
- Hovering a **background tab** for about 0.6 s shows a small preview of that window in a glass popover below it (beside it in Left mode), like Safari's tab previews. The preview shows the window's current contents, plus the tab's name and window title.
- Moving to the next tab swaps the preview right away, with no second wait, like Safari. Clicking the tab or moving away dismisses it.
- **How:** ScreenCaptureKit can capture a window even when another window covers it, which is the normal state for a background tab. While the popover is open, Tabsome streams **only that one window at a low frame rate** (about 5 fps) and stops the stream the moment it closes.
- **Needs the optional Screen Recording permission.** Without it, the popover shows a larger app icon with the name and window title instead.
- Previews are kept in memory only, never saved or sent anywhere (§6.1 S3).
- Settings › Tabs › "Show previews when hovering tabs" (on by default).

### 5.15 Look: Liquid Glass, like current macOS
Tabsome targets **macOS 26 and later**, so it has one look: Apple's **Liquid Glass**, matching the system exactly.
- **The tab strip** uses the system glass material (SwiftUI `glassEffect`), like the toolbars and tab bars in Safari and Finder. It is not a custom imitation of glass.
- **The active tab** uses the selected-tab treatment from current Safari: a raised glass capsule. Background tabs sit flat on the strip.
- **Popovers and menus** (the "+" menu, Move & Resize flyout, hover previews, rename field in Left mode, right-click menus) use the standard system popover and menu styles, so they match whatever the system draws.
- **The drop highlight and insertion marker** use glass with the system accent color, like the window-tiling preview.
- **Size and spacing** (strip height, corner radii, button size and inset, padding) are measured from real Safari and Finder windows on the running macOS in Phase 0. They are not guessed. They live in one `Metrics.swift` file so a future macOS update means one file to adjust.
- Respects the user's accent color, Appearance setting (§5.13), Reduce Transparency, and Increase Contrast; the glass APIs handle the last two on their own.

## 6. Security and performance

Tabsome needs broad system access and talks to every running app. That's normal for a Mac window manager, but it means the rules below are **design requirements from day one**, not polish. Each item lists the roadmap phase where it's built (§7).

### 6.1 Security

| # | Risk | Rule | Phase |
|---|---|---|---|
| S1 | **The Accessibility permission is very powerful.** It lets Tabsome read and control the interface of every app. A compromised Tabsome (e.g., a tampered update) would inherit that power | **Window-level access only.** Tabsome reads and writes only these window attributes: frame, title, subrole, minimized, fullscreen, main/focused, close button, and raise. It never walks into an app's content. **One narrow exception:** reading the badge text of the Dock's items for app badges (§5.14), in a single `DockBadges.swift` file that reads nothing else. `AXWindow.swift` / `AXApp.swift` (plus `DockBadges.swift`) are the **only** files allowed to import or call AX APIs, and they expose only those attributes. Code review enforces this, and a CI grep check fails the build if AX calls appear anywhere else | 1 |
| S2 | Supply chain: tampered updates or dependencies | Sparkle 2 updates only, **EdDSA-signed** and over HTTPS. Hardened runtime with library validation (no loading unsigned code). Notarized builds. No plugin or scripting system. Only two dependencies (Sparkle, KeyboardShortcuts), pinned in `Package.resolved`, with dependency bumps reviewed | 1 (hardened runtime), 7 (Sparkle, notarization) |
| S3 | **Screen Recording** (optional, for animations and hover previews) can see anything on screen | Capture **only the one window being animated or previewed**: a single `SCScreenshotManager` shot for animations, and a low-rate stream of that one window that runs only while a hover preview is open. Held **in memory only** and released as soon as the animation ends or the preview closes. Never written to disk and never sent anywhere. Windows that block capture (password managers, DRM video) are excluded by ScreenCaptureKit and fall back to the icon card. Keep the permission optional, partly because recent macOS versions periodically ask users to re-confirm Screen Recording access | 1 (onboarding), 3 (proxies), 4 (previews) |
| S4 | **Window titles can be sensitive** (email subjects, document names, URLs), and so can custom tab names | `os.Logger` marks titles and tab names `.private`, and the file log never records them. The crash-recovery file stores only window IDs, pids, bundle IDs, and frames. "Report a Problem" shows the user everything before it's sent. **No telemetry and no network traffic besides Sparkle update checks** | 1 (logging), 5 (recovery file), 7 (reporting) |
| S5 | Input monitoring could look like (or become) a keylogger | Monitor **mouse button and drag events only**, never keystrokes. Hotkeys use `RegisterEventHotKey` (through KeyboardShortcuts), which doesn't need the Input Monitoring permission. Tabsome never asks for Input Monitoring | 2 |
| S6 | Tabbing or snapshotting a security-sensitive window | A **hard-coded exclusion list that users can't override**: SecurityAgent and other authorization dialogs, Keychain prompts, password manager windows, and any window shown while secure input is on (`IsSecureEventInputEnabled`). Only `AXStandardWindow` subroles are eligible at all | 2 (eligibility), 5 (full list) |
| S7 | Overlays catching clicks meant for another app | The tab strip sits **outside** the window's frame. The drop highlight and window proxies set `ignoresMouseEvents = true`. Nothing Tabsome draws ever covers another app's content while it can receive clicks | 2, 3 |
| S8 | A larger blast radius because Tabsome isn't sandboxed | Disk writes only to Tabsome's own `Application Support`, `Logs`, and `Preferences` folders. No network access besides Sparkle. No URL scheme in v1 (if one is added later, every parameter gets validated and every command is something a user could safely trigger from a webpage) | 1 |

### 6.2 Performance and stability

| # | Risk | Rule | Phase |
|---|---|---|---|
| P1 | **A frozen app freezes Tabsome.** AX calls are synchronous messages to the target app, and they block for up to 6 s by default if that app is hung | Set `AXUIElementSetMessagingTimeout` to about 0.5 s on every element. Run **each app's AX work and AXObserver on its own thread**, so a hung app only stalls its own thread. The main thread never makes AX calls; it only receives results. If an app keeps timing out, mark it "unresponsive", ignore it until it recovers, and leave its tabs alone. (This only works one way: Tabsome can't freeze other apps, because they never wait on it) | 1 |
| P2 | Idle CPU and battery drain | Everything is event-driven, with **no polling and no repeating timers while idle**. The one exception is the Dock badge check (§5.14): every 3 s, one call, only while a group exists. With no groups, nothing runs at all. `CGWindowListCopyWindowInfo` runs only during an active drag, at most 30 times a second. The display link runs only while something is animating. Budget: **0% CPU and under 50 MB of memory when idle** | 1, checked in 6 |
| P3 | Making other apps redraw too much | During a drag or resize, only Tabsome's strip moves live. Inactive members are re-synced **once, on mouse up**. Stacking (the default way of hiding inactive tabs) lets macOS tell covered windows they're hidden so apps like Safari slow their rendering. Corner-parked windows still count as visible, so parking stays the fallback, never the default | 3 |
| P4 | **Fights with other window managers** (Rectangle, Stage Manager, an app's own window code) looping and burning CPU | **Loop detection:** if a member's frame is changed against Tabsome more than 3 times in 1 s, stop writing to it, remove it from its group, and show a one-time notice naming the app | 5 |
| P5 | Reacting to its own moves | Every AX write records the frame it expects with a short expiry. "Moved" or "resized" notifications that match an expected frame are ignored | 3 |
| P6 | Slow memory leaks from AX handles and observers | One owner per app (`AXApp`) holds every AX handle and observer for that app and tears them all down when the app quits. Test: launch and quit 100 apps with the Leaks instrument attached; memory must return to baseline | 1, checked in 5 |
| P7 | Windows stuck off-screen after a crash | Crash-recovery file written on every group change; next launch un-parks everything (§5.8) | 5 |

## 7. Phased roadmap

Each phase ends with something you can run and demo.

### Phase 0 — Spikes (de-risk the unknowns before writing product code)
Small throwaway command-line or app targets that prove:
1. AX can read, move, and resize windows in the test apps: Safari, Chrome, Finder, Terminal, VS Code, Slack (Electron), Notes, Xcode, and a Java app.
2. `_AXUIElementGetWindow` maps AX windows to CGWindowIDs reliably.
3. **Overlay z-ordering:** an `NSPanel` can be kept just above another app's window with `order(.above, relativeTo:)`, and another app's window can cover it. *This is the biggest risk*; pick the primary approach or the fallback here.
4. Title-bar drag detection (§5.1) has no false positives during text selection or resizing.
5. Stacking concealment: switching by `AXRaise` feels instant, with no flicker.
6. **Proxy animation (§5.9):** snapshot a window, spring the snapshot to a new frame, and swap in the real window with no visible pop. Measure the snapshot latency and how long the AX write takes to land in Safari, Terminal, and an Electron app.
7. **Hung-app isolation (§6.2 P1):** a test app that blocks its main thread for 10 s. Confirm that with per-app threads and a 0.5 s timeout, Tabsome stays responsive and keeps working with every other app.
8. **Measure the current macOS look (§5.15):** strip height, button size and inset, corner radii, and tab padding from real Safari and Finder windows, recorded in `Metrics.swift`.
9. **Cross-app drag destination:** a non-activating panel receives `draggingEntered` for a file dragged from Finder, and declining the drop still lets it land in the window underneath (§5.14).

**Exit:** a short findings note added to this file, with the hiding and z-order approaches confirmed.

### Phase 1 — Foundation
- **git repository** (this folder isn't one yet) with a Swift/Xcode `.gitignore`. Commit `PLAN.md` first.
- Xcode project, Swift 6, deployment target **macOS 26**, hardened runtime, no sandbox, `LSUIElement = YES`.
- Signed with your free Personal Team's Apple Development certificate. Confirm that the Accessibility permission **survives a rebuild** before moving on.
- `MenuBarExtra` with the two-item menu: Settings… and Quit Tabsome (§1).
- Settings window skeleton with the **Launch at login** toggle and the **Appearance** picker (§5.13), so every view built later is checked in both light and dark from the start (§7, Phase 6 has the full Settings list).
- Onboarding window: explain the Accessibility permission, "Open System Settings" button, poll until granted. A second, **optional** step asks for Screen Recording to enable live-picture animations (§5.9), with a "Skip" button. The last step is a short looping animation of the one gesture to learn ("drag a window onto another, pause, let go"), with the caption "After that, they work just like browser tabs."
- `Motion.swift` tokens and Reduce Motion / Reduce Transparency observers, so every later phase uses them from day one.
- `WindowRegistry` with AXObservers for all regular apps and live window tracking.
- **Security and performance groundwork (§6):**
  - one thread per app for AX work, 0.5 s messaging timeouts, no AX calls on the main thread (P1)
  - AX calls only in `AXWindow` / `AXApp`, limited to window-level attributes, plus the CI grep check (S1)
  - hardened runtime with library validation (S2); disk writes only to Tabsome's own folders (S8)
  - private logging of titles and names (S4)
  - event-driven only, no polling timers (P2); one `AXApp` owns and tears down each app's handles (P6)
- Debug menu item (debug builds only) that dumps the registry. Titles appear only in this debug-build dump, never in logs.

**Demo:** the menu bar icon appears, onboarding grants permission, and the debug dump lists every window with its frame and title.

### Phase 2 — Drag, dwell, highlight (no merging yet)
- `DragMonitor`, `DropTargetResolver`, `DropZone`, and `DwellStateMachine`, with unit tests.
- `DropHighlightWindow`, including the ghost tab preview, with the tiling-preview-style fade and scale-in.
- Mouse-only event monitoring (S5). Only `AXStandardWindow` subroles are eligible targets (S6). Overlays ignore mouse events (S7).

**Demo:** dragging Finder over the middle of Safari and pausing lights up Safari. Moving away clears it.

### Phase 3 — Tabbing two windows together (the core loop)
- `TabGroup`, `GroupManager.merge`, `FrameSync`, and stacking `Concealment`.
- `TabBarWindow` with clickable tabs, Top mode only for now. `StripLayout` and `TabPlacement` are already in place so Left mode slots in next phase.
- Tear-out by dragging a tab away from the strip.
- Close × and middle-click close, with the browser rule of activating the tab to the right.
- Browser look: an attached active tab and recessed background tabs.
- **Group window buttons** (§5.11): red (close all, with confirmation), yellow (minimize the group as one Dock item, then restore), green click (Fill / return to previous size).
- Move and resize sync, member close handling.
- **Dissolve to a normal window when one is left.**
- `WindowProxy` and the snap-in, tear-out, and dissolve animations from §5.9. Snapshots stay in memory and are released right after each animation (S3).
- Re-sync inactive members only on mouse up (P3). Ignore Tabsome's own moves by expected frame (P5).
- **Quit Tabsome untabs everything and closes nothing** (§5.12): dissolve every group, un-park, cascade, then exit, with the 2-second cap.

**Demo:** the headline feature works end to end for two windows from different apps. Tearing one out leaves two normal windows with no strip.

### Phase 4 — Unlimited tabs and full tab interactions
- Add to an existing group, and merge a group into a group.
- Reorder, and drop a tab or window onto another group's **tab strip** at a chosen position, with no pause and an insertion marker (§5.2).
- Chrome-style right-click menu (§5.7), including Close Tabs to the Right.
- **"+" button** with the open-windows menu.
- Width freeze while closing tabs in a row.
- Double-click on empty strip area follows the system title-bar setting.
- **Inline tab renaming** (§5.10) in both placements, including Reset Name and ⌃⌥R.
- **Left (icon-only) tab placement**, including vertical reorder, rightward tear-out, and scrolling overflow.
- Tab width and overflow behavior for many tabs, in both placements.
- Focus sync (Cmd-Tab or a click on an inactive member activates its tab).
- Browser-layout keyboard shortcuts (⌃⌥Tab, ⌃⌥1–9, ⌃⌥W, ⌃⌥⇧N, ⌃⌥R).
- **Move & Resize flyout** on the green button (§5.11), with all presets, other displays, and the tiled-margins setting.
- Re-fit the group when macOS tiles a member window (§5.8). Group close, minimize, and fill in the Left mode right-click menu.
- **Spring-loaded tabs** and **hover previews** (§5.14), in both placements, with the icon-card fallback when Screen Recording is denied.

**Demo:** a group of 8+ windows from 5+ apps. Every interaction in §5.7 works in both Top and Left modes.

### Phase 5 — Robustness
- Corner-parking fallback for misfit windows.
- Full screen, minimize, Spaces, multiple displays.
- App quit and crash, sleep/wake, permission revoke.
- Crash-recovery file (IDs, pids, bundle IDs, and frames only; S4) and restore on next launch (P7).
- Every way Tabsome can stop from the §5.12 table: logout/restart/shutdown, pause, Sparkle relaunch, crash, and Force Quit.
- Exclusion list (defaults: System Settings dialogs, Tabsome itself, and any non-standard subroles), plus the hard-coded security list that users can't override: authorization and Keychain dialogs, password managers, and secure-input windows (S6).
- Loop detection against other window managers (P4).
- Detect Stage Manager and warn that it conflicts.
- Leak test: 100 app launches and quits with the Leaks instrument (P6).

**Demo:** the manual QA matrix (§9) passes.

### Phase 6 — Settings and polish
- **Settings › General:**
  - **Launch at login** toggle, off by default. Uses `SMAppService.mainApp.register()` / `unregister()`. The toggle reads its state from `SMAppService.mainApp.status` rather than a stored flag, so it stays correct if the user changes it in System Settings › General › Login Items. If the status is `.requiresApproval`, show a note with a button that opens Login Items.
  - **Appearance:** System (default), Light, or Dark, shown as three thumbnails like System Settings › Appearance (§5.13).
  - Pause
  - Dwell delay slider
  - Middle-zone size
  - Permission status
- **Settings › Tabs:**
  - **Tab position:** a Top / Left picker with a small preview of each (Top shows app names; Left shows icons only). Changes apply to all open groups right away.
  - Strip size (height in Top mode, width in Left mode)
  - Show close buttons
  - Show app badges on tabs (on by default)
  - Show previews when hovering tabs (on by default)
  - Ask before closing all tabs (the red button), on by default
  - Tab min width (Top mode)
- **Settings › Apps:** the list of apps Tabsome never tabs, with + / − buttons and an app picker.
- **Settings › Shortcuts:** rebind.
- **Settings › About:** version, Check for Updates…, Report a Problem…, and acknowledgements.
- **Browser parity pass:** go through every row of the §1 browser table side by side with Safari and Chrome, and fix anything that behaves differently.
- First-time hint: the first few times a window is dragged over another window's middle, a small label near the cursor says "Pause to make tabs". It stops appearing after the user has made a group twice.
- Motion pass: compare each moment in §5.9 side by side with the macOS behavior it's modeled on (screen-record both) and tune until they match. Verify with Reduce Motion on, and with Screen Recording denied (icon-card proxies).
- Accessibility: tab strip VoiceOver labels and full keyboard navigation.
- **App badges on tabs** (§5.14), with the 3-second Dock check that runs only while groups exist.
- Performance check against the §6.2 budgets in Instruments (Time Profiler, Allocations, Energy Log): 0% CPU and under 50 MB idle.
- App icon and menu bar template icon.

### Phase 7 — Ship
- **Enroll in the paid Apple Developer Program** (only needed if Tabsome will be shared beyond your own Mac).
- Developer ID signing, notarization (`notarytool`), and a stapled DMG (`create-dmg`).
- Sparkle 2 with a hosted appcast and EdDSA-signed updates (S2). The signing key is kept offline, never in the repo.
- "Report a Problem…" (in Settings › About) attaches the rotating log, shown to the user in full before sending (S4).
- Security review pass: re-check every §6.1 rule against the shipped build.
- Simple landing page and docs. Licensing or trial (e.g., free core with Pro extras) can be decided later.

## 8. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Overlay can't be ordered relative to another app's window | Phase 0 spike. Fallback: occlusion-based hide/clip of the strip |
| Apps that resize asynchronously or snap to a grid (Terminal, iTerm) | Tolerate a few pt of mismatch. Re-read the actual frame after writing it and base the group frame on what the active window really ended up as |
| Windows with min/max sizes or fixed sizes | Group frame = largest common size that fits. Misfits get corner-parked when inactive |
| AX latency or flakiness in some apps (Electron, Java), or a hung app | One thread per app with short timeouts (§6.2 P1). Retry with backoff, coalesce writes, keep AX calls off hot paths during the drag |
| Inactive tabs peek through transparent or vibrant windows | Corner-park inactive members for windows flagged as non-opaque. A per-app setting forces corner parking |
| Fights with other window managers (Stage Manager, Rectangle, macOS edge tiling) | Loop detection and back-off (§6.2 P4). Detect them and show a warning in Settings. Document it in the FAQ |
| Proxy-to-real-window swap shows a visible pop (the app's window lands late or at a slightly different size) | Wait for the AX "moved/resized" confirmation before fading the proxy, with a short timeout. Re-read the real frame and spring the proxy to it before revealing |
| User denies Screen Recording | Icon-card proxies (§5.9). Every feature still works |
| Losing windows if Tabsome crashes while windows are parked | Recovery file written on every group change. Next launch un-parks everything |
| Mission Control, App Exposé, and the ⌘Tab window list show a group's windows as **separate windows** | Expected: they really are separate windows, and macOS gives no way to merge them there. Document it in the FAQ so it isn't reported as a bug. Choosing an inactive tab's window from Mission Control is handled as a tab switch (§5.8) |
| Private `_AXUIElementGetWindow` breaks in a future macOS | Isolated behind `WindowSystem`. Fallback: match AX windows to CG windows by pid, frame, and title |

## 9. Testing strategy

- **Unit tests (XCTest / Swift Testing):**
  - `DropZone` geometry
  - `DwellStateMachine`
  - `TabGroup` operations (add, remove, reorder, activate, dissolve)
  - `StripLayout` geometry and overflow math for both Top and Left placements
  - dissolving when a group drops to one window, from every path (tear-out, close, quit)
  - **quit restore** (§5.12): no window is ever sent a close; every window ends un-parked, full size, and cascaded inside the screen's usable area; minimized windows stay minimized; the 2-second cap is respected when an app is hung
  - `LayoutPresets`: every half, quarter, fill, center, and arrange preset on single and multiple displays, with and without tiled-window margins, always against the group's outer frame; "Return to Previous Size" round trips; detecting when macOS has tiled a member
  - spring-loading timing: switches after the system delay, doesn't switch when spring-loading is off in System Settings, never accepts the drop
  - badge parsing from Dock items, and the badge timer stopping when the last group dissolves
  - hover previews: the capture stream stops when the popover closes; the fallback card appears when Screen Recording is denied
  - `AppearanceController`: System maps to `nil`, Light to `.aqua`, Dark to `.darkAqua`; the choice is saved and reapplied on launch
  - group minimize and restore: one window minimized, others parked, and everything back in place afterwards
  - browser rules: which tab activates after a close (right neighbor, else left), Close Tabs to the Right, ⌃⌥9 going to the last tab, and insert index from the cursor position on a strip
  - `TabNaming`: default app name, same-app tiebreaker, custom name winning, trimming, the 60-character limit, empty name resetting, and the name following a window across tear-out and regrouping
  - expected-frame filtering of Tabsome's own moves (P5) and loop detection (P4)
  - security eligibility: excluded and secure-input windows are never grouped or snapshotted (S6)
  - all against a fake `WindowSystem`
- **Security and stability checks:**
  - CI grep check: AX calls only in `AXWindow` / `AXApp` (S1)
  - a log-scan test that drives a session and fails if any window title or tab name appears in the log files (S4)
  - the hung-app test from Phase 0, kept as a regression test (P1)
  - the 100-app launch/quit leak test (P6)
- **Integration harness:** a small companion test app that opens N windows with known titles and sizes, so we can script merge, switch, and close scenarios through the real AX path.
- **"Is it understandable?" hallway test** (Phases 4 and 6): give Tabsome to 3–5 people who haven't seen it. Tell them only "drag a window onto another one and pause." Then ask them to switch, reorder, close, tear out, and move tabs between groups, with no other help. Anything they can't figure out on the first try is a bug, and the fix should make it more like browsers.
- **Manual QA matrix** (run each phase): Safari, Chrome, Firefox, Finder, Terminal, iTerm, VS Code, Slack, Notes, Mail, Xcode, Preview, System Settings (expect it to be rejected or parked), plus combinations:
  - same-app and cross-app groups
  - two displays
  - Spaces
  - full screen
  - quitting member apps
  - **Appearance:** every Tabsome surface (§5.13 list) in System, Light, and Dark; on System, switching macOS between light and dark (and Auto) while groups are open updates them live; Tabsome Dark on a light app window and Tabsome Light on a dark one both look deliberate; with Increase Contrast and Reduce Transparency on
  - quitting Tabsome with several groups open (including a minimized one, and one with corner-parked members): every app and window is still open afterwards, and each window is visible and separate
  - Force Quit Tabsome, then relaunch it: the recovery file restores everything
  - sleep/wake
- **Performance budget:** 0% CPU and under 50 MB idle, drag-time CPU under 5%, tab switch under 50 ms, no AX writes during the drag other than the strip itself, and zero hitches in Instruments' Animation Hitches template at 60 and 120 Hz.

## 10. Open decisions (sensible defaults chosen; revisit anytime)

1. ~~Dragging a grouped window's title bar~~ **Decided:** moves the whole group, like dragging a browser window. Single tabs come out only by dragging the tab itself.
2. **Two tabs from the same app** (e.g. two Safari windows) would both say "Safari" in Top mode. Default: show "Safari — *window title*" for those tabs only, and keep the plain app name everywhere else. The alternative is to always show just the app name and rely on the tooltip. A custom name (§5.10) always replaces either.
3. ~~Group and custom-name persistence~~ **Decided:** groups and custom tab names last **only while Tabsome is running** and the windows are open. Quitting untabs everything (§5.12), and nothing is restored on the next launch, except the crash-recovery repair, which only un-parks and un-stacks windows and never re-forms groups.
4. **Pricing/licensing:** out of scope until Phase 7.
5. **Group window buttons in Left mode:** default is none in the strip (it stays icon-only), with the actions in the right-click menu. The alternative is stacking the three buttons vertically at the top of the icon column.
6. **The app windows' own buttons** stay visible below the strip in Top mode, since Tabsome can't remove them, so a group shows two sets of buttons. Default: keep both, mapped as §5.11 describes. If that looks too busy in practice, the alternative is to lay the strip *over* the app's title bar instead of above it, hiding the app's buttons. That's harder, because every app's title bar is a different height.
7. **Name:** "Tabsome" for now. Keep the name in one place (`Info.plist` display name plus a `Brand.swift` constant) so renaming is cheap.
