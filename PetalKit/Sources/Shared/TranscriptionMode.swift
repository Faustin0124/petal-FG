public enum TranscriptionMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case verbatim
    case smart

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .verbatim:
            return String(localized: "Verbatim", bundle: .module)
        case .smart:
            return String(localized: "Smart", bundle: .module)
        }
    }

    public var description: String {
        switch self {
        case .verbatim:
            return String(localized: "Word-for-word transcription", bundle: .module)
        case .smart:
            return String(localized: "Refine transcription with a custom prompt", bundle: .module)
        }
    }
}
