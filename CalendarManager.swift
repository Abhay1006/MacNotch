import Foundation
import EventKit

class CalendarManager: ObservableObject {
    @Published var nextEventTitle: String = "No upcoming events"
    @Published var nextEventTime: String = ""
    @Published var isAuthorized: Bool = false
    
    private let eventStore = EKEventStore()
    
    init() {
        checkPermission()
    }
    
    func checkPermission() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess {
            self.isAuthorized = true
            self.fetchNextEvent()
        } else if status == .notDetermined {
            eventStore.requestFullAccessToEvents { [weak self] granted, _ in
                if granted {
                    DispatchQueue.main.async {
                        self?.isAuthorized = true
                        self?.fetchNextEvent()
                    }
                }
            }
        }
    }
    
    func fetchNextEvent() {
        guard isAuthorized else { return }
        
        DispatchQueue.global(qos: .default).async { [weak self] in
            guard let self = self else { return }
            let calendars = self.eventStore.calendars(for: .event)
            let now = Date()
            let oneDayFromNow = now.addingTimeInterval(24 * 3600)
            let predicate = self.eventStore.predicateForEvents(withStart: now, end: oneDayFromNow, calendars: calendars)
            
            let events = self.eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }
            
            DispatchQueue.main.async {
                if let nextEvent = events.first {
                    self.nextEventTitle = nextEvent.title
                    
                    let formatter = DateFormatter()
                    formatter.dateStyle = .none
                    formatter.timeStyle = .short
                    self.nextEventTime = formatter.string(from: nextEvent.startDate)
                } else {
                    self.nextEventTitle = "No upcoming events"
                    self.nextEventTime = ""
                }
            }
        }
    }
}
