import Foundation
import Combine
import Cocoa

class MusicManager: ObservableObject {
    @Published var activePlayer: PlayerType = .none
    @Published var isPlaying: Bool = false
    @Published var trackTitle: String = ""
    @Published var artist: String = ""
    @Published var trackDuration: Double = 0
    @Published var artworkImage: NSImage? = nil

    /// Playback position as of `positionAnchorDate`.
    ///
    /// The position used to be advanced by a 1 Hz timer writing a `@Published` value,
    /// which re-rendered every observing view once a second for as long as music
    /// played — including the collapsed capsule, which never shows progress. Now the
    /// position is extrapolated on demand, and only the Music tab's progress bar asks.
    private var positionAnchor: Double = 0
    private var positionAnchorDate = Date()

    private var lastTrackIdentifier: String = ""
    private var playerInfoObserver: NSObjectProtocol?

    /// Artwork is expensive to fetch (an AppleScript export or a network round trip),
    /// and users cycle back and forth between tracks constantly. Cache it.
    private let artworkCache = NSCache<NSString, NSImage>()

    /// Unique per launch, inside the per-user temporary directory.
    ///
    /// The old code wrote to a fixed `/tmp/macnotch_artwork.jpg`: a world-writable path
    /// any local process could swap out from under us, and one that collided between
    /// users on a shared machine.
    private let artworkScratchURL: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("macnotch-artwork-\(UUID().uuidString).jpg")

    /// ASCII unit separator. Cannot occur in a track title, unlike the `|` the old
    /// parser used — a title containing a pipe still satisfied the field-count guard
    /// but shifted every subsequent field, including the numeric ones.
    private static let fieldSeparator = "\u{1F}"

    enum PlayerType: String {
        case music = "Music"
        case none = "None"
    }

