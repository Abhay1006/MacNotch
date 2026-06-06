import Foundation
import Combine

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
    let dateString: String
    
    var isLive: Bool {
        return statusState == "in"
    }
    
    var isFinished: Bool {
        return statusState == "post"
    }
    
    var isScheduled: Bool {
        return statusState == "pre"
    }
    
    var timeUntilKickoff: TimeInterval? {
        guard !dateString.isEmpty else { return nil }
        let isoFormatter = ISO8601DateFormatter()
        var dateObj = isoFormatter.date(from: dateString)
        
        if dateObj == nil {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            df.timeZone = TimeZone(secondsFromGMT: 0)
            dateObj = df.date(from: dateString)
        }
        
        if dateObj == nil {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd'T'HH:mmZ"
            dateObj = df.date(from: dateString)
        }
        
        guard let date = dateObj else { return nil }
        return date.timeIntervalSinceNow
    }
}

class SportsManager: ObservableObject {
    @Published var favoriteTeam: String
    @Published var selectedLeague: String
    
    @Published var leagueMatches: [SportMatch] = []
    @Published var favoriteTeamMatch: SportMatch? = nil
    @Published var isFetching = false
    
    private var timer: Timer?
    private var currentTimerInterval: TimeInterval = 60.0
    private var cancellables = Set<AnyCancellable>()
    
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
        startTimer()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    func startTimer() {
        timer?.invalidate()
        let interval = (favoriteTeamMatch?.isLive ?? false) ? 30.0 : 60.0
        currentTimerInterval = interval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.fetchScores()
        }
    }
    
    func fetchScores() {
        guard !isFetching else { return }
        isFetching = true
        
        // Fetch the user's selected league, plus club and national fallback leagues
        let leaguesToFetch = Array(Set([
            selectedLeague,
            "eng.1",
            "uefa.champions",
            "fifa.world",
            "uefa.euro",
            "conmebol.america",
            "uefa.nations",
            "fifa.friendly"
        ]))
        
        var allMatches: [SportMatch] = []
        let group = DispatchGroup()
        
        for league in leaguesToFetch {
            group.enter()
            fetchLeagueMatches(league: league) { matches in
                if let matches = matches {
                    allMatches.append(contentsOf: matches)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isFetching = false
            
            // Filter matches for the selected league
            self.leagueMatches = allMatches.filter { $0.leagueId == self.selectedLeague }
            
            // Find favorite team match if favorite team is set
            if !self.favoriteTeam.isEmpty {
                let lowerFav = self.favoriteTeam.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                
                // 1. Get all matches involving favorite team
                let matching = allMatches.filter { match in
                    match.homeTeam.lowercased().contains(lowerFav) || 
                    match.awayTeam.lowercased().contains(lowerFav) ||
                    match.homeAbbr.lowercased() == lowerFav ||
                    match.awayAbbr.lowercased() == lowerFav
                }
                
                // 2. Separate them by state
                let liveMatches = matching.filter { $0.isLive }
                let scheduledMatches = matching.filter { $0.isScheduled }
                let finishedMatches = matching.filter { $0.isFinished }
                
                // 3. Deterministically choose the best match:
                // - First preference: Live match
                // - Second preference: Scheduled match closest to today (earliest dateString)
                // - Third preference: Finished match that was most recent (latest dateString)
                if let live = liveMatches.first {
                    self.favoriteTeamMatch = live
                } else if !scheduledMatches.isEmpty {
                    let sortedScheduled = scheduledMatches.sorted { $0.dateString < $1.dateString }
                    self.favoriteTeamMatch = sortedScheduled.first
                } else if !finishedMatches.isEmpty {
                    let sortedFinished = finishedMatches.sorted { $0.dateString > $1.dateString }
                    self.favoriteTeamMatch = sortedFinished.first
                } else {
                    self.favoriteTeamMatch = nil
                }
            } else {
                self.favoriteTeamMatch = nil
            }
            
            // Dynamically adjust polling speed based on whether the match is live
            let isNowLive = self.favoriteTeamMatch?.isLive ?? false
            let expectedInterval = isNowLive ? 30.0 : 60.0
            if self.currentTimerInterval != expectedInterval {
                self.startTimer()
            }
        }
    }
    
    private func fetchLeagueMatches(league: String, completion: @escaping ([SportMatch]?) -> Void) {
        let urlString = "https://site.api.espn.com/apis/site/v2/sports/soccer/\(league)/scoreboard"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }
            
            var parsedMatches: [SportMatch] = []
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let events = json["events"] as? [[String: Any]] {
                
                let leagueName = (json["leagues"] as? [[String: Any]])?.first?["name"] as? String ?? league
                
                for event in events {
                    let id = event["id"] as? String ?? UUID().uuidString
                    let dateString = event["date"] as? String ?? ""
                    let statusObj = event["status"] as? [String: Any]
                    let statusTypeObj = statusObj?["type"] as? [String: Any]
                    let statusState = statusTypeObj?["state"] as? String ?? "pre"
                    var statusDetail = statusTypeObj?["detail"] as? String ?? ""
                    
                    if statusState == "pre" && !dateString.isEmpty {
                        if let formattedTime = SportsManager.formatMatchTime(from: dateString) {
                            statusDetail = formattedTime
                        }
                    }
                    
                    if let competitions = event["competitions"] as? [[String: Any]],
                       let competitors = competitions.first?["competitors"] as? [[String: Any]] {
                        
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
                        
                        let match = SportMatch(
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
                            dateString: dateString
                        )
                        parsedMatches.append(match)
                    }
                }
            }
            completion(parsedMatches)
        }.resume()
    }
    
    static func formatMatchTime(from dateString: String) -> String? {
        guard !dateString.isEmpty else { return nil }
        
        let isoFormatter = ISO8601DateFormatter()
        var dateObj = isoFormatter.date(from: dateString)
        
        if dateObj == nil {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            df.timeZone = TimeZone(secondsFromGMT: 0)
            dateObj = df.date(from: dateString)
        }
        
        if dateObj == nil {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd'T'HH:mmZ"
            dateObj = df.date(from: dateString)
        }
        
        guard let date = dateObj else { return nil }
        
        let outputFormatter = DateFormatter()
        outputFormatter.timeZone = TimeZone.current // Automatically adapts to user's system timezone (IST)
        
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            outputFormatter.dateFormat = "HH:mm"
            return "Today \(outputFormatter.string(from: date))"
        } else if calendar.isDateInTomorrow(date) {
            outputFormatter.dateFormat = "HH:mm"
            return "Tomorrow \(outputFormatter.string(from: date))"
        } else {
            outputFormatter.dateFormat = "d MMM, HH:mm"
            return outputFormatter.string(from: date)
        }
    }
}
