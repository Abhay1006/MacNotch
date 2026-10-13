import SwiftUI
import Combine
import Cocoa

/// The island itself: a collapsed capsule that hugs the camera notch, expanding into a
/// tabbed panel on hover.
///
/// The view fills a fixed, mostly transparent canvas (`NotchMetrics.canvasSize`) and
/// draws the island top-centred inside it, so growing and shrinking is a single SwiftUI
/// animation with room left over for the drop shadow.
///
/// Managers are *not* created here. They live in `AppEnvironment` and are shared by every
/// screen — one view per display used to mean one of everything per display.
struct NotchIslandView: View {
    @ObservedObject var appState: AppState
    let metrics: NotchMetrics
    var onSizeChanged: (CGSize) -> Void

    private let env = AppEnvironment.shared

    // Only what `body` and `collapsedSize` actually read. Every `@ObservedObject` here
    // re-evaluates the whole island, on every display, whenever that manager publishes
    // anything — so managers the root merely calls into or listens to are held plainly.
    @ObservedObject private var music: MusicManager
    @ObservedObject private var sports: SportsManager
    @ObservedObject private var zen: ZenManager
    @ObservedObject private var notifications: NotificationManager
    @ObservedObject private var fileShelf: FileShelfManager
    @ObservedObject private var preferences: Preferences

    private let clipboard: ClipboardManager
    private let favoriteApps: FavoriteAppsManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        _sports = ObservedObject(wrappedValue: env.sports)
        _zen = ObservedObject(wrappedValue: env.zen)
        _notifications = ObservedObject(wrappedValue: env.notifications)
        _fileShelf = ObservedObject(wrappedValue: env.fileShelf)
        _preferences = ObservedObject(wrappedValue: env.preferences)
        clipboard = env.clipboard
        favoriteApps = env.favoriteApps
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

    /// Collapsed capsule size. The expanded panel has no fixed size: it takes the height
    /// its current tab lays out at, so tabs no longer need a hand-maintained height table.
    private var collapsedSize: CGSize {
        collapsedHasContent ? metrics.collapsedActive : metrics.collapsedIdle
    }

    var body: some View {
        island
            .frame(
                width: metrics.canvasSize.width,
                height: metrics.canvasSize.height,
                alignment: .top
            )
            .onChange(of: appState.isExpanded) { _, _ in updateTabVisibility() }
            .onChange(of: appState.currentTab) { _, tab in
                updateTabVisibility()
                if tab == .quotes { env.quotes.selectNewQuote() }
                if tab == .calendar { env.obsidian.scanTasks() }
            }
            .onChange(of: preferences.hiddenTabs) { _, _ in ensureCurrentTabIsVisible() }
            .onAppear { ensureCurrentTabIsVisible() }
            .onReceive(clipboard.$items) { items in
                handleClipboardChange(items)
            }
            .onReceive(music.$trackTitle) { title in
                handleTrackChange(title)
            }
            .onReceive(sports.$favoriteTeamMatch) { match in
                handleMatchChange(match)
            }
    }

