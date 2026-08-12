import Foundation
import Combine

final class FileShelfManager: ObservableObject {
    @Published var files: [ShelfFile] = []

    func addFile(url: URL) {
        if !files.contains(where: { $0.url == url }) {
            files.append(ShelfFile(url: url))
        }
    }

    func removeFile(at index: Int) {
        guard files.indices.contains(index) else { return }
        files.remove(at: index)
    }

    func remove(_ file: ShelfFile) {
        files.removeAll { $0.id == file.id }
    }

    func clear() {
        files.removeAll()
    }
}
