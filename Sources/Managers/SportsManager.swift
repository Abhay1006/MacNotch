import Foundation
import Combine

class SportsManager: ObservableObject {
    @Published var favoriteTeam: String
    @Published var selectedLeague: String

    @Published var leagueMatches: [SportMatch] = []
    @Published var favoriteTeamMatch: SportMatch? = nil
    @Published var isFetching = false

    @Published var searchUpcomingMatches: [SportMatch] = []
    @Published var searchLastGamePlayed: SportMatch? = nil

    private var timer: Timer?
    private var currentTimerInterval: TimeInterval = 0
    private var cancellables = Set<AnyCancellable>()

    /// Whether the Sports tab is on screen. Drives the slow idle refresh — without it
    /// the default (no favourite team) view never updated after the first load.
    private var isTabVisible = false

    /// Per-league results.
    ///
    /// The old code appended into one shared array from eight concurrent `URLSession`
    /// completion handlers with no synchronization. `Array` is not thread-safe and
    /// concurrent appends can corrupt memory. Results are now written into a
    /// lock-guarded dictionary keyed by league, which also lets a poll refresh a
    /// single league without discarding the others.
    private var matchesByLeague: [String: [SportMatch]] = [:]
    private let cacheLock = NSLock()

    /// When the wide multi-league sweep last ran.
    private var lastFullSweep: Date = .distantPast
    private let fullSweepInterval: TimeInterval = 600

    private static let dateRangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    /// Leagues swept when looking for a favourite team that may play anywhere.
    private static let fallbackLeagues = [
        "eng.1", "uefa.champions", "fifa.world", "uefa.euro",
        "conmebol.america", "uefa.nations", "fifa.friendly"
    ]

    let leaguesList = [
        ("eng.1", "English Premier League"),
        ("uefa.champions", "UEFA Champions League"),
        ("esp.1", "La Liga"),
        ("ita.1", "Serie A"),
        ("ger.1", "Bundesliga"),
        ("usa.1", "MLS"),
        ("fra.1", "Ligue 1"),
        ("uefa.europa", "UEFA Europa League"),
        ("eng.fa", "FA Cup"),
        ("fifa.world", "FIFA World Cup"),
        ("uefa.euro", "UEFA European Championship"),
        ("conmebol.america", "Copa América"),
        ("uefa.nations", "UEFA Nations League"),
        ("fifa.friendly", "International Friendlies")
    ]

    init() {
        self.favoriteTeam = UserDefaults.standard.string(forKey: "FavoriteTeam") ?? ""
        self.selectedLeague = UserDefaults.standard.string(forKey: "SelectedLeague") ?? "eng.1"

        $favoriteTeam
            .dropFirst()
            .debounce(for: .milliseconds(800), scheduler: RunLoop.main)
            .sink { [weak self] team in
                UserDefaults.standard.set(team, forKey: "FavoriteTeam")
                self?.fetchScores()
            }
            .store(in: &cancellables)

        $selectedLeague
            .dropFirst()
            .sink { [weak self] league in
                UserDefaults.standard.set(league, forKey: "SelectedLeague")
                self?.fetchScores()
            }
            .store(in: &cancellables)

        fetchScores()
    }

    deinit {
        timer?.invalidate()
    }

    /// Called by the view when the Sports tab is shown or hidden.
    func setTabVisible(_ visible: Bool) {
        guard visible != isTabVisible else { return }
        isTabVisible = visible
        if visible { fetchScores() }
        scheduleNextPoll()
    }

    // MARK: - Polling cadence

