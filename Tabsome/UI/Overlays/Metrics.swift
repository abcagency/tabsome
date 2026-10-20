// Every size, spacing, and radius Tabsome draws with (PLAN.md §5.15), measured in Phase 0
// (spike 8) on macOS 27.0.1. A future macOS update means adjusting this one file.
//
// Sources: our own NSWindows (standardWindowButton frames, contentLayoutRect, _cornerRadius),
// real Safari / Finder / Terminal / Notes windows through AX, and alpha scans of
// ScreenCaptureKit captures. AX reports window-button frames as 16×16 with a 7 pt gap: that is
// the 14 pt button plus 1 pt of hit area on each side, so the visual values below use 14 / 9.

import CoreGraphics

enum Metrics {
    // Window buttons (red / yellow / green)
    static let windowButtonDiameter: CGFloat = 14
    static let windowButtonPitch: CGFloat = 23          // centre to centre; 9 pt gap between buttons
    static let windowButtonLeadingInset: CGFloat = 9    // plain 32 pt title bar (Terminal, Notes)
    static let windowButtonCenterFromTop: CGFloat = 16  // plain 32 pt title bar
    // Toolbar windows put the buttons lower and further in:
    //   .unifiedCompact (40 pt): inset 12, centre 20
    //   .unified / Safari / Finder (52 pt toolbar): inset 19, centre 26

    // Bars
    static let titleBarHeight: CGFloat = 32             // plain title bar
    static let compactToolbarHeight: CGFloat = 40
    static let toolbarHeight: CGFloat = 52              // Safari, Finder
    static let nativeTabBarHeight: CGFloat = 28         // NSTabBar (Finder tabs, AppKit window tabs)
    static let nativeTabButtonHeight: CGFloat = 24      // Finder tab buttons, 1 pt apart

    // Top-mode strip: same height as a plain title bar, so the group buttons sit exactly where
    // macOS puts them (inset 9, centre 16) and the strip reads as the window's title bar.
    static let topStripHeight: CGFloat = titleBarHeight
    static let leftStripWidth: CGFloat = 40             // not measured (no system equivalent); plan §5.6
    /// Left mode "With names": a fixed width, so windows don't resize as tabs come and go;
    /// longer names get an ellipsis.
    static let leftNamedStripWidth: CGFloat = 180

    // Shape
    static let windowCornerRadius: CGFloat = 16         // NSWindow._cornerRadius, all styles; captures ≈17 incl. antialiasing
}
