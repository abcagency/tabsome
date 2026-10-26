import AppKit
import CoreMedia
import ScreenCaptureKit
import SwiftUI
import VideoToolbox

/// When a hover preview shows (PLAN.md §5.14), like Safari's tab previews: a background tab
/// hovered for 0.6 s opens one; while one is open (or was, and the pointer is still on the
/// strip), moving to another background tab swaps it right away. A click ends it until the
/// pointer moves to another tab; leaving the strip resets everything. Pure, so it's tested
/// without a pointer.
nonisolated struct HoverPreviewTimer: Equatable {
    enum State: Equatable {
        case idle
        case waiting(CGWindowID, since: TimeInterval)
        case showing(CGWindowID)
        /// A preview was open and the pointer is on the strip but not on a background tab.
        case warm
        /// Clicked: nothing until the pointer leaves this tab.
        case suppressed(CGWindowID?)
    }

    static let delay: TimeInterval = 0.6
    private(set) var state = State.idle

    /// The tab whose preview should be open.
    var shown: CGWindowID? { if case .showing(let id) = state { id } else { nil } }
    /// When `tick` should next be called.
    var deadline: TimeInterval? { if case .waiting(_, let since) = state { since + Self.delay } else { nil } }

    /// The pointer moved. `tab` is the background tab under it (nil over the active tab, a
    /// button, or empty strip); `inStrip` is false once it leaves the strip.
    mutating func pointer(tab: CGWindowID?, inStrip: Bool, now: TimeInterval) {
        guard inStrip else { state = .idle; return }
        switch state {
        case .suppressed(let clicked):
            if tab == clicked { return }
            state = tab.map { .waiting($0, since: now) } ?? .idle
        case .showing, .warm:
            state = tab.map { .showing($0) } ?? .warm
        case .waiting(let id, _) where id == tab:
            return
        case .idle, .waiting:
            state = tab.map { .waiting($0, since: now) } ?? .idle
        }
    }

    mutating func tick(now: TimeInterval) {
        if case .waiting(let id, let since) = state, now - since >= Self.delay { state = .showing(id) }
    }

    /// A click on the strip (or a drag starting there) closes the preview.
    mutating func click(on tab: CGWindowID?) { state = .suppressed(tab) }

    /// Renaming, a menu, or the strip going away.
    mutating func cancel() { state = .idle }
}

/// Where the popover goes: below the tab in Top mode, beside the column in Left mode, kept on
/// the screen's usable area. All rects global, top-left origin.
nonisolated enum PreviewGeometry {
    static let imageWidth: CGFloat = 240
    static let imageHeightRange: ClosedRange<CGFloat> = 100...180
    static let padding: CGFloat = 8
    static let labelHeight: CGFloat = 36
    static let gap: CGFloat = 6

    /// The picture's size for a window of `windowSize`, keeping its shape within the range.
    static func imageSize(for windowSize: CGSize) -> CGSize {
        guard windowSize.width > 0, windowSize.height > 0 else { return CGSize(width: imageWidth, height: imageHeightRange.lowerBound) }
        let h = min(max(imageWidth * windowSize.height / windowSize.width, imageHeightRange.lowerBound), imageHeightRange.upperBound)
        return CGSize(width: imageWidth, height: h.rounded())
    }

    static func frame(tab: CGRect, placement: TabPlacement, windowSize: CGSize, screen: CGRect) -> CGRect {
        let image = imageSize(for: windowSize)
        let size = CGSize(width: image.width + 2 * padding, height: image.height + 2 * padding + labelHeight)
        var origin: CGPoint
        switch placement {
        case .top: origin = CGPoint(x: tab.midX - size.width / 2, y: tab.maxY + gap)
        case .left, .leftNamed: origin = CGPoint(x: tab.maxX + gap, y: tab.midY - size.height / 2)
        }
        origin.x = min(max(origin.x, screen.minX + gap), screen.maxX - gap - size.width)
        origin.y = min(max(origin.y, screen.minY + gap), screen.maxY - gap - size.height)
        return CGRect(origin: origin, size: size)
    }
}

/// A live picture of one window while its preview is open (§6.1 S3).
@MainActor
protocol PreviewStreaming: AnyObject {
    func stop()
}

/// Streams only the previewed window, at about 5 fps, at the preview's size. ScreenCaptureKit
/// captures it even though the active tab covers it. Frames stay in memory and the stream
/// stops the moment the preview closes.
@MainActor
final class PreviewStream: PreviewStreaming {
    private var stream: SCStream?
    private var stopped = false
    private let output: Output

    /// Nil without the Screen Recording permission, or while secure input is on: the preview
    /// shows the app's icon instead.
    static func make(window: CGWindowID, pixels: CGSize, onFrame: @escaping @MainActor (CGImage) -> Void) -> PreviewStreaming? {
        // No pictures while a password field has focus anywhere (S6): the icon card instead.
        guard CGPreflightScreenCaptureAccess(), !Eligibility.secureInputActive else { return nil }
        let s = PreviewStream(onFrame: onFrame)
        Task { await s.start(window: window, pixels: pixels) }
        return s
    }

