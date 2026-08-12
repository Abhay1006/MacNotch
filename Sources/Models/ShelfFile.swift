import Foundation

struct ShelfFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
}

struct FavApp: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let path: String

    init(id: UUID = UUID(), name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }
}
