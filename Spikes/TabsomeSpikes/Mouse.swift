// Tooling: synthesized mouse input and region captures for checking the real app.
//   mouse click X Y
//   mouse middle X Y                     middle-click
//   mouse drag X1 Y1 X2 Y2 [holdSeconds]  press, drag in steps, optionally hold, release
//   mouse shot X Y W H name              capture a region of the screen (global, top-left)

import AppKit

@MainActor
enum Mouse {
    static func run(_ args: ArraySlice<String>) {
        guard requireAX() else { return }
        let a = Array(args)
        let n = a.dropFirst().compactMap(Double.init).map { CGFloat($0) }
        switch a.first {
        case "click" where n.count >= 2:
            let p = CGPoint(x: n[0], y: n[1])
            postMouse(.mouseMoved, p); usleep(60_000)
            postMouse(.leftMouseDown, p); usleep(70_000); postMouse(.leftMouseUp, p)
            usleep(200_000)
        case "middle" where n.count >= 2:
            let p = CGPoint(x: n[0], y: n[1])
            postMouse(.mouseMoved, p); usleep(60_000)
            for type in [CGEventType.otherMouseDown, .otherMouseUp] {
                let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .center)
                e?.post(tap: .cghidEventTap); usleep(70_000)
            }
            usleep(200_000)
        case "drag" where n.count >= 4:
            let hold = n.count >= 5 ? useconds_t(n[4] * 1_000_000) : 150_000
            synthDrag(from: CGPoint(x: n[0], y: n[1]), to: CGPoint(x: n[2], y: n[3]), steps: 40, stepDelay: 12_000, holdBeforeRelease: hold)
            usleep(200_000)
        case "shot" where n.count >= 4:
            keepAlive = true
            let name = a.count > 5 ? a[5] : "region"
            Task { @MainActor in
                await TabDrag.shoot(region: CGRect(x: n[0], y: n[1], width: n[2], height: n[3]), name: name)
                finish()
            }
        default:
            log("usage: mouse click X Y | middle X Y | drag X1 Y1 X2 Y2 [hold] | shot X Y W H name")
        }
    }
}
