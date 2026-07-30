import Foundation
import EventKit

class CalendarManager: ObservableObject {
    @Published var nextEventTitle: String = "No upcoming events"
    @Published var nextEventTime: String = ""
    @Published var isAuthorized: Bool = false
    @Published var syncStatusMessage: String = ""
    
    private let eventStore = EKEventStore()
    
    init() {
        checkPermission()
    }
    
    func checkPermission() {
        let status = EKEventStore.authorizationStatus(for: .event)
        var hasAccess = false
        if #available(macOS 14.0, *) {
            hasAccess = (status == .fullAccess)
        } else {
            hasAccess = (status.rawValue == 3) // authorized
        }
        
        if hasAccess {
            self.isAuthorized = true
            self.fetchNextEvent()
        } else if status == .notDetermined {
            if #available(macOS 14.0, *) {
                eventStore.requestFullAccessToEvents { [weak self] granted, _ in
                    if granted {
                        DispatchQueue.main.async {
                            self?.isAuthorized = true
                            self?.fetchNextEvent()
                        }
                    }
                }
            } else {
                eventStore.requestAccess(to: .event) { [weak self] granted, _ in
                    if granted {
                        DispatchQueue.main.async {
                            self?.isAuthorized = true
                            self?.fetchNextEvent()
                        }
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
    
    func syncObsidianTasksToAppleCalendar(tasks: [ObsidianTask], completion: ((Int) -> Void)? = nil) {
        guard isAuthorized, let targetCalendar = eventStore.defaultCalendarForNewEvents else {
            DispatchQueue.main.async {
                self.syncStatusMessage = "Calendar access not granted"
                completion?(0)
            }
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            
            var syncedCount = 0
            
            for task in tasks {
                guard let taskDate = dateFormatter.date(from: task.dateString) else { continue }
                
                let startOfDay = Calendar.current.startOfDay(for: taskDate)
                guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else { continue }
                
                let predicate = self.eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: [targetCalendar])
                let existingEvents = self.eventStore.events(matching: predicate)
                
                let expectedTitle = "[Obsidian] \(task.title)"
                let alreadyExists = existingEvents.contains { $0.title == expectedTitle || $0.title == task.title }
                
                if !alreadyExists {
                    let event = EKEvent(eventStore: self.eventStore)
                    event.title = expectedTitle
                    event.startDate = startOfDay
                    event.endDate = endOfDay
                    event.isAllDay = true
                    event.calendar = targetCalendar
                    event.notes = "Synced from Obsidian daily tasks (\(task.dateString))"
                    
                    do {
                        try self.eventStore.save(event, span: .thisEvent)
                        syncedCount += 1
                    } catch {
                        print("Failed to save task to Apple Calendar: \(error)")
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.syncStatusMessage = syncedCount > 0 ? "Synced \(syncedCount) tasks to Apple Calendar!" : "All tasks already in Apple Calendar"
                self.fetchNextEvent()
                completion?(syncedCount)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    self.syncStatusMessage = ""
                }
            }
        }
    }
}
