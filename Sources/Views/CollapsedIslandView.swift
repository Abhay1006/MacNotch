import SwiftUI

/// The collapsed capsule.
///
/// Everything is laid out as `leading content — Spacer — trailing content` so the middle
/// stays clear of the physical camera housing.
struct CollapsedIslandView: View {
    let metrics: NotchMetrics
    let showFavoriteMatch: Bool

    @ObservedObject private var music: MusicManager
    @ObservedObject private var sports: SportsManager
    @ObservedObject private var zen: ZenManager
    @ObservedObject private var notifications: NotificationManager

    init(metrics: NotchMetrics, showFavoriteMatch: Bool) {
        self.metrics = metrics
        self.showFavoriteMatch = showFavoriteMatch

        let env = AppEnvironment.shared
        _music = ObservedObject(wrappedValue: env.music)
        _sports = ObservedObject(wrappedValue: env.sports)
        _zen = ObservedObject(wrappedValue: env.zen)
        _notifications = ObservedObject(wrappedValue: env.notifications)
    }

    var body: some View {
        HStack(spacing: 8) {
            content
        }
        .frame(height: metrics.collapsedActive.height)
        // One combined element for VoiceOver rather than a pile of unlabelled glyphs.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHidden(accessibilityDescription.isEmpty)
    }

    @ViewBuilder
    private var content: some View {
        if let notification = notifications.activeNotification {
            notificationBanner(notification)
        } else if zen.isActive {
            zenBanner
        } else if let match = sports.favoriteTeamMatch, match.isLive {
            liveMatchBanner(match)
        } else if music.isPlaying {
            musicBanner
        } else if let match = sports.favoriteTeamMatch, match.isScheduled, showFavoriteMatch {
            scheduledMatchBanner(match)
        } else if let match = sports.favoriteTeamMatch, match.isFinished, showFavoriteMatch {
            finishedMatchBanner(match)
        } else {
            // Idle: tucked behind the camera housing.
            Color.clear
        }
    }

    /// Spoken description of whatever the capsule is currently showing.
    private var accessibilityDescription: String {
        if let notification = notifications.activeNotification {
            return "\(notification.title). \(notification.subtitle)"
        }
        if zen.isActive {
            return "Zen timer, \(zen.timeFormatted) remaining"
        }
        if let match = sports.favoriteTeamMatch, match.isLive {
            return "Live: \(match.homeTeam) \(match.homeScore), \(match.awayTeam) \(match.awayScore), \(match.statusDetail)"
        }
        if music.isPlaying {
            return "Now playing: \(music.trackTitle)\(music.artist.isEmpty ? "" : " by \(music.artist)")"
        }
        if let match = sports.favoriteTeamMatch, showFavoriteMatch {
            if match.isScheduled {
                return "Upcoming: \(match.homeTeam) versus \(match.awayTeam), \(match.statusDetail)"
            }
            if match.isFinished {
                return "Final: \(match.homeTeam) \(match.homeScore), \(match.awayTeam) \(match.awayScore)"
            }
        }
        return ""
    }

    // MARK: - Banners

    @ViewBuilder
    private func notificationBanner(_ notification: NotchNotification) -> some View {
        Image(systemName: notification.systemImage)
            .foregroundColor(notification.tintColor)
            .font(.system(size: 11, weight: .bold))
            .frame(width: 18, height: 18)
            .background(Color.white.opacity(0.1))
            .clipShape(Circle())
            .padding(.leading, 10)

        Spacer()

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
    }

    @ViewBuilder
    private var zenBanner: some View {
        Image(systemName: "leaf.fill")
            .font(.system(size: 11))
            .foregroundColor(.green)
            .padding(.leading, 10)

        Spacer()

        Text(zen.timeFormatted)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.green)
            .monospacedDigit()
            .padding(.trailing, 10)
    }

    @ViewBuilder
    private func liveMatchBanner(_ match: SportMatch) -> some View {
        HStack(spacing: 5) {
            Text(match.homeScore)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            TeamLogo(url: match.homeLogo)
        }
        .padding(.leading, 10)

        Spacer()

        HStack(spacing: 5) {
            Text("(\(match.statusDetail))")
                .font(.system(size: 9, design: .rounded))
                .foregroundColor(.green)
            TeamLogo(url: match.awayLogo)
            Text(match.awayScore)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.trailing, 10)
    }

    @ViewBuilder
    private var musicBanner: some View {
        Group {
            if let artwork = music.artworkImage {
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

        Spacer()

        MiniVisualizer(isPlaying: true, color: .pink)
            .padding(.trailing, 10)
    }

    @ViewBuilder
    private func scheduledMatchBanner(_ match: SportMatch) -> some View {
        TeamLogo(url: match.homeLogo)
            .padding(.leading, 10)

        Spacer()

        HStack(spacing: 5) {
            TeamLogo(url: match.awayLogo)
            Text("(\(match.statusDetail))")
                .font(.system(size: 9, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.trailing, 10)
    }

    @ViewBuilder
    private func finishedMatchBanner(_ match: SportMatch) -> some View {
        HStack(spacing: 5) {
            Text(match.homeScore)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
            TeamLogo(url: match.homeLogo)
        }
        .padding(.leading, 10)

        Spacer()

        HStack(spacing: 5) {
            Text("(\(match.statusDetail))")
                .font(.system(size: 9, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
            TeamLogo(url: match.awayLogo)
            Text(match.awayScore)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.trailing, 10)
    }
}
