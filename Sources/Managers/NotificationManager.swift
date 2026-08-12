import SwiftUI
import Combine

struct NotchNotification: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let tintColor: Color
}

/// Transient banners shown inside the collapsed island.
final class NotificationManager: ObservableObject {
    @Published var activeNotification: NotchNotification? = nil

    private var collapseTimer: Timer?

    deinit {
        collapseTimer?.invalidate()
    }

    func showNotification(title: String, subtitle: String, systemImage: String, tintColor: Color = .pink) {
        DispatchQueue.main.async {
            self.activeNotification = NotchNotification(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                tintColor: tintColor
            )

            // Auto dismiss after 3 seconds
            self.collapseTimer?.invalidate()
            let timer = Timer(timeInterval: 3.0, repeats: false) { [weak self] _ in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    self?.activeNotification = nil
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.collapseTimer = timer
        }
    }

    func dismiss() {
        collapseTimer?.invalidate()
        collapseTimer = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            activeNotification = nil
        }
    }
}
