import SwiftUI
import Combine
import Cocoa

/// The island itself: a collapsed capsule that hugs the camera notch, expanding into a
/// tabbed panel on hover.
///
/// Managers are *not* created here. They live in `AppEnvironment` and are shared by every
/// screen — one view per display used to mean one of everything per display.
struct NotchIslandView: View {
    @ObservedObject var appState: AppState
    let metrics: NotchMetrics
    var onSizeChanged: (CGSize) -> Void

    private let env = AppEnvironment.shared

    @ObservedObject private var music: MusicManager
    @ObservedObject private var clipboard: ClipboardManager
    @ObservedObject private var system: SystemManager
    @ObservedObject private var sports: SportsManager
    @ObservedObject private var zen: ZenManager
    @ObservedObject private var notifications: NotificationManager
    @ObservedObject private var fileShelf: FileShelfManager
    @ObservedObject private var favoriteApps: FavoriteAppsManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var currentTab: IslandTab = .music
    @State private var isDragOver = false

    // Notification de-duplication state
    @State private var lastNotifiedTrack = ""
    @State private var lastClipboardItemId: UUID? = nil
    @State private var lastHomeScore: Int? = nil
    @State private var lastAwayScore: Int? = nil
    @State private var lastMatchId: String? = nil
    @State private var lastMatchStatusState: String? = nil
    @State private var lastMatchStatusDetail: String? = nil

    init(appState: AppState, metrics: NotchMetrics, onSizeChanged: @escaping (CGSize) -> Void) {
        self.appState = appState
        self.metrics = metrics
        self.onSizeChanged = onSizeChanged

        let env = AppEnvironment.shared
        _music = ObservedObject(wrappedValue: env.music)
        _clipboard = ObservedObject(wrappedValue: env.clipboard)
        _system = ObservedObject(wrappedValue: env.system)
        _sports = ObservedObject(wrappedValue: env.sports)
        _zen = ObservedObject(wrappedValue: env.zen)
        _notifications = ObservedObject(wrappedValue: env.notifications)
        _fileShelf = ObservedObject(wrappedValue: env.fileShelf)
        _favoriteApps = ObservedObject(wrappedValue: env.favoriteApps)
    }

    var isExpanded: Bool { appState.isExpanded }