    private init(onFrame: @escaping @MainActor (CGImage) -> Void) {
        output = Output(onFrame: onFrame)
    }

    private func start(window id: CGWindowID, pixels: CGSize) async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let window = content.windows.first(where: { $0.windowID == id }), !stopped else { return }
        let config = SCStreamConfiguration()
        config.width = Int(pixels.width)
        config.height = Int(pixels.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 5)
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, delegate: nil)
        do {
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
            try await stream.startCapture()
        } catch { return }
        if stopped { try? await stream.stopCapture(); return }
        self.stream = stream
    }

    func stop() {
        stopped = true
        output.onFrame = nil
        guard let stream else { return }
        self.stream = nil
        Task { try? await stream.stopCapture() }
    }

    private final class Output: NSObject, SCStreamOutput, @unchecked Sendable {
        let queue = DispatchQueue(label: "com.tabsome.preview")
        /// Touched on the main thread only.
        var onFrame: (@MainActor (CGImage) -> Void)?

        init(onFrame: @escaping @MainActor (CGImage) -> Void) { self.onFrame = onFrame }

        func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
            // Only frames with new content; idle frames repeat the last one.
            guard type == .screen,
                  let info = (CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
                  let raw = info[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
                  let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
            var image: CGImage?
            VTCreateCGImageFromCVPixelBuffer(pixels, options: nil, imageOut: &image)
            guard let image else { return }
            let frame = UncheckedImage(image)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.onFrame?(frame.image) }
            }
        }
    }

    private struct UncheckedImage: @unchecked Sendable {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }
}

@MainActor
@Observable
final class PreviewModel {
    var tab: TabItem?
    var image: CGImage?
    /// No Screen Recording: a larger icon with the name and title instead of a picture.
    var fallback = false
    var imageSize = CGSize(width: PreviewGeometry.imageWidth, height: PreviewGeometry.imageHeightRange.lowerBound)
    var visible = false
}

/// The preview popover (§5.14): one per strip, click-through, above the windows.
@MainActor
final class HoverPreview {
    /// Settings › Tabs › "Show previews when hovering tabs" (on by default).
    nonisolated static let settingKey = "showHoverPreviews"

    let model = PreviewModel()
    private let panel = OverlayPanel(clickThrough: true)
    private var stream: PreviewStreaming?
    /// Replaced in tests.
    var makeStream: (CGWindowID, CGSize, @escaping @MainActor (CGImage) -> Void) -> PreviewStreaming? = {
        PreviewStream.make(window: $0, pixels: $1, onFrame: $2)
    }

    var shownID: CGWindowID? { model.tab?.id }

    init() {
        panel.level = .popUpMenu
        let host = NSHostingView(rootView: PreviewView(model: model))
        host.sizingOptions = []
        panel.setHostedContent(host)
    }

    /// Opens (or swaps to) the preview for `tab`. `frame` is the popover's global frame.
    func show(_ tab: TabItem, frame: CGRect, windowSize: CGSize) {
        let swapping = model.tab?.id != tab.id
        panel.setFrame(ScreenGeometry.appKitRect(fromCG: frame), display: false)
        if swapping {
            stream?.stop()
            model.image = nil
            model.tab = tab
            model.imageSize = PreviewGeometry.imageSize(for: windowSize)
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let pixels = CGSize(width: model.imageSize.width * scale, height: model.imageSize.height * scale)
            stream = makeStream(tab.id, pixels) { [weak self] image in
                guard let self, self.model.tab?.id == tab.id else { return }
                self.model.image = image
            }
            model.fallback = stream == nil
            FileLog.shared.write("preview window=\(tab.id) \(model.fallback ? "icon card (no Screen Recording)" : "live")")
        } else {
            model.tab = tab // the title may have changed
        }
        if !model.visible {
            panel.orderFrontRegardless()
            withAnimation(Motion.quickFade) { model.visible = true }
        }
    }

    /// Closes it, stops the stream, and lets go of the last frame (S3).
    func hide() {
        stream?.stop()
        stream = nil
        guard model.tab != nil else { return }
        model.tab = nil
        model.image = nil
        model.visible = false
        panel.orderOut(nil)
    }
}

private struct PreviewView: View {
    let model: PreviewModel

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            picture
                .frame(width: model.imageSize.width, height: model.imageSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            if let tab = model.tab {
                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.label).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if let title = tab.title, !title.isEmpty, title != tab.label {
                        Text(title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                .padding(.horizontal, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(PreviewGeometry.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: shape)
        .opacity(model.visible ? 1 : 0)
    }

    @ViewBuilder private var picture: some View {
        if let image = model.image {
            Image(decorative: image, scale: NSScreen.main?.backingScaleFactor ?? 2)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05))
                if let tab = model.tab, let icon = NSRunningApplication(processIdentifier: tab.pid)?.icon {
                    // The fallback card, and the moment before the first frame arrives.
                    Image(nsImage: icon).resizable().frame(width: model.fallback ? 64 : 40, height: model.fallback ? 64 : 40)
                        .opacity(model.fallback ? 1 : 0.6)
                }
            }
        }
    }
}