    init() {
        artworkCache.countLimit = 40
        startMonitoring()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.pollMusicStateBackground()
        }
    }

    deinit {
        if let observer = playerInfoObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        try? FileManager.default.removeItem(at: artworkScratchURL)
    }

    func startMonitoring() {
        playerInfoObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // When track changes, plays, or pauses, we do ONE apple script call to resync state
            DispatchQueue.global(qos: .userInitiated).async {
                self?.pollMusicStateBackground()
            }
        }
    }

    /// Playback position at `date`, extrapolated from the last sync while playing.
    func position(at date: Date) -> Double {
        guard isPlaying else { return positionAnchor }
        let elapsed = max(0, date.timeIntervalSince(positionAnchorDate))
        return min(trackDuration, positionAnchor + elapsed)
    }

    private func setPosition(_ position: Double) {
        positionAnchor = position
        positionAnchorDate = Date()
    }

    private func updateArtwork() {
        let currentTitle = self.trackTitle
        let currentArtist = self.artist
        let cacheKey = "\(currentArtist)\(MusicManager.fieldSeparator)\(currentTitle)" as NSString

        if activePlayer == .none || currentTitle == "Not Playing" || currentTitle.isEmpty {
            self.artworkImage = nil
            return
        }

        if let cached = artworkCache.object(forKey: cacheKey) {
            self.artworkImage = cached
            return
        }

        // Export artwork to a scratch file in the background to avoid blocking the main thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            autoreleasepool {
                guard let self = self else { return }
                let script = """
                tell application "Music"
                    if player state is not stopped then
                        try
                            set currentTrack to current track
                            if exists artwork 1 of currentTrack then
                                set rawData to (get raw data of artwork 1 of currentTrack)
                                set tempPath to POSIX file "\(self.artworkScratchURL.path)"
                                set fileRef to (open for access tempPath with write permission)
                                set eof fileRef to 0
                                write rawData to fileRef
                                close access fileRef
                                return "SUCCESS"
                            end if
                        end try
                    end if
                    return "FAIL"
                end tell
                """

                let result = self.runAppleScript(script)
                if result == "SUCCESS", let image = NSImage(contentsOf: self.artworkScratchURL) {
                    // Force load raw image data into memory before returning
                    _ = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    // Don't leave the export lying around on disk.
                    try? FileManager.default.removeItem(at: self.artworkScratchURL)
                    self.applyArtwork(image, key: cacheKey, title: currentTitle, artist: currentArtist)
                    return
                }
                try? FileManager.default.removeItem(at: self.artworkScratchURL)

                // Fallback to iTunes Search API for streamed/URL tracks. This leaves the
                // machine, so it is opt-out via preferences and disclosed in the README.
                guard Preferences.shared.artworkLookupEnabled else {
                    self.applyArtwork(nil, key: cacheKey, title: currentTitle, artist: currentArtist)
                    return
                }

                self.fetchArtworkFromiTunes(title: currentTitle, artist: currentArtist) { [weak self] image in
                    self?.applyArtwork(image, key: cacheKey, title: currentTitle, artist: currentArtist)
                }
            }
        }
    }

    /// Publish artwork only if the track hasn't changed since the fetch started.
    private func applyArtwork(_ image: NSImage?, key: NSString, title: String, artist: String) {
        if let image = image {
            artworkCache.setObject(image, forKey: key)
        }
        DispatchQueue.main.async {
            if self.trackTitle == title && self.artist == artist {
                self.artworkImage = image
            }
        }
    }

    private func fetchArtworkFromiTunes(title: String, artist: String, completion: @escaping (NSImage?) -> Void) {
        let term = "\(artist) \(title)"
        guard let encodedTerm = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encodedTerm)&entity=song&limit=1") else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            guard error == nil, let data = data,
                  let searchResult = try? JSONDecoder().decode(iTunesSearchResponse.self, from: data),
                  let artworkUrlString = searchResult.results.first?.artworkUrl100,
                  let artworkUrl = URL(string: artworkUrlString.replacingOccurrences(of: "100x100", with: "200x200"))
            else {
                completion(nil)
                return
            }

            // A second request rather than `Data(contentsOf:)`, which would block a
            // URLSession delegate thread on a synchronous network fetch.
            URLSession.shared.dataTask(with: artworkUrl) { imageData, _, _ in
                completion(imageData.flatMap(NSImage.init(data:)))
            }.resume()
        }.resume()
    }

    private func runAppleScript(_ source: String) -> String? {
        return autoreleasepool {
            guard let script = NSAppleScript(source: source) else { return nil }
            var error: NSDictionary?
            let descriptor = script.executeAndReturnError(&error)
            if error != nil {
                return nil
            }
            return descriptor.stringValue
        }
    }

    private func pollMusicStateBackground() {
        let script = """
        set sep to (character id 31)
        set musicRunning to false

        tell application "System Events"
            set musicRunning to (count of (every process whose name is "Music")) > 0
        end tell

        if musicRunning then
            tell application "Music"
                if player state is playing then
                    return "Music" & sep & "Playing" & sep & (name of current track) & sep & (artist of current track) & sep & (player position) & sep & (duration of current track)
                end if
            end tell
        end if

        if musicRunning then
            tell application "Music"
                try
                    return "Music" & sep & "Paused" & sep & (name of current track) & sep & (artist of current track) & sep & (player position) & sep & (duration of current track)
                on error
                    return "Music" & sep & "Stopped" & sep & "" & sep & "" & sep & "0" & sep & "0"
                end try
            end tell
        end if

        return "None" & sep & "Stopped" & sep & "" & sep & "" & sep & "0" & sep & "0"
        """

        let output = self.runAppleScript(script)
        DispatchQueue.main.async { [weak self] in
            self?.parseState(output)
        }
    }

    private func parseState(_ stateString: String?) {
        guard let stateString = stateString else {
            // Script failed (Music quit mid-call, Automation permission revoked).
            // Fall back to a known-idle state rather than leaving stale data on screen.
            resetToIdle()
            return
        }

        let parts = stateString.components(separatedBy: MusicManager.fieldSeparator)
        guard parts.count >= 6 else {
            resetToIdle()
            return
        }

        // Anchor the fixed fields to both ends. Even if a title somehow contained the
        // separator, position and duration are still read from the correct place.
        let player = PlayerType(rawValue: parts[0]) ?? .none
        let status = parts[1]
        let title = parts[2]
        let art = parts[3..<(parts.count - 2)].joined(separator: " ")
        let pos = Double(parts[parts.count - 2]) ?? 0.0
        let dur = Double(parts[parts.count - 1]) ?? 0.0

        self.activePlayer = player
        self.trackTitle = title.isEmpty ? "Not Playing" : title
        self.artist = art
        self.setPosition(pos)
        self.trackDuration = dur
        self.isPlaying = (status == "Playing")

        let currentTrackIdentifier = "\(player.rawValue)|\(title)|\(art)"
        if currentTrackIdentifier != lastTrackIdentifier {
            lastTrackIdentifier = currentTrackIdentifier
            updateArtwork()
        }
    }

    private func resetToIdle() {
        activePlayer = .none
        trackTitle = "Not Playing"
        artist = ""
        setPosition(0)
        trackDuration = 0
        isPlaying = false
        artworkImage = nil
        lastTrackIdentifier = ""
    }

    func playPause() {
        runScriptAsync("tell application \"Music\" to playpause")
        // Optimistically toggle state; the follow-up poll corrects it if the script failed.
        // Freeze the extrapolated position first, so pausing doesn't snap the bar back
        // to where it was at the last sync.
        setPosition(position(at: Date()))
        self.isPlaying.toggle()
    }

    func nextTrack() {
        runScriptAsync("tell application \"Music\" to next track")
    }

    func previousTrack() {
        runScriptAsync("tell application \"Music\" to back track")
    }

    private func runScriptAsync(_ scriptSource: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = self?.runAppleScript(scriptSource)
            self?.pollMusicStateBackground()
        }
    }
}

private struct iTunesSearchResponse: Codable {
    struct Result: Codable {
        let artworkUrl100: String?
    }
    let results: [Result]
}
