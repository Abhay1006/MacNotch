import Foundation

enum IslandTab: String, CaseIterable {
    case music = "music.note"
    case calendar = "calendar"
    case sports = "trophy"
    case clipboard = "doc.on.clipboard"
    case system = "slider.horizontal.3"
    case zen = "leaf.fill"
    case apps = "square.grid.2x2.fill"
    case quotes = "quote.bubble.fill"
    case settings = "gearshape.fill"

    /// SF Symbol name for the tab bar.
    var symbol: String { rawValue }

    /// Spoken by VoiceOver — the symbol name alone is meaningless.
    var accessibilityLabel: String {
        switch self {
        case .music: return "Music"
        case .calendar: return "Calendar and tasks"
        case .sports: return "Live scores"
        case .clipboard: return "Clipboard history"
        case .system: return "System controls"
        case .zen: return "Zen timer"
        case .apps: return "Favorite apps"
        case .quotes: return "Quotes"
        case .settings: return "Settings"
        }
    }
}
