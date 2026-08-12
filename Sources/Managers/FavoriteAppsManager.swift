import Cocoa
import Combine

final class FavoriteAppsManager: ObservableObject {
    @Published var apps: [FavApp] = []

    private let storageKey = "FavoriteApps"

    init() {
        loadApps()
        if apps.isEmpty {
            // Pre-populate with standard macOS apps
            let defaults = [
                ("/System/Library/CoreServices/Finder.app", "Finder"),
                ("/Applications/Safari.app", "Safari"),
                ("/System/Applications/Music.app", "Music"),
                ("/System/Applications/Mail.app", "Mail"),
                ("/System/Applications/System Settings.app", "Settings"),
                ("/System/Applications/Utilities/Terminal.app", "Terminal")
            ]

            for (path, name) in defaults {
                if FileManager.default.fileExists(atPath: path) {
                    apps.append(FavApp(name: name, path: path))
                }
            }
            saveApps()
        }
    }

    func addApp(url: URL) {
        let path = url.path
        guard path.hasSuffix(".app") else { return }
        let name = url.deletingPathExtension().lastPathComponent

        // Prevent duplicates
        if !apps.contains(where: { $0.path == path }) {
            apps.append(FavApp(name: name, path: path))
            saveApps()
        }
    }

    func removeApp(at index: Int) {
        guard apps.indices.contains(index) else { return }
        apps.remove(at: index)
        saveApps()
    }

    func remove(_ app: FavApp) {
        apps.removeAll { $0.id == app.id }
        saveApps()
    }

    func launchApp(_ app: FavApp) {
        let url = URL(fileURLWithPath: app.path)
        // Matches how the rest of the app opens bundles; `NSWorkspace.open(_:)` is the
        // generic file-opening call and reports no error for a missing bundle.
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error = error {
                Log.window.error("Failed to launch \(app.name, privacy: .public): \(error.localizedDescription)")
            }
        }
    }

    private func saveApps() {
        if let encoded = try? JSONEncoder().encode(apps) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    private func loadApps() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([FavApp].self, from: data) {
            self.apps = decoded
        }
    }
}
