import Foundation

/// The single owner of every manager in the app.
///
/// Previously each `NotchIslandView` created its own managers with `@StateObject`, and one
/// view was built per screen. With two displays that meant two AppleScript pollers, two ESPN
/// pollers (16 HTTP requests per cycle), two clipboard timers, and two Obsidian vault scanners
/// — all doing identical work. Worse, a `didChangeScreenParameters` notification rebuilt the
/// windows and therefore the managers, which leaked their timers and wiped clipboard history
/// and any running Zen session.
///
/// Managers now live here, outlive the windows, and are shared by every screen.
final class AppEnvironment {
    static let shared = AppEnvironment()

    let preferences = Preferences.shared

    let music = MusicManager()
    let clipboard = ClipboardManager()
    let system = SystemManager()
    let audio = AudioManager()
    let calendar = CalendarManager()
    let obsidian = ObsidianTaskManager()
    let sports = SportsManager()
    let quotes = QuotesManager()
    let zen = ZenManager()
    let notifications = NotificationManager()
    let fileShelf = FileShelfManager()
    let favoriteApps = FavoriteAppsManager()

    private init() {}
}
