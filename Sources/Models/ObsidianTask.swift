import Foundation

struct ObsidianTask: Identifiable, Equatable {
    let id: String
    let dateString: String // YYYY-MM-DD
    let title: String
    var isCompleted: Bool
    let sourceFile: String
}
