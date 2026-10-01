import Foundation
import Combine

/// Rest timer.
///
/// Nothing ticks. The manager publishes only the session's start and end dates; views
/// render the countdown with `Text(timerInterval:)`, which SwiftUI updates itself
/// without our code running. The previous version republished `timeRemaining` twice a
/// second, re-evaluating every view that observed the manager for the whole session.
///
/// Completion is a single wall-clock deadline, so a session that spans system sleep
/// still ends on time rather than after the sleep duration is added on.
final class ZenManager: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var duration: TimeInterval = 15 * 60
    @Published private(set) var startDate: Date?
    @Published private(set) var endDate: Date?

    static let finishedNotification = Notification.Name("ZenTimerFinished")

    private var deadline: DispatchSourceTimer?

    private let minDuration: TimeInterval = 60
    private let maxDuration: TimeInterval = 120 * 60

    deinit {
        deadline?.cancel()
    }

    /// The running countdown, for `Text(timerInterval:countsDown:)`.
    var countdownInterval: ClosedRange<Date>? {
        guard let start = startDate, let end = endDate else { return nil }
        return start...end
    }

    /// Seconds left, computed on demand — not published.
    var timeRemaining: TimeInterval {
        guard let end = endDate else { return duration }
        return max(0, end.timeIntervalSinceNow)
    }

    func startTimer() {
        let now = Date()
        startDate = now
        endDate = now.addingTimeInterval(duration)
        isActive = true

        deadline?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(wallDeadline: .now() + duration, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            self?.stopTimer(finished: true)
        }
        timer.resume()
        deadline = timer
    }

    func stopTimer(finished: Bool = false) {
        deadline?.cancel()
        deadline = nil
        startDate = nil
        endDate = nil
        isActive = false

        if finished {
            NotificationCenter.default.post(name: ZenManager.finishedNotification, object: nil)
        }
    }

    func adjustDuration(by seconds: TimeInterval) {
        let newDuration = duration + seconds
        guard newDuration >= minDuration && newDuration <= maxDuration else { return }
        duration = newDuration
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
