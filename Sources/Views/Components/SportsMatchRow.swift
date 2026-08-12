import SwiftUI

struct SportsMatchRow: View {
    let match: SportMatch

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            HStack {
                Text(match.homeTeam)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        if match.isScheduled {
            return "\(match.homeTeam) versus \(match.awayTeam), \(match.statusDetail), \(match.leagueName)"
        }
        let state = match.isLive ? "Live" : "Final"
        return "\(state): \(match.homeTeam) \(match.homeScore), \(match.awayTeam) \(match.awayScore), \(match.leagueName)"
    }
}
