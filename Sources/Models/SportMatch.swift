import Foundation

struct SportMatch: Identifiable, Equatable {
    let id: String
    let leagueId: String
    let leagueName: String
    let homeTeam: String
    let awayTeam: String
    let homeAbbr: String
    let awayAbbr: String
    let homeScore: String
    let awayScore: String
    let statusState: String // "pre", "in", "post"
    let statusDetail: String // e.g. "72'", "FT", "19:30"
    let homeLogo: String?
    let awayLogo: String?

    /// Kick-off, parsed once at construction.
    ///
    /// This used to be re-derived from a raw `dateString` on every access, building up to
    /// three `DateFormatter`s per call — from inside sorts, filters, and a view property
    /// that was evaluated once a second. `DateFormatter` initialization is expensive.
    /// Sorting also compared the raw strings, which only happens to work while ESPN
    /// returns `Z`-suffixed UTC.
    let date: Date?

    var isLive: Bool { statusState == "in" }
    var isFinished: Bool { statusState == "post" }
    var isScheduled: Bool { statusState == "pre" }

    var timeUntilKickoff: TimeInterval? { date?.timeIntervalSinceNow }

    /// Sort key that keeps undated fixtures at the end rather than at the epoch.
    var sortDate: Date { date ?? .distantFuture }
}

// MARK: - Date handling

extension SportMatch {
    private static let isoFormatter = ISO8601DateFormatter()

    private static let fallbackFormatters: [DateFormatter] = {
        let patterns = ["yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd'T'HH:mmZ", "yyyy-MM-dd'T'HH:mm'Z'"]
        return patterns.map { pattern in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
            if pattern.hasSuffix("'Z'") {
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
            }
            return formatter
        }
    }()

    private static let todayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter
    }()

    /// Parse an ESPN timestamp. Formatters are cached statically — the whole point of
    /// doing this once per match rather than once per read.
    static func parseDate(from dateString: String) -> Date? {
        guard !dateString.isEmpty else { return nil }
        if let date = isoFormatter.date(from: dateString) { return date }
        for formatter in fallbackFormatters {
            if let date = formatter.date(from: dateString) { return date }
        }
        return nil
    }

    /// Kick-off rendered in the user's local timezone.
    static func formatMatchTime(from dateString: String) -> String? {
        guard let date = parseDate(from: dateString) else { return nil }
        return formatMatchTime(date)
    }

    static func formatMatchTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today \(todayFormatter.string(from: date))"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow \(todayFormatter.string(from: date))"
        }
        return dayFormatter.string(from: date)
    }
}
