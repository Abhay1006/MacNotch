import Foundation
import Combine

struct ObsidianTask: Identifiable, Equatable {
    let id: String
    let dateString: String // YYYY-MM-DD
    let title: String
    var isCompleted: Bool
    let sourceFile: String
}

class ObsidianTaskManager: ObservableObject {
    @Published var allTasks: [ObsidianTask] = []
    @Published var todayTasks: [ObsidianTask] = []
    @Published var pendingTodayCount: Int = 0
    @Published var totalPendingCount: Int = 0
    @Published var lastScanDate: Date? = nil
    
    private let vaultPath: String
    private let dailyTasksPath: String
    
    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.vaultPath = "\(home)/Documents/Obsidian Vault"
        self.dailyTasksPath = "\(home)/Documents/Obsidian Vault/Daily Tasks"
        
        scanTasks()
    }
    
    func scanTasks() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var parsedTasks: [ObsidianTask] = []
            let fm = FileManager.default
            
            // Directories to search
            let dirsToScan = [self.dailyTasksPath, self.vaultPath]
            var scannedFiles = Set<String>()
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let todayString = dateFormatter.string(from: Date())
            
            for dir in dirsToScan {
                guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
                
                for file in files {
                    guard file.hasSuffix(".md") else { continue }
                    let filename = (file as NSString).deletingPathExtension
                    
                    // Match YYYY-MM-DD
                    guard filename.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { continue }
                    
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
                        
                        let taskId = "\(filename)-\(idx)-\(cleanedTitle.hashValue)"
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
    
    private func cleanMarkdownLinks(_ text: String) -> String {
        var result = text
        
        // Remove [[link]]
        result = result.replacingOccurrences(of: #"\[\[(.*?)\]\]"#, with: "$1", options: .regularExpression)
        
        // Remove [title](url)
        result = result.replacingOccurrences(of: #"\[(.*?)\]\(.*?\)"#, with: "$1", options: .regularExpression)
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
