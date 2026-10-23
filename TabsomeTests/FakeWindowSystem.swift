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

    /// Every command, in order. Frames "land" exactly unless `landing` says otherwise.
    private(set) var commands: [(WindowCommand, CGWindowID)] = []
    var landing: [CGWindowID: (CGRect) -> CGRect] = [:]
    /// Windows whose app never answers (hung): their commands never complete.
    var hung: Set<CGWindowID> = []

    func perform(_ command: WindowCommand, window: CGWindowID, pid: pid_t, completion: (@MainActor (CommandResult) -> Void)?) {
        commands.append((command, window))
        if hung.contains(window) { return }
        var frame: CGRect?
        if case .setFrame(let f) = command { frame = landing[window]?(f) ?? f }
        completion?(CommandResult(ok: true, frame: frame))
    }

    func clearCommands() { commands.removeAll() }
}

func snapshot(_ id: CGWindowID, pid: pid_t, title: String? = "Doc", frame: CGRect = CGRect(x: 10, y: 20, width: 300, height: 200),
              main: Bool = false) -> WindowSnapshot {
    WindowSnapshot(id: id, pid: pid, title: title, frame: frame, subrole: "AXStandardWindow", isStandard: true,
                   isMinimized: false, isFullScreen: false, isMain: main)
}
