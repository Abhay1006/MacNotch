import SwiftUI
import Cocoa

struct AppsTab: View {
    @ObservedObject var favoriteApps: FavoriteAppsManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredAppId: UUID? = nil

    private let columns = Array(repeating: GridItem(.flexible()), count: 5)

    var body: some View {
        VStack(spacing: 6) {
            Text("Favorite Apps")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            if favoriteApps.apps.isEmpty {
                emptyState
            } else {
                grid
            }

            Text("Drag & drop .app here to add • Click (X) or Right-click to remove")
                .font(.system(size: 8, design: .rounded))
                .foregroundColor(.white.opacity(0.45))
                .padding(.bottom, 2)
        }
        .padding(.horizontal, 15)
        .padding(.top, 8)
        .padding(.bottom, 5)
        .frame(height: 125)
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "square.grid.3x3.topleft.filled")
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.3))

            Text("No favorite apps added yet.")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(height: 80)
    }

    private var grid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(favoriteApps.apps) { app in
                    appCell(app)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
        }
        .frame(height: 80)
    }

    private func appCell(_ app: FavApp) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Button(action: { favoriteApps.launchApp(app) }) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(8)
                        .shadow(radius: 2)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Launch \(app.name)")

                if hoveredAppId == app.id {
                    Button(action: {
                        withAnimation(reduceMotion ? nil : .default) {
                            favoriteApps.remove(app)
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.red)
                            .background(Color.white.clipShape(Circle()))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .offset(x: 6, y: -6)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Remove \(app.name) from favorites")
                }
            }
            .onHover { isHovering in
                withAnimation(reduceMotion ? nil : .easeIn(duration: 0.1)) {
                    hoveredAppId = isHovering ? app.id : nil
                }
            }

            Text(app.name)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
                .frame(maxWidth: 60)
        }
        .contextMenu {
            Button(action: { favoriteApps.remove(app) }) {
                Label("Remove Favorite", systemImage: "trash")
            }
        }
    }
}
