import Cocoa
import Combine

class ClipboardManager: ObservableObject {
    @Published var items: [ClipboardItem] = []
    private var timer: AnyCancellable?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let maxItems = 15

    struct ClipboardItem: Identifiable, Equatable {
        let id = UUID()
        let content: String
        let timestamp: Date
        
        var preview: String {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 100 {
                return String(trimmed.prefix(97)) + "..."
            }
            return trimmed
        }
    }

    init() {
        startMonitoring()
        // Load initial clipboard item if any
        checkClipboard()
    }

    func startMonitoring() {
        timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkClipboard()
            }
    }

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if let newString = pasteboard.string(forType: .string) {
            let trimmed = newString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            
            // Avoid duplicates at the top of the history
            if items.first?.content == trimmed {
                return
            }
            
            // Remove previous occurrence if it exists to bring it to the top
            items.removeAll { $0.content == trimmed }
            
            let newItem = ClipboardItem(content: trimmed, timestamp: Date())
            items.insert(newItem, at: 0)
            
            // Limit items
            if items.count > maxItems {
                items.removeLast()
            }
        }
    }

    func copyToClipboard(item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.content, forType: .string)
        // Update change count so we don't trigger our own duplicate detection
        lastChangeCount = pasteboard.changeCount
        
        // Move copied item to the top of the list
        items.removeAll { $0.id == item.id }
        items.insert(ClipboardItem(content: item.content, timestamp: Date()), at: 0)
    }

    func deleteItem(at indexSet: IndexSet) {
        items.remove(atOffsets: indexSet)
    }

    func clearHistory() {
        items.removeAll()
    }
}
