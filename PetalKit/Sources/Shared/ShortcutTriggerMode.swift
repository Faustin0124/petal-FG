public enum ShortcutTriggerMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case combo
    case doubleTap

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .combo: String(localized: "Key Combo", bundle: .module)
        case .doubleTap: String(localized: "Double-Tap", bundle: .module)
        }
    }
}
