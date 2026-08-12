import SwiftUI

struct QuotesTab: View {
    @ObservedObject var quotes: QuotesManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
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
                    withAnimation(reduceMotion ? nil : .default) {
                        quotes.selectNewQuote()
                    }
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Get another quote")
                .accessibilityLabel("Show another quote")
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.pink.opacity(0.6))
                        .padding(.top, 2)
                        .accessibilityHidden(true)

                    Text(quotes.currentQuote)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

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
}
