import Foundation

/// Watches directories for changes using FSEvents.
///
/// Replaces polling the Obsidian vault from disk every 5 seconds — a full directory
/// listing plus a read of every dated note, forever, whether or not anything changed.
/// FSEvents wakes us only when something actually moves.
final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.abhay.MacNotch.fsevents", qos: .utility)
    private let onChange: () -> Void

    /// Coalescing window. Obsidian writes several files in quick succession when it
    /// syncs; there is no point rescanning once per file.
    private let latency: CFTimeInterval = 1.0

    init(paths: [String], onChange: @escaping () -> Void) {
        self.onChange = onChange
        start(paths: paths)
    }

    deinit {
        stop()
    }

    private func start(paths: [String]) {
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info = info else { return }
            Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue().fire()
        }

        // `FileEvents` reports individual file writes, not just directory-level changes,
        // so edits to an existing note are picked up too.
        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            existing as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            Log.obsidian.error("Failed to create FSEvent stream for \(existing.joined(separator: ", "))")
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    fileprivate func fire() {
        onChange()
    }
}
