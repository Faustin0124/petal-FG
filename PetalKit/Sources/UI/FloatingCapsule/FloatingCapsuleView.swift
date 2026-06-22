import SwiftUI

public struct FloatingCapsuleView: View {
    @Bindable var state: FloatingCapsuleState
    @State private var blurRadius: CGFloat = 0

    public init(state: FloatingCapsuleState) {
        self.state = state
    }

    public var body: some View {
        Group {
            switch self.state.phase {
            case .hidden:
                Color.clear
            case .recording:
                recording
            case .confirmCancel:
                confirmCancel
            case .trimming:
                trimming
            case .speeding:
                speeding
            case .warming:
                warming
            case .transcribing:
                transcribing
            case .refining:
                RefiningCapsuleContent(contentBlur: blurRadius)
            case .copiedToClipboard:
                copiedToClipboard
            case .accessibilityPrompt:
                accessibilityPrompt
            case .accessibilityEnabled:
                accessibilityEnabled
            case .error:
                error
            }
        }
        .fixedSize()
        .blur(radius: blurRadius > 0 ? 8 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.35), value: self.state.phase)
        .onChange(of: state.phase) { _, newPhase in
            guard newPhase != .hidden else { return }
            blurRadius = 12
            withAnimation(.easeOut(duration: 0.5)) {
                blurRadius = 0
            }
        }
    }

    // MARK: - Phase content

    private var recording: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)

            Text("REC")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)

            RecordingBars(level: self.state.level)
        }
        .floatingCapsuleChrome(blur: blurRadius)
    }

    private var confirmCancel: some View {
        CancelConfirmationCapsule(isActive: state.cancelCountdownActive, blur: blurRadius)
    }

    private var trimming: some View {
        HStack(spacing: 8) {
            Image(systemName: "scissors")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)

            Text("Trimming silence")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .floatingCapsuleChrome(blur: blurRadius)
    }

    private var speeding: some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.run")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.teal)

            Text("Speeding audio")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.teal)
        }
        .floatingCapsuleChrome(blur: blurRadius)
    }

    private var warming: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Text("Loading model")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .floatingCapsuleChrome(blur: blurRadius)
    }

    private var transcribing: some View {
        HStack(spacing: 8) {
            CircularProgressRing(progress: self.state.transcriptionProgress)

            Text("Transcribing")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .floatingCapsuleChrome(blur: blurRadius)
    }

    private var error: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption2.weight(.bold))

            Text("Error")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .floatingCapsuleChrome(blur: blurRadius)
    }

    private var copiedToClipboard: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption2.weight(.bold))

            Text("Copied to clipboard")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(height: 20)
        .floatingCapsuleChrome(blur: blurRadius)
    }

    private var accessibilityPrompt: some View {
        Button {
            state.onAccessibilityTapped?()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "accessibility")
                    .foregroundStyle(.blue)
                    .font(.caption2.weight(.bold))

                Text("Enable Accessibility")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(height: 20)
            .floatingCapsuleChrome(blur: blurRadius)
        }
        .buttonStyle(.plain)
    }

    private var accessibilityEnabled: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption2.weight(.bold))

            Text("Accessibility Enabled")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(height: 20)
        .floatingCapsuleChrome(blur: blurRadius)
    }

}

// MARK: - Preview

#Preview("Floating Capsule") {
    FloatingCapsulePreview()
}

private struct FloatingCapsulePreview: View {
    @State private var state = FloatingCapsuleState()
    @State private var phaseIndex = 1

    private let phases: [(String, FloatingCapsuleState.Phase)] = [
        ("Hidden", .hidden),
        ("Recording", .recording),
        ("Confirm Cancel", .confirmCancel),
        ("Trimming", .trimming),
        ("Speeding", .speeding),
        ("Warming", .warming),
        ("Transcribing", .transcribing),
        ("Refining", .refining),
        ("Copied", .copiedToClipboard),
        ("Accessibility", .accessibilityPrompt),
        ("AX Enabled", .accessibilityEnabled),
        ("Error", .error("Preview")),
    ]

    var body: some View {
        VStack(spacing: 20) {
            FloatingCapsuleView(state: state)
                .frame(width: 400, height: 60)
                .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))

            HStack(spacing: 16) {
                Button(action: prev) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)

                Text(phases[phaseIndex].0)
                    .font(.footnote.weight(.medium))
                    .frame(width: 120)

                Button(action: next) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(24)
        .onAppear { applyPhase() }
    }

    private func prev() {
        phaseIndex = (phaseIndex - 1 + phases.count) % phases.count
        applyPhase()
    }

    private func next() {
        phaseIndex = (phaseIndex + 1) % phases.count
        applyPhase()
    }

    private func applyPhase() {
        state.phase = phases[phaseIndex].1
        state.level = 0.72
        state.transcriptionProgress = 0.64
    }
}
