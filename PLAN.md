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
4. Keep going: a group can hold **up to 50 tabs**, from any mix of apps. (A quiet safety limit: a full group simply stops accepting more, with no alert. It doesn't highlight as a drop target, shows no insertion marker, and hides its "+" button.) Dropping a window straight onto an existing tab strip adds it right away, at the spot you drop it.

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
| Safari/Chrome put the red, yellow, and green window buttons **in the tab bar, left of the tabs**, and they act on the whole window | Same in Top mode: **close all tabs, minimize the group to the Dock, and fill the screen** (click green again to go back). macOS's own tiling works on a group too: the group re-fits to the tile (§5.8, §5.11) |
| Active tab looks attached to the page; background tabs look recessed | Same: the active tab blends into the window below it, and the others are dimmer |
| "+" opens a new tab | The **"+" button** opens a menu of your other open windows; pick one to add it as a tab. It's the click alternative to dragging, and it makes the feature discoverable |
| Double-click empty space in the tab bar | Does what double-clicking a title bar does on this Mac (zoom or minimize, per System Settings) |

The one deliberate difference: **renaming** (double-click a tab). Browsers don't have it, but it's the same gesture as renaming in Finder.

Inside a group, then:
- **Window buttons** (Top mode): the usual red, yellow, and green buttons sit at the left end of the tab strip and act on the **whole group**. Red closes all tabs, yellow minimizes the group to the Dock, and green fills the screen (click again to go back). To tile a group, use macOS's own tiling on its window; the group re-fits to the tile (§5.8, §5.11).
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
| Language | Swift 6 (strict concurrency). The registry and UI are `@MainActor`; AX calls run on one thread per app and never on the main thread (§6.2 P1), delivering plain-value events to the main actor |
| UI | **AppKit** for overlay windows (precise control over level, ordering, and click-through); **SwiftUI** for the tab strip contents, menu bar menu, Settings, and onboarding |
| Minimum macOS | **26 Tahoe**. One visual style, Liquid Glass, matching current macOS exactly, with the SwiftUI `glassEffect` APIs, `MenuBarExtra`, `SMAppService`, and current ScreenCaptureKit available without fallbacks |
| Look | **Liquid Glass** throughout (§5.15): the tab strip, highlight, and menus use the system glass materials, not custom imitations |
| Window control | `ApplicationServices` AX API (`AXUIElement`, `AXObserver`) |
| Window discovery / z-order | `CGWindowListCopyWindowInfo`; `CGWindowListCreateDescriptionFromArray` for one window's live bounds during a drag (§5.6) |
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
- If `security find-identity -v -p codesigning` shows the certificate but "0 valid identities", add Apple's **WWDR G3 intermediate** (`AppleWWDRCAG3.cer` from apple.com/certificateauthority) to the login keychain. This Mac needed it (Phase 0 findings).

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
│   ├── GroupGeometry.swift       fill/return, tile detection, parking, cascade (pure, tested)
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
- If that window moves while the button is still down **and its size is unchanged since mouse-down**, it's a **title-bar drag** of that window. (Resizing from the top or left edge moves the origin too; the size check rules it out.) "Moves" is read from the **window server's bounds** for that one window on mouse-dragged events (≈0.7 ms, at most 30 times a second), which sees the move right away; an AX `moved` notification arrives 120–170 ms in and lags the real position (Phase 0, spike 3b).
- This ignores text selection, scrolling, and resizing. A resize fires `kAXResizedNotification`, which we ignore for merge purposes. Verified with no false positives in Phase 0.
- The global mouse monitor is delivered through `NSApp`'s event loop, so the main thread must never block or run a nested run loop.

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
   - Top: 32 pt off the top (a plain title bar's height, measured in Phase 0)
   - Left: 40 pt off the left

   The outer bounds (window plus strip) stay where the original window was.
2. Append the dragged window (or, if the dragged window is itself a group's active window, all of that group's tabs).
3. Use `FrameSync` to set each new member's frame to the group frame, with the size → position → size pattern for reliability.
4. Make the dropped window the active tab: raise it and activate its app.
5. Create or update the group's `TabBarWindow`.
6. Animate the snap-in with the proxy technique in §5.9.

### 5.5 Keeping inactive tabs hidden (`Concealment`)
- **Default (stacking):** inactive members share the exact frame and sit directly beneath the active window. Switching = `AXRaise` the window, then `NSRunningApplication.activate()` (`AXRaise` alone doesn't cross apps). That measured 31–34 ms median in Phase 0, with nothing showing through, and Mission Control still shows real windows.
- **Snapping apps:** some apps round the frame they're given (Terminal snaps to its character grid). The group frame is the frame the **strictest member actually took**, re-applied to the others, so no back window peeks out at an edge.
- **Members that can't get small enough** (a minimum size, or a fixed size, bigger than the group) make the **group grow to fit them**, so every tab still shares one frame. The grown group moves up or left if it would run off the screen's usable area. (Decided in Phase 5: growing beats parking, because the tab then looks like the others when it's active.)
- **Corner parking** handles the opposite case: a member that can't get *as big* as the group (a maximum or fixed size). When it's active, the other tabs would show around it, so they're moved to the screen's bottom-right corner, leaving 1 px on screen. When it's in the background, it's simply covered. This is the approach AeroSpace uses. Parked tabs return to the group frame before they're activated. Tabsome predicts which tabs would show from the size each window took the last time it was asked for the group frame.
- **Rejected options:**
  - *Minimize*: slow genie animation and Dock clutter.
  - *App hide*: hides all of that app's windows, which breaks two tabs from the same app.

### 5.6 The tab strip overlay (`TabBarWindow`)
- One `NSPanel` per group:
  - style: `.borderless` + `.nonactivatingPanel`
  - `isFloatingPanel = false`
  - `collectionBehavior = [.transient, .fullScreenNone, .ignoresCycle]`: hidden from Mission Control and App Exposé, so Tabsome never appears there as an app with windows of its own (found in Phase 4; `.managed` listed the strips). The Spaces behavior stays the default, so the strip stays on its window's Space
  - `hidesOnDeactivate = false`
  - clicks don't steal focus from the tabbed app
- **Z-order (verified in Phase 0):** the strip must sit right above the group's window but *below* any other window covering it, so we can't use a floating level. Keep it at normal level and call `order(.above, relativeTo: activeWindowCGWindowID)` whenever focus or order changes.
  - **Settle burst:** apps raise their window 40–50 ms *after* the activation and focus notifications arrive, so re-ordering once isn't enough. After any focus or activation notification for a member, check the CG order once per frame for up to 300 ms and re-order whenever the strip isn't directly above the active window. That's event-triggered, not idle polling.
  - Set `animationBehavior = .none` on overlay panels (the default fades `orderOut` for ~270 ms).
  - The occlusion-based hide/clip fallback isn't needed.
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
- Both modes handle **up to 50 tabs** (the quiet safety limit in §1) through the overflow behavior above.
- Follows the active window live during moves and resizes. **During a drag**, AX `moved` notifications are too sparse and the AX frame lags (Phase 0), so on each mouse-dragged event (at most once per display frame) the strip reads the dragged window's WindowServer bounds with `CGWindowListCreateDescriptionFromArray` (≈0.7 ms) and moves to them. Outside drags (AX-driven moves and resizes) it tracks `kAXMovedNotification`/`kAXResizedNotification`. Inactive members are re-synced on mouse up so we don't flood other apps with AX writes mid-drag. Until then they're **tucked** into a screen corner (one write each when the move or resize starts), because the moving front window no longer covers them (found in Phase 4).

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
| Right-click tab | Same order as Chrome: **Close Tab**, **Close Other Tabs**, **Close Tabs to the Right**, separator, **Move Tab to New Window** (tear it out in place), separator, **Rename Tab…**, **Reset Name** (only when renamed). With several tabs selected: **Close *N* Tabs** and **Move *N* Tabs to New Window** |
| **⇧-click / ⌘-click tabs** (added in Phase 4) | **Select several tabs**, like Chrome and Safari: ⇧-click selects the range from the anchor tab to the clicked one, ⌘-click adds or removes one tab, and a plain click goes back to one. The active tab is always selected. Selected tabs get a subtle accent tint |
| Drag a selected tab | **The whole selection comes along**, in order, and the grabbed tab becomes active. Dropped in empty space, the selected tabs become **a group of their own** there (a single tab becomes a normal window, as before); dropped on another group's strip or a window's middle (after the pause), they all move there. The 50-tab limit counts the whole selection |

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
| Active member tiled by macOS (its own green-button flyout, Window › Move & Resize, the fn-⌃ arrow shortcuts, or edge drag) | The window lands on a screen tile with no room for the strip. Detect a frame that matches a tile of `NSScreen.visibleFrame`, then **re-fit the group so the outer frame (strip plus window) fills that tile**, shrinking the window by the strip's thickness. A frame counts as a tile when each axis spans the whole usable area or one half of it, within 20 pt (enough for "Tiled windows have margins" and apps that round, and less than the strip's thickness, so a group's own frame never reads as a tile). It's checked once the window stops moving, after macOS's tiling animation. The result looks like a tiled ordinary window, which is why there's no group flyout (§5.11) |
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
1. Capture a snapshot of the window with ScreenCaptureKit (`SCScreenshotManager`). It takes 50–140 ms, so for snap-in it's **captured during the dwell**, before mouse-up.
2. Show the snapshot in a borderless overlay at the window's current frame, and animate the overlay with the spring.
3. Underneath, move the real window to its final frame with one AX write while it's hidden:
   - **cover:** when the destination is covered by the group's active window (snap-in), activate that window so the real one goes behind it, then move.
   - **park:** when nothing covers the destination (layout presets, if a group flyout returns), corner-park the real window during the spring, then move it at the end.
4. When the real window has landed (within 8 pt and unchanged across two polls, never an exact match), take a **second snapshot at the final size** (ScreenCaptureKit captures covered windows) and cross-fade the proxy's contents to it during the spring. A snapshot stretched to a new size reads as "scaled up" (seen in Phase 0), so **the picture is never scaled** (Phase 6e): it stays at its real size, anchored top-left, and the frame's new area fills with the window's own edge color, like a live resize. A second snapshot counts only once the app has painted the window's far edges.
5. Retarget the spring to the frame the window actually took (apps like Terminal round it), then raise the real window and fade the proxy out over 0.1 s.

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

### 5.11 Group window buttons
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

**No Move & Resize flyout (dropped for now, 2026-10-21).** The plan had a copy of the macOS green-button menu on the group's green button, since the system's own menu only acts on the window that owns it. It's dropped because macOS's tiling already reaches groups: when the active window is tiled, the group re-fits so its outer frame (strip plus window) fills the tile (§5.8). So the window's own green-button menu, Window › Move & Resize, the fn-⌃ arrow keys, and edge drags all tile the whole group, and they keep matching whatever macOS offers. Hovering the group's green button shows its glyph but opens nothing; a click fills and a second click returns. A copy with halves, quarters, other displays, Return to Previous Size, and proxy-animated presets can come back later if it's missed.

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

**Timing:** all of this happens in `applicationShouldTerminate`. Tabsome replies `.terminateLater`, then confirms once the windows are restored. The restore is capped at **2 seconds** in total, so a hung app (§6.2 P1) can't stop Tabsome from quitting; any window that didn't respond is fixed by the recovery file on the next launch. The windows fan out through proxies with `Motion.snappy` (instant under Reduce Motion; Phase 6e).

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
- the group window buttons
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
- **How:** the Dock's own items expose their badge text through Accessibility (the status label of each Dock item). macOS sends no notification when a badge changes, so this is the one place Tabsome checks on a timer: **every 3 seconds, only while at least one group exists, on a background thread, reading only the Dock's item list** (one call for the list, then one for each item's kind, bundle, name, and badge). The timer stops when the last group dissolves. This is a deliberate, narrow exception to the "no polling" rule (§6.2 P2) and the "window attributes only" rule (§6.1 S1).
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
- **Popovers and menus** (the "+" menu, hover previews, rename field in Left mode, right-click menus) use the standard system popover and menu styles, so they match whatever the system draws.
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
| S3 | **Screen Recording** (optional, for animations and hover previews) can see anything on screen | Capture **only the windows being animated or previewed, one window per capture**: `SCScreenshotManager` stills for animations (the picture before it moves and, once the app has redrawn, one at the final size; Quit's fan-out takes one per tab it moves), and a low-rate stream of that one window that runs only while a hover preview is open. Held **in memory only** and released as soon as the animation ends or the preview closes. Never written to disk and never sent anywhere. Windows that block capture (password managers, DRM video) are excluded by ScreenCaptureKit and fall back to the icon card. Keep the permission optional, partly because recent macOS versions periodically ask users to re-confirm Screen Recording access | 1 (onboarding), 3 (proxies), 4 (previews) |
| S4 | **Window titles can be sensitive** (email subjects, document names, URLs), and so can custom tab names | `os.Logger` marks titles and tab names `.private`, and the file log never records them. The crash-recovery file stores only window IDs, pids, bundle IDs, and frames. "Report a Problem" shows the user everything before it's sent. **No telemetry and no network traffic besides Sparkle update checks** | 1 (logging), 5 (recovery file), 7 (reporting) |
| S5 | Input monitoring could look like (or become) a keylogger | Monitor **mouse button and drag events only**, never keystrokes. Hotkeys use `RegisterEventHotKey` (through KeyboardShortcuts), which doesn't need the Input Monitoring permission. Tabsome never asks for Input Monitoring | 2 |
| S6 | Tabbing or snapshotting a security-sensitive window | A **hard-coded exclusion list that users can't override**: SecurityAgent and other authorization dialogs, Keychain prompts, password manager windows, and any window shown while secure input is on (`IsSecureEventInputEnabled`). Only `AXStandardWindow` subroles are eligible at all | 2 (eligibility), 5 (full list) |
| S7 | Overlays catching clicks meant for another app | The tab strip sits **outside** the window's frame. The drop highlight and window proxies set `ignoresMouseEvents = true`. Nothing Tabsome draws ever covers another app's content while it can receive clicks. **One narrow exception:** Left mode's rename field sits beside the tab, over the window's edge, only while the user is typing a name they asked to change; any click elsewhere, Return, or Esc ends it (Phase 7d) | 2, 3 |
| S8 | A larger blast radius because Tabsome isn't sandboxed | Disk writes only to Tabsome's own `Application Support`, `Logs`, `Preferences`, and `Caches` (Sparkle's downloads) folders, plus a problem report saved where the user picks in a save panel (Phase 7a). No network access besides Sparkle. No URL scheme in v1 (if one is added later, every parameter gets validated and every command is something a user could safely trigger from a webpage) | 1 |

### 6.2 Performance and stability

| # | Risk | Rule | Phase |
|---|---|---|---|
| P1 | **A frozen app freezes Tabsome.** AX calls are synchronous messages to the target app, and they block until the messaging timeout if that app is hung (1.5 s by default on macOS 27; older docs say 6 s) | Set `AXUIElementSetMessagingTimeout` to about 0.5 s on every element. Run **each app's AX work and AXObserver on its own thread**, so a hung app only stalls its own thread. The main thread never makes AX calls; it only receives results. If an app keeps timing out, mark it "unresponsive", ignore it until it recovers, and leave its tabs alone. (This only works one way: Tabsome can't freeze other apps, because they never wait on it) | 1 |
| P2 | Idle CPU and battery drain | Everything is event-driven, with **no polling and no repeating timers while idle**. The one exception is the Dock badge check (§5.14): every 3 s, one call, only while a group exists. With no groups, nothing runs at all. `CGWindowListCopyWindowInfo` runs only during an active drag, at most 30 times a second. The single-window bounds query that keeps the strip on a dragged window (§5.6) runs only during that drag, at most once per display frame. The post-activation settle burst (§5.6) runs at most 300 ms per focus change. The display link runs only while something is animating. Budget: **0% CPU and under 50 MB of memory when idle** | 1, checked in 6 |
| P3 | Making other apps redraw too much | During a drag or resize, only Tabsome's strip moves live. Inactive members are tucked into a screen corner when it starts (they'd be exposed otherwise) and re-synced **once, on mouse up**: two writes per tab per interaction. Stacking (the default way of hiding inactive tabs) lets macOS tell covered windows they're hidden so apps like Safari slow their rendering. Corner-parked windows still count as visible, so parking stays the fallback, never the default | 3 |
| P4 | **Fights with other window managers** (Rectangle, Stage Manager, an app's own window code) looping and burning CPU | **Loop detection:** if a member's frame is changed against Tabsome more than 3 times in 2 s, stop writing to it, remove it from its group, and show a one-time notice naming the app. (2 s, not the 1 s first planned: Tabsome's own debounce re-places a window at most about 4 times a second, so 1 s could miss a real fight.) | 5 |
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

#### Phase 0 findings (2026-10-19, macOS 27.0.1, Xcode 27.1, Swift 6.4)
Spikes live in `Spikes/` (see its README). They're one host app, `TabsomeSpikes.app`, so the permissions are granted once, plus a cooperative `SpikeHelper.app`. Raw logs: `Spikes/out/logs/`. **Both exit questions are answered: the strip uses `order(.above, relativeTo:)` (no occlusion fallback needed), and inactive tabs are hidden by stacking.**

| # | Spike | Result | Key measurements | Chosen approach / plan change |
|---|---|---|---|---|
| 1 | AX move/resize | ✅ Safari, Chrome, Firefox, Finder, Terminal, VS Code (Electron), Notes, TextEdit. Xcode: only its fixed-size welcome window (move works, size not settable). ⚠️ **Slack and a Java app aren't installed, so they're untested**; VS Code covers Electron. | Move call 0.4–10 ms, lands in ≤3.5 ms. Resize call 3–42 ms, lands in ≤26 ms. Terminal snaps to its character grid (asked 807×458, got 804×454). Notes enforces a ~680 pt minimum height. `AXEnhancedUserInterface` was off in every app. | Size → position → size works everywhere. Treat "can't set size" (Xcode welcome) and min-size clamps (Notes) as misfits → corner parking (§5.5). Re-read the frame after every write (§8). |
| 2 | `_AXUIElementGetWindow` | ✅ 17/17 standard windows mapped, with pid and bounds matching CGWindowList. Only the Finder desktop (`AXDesktop`) has no ID, as expected. | 0.16 ms average, ≤1 ms max. | Use it as planned. ⚠️ CGWindowList reports **interpolated bounds during a window's open animation** (≈0.5 s), so the registry must not compare AX and CG frames for a just-created window until it settles. |
| 3 | **Overlay z-order** | ✅ **Primary approach works.** A normal-level, non-activating `NSPanel` with `order(.above, relativeTo: otherAppsWindowID)` sits directly above the other app's window. Other apps' windows cover it, and `relativeTo` is honoured even when the target is behind another window. Clicking the strip doesn't activate Tabsome or steal focus. Verified with Terminal/Finder, Safari/VS Code, Chrome/Safari, VS Code/Notes, and by hand. | ⚠️ **Race found:** the activation notifications (`AXApplicationActivated`, `AXFocusedWindowChanged`, `NSWorkspace.didActivate`) arrive 6–22 ms after activation, but the app raises its window 40–50 ms after. Re-ordering only on the notification left the strip **behind** the covering window (Safari: 82/82 samples). | **Settle burst:** after any focus or activation notification for a group member, re-check the CG order once per frame for up to 300 ms and re-order whenever the strip isn't directly above the active window. That brought the strip to ≤1 wrong sample (≈1 ms) in every pair. It's event-triggered, not idle polling (P2). Strip panels need `animationBehavior = .none`; with the default, `orderOut` fades for ~270 ms. |
| 3b | Strip following a live drag | ⚠️ AX `moved` notifications during a drag are sparse (10–15 per multi-second hand drag) and the AX frame lags the real window by a median 22–82 pt, so a strip driven by them visibly lags (hand-checked). Mouse-delta prediction "ran ahead": the window only starts moving after a 13–41 pt drag threshold and then doesn't track the cursor 1:1 (up to 57 pt off). | WindowServer bounds per window through `CGWindowListCreateDescriptionFromArray` cost 0.6–0.9 ms median (≤10 ms max). | **During a detected drag, set the strip from the dragged window's WindowServer bounds on each mouse-dragged event** (at most once per display frame). Hand check: "slight trail" (about one frame). Velocity extrapolation is an optional Phase 3 refinement. Changes §5.6 and §6.2 P2. |
| 4 | Title-bar drag detection | ✅ No false positives. Synthesized Terminal + Finder: 12/12 (title-bar drag, content/text selection, bottom-right / top-left / left-edge resize, stationary click). By hand (Safari, Chrome, VS Code): 3/3 drags, 2/2 resizes, 13/13 clicks and selections correctly NONE. | First `moved` arrives 120–170 ms after the drag starts (fine against the 450 ms dwell). The resize zone extends a few pt **outside** the window's frame, so the hit test picks the window behind; that's harmless (the resize notifications go to a different window, so it's NONE). | §5.1 as planned, plus one rule: a `moved` counts as a drag only if the window's **size is unchanged** since mouse-down. `NSEvent.addGlobalMonitorForEvents` works (605 vs 608 events against a listen-only CGEventTap). ⚠️ Global monitors are delivered through `NSApp`'s event loop, so **never block the main thread in a nested run loop** (spin waits silently starve them). |
| 5 | Stacking concealment | ✅ Instant enough, and nothing shows through: 0 of ~5,300 samples during switching had any other window or the desktop on top of the stack. Hand check: no flicker on the final run (one earlier run looked like a flash, most likely the active/inactive title-bar change any app switch has). | `AXRaise` + `NSRunningApplication.activate()`: **24/24 switches**, median 31–34 ms, max 58 ms. `AXFrontmost = true`: 7/12 (Terminal), 12/12 (Safari/Code). `AXRaise` alone: 6/12 (it doesn't cross apps). | Switching = `AXRaise` the window, then `NSRunningApplication.activate()`; cooperative activation doesn't block an LSUIElement app on macOS 27. The tab-switch budget is 50 ms median (§9), since the max is set by the app. Grid-snapping apps (Terminal) end up a few pt off the group frame, so a back window can peek out at an edge. The group frame becomes **the snapped frame the strictest member actually took**, applied to everyone else (§8). |
| 6 | Proxy animation | ✅ Mechanism works in Safari, Terminal, and VS Code. ⚠️ Hand check: during a size change the proxy looks **"scaled up"**, because the snapshot is stretched to the new size. A cross-fade fix is built, but the hand comparison was too fast to judge, so it **needs a slow side-by-side check in the Phase 3 motion pass**. | `SCShareableContent` 20–35 ms + `SCScreenshotManager` capture 28–107 ms (the first capture is the slowest). The real window lands 16–53 ms after the AX write. Terminal lands 2×6 pt off the target. Spring (`perceptualDuration 0.3, bounce 0.15`) settles in 442 ms. Re-raise 1–45 ms. | **Pre-capture during the dwell** (the dragged window is known before mouse-up). Two choreographies: **cover** (destination covered by the group's window: activate the cover, move the real window behind it, spring, raise, fade) and **park** (nothing covers the destination: corner-park, spring, move, wait for landing, fade). Landing = within 8 pt and unchanged for two polls, never an exact match. **Cross-fade to a second snapshot taken at the final size** (ScreenCaptureKit captures the covered window) so nothing is shown stretched at rest. Retarget the spring to the real landed frame before revealing. Changes §5.9. |
| 7 | Hung-app isolation | ✅ Helper blocked its main thread for 10 s. With one thread and run loop per app and a 0.5 s timeout: Terminal and Finder workers kept working (95 ops each, max 6 ms), and the main thread's max heartbeat gap was 18 ms. | Hung app's calls return `cannotComplete` after 505 ms. Marked unresponsive at 0.54 s, recovered 0.58 s after the hang ended, with back-off to 1 probe/s. Control: a naive main-thread AX call blocked the main thread 1.5 s (that's the default timeout seen on macOS 27; the plan assumed 6 s). | §6.2 P1 as planned. |
| 8 | macOS look | ✅ Recorded in `Spikes/Findings/Metrics.swift` (to move into the app in Phase 1). | Window buttons 14 pt, 23 pt pitch (9 pt gap); inset 9 / centre 16 in a plain 32 pt title bar (12/20 compact, 19/26 in Safari's and Finder's 52 pt toolbar). Native tab bar 28 pt, Finder tab buttons 24 pt. Corner radius 16 pt. AX reports buttons as 16×16 (1 pt hit slop). | **Top strip height = 32 pt** (a plain title bar), so the group buttons sit exactly where macOS puts them. The plan's earlier 28 pt was a guess (§5.4). Left strip stays 40 pt (no system equivalent to measure). |
| 9 | Cross-app drag destination | ✅ A background app's non-activating panel gets `draggingEntered` and keeps getting `draggingUpdated` (84–233 per hover) after returning no operation. Spring-loading raised the background window mid-drag, and the drop landed in it (automated, cross-process). By hand: Finder file → strip turned teal after ~0.5 s → dropped in a folder, landed. | Spring fires 515–531 ms after entering. `performDragOperation` never called. | §5.14 as planned. Register for file URLs, URLs, strings, images, PDF, RTF/HTML, and file promises; return `[]` from `draggingEntered`/`Updated`; override `wantsPeriodicDraggingUpdates` (true). |

**Setup notes for Phase 1:**
- **Signing:** the free Personal Team certificate was "not valid" until Apple's **WWDR G3 intermediate** was added to the login keychain (only the 2023-expired one was present). After that, the designated requirement is `identifier … and certificate leaf = Apple Development: …`, and both TCC grants survived ~20 rebuilds. Grants made while the app was ad-hoc signed didn't carry over; the entries had to be removed and re-added once.
- **"Prefer tabs: Always"** is set on this Mac (`AppleWindowTabbingMode`). AppKit apps merge new windows into **native** tabs, and the background native tabs **aren't exposed as AX windows**. Tabsome treats a natively tabbed window as one window. Phase 1's test-harness app must set `tabbingMode = .disallowed` (SpikeHelper had to).
- **Language mode:** spikes compile in Swift 5 mode with the Command Line Tools `swiftc` (the Xcode license wasn't accepted yet). Product code is Swift 6 strict concurrency in an Xcode project, as planned.

### Phase 1 — Foundation
- **git repository** (this folder isn't one yet) with a Swift/Xcode `.gitignore`. Commit `PLAN.md` first.
- Xcode project, Swift 6, deployment target **macOS 26**, hardened runtime, no sandbox, `LSUIElement = YES`.
- **Icons are already supplied:**
  - `Tabsome/AppIcon.icon` is the **Icon Composer** app icon (Liquid Glass, with light, dark, and tinted versions generated by the system). Add it to the app target and set the target's App Icon to `AppIcon`; it takes precedence over the PNG set.
  - `Tabsome/Assets.xcassets` has a flat PNG `AppIcon` (all ten macOS sizes, kept as a fallback) and `MenuBarIcon` (a template image, 16/32 px). Add the catalog to the target and use `MenuBarIcon` for the `MenuBarExtra`.
  - Sources are in `Design/Icon/` (see its README). Both compile together with `actool` for macOS 26 with no warnings.
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

#### Phase 1 status (2026-10-20): done
Everything above is built (see `README.md` for build, run, and test commands). Verified on this Mac:
- **Demo:** the menu bar icon (badged while Accessibility is missing), onboarding through all three steps (by hand), and the debug dump listing every app's windows with frame, subrole, main/minimized/full-screen flags, and title. It matched an independent CGWindowList/AX census.
- **Permission survives a rebuild:** a build with a new build number changed the binary's hash, and Accessibility stayed granted. Signing is manual (Apple Development identity, team `DM9Y3M74XK`) with **no provisioning profile**, so nothing expires. The only entitlement is the debug-only `get-task-allow`, with hardened runtime on.
- **Live tracking:** an app launched after Tabsome started (TextEdit) was picked up with its window.
- **Hung app (P1):** with a test app frozen at Tabsome's launch, Tabsome's main thread stayed on time, every other app was tracked, the frozen app was flagged unresponsive, and it was picked up with its windows once it answered again. This found and fixed a bug: a timeout during setup was treated as "still launching" and could give up for good.
- **S1:** `scripts/check-ax-usage.sh` runs as the first build phase and is covered by tests (passes on the tree, fails on a planted violation). **S4:** no window title from the dump appears in the logs. **S8:** writes go only to `~/Library/Logs/Tabsome` and `~/Library/Application Support/Tabsome` (the debug dump).
- 14 unit tests (Swift Testing): registry events against a fake `WindowSystem`, appearance mapping and persistence, log rotation, and the S1 check.

Notes for later phases:
- The registry also records non-standard windows (e.g. a browser's small `AXUnknown` popups). Phase 2's eligibility filter (`isStandard`, S6) keeps them out of grouping.
- Launch at login and the Appearance picker are built, but not exercised by hand yet. Turning on Launch at login from a debug build registers that build's path.
- Quitting currently just stops the registry; "untab everything, close nothing" (§5.12) arrives with groups in Phase 3.

### Phase 2 — Drag, dwell, highlight (no merging yet)
- `DragMonitor`, `DropTargetResolver`, `DropZone`, and `DwellStateMachine`, with unit tests.
- `DropHighlightWindow`, including the ghost tab preview, with the tiling-preview-style fade and scale-in.
- Mouse-only event monitoring (S5). Only `AXStandardWindow` subroles are eligible targets (S6). Overlays ignore mouse events (S7).

**Demo:** dragging Finder over the middle of Safari and pausing lights up Safari. Moving away clears it.

#### Phase 2 status (2026-10-20): done
Built in `Core/Drag/` (`DragMonitor` with a pure `DragClassifier`, `DropTargetResolver`, `DropZone`, `DwellStateMachine`, `Eligibility`, `DragCoordinator`, `TabLabel`) and `UI/Overlays/` (`OverlayPanel`, `DropHighlightWindow`). Verified:
- **Demo by hand:** Finder over Safari's middle with a pause lights Safari up with the glass highlight and a ghost strip ("Safari", "Finder"). Moving off the middle clears it. The highlight's look was approved.
- **Synthesized, against the real app:** drag start → armed after the pause → disarmed off the middle → drag end; release while armed logs a drop (the Phase 3 hook); a 0.2 s pause never arms. Captures confirmed the highlight sits directly above the target and below the dragged window.
- **Idle:** 0.0% CPU, 25 MB footprint, about one wakeup per sample. During a drag, CGWindowList is read at most 30 times a second, and the dwell uses a one-shot timer (the cursor is still, so no events arrive).
- **S5:** only left-mouse down/dragged/up are monitored. **S6:** only standard, non-minimized, non-full-screen windows of non-excluded apps can be dragged or targeted, and nothing happens while secure input is on; the hard-coded list starts with authorization, Keychain, password-manager, and system apps (Phase 5 completes it). **S7:** the highlight panel ignores mouse events.
- 44 unit tests in total, 30 new: dwell transitions (jitter, restart, arm, leave, drop, cancel, configurable dwell), zone geometry, target resolution (skips the dragged window, Tabsome's overlays, ineligible popups, and non-normal layers), drag vs. resize classification, eligibility, and tab labels (app name; "App — title" when two tabs share an app).

Notes for later phases:
- Resolving the target follows §5.2 literally: windows under the cursor that can't be tabbed (a browser's small popup, for example) are skipped, so the window behind them can still be the target.
- The tab strip zone (no dwell, insertion marker) needs groups, so it arrives in Phase 4 as `armedOnStrip(target:insertIndex:)` in the same state machine.
- The highlight uses the system accent color, so it's gray here, where the accent is Graphite.

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

#### Phase 3 status (2026-10-20): done
Built in `Core/Groups/` (`TabGroup`, `GroupManager`, `GroupGeometry`, `ExpectedFrames`) and `UI/Overlays/` (`TabBarWindow`, `TabStripView`, `WindowControlsView`, `StripLayout`, `WindowProxy`). Window commands (set frame, set position, raise, close, minimize) run on each app's AX thread and report the frame the window actually took. Verified:
- **By hand:** merge, switching, hover, moving the group (title bar and empty strip area), resize, yellow minimize/restore, green Fill/return, red with its confirmation, tear-out, ⌘Tab focus sync, and Quit all worked.
- **Synthesized, against the real app:** merge (strip 1000×32 directly above the active window), clicking a tab raises that window with the strip above it, middle-click closes the tab's window and dissolves the group (the last window grows back to the outer frame), tear-out leaves the window at the drop point at the group's size, and Quit restored 3 windows (active keeps the outer frame, the others cascade 22 pt) and exited in 0.41 s, with nothing closed.
- **Window buttons follow the system:** under the Graphite accent all three are grey, as on real windows. The greys were measured on this Mac (Dark: focused #939495 vs. Finder's #949596, unfocused #535353 vs. #555555; Light from AppKit's own buttons). They update live when the accent changes.
- 74 unit tests in total: `TabGroup` browser rules, `StripLayout` for both placements, frame reconciliation for snapping apps, Fill/return, the quit cascade, expected-frame filtering (P5), the button colors, and `GroupManager` end to end against a fake window system (merge, switch, close → right neighbor, dissolve, tear-out, own moves ignored, follow the active window, full screen leaves, minimize parks, quit closes nothing).

Bugs found by testing the real app and fixed:
- **Strip frame collapsed to 0×0** a moment after placement: a SwiftUI hosting view as a panel's content view resizes its window to the view's ideal size. Overlay panels now host SwiftUI inside a plain container (`OverlayPanel.setHostedContent`).
- **Quit could hang:** when Quit was triggered from a main-queue block, AX completions and the 2-second cap, both delivered through the main dispatch queue, never ran inside Quit's nested run loop. They now go through the main run loop in common modes, and the cap is a run-loop timer.

Also built here, ahead of Phase 4: activating an inactive tab's app (⌘Tab, a click) counts as a tab switch, a member entering full screen leaves its group, and a window can be dropped onto an existing group to add a tab. Without the first two, stacked tabs would break as soon as you clicked around.

Deviations and notes for later phases:
- On Quit, windows move into the cascade instantly; animating them needs one proxy per window (Phase 6 motion pass). *Done in 6e.*
- Fill and return are instant; animating them through proxies is left for the Phase 6 motion pass (the flyout that would have brought it was dropped in 4c). *Done in 6e.*
- Small notches can show where the strip's square bottom corners meet the window's rounded top corners (Phase 6 polish). *Fixed in Phase 4 by the corner fillets.*
- Grouped windows can't yet be dropped onto another group (Phase 4: merge a group into a group).
- Synthesized checks activate other apps' windows, so they can catch the user's keystrokes; run them only while hands are off the keyboard (it happened once, harmlessly, with a scratch file).

### Phase 4 — Many tabs (up to 50) and full tab interactions
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
- Re-fit the group when macOS tiles a member window (§5.8). This replaces the planned Move & Resize flyout copy, dropped for now (§5.11). Group close, minimize, and fill in the Left mode right-click menu.
- **Spring-loaded tabs** and **hover previews** (§5.14), in both placements, with the icon-card fallback when Screen Recording is denied.

**Demo:** a group of 8+ windows from 5+ apps. Every interaction in §5.7 works in both Top and Left modes.

#### Phase 4 progress
Built in four parts, each committed once checked by hand: **4a** tab management, **4b** renaming, shortcuts, and Left placement, **4c** re-fitting groups to macOS tiles, and **4d** spring-loaded tabs and hover previews.

**4a (2026-10-20): done.** Verified by hand:
- dropping a window onto a strip at a position (no pause, with an insertion marker)
- sideways reorder
- moving a tab between groups, and tearing it onto another window's middle
- merging a whole group into another
- "+" with the open-windows menu
- the right-click menu (Close Tab, Close Other Tabs, Close Tabs to the Right, Move Tab to New Window)
- the width freeze while closing tabs
- double-clicking the empty strip area (follows System Settings' title-bar action)
- icon-only tabs and the » overflow menu
- the quiet 50-tab limit: a full group isn't a drop target, shows no marker, and hides "+"

Found by hand and fixed:
- **Background tabs showed during moves and resizes:** they were only hidden by the front window, so moving it exposed them. They're now tucked into a screen corner for the duration (P3, §5.6).
- **Parked windows could spill onto another display:** corner parking now picks a corner where the window doesn't land on another display (this also affected yellow-minimize).

101 unit tests in total. New ones cover:
- the strip layout (full → icon-only → overflow, with the active tab always visible), insertion indexes, and the width freeze
- the `TabGroup` limit, insert, move, and close-others/right
- the dwell machine's strip cases
- strip targets in the resolver
- group-into-group merges, drops at a strip position, reorder, Move Tab to New Window, and the "+" candidates
- tucking, and parking-corner choice across displays

Deferred, by plan: rename items in the right-click menu (4b), and Left mode's "Close Tabs Below" wording (4b).

**4b (2026-10-20): done.** Checked by hand and approved:
- renaming: double-click a tab, the right-click menu, or ⌃⌥R. Names are trimmed and capped at 60 characters, and clearing a name restores the window title. Losing focus saves what has been typed so far; Esc cancels.
- the ⌃⌥ shortcuts (next/previous tab, tabs 1–8, last tab, close, move to a new window, rename). They're registered only while a group is focused (S5).
- Left placement in two styles, set in Settings › Tabs: **Compact** (icons, with the name tooltip and a × badge on hover) and **With names** (a 180 pt column with icon, name truncated with "…", and ×). Left mode's menu says "Close Tabs Below".
- multi-select: ⇧-click selects a range and ⌘-click toggles a tab. The selection can be torn off into a new group, moved onto another group's strip, closed, or moved to a new window together.
- Mission Control: overlay panels are `.transient`, so they no longer show up as a separate app (§5.6).
- corner fillets: the strip's glass extends into the gaps outside the window's rounded corners.

Found by hand and fixed:
- **One window stayed outside after a multi-tab merge:** an app sometimes moves a window again after Tabsome places it. Groups now ignore that for one second after Tabsome moves them, then run a settle check that puts any stray member back.
- **Hover didn't work in Left mode:** the cursor's coordinates were flipped twice.
- **The fillet band would have caught clicks meant for the app's title bar:** the strip now uses two panels: a click-through glass panel directly above the window, and the clickable strip above that.

123 unit tests in total. The new ones cover:
- selection
- the Left layouts
- renaming and committing a rename
- the shortcuts' actions
- multi-tab tear-off and moves
- the settle check
- the fillet geometry

**4c (2026-10-21): done.** The Move & Resize flyout copy was dropped for now (§5.11). In its place, a group re-fits to a tile when macOS tiles its active window (§5.8). Checked by hand, in Top and Left modes:
- the window's own green-button menu, Window › Move & Resize (halves, quarters, Fill), the fn-⌃ arrow keys, and an edge drag all tile the whole group, strip included
- the background tabs land in the same tile
- ordinary moves and resizes are unchanged

Also fixed: ending a title-bar drag no longer re-sends the active window's frame. That write could land after macOS tiled the window and undo the tile.

128 unit tests in total. The new ones cover tile detection, with and without margins, and check that a group's own frame never reads as a tile. They also test the re-fit itself.

**4d (2026-10-23): done. Phase 4 is complete.** Checked by hand in Top and in both Left styles:
- **Spring-loaded tabs (§5.14).** A drag from any app over a background tab switches to it after the system's spring-loading delay (0.5 s here), with a blink just before. The drop lands in the window underneath. If spring-loading is off in System Settings, so is this.
- **Hover previews (§5.14).** Hovering a background tab for 0.6 s opens a glass popover with a live picture of that window, streamed at about 5 fps. Once one is open, moving to another background tab swaps it instantly. A click closes it until the pointer moves to another tab, and leaving the strip resets it. The stream runs only while the popover is open. Without Screen Recording, the popover shows the app's icon instead.
- Background tabs skip their tooltip while previews are on.
- Settings › Tabs has a new switch, "Show previews when hovering tabs" (on by default).

Found and fixed:
- **The Settings window scrolled after switching panes.** Its grouped forms have no fixed height. Each pane is now held to its content height with scrolling off, so the window fits each pane, like the system's Settings windows.
- **A first fix for that crashed on opening Settings.** It measured each pane's height and set it, which became a layout feedback loop that AppKit aborts. The fix that shipped stores nothing.
- **Debug builds** gained the `com.tabsome.debug.settings` notification, which opens Settings for scripted layout checks.

147 unit tests in total. The new ones cover:
- spring-loading timing: the system delay, the blink, a reset when the drag moves to another tab, and the off setting
- the preview timer: the delay, instant swaps, clicks, and leaving the strip
- popover placement in both placements, kept on screen
- the capture stream stopping when a preview closes or swaps
- frames from a previous tab being ignored
- the icon card when Screen Recording is missing

Not done: app badges on tabs (§5.14) belong to a later phase.

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

#### Phase 5 progress
Built in four parts, each committed once checked by hand:
- **5a:** the recovery file and every way Tabsome can stop
- **5b:** misfits, full screen, Spaces and displays, sleep/wake, app quit and crash, and permission revoke
- **5c:** exclusions, the security list, loop detection, and Stage Manager
- **5d:** the leak test and the QA matrix

**5a (2026-10-23): done.** Checked by hand:
- **Force Quit and relaunch:** the next launch undoes the leftover groups, the same way Quit does. The windows fan out, the active one stays on top, and nothing closes.
- **Pause** (Settings › General): every group is undone, the menu bar icon dims, and no new groups form. Unpausing doesn't bring the old groups back. The setting survives a relaunch.
- **Quit:** windows fan out and the recovery file is deleted.
- **Accessibility turned off and back on:** the groups are let go where they are, then undone once the permission returns.

How it works:
- **The recovery file** is `recovery.json` in Application Support. It holds window IDs, pids, bundle IDs, the outer frame, and the minimized flag; no titles or names (S4). It's saved 0.3 s after groups change, so a drag writes it once, and it's removed when there are no groups.
- **Recovery on launch** waits up to 3 s for the recorded windows to show up in the registry. It restores only windows whose ID still belongs to the same pid, and skips any the user has already tabbed again.
- **A quit restore that hits the 2 s cap** keeps the file, so the next launch fixes the window that didn't answer.
- **Logout, restart, and shutdown** take the same `applicationShouldTerminate` path as Quit.
- **Sparkle's relaunch** will too, once Sparkle is added in Phase 7.

Found and fixed: the quit restore counted windows as it sent each move. An app that answered at once could bring the count to zero early and report "all done" while windows were still to come. Every move is now counted before any is sent.

156 unit tests in total. The new ones cover:
- the recovery state's contents (and that no titles reach it)
- coalesced saves
- recovery: restoring, waiting for windows, a reused window ID, and a minimized group
- the save/load/delete round trip
- a quit restore that runs out of time

**5b (2026-10-26): done.** Checked by hand:
- **A member that can't get small enough** (Notes' minimum height in a short group) makes the group grow to its size. Every tab shares the frame, and nothing goes to a corner.
- **Corner parking** for background tabs that would show around a smaller active tab (§5.5).
- **The strip follows its window across Spaces** and hides with its app (⌘H).
- **Display changes:** a group left off-screen moves onto a screen, and every group re-syncs.
- **Sleep/wake:** groups, strips, and tabs come back as they were.
- **App quit and crash** were already handled: the app's tabs are removed, and a group of one dissolves.

How it works:
- **Prediction:** each member's last answer to the group frame (asked for, took) predicts what it will take next. Bigger means a minimum held it; smaller means a maximum held it.
- **Growing:** `GroupGeometry.reconcile` grows the group to the largest minimum, then `keepOnScreen` keeps the grown outer frame inside the usable area.
- **Concealment** runs after every sync and tab switch. The settle check leaves misfits and parked tabs alone.
- **Strips:** they re-check where their window is 0.15 s after a Space change, hide/unhide, or app activation. They use CGWindowList's on-screen list, and order out and back in to join the current Space.
- **Displays:** `didChangeScreenParameters` moves a group that's less than half on any screen with `refitToScreens`, re-parks parked tabs on the group's current screen, and re-syncs.
- **Wake:** the registry re-reads every app's windows, keeping its entries, and the groups are re-validated 1.5 s later.

Decided here: grow the group to a member's minimum size rather than park that member (the user's call). A group can't be resized below that minimum, and it keeps its grown size if that member leaves.

173 unit tests in total. The new ones cover:
- size prediction and covering
- moving a group back onto a screen
- growing to a minimum, and staying on screen
- parking around a smaller active tab, and coming back in order
- the settle check leaving misfits alone

**5c (2026-10-26): done.** Checked by hand:
- **Settings › Apps** (pulled forward from Phase 6 at the user's request): a list of apps Tabsome never tabs. It starts with System Settings. The + button lists the running apps and has **Choose App…** for any installed app, and − removes the selection. Adding an app takes its windows out of their groups at once, each cascaded as its own window; nothing closes. Excluded apps can't be dragged into groups and aren't offered by "+".
- **Stage Manager:** a warning in Settings › General with a button to Desktop & Dock, plus a one-time notice at launch while it's on. It's read from `com.apple.WindowManager` › `GloballyEnabled`.

Also built, and covered by the tests:
- **The security list** (S6) now covers authorization, Touch ID, Keychain, the Passwords app, 14 password managers, system surfaces (Dock, Control Center, Spotlight, Stage Manager, screenshot UI), and Tabsome itself. Users can't override it, and the Apps pane's footer says so.
- **Secure input:** no window capture while it's on, for proxies or previews. Hover previews fall back to the icon card.
- **Loop detection (P4):** a move that lands within 1 s of Tabsome placing the window, with no mouse down, counts against it. More than 3 in 2 s takes the window out of its group and shows a one-time notice naming the app. Notices are remembered in `shownNotices`.

182 unit tests in total. The new ones cover:
- the security list and the user's list
- fight counting, and a fight removing the window
- exclusion removing windows from groups and from "+"

**5d (2026-10-27): done. Phase 5 is complete.**

**Leak test (P6):** `scripts/leak-test.sh` launches and quits SpikeHelper 100 times while Tabsome runs. SpikeHelper uses its "quiet" role, launched hidden, so it never takes focus. The script compares Tabsome before and after:

| | Before | During | After |
|---|---|---|---|
| Threads | 12 | 13 (the helper's AX thread) | 12 |
| Open files | 68 | 68 | 68 |
| Footprint | 51 MB | 51 MB | 51 MB |
| `leaks` | | | 0 leaks |

The 100 cycles took 84 s. Idle CPU afterwards was 0.0%.

**QA matrix (§9)** checked by hand, adding to what 5a–5c covered:
- Chrome, Firefox, Terminal, VS Code, Mail, Xcode, Preview, and Notes, in same-app and cross-app groups
- System Settings refused (it's excluded by default)
- full screen leaving a group
- quitting a member's app
- the Appearance settings, including live light/dark switching, Increase Contrast, and Reduce Transparency
- quitting Tabsome with a minimized group and one with a parked tab: every window comes back open and separate

iTerm and Slack aren't installed, so they're untested.

**Found by hand and fixed:** a window that can't take the group's size (Calculator) seemed to zoom up to the group's size and back when it joined, left, or was torn out. The animation proxy was springing to the group frame. Proxies now spring to `landing(_:at:)`, the size the window will actually take according to its last answer (§5.9 step 5). A torn-out tab's ghost and its landing use that size too. A window's last answer is now kept across groups and forgotten only when the window closes.

**For Phase 6:** the 51 MB footprint was measured on a long-running copy that had opened Settings. That's just over the 50 MB idle budget (P2), so it should be measured on a fresh launch in Phase 6's performance check.

184 unit tests in total.

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
- **Settings › Apps:** the list of apps Tabsome never tabs, with + / − buttons and an app picker. *(Built early, in Phase 5c.)*
- **Settings › Shortcuts:** rebind.
- **Settings › About:** version, Check for Updates…, Report a Problem…, and acknowledgements.
- **Browser parity pass:** go through every row of the §1 browser table side by side with Safari and Chrome, and fix anything that behaves differently.
- First-time hint: the first few times a window is dragged over another window's middle, a small label near the cursor says "Pause to make tabs". It stops appearing after the user has made a group twice.
- Motion pass: compare each moment in §5.9 side by side with the macOS behavior it's modeled on (screen-record both) and tune until they match. Verify with Reduce Motion on, and with Screen Recording denied (icon-card proxies).
- Accessibility: tab strip VoiceOver labels and full keyboard navigation.
- **App badges on tabs** (§5.14), with the 3-second Dock check that runs only while groups exist.
- Performance check against the §6.2 budgets in Instruments (Time Profiler, Allocations, Energy Log): 0% CPU and under 50 MB idle.
- App icon and menu bar template icon: **supplied** (`Tabsome/AppIcon.icon`, `Tabsome/Assets.xcassets`, sources in `Design/Icon/`). Check them in the Dock, Finder, Settings, and the menu bar in light, dark, and tinted, and tune the glyph's glass and translucency in Icon Composer if needed. Delete the PNG `AppIcon` set if nothing uses it.

#### Phase 6 progress
Built in six parts, each committed once checked by hand:
- **6a:** the rest of Settings › General and Tabs: dwell delay, middle-zone size, permission status, strip size, close buttons, asking before Close All, and tab min width
- **6b:** app badges on tabs, with the 3-second Dock check and its setting
- **6c:** Settings › Shortcuts (rebinding; adds the KeyboardShortcuts package) and Settings › About
- **6d:** the first-time hint, VoiceOver labels, and keyboard navigation
- **6e:** the motion pass: the animated quit cascade, Fill and return through proxies, the strip's corner notches, Reduce Motion, and Screen Recording denied
- **6f:** the browser parity pass, the performance check (from a fresh launch), and the icons

Check for Updates… and Report a Problem… stay in Phase 7 with Sparkle and the log viewer.

**6a (2026-10-27): done.** Checked by hand: every setting below, at every strip size, and the snap-in fix.
- **Settings › General** gains:
  - **Making tabs:** "Pause before tabbing" (0.2–1 s, 0.45 s by default) and "Middle of a window" (30–70% of each side, 50% by default). Both take effect from the next drag.
  - **Permissions:** Accessibility and Screen & System Audio Recording, each with a green check when allowed, or a button to open Privacy & Security.
- **Settings › Tabs** gains:
  - **Strip size:** Small, Medium (the measured size), or Large. Top is 28/32/38 pt tall, compact Left 34/40/48 pt wide (icons 24/28/34), and Left with names 150/180/220 pt wide. A change re-lays out every open group the way a placement change does: the outer frame stays put and the windows take what's left.
  - **Minimum tab width** (Top only, 60–200 pt, 90 by default): narrower than this, tabs show only icons.
  - **Show close buttons on tabs** (on by default). Off, tabs have no ×; the right-click menu still closes them.
  - **Ask before closing all tabs** (on by default), the same setting as the alert's "Don't ask again".
- Settings reopens on the pane it was left on.
- Debug builds take two more scripted hooks, so layout can be checked without synthesized mouse input: `com.tabsome.debug.group` ("target,dragged" window IDs) and `com.tabsome.debug.strip` ("size[,placement]"). `com.tabsome.debug.settings` can name a pane.

Found and fixed during the hand check: adding a small window (Finder) to a big group (Safari) showed the small snapshot stretched up to the group's size for the whole spring, then swapped it. The proxy now cross-fades to a snapshot at the final size as soon as one arrives, while the spring is still running (§5.9 step 4: the window has already landed behind the cover, so it can be captured at once). The size spring no longer bounces, so the picture doesn't overshoot its final size.

Checked by script: every strip size in Top, Left, and Left with names, on a real group. 192 unit tests in total. The new ones cover each size's thickness and frame round trip, Medium matching the measured metrics, the tab min width deciding when names give way to icons, and the middle-zone size.

**6b (2026-10-27): done.** Checked by hand with real Dock badges in every strip style, and the setting. App badges on tabs (§5.14):
- **Where badges come from:** `Core/AX/DockBadges.swift`, the one file besides `AXWindow` and `AXApp` allowed to call AX (the S1 check already named it). It reads the Dock's app items on its own thread with the usual 0.5 s timeout: one call for the item list, then one per item for its kind, bundle, name, and badge. Nothing else is read from the Dock or any other app, and badge text is never logged.
- **When:** `BadgeMonitor` reads once as soon as the first group forms, then every 3 seconds, and stops when the last group goes or the setting is turned off. A read only redraws the strips when something changed.
- **Matching:** a Dock item belongs to an app by its bundle's location (by name only for an item with no URL). Every tab from that app shows the badge. Two running copies of the same app share one Dock item as far as Tabsome can tell, so they show the same badge.
- **Look:** the Dock's red with white text.
  - Top: a pill after the tab's name, or on the icon's corner when tabs are icon-only.
  - Left: on the icon's top-right corner, like the Dock; × takes its place on hover.
  - Left with names: a pill before the ×.
  - Big counts show as "9999+" in a pill and "99+" on an icon, never as a cut-off number. Other long text gets an ellipsis.
  - VoiceOver reads it as the tab's value ("Badge: 3").
- **Settings › Tabs › Show app badges on tabs** (on by default).
- SpikeHelper gained a `badge` role: one window with a Dock badge, changed by a distributed notification.

Checked by script: a real Dock badge reaches the tabs in Top, Left, and Left with names, changes within 3 s, clears, and caps. With a group open, Tabsome used about 20 ms of CPU in 30 s. 199 unit tests in total. The new ones cover matching Dock items to apps, capping long badges, the monitor reading at once and then on its timer, and the Dock being read only while a group exists.

**6c (2026-10-27): done.** Checked by hand: the shortcuts, rebinding, conflicts, Restore Defaults, the on/off toggle, relaunch, and About.
- **KeyboardShortcuts 3.1.0** (SPM, up to the next major version) now registers the tab shortcuts. It still uses Carbon's `RegisterEventHotKey`, so there's no Input Monitoring permission and Tabsome never sees other keystrokes (S5). The keys are registered only while a group is focused, as before, through its global `isEnabled`.
- **Settings › Shortcuts:** a **Use keyboard shortcuts** toggle at the top (on by default, added at the user's request during the hand check). Off, Tabsome never takes any keys, even while a group is focused, and the fields below are dimmed. Then every tab shortcut, in two sections: switching (Next, Previous, Tab 1–8 in two columns, Last) and the active tab (Close, Move to New Window, Rename). Click a field and press new keys, or clear it to turn that shortcut off. A key macOS already uses gets KeyboardShortcuts' warning; a key another tab shortcut has is refused, naming it. **Restore Defaults** brings back the ⌃⌥ browser layout. The choices live in UserDefaults under `KeyboardShortcuts_tabsome_<action>`.
- **Settings › About:** the icon, version, a one-line description, and Acknowledgements (KeyboardShortcuts, with its website and MIT license). Check for Updates… and Report a Problem… come in Phase 7.

Checked by script: both panes fit without scrolling. 203 unit tests in total. The new ones cover the default layout, every action having its own title and keys, and conflicts between actions.

**6d (2026-10-27): done.** Checked by hand: the hint (and that it retires after two groups), and the strips with VoiceOver.
- **First-time hint:** while a window is dragged by its title bar over another window's middle, a small glass label by the cursor says "Pause to make tabs", then "Let go to make tabs" once the highlight shows. It never shows over a tab strip (the insertion marker says enough) or for torn-out tabs. Every drop into a window or strip counts; after two, it's gone for good (`hintGroupsMade` in UserDefaults).
- **VoiceOver on the strips:**
  - The strip window is a floating window titled "Tabs" (AppKit called it a "system dialog"), holding one "Tabs" group whose actions are Close All Tabs, Minimize, and Fill (Left mode has no buttons for these).
  - Each tab is one element: its label, "2 of 5" (plus ", badge 3"), selected when active, and the window's title as the hint. Pressing it switches to it.
  - Each tab's actions: Close Tab, Close Other Tabs, Move Tab Left/Right (Up/Down in Left mode), Move Tab to New Window, and Rename Tab. So nothing needs a drag or a right-click, which also covers reordering from the keyboard.
  - The + and » menus read as "Add a Window as a Tab" and "More Tabs". The glass panel, the insertion marker, the hint, the highlight, proxies, and decorative icons are hidden from VoiceOver.
- **Keyboard:** the tab shortcuts (6c) cover switching, closing, moving out, and renaming. Neither Safari nor Chrome on the Mac has default keys for reordering tabs, so there are no new global shortcuts; VoiceOver's actions cover it. Settings and onboarding use standard controls, which Full Keyboard Access already reaches.
- The spikes app gained `axdump`, which prints an app's accessibility tree, and `axdump <app> press <label> [n] [action]`.

Checked by script: the accessibility tree in Top and Left, pressing a tab through accessibility to switch, and Move Tab Right. 207 unit tests in total. The new ones cover when the hint shows and what it says, and the tab's VoiceOver value.

**6e (2026-10-27): done.** Checked by hand: Fill and return, Quit and Pause, snap-in both ways, and Reduce Motion.
- **Fill and return** animate through a proxy, the "park" choreography (§5.9). Every tab steps into the screen's corner while a picture of the active one springs to the new frame and the strip glides along. The active window is resized while it waits, so the picture switches to one at the final size during the spring. Then the windows move in and the picture fades. A second click waits until the first is done.
- **Quit and Pause** fan the tabs out through proxies (§5.12). Each window's picture springs from the group frame to its place in the cascade while the real windows stay stacked out of sight; then the windows move and the pictures fade. Quit waits in a nested run loop, so this path uses only callbacks and common-mode run-loop timers, never a task. All the captures happen at once and wait at most 0.35 s (late ones get icon cards). The 2 s cap still covers everything. Minimized groups and corner-parked tabs just move.
- **Pictures are never scaled.** A proxy shows its snapshot at its real size, anchored top-left, over the window's own edge color (sampled from the snapshot), so a growing or shrinking proxy looks like a live resize rather than a zoom. This also fixes the leftover stretch on snap-in. A final-size snapshot is used only once the app has painted the window's far edges (up to 4 tries, 60 ms apart); a capture taken right after a resize can be blank beyond the old size.
- **The size doesn't bounce** in any proxy spring; position keeps `Motion.snappy`'s small bounce.
- **Reduce Motion:** snap-in, tear-out, new groups, and Fill no longer travel. The picture stays put and cross-fades away over 0.2 s as the real window appears in its new place. Quit stays instant (§5.12).
- **Screen Recording denied:** the icon card's color fills the proxy as it moves and the icon stays centered at its own size, instead of the whole card being stretched.
- **The strip's corner notches** were already fixed in Phase 4 by the corner fillets.
- Debug builds: `com.tabsome.debug.fill` (a window ID) clicks its group's green button, and `TabsomeDebugNoCapture` acts as if Screen Recording were denied. The spikes app gained `mouse burst`, which captures a screen region several times in a row. SpikeHelper's `badge` and `quiet` windows are now opaque, so animation checks see real edges.

Checked by script, frame by frame: Fill, return, the quit fan-out, and Fill with icon cards, with no stretched frames. 210 unit tests in total. The new ones cover the edge color and the painted-capture check.

**6f (2026-10-27): done.** Checked by hand: Esc during tab and window drags, dropping tabs back on their own strip, and the icons. Phase 6 is complete.
- **Browser parity:** every row of the §1 table is implemented. Checking each against Chrome found two differences, now fixed:
  - **Esc cancels a drag**, as in Chrome. During a tab drag it sends the tab back. During a window drag over a target it removes the highlight, and letting go then won't tab the window (macOS still moves it). Esc is a Carbon hot key registered only while there's something to cancel (S5: no Input Monitoring), so it reaches apps the rest of the time.
  - **A torn-out tab dragged back over its own strip** shows the insertion marker and goes in at that spot. Before, it went back to where it started, or became its own window when let go more than 20 pt from the strip.
- **Performance** (§6.2), measured with `footprint` and the process's CPU time on a 5K display:
  - Fresh launch, idle: **21 MB**, and no CPU used in a minute.
  - A group open, idle: 31 MB; 0.06 s of CPU a minute, the 3-second Dock badge check (§5.14).
  - After opening every Settings pane: 47 MB, staying there after Settings closes. Tabsome's live heap is only 24 MB; the rest is fragmented malloc pages from SwiftUI, which `malloc_zone_pressure_relief` doesn't return (tried, it freed nothing). With a group open and Fill on a full 5K screen as well, it reached 54 MB (a full-screen capture is about 60 MB while it lasts).
  - So the budget holds at idle and in normal use, but a long session with Settings and large animations ends a little over it. Drag-time CPU and Animation Hitches need Instruments by hand.
- **Icons:** the Icon Composer icon (`AppIcon.icon`) is the whole app icon. Without the PNG `AppIcon` set the built `AppIcon.icns` was byte-for-byte the same, so the PNG set is deleted. The menu bar glyph renders as a template image. The icon in dark and tinted appearances is a hand check.

213 unit tests in total. The new ones cover moving a torn-out tab, or a selection, back into its own strip at the marker.

**After Phase 6 (2026-10-28):** unit tests run inside the app, and they had been writing into the user's real log (`~/Library/Logs/Tabsome`). `AppPaths` now points a test run's log and Application Support at a throwaway folder in the temporary directory, so test runs never touch the user's log or recovery file. A test checks that no path a test run uses is under `~/Library`.

### Phase 7 — Ship
- **Enroll in the paid Apple Developer Program** (only needed if Tabsome will be shared beyond your own Mac).
- Developer ID signing, notarization (`notarytool`), and a stapled DMG (`create-dmg`).
- Sparkle 2 with a hosted appcast and EdDSA-signed updates (S2). The signing key is kept offline, never in the repo.
- "Report a Problem…" (in Settings › About) attaches the rotating log, shown to the user in full before sending (S4).
- Security review pass: re-check every §6.1 rule against the shipped build.
- Simple landing page and docs. Licensing or trial (e.g., free core with Pro extras) can be decided later.

#### Phase 7 progress
Decided (2026-10-28):
- **Signed and notarized under the company's team:** "ALOYSIUS, BUTLER & CLARK ASSOCIATES, INC.", Team ID `Y6BK74SSGR`. The company's name appears on the signature and in macOS's first-launch dialog. Moving off the personal team changes Tabsome's signature, so macOS asks for Accessibility (and Screen Recording) again, once.
  - The user is an Admin with access to the team's **cloud-managed Developer ID certificate**, so there's no Developer ID certificate on this Mac: Apple signs during export. Release signing is `xcodebuild archive`, then `xcodebuild -exportArchive -allowProvisioningUpdates` with export options `method developer-id`, `signingStyle automatic`, `teamID Y6BK74SSGR`. A test export (scratch only) came out signed "Developer ID Application: ALOYSIUS, BUTLER & CLARK ASSOCIATES, INC. (Y6BK74SSGR)", hardened runtime on, no `get-task-allow`, and passed `codesign --verify --deep --strict`.
  - Notarization uses a `notarytool` keychain profile named `tabsome` (`xcrun notarytool store-credentials tabsome --apple-id … --team-id Y6BK74SSGR`, with an app-specific password the user enters). Confirm it exists before 7b notarizes.
- **Hosting:** DMGs as GitHub Release assets and Sparkle's appcast on GitHub Pages, both in `abcagency/tabsome`. The repo was private, which kept release downloads behind a login, so it was made public on 2026-10-28 (a scan of the full history found no secrets or personal email; every commit uses the GitHub noreply address). A separate public releases repo was tried and deleted.
- **Report a Problem…** saves the log to a file the user picks, after showing it in full (S4). Tabsome sends nothing itself.

Built in five parts, each committed once checked by hand:
- **7a:** Report a Problem… (Settings › About): the log shown in full, then saved where the user chooses
- **7b:** Developer ID signing of Release builds, notarization with `notarytool`, stapling, and the DMG, from one release script
- **7c:** Sparkle 2: the package, EdDSA keys (the private key stays in the login keychain, never in the repo), Check for Updates…, the appcast on GitHub Pages, and the relaunch path through the quit restore
- **7d:** the security review pass: every §6.1 rule re-checked against a notarized build
- **7e:** the landing page and docs on GitHub Pages

**7a (2026-10-28): done.** Checked by hand. Settings › About › **Report a Problem…** opens a sheet:
- A box for what happened, then the rest of the report exactly as it will be saved: a few facts and the whole rotating log, oldest file first. The facts are versions, the Mac model, display count, both permissions, paused, group and tab counts, every Tabs and General setting, whether shortcuts are on, the number of excluded apps (not their names), Stage Manager, and Reduce Motion.
- Nothing in it can hold a window title or tab name (S4): the log never records them, and the facts are counts and choices. The one app detail is a bundle ID (like `com.apple.Safari`) on the log line for an app that keeps fighting Tabsome over a window, the same kind of data the recovery file keeps (found in 7d).
- **Save Report…** opens a save panel ("Tabsome Report 2026-10-28.txt"), writes the file where the user picks, and shows it in Finder. Tabsome sends nothing; the user attaches the file to an email or message. That save is the one file Tabsome writes outside its own folders, and only where the user chose (S8).
- The report view is an AppKit text view, so a full log (up to about 4 MB) scrolls without lag; the description is kept apart so typing never rebuilds it.

218 unit tests in total. The new ones cover the report's order and layout, reading the log files oldest first, and the file name.

**7b (2026-10-28): done.** Checked by hand: installed from the DMG, opened without a Gatekeeper warning, and worked like the dev build. `scripts/release.sh [version]` makes a release:
1. **Archive** the Release configuration. Its build number is the commit count, so each release is newer for Sparkle. Only the app's Release configuration uses the company team (automatic signing, `Y6BK74SSGR`). Debug builds stay on the personal Apple Development certificate, so everyday builds keep their Accessibility and Screen Recording permissions.
2. **Export** with Developer ID through the team's cloud-managed certificate (`scripts/ExportOptions.plist`).
3. **Check** the signature: Developer ID of the team, hardened runtime on, no `get-task-allow`, and `codesign --verify --deep --strict`.
4. **Notarize** the app (`notarytool`, profile `tabsome`) and **staple** it.
5. **Build the DMG** with `hdiutil` (APFS, compressed): the app and an Applications link. `create-dmg` wasn't needed, so there's no extra tool to install.
6. **Notarize and staple the DMG**, then check with Gatekeeper: the app, the DMG's ticket, and the app inside the mounted DMG.

`--no-notarize` stops after the signed export. The DMG itself isn't code-signed: signing anything outside Xcode's export needs a Developer ID certificate on this Mac, and the team's is cloud-managed. Gatekeeper checks a downloaded disk image's notarization, and the app inside is signed, notarized, and stapled, so this is enough. If the team later puts a Developer ID certificate on this Mac, the script can sign the DMG too.

First release built: `Tabsome-0.1.0.dmg`, version 0.1.0 (27), 3.6 MB. Both notarizations were accepted in under a minute; Gatekeeper says "Notarized Developer ID" for the app on its own and inside the DMG.

Also fixed two compiler warnings the Release build showed (a deprecated `String(cString:)`, and an unneeded `nonisolated(unsafe)`).

**Debug builds are "Tabsome Dev"** (added during the 7b hand check, at the user's request). Both builds had the bundle ID `com.tabsome.app`, and macOS keeps one Privacy & Security entry per bundle ID, tied to the first signature it saw, so granting the release copy took the permission away from the dev build. Debug builds are now `com.tabsome.app.dev`, and the app itself is **Tabsome Dev.app** (product name "Tabsome Dev", Swift module still `Tabsome`; System Settings' list shows the bundle's name, not its display name, so a display name alone left two entries called "Tabsome"): a separate app to macOS, with its own Accessibility and Screen Recording entries, settings, logs (`~/Library/Logs/Tabsome Dev`), and recovery file. `Brand.name` reads the display name, so onboarding names the right entry. The user's settings were copied to the new ID once. Release builds are unchanged: `com.tabsome.app`, "Tabsome".

**7c (2026-10-28): done.** Checked by hand, including a real update from 0.1.0 to 0.1.1.
- **Sparkle 2.10.0**, pinned exactly (2.10.1 was three days old; dependency bumps are reviewed, S2). Release builds start the updater; Tabsome Dev doesn't, so a dev build never replaces itself with a release.
- **The key:** EdDSA, generated into the login keychain under the account `tabsome` (not Sparkle's default account, which another project could share). The public key is in `Config/Info.plist`, merged into the generated Info.plist. The private key is never in the repo, and `.gitignore` blocks key files. Back it up off this Mac: losing it means existing users can't get signed updates.
- **Info.plist:** the feed at `https://abcagency.github.io/tabsome/appcast.xml`, the public key, no system profiling, **a signed feed required** (`SURequireSignedFeed`: an edited feed can't point at an older signed version or change the notes), and **updates verified before they're unpacked** (`SUVerifyUpdateBeforeExtraction`).
- **In the app:** Settings › About has **Check for Updates…** and "Check for updates automatically" (Sparkle asks on the second launch first). A scheduled check that finds an update while the user is in another app doesn't open a window; the menu shows **Update Available…** (Sparkle's gentle reminders for background apps). Installing quits Tabsome through the usual restore (§5.12), then opens the new version.
- **`scripts/release.sh`** now also signs the final, stapled DMG with the Sparkle key, adds its entry to `docs/appcast.xml` (`scripts/appcast.py`: newest first, notes from `docs/releases/<version>.md` as Markdown), signs the feed, and verifies both signatures. It publishes nothing.
- **`scripts/publish.sh <version>`** is the only step that makes anything public, and it asks first: it pushes main, creates the GitHub release with the DMG and notes, then commits and pushes the feed. The DMG goes up before the feed, so the feed never points at a missing file.
- Checked by script: a Release export embeds Sparkle signed with the team's Developer ID (hardened runtime), the Info.plist carries the feed settings, and a test feed signs, re-signs, and verifies.
- **Published 0.1.0 (30)** on 2026-10-28, at the user's go-ahead: GitHub Pages turned on (`main`, `/docs`, HTTPS enforced), release `v0.1.0` with the DMG, and the feed. `publish.sh --yes` skips the prompt for an already-approved publish (its prompt needs a terminal). Checked after: the live feed matches the repo and its signature verifies; the DMG downloads without a login, its SHA-256 matches the build (`09226737…`), and it verifies against the update signature in the feed.
- **A generic icon in Privacy & Security** for the release copy (found in the hand check): macOS's app database had nine copies of `com.tabsome.app` registered, seven of them already gone (DMG mounts, the script's staging and checks, archive leftovers), and System Settings picked a missing one. The stale ones were unregistered, and `release.sh` now unregisters every copy it makes (`lsregister -u`).
- **Published 0.1.1 (34)** to test updating (release notes: a maintenance release; the project's version is now 0.1.1). An installed 0.1.0 found it through Check for Updates…, showed the notes, quit through the usual restore (tabs came apart, nothing closed), and reopened as 0.1.1 with its permissions intact. The scheduled check's Update Available… menu item wasn't triggered by hand; it needs a day-long wait.

**7d (2026-10-28): done.** Security review, read and accepted by the user. Every §6.1 rule re-checked against the shipped 0.1.1 (34), as installed by the update, and against the source:
- **S1** holds. The AX usage check passes. Tabsome reads only window-level attributes (position, size, title, role and subrole, minimized, full screen, main, close button) and writes only position, size, and minimized; its only actions are raise and the close button's press. The only place that reads an element's children is `DockBadges.swift`, and only the Dock's item list.
- **S2** holds. Notarized Developer ID ("Notarized Developer ID" from Gatekeeper); hardened runtime on every binary inside the app, with no entitlements that loosen it (no library-validation or JIT exceptions; Sparkle's helper carries only its own app identifier). No URL scheme, AppleScript dictionary, or usage-description keys. Sparkle 2.10.0 and KeyboardShortcuts 3.1.0 pinned in `Package.resolved`. Updates: HTTPS feed, EdDSA-signed DMG and feed, verified before unpacking. Sparkle's two XPC services ship unused (they're for sandboxed apps); harmless, left as is.
- **S3** holds, with the rule's wording updated: each capture is one window (`desktopIndependentWindow`), never the screen, held in memory only; nothing captures without the permission or while secure input is on; the preview stream runs at 5 frames a second only while a preview is open. No image is ever written to disk.
- **S4** holds. The file log records window numbers, pids, group IDs, counts, and frames, never titles or tab names; one line (a window manager fighting Tabsome) records the other app's bundle ID. `os.Logger` lines carry only pids, counts, and states. Tabsome's own code has no networking at all (no `URLSession` in the binary); Sparkle's feed check is the only traffic, with system profiling off. The 7a note's "no app names" claim was corrected.
- **S5** holds. The only global monitor is left mouse down, dragged, and up. Shortcuts and Esc are Carbon hot keys; the two local key monitors in the binary are KeyboardShortcuts' recorder, which only sees keys typed into Tabsome's own Settings. Nothing asks for Input Monitoring.
- **S6** holds: the hard-coded security list and the secure-input checks in dragging, previews, and captures, all covered by tests.
- **S7** holds, with one exception now written into the rule: Left mode's rename field sits over the window's edge while the user is typing a name.
- **S8** holds, with the rule's wording updated: besides its own Application Support, Logs, and Preferences, Tabsome's `Caches` folder holds Sparkle's downloads, and a problem report goes where the user picks. Debug-only code (the distributed-notification hooks, debug defaults, the registry dump) is absent from the release binary.

**7e (2026-10-28): done.** Reviewed by the user and live. The landing page and docs are one static page, `docs/index.html`, served by GitHub Pages at https://abcagency.github.io/tabsome/ next to the update feed:
- The hero (icon, tagline, **Download for Mac**), an illustration of a tabbed window drawn in CSS, how it works in three steps, what works like browser tabs, the keyboard shortcuts, install steps, privacy, and an FAQ. The FAQ covers the two items §8 asked for (Mission Control and ⌘Tab showing separate windows; Stage Manager), plus windows that won't tab, quitting, reporting a problem, and uninstalling.
- The Download button reads the newest release from `appcast.xml` on the same site, so the page never needs editing for a release. Without it, the button goes to the latest GitHub release.
- No build step, no third-party scripts or fonts, no analytics, and no cookies, in keeping with S4. Light and dark follow the system; at phone width nothing scrolls sideways.
- The README now links the site, describes Tabsome Dev, and documents `release.sh` and `publish.sh`.


## 8. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Overlay can't be ordered relative to another app's window | **Resolved in Phase 0:** `order(.above, relativeTo:)` works with another app's window, plus the post-activation settle burst (§5.6). The occlusion-based hide/clip fallback isn't needed |
| Apps that resize asynchronously or snap to a grid (Terminal, iTerm) | Tolerate a few pt of mismatch. Re-read the actual frame after writing it and base the group frame on what the active window really ended up as |
| Windows with min/max sizes or fixed sizes | The group grows to the largest minimum size among its members. Background tabs that would show around a smaller active tab (a maximum or fixed size) get corner-parked |
| AX latency or flakiness in some apps (Electron, Java), or a hung app | One thread per app with short timeouts (§6.2 P1). Retry with backoff, coalesce writes, keep AX calls off hot paths during the drag |
| Inactive tabs peek through transparent or vibrant windows | Corner-park inactive members for windows flagged as non-opaque. A per-app setting forces corner parking |
| Fights with other window managers (Stage Manager, Rectangle, macOS edge tiling) | Loop detection and back-off (§6.2 P4). Detect them and show a warning in Settings. Document it in the FAQ |
| Proxy-to-real-window swap shows a visible pop (the app's window lands late or at a slightly different size) | Wait for the AX "moved/resized" confirmation before fading the proxy, with a short timeout. Re-read the real frame and spring the proxy to it before revealing |
| User denies Screen Recording | Icon-card proxies (§5.9). Every feature still works |
| Losing windows if Tabsome crashes while windows are parked | Recovery file written on every group change. Next launch un-parks everything |
| Mission Control, App Exposé, and the ⌘Tab window list show a group's windows as **separate windows** | Expected: they really are separate windows, and macOS gives no way to merge them there. Document it in the FAQ so it isn't reported as a bug. Choosing an inactive tab's window from Mission Control is handled as a tab switch (§5.8). Tabsome's own overlays (strips, highlight, proxies) are hidden from Mission Control (§5.6) |
| Private `_AXUIElementGetWindow` breaks in a future macOS | Isolated behind `WindowSystem`. Fallback: match AX windows to CG windows by pid, frame, and title |

## 9. Testing strategy

- **Unit tests (XCTest / Swift Testing):**
  - `DropZone` geometry
  - `DwellStateMachine`
  - `TabGroup` operations (add, remove, reorder, activate, dissolve)
  - `StripLayout` geometry and overflow math for both Top and Left placements
  - dissolving when a group drops to one window, from every path (tear-out, close, quit)
  - **quit restore** (§5.12): no window is ever sent a close; every window ends un-parked, full size, and cascaded inside the screen's usable area; minimized windows stay minimized; the 2-second cap is respected when an app is hung
  - tile detection: halves, quarters, and fill, with and without tiled-window margins; a group's own content frame never reads as a tile; a re-fit moves every member to the tile minus the strip
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
