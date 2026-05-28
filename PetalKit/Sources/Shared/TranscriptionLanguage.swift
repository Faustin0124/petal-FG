import Foundation

public struct TranscriptionLanguage: Identifiable, Hashable, Codable, Sendable {
    public let code: String
    public let displayName: String

    public var id: String { code }

    public init(code: String, displayName: String) {
        self.code = code
        self.displayName = displayName
    }

    public static var auto: TranscriptionLanguage {
        TranscriptionLanguage(code: "auto", displayName: String(localized: "Auto-detect", bundle: .module))
    }

    public static let supported: [TranscriptionLanguage] = [
        TranscriptionLanguage(code: "auto", displayName: String(localized: "Auto-detect", bundle: .module)),
        TranscriptionLanguage(code: "en", displayName: "English"),
        TranscriptionLanguage(code: "fr", displayName: "Français"),
        TranscriptionLanguage(code: "de", displayName: "Deutsch"),
        TranscriptionLanguage(code: "es", displayName: "Español"),
        TranscriptionLanguage(code: "it", displayName: "Italiano"),
        TranscriptionLanguage(code: "pt", displayName: "Português"),
        TranscriptionLanguage(code: "ja", displayName: "日本語"),
        TranscriptionLanguage(code: "zh", displayName: "中文"),
        TranscriptionLanguage(code: "ko", displayName: "한국어"),
        TranscriptionLanguage(code: "ar", displayName: "العربية"),
        TranscriptionLanguage(code: "ru", displayName: "Русский"),
    ]
}
