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

    /// Identifier persisted in user defaults. Deliberately not `rawValue`: that is an SF
    /// Symbol name, and swapping an icon must not scramble someone's saved tab order.
    var key: String {
        switch self {
        case .music: return "music"
        case .calendar: return "calendar"
        case .sports: return "sports"
        case .clipboard: return "clipboard"
        case .system: return "system"
        case .zen: return "zen"
        case .apps: return "apps"
        case .quotes: return "quotes"
        case .settings: return "settings"
        }
    }

    init?(key: String) {
        guard let tab = IslandTab.allCases.first(where: { $0.key == key }) else { return nil }
        self = tab
    }

    /// Settings can't be hidden — it is where tabs are un-hidden.
    var isAlwaysVisible: Bool { self == .settings }

    /// Tabs in the user's saved order, minus the hidden ones.
    ///
    /// Unknown keys (a tab removed in a later version) are dropped, duplicates are
    /// ignored, and tabs missing from `order` (added in a later version) go at the end,
    /// so a stale saved order can never lose a tab.
    static func arrange(order: [String], hidden: Set<String> = []) -> [IslandTab] {
        var result: [IslandTab] = []
        for key in order {
            if let tab = IslandTab(key: key), !result.contains(tab) {
                result.append(tab)
            }
        }
        for tab in allCases where !result.contains(tab) {
            result.append(tab)
        }
        return result.filter { $0.isAlwaysVisible || !hidden.contains($0.key) }
    }
}
