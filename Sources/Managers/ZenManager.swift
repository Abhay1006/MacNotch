import Foundation
import Combine

/// Rest timer.
///
/// The countdown is derived from a target `Date` rather than decremented once per tick.
/// The old `timeRemaining -= 1` approach ran on a default-mode `Timer`, so it stalled
/// whenever a menu was tracking and drifted under timer coalescing — a 15-minute rest
/// could take noticeably longer than 15 minutes.
final class ZenManager: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var timeRemaining: TimeInterval = 15 * 60
    @Published private(set) var duration: TimeInterval = 15 * 60

    static let finishedNotification = Notification.Name("ZenTimerFinished")

    private var endDate: Date?
    private var timer: Timer?

    private let minDuration: TimeInterval = 60
    private let maxDuration: TimeInterval = 120 * 60

    deinit {
        timer?.invalidate()
    }

    func startTimer() {
        isActive = true
        endDate = Date().addingTimeInterval(duration)
        timeRemaining = duration

        timer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // `.common` so the countdown keeps running while menus or scroll views track.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopTimer(finished: Bool = false) {
        timer?.invalidate()
        timer = nil
        endDate = nil
        isActive = false
        timeRemaining = duration

        if finished {
            NotificationCenter.default.post(name: ZenManager.finishedNotification, object: nil)
        }
    }

    func adjustDuration(by seconds: TimeInterval) {
        let newDuration = duration + seconds
        guard newDuration >= minDuration && newDuration <= maxDuration else { return }
        duration = newDuration
        if !isActive {
            timeRemaining = newDuration
        }
    }

    private func tick() {
        guard let endDate = endDate else { return }
        let remaining = endDate.timeIntervalSinceNow
        if remaining <= 0 {
            timeRemaining = 0
            stopTimer(finished: true)
        } else {
            timeRemaining = remaining
        }
    }

    var timeFormatted: String {
        // Round up so a fresh 15:00 timer reads "15:00", not "14:59".
        let total = Int(timeRemaining.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var durationFormatted: String {
        "\(Int(duration) / 60) Min"
    }
}
