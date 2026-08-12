import Foundation
import Combine

class ObsidianTaskManager: ObservableObject {
    @Published var allTasks: [ObsidianTask] = []
    @Published var todayTasks: [ObsidianTask] = []
    @Published var pendingTodayCount: Int = 0
    @Published var totalPendingCount: Int = 0
    @Published var lastScanDate: Date? = nil

    private var watcher: DirectoryWatcher?
    private var fallbackTimer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private let scanQueue = DispatchQueue(label: "com.abhay.MacNotch.obsidian", qos: .utility)
    private var isScanning = false

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// `YYYY-MM-DD.md` note names.
    private static let datedNotePattern = try? NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}$"#)

    private var vaultPath: String { Preferences.shared.obsidianVaultPath }
    private var dailyTasksPath: String { Preferences.shared.dailyTasksPath }

    init() {
        scanTasks()
        startWatching()

        // A slow safety net in case FSEvents misses something (network volumes, iCloud
        // Drive placeholders). Five minutes instead of the old five seconds.
        fallbackTimer = Timer.publish(every: 300.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.scanTasks() }

        // Re-point the watcher if the user changes the vault location.
        Preferences.shared.$obsidianVaultPath
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.startWatching()
                self?.scanTasks()
            }
            .store(in: &cancellables)
    }

    deinit {
        fallbackTimer?.cancel()
    }

    private func startWatching() {
        watcher = DirectoryWatcher(paths: [dailyTasksPath, vaultPath]) { [weak self] in
            self?.scanTasks()
        }
    }

    func scanTasks() {
        scanQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.isScanning else { return }
            self.isScanning = true
            defer { self.isScanning = false }

            var parsedTasks: [ObsidianTask] = []
            let fm = FileManager.default

            // Directories to search
            let dirsToScan = [self.dailyTasksPath, self.vaultPath]
            var scannedFiles = Set<String>()
            let todayString = ObsidianTaskManager.dayFormatter.string(from: Date())

            for dir in dirsToScan {
                guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }

                for file in files {
                    guard file.hasSuffix(".md") else { continue }
                    let filename = (file as NSString).deletingPathExtension
                    guard ObsidianTaskManager.isDatedNote(filename) else { continue }

                    let fullPath = "\(dir)/\(file)"
                    if scannedFiles.contains(fullPath) { continue }
                    scannedFiles.insert(fullPath)

                    guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { continue }

                    let lines = content.components(separatedBy: .newlines)
                    for (idx, line) in lines.enumerated() {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)

                        var isCompleted = false
                        var taskTitle = ""

                        if trimmed.hasPrefix("- [ ]") {
                            isCompleted = false
                            taskTitle = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        } else if trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]") {
                            isCompleted = true
                            taskTitle = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        } else {
                            continue
                        }

                        if taskTitle.isEmpty { continue }

                        // Clean markdown links e.g. [title](url) -> title, [[title]] -> title
                        let cleanedTitle = self.cleanMarkdownLinks(taskTitle)

                        // Stable across launches. `String.hashValue` is randomly seeded per
                        // process, so IDs built from it changed on every run.
                        let taskId = "\(filename)-\(idx)-\(cleanedTitle.stableHash)"
                        let task = ObsidianTask(
                            id: taskId,
                            dateString: filename,
                            title: cleanedTitle,
                            isCompleted: isCompleted,
                            sourceFile: fullPath
                        )
                        parsedTasks.append(task)
                    }
                }
            }

            // Sort tasks by date descending
            parsedTasks.sort { $0.dateString > $1.dateString }

            let todayList = parsedTasks.filter { $0.dateString == todayString }
            let pendingToday = todayList.filter { !$0.isCompleted }.count
            let totalPending = parsedTasks.filter { !$0.isCompleted }.count

            DispatchQueue.main.async {
                self.allTasks = parsedTasks
                self.todayTasks = todayList
                self.pendingTodayCount = pendingToday
                self.totalPendingCount = totalPending
                self.lastScanDate = Date()
            }
        }
    }

    private static func isDatedNote(_ filename: String) -> Bool {
        guard let pattern = datedNotePattern else { return false }
        let range = NSRange(filename.startIndex..., in: filename)
        return pattern.firstMatch(in: filename, range: range) != nil
    }

    private func cleanMarkdownLinks(_ text: String) -> String {
        var result = text

        // Remove [[link]]
        result = result.replacingOccurrences(of: #"\[\[(.*?)\]\]"#, with: "$1", options: .regularExpression)

        // Remove [title](url)
        result = result.replacingOccurrences(of: #"\[(.*?)\]\(.*?\)"#, with: "$1", options: .regularExpression)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension String {
    /// FNV-1a. Unlike `hashValue`, this is stable across processes, so IDs derived from
    /// it survive a relaunch.
    var stableHash: String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in self.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 36)
    }
}
