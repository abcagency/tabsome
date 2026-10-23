import CoreGraphics
import Testing
@testable import Tabsome

struct SpringLoaderTests {
    @Test func switchesAfterTheSystemDelayWithABlinkJustBefore() {
        var s = SpringLoader(enabled: true, delay: 0.5)
        #expect(s.update(tab: 7, now: 10) == nil)
        #expect(s.update(tab: 7, now: 10.3) == nil)
        #expect(s.update(tab: 7, now: 10.36) == .blink(7))
        #expect(s.update(tab: 7, now: 10.45) == nil)
        #expect(s.update(tab: 7, now: 10.5) == .activate(7))
        #expect(s.update(tab: 7, now: 11) == nil) // once per hover
    }

    @Test func movingToAnotherTabStartsOverAndEndsTheBlink() {
        var s = SpringLoader(enabled: true, delay: 0.5)
        _ = s.update(tab: 7, now: 0)
        #expect(s.update(tab: 7, now: 0.4) == .blink(7))
        #expect(s.update(tab: 8, now: 0.45) == .endBlink)
        #expect(s.update(tab: 8, now: 0.9) == .blink(8))
        #expect(s.update(tab: 8, now: 0.96) == .activate(8))
    }

    @Test func leavingTheTabsBeforeTheDelayDoesNothing() {
        var s = SpringLoader(enabled: true, delay: 0.5)
        _ = s.update(tab: 7, now: 0)
        #expect(s.update(tab: nil, now: 0.2) == nil)
        #expect(s.update(tab: nil, now: 2) == nil)
        #expect(s.reset() == nil)
    }

    @Test func offInSystemSettingsMeansOff() {
        var s = SpringLoader(enabled: false, delay: 0.5)
        _ = s.update(tab: 7, now: 0)
        #expect(s.update(tab: 7, now: 5) == nil)
    }

    @Test func aSlowerSystemDelayIsFollowed() {
        var s = SpringLoader(enabled: true, delay: 1.2)
        _ = s.update(tab: 3, now: 0)
        #expect(s.update(tab: 3, now: 0.6) == nil)
        #expect(s.update(tab: 3, now: 1.1) == .blink(3))
        #expect(s.update(tab: 3, now: 1.2) == .activate(3))
    }

    @Test func theDragEndingMidBlinkEndsTheBlink() {
        var s = SpringLoader(enabled: true, delay: 0.5)
        _ = s.update(tab: 7, now: 0)
        _ = s.update(tab: 7, now: 0.4)
        #expect(s.reset() == .endBlink)
    }
}

struct HoverPreviewTimerTests {
    @Test func opensAfterTheDelay() {
        var t = HoverPreviewTimer()
        t.pointer(tab: 5, inStrip: true, now: 0)
        #expect(t.shown == nil)
        #expect(t.deadline == HoverPreviewTimer.delay)
        t.pointer(tab: 5, inStrip: true, now: 0.3) // moving within the tab doesn't restart the wait
        t.tick(now: 0.59)
        #expect(t.shown == nil)
        t.tick(now: 0.6)
        #expect(t.shown == 5)
    }

    @Test func swapsRightAwayOnceOpen() {
        var t = HoverPreviewTimer()
        t.pointer(tab: 5, inStrip: true, now: 0)
        t.tick(now: 1)
        t.pointer(tab: 6, inStrip: true, now: 1.1)
        #expect(t.shown == 6)
        t.pointer(tab: nil, inStrip: true, now: 1.2) // over the active tab: hidden, but still warm
        #expect(t.shown == nil)
        t.pointer(tab: 5, inStrip: true, now: 1.3)
        #expect(t.shown == 5)
    }

    @Test func leavingTheStripResets() {
        var t = HoverPreviewTimer()
        t.pointer(tab: 5, inStrip: true, now: 0)
        t.tick(now: 1)
        t.pointer(tab: nil, inStrip: false, now: 1.1)
        #expect(t.state == .idle)
        t.pointer(tab: 6, inStrip: true, now: 2)
        #expect(t.shown == nil)
    }

    @Test func aClickClosesItUntilThePointerMovesToAnotherTab() {
        var t = HoverPreviewTimer()
        t.pointer(tab: 5, inStrip: true, now: 0)
        t.tick(now: 1)
        t.click(on: 5)
        #expect(t.shown == nil)
        t.pointer(tab: 5, inStrip: true, now: 3)
        t.tick(now: 5)
        #expect(t.shown == nil)
        t.pointer(tab: 6, inStrip: true, now: 6)
        #expect(t.deadline == 6 + HoverPreviewTimer.delay) // a fresh wait, not an instant swap
    }

    @Test func movingOffABackgroundTabBeforeTheDelayCancelsIt() {
        var t = HoverPreviewTimer()
        t.pointer(tab: 5, inStrip: true, now: 0)
        t.pointer(tab: nil, inStrip: true, now: 0.3)
        t.tick(now: 1)
        #expect(t.shown == nil)
    }
}

