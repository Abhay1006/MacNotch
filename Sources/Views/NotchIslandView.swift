import SwiftUI
import Combine
import Cocoa

enum IslandTab: String, CaseIterable {
    case music = "music.note"
    case calendar = "calendar"
    case sports = "trophy"
    case clipboard = "doc.on.clipboard"
    case system = "slider.horizontal.3"
    case zen = "leaf.fill"
    case apps = "square.grid.2x2.fill"
    case quotes = "quote.bubble.fill"
}

struct ShelfFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
}

class FileShelfManager: ObservableObject {
    @Published var files: [ShelfFile] = []
    
    func addFile(url: URL) {
        if !files.contains(where: { $0.url == url }) {
            files.append(ShelfFile(url: url))
        }
    }
    
    func removeFile(at index: Int) {
        files.remove(at: index)
    }
    
    func clear() {
        files.removeAll()
    }
}

struct NotchNotification: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let tintColor: Color
}

class NotificationManager: ObservableObject {
    @Published var activeNotification: NotchNotification? = nil
    private var collapseTimer: Timer?
    
    func showNotification(title: String, subtitle: String, systemImage: String, tintColor: Color = .pink) {
        DispatchQueue.main.async {
            self.activeNotification = NotchNotification(title: title, subtitle: subtitle, systemImage: systemImage, tintColor: tintColor)
            
            // Auto collapse / dismiss after 3 seconds
            self.collapseTimer?.invalidate()
            self.collapseTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    self?.activeNotification = nil
                }
            }
        }
    }
}

struct NotchIslandView: View {
    @ObservedObject var appState: AppState
    
    @StateObject var musicManager = MusicManager()
    @StateObject var clipboardManager = ClipboardManager()
    @StateObject var systemManager = SystemManager()
    @StateObject var fileShelfManager = FileShelfManager()
    @StateObject var notificationManager = NotificationManager()
    @StateObject var sportsManager = SportsManager()
    @StateObject var zenManager = ZenManager()
    @StateObject var favoriteAppsManager = FavoriteAppsManager()
    @StateObject var quotesManager = QuotesManager()
    
    var isExpanded: Bool { appState.isExpanded }
    @State private var currentTab: IslandTab = .music
    @State private var hoveredAppId: UUID? = nil
    @State private var clipboardSearch = ""
    @State private var appColumns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    @State private var recentlyCopiedId: UUID? = nil
    @State private var isDragOver = false
    @State private var lastNotifiedTrack = ""
    @State private var lastClipboardItemId: UUID? = nil
    @State private var lastHomeScore: Int? = nil
    @State private var lastAwayScore: Int? = nil
    @State private var lastMatchId: String? = nil
    @State private var lastMatchStatusState: String? = nil
    @State private var lastMatchStatusDetail: String? = nil
    
    @State private var currentTime = Date()
    let updateTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var shouldShowFavoriteTeamMatchCollapsed: Bool {
        guard let match = sportsManager.favoriteTeamMatch else { return false }
        if match.isLive {
            return true
        }
        
        if match.isScheduled {
            if let kickoff = match.timeUntilKickoff {
                if kickoff <= 1800 {
                    return true
                }
            }
            return false
        }
        
        if match.isFinished {
            return false
        }
        
        return false
    }
    
    // Callback to resize the window when content size changes
    var onSizeChanged: (CGSize) -> Void
    
