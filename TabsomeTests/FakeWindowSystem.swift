import CoreGraphics
@testable import Tabsome

@MainActor
final class FakeWindowSystem: WindowSystem {
    var onEvent: ((WindowEvent) -> Void)?
    private(set) var tracked: Set<pid_t> = []
    private(set) var untrackAllCount = 0

    func track(pid: pid_t) { tracked.insert(pid) }
    func untrack(pid: pid_t) { tracked.remove(pid) }
    func untrackAll() { tracked.removeAll(); untrackAllCount += 1 }

    func send(_ event: WindowEvent) { onEvent?(event) }
}

func snapshot(_ id: CGWindowID, pid: pid_t, title: String? = "Doc", frame: CGRect = CGRect(x: 10, y: 20, width: 300, height: 200),
              main: Bool = false) -> WindowSnapshot {
    WindowSnapshot(id: id, pid: pid, title: title, frame: frame, subrole: "AXStandardWindow", isStandard: true,
                   isMinimized: false, isFullScreen: false, isMain: main)
}
