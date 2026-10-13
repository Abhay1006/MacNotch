import Foundation
import Combine
import ServiceManagement

/// User-configurable settings, backed by `UserDefaults`.
///
/// Previously the Obsidian vault path, the quotes file, and every poll interval were
/// hardcoded to one machine's home directory, which made the app unusable for anyone
/// else. Everything tweakable now lives here with a sensible default.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let obsidianVaultPath = "ObsidianVaultPath"
        static let quotesFileRelativePath = "QuotesFileRelativePath"
        static let artworkLookupEnabled = "ArtworkLookupEnabled"
        static let showOnExternalDisplays = "ShowOnExternalDisplays"
        static let clipboardHistoryLimit = "ClipboardHistoryLimit"
        static let launchAtLogin = "LaunchAtLogin"
        static let tabOrder = "TabOrder"
        static let hiddenTabs = "HiddenTabs"
        static let hapticFeedbackEnabled = "HapticFeedbackEnabled"
    }

    /// Default vault location — still `~/Documents/Obsidian Vault`, but now only a default.
    static var defaultVaultPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Obsidian Vault").path
    }

    @Published var obsidianVaultPath: String {
        didSet { defaults.set(obsidianVaultPath, forKey: Key.obsidianVaultPath) }
    }

    /// Path of the quotes note, relative to the vault root.
    @Published var quotesFileRelativePath: String {
        didSet { defaults.set(quotesFileRelativePath, forKey: Key.quotesFileRelativePath) }
    }

    /// Whether to fall back to the iTunes Search API when Apple Music has no local
    /// artwork. This sends the current track title and artist to Apple, so it is
    /// disclosed in the README and can be turned off here.
    @Published var artworkLookupEnabled: Bool {
        didSet { defaults.set(artworkLookupEnabled, forKey: Key.artworkLookupEnabled) }
    }

    @Published var showOnExternalDisplays: Bool {
        didSet { defaults.set(showOnExternalDisplays, forKey: Key.showOnExternalDisplays) }
    }

    @Published var clipboardHistoryLimit: Int {
        didSet { defaults.set(clipboardHistoryLimit, forKey: Key.clipboardHistoryLimit) }
    }

    /// Tab keys (`IslandTab.key`) in display order, hidden ones included.
    @Published var tabOrder: [String] {
        didSet { defaults.set(tabOrder, forKey: Key.tabOrder) }
    }

    /// Keys of tabs left out of the tab bar.
    @Published var hiddenTabs: [String] {
        didSet { defaults.set(hiddenTabs, forKey: Key.hiddenTabs) }
    }

    /// A light trackpad tap when the island opens.
    @Published var hapticFeedbackEnabled: Bool {
        didSet { defaults.set(hapticFeedbackEnabled, forKey: Key.hapticFeedbackEnabled) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    /// Full path to the quotes note.
    var quotesFilePath: String {
        (obsidianVaultPath as NSString).appendingPathComponent(quotesFileRelativePath)
    }

    /// Directory holding dated `YYYY-MM-DD.md` task notes.
    var dailyTasksPath: String {
        (obsidianVaultPath as NSString).appendingPathComponent("Daily Tasks")
    }

    /// Every tab in display order, hidden ones included — what Settings lists.
    var orderedTabs: [IslandTab] {
        IslandTab.arrange(order: tabOrder)
    }

    /// The tabs shown in the tab bar.
    var visibleTabs: [IslandTab] {
        IslandTab.arrange(order: tabOrder, hidden: Set(hiddenTabs))
    }

    func isTabVisible(_ tab: IslandTab) -> Bool {
        tab.isAlwaysVisible || !hiddenTabs.contains(tab.key)
    }

    func setTab(_ tab: IslandTab, visible: Bool) {
        guard !tab.isAlwaysVisible else { return }
        var hidden = hiddenTabs.filter { $0 != tab.key }
        if !visible { hidden.append(tab.key) }
        hiddenTabs = hidden
    }

    /// Move a tab `offset` places along the full order, clamped to the ends.
    func moveTab(_ tab: IslandTab, by offset: Int) {
        var keys = orderedTabs.map(\.key)
        guard let index = keys.firstIndex(of: tab.key) else { return }
        let target = min(max(index + offset, 0), keys.count - 1)
        guard target != index else { return }
        keys.remove(at: index)
        keys.insert(tab.key, at: target)
        tabOrder = keys
    }

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.obsidianVaultPath: Preferences.defaultVaultPath,
            Key.quotesFileRelativePath: "Quotes and ideas.md",
            Key.artworkLookupEnabled: true,
            Key.showOnExternalDisplays: true,
            Key.clipboardHistoryLimit: 15,
            Key.tabOrder: IslandTab.allCases.map(\.key),
            Key.hiddenTabs: [String](),
            Key.hapticFeedbackEnabled: true
        ])

        obsidianVaultPath = defaults.string(forKey: Key.obsidianVaultPath) ?? Preferences.defaultVaultPath
        quotesFileRelativePath = defaults.string(forKey: Key.quotesFileRelativePath) ?? "Quotes and ideas.md"
        artworkLookupEnabled = defaults.bool(forKey: Key.artworkLookupEnabled)
        showOnExternalDisplays = defaults.bool(forKey: Key.showOnExternalDisplays)
        clipboardHistoryLimit = max(1, defaults.integer(forKey: Key.clipboardHistoryLimit))
        tabOrder = defaults.stringArray(forKey: Key.tabOrder) ?? IslandTab.allCases.map(\.key)
        hiddenTabs = defaults.stringArray(forKey: Key.hiddenTabs) ?? []
        hapticFeedbackEnabled = defaults.bool(forKey: Key.hapticFeedbackEnabled)

        // Read the real registration state rather than trusting a stored flag, which
        // can drift if the user removes the login item in System Settings.
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            defaults.set(enabled, forKey: Key.launchAtLogin)
        } catch {
            Log.system.error("Failed to update launch-at-login: \(error.localizedDescription)")
            // Reflect the real state back into the UI rather than lying about it.
            DispatchQueue.main.async {
                self.launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }
}
