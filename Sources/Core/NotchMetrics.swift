import AppKit

/// Geometry for the island on a given screen.
///
/// Previously sizes like `110×22`, `240×35`, and `300×35` were hardcoded and duplicated
/// between `AppDelegate` and `NotchIslandView`, which meant the "hide behind the camera"
/// idle state only lined up on one Mac model — the notch differs between the 14", 16",
/// and 15" Air, and external displays have none at all.
///
/// macOS 12+ reports the real cutout through `NSScreen.safeAreaInsets` and
/// `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`, so derive it instead of guessing.
struct NotchMetrics: Equatable {
    /// Whether this screen has a physical camera housing.
    let hasNotch: Bool
    /// Size of the physical notch, or a synthetic pill on screens without one.
    let notchSize: CGSize

    // Sanity bounds. If the reported geometry is implausible (an odd virtual display,
    // a future layout change), clamp rather than render something broken.
    private static let widthRange: ClosedRange<CGFloat> = 120...280
    private static let heightRange: ClosedRange<CGFloat> = 20...44

    /// Fallback used on screens with no notch, matching the app's original look.
    private static let notchlessIdle = CGSize(width: 110, height: 22)

    init(screen: NSScreen) {
        let inset = screen.safeAreaInsets.top

        // A notched built-in display reports a non-zero top safe-area inset *and*
        // splits the menu bar into two auxiliary areas either side of the cutout.
        if inset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let rawWidth = screen.frame.width - left.width - right.width
            hasNotch = rawWidth > 0
            notchSize = CGSize(
                width: rawWidth.clamped(to: NotchMetrics.widthRange),
                height: inset.clamped(to: NotchMetrics.heightRange)
            )
        } else {
            hasNotch = false
            notchSize = NotchMetrics.notchlessIdle
        }
    }

    /// Idle collapsed size — tucked entirely behind the camera housing so it is invisible.
    ///
    /// Inset slightly so rounded corners cannot peek past the cutout if the reported
    /// geometry is a point or two optimistic.
    var collapsedIdle: CGSize {
        guard hasNotch else { return NotchMetrics.notchlessIdle }
        return CGSize(width: notchSize.width - 4, height: notchSize.height - 2)
    }

    /// Collapsed size when there is live content (music, a match, Zen, a notification)
    /// that must sit clear of the camera on both sides.
    var collapsedActive: CGSize {
        // Enough room either side of the cutout for a glyph plus a short label.
        CGSize(width: max(300, notchSize.width + 110), height: max(35, notchSize.height))
    }

    /// Width of the expanded panel.
    var expandedWidth: CGFloat { 380 }

    /// Vertical space the expanded panel must leave clear for the physical camera.
    var expandedTopClearance: CGFloat { max(35, notchSize.height) }

    /// Hover target. Deliberately a little larger than the rendered capsule so the
    /// island is easy to hit — but no longer clamped to a fixed 240×35, which used to
    /// swallow clicks on menu-bar items near the centre of the screen.
    func hoverRect(on screen: NSScreen, currentSize: CGSize) -> NSRect {
        let margin: CGFloat = 6
        let width = currentSize.width + margin * 2
        let height = currentSize.height + margin
        let midX = screen.frame.minX + screen.frame.width / 2
        return NSRect(
            x: midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
