import SwiftUI
import Cocoa

struct MusicTab: View {
    @ObservedObject var music: MusicManager

    var body: some View {
        HStack(spacing: 16) {
            artwork
                .onTapGesture { openMusicApp() }
                .onHover { inside in
                    if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                }
                .padding(.leading, 16)
                .accessibilityLabel("Open Music")

            VStack(alignment: .leading, spacing: 4) {
                Text(music.trackTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(music.artist.isEmpty ? "No active media" : music.artist)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)

                if music.trackDuration > 0 {
                    progressBar
                }
            }

            Spacer()

            controls
                .padding(.trailing, 16)
        }
        .frame(height: 80)
    }

    private var artwork: some View {
        ZStack {
            if let artwork = music.artworkImage {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color.pink.opacity(0.4), Color.black],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 54, height: 54)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )

                Image(systemName: "music.note.house")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 4)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.pink)
                    .frame(width: geo.size.width * progressFraction, height: 4)
            }
        }
        .frame(height: 4)
        .padding(.top, 4)
        .accessibilityHidden(true)
    }

    private var progressFraction: CGFloat {
        guard music.trackDuration > 0 else { return 0 }
        return CGFloat(min(1, max(0, music.playerPosition / music.trackDuration)))
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button(action: { music.previousTrack() }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.85))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Previous track")

            Button(action: { music.playPause() }) {
                Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(music.isPlaying ? "Pause" : "Play")

            Button(action: { music.nextTrack() }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.85))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Next track")
        }
    }

    private func openMusicApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
