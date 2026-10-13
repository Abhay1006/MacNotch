import SwiftUI

/// A vertical scroll view that is only as tall as its content, up to `maxHeight`.
///
/// The expanded island sizes itself to whatever the current tab needs. A plain
/// `ScrollView` has no fixed height of its own to offer that measurement — asked for its
/// ideal size it either collapses or grows to the full content and stops scrolling — so
/// this measures the content and pins the scroll view to `min(content, maxHeight)`.
struct FittedScrollView<Content: View>: View {
    let maxHeight: CGFloat
    let showsIndicators: Bool
    let content: Content

    @State private var contentHeight: CGFloat = 0

    init(maxHeight: CGFloat, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.maxHeight = maxHeight
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: showsIndicators) {
            content
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )
        }
        .frame(height: min(contentHeight, maxHeight))
        .onPreferenceChange(ContentHeightKey.self) { height in
            contentHeight = height
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
