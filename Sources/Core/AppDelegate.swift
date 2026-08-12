import Cocoa
import SwiftUI
import Combine

/// Per-window UI state.
class AppState: ObservableObject {
    @Published var isExpanded: Bool = false
    @Published var hoverLocked: Bool = false
}

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Keyed by `CGDirectDisplayID` so screens can be diffed instead of rebuilt.
    private var controllers: [CGDirectDisplayID: NotchWindowController] = [:]
    private(set) var previousActiveApp: NSRunningApplication?

    /// One monitor for the whole app.
    ///
    /// Previously each window controller installed its own global `.mouseMoved` monitor,
    /// so every mouse movement anywhere on the system woke N handlers on a multi-display
    /// setup. There is no reason for more than one.
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var lastMouseLocation: NSPoint = .zero

    private var cancellables = Set<AnyCancellable>()
    private var appActivationObserver: NSObjectProtocol?
    private var screenChangeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setbuf(stdout, nil)
        // Accessory activation policy so the app doesn't show in the Dock
        NSApp.setActivationPolicy(.accessory)

        // Instantiating the environment starts every manager exactly once, for the
        // whole app, independent of how many windows exist.
        _ = AppEnvironment.shared

        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let newApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               newApp.bundleIdentifier != Bundle.main.bundleIdentifier {
                self?.previousActiveApp = newApp
            }
        }

        syncWindows()
        startMouseMonitoring()

        // Plugging in or removing a monitor, changing resolution, display sleep.
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncWindows()
        }

        Preferences.shared.$showOnExternalDisplays
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.syncWindows() }
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopMouseMonitoring()
        if let observer = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Windows

    /// Reconcile windows with the current screen list.
    ///
    /// The old version closed every window and rebuilt from scratch on each screen-parameter
    /// notification — which also rebuilt every manager, leaking their timers and wiping
    /// clipboard history and any running Zen session. Now only genuine additions and
    /// removals do any work.
    private func syncWindows() {
        let screens = eligibleScreens()
        var seen = Set<CGDirectDisplayID>()

        for screen in screens {
            guard let id = screen.displayID else { continue }
            seen.insert(id)

            if let existing = controllers[id] {
                existing.update(screen: screen)
            } else {
                controllers[id] = NotchWindowController(screen: screen, delegate: self)
                Log.window.info("Added island for display \(id)")
            }
        }

        for (id, controller) in controllers where !seen.contains(id) {
            controller.close()
            controllers.removeValue(forKey: id)
            Log.window.info("Removed island for display \(id)")
        }
    }

    private func eligibleScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        guard !Preferences.shared.showOnExternalDisplays else { return screens }
        let builtIn = screens.filter { $0.isBuiltIn }
        // Never end up with nothing — a Mac mini or a clamshell setup has no built-in screen.
        return builtIn.isEmpty ? Array(screens.prefix(1)) : builtIn
    }

    func restorePreviousActiveApp() {
        previousActiveApp?.activate()
    }

    // MARK: - Hover

    private func startMouseMonitoring() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.mouseMoved()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.mouseMoved()
            return event
        }
    }

    private func stopMouseMonitoring() {
        if let monitor = globalMouseMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMouseMonitor { NSEvent.removeMonitor(monitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
    }

    private func mouseMoved() {
        let location = NSEvent.mouseLocation
        // Sub-pixel jitter and duplicate global/local deliveries of the same event
        // shouldn't cost anything.
        guard location != lastMouseLocation else { return }
        lastMouseLocation = location

        for controller in controllers.values {
            controller.checkMouseHover(at: location)
        }
    }
}

// MARK: - Window controller

class NotchWindowController {
    let window: NotchPanel
    let appState: AppState
    private(set) var screen: NSScreen
    private(set) var metrics: NotchMetrics
    weak var delegate: AppDelegate?

    private var isMenuTracking = false
    private var menuCooldownActive = false
    private var targetSize: CGSize

    private var menuBeginObserver: Any?
    private var menuEndObserver: Any?

    init(screen: NSScreen, delegate: AppDelegate) {
        self.screen = screen
        self.delegate = delegate
        self.appState = AppState()
        self.metrics = NotchMetrics(screen: screen)
        self.targetSize = metrics.collapsedIdle

        let x = screen.frame.minX + (screen.frame.width - targetSize.width) / 2
        let y = screen.frame.maxY - targetSize.height

        window = NotchPanel(
            contentRect: NSRect(x: x, y: y, width: targetSize.width, height: targetSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false

        let contentView = NotchIslandView(appState: appState, metrics: metrics) { [weak self] newSize in
            self?.resizeWindow(to: newSize)
        }

        window.contentView = AcceptsFirstMouseHostingView(rootView: contentView)
        // `orderFrontRegardless` alone is enough — `makeKeyAndOrderFront` would steal
        // key status from whatever the user is working in, at launch, on every screen.
        window.orderFrontRegardless()

        setupMenuObservers()
    }

    deinit {
        removeMenuObservers()
    }

    func close() {
        removeMenuObservers()
        window.close()
    }

    /// Reattach to a screen whose geometry may have changed (resolution, arrangement).
    func update(screen: NSScreen) {
        self.screen = screen
        let newMetrics = NotchMetrics(screen: screen)
        if newMetrics != metrics {
            metrics = newMetrics
            let contentView = NotchIslandView(appState: appState, metrics: metrics) { [weak self] newSize in
                self?.resizeWindow(to: newSize)
            }
            window.contentView = AcceptsFirstMouseHostingView(rootView: contentView)
        }
        repositionWindow(to: targetSize, animated: false)
    }

    private func setupMenuObservers() {
        menuBeginObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isMenuTracking = true
        }

        menuEndObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isMenuTracking = false
            self?.menuCooldownActive = true

            // Grace period to move the mouse back to the notch
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.menuCooldownActive = false
                self?.checkMouseHover(at: NSEvent.mouseLocation)
            }
        }
    }

    private func removeMenuObservers() {
        if let observer = menuBeginObserver {
            NotificationCenter.default.removeObserver(observer)
            menuBeginObserver = nil
        }
        if let observer = menuEndObserver {
            NotificationCenter.default.removeObserver(observer)
            menuEndObserver = nil
        }
    }

    func checkMouseHover(at location: NSPoint) {
        guard !appState.hoverLocked, !isMenuTracking, !menuCooldownActive else { return }

        // Track the rendered size instead of a fixed 240×35 floor, which used to
        // swallow clicks on menu-bar items near the centre of the screen.
        let isInside = metrics.hoverRect(on: screen, currentSize: targetSize).contains(location)

        if isInside != appState.isExpanded {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                appState.isExpanded = isInside
            }
        }
    }

    func resizeWindow(to size: CGSize) {
        if targetSize == size { return } // Prevent continuous redundant animations
        targetSize = size
        repositionWindow(to: size, animated: true)
    }

    private func repositionWindow(to size: CGSize, animated: Bool) {
        let midX = screen.frame.minX + screen.frame.width / 2
        let newFrame = NSRect(
            x: midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )

        guard animated else {
            window.setFrame(newFrame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }
}

/// Hosting view that responds to the first click without requiring the window to be
/// activated first.
private class AcceptsFirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The borderless panel the island lives in.
class NotchPanel: NSPanel {
    override var canBecomeKey: Bool {
        // True so text fields (clipboard search, favourite team) can take focus.
        return true
    }

    override var canBecomeMain: Bool {
        return false
    }

    /// macOS otherwise pushes the frame down below the menu bar, which breaks placement
    /// on secondary displays.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)

        self.isMovable = false
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.acceptsMouseMovedEvents = true
    }
}

// MARK: - Screen helpers

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var isBuiltIn: Bool {
        guard let id = displayID else { return false }
        return CGDisplayIsBuiltin(id) != 0
    }
}
