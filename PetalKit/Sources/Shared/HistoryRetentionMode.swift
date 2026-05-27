import Foundation

public enum HistoryRetentionMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case none
    case transcripts
    case audio
    case both

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none:
            return String(localized: "Off", bundle: .module)
        case .transcripts:
            return String(localized: "Transcripts", bundle: .module)
        case .audio:
            return String(localized: "Audio", bundle: .module)
        case .both:
            return String(localized: "Audio + Transcripts", bundle: .module)
        }
    }

    public var keepsHistory: Bool {
        self != .none
    }

    public var keepsTranscripts: Bool {
        self == .transcripts || self == .both
    }

    public var keepsAudio: Bool {
        self == .audio || self == .both
    }
}
