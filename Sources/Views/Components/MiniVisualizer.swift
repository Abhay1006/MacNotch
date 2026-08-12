import SwiftUI

/// Five bars that jitter while music plays.
struct MiniVisualizer: View {
    let isPlaying: Bool
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var barHeights: [CGFloat] = [6, 4, 8, 5, 7]

    private let timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 2, height: isPlaying ? barHeights[index] : 2)
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
        .onReceive(timer) { _ in
            // A purely decorative animation — skip it entirely under Reduce Motion,
            // which also stops the 6.6 Hz state churn.
            guard isPlaying, !reduceMotion else { return }
            withAnimation(.linear(duration: 0.15)) {
                barHeights = (0..<5).map { _ in CGFloat.random(in: 3...12) }
            }
        }
    }
}