    private var island: some View {
        ZStack(alignment: .top) {
            if isExpanded {
                expandedView
                    .transition(expandedTransition)
            } else {
                CollapsedIslandView(
                    metrics: metrics,
                    showFavoriteMatch: shouldShowFavoriteTeamMatchCollapsed
                )
                .transition(collapsedTransition)
            }
        }
        .frame(
            width: isExpanded ? metrics.expandedWidth : collapsedSize.width,
            height: isExpanded ? nil : collapsedSize.height,
            alignment: .top
        )
        // Lay the expanded panel out at its natural height rather than the canvas's.
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: IslandSizeKey.self, value: proxy.size)
            }
        )
        // Content is clipped to the outline so it never spills past the shape while
        // the island is still growing; the fill and shadow sit outside the clip.
        .clipShape(islandShape)
        .background(islandFill)
        .overlay(islandOutline)
        .contentShape(islandShape)
        .contextMenu { islandContextMenu }
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers)
        }
        .onPreferenceChange(IslandSizeKey.self) { size in
            onSizeChanged(size)
        }
    }

    /// Expanded content waits a beat so it fades in once there is room for it, instead
    /// of being squeezed into a capsule that is still growing.
    private var expandedTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.94, anchor: .top))
                .animation(.easeOut(duration: 0.22).delay(0.08)),
            removal: .opacity.animation(.easeIn(duration: 0.1))
        )
    }

    private var collapsedTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.1)),
            removal: .opacity.animation(.easeIn(duration: 0.08))
        )
    }

    /// Expanded, the top corners flare out into the screen edge so the panel grows out of
    /// the bezel like the camera notch; collapsed, it keeps its rounded pill shape.
    private var islandShape: NotchShape {
        NotchShape(topCornerRadius: isExpanded ? -10 : 15, bottomCornerRadius: isExpanded ? 24 : 15)
    }

    private var islandFill: some View {
        islandShape
            // Opaque when expanded so the top matches the black camera housing it meets.
            .fill(Color.black.opacity(isExpanded ? 1 : 0.85))
            // The idle capsule hides behind the camera; a shadow would peek out below it.
            .shadow(
                color: Color.black.opacity(isExpanded || collapsedHasContent ? 0.5 : 0),
                radius: 10, x: 0, y: 5
            )
    }

    private var islandOutline: some View {
        var outline = islandShape
        // No border along the screen edge when expanded — it would draw a seam where the
        // panel is meant to merge into the top of the screen.
        outline.closesTopEdge = !isExpanded

        return outline
            .stroke(isDragOver ? Color.pink : Color.white.opacity(0.12), lineWidth: isDragOver ? 2 : 1)
    }

    /// Right-click menu. Previously the only documented way to quit was focusing the
    /// clipboard search field and pressing Cmd+Q, or `killall MacNotch` in a terminal.
    @ViewBuilder
    private var islandContextMenu: some View {
        Button("Settings…") {
            withAnimation(springAnimation) {
                appState.currentTab = .settings
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
                ForEach(preferences.visibleTabs, id: \.self) { tab in
                    Button(action: {
                        withAnimation(springAnimation) {
                            appState.currentTab = tab
                        }
                    }) {
                        tabButtonContent(tab: tab)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel(tab.accessibilityLabel)
                    .accessibilityAddTraits(appState.currentTab == tab ? [.isSelected] : [])
                    .help(tab.accessibilityLabel)
                }
            }
            .padding(.bottom, 6)

            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.horizontal, 16)

            // Tab Contents
            Group {
                switch appState.currentTab {
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
            // Breathing room that used to come from padding every tab out to a fixed height.
            .padding(.top, 10)
            .padding(.bottom, 14)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .bottom)),
                removal: .opacity
            ))
        }
    }

    private func tabButtonContent(tab: IslandTab) -> some View {
        VStack(spacing: 4) {
            Image(systemName: tab.symbol)
                .font(.system(size: 14, weight: appState.currentTab == tab ? .semibold : .regular))
                .foregroundColor(appState.currentTab == tab ? .pink : .white.opacity(0.45))

            // Indicator line
            RoundedRectangle(cornerRadius: 1)
                .fill(appState.currentTab == tab ? Color.pink : Color.clear)
                .frame(width: 14, height: 2)
        }
    }

    // MARK: - Behaviour

    /// Tells managers with tab-gated polling whether their tab is on screen.
    private func updateTabVisibility() {
        sports.setTabVisible(isExpanded && appState.currentTab == .sports)
        env.system.setTabVisible(isExpanded && appState.currentTab == .system)
    }

    /// Hiding the tab you're on in Settings mustn't leave the panel showing a tab that
    /// is no longer in the tab bar.
    private func ensureCurrentTabIsVisible() {
        let visible = preferences.visibleTabs
        if !visible.contains(appState.currentTab), let first = visible.first {
            appState.currentTab = first
        }
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
                            appState.currentTab = .apps
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
                            appState.currentTab = .clipboard
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

/// The island's laid-out size, reported to the window controller for hover and hit testing.
private struct IslandSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