    // Size constants for different states
    var bodySize: CGSize {
        if !isExpanded {
            // Collapsed size (fits around the notch)
            if zenManager.isActive {
                return CGSize(width: 300, height: 35)
            }
            if notificationManager.activeNotification != nil {
                return CGSize(width: 300, height: 35)
            }
            if let match = sportsManager.favoriteTeamMatch, match.isLive {
                return CGSize(width: 300, height: 35)
            }
            if musicManager.isPlaying {
                return CGSize(width: 300, height: 35)
            }
            if sportsManager.favoriteTeamMatch != nil && shouldShowFavoriteTeamMatchCollapsed {
                return CGSize(width: 300, height: 35)
            }
            return CGSize(width: 110, height: 22) // Hide behind the camera!
        }
        
        switch currentTab {
        case .music:
            return CGSize(width: 380, height: 170)
        case .calendar:
            return CGSize(width: 380, height: 170)
        case .sports:
            return CGSize(width: 380, height: sportsManager.favoriteTeamMatch != nil ? 335 : 255)
        case .clipboard:
            return CGSize(width: 380, height: fileShelfManager.files.isEmpty ? 355 : 390)
        case .system:
            return CGSize(width: 380, height: 170)
        case .zen:
            return CGSize(width: 380, height: 190)
        case .apps:
            return CGSize(width: 380, height: 210)
        case .quotes:
            return CGSize(width: 380, height: 170)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if !isExpanded {
                collapsedView
            } else {
                expandedView
            }
        }
        .frame(width: bodySize.width, height: bodySize.height)
        .background(
            RoundedRectangle(cornerRadius: isExpanded ? 24 : 15)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: isExpanded ? 24 : 15)
                        .stroke(isDragOver ? Color.pink : Color.white.opacity(0.12), lineWidth: isDragOver ? 2 : 1)
                )
                .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 5)
        )
        .onChange(of: appState.isExpanded) { _, newValue in
            if newValue && currentTab == .sports {
                sportsManager.fetchScores()
            }
        }
        .onChange(of: currentTab) {
            if currentTab == .sports {
                sportsManager.fetchScores()
            } else if currentTab == .quotes {
                quotesManager.selectNewQuote()
            }
        }
        .onChange(of: bodySize) { _, newSize in
            onSizeChanged(newSize)
        }
        .onAppear {
            updateWindowSize()
        }
        .onReceive(updateTimer) { _ in
            currentTime = Date()
            updateWindowSize()
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            if url.path.hasSuffix(".app") {
                                favoriteAppsManager.addApp(url: url)
                                notificationManager.showNotification(
                                    title: "Added Favorite App",
                                    subtitle: url.deletingPathExtension().lastPathComponent,
                                    systemImage: "square.grid.3x3.topleft.filled",
                                    tintColor: .green
                                )
                                withAnimation {
                                    currentTab = .apps
                                    appState.isExpanded = true
                                }
                            } else {
                                fileShelfManager.addFile(url: url)
                                notificationManager.showNotification(
                                    title: "Added to File Shelf",
                                    subtitle: url.lastPathComponent,
                                    systemImage: "doc.badge.plus"
                                )
                                withAnimation {
                                    currentTab = .clipboard
                                    appState.isExpanded = true
                                }
                            }
                        }
                    }
                }
            }
            return true
        }
        .onReceive(clipboardManager.$items) { items in
            guard let firstItem = items.first else { return }
            if lastClipboardItemId == nil {
                // Initialize on startup without triggering a notification
                lastClipboardItemId = firstItem.id
                return
            }
            if firstItem.id != lastClipboardItemId {
                lastClipboardItemId = firstItem.id
                notificationManager.showNotification(
                    title: "Copied",
                    subtitle: firstItem.preview,
                    systemImage: "doc.on.doc"
                )
            }
        }
        .onReceive(musicManager.$trackTitle) { title in
            if musicManager.activePlayer != .none && title != "Not Playing" && title != lastNotifiedTrack {
                lastNotifiedTrack = title
                notificationManager.showNotification(
                    title: title,
                    subtitle: musicManager.artist,
                    systemImage: "music.note",
                    tintColor: .pink
                )
            }
        }
        .onReceive(sportsManager.$favoriteTeamMatch) { match in
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
            let currentStatusState = match.statusState
            let currentStatusDetail = match.statusDetail
            
            // Only trigger notifications if we are tracking the same match
            if lastMatchId == match.id {
                // 1. Goal Notification
                if let prevHome = lastHomeScore, currentHomeScore > prevHome {
                    notificationManager.showNotification(
                        title: "⚽ GOAL! for \(match.homeTeam)",
                        subtitle: "\(match.homeAbbr) \(currentHomeScore) - \(currentAwayScore) \(match.awayAbbr)",
                        systemImage: "soccerball",
                        tintColor: .green
                    )
                } else if let prevAway = lastAwayScore, currentAwayScore > prevAway {
                    notificationManager.showNotification(
                        title: "⚽ GOAL! for \(match.awayTeam)",
                        subtitle: "\(match.homeAbbr) \(currentHomeScore) - \(currentAwayScore) \(match.awayAbbr)",
                        systemImage: "soccerball",
                        tintColor: .green
                    )
                }
                
                // 2. Kickoff Notification (pre -> in)
                if let prevState = lastMatchStatusState, prevState == "pre" && currentStatusState == "in" {
                    notificationManager.showNotification(
                        title: "⚽ Kick-off!",
                        subtitle: "\(match.homeTeam) vs \(match.awayTeam)",
                        systemImage: "play.fill",
                        tintColor: .green
                    )
                }
                
                // 3. Half Time Notification (statusDetail changes to HT)
                if let prevDetail = lastMatchStatusDetail, prevDetail != "HT" && currentStatusDetail == "HT" {
                    notificationManager.showNotification(
                        title: "⏸️ Half Time",
                        subtitle: "\(match.homeAbbr) \(currentHomeScore) - \(currentAwayScore) \(match.awayAbbr)",
                        systemImage: "pause.fill",
                        tintColor: .orange
                    )
                }
                
                // 4. Full Time Notification (in -> post)
                if let prevState = lastMatchStatusState, prevState == "in" && currentStatusState == "post" {
                    notificationManager.showNotification(
                        title: "🏁 Full Time",
                        subtitle: "\(match.homeAbbr) \(currentHomeScore) - \(currentAwayScore) \(match.awayAbbr)",
                        systemImage: "flag.checkered",
                        tintColor: .red
                    )
                }
            }
            
            lastMatchId = match.id
            lastHomeScore = currentHomeScore
            lastAwayScore = currentAwayScore
            lastMatchStatusState = currentStatusState
            lastMatchStatusDetail = currentStatusDetail
        }
        .onChange(of: systemManager.isBatteryCharging) { _, charging in
            notificationManager.showNotification(
                title: charging ? "Charging" : "Power Unplugged",
                subtitle: "\(systemManager.batteryPercentage)%",
                systemImage: charging ? "bolt.fill" : "battery.100",
                tintColor: charging ? .green : .pink
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ZenTimerFinished"))) { _ in
            notificationManager.showNotification(
                title: "🧘 Zen Rest Complete",
                subtitle: "Time to wake up!",
                systemImage: "leaf.fill",
                tintColor: .green
            )
        }
    }
    
    private func updateWindowSize() {
        onSizeChanged(bodySize)
    }
    
    // MARK: - Collapsed View
    private var collapsedView: some View {
        HStack(spacing: 8) {
            if let notification = notificationManager.activeNotification {
                // Dynamic Island Notification banner
                Image(systemName: notification.systemImage)
                    .foregroundColor(notification.tintColor)
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
                    .padding(.leading, 10)
                
                Spacer() // Completely clear camera notch area
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(notification.title)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(notification.subtitle)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .frame(width: 90, alignment: .leading)
                .padding(.trailing, 10)
            } else if zenManager.isActive {
                // Zen Timer Active State
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                }
                .padding(.leading, 10)
                
                Spacer() // Completely clear camera notch area
                
                HStack(spacing: 6) {
                    Text(zenManager.timeFormatted)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                }
                .padding(.trailing, 10)
            } else if let match = sportsManager.favoriteTeamMatch, match.isLive {
                // Left side: Home Team score and logo at extreme left end
                HStack(spacing: 5) {
                    Text("\(match.homeScore)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    if let logo = match.homeLogo, let url = URL(string: logo) {
                        AsyncImage(url: url) { image in
                            image.resizable()
                        } placeholder: {
                            Color.white.opacity(0.1)
                        }
                        .frame(width: 16, height: 16)
                        .clipShape(Circle())
                    }
                }
                .padding(.leading, 10)
                
                Spacer() // Completely clear the camera notch area in the center!
                
                // Right side: Status, Away logo, and score at extreme right end
                HStack(spacing: 5) {
                    Text("(\(match.statusDetail))")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(.green)
                    
                    if let logo = match.awayLogo, let url = URL(string: logo) {
                        AsyncImage(url: url) { image in
                            image.resizable()
                        } placeholder: {
                            Color.white.opacity(0.1)
                        }
                        .frame(width: 16, height: 16)
                        .clipShape(Circle())
                    }
                    
                    Text("\(match.awayScore)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.trailing, 10)
            } else if musicManager.isPlaying {
                // Left side: tiny album thumbnail/icon or artwork
                Group {
                    if let artwork = musicManager.artworkImage {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "music.note.house")
                            .foregroundColor(.pink)
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 18, height: 18)
                            .background(Color.white.opacity(0.1))
                    }
                }
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.leading, 10)
                
                Spacer() // Completely clear the camera notch area in the center!
                
                // Right side: Audio visualizer (no track title in collapsed view)
                MiniVisualizer(isPlaying: true, color: .pink)
                    .padding(.trailing, 10)
            } else if let match = sportsManager.favoriteTeamMatch, match.isScheduled, shouldShowFavoriteTeamMatchCollapsed {
                // Left side: Home Team logo
                HStack(spacing: 5) {
                    if let logo = match.homeLogo, let url = URL(string: logo) {
                        AsyncImage(url: url) { image in
                            image.resizable()
                        } placeholder: {
                            Color.white.opacity(0.1)
                        }
                        .frame(width: 16, height: 16)
                        .clipShape(Circle())
                    }
                }
                .padding(.leading, 10)
                
                Spacer() // Completely clear center camera area
                
                // Right side: Away logo and Start Time (statusDetail)
                HStack(spacing: 5) {
                    if let logo = match.awayLogo, let url = URL(string: logo) {
                        AsyncImage(url: url) { image in
                            image.resizable()
                        } placeholder: {
                            Color.white.opacity(0.1)
                        }
                        .frame(width: 16, height: 16)
                        .clipShape(Circle())
                    }
                    
                    Text("(\(match.statusDetail))")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.trailing, 10)
            } else if let match = sportsManager.favoriteTeamMatch, match.isFinished, shouldShowFavoriteTeamMatchCollapsed {
                // Left side: Home Team score and logo at extreme left end
                HStack(spacing: 5) {
                    Text("\(match.homeScore)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                    
                    if let logo = match.homeLogo, let url = URL(string: logo) {
                        AsyncImage(url: url) { image in
                            image.resizable()
                        } placeholder: {
                            Color.white.opacity(0.1)
                        }
                        .frame(width: 16, height: 16)
                        .clipShape(Circle())
                    }
                }
                .padding(.leading, 10)
                
                Spacer() // Completely clear center camera area
                
                // Right side: Status, Away logo, and score at extreme right end
                HStack(spacing: 5) {
                    Text("(\(match.statusDetail))")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                    
                    if let logo = match.awayLogo, let url = URL(string: logo) {
                        AsyncImage(url: url) { image in
                            image.resizable()
                        } placeholder: {
                            Color.white.opacity(0.1)
                        }
                        .frame(width: 16, height: 16)
                        .clipShape(Circle())
                    }
                    
                    Text("\(match.awayScore)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.trailing, 10)
            } else {
                // Idle state: Hidden behind the camera notch
                Color.clear
            }
        }
        .frame(height: 35)
    }
    
    // MARK: - Expanded View
    private var expandedView: some View {
        VStack(spacing: 0) {
            // Unobstructed space for the physical camera notch
            Color.clear
                .frame(height: 35)
            
            // Tab Header (centered, below the notch)
            HStack(spacing: 16) {
                ForEach(IslandTab.allCases, id: \.self) { tab in
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            currentTab = tab
                        }
                    }) {
                        tabButtonContent(tab: tab)
                    }
                    .buttonStyle(PlainButtonStyle())
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
                    musicTabContent
                case .calendar:
                    calendarTabContent
                case .sports:
                    sportsTabContent
                case .clipboard:
                    clipboardTabContent
                case .system:
                    systemTabContent
                case .zen:
                    zenTabContent
                case .apps:
                    appsTabContent
                case .quotes:
                    quotesTabContent
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
            Image(systemName: tab.rawValue)
                .font(.system(size: 15, weight: currentTab == tab ? .semibold : .regular))
                .foregroundColor(currentTab == tab ? .pink : .white.opacity(0.4))
            
            // Indicator line
            RoundedRectangle(cornerRadius: 1)
                .fill(currentTab == tab ? Color.pink : Color.clear)
                .frame(width: 14, height: 2)
        }
    }
    
    // MARK: - Zen Content
    private var zenTabContent: some View {
        VStack(spacing: 6) {
            Text("Zen Mode")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            if zenManager.isActive {
                VStack(spacing: 3) {
                    Text(zenManager.timeFormatted)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                    
                    Text("Take a deep breath and rest.")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Button(action: {
                        withAnimation {
                            zenManager.stopTimer()
                        }
                    }) {
                        Text("Stop Session")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.3))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.red.opacity(0.5), lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.top, 2)
                }
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: 12) {
                        Button(action: {
                            zenManager.adjustDuration(by: -5 * 60)
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Text(zenManager.durationFormatted)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: 70)
                        
                        Button(action: {
                            zenManager.adjustDuration(by: 5 * 60)
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Button(action: {
                        withAnimation {
                            zenManager.startTimer()
                            appState.isExpanded = false
                        }
                    }) {
                        Text("Start Rest Timer")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.black)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                            .background(Color.green)
                            .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(height: 105)
    }
    
    // MARK: - Apps Content
    private var appsTabContent: some View {
        VStack(spacing: 6) {
            Text("Favorite Apps")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            if favoriteAppsManager.apps.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "square.grid.3x3.topleft.filled")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.3))
                    
                    Text("No favorite apps added yet.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(height: 80)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: appColumns, spacing: 12) {
                        ForEach(favoriteAppsManager.apps) { app in
                            VStack(spacing: 4) {
                                ZStack(alignment: .topTrailing) {
                                    Button(action: {
                                        favoriteAppsManager.launchApp(app)
                                    }) {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(8)
                                            .shadow(radius: 2)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    // Delete button shown on hover
                                    if hoveredAppId == app.id {
                                        Button(action: {
                                            if let index = favoriteAppsManager.apps.firstIndex(of: app) {
                                                withAnimation {
                                                    favoriteAppsManager.removeApp(at: index)
                                                }
                                            }
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.red)
                                                .background(Color.white.clipShape(Circle()))
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .offset(x: 6, y: -6)
                                        .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                .onHover { isHovering in
                                    withAnimation(.easeIn(duration: 0.1)) {
                                        hoveredAppId = isHovering ? app.id : nil
                                    }
                                }
                                
                                Text(app.name)
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineLimit(1)
                                    .frame(maxWidth: 60)
                            }
                            .contextMenu {
                                Button(action: {
                                    if let index = favoriteAppsManager.apps.firstIndex(of: app) {
                                        favoriteAppsManager.removeApp(at: index)
                                    }
                                }) {
                                    Label("Remove Favorite", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                }
                .frame(height: 80)
            }
            
            Text("Drag & drop .app here to add • Click (X) or Right-click to remove")
                .font(.system(size: 8, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
                .padding(.bottom, 2)
        }
        .padding(.horizontal, 15)
        .padding(.top, 8)
        .padding(.bottom, 5)
        .frame(height: 125)
    }
    
    // MARK: - Quotes Content
    private var quotesTabContent: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "quote.bubble.fill")
                    .foregroundColor(.pink)
                    .font(.system(size: 11))
                Text("Motivational Quote")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .textCase(.uppercase)
                Spacer()
                Button(action: {
                    withAnimation {
                        quotesManager.selectNewQuote()
                    }
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Get another quote")
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.pink.opacity(0.6))
                        .padding(.top, 2)
                    
                    Text(quotesManager.currentQuote)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 16)
        }
        .frame(height: 80)
    }
    
    // MARK: - Music Content
    private var musicTabContent: some View {
        HStack(spacing: 16) {
            // Album art placeholder
            ZStack {
                if let artwork = musicManager.artworkImage {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color.pink.opacity(0.4), Color.black],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 54, height: 54)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                    
                    Image(systemName: "music.note.house")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .onTapGesture {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
            }
            .onHover { inside in
                if inside {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .padding(.leading, 16)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(musicManager.trackTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(musicManager.artist.isEmpty ? "No active media" : musicManager.artist)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                
                // Track progress
                if musicManager.trackDuration > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 4)
                            
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.pink)
                                .frame(width: geo.size.width * CGFloat(musicManager.playerPosition / musicManager.trackDuration), height: 4)
                        }
                    }
                    .frame(height: 4)
                    .padding(.top, 4)
                }
            }
            
            Spacer()
            
            // Media Controls
            HStack(spacing: 12) {
                Button(action: { musicManager.previousTrack() }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.85))
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { musicManager.playPause() }) {
                    Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { musicManager.nextTrack() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.85))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.trailing, 16)
        }
        .frame(height: 80)
    }
    
    // MARK: - Calendar & Stats Content
    private var calendarTabContent: some View {
        HStack(spacing: 20) {
            // Calendar Event Widget
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.pink)
                    Text("Upcoming Event")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(systemManager.calendarManager.nextEventTitle)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(height: 28, alignment: .topLeading)
                    
                    if !systemManager.calendarManager.nextEventTime.isEmpty {
                        Text(systemManager.calendarManager.nextEventTime)
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding(8)
                .frame(width: 160, alignment: .leading)
                .background(Color.white.opacity(0.04))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .onTapGesture {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    }
                }
                .onHover { inside in
                    if inside {
                        NSCursor.pointingHand.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
            }
            .padding(.leading, 16)
            
            Divider()
                .background(Color.white.opacity(0.08))
                .frame(height: 60)
            
            // CPU & RAM Usage Stack
            VStack(spacing: 10) {
                // CPU Progress Bar
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "cpu")
                            .font(.system(size: 10))
                            .foregroundColor(.pink)
                        Text("CPU")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Text("\(systemManager.cpuUsage)%")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 4)
                            
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.pink)
                                .frame(width: geo.size.width * CGFloat(Double(systemManager.cpuUsage) / 100.0), height: 4)
                        }
                    }
                    .frame(height: 4)
                }
                
                // RAM Progress Bar
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "memorychip")
                            .font(.system(size: 10))
                            .foregroundColor(.pink)
                        Text("RAM")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Text("\(systemManager.ramUsage)%")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 4)
                            
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.pink)
                                .frame(width: geo.size.width * CGFloat(Double(systemManager.ramUsage) / 100.0), height: 4)
                        }
                    }
                    .frame(height: 4)
                }
            }
            .padding(.trailing, 16)
        }
        .frame(height: 80)
    }
    
    // MARK: - Clipboard Content
    private var clipboardTabContent: some View {
        VStack(spacing: 8) {
            // File Shelf (Drag & Drop zone)
            if !fileShelfManager.files.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(fileShelfManager.files) { file in
                            HStack(spacing: 6) {
                                Image(systemName: "doc.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.pink)
                                Text(file.name)
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .frame(maxWidth: 80)
                                
                                Button(action: {
                                    if let idx = fileShelfManager.files.firstIndex(of: file) {
                                        fileShelfManager.removeFile(at: idx)
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(6)
                            .onDrag {
                                NSItemProvider(contentsOf: file.url) ?? NSItemProvider()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 28)
                .padding(.top, 4)
            }
            
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.4))
                    .font(.system(size: 12))
                
                TextField("Search clipboard...", text: $clipboardSearch)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.white)
                
                if !clipboardSearch.isEmpty {
                    Button(action: { clipboardSearch = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            
            // Clipboard List
            ScrollView {
                VStack(spacing: 6) {
                    let filteredItems = clipboardManager.items.filter {
                        clipboardSearch.isEmpty ? true : $0.content.localizedCaseInsensitiveContains(clipboardSearch)
                    }
                    
                    if filteredItems.isEmpty {
                        Text("No items found")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.top, 24)
                    } else {
                        ForEach(filteredItems) { item in
                            HStack {
                                Text(item.preview)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.85))
                                    .lineLimit(1)
                                    .frame(maxWidth: 320, alignment: .leading)
                                
                                Spacer()
                                
                                if recentlyCopiedId == item.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 12))
                                } else {
                                    Image(systemName: "doc.on.doc")
                                        .foregroundColor(.white.opacity(0.4))
                                        .font(.system(size: 10))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(recentlyCopiedId == item.id ? 0.08 : 0.03))
                            .cornerRadius(6)
                            .onTapGesture {
                                clipboardManager.copyToClipboard(item: item)
                                withAnimation {
                                    recentlyCopiedId = item.id
                                }
                                // Reset copied checkmark
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    if recentlyCopiedId == item.id {
                                        recentlyCopiedId = nil
                                    }
                                }
                                
                                // Collapse the notch immediately and temporarily lock hover monitoring
                                appState.hoverLocked = true
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    appState.isExpanded = false
                                }
                                
                                // Restore focus to the previous active application
                                if let delegate = NSApp.delegate as? AppDelegate {
                                    delegate.restorePreviousActiveApp()
                                }
                                
                                // Unlock hover after a short delay (e.g. 1.0 second) to allow the mouse to leave
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    appState.hoverLocked = false
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(maxHeight: 180)
            
            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.horizontal, 16)
            
            // Clear History Button
            HStack {
                Spacer()
                Button(action: { clipboardManager.clearHistory() }) {
                    Text("Clear History")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.trailing, 16)
                .padding(.bottom, 8)
            }
        }
    }
    
    // MARK: - Sports Content
    private var sportsTabContent: some View {
        VStack(spacing: 8) {
            // Settings Header: Favorite Team & League
            HStack(spacing: 12) {
                // Favorite Team Input
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.pink)
                        .font(.system(size: 10))
                    
                    TextField("Fav Team (e.g. Arsenal)", text: $sportsManager.favoriteTeam)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .cornerRadius(6)
                
                // League Selector
                Menu {
                    ForEach(sportsManager.leaguesList, id: \.0) { league in
                        Button(action: {
                            withAnimation {
                                sportsManager.selectedLeague = league.0
                            }
                        }) {
                            Text(league.1)
                        }
                    }
                } label: {
                    HStack {
                        Text(sportsManager.leaguesList.first(where: { $0.0 == sportsManager.selectedLeague })?.1 ?? "Select League")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .menuIndicator(.hidden)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            
            // Favorite Team Spotlight Match (if playing today)
            if let favMatch = sportsManager.favoriteTeamMatch {
                VStack(spacing: 4) {
                    HStack {
                        Circle()
                            .fill(favMatch.isLive ? Color.green : (favMatch.isFinished ? Color.white.opacity(0.4) : Color.pink))
                            .frame(width: 6, height: 6)
                        
                        Text(favMatch.leagueName)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Spacer()
                        
                        Text(favMatch.statusDetail)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(favMatch.isLive ? .green : .white.opacity(0.8))
                    }
                    .padding(.horizontal, 8)
                    
                    HStack {
                        // Home Team
                        HStack {
                            Spacer()
                            Text(favMatch.homeTeam)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            if let logo = favMatch.homeLogo, let url = URL(string: logo) {
                                AsyncImage(url: url) { image in
                                    image.resizable()
                                } placeholder: {
                                    Color.white.opacity(0.1)
                                }
                                .frame(width: 16, height: 16)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        
                        // Score
                        Text("\(favMatch.homeScore) - \(favMatch.awayScore)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.pink)
                            .padding(.horizontal, 8)
                        
                        // Away Team
                        HStack {
                            if let logo = favMatch.awayLogo, let url = URL(string: logo) {
                                AsyncImage(url: url) { image in
                                    image.resizable()
                                } placeholder: {
                                    Color.white.opacity(0.1)
                                }
                                .frame(width: 16, height: 16)
                            }
                            
                            Text(favMatch.awayTeam)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 4)
                }
                .padding(8)
                .background(Color.pink.opacity(0.08))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.pink.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, 16)
            }
            
            // Matches List
            ScrollView {
                VStack(spacing: 8) {
                    if !sportsManager.favoriteTeam.isEmpty {
                        // SEARCH MODE
                        if sportsManager.isFetching && sportsManager.searchUpcomingMatches.isEmpty && sportsManager.searchLastGamePlayed == nil {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .pink))
                                .scaleEffect(0.8)
                                .padding(.top, 20)
                        } else if sportsManager.searchUpcomingMatches.isEmpty && sportsManager.searchLastGamePlayed == nil {
                            Text("No matches found for '\(sportsManager.favoriteTeam)'")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(.white.opacity(0.4))
                                .padding(.top, 24)
                        } else {
                            if let lastGame = sportsManager.searchLastGamePlayed {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("LAST GAME PLAYED")
                                        .font(.system(size: 8, weight: .bold, design: .rounded))
                                        .foregroundColor(.white.opacity(0.4))
                                        .padding(.leading, 2)
                                    
                                    SportsMatchRow(match: lastGame)
                                }
                            }
                            
                            if !sportsManager.searchUpcomingMatches.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    let leagueName = sportsManager.leaguesList.first(where: { $0.0 == sportsManager.selectedLeague })?.1 ?? "Selected League"
                                    Text("UPCOMING IN \(leagueName.uppercased())")
                                        .font(.system(size: 8, weight: .bold, design: .rounded))
                                        .foregroundColor(.white.opacity(0.4))
                                        .padding(.leading, 2)
                                        .padding(.top, 4)
                                    
                                    ForEach(sportsManager.searchUpcomingMatches) { match in
                                        SportsMatchRow(match: match)
                                    }
                                }
                            }
                        }
                    } else {
                        // DEFAULT MODE (SHOW TODAY'S MATCHES IN THE LEAGUE)
                        if sportsManager.isFetching && sportsManager.leagueMatches.isEmpty {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .pink))
                                .scaleEffect(0.8)
                                .padding(.top, 20)
                        } else if sportsManager.leagueMatches.isEmpty {
                            Text("No matches today")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(.white.opacity(0.4))
                                .padding(.top, 24)
                        } else {
                            ForEach(sportsManager.leagueMatches) { match in
                                SportsMatchRow(match: match)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(maxHeight: 140)
        }
    }

    // MARK: - System Content
    private var systemTabContent: some View {
        HStack(spacing: 20) {
            // Battery Widget
            VStack(alignment: .center, spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 4)
                        .frame(width: 44, height: 44)
                    
                    Circle()
                        .trim(from: 0.0, to: CGFloat(systemManager.batteryPercentage) / 100.0)
                        .stroke(
                            systemManager.isBatteryCharging ? Color.green : (systemManager.batteryPercentage < 20 ? Color.red : Color.pink),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(-90))
                    
                    VStack(spacing: 0) {
                        if systemManager.isBatteryCharging {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.green)
                        }
                        Text("\(systemManager.batteryPercentage)%")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
                Text("Battery")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.leading, 16)
            
            Divider()
                .background(Color.white.opacity(0.08))
                .frame(height: 50)
            
            // Volume and Brightness Sliders Stack
            VStack(spacing: 12) {
                // Volume Control
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Image(systemName: systemManager.systemVolume == 0 ? "speaker.slash.fill" : (systemManager.systemVolume < 33 ? "speaker.wave.1.fill" : (systemManager.systemVolume < 66 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")))
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                        
                        Text("Volume")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Text("\(systemManager.systemVolume)%")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Slider(value: Binding(
                        get: { Double(systemManager.systemVolume) },
                        set: { systemManager.setVolume(Int($0)) }
                    ), in: 0...100)
                    .accentColor(.pink)
                }
                
                // Brightness Control
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Image(systemName: systemManager.systemBrightness < 33 ? "sun.min.fill" : (systemManager.systemBrightness < 66 ? "sun.layout.fill" : "sun.max.fill"))
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                        
                        Text("Brightness")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Text("\(systemManager.systemBrightness)%")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Slider(value: Binding(
                        get: { Double(systemManager.systemBrightness) },
                        set: { systemManager.setBrightness(Int($0)) }
                    ), in: 0...100)
                    .accentColor(.pink)
                }
            }
            .padding(.trailing, 16)
        }
        .frame(height: 80)
    }
}

// MARK: - Mini Visualizer
struct MiniVisualizer: View {
    let isPlaying: Bool
    let color: Color
    @State private var barHeights: [CGFloat] = [6, 4, 8, 5, 7]
    let timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 2, height: isPlaying ? barHeights[index] : 2)
            }
        }
        .frame(height: 12)
        .onReceive(timer) { _ in
            if isPlaying {
                withAnimation(.linear(duration: 0.15)) {
                    barHeights = (0..<5).map { _ in CGFloat.random(in: 3...12) }
                }
            }
        }
    }
}

