import CoreGraphics
import SwiftUI
import Testing
@testable import Tabsome

@MainActor
struct SettleTests {
    let system = FakeWindowSystem()
    let registry: WindowRegistry
    let manager: GroupManager
    var bounds: [CGWindowID: CGRect] = [:]

    init() {
        registry = WindowRegistry(system: system)
        manager = GroupManager(registry: registry, system: system)
        manager.animates = false
        manager.windowBounds = { _ in nil }
        for (pid, name) in [(101, "Safari"), (202, "Finder"), (303, "Notes")] as [(pid_t, String)] {
            registry.track(.init(pid: pid, name: name, bundleID: "t.\(name)"))
            system.send(.appWindows(pid, [snapshot(CGWindowID(pid / 101), pid: pid, frame: CGRect(x: 100, y: 100, width: 800, height: 600))]))
        }
        manager.merge(dragged: 2, into: 1, dropFrame: nil, snapshot: nil)
        manager.merge(dragged: 3, into: 2, dropFrame: nil, snapshot: nil)
    }

    @Test func aReportMidMergeDoesntDragTheGroupAway() throws {
        let content = try #require(manager.group(containing: 1)).content
        // The active window reports an in-between frame (its old origin, the new size) while settling.
        system.send(.windowUpdated(snapshot(3, pid: 303, frame: CGRect(x: 600, y: 300, width: content.width, height: content.height))))
        #expect(try #require(manager.group(containing: 1)).content == content)
    }

    @Test func theSettleCheckPutsAStragglerBack() throws {
        let content = try #require(manager.group(containing: 1)).content
        let stray = content.offsetBy(dx: 300, dy: 120)
        manager.windowBounds = { $0 == 1 ? stray : content }
        system.clearCommands()
        manager.settleCheck(try #require(manager.group(containing: 1)).id)
        let fixes = system.commands.compactMap { c, w -> CGWindowID? in if case .setFrame(let f) = c, f == content { w } else { nil } }
        #expect(fixes == [1])
    }
}

struct Phase4bLayoutTests {
    @Test func leftWithNamesIsAFixedWideColumnWithFullTabs() {
        #expect(StripLayout.thickness(.leftNamed) == Metrics.leftNamedStripWidth)
        let l = StripLayout.left(height: 600, count: 3, active: 0, showsPlus: true, named: true)
        #expect(l.style == .full)
        #expect(l.frames.map(\.height) == [30, 30, 30])
        #expect(l.frames.allSatisfy { $0.width == Metrics.leftNamedStripWidth })
        let outer = CGRect(x: 0, y: 0, width: 1000, height: 600)
        #expect(StripLayout.frames(outer: outer, placement: .leftNamed).content.minX == 180)
    }

    @Test(arguments: Tabsome.TabPlacement.allCases)
    func thePanelIsTheStripPlusAFilletBand(placement: Tabsome.TabPlacement) {
        let strip = StripLayout.frames(outer: CGRect(x: 50, y: 60, width: 900, height: 700), placement: placement).strip
        let panel = StripLayout.panelFrame(strip: strip, placement: placement)
        #expect(panel.origin == strip.origin)
        #expect(StripLayout.stripSize(panel: panel.size, placement: placement) == strip.size)
    }

    @Test func theFilletsCoverOnlyTheCornerGaps() {
        let t: CGFloat = 32, r = Metrics.windowCornerRadius, w: CGFloat = 800
        let path = StripShape(placement: .top, thickness: t).path(in: CGRect(x: 0, y: 0, width: w, height: t + r))
        #expect(path.contains(CGPoint(x: w / 2, y: t / 2)))       // the strip itself
        #expect(path.contains(CGPoint(x: 1.5, y: t + 1.5)))       // the gap outside the window's top-left corner
        #expect(path.contains(CGPoint(x: w - 1.5, y: t + 1.5)))   // and top-right
        #expect(!path.contains(CGPoint(x: r, y: t + r - 1)))      // inside the window's rounded corner
        #expect(!path.contains(CGPoint(x: w / 2, y: t + 4)))      // the window's title bar: never covered
        #expect(!path.contains(CGPoint(x: 0.5, y: 0.5)))          // the strip's own rounded outer corner
    }

    @Test func leftFilletsSitBesideTheWindowsLeftCorners() {
        let t: CGFloat = 40, r = Metrics.windowCornerRadius, h: CGFloat = 600
        let path = StripShape(placement: .left, thickness: t).path(in: CGRect(x: 0, y: 0, width: t + r, height: h))
        #expect(path.contains(CGPoint(x: t + 1.5, y: 1.5)))
        #expect(path.contains(CGPoint(x: t + 1.5, y: h - 1.5)))
        #expect(!path.contains(CGPoint(x: t + 4, y: h / 2)))
    }
}

@MainActor
struct RenameCommitTests {
    @Test func losingFocusSavesWhatsTypedSoFar() {
        let model = TabStripModel()
        model.tabs = [TabItem(id: 7, label: "Safari", pid: 1, title: nil, isActive: true)]
        var saved: (CGWindowID, String?, Bool)?
        model.onRename = { saved = ($0, $1, $2) }
        model.beginRename(7)
        model.renameDraft = "Cool ta"
        model.commitRename(refocus: false)
        #expect(saved?.0 == 7)
        #expect(saved?.1 == "Cool ta")
        #expect(saved?.2 == false)
        #expect(model.renaming == nil)
    }

    @Test func savingTheUnchangedDefaultKeepsNoCustomName() {
        let model = TabStripModel()
        model.tabs = [TabItem(id: 7, label: "Safari", pid: 1, title: nil, isActive: true)]
        var saved: String?? = .none
        model.onRename = { _, name, _ in saved = name }
        model.beginRename(7)
        model.commitRename(refocus: true)
        #expect(saved == .some(nil))
    }
}