    /// Decide whether to poll and how often.
    ///
    /// The old version fetched all eight leagues on every tick — 8 requests every 30s
    /// during a live match, each `limit=200` over a 120-day window. It also stopped
    /// polling entirely when no favourite team was set, so league mode went stale.
    private func scheduleNextPoll() {
        var interval: TimeInterval = 0

        if let match = favoriteTeamMatch {
            if match.isLive {
                interval = 30
            } else if match.isScheduled, let kickoff = match.timeUntilKickoff, kickoff <= 1800 {
                interval = 60
            } else if isTabVisible {
                interval = 180
            }
        } else if isTabVisible {
            // Nothing to track, but the user is looking at the tab.
            interval = 120
        }

        guard interval > 0 else {
            timer?.invalidate()
            timer = nil
            currentTimerInterval = 0
            return
        }

        // Already running at the right cadence.
        if timer != nil && currentTimerInterval == interval { return }

        timer?.invalidate()
        currentTimerInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.fetchScores()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func dateRangeString() -> String {
        let calendar = Calendar.current
        let now = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -30, to: now),
              let endDate = calendar.date(byAdding: .day, value: 90, to: now) else {
            return ""
        }
        let formatter = SportsManager.dateRangeFormatter
        return "\(formatter.string(from: startDate))-\(formatter.string(from: endDate))"
    }

    // MARK: - Fetching

    func fetchScores() {
        guard !isFetching else { return }
        isFetching = true

        let leagues = leaguesToFetch()
        if leagues.count > 1 { lastFullSweep = Date() }

        let datesParam = favoriteTeam.isEmpty ? nil : dateRangeString()
        let group = DispatchGroup()

        for league in leagues {
            group.enter()
            fetchLeagueMatches(league: league, dates: datesParam) { [weak self] matches in
                if let matches = matches, let self = self {
                    // Guarded: these callbacks run concurrently on URLSession's queue.
                    self.cacheLock.lock()
                    self.matchesByLeague[league] = matches
                    self.cacheLock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isFetching = false
            self.recomputeDerivedState()
            self.scheduleNextPoll()
        }
    }

    /// Which leagues this poll should refresh.
    ///
    /// While a favourite match is live we only need that one league; the wide sweep
    /// that hunts for the team's *next* fixture can run every ten minutes instead.
    private func leaguesToFetch() -> [String] {
        if let match = favoriteTeamMatch,
           match.isLive,
           Date().timeIntervalSince(lastFullSweep) < fullSweepInterval {
            return Array(Set([match.leagueId, selectedLeague]))
        }

        if favoriteTeam.isEmpty {
            // No team to hunt for — the selected league is all that's displayed.
            return [selectedLeague]
        }

        return Array(Set([selectedLeague] + SportsManager.fallbackLeagues))
    }

    private func allCachedMatches() -> [SportMatch] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return matchesByLeague.values.flatMap { $0 }
    }

    private func recomputeDerivedState() {
        let allMatches = allCachedMatches()

        self.leagueMatches = allMatches
            .filter { $0.leagueId == self.selectedLeague }
            .sorted { $0.sortDate < $1.sortDate }

        guard !favoriteTeam.isEmpty else {
            self.favoriteTeamMatch = nil
            self.searchLastGamePlayed = nil
            self.searchUpcomingMatches = []
            return
        }

        let lowerFav = favoriteTeam.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. All matches involving the favourite team
        let matching = allMatches.filter { match in
            match.homeTeam.lowercased().contains(lowerFav) ||
            match.awayTeam.lowercased().contains(lowerFav) ||
            match.homeAbbr.lowercased() == lowerFav ||
            match.awayAbbr.lowercased() == lowerFav
        }

        // 2. Separate by state
        let liveMatches = matching.filter { $0.isLive }
        let scheduledMatches = matching.filter { $0.isScheduled }
        let finishedMatches = matching.filter { $0.isFinished }

        let recentFinished = finishedMatches
            .filter { ($0.timeUntilKickoff ?? .leastNormalMagnitude) > -86400 }
            .sorted { $0.sortDate > $1.sortDate }

        // 3. Pick the best match to spotlight:
        //    live → finished in the last 24h → next scheduled → most recent finished
        if let live = liveMatches.first {
            self.favoriteTeamMatch = live
        } else if let recent = recentFinished.first {
            self.favoriteTeamMatch = recent
        } else if let nextUp = scheduledMatches.sorted(by: { $0.sortDate < $1.sortDate }).first {
            self.favoriteTeamMatch = nextUp
        } else {
            self.favoriteTeamMatch = finishedMatches.sorted { $0.sortDate > $1.sortDate }.first
        }

        // 4. Populate search properties for UI
        self.searchLastGamePlayed = finishedMatches.sorted { $0.sortDate > $1.sortDate }.first

        let searchLive = matching.filter { $0.isLive && $0.leagueId == self.selectedLeague }
        let searchUpcoming = matching
            .filter { $0.isScheduled && $0.leagueId == self.selectedLeague }
            .sorted { $0.sortDate < $1.sortDate }
        self.searchUpcomingMatches = searchLive + searchUpcoming
    }

    private func fetchLeagueMatches(league: String, dates: String? = nil, completion: @escaping ([SportMatch]?) -> Void) {
        var urlString = "https://site.api.espn.com/apis/site/v2/sports/soccer/\(league)/scoreboard?limit=200"
        if let dates = dates {
            urlString += "&dates=\(dates)"
        }
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil else {
                if let error = error {
                    Log.sports.debug("Fetch failed for \(league): \(error.localizedDescription)")
                }
                completion(nil)
                return
            }
            completion(SportsManager.parseScoreboard(data: data, league: league))
        }.resume()
    }