// MARK: - Zen Manager
class ZenManager: ObservableObject {
    @Published var isActive = false
    @Published var timeRemaining: TimeInterval = 15 * 60
    @Published var duration: TimeInterval = 15 * 60
    
    private var timer: Timer?
    
    func startTimer() {
        self.isActive = true
        self.timeRemaining = self.duration
        
        self.timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if self.timeRemaining > 1 {
                    self.timeRemaining -= 1
                } else {
                    self.timeRemaining = 0
                    self.stopTimer(finished: true)
                }
            }
        }
    }
    
    func stopTimer(finished: Bool = false) {
        self.timer?.invalidate()
        self.timer = nil
        self.isActive = false
        
        if finished {
            NotificationCenter.default.post(name: Notification.Name("ZenTimerFinished"), object: nil)
        }
    }
    
    func adjustDuration(by seconds: TimeInterval) {
        let newDuration = self.duration + seconds
        if newDuration >= 60 && newDuration <= 120 * 60 { // Min 1m, max 2h
            self.duration = newDuration
            if !isActive {
                self.timeRemaining = newDuration
            }
        }
    }
    
    var timeFormatted: String {
        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var durationFormatted: String {
        let minutes = Int(duration) / 60
        return "\(minutes) Min"
    }
}

// MARK: - FavApp model and FavoriteAppsManager
struct FavApp: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let path: String
    
    init(id: UUID = UUID(), name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }
}

