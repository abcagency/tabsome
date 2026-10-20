import SwiftUI

/// A short looping animation of the one gesture to learn: drag a window over the middle of
/// another, pause until it highlights, let go, and they become tabs (PLAN.md §1, §7 Phase 1).
/// All timing comes from `Motion`; with Reduce Motion each stage cross-fades instead.
struct GestureDemoView: View {
    private enum Phase: Int { case apart, dragging, armed, merged }

    @State private var phase = Phase.apart
    private let back = CGRect(x: 40, y: 64, width: 210, height: 140)
    private let frontStart = CGRect(x: 214, y: 26, width: 160, height: 112)

    var body: some View {
        let reduced = Motion.reduced
        ZStack(alignment: .topLeading) {
            scene(phase)
                .id(reduced ? phase.rawValue : 0)
                .transition(.opacity)
        }
        .frame(width: 400, height: 230, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Animation: a window is dragged onto another window, held for a moment, and released. The two windows become tabs of one window.")
        .task { await loop() }
    }

    private func scene(_ phase: Phase) -> some View {
        let merged = phase == .merged
        let front: CGRect = switch phase {
        case .apart: frontStart
        case .dragging, .armed: CGRect(x: back.midX - 80 + 18, y: back.midY - 56 + 8, width: 160, height: 112)
        case .merged: back
        }
        return ZStack(alignment: .topLeading) {
            MiniWindow(tint: .orange, showsTitleBar: !merged)
                .frame(width: back.width, height: back.height)
                .offset(x: back.minX, y: back.minY)

            if phase == .armed {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.18))
                    .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 2)
                    .frame(width: back.width + 8, height: back.height + 8)
                    .offset(x: back.minX - 4, y: back.minY - 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            MiniWindow(tint: .blue, showsTitleBar: !merged)
                .frame(width: front.width, height: front.height)
                .offset(x: front.minX, y: front.minY)
                .shadow(color: .black.opacity(phase == .dragging || phase == .armed ? 0.3 : 0.15), radius: 10, y: 4)

            if merged {
                MiniTabStrip()
                    .frame(width: back.width, height: 20)
                    .offset(x: back.minX, y: back.minY - 20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if phase != .apart {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.primary, .background)
                    .offset(x: front.midX - 6, y: front.minY + 2)
            }
        }
    }

    private func loop() async {
        while !Task.isCancelled {
            set(.apart, Motion.quickFade)
            try? await Task.sleep(for: .seconds(1.0))
            set(.dragging, Motion.smooth)
            try? await Task.sleep(for: .seconds(1.0))
            set(.armed, Motion.quickFade)      // the pause: the target highlights
            try? await Task.sleep(for: .seconds(0.9))
            set(.merged, Motion.snappy)        // let go: they become tabs
            try? await Task.sleep(for: .seconds(2.2))
        }
    }

    private func set(_ p: Phase, _ animation: Animation) {
        withAnimation(Motion.reduced ? .easeInOut(duration: 0.25) : animation) { phase = p }
    }
}

private struct MiniWindow: View {
    let tint: Color
    let showsTitleBar: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showsTitleBar {
                HStack(spacing: 4) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 7, height: 7) }
                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(.background.secondary)
            }
            ZStack {
                Rectangle().fill(.background)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<4) { i in
                        Capsule().fill(tint.opacity(i == 0 ? 0.55 : 0.2)).frame(width: i == 0 ? 70 : 110 - CGFloat(i * 14), height: 7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }
}

private struct MiniTabStrip: View {
    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 3) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 6, height: 6) }
            }
            .padding(.trailing, 2)
            tab(.orange, active: false)
            tab(.blue, active: true)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.background.secondary, in: UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8))
    }

    private func tab(_ tint: Color, active: Bool) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 9, height: 9)
            Capsule().fill(.secondary.opacity(0.5)).frame(width: 34, height: 5)
        }
        .padding(.horizontal, 8)
        .frame(height: 15)
        .background(active ? AnyShapeStyle(.background) : AnyShapeStyle(.clear), in: Capsule())
    }
}
