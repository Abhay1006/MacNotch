import SwiftUI

struct SportsTab: View {
    @ObservedObject var sports: SportsManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            settingsHeader

            if let favMatch = sports.favoriteTeamMatch {
                spotlight(favMatch)
            }

            matchList
        }
    }

    // MARK: - Header

    private var settingsHeader: some View {
        HStack(spacing: 12) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundColor(.pink)
                    .font(.system(size: 10))

                TextField("Fav Team (e.g. Arsenal)", text: $sports.favoriteTeam)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white)
                    .accessibilityLabel("Favorite team")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08))
            .cornerRadius(6)

            Menu {
                ForEach(sports.leaguesList, id: \.0) { league in
                    Button(action: {
                        withAnimation(reduceMotion ? nil : .default) {
                            sports.selectedLeague = league.0
                        }
                    }) {
                        Text(league.1)
                    }
                }
            } label: {
                HStack {
                    Text(selectedLeagueName)
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
            .accessibilityLabel("League: \(selectedLeagueName)")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var selectedLeagueName: String {
        sports.leaguesList.first { $0.0 == sports.selectedLeague }?.1 ?? "Select League"
    }

    // MARK: - Spotlight

    private func spotlight(_ match: SportMatch) -> some View {
        VStack(spacing: 4) {
            HStack {
                Circle()
                    .fill(match.isLive ? Color.green : (match.isFinished ? Color.white.opacity(0.4) : Color.pink))
                    .frame(width: 6, height: 6)

                Text(match.leagueName)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                Text(match.statusDetail)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(match.isLive ? .green : .white.opacity(0.8))
            }
            .padding(.horizontal, 8)

            HStack {
                HStack {
                    Spacer()
                    Text(match.homeTeam)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    TeamLogo(url: match.homeLogo)
                }
                .frame(maxWidth: .infinity)

                Text("\(match.homeScore) - \(match.awayScore)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.pink)
                    .padding(.horizontal, 8)

                HStack {
                    TeamLogo(url: match.awayLogo)
                    Text(match.awayTeam)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(match.homeTeam) \(match.homeScore), \(match.awayTeam) \(match.awayScore). \(match.statusDetail)")
    }

    // MARK: - List

    private var matchList: some View {
        ScrollView {
            VStack(spacing: 8) {
                if sports.favoriteTeam.isEmpty {
                    leagueMode
                } else {
                    searchMode
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(maxHeight: 140)
    }

    @ViewBuilder
    private var leagueMode: some View {
        if sports.isFetching && sports.leagueMatches.isEmpty {
            loadingSpinner
        } else if sports.leagueMatches.isEmpty {
            emptyMessage("No matches today")
        } else {
            ForEach(sports.leagueMatches) { match in
                SportsMatchRow(match: match)
            }
        }
    }

    @ViewBuilder
    private var searchMode: some View {
        let hasResults = !sports.searchUpcomingMatches.isEmpty || sports.searchLastGamePlayed != nil

        if sports.isFetching && !hasResults {
            loadingSpinner
        } else if !hasResults {
            emptyMessage("No matches found for '\(sports.favoriteTeam)'")
        } else {
            if let lastGame = sports.searchLastGamePlayed {
                VStack(alignment: .leading, spacing: 4) {
                    sectionHeader("LAST GAME PLAYED")
                    SportsMatchRow(match: lastGame)
                }
            }

            if !sports.searchUpcomingMatches.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    sectionHeader("UPCOMING IN \(selectedLeagueName.uppercased())")
                        .padding(.top, 4)

                    ForEach(sports.searchUpcomingMatches) { match in
                        SportsMatchRow(match: match)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundColor(.white.opacity(0.45))
            .padding(.leading, 2)
    }

    private var loadingSpinner: some View {
        ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .pink))
            .scaleEffect(0.8)
            .padding(.top, 20)
    }

    private func emptyMessage(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .rounded))
            .foregroundColor(.white.opacity(0.45))
            .padding(.top, 24)
    }
}
