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

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.obsidianVaultPath: Preferences.defaultVaultPath,
            Key.quotesFileRelativePath: "Quotes and ideas.md",
            Key.artworkLookupEnabled: true,
            Key.showOnExternalDisplays: true,
            Key.clipboardHistoryLimit: 15
        ])

        obsidianVaultPath = defaults.string(forKey: Key.obsidianVaultPath) ?? Preferences.defaultVaultPath
        quotesFileRelativePath = defaults.string(forKey: Key.quotesFileRelativePath) ?? "Quotes and ideas.md"
        artworkLookupEnabled = defaults.bool(forKey: Key.artworkLookupEnabled)
        showOnExternalDisplays = defaults.bool(forKey: Key.showOnExternalDisplays)
        clipboardHistoryLimit = max(1, defaults.integer(forKey: Key.clipboardHistoryLimit))

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
