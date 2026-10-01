import SwiftUI
import Cocoa

/// Five bars that bounce while music plays.
///
/// The old version drove this from a 0.15 s `Timer` that wrote random heights into
/// `@State` inside `withAnimation`: a body re-evaluation, layout pass and window redraw
/// 6.6 times a second for as long as anything played. The bars are now `CALayer`s with
/// repeating `CABasicAnimation`s, which Core Animation runs in the render server — the
/// app itself does no per-frame work at all.
struct MiniVisualizer: View {
    let isPlaying: Bool
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VisualizerBars(isPlaying: isPlaying, animates: isPlaying && !reduceMotion, color: NSColor(color))
            .frame(width: VisualizerBarsView.totalWidth, height: VisualizerBarsView.maxBarHeight)
            .accessibilityHidden(true)
    }
}

private struct VisualizerBars: NSViewRepresentable {
    let isPlaying: Bool
    let animates: Bool
    let color: NSColor

    func makeNSView(context: Context) -> VisualizerBarsView {
        let view = VisualizerBarsView()
        update(view)
        return view
    }

    func updateNSView(_ view: VisualizerBarsView, context: Context) {
        update(view)
    }

    private func update(_ view: VisualizerBarsView) {
        view.color = color
        view.setState(isPlaying: isPlaying, animates: animates)
    }
}

final class VisualizerBarsView: NSView {
    static let barCount = 5
    static let barWidth: CGFloat = 2
    static let barSpacing: CGFloat = 2
    static let maxBarHeight: CGFloat = 12
    static let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing

    /// Heights shown when playing without animation (Reduce Motion).
    private static let restHeights: [CGFloat] = [6, 4, 8, 5, 7]
    private static let stoppedHeight: CGFloat = 2
    private static let minAnimatedHeight: CGFloat = 3

    /// Different, non-harmonic periods so the bars never fall into step.
    private static let durations: [CFTimeInterval] = [0.43, 0.57, 0.37, 0.61, 0.49]

    private static let animationKey = "bounce"

    private var bars: [CALayer] = []
    private var isPlaying = false
    private var animates = false

    var color: NSColor = .systemPink {
        didSet {
            guard color != oldValue else { return }
            withoutActions { bars.forEach { $0.backgroundColor = color.cgColor } }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Layer-hosting rather than layer-backed: the root layer exists immediately and
        // AppKit leaves its sublayers to us.
        layer = CALayer()
        wantsLayer = true
        for _ in 0..<VisualizerBarsView.barCount {
            let bar = CALayer()
            bar.backgroundColor = color.cgColor
            bar.cornerRadius = 1
            layer?.addSublayer(bar)
            bars.append(bar)
        }
        applyState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        // Each bar is laid out at full height and scaled down vertically, so the
        // animation only touches `transform` — the cheapest property to composite.
        withoutActions {
            let midY = bounds.midY
            for (index, bar) in bars.enumerated() {
                let x = CGFloat(index) * (VisualizerBarsView.barWidth + VisualizerBarsView.barSpacing)
                bar.bounds = CGRect(x: 0, y: 0, width: VisualizerBarsView.barWidth, height: VisualizerBarsView.maxBarHeight)
                bar.position = CGPoint(x: x + VisualizerBarsView.barWidth / 2, y: midY)
            }
        }
    }

    /// Core Animation can drop running animations when a layer leaves the window, so
    /// re-add them whenever the view is put back on screen.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { applyState() }
    }

    func setState(isPlaying: Bool, animates: Bool) {
        guard isPlaying != self.isPlaying || animates != self.animates else { return }
        self.isPlaying = isPlaying
        self.animates = animates
        applyState()
    }

    private func applyState() {
        withoutActions {
            for (index, bar) in bars.enumerated() {
                bar.removeAnimation(forKey: VisualizerBarsView.animationKey)

                let height: CGFloat = isPlaying ? VisualizerBarsView.restHeights[index] : VisualizerBarsView.stoppedHeight
                bar.transform = CATransform3DMakeScale(1, height / VisualizerBarsView.maxBarHeight, 1)

                guard animates else { continue }

                let duration = VisualizerBarsView.durations[index]
                let bounce = CABasicAnimation(keyPath: "transform.scale.y")
                bounce.fromValue = VisualizerBarsView.minAnimatedHeight / VisualizerBarsView.maxBarHeight
                bounce.toValue = 1.0
                bounce.duration = duration
                bounce.autoreverses = true
                bounce.repeatCount = .infinity
                bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                // Start each bar part-way through its cycle so they don't all rise together.
                bounce.timeOffset = duration * Double(index) / Double(VisualizerBarsView.barCount)
                bounce.isRemovedOnCompletion = false
                bar.add(bounce, forKey: VisualizerBarsView.animationKey)
            }
        }
    }

    private func withoutActions(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
