import SwiftUI

/// PLAN.md §7 Phase 1: Accessibility (required) → Screen Recording (optional) → the one gesture.
struct OnboardingView: View {
    enum Step: Int, CaseIterable { case accessibility, screenRecording, gesture }

    let model: AppModel
    let onFinish: () -> Void
    @State private var step: Step

    init(model: AppModel, onFinish: @escaping () -> Void) {
        self.model = model
        self.onFinish = onFinish
        let p = model.permissions
        _step = State(initialValue: !p.accessibility ? .accessibility : (p.screenRecording ? .gesture : .screenRecording))
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .accessibility: AccessibilityStep(permissions: model.permissions) { advance(to: .screenRecording) }
                case .screenRecording: ScreenRecordingStep(permissions: model.permissions) { advance(to: .gesture) }
                case .gesture: GestureStep(onFinish: onFinish)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            HStack(spacing: 8) {
                ForEach(Step.allCases, id: \.self) { s in
                    Circle()
                        .fill(s == step ? Color.primary : Color.secondary.opacity(0.35))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.bottom, 20)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
        }
        .padding(.horizontal, 48)
        .padding(.top, 36)
        .frame(width: 560, height: 500)
    }

    private func advance(to next: Step) {
        withAnimation(Motion.smooth) { step = next }
    }
}

private struct StepHeader: View {
    let image: Image
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            image
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AccessibilityStep: View {
    let permissions: Permissions
    let onGranted: () -> Void
    @State private var asked = false

    var body: some View {
        VStack(spacing: 24) {
            StepHeader(
                image: Image(nsImage: NSApp.applicationIconImage),
                title: "Let \(Brand.name) arrange your windows",
                message: "\(Brand.name) needs Accessibility access to move and resize other apps’ windows, so they can share one tabbed window. It works only with windows (their position, size, and title) and never reads what’s inside them.")

            if permissions.accessibility {
                Label("Access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                Button("Open System Settings") {
                    permissions.promptForAccessibility()
                    permissions.openAccessibilitySettings()
                    asked = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if asked {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Turn on \(Brand.name) in Privacy & Security › Accessibility. This window continues on its own.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .onAppear { permissions.startWaiting() }
        .onDisappear { permissions.stopWaiting() }
        .onChange(of: permissions.accessibility) { _, granted in
            guard granted else { return }
            permissions.stopWaiting()
            NSApp.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { onGranted() }
        }
    }
}

private struct ScreenRecordingStep: View {
    let permissions: Permissions
    let onContinue: () -> Void
    @State private var asked = false

    var body: some View {
        VStack(spacing: 24) {
            StepHeader(
                image: Image(systemName: "rectangle.dashed.badge.record"),
                title: "Optional: live window pictures",
                message: "With Screen Recording, \(Brand.name) shows real pictures of windows while they animate into tabs and when you hover over a tab. It captures only that one window, keeps the picture in memory for a moment, and never saves or sends it. Without it, \(Brand.name) shows the app’s icon instead, and everything else works the same.")

            if permissions.screenRecording {
                Label("Screen Recording is on", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else if asked {
                Text("If you turned it on, macOS may ask you to quit and reopen \(Brand.name). You can do that any time.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                HStack(spacing: 12) {
                    Button("Skip", action: onContinue)
                        .controlSize(.large)
                    Button("Allow Screen Recording…") {
                        permissions.requestScreenRecording()
                        asked = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct GestureStep: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            GestureDemoView()
                .frame(width: 400, height: 230)
            VStack(spacing: 8) {
                Text("Drag a window onto another, pause, let go.")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("After that, they work just like browser tabs.")
                    .foregroundStyle(.secondary)
            }
            Button("Done", action: onFinish)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            Spacer(minLength: 0)
        }
    }
}
