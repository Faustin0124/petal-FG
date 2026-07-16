import Observation

@MainActor
@Observable
public final class FloatingCapsuleState {
    public enum Phase: Equatable {
        case hidden
        case recording
        case confirmCancel
        case trimming
        case speeding
        case transcribing
        /// Live streaming transcription in progress; associated text is the best-effort
        /// transcript so far, updated as the user speaks.
        case streaming(String)
        case refining
        case copiedToClipboard
        case accessibilityPrompt
        case accessibilityEnabled
        case error(String)
    }

    public var phase: Phase = .hidden
    public var level: Double = 0
    public var transcriptionProgress: Double = 0
    public var cancelCountdownActive: Bool = false
    public var onAccessibilityTapped: (() -> Void)?

    public init() {}
}
