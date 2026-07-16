import AppKit
import Dependencies
import DependenciesMacros
import UI
import Observation
import SwiftUI

@DependencyClient
public struct FloatingCapsuleClient: Sendable {
    public var showRecording: @Sendable () async -> Void = {}
    public var showTrimming: @Sendable () async -> Void = {}
    public var showSpeeding: @Sendable () async -> Void = {}
    public var updateLevel: @Sendable (Double) async -> Void = { _ in }
    public var showTranscribing: @Sendable () async -> Void = {}
    public var updateTranscriptionProgress: @Sendable (Double) async -> Void = { _ in }
    /// Shows the live partial transcript. Call repeatedly with the latest text as it updates;
    /// call once with an empty string to enter the phase before any text has arrived.
    public var updateStreamingText: @Sendable (String) async -> Void = { _ in }
    public var showRefining: @Sendable () async -> Void = {}
    public var showCancelConfirmation: @Sendable () async -> Void = {}
    public var showCopiedToClipboard: @Sendable () async -> Void = {}
    public var showAccessibilityPrompt: @Sendable (@escaping @Sendable () -> Void) async -> Void = { _ in }
    public var showAccessibilityEnabled: @Sendable () async -> Void = {}
    public var showError: @Sendable (String) async -> Void = { _ in }
    public var hide: @Sendable () async -> Void = {}
}

extension FloatingCapsuleClient: DependencyKey {
    public static var liveValue: Self {
        return Self(
            showRecording: {
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.showRecording() }
            },
            showTrimming: {
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.showTrimming() }
            },
            showSpeeding: {
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.showSpeeding() }
            },
            updateLevel: { level in
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.updateLevel(level) }
            },
            showTranscribing: {
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.showTranscribing() }
            },
            updateTranscriptionProgress: { progress in
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.updateTranscriptionProgress(progress) }
            },
            updateStreamingText: { text in
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.updateStreamingText(text) }
            },
            showRefining: {
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.showRefining() }
            },
            showCancelConfirmation: {
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.showCancelConfirmation() }
            },
            showCopiedToClipboard: {
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.showCopiedToClipboard() }
            },
            showAccessibilityPrompt: { onTap in
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.showAccessibilityPrompt(onTap: onTap) }
            },
            showAccessibilityEnabled: {
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.showAccessibilityEnabled() }
            },
            showError: { message in
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.showError(message) }
            },
            hide: {
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.hide() }
            }
        )
    }
}

extension FloatingCapsuleClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            showRecording: {},
            showTrimming: {},
            showSpeeding: {},
            updateLevel: { _ in },
            showTranscribing: {},
            updateTranscriptionProgress: { _ in },
            updateStreamingText: { _ in },
            showRefining: {},
            showCancelConfirmation: {},
            showCopiedToClipboard: {},
            showAccessibilityPrompt: { _ in },
            showAccessibilityEnabled: {},
            showError: { _ in },
            hide: {}
        )
    }
}

public extension DependencyValues {
    var floatingCapsuleClient: FloatingCapsuleClient {
        get { self[FloatingCapsuleClient.self] }
        set { self[FloatingCapsuleClient.self] = newValue }
    }
}

@MainActor
private final class LiveFloatingCapsuleRuntime {
    private let state = FloatingCapsuleState()
    private let panel: NSPanel

    init() {
        let contentView = FloatingCapsuleView(state: state)
        let hostingController = NSHostingController(rootView: contentView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        panel.contentViewController = hostingController
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        self.panel = panel
    }

    func showRecording() {
        state.cancelCountdownActive = false
        state.phase = .recording
        showWindowIfNeeded()
    }

    func showTrimming() {
        state.phase = .trimming
        showWindowIfNeeded()
    }

    func showSpeeding() {
        state.phase = .speeding
        showWindowIfNeeded()
    }

    func updateLevel(_ level: Double) {
        state.level = level
    }

    func showTranscribing() {
        state.transcriptionProgress = 0
        state.phase = .transcribing
        showWindowIfNeeded()
    }

    func updateStreamingText(_ text: String) {
        state.phase = .streaming(text)
        showWindowIfNeeded()
    }

    func showRefining() {
        state.phase = .refining
        showWindowIfNeeded()
    }

    func updateTranscriptionProgress(_ progress: Double) {
        let clamped = min(max(progress, 0), 1)
        state.transcriptionProgress = max(state.transcriptionProgress, clamped)
    }

    func showCancelConfirmation() {
        state.cancelCountdownActive = false
        state.phase = .confirmCancel
        showWindowIfNeeded()
        // Trigger on next run loop so SwiftUI sees the change from false → true
        DispatchQueue.main.async { [state] in
            state.cancelCountdownActive = true
        }
    }

    func showCopiedToClipboard() {
        state.phase = .copiedToClipboard
        showWindowIfNeeded()
    }

    func showAccessibilityPrompt(onTap: @escaping @Sendable () -> Void) {
        state.onAccessibilityTapped = onTap
        state.phase = .accessibilityPrompt
        showWindowIfNeeded()
    }

    func showAccessibilityEnabled() {
        state.phase = .accessibilityEnabled
        showWindowIfNeeded()
    }

    func showError(_ message: String) {
        state.phase = .error(message)
        showWindowIfNeeded()
    }

    func hide() {
        state.phase = .hidden
        state.level = 0
        state.transcriptionProgress = 0
        state.cancelCountdownActive = false
        panel.orderOut(nil)
    }

    private func showWindowIfNeeded() {
        positionPanel()
        panel.orderFrontRegardless()
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }

        let panelWidth: CGFloat = 400
        panel.setContentSize(NSSize(width: panelWidth, height: 52))
        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.midX - panelWidth / 2
        let y = visibleFrame.minY + 36
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

@MainActor
private enum LiveFloatingCapsuleRuntimeContainer {
    static let shared = LiveFloatingCapsuleRuntime()
}