    /// Respects the "Reduce Motion" accessibility setting.
    private var springAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)
    }

    var shouldShowFavoriteTeamMatchCollapsed: Bool {
        guard let match = sports.favoriteTeamMatch else { return false }
        if match.isLive { return true }
        if match.isScheduled, let kickoff = match.timeUntilKickoff {
            return kickoff <= 1800
        }
        return false
    }

    /// Whether the collapsed capsule has content that must clear the camera on both sides.
    private var collapsedHasContent: Bool {
        if zen.isActive { return true }
        if notifications.activeNotification != nil { return true }
        if music.isPlaying { return true }
        if sports.favoriteTeamMatch?.isLive == true { return true }
        return sports.favoriteTeamMatch != nil && shouldShowFavoriteTeamMatchCollapsed
    }

    /// Content height per tab, *excluding* the space reserved for the physical camera.
    private var tabContentHeight: CGFloat {
        switch currentTab {
        case .music: return 135
        case .calendar: return 135
        case .sports: return sports.favoriteTeamMatch != nil ? 300 : 220
        case .clipboard: return fileShelf.files.isEmpty ? 320 : 355
        case .system: return 190
        case .zen: return 155
        case .apps: return 175
        case .quotes: return 135
        case .settings: return 205
        }
    }

    var bodySize: CGSize {
        guard isExpanded else {
            return collapsedHasContent ? metrics.collapsedActive : metrics.collapsedIdle
        }
        return CGSize(
            width: metrics.expandedWidth,
            height: metrics.expandedTopClearance + tabContentHeight
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isExpanded {
                CollapsedIslandView(
                    metrics: metrics,
                    showFavoriteMatch: shouldShowFavoriteTeamMatchCollapsed
                )
            } else {
                expandedView
            }
        }
        .frame(width: bodySize.width, height: bodySize.height)
        .background(islandBackground)
        .contextMenu { islandContextMenu }
        .onChange(of: appState.isExpanded) { _, _ in updateTabVisibility() }
        .onChange(of: currentTab) { _, _ in
            updateTabVisibility()
            if currentTab == .quotes { env.quotes.selectNewQuote() }
            if currentTab == .calendar { env.obsidian.scanTasks() }
        }
        .onChange(of: bodySize) { _, newSize in
            onSizeChanged(newSize)
        }
        .onAppear {
            onSizeChanged(bodySize)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers)
        }
        .onReceive(clipboard.$items) { items in
            handleClipboardChange(items)
        }
        .onReceive(music.$trackTitle) { title in
            handleTrackChange(title)
        }
        .onReceive(sports.$favoriteTeamMatch) { match in
            handleMatchChange(match)
        }
        .onChange(of: system.isBatteryCharging) { _, charging in
            // Skip until a real power-source reading has landed. `isBatteryCharging`
            // starts false, so the first poll on a plugged-in Mac used to fire a
            // spurious "Charging" banner on every launch.
            guard system.hasBatteryReading else { return }
            notifications.showNotification(
                title: charging ? "Charging" : "Power Unplugged",
                subtitle: "\(system.batteryPercentage)%",
                systemImage: charging ? "bolt.fill" : "battery.100",
                tintColor: charging ? .green : .pink
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: ZenManager.finishedNotification)) { _ in
            notifications.showNotification(
                title: "🧘 Zen Rest Complete",
                subtitle: "Time to wake up!",
                systemImage: "leaf.fill",
                tintColor: .green
            )
        }
    }

    private var islandBackground: some View {
        RoundedRectangle(cornerRadius: isExpanded ? 24 : 15)
            .fill(Color.black.opacity(0.85))
            .overlay(
                RoundedRectangle(cornerRadius: isExpanded ? 24 : 15)
                    .stroke(isDragOver ? Color.pink : Color.white.opacity(0.12), lineWidth: isDragOver ? 2 : 1)
            )
            .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 5)
    }

    /// Right-click menu. Previously the only documented way to quit was focusing the
    /// clipboard search field and pressing Cmd+Q, or `killall MacNotch` in a terminal.
    @ViewBuilder
    private var islandContextMenu: some View {
        Button("Settings…") {
            withAnimation(springAnimation) {
                currentTab = .settings
                appState.isExpanded = true
            }
        }
        Divider()
        Button("Quit MacNotch") {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Expanded View

    private var expandedView: some View {
        VStack(spacing: 0) {
            // Unobstructed space for the physical camera notch
            Color.clear
                .frame(height: metrics.expandedTopClearance)

            // Tab Header (centered, below the notch)
            HStack(spacing: 13) {
                ForEach(IslandTab.allCases, id: \.self) { tab in
                    Button(action: {
                        withAnimation(springAnimation) {
                            currentTab = tab
                        }
                    }) {
                        tabButtonContent(tab: tab)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel(tab.accessibilityLabel)
                    .accessibilityAddTraits(currentTab == tab ? [.isSelected] : [])
                    .help(tab.accessibilityLabel)
                }
            }
            .padding(.bottom, 6)

            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.horizontal, 16)

            // Tab Contents
            Group {
                switch currentTab {
                case .music:
                    MusicTab(music: env.music)
                case .calendar:
                    CalendarTab(calendar: env.calendar, obsidian: env.obsidian)
                case .sports:
                    SportsTab(sports: env.sports)
                case .clipboard:
                    ClipboardTab(
                        clipboard: env.clipboard,
                        fileShelf: env.fileShelf,
                        appState: appState
                    )
                case .system:
                    SystemTab(system: env.system, audio: env.audio)
                case .zen:
                    ZenTab(zen: env.zen, appState: appState)
                case .apps:
                    AppsTab(favoriteApps: env.favoriteApps)
                case .quotes:
                    QuotesTab(quotes: env.quotes)
                case .settings:
                    SettingsTab(preferences: env.preferences)
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .bottom)),
                removal: .opacity
            ))
        }
    }

    private func tabButtonContent(tab: IslandTab) -> some View {
        VStack(spacing: 4) {
            Image(systemName: tab.symbol)
                .font(.system(size: 14, weight: currentTab == tab ? .semibold : .regular))
                .foregroundColor(currentTab == tab ? .pink : .white.opacity(0.45))

            // Indicator line
            RoundedRectangle(cornerRadius: 1)
                .fill(currentTab == tab ? Color.pink : Color.clear)
                .frame(width: 14, height: 2)
        }
    }

    // MARK: - Behaviour

    /// Tells the sports manager whether it is on screen, which drives its poll cadence.
    private func updateTabVisibility() {
        sports.setTabVisible(isExpanded && currentTab == .sports)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                DispatchQueue.main.async {
                    if url.pathExtension == "app" {
                        favoriteApps.addApp(url: url)
                        notifications.showNotification(
                            title: "Added Favorite App",
                            subtitle: url.deletingPathExtension().lastPathComponent,
                            systemImage: "square.grid.3x3.topleft.filled",
                            tintColor: .green
                        )
                        withAnimation(springAnimation) {
                            currentTab = .apps
                            appState.isExpanded = true
                        }
                    } else {
                        fileShelf.addFile(url: url)
                        notifications.showNotification(
                            title: "Added to File Shelf",
                            subtitle: url.lastPathComponent,
                            systemImage: "doc.badge.plus"
                        )
                        withAnimation(springAnimation) {
                            currentTab = .clipboard
                            appState.isExpanded = true
                        }
                    }
                }
            }
        }
        return true
    }

    private func handleClipboardChange(_ items: [ClipboardManager.ClipboardItem]) {
        guard let firstItem = items.first else { return }
        if lastClipboardItemId == nil {
            // Initialize on startup without triggering a notification
            lastClipboardItemId = firstItem.id
            return
        }
        if firstItem.id != lastClipboardItemId {
            lastClipboardItemId = firstItem.id
            notifications.showNotification(
                title: "Copied",
                subtitle: firstItem.preview,
                systemImage: "doc.on.doc"
            )
        }
    }

    private func handleTrackChange(_ title: String) {
        guard music.activePlayer != .none, title != "Not Playing", title != lastNotifiedTrack else { return }
        lastNotifiedTrack = title
        notifications.showNotification(
            title: title,
            subtitle: music.artist,
            systemImage: "music.note",
            tintColor: .pink
        )
    }

    private func handleMatchChange(_ match: SportMatch?) {
        guard let match = match else {
            lastMatchId = nil
            lastHomeScore = nil
            lastAwayScore = nil
            lastMatchStatusState = nil
            lastMatchStatusDetail = nil
            return
        }

        let currentHomeScore = Int(match.homeScore) ?? 0
        let currentAwayScore = Int(match.awayScore) ?? 0
        let scoreline = "\(match.homeAbbr) \(currentHomeScore) - \(currentAwayScore) \(match.awayAbbr)"

        // Only trigger notifications if we are tracking the same match
        if lastMatchId == match.id {
            if let prevHome = lastHomeScore, currentHomeScore > prevHome {
                notifications.showNotification(
                    title: "⚽ GOAL! for \(match.homeTeam)",
                    subtitle: scoreline,
                    systemImage: "soccerball",
                    tintColor: .green
                )
            } else if let prevAway = lastAwayScore, currentAwayScore > prevAway {
                notifications.showNotification(
                    title: "⚽ GOAL! for \(match.awayTeam)",
                    subtitle: scoreline,
                    systemImage: "soccerball",
                    tintColor: .green
                )
            }

            if lastMatchStatusState == "pre" && match.statusState == "in" {
                notifications.showNotification(
                    title: "⚽ Kick-off!",
                    subtitle: "\(match.homeTeam) vs \(match.awayTeam)",
                    systemImage: "play.fill",
                    tintColor: .green
                )
            }

            if let prevDetail = lastMatchStatusDetail, prevDetail != "HT", match.statusDetail == "HT" {
                notifications.showNotification(
                    title: "⏸️ Half Time",
                    subtitle: scoreline,
                    systemImage: "pause.fill",
                    tintColor: .orange
                )
            }

            if lastMatchStatusState == "in" && match.statusState == "post" {
                notifications.showNotification(
                    title: "🏁 Full Time",
                    subtitle: scoreline,
                    systemImage: "flag.checkered",
                    tintColor: .red
                )
            }
        }

        lastMatchId = match.id
        lastHomeScore = currentHomeScore
        lastAwayScore = currentAwayScore
        lastMatchStatusState = match.statusState
        lastMatchStatusDetail = match.statusDetail
    }
}
