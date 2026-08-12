import SwiftUI

/// Circular crest for a team, or a subtle placeholder while it loads.
///
/// The same `AsyncImage` block was pasted six times across the collapsed and expanded
/// sports views.
struct TeamLogo: View {
    let url: String?
    var size: CGFloat = 16

    var body: some View {
        if let url = url, let parsed = URL(string: url) {
            AsyncImage(url: parsed) { image in
                image.resizable()
            } placeholder: {
                Color.white.opacity(0.1)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityHidden(true)
        }
    }
}