class FavoriteAppsManager: ObservableObject {
    @Published var apps: [FavApp] = []
    
    init() {
        loadApps()
        if apps.isEmpty {
            // Pre-populate with standard macOS apps
            let defaults = [
                ("/System/Applications/Finder.app", "Finder"),
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
        guard index >= 0 && index < apps.count else { return }
        apps.remove(at: index)
        saveApps()
    }
    
    func launchApp(_ app: FavApp) {
        let url = URL(fileURLWithPath: app.path)
        NSWorkspace.shared.open(url)
    }
    
    private func saveApps() {
        if let encoded = try? JSONEncoder().encode(apps) {
            UserDefaults.standard.set(encoded, forKey: "FavoriteApps")
        }
    }
    
    private func loadApps() {
        if let data = UserDefaults.standard.data(forKey: "FavoriteApps"),
           let decoded = try? JSONDecoder().decode([FavApp].self, from: data) {
            self.apps = decoded
        }
    }
}

struct SportsMatchRow: View {
    let match: SportMatch
    
    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            HStack {
                // Home Team
                Text(match.homeTeam)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                
                // Score/Time
                if match.isScheduled {
                    Text(match.statusDetail)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(4)
                        .frame(width: 70)
                } else {
                    Text("\(match.homeScore) - \(match.awayScore)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(match.isLive ? .green : .white.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(match.isLive ? Color.green.opacity(0.12) : Color.white.opacity(0.08))
                        .cornerRadius(4)
                        .frame(width: 70)
                }
                
                // Away Team
                Text(match.awayTeam)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Text(match.leagueName)
                .font(.system(size: 7, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.03))
        .cornerRadius(6)
    }
}