    private static func parseScoreboard(data: Data, league: String) -> [SportMatch] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = json["events"] as? [[String: Any]] else {
            return []
        }

        let leagueName = (json["leagues"] as? [[String: Any]])?.first?["name"] as? String ?? league
        var parsedMatches: [SportMatch] = []

        for event in events {
            let id = event["id"] as? String ?? UUID().uuidString
            let dateString = event["date"] as? String ?? ""
            let statusObj = event["status"] as? [String: Any]
            let statusTypeObj = statusObj?["type"] as? [String: Any]
            let statusState = statusTypeObj?["state"] as? String ?? "pre"
            var statusDetail = statusTypeObj?["detail"] as? String ?? ""

            let date = SportMatch.parseDate(from: dateString)

            if statusState == "pre", let date = date {
                statusDetail = SportMatch.formatMatchTime(date)
            }

            guard let competitions = event["competitions"] as? [[String: Any]],
                  let competitors = competitions.first?["competitors"] as? [[String: Any]] else {
                continue
            }

            var homeTeamName = ""
            var awayTeamName = ""
            var homeAbbrValue = ""
            var awayAbbrValue = ""
            var homeScoreValue = "0"
            var awayScoreValue = "0"
            var homeLogoUrl: String? = nil
            var awayLogoUrl: String? = nil

            for competitor in competitors {
                let homeAway = competitor["homeAway"] as? String ?? ""
                let team = competitor["team"] as? [String: Any]
                let teamName = team?["name"] as? String ?? ""
                let abbreviation = team?["abbreviation"] as? String ?? String(teamName.prefix(3)).uppercased()
                let score = competitor["score"] as? String ?? "0"
                let logo = team?["logo"] as? String

                if homeAway == "home" {
                    homeTeamName = teamName
                    homeAbbrValue = abbreviation
                    homeScoreValue = score
                    homeLogoUrl = logo
                } else {
                    awayTeamName = teamName
                    awayAbbrValue = abbreviation
                    awayScoreValue = score
                    awayLogoUrl = logo
                }
            }

            parsedMatches.append(SportMatch(
                id: id,
                leagueId: league,
                leagueName: leagueName,
                homeTeam: homeTeamName,
                awayTeam: awayTeamName,
                homeAbbr: homeAbbrValue,
                awayAbbr: awayAbbrValue,
                homeScore: homeScoreValue,
                awayScore: awayScoreValue,
                statusState: statusState,
                statusDetail: statusDetail,
                homeLogo: homeLogoUrl,
                awayLogo: awayLogoUrl,
                date: date
            ))
        }

        return parsedMatches
    }
}
