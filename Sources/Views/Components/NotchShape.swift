import SwiftUI

/// The island's outline: rounded bottom corners, with a top edge that either rounds
/// inward like a capsule or flares outward into the top of the screen like the
/// physical notch.
///
/// `topCornerRadius` is signed so the two looks animate into each other:
/// - positive: ordinary convex corners (the free-floating collapsed pill);
/// - zero: square corners, flush with the screen edge;
/// - negative: concave "ears" that curve out and meet the screen edge tangentially, so
///   the expanded panel reads as part of the bezel rather than a card hanging below it.
///   The sides are inset by the flare so the shape still fits its frame.
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    /// When `false` the top edge is left open — for stroking an outline without drawing
    /// a line along the top of the screen.
    var closesTopEdge = true

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        // Flare (outward) and convex (inward) parts of the top corner; at most one is non-zero.
        let flare = min(max(0, -topCornerRadius), w / 4, h / 2)
        let convex = min(max(0, topCornerRadius), w / 2, h / 2)
        let bottom = min(max(0, bottomCornerRadius), (w - 2 * flare) / 2, h - convex - flare)

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x, y: rect.minY + y)
        }

        var path = Path()
        // Clockwise from the top edge, so the open variant can simply skip it.
        path.move(to: p(w - convex, 0))
        path.addCorner(via: p(w - flare, 0), to: p(w - flare, convex + flare))
        path.addLine(to: p(w - flare, h - bottom))
        path.addCorner(via: p(w - flare, h), to: p(w - flare - bottom, h))
        path.addLine(to: p(flare + bottom, h))
        path.addCorner(via: p(flare, h), to: p(flare, h - bottom))
        path.addLine(to: p(flare, convex + flare))
        path.addCorner(via: p(flare, 0), to: p(convex, 0))
        if closesTopEdge {
            path.closeSubpath()
        }
        return path
    }
}

private extension Path {
    /// A quarter-circle-like corner from the current point to `end`, bending towards
    /// `corner` (the point where the two straight edges would meet).
    mutating func addCorner(via corner: CGPoint, to end: CGPoint) {
        guard let start = currentPoint else { return }
        // Cubic Bézier approximation of a circular arc.
        let k: CGFloat = 0.5523
        addCurve(
            to: end,
            control1: CGPoint(x: start.x + (corner.x - start.x) * k, y: start.y + (corner.y - start.y) * k),
            control2: CGPoint(x: end.x + (corner.x - end.x) * k, y: end.y + (corner.y - end.y) * k)
        )
    }
}