struct PreviewGeometryTests {
    let screen = CGRect(x: 0, y: 25, width: 1600, height: 1000)

    @Test func topModeSitsCenteredBelowTheTab() {
        let tab = CGRect(x: 400, y: 100, width: 160, height: 32)
        let f = PreviewGeometry.frame(tab: tab, placement: .top, windowSize: CGSize(width: 800, height: 600), screen: screen)
        #expect(f.midX == tab.midX)
        #expect(f.minY == tab.maxY + PreviewGeometry.gap)
        #expect(f.width == PreviewGeometry.imageWidth + 2 * PreviewGeometry.padding)
    }

    @Test(arguments: [Tabsome.TabPlacement.left, .leftNamed])
    func leftModeSitsBesideTheColumn(placement: Tabsome.TabPlacement) {
        let tab = CGRect(x: 100, y: 400, width: 40, height: 36)
        let f = PreviewGeometry.frame(tab: tab, placement: placement, windowSize: CGSize(width: 800, height: 600), screen: screen)
        #expect(f.minX == tab.maxX + PreviewGeometry.gap)
        #expect(f.midY == tab.midY)
    }

    @Test func staysOnTheScreen() {
        let tab = CGRect(x: 1560, y: 980, width: 40, height: 32)
        let f = PreviewGeometry.frame(tab: tab, placement: .top, windowSize: CGSize(width: 800, height: 600), screen: screen)
        #expect(screen.contains(f))
    }

    @Test func thePictureKeepsTheWindowsShapeWithinLimits() {
        #expect(PreviewGeometry.imageSize(for: CGSize(width: 800, height: 600)) == CGSize(width: 240, height: 180))
        #expect(PreviewGeometry.imageSize(for: CGSize(width: 1600, height: 900)) == CGSize(width: 240, height: 135))
        #expect(PreviewGeometry.imageSize(for: CGSize(width: 400, height: 1200)).height == 180)
        #expect(PreviewGeometry.imageSize(for: CGSize(width: 3000, height: 400)).height == 100)
    }
}

@MainActor
final class FakePreviewStream: PreviewStreaming {
    var stopped = 0
    func stop() { stopped += 1 }
}

@MainActor
struct HoverPreviewTests {
    let preview = HoverPreview()
    let frame = CGRect(x: 100, y: 100, width: 256, height: 240)
    func tab(_ id: CGWindowID) -> TabItem { TabItem(id: id, label: "Notes", pid: 1, title: "Groceries", isActive: false) }

    @Test func theStreamRunsOnlyWhileThePreviewIsOpen() {
        var streams: [CGWindowID: FakePreviewStream] = [:]
        preview.makeStream = { id, _, _ in let s = FakePreviewStream(); streams[id] = s; return s }
        preview.show(tab(5), frame: frame, windowSize: CGSize(width: 800, height: 600))
        #expect(streams[5]?.stopped == 0)
        preview.show(tab(6), frame: frame, windowSize: CGSize(width: 800, height: 600)) // swap
        #expect(streams[5]?.stopped == 1)
        #expect(streams[6]?.stopped == 0)
        preview.hide()
        #expect(streams[6]?.stopped == 1)
        #expect(preview.model.image == nil)
        #expect(preview.shownID == nil)
    }

    @Test func showingTheSameTabAgainKeepsItsStream() {
        var starts = 0
        preview.makeStream = { _, _, _ in starts += 1; return FakePreviewStream() }
        preview.show(tab(5), frame: frame, windowSize: CGSize(width: 800, height: 600))
        preview.show(tab(5), frame: frame, windowSize: CGSize(width: 800, height: 600))
        #expect(starts == 1)
        preview.hide()
    }

    @Test func withoutScreenRecordingItShowsTheIconCard() {
        preview.makeStream = { _, _, _ in nil }
        preview.show(tab(5), frame: frame, windowSize: CGSize(width: 800, height: 600))
        #expect(preview.model.fallback)
        #expect(preview.model.tab?.id == 5)
        preview.hide()
    }

    @Test func framesFromAPreviousTabAreIgnored() throws {
        var deliver: [CGWindowID: (CGImage) -> Void] = [:]
        preview.makeStream = { id, _, onFrame in deliver[id] = onFrame; return FakePreviewStream() }
        preview.show(tab(5), frame: frame, windowSize: CGSize(width: 800, height: 600))
        preview.show(tab(6), frame: frame, windowSize: CGSize(width: 800, height: 600))
        let ctx = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(ctx.makeImage())
        deliver[5]?(image)
        #expect(preview.model.image == nil)
        deliver[6]?(image)
        #expect(preview.model.image != nil)
        preview.hide()
    }
}
