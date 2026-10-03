import Foundation
import Combine
import SwiftUI

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

    private var cancellables = Set<AnyCancellable>()

    private init() {
        wireAppWideBanners()
    }

    /// Banners that depend on app state rather than on any one window.
    ///
    /// These used to live in `NotchIslandView`, which meant the root view had to observe
    /// `SystemManager` (re-rendering on every sample) just to watch for a plug event, and
    /// each display's view posted its own copy of the same banner.
    private func wireAppWideBanners() {
        system.$isBatteryCharging
            .removeDuplicates()
            .sink { [unowned self] charging in
                // `@Published` delivers in willSet, before `hasBatteryReading` flips on
                // the first read — so the initial plugged-in state never fires a banner.
                guard self.system.hasBatteryReading else { return }
                self.notifications.showNotification(
                    title: charging ? "Charging" : "Power Unplugged",
                    subtitle: "\(self.system.batteryPercentage)%",
                    systemImage: charging ? "bolt.fill" : "battery.100",
                    tintColor: charging ? .green : .pink
                )
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: ZenManager.finishedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in
                self.notifications.showNotification(
                    title: "🧘 Zen Rest Complete",
                    subtitle: "Time to wake up!",
                    systemImage: "leaf.fill",
                    tintColor: .green
                )
            }
            .store(in: &cancellables)
    }
}
