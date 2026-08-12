import SwiftUI

struct ZenTab: View {
    @ObservedObject var zen: ZenManager
    @ObservedObject var appState: AppState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            Text("Zen Mode")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            if zen.isActive {
                runningState
            } else {
                idleState
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(height: 105)
    }

    private var runningState: some View {
        VStack(spacing: 3) {
            Text(zen.timeFormatted)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.green)
                .monospacedDigit()
                .accessibilityLabel("\(zen.timeFormatted) remaining")

            Text("Take a deep breath and rest.")
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(.white.opacity(0.6))

            Button(action: {
                withAnimation(reduceMotion ? nil : .default) {
                    zen.stopTimer()
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
    }

    private var idleState: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Button(action: { zen.adjustDuration(by: -5 * 60) }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Decrease rest duration by five minutes")

                Text(zen.durationFormatted)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 70)

                Button(action: { zen.adjustDuration(by: 5 * 60) }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Increase rest duration by five minutes")
            }

            Button(action: {
                withAnimation(reduceMotion ? nil : .default) {
                    zen.startTimer()
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
