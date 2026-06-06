import Foundation
import Combine
import Cocoa

class MusicManager: ObservableObject {
    @Published var activePlayer: PlayerType = .none
    @Published var isPlaying: Bool = false
    @Published var trackTitle: String = ""
    @Published var artist: String = ""
    @Published var playerPosition: Double = 0
    @Published var trackDuration: Double = 0
    @Published var artworkImage: NSImage? = nil
    
    private var lastTrackIdentifier: String = ""
    private var timer: AnyCancellable?
    
    enum PlayerType: String {
        case music = "Music"
        case none = "None"
    }
    
    init() {
        startMonitoring()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.pollMusicStateBackground()
        }
    }
    
    func startMonitoring() {
        // Poll every 1.0 second on background thread for track details and progress
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                DispatchQueue.global(qos: .userInitiated).async {
                    self?.pollMusicStateBackground()
                }
            }
    }
    
    private func updateArtwork() {
        if activePlayer == .none || trackTitle == "Not Playing" {
            self.artworkImage = nil
            return
        }
        
        // Export artwork to temporary file in the background to avoid blocking the main thread
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
                                set tempPath to POSIX file "/tmp/macnotch_artwork.jpg"
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
                if result == "SUCCESS" {
                    if let image = NSImage(contentsOfFile: "/tmp/macnotch_artwork.jpg") {
                        // Force load raw image data into memory before returning
                        _ = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                        DispatchQueue.main.async {
                            self.artworkImage = image
                        }
                        return
                    }
                }
                
                DispatchQueue.main.async {
                    self.artworkImage = nil
                }
            }
        }
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
        set musicRunning to false
        
        tell application "System Events"
            set musicRunning to (count of (every process whose name is "Music")) > 0
        end tell
        
        if musicRunning then
            tell application "Music"
                if player state is playing then
                    return "Music|Playing|" & name of current track & "|" & artist of current track & "|" & player position & "|" & duration of current track
                end if
            end tell
        end if
        
        if musicRunning then
            tell application "Music"
                try
                    return "Music|Paused|" & name of current track & "|" & artist of current track & "|" & player position & "|" & duration of current track
                on error
                    return "Music|Stopped|||0|0"
                end try
            end tell
        end if
        
        return "None|Stopped|||0|0"
        """
        
        let output = self.runAppleScript(script) ?? "None|Stopped|||0|0"
        DispatchQueue.main.async { [weak self] in
            self?.parseState(output)
        }
    }
    
    private func parseState(_ stateString: String) {
        let parts = stateString.components(separatedBy: "|")
        guard parts.count >= 6 else { return }
        
        let player = PlayerType(rawValue: parts[0]) ?? .none
        let status = parts[1]
        let title = parts[2]
        let art = parts[3]
        let pos = Double(parts[4]) ?? 0.0
        let dur = Double(parts[5]) ?? 0.0
        
        self.activePlayer = player
        self.isPlaying = (status == "Playing")
        self.trackTitle = title.isEmpty ? "Not Playing" : title
        self.artist = art.isEmpty ? "" : art
        self.playerPosition = pos
        self.trackDuration = dur
        
        let currentTrackIdentifier = "\(player.rawValue)|\(title)|\(art)"
        if currentTrackIdentifier != lastTrackIdentifier {
            lastTrackIdentifier = currentTrackIdentifier
            updateArtwork()
        }
    }
    
    func playPause() {
        let script = "tell application \"Music\" to playpause"
        runScriptAsync(script)
        // Optimistically toggle state
        self.isPlaying.toggle()
    }
    
    func nextTrack() {
        let script = "tell application \"Music\" to next track"
        runScriptAsync(script)
    }
    
    func previousTrack() {
        let script = "tell application \"Music\" to back track"
        runScriptAsync(script)
    }
    
    private func runScriptAsync(_ scriptSource: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = self?.runAppleScript(scriptSource)
            self?.pollMusicStateBackground()
        }
    }
}
