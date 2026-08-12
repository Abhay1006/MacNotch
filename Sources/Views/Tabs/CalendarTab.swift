import SwiftUI
import Cocoa

struct CalendarTab: View {
    @ObservedObject var calendar: CalendarManager
    @ObservedObject var obsidian: ObsidianTaskManager

    var body: some View {
        HStack(spacing: 14) {
            appleCalendarCard
            Divider()
                .background(Color.white.opacity(0.08))
                .frame(height: 60)
            obsidianCard
        }
        .padding(.horizontal, 16)
    }

    private var appleCalendarCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.pink)
                Text("Apple Calendar")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(calendar.nextEventTitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 28, alignment: .topLeading)

                if !calendar.nextEventTime.isEmpty {
                    Text(calendar.nextEventTime)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { openCalendarApp() }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Next event: \(calendar.nextEventTitle) \(calendar.nextEventTime)")
            .accessibilityHint("Opens Calendar")
        }
    }

    private var obsidianCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.purple)
                Text("Obsidian Tasks")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text("\(obsidian.pendingTodayCount) due")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.purple)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.2))
                    .cornerRadius(4)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let topTask = topPendingTask {
                    Text("• \(topTask.title)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                } else {
                    Text("All daily tasks completed!")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(.green.opacity(0.8))
                }

                HStack {
                    Spacer()
                    Button(action: syncToCalendar) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 9, weight: .bold))
                            Text(calendar.syncStatusMessage.isEmpty ? "Sync" : calendar.syncStatusMessage)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(5)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("Sync Obsidian tasks to Apple Calendar")
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.purple.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private var topPendingTask: ObsidianTask? {
        obsidian.todayTasks.first { !$0.isCompleted }
            ?? obsidian.allTasks.first { !$0.isCompleted }
    }

    private func syncToCalendar() {
        let pending = obsidian.allTasks.filter { !$0.isCompleted }
        calendar.syncObsidianTasksToAppleCalendar(tasks: pending)
    }

    private func openCalendarApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
