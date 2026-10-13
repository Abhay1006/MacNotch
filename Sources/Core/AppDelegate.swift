import Cocoa
import SwiftUI
import Combine

/// Per-window UI state.
class AppState: ObservableObject {
    @Published var isExpanded: Bool = false
    @Published var hoverLocked: Bool = false
    /// Lives here rather than in the view so the window controller can switch tabs on a
    /// trackpad swipe.
    @Published var currentTab: IslandTab = .music
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
    private var localKeyMonitor: Any?
    private var localScrollMonitor: Any?
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
        // Drags count too: a file dragged from Finder moves the cursor without any
        // `.mouseMoved`, and the island must stop ignoring the mouse to accept the drop.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] event in
            if event.type == .leftMouseDragged {
                self?.mouseDragged()
            } else {
                self?.mouseMoved()
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.mouseMoved()
            return event
        }

        // Only reaches us while an island window is key (after clicking into it): a
        // global key monitor would need Accessibility access, and making the panel key on
        // hover would steal typing from the app underneath.
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let escapeKeyCode: UInt16 = 53
            if event.keyCode == escapeKeyCode,
               let controller = self?.controller(for: event.window),
               controller.appState.isExpanded {
                controller.dismiss()
                return nil
            }
            return event
        }

        // Scroll events go to the window under the cursor even while the app is inactive.
        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.controller(for: event.window)?.handleScroll(event)
            return event
        }
    }

    private func stopMouseMonitoring() {
        for monitor in [globalMouseMonitor, localMouseMonitor, localKeyMonitor, localScrollMonitor] {
            if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        localKeyMonitor = nil
        localScrollMonitor = nil
    }

    private func controller(for window: NSWindow?) -> NotchWindowController? {
        guard let window = window else { return nil }
        return controllers.values.first { $0.window === window }
    }

    private func mouseDragged() {
        let location = NSEvent.mouseLocation
        for controller in controllers.values {
            controller.updateMouseTransparency(at: location)
        }
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

    /// The island's current laid-out size, as reported by the view. The window itself
    /// never changes size; this drives hover and click-through instead.
    private var islandSize: CGSize

    /// Hover intent: open only once the cursor rests on the island, close only once it
    /// has been gone for a moment. Without these, sweeping across the menu bar popped the
    /// panel open, and grazing its edge made it flicker.
    private static let openDelay: TimeInterval = 0.12
    private static let closeDelay: TimeInterval = 0.25
    private var pendingHoverChange: DispatchWorkItem?
    private var pendingHoverTarget: Bool?

    /// Set when the island is dismissed with Esc, so it doesn't spring straight back open
    /// under a cursor that is still sitting on it.
    private var reopenRequiresExit = false

    /// Two-finger horizontal swipe tracking.
    private var swipeDistance = CGSize.zero
    private var swipeHandled = false
    private var swipeStartedInHeader = false

    private var menuBeginObserver: Any?
    private var menuEndObserver: Any?

    init(screen: NSScreen, delegate: AppDelegate) {
        self.screen = screen
        self.delegate = delegate
        self.appState = AppState()
        self.metrics = NotchMetrics(screen: screen)
        self.islandSize = metrics.collapsedIdle

        window = NotchPanel(
            contentRect: metrics.canvasFrame(on: screen),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        // The window spans the island's largest size; until the cursor is actually on
        // the island, clicks fall through to the menu bar and apps underneath.
        window.ignoresMouseEvents = true

        installContentView()
        // `orderFrontRegardless` alone is enough — `makeKeyAndOrderFront` would steal
        // key status from whatever the user is working in, at launch, on every screen.
        window.orderFrontRegardless()

        setupMenuObservers()
    }

    deinit {
        cancelPendingHoverChange()
        removeMenuObservers()
    }

    func close() {
        cancelPendingHoverChange()
        removeMenuObservers()
        window.close()
    }

    /// Reattach to a screen whose geometry may have changed (resolution, arrangement).
    func update(screen: NSScreen) {
        self.screen = screen
        let newMetrics = NotchMetrics(screen: screen)
        if newMetrics != metrics {
            metrics = newMetrics
            installContentView()
        }
        window.setFrame(metrics.canvasFrame(on: screen), display: true)
    }

    private func installContentView() {
        let contentView = NotchIslandView(appState: appState, metrics: metrics) { [weak self] newSize in
            self?.islandDidResize(to: newSize)
        }
        window.contentView = AcceptsFirstMouseHostingView(rootView: contentView)
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

    // MARK: Hover

    /// Track the rendered size instead of a fixed 240×35 floor, which used to swallow
    /// clicks on menu-bar items near the centre of the screen.
    private var hoverRect: NSRect {
        metrics.hoverRect(on: screen, currentSize: islandSize)
    }

    private func islandDidResize(to size: CGSize) {
        guard size != islandSize else { return }
        islandSize = size
        updateMouseTransparency(at: NSEvent.mouseLocation)
    }

    /// Let the mouse through everywhere except over the island itself.
    func updateMouseTransparency(at location: NSPoint) {
        let ignores = !hoverRect.contains(location)
        if window.ignoresMouseEvents != ignores {
            window.ignoresMouseEvents = ignores
        }
    }

    func checkMouseHover(at location: NSPoint) {
        updateMouseTransparency(at: location)

        let isInside = hoverRect.contains(location)
        if !isInside { reopenRequiresExit = false }

        guard !appState.hoverLocked, !isMenuTracking, !menuCooldownActive else {
            cancelPendingHoverChange()
            return
        }

        let wantsExpanded = isInside && !reopenRequiresExit
        guard wantsExpanded != appState.isExpanded else {
            cancelPendingHoverChange()
            return
        }
        guard pendingHoverTarget != wantsExpanded else { return } // Already on its way.

        cancelPendingHoverChange()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.pendingHoverChange = nil
            self.pendingHoverTarget = nil

            // Re-check: the cursor may have moved on, or a menu opened, while waiting.
            let stillInside = self.hoverRect.contains(NSEvent.mouseLocation)
            guard stillInside == wantsExpanded,
                  !self.appState.hoverLocked, !self.isMenuTracking, !self.menuCooldownActive
            else { return }
            self.setExpanded(wantsExpanded)
        }
        pendingHoverChange = work
        pendingHoverTarget = wantsExpanded
        let delay = wantsExpanded ? NotchWindowController.openDelay : NotchWindowController.closeDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPendingHoverChange() {
        pendingHoverChange?.cancel()
        pendingHoverChange = nil
        pendingHoverTarget = nil
    }

    private func setExpanded(_ expanded: Bool) {
        guard appState.isExpanded != expanded else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75)) {
            appState.isExpanded = expanded
        }
        // Only felt on a Force Touch trackpad with a finger on it; a no-op otherwise.
        if expanded && Preferences.shared.hapticFeedbackEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    /// Esc: collapse, and hand the keyboard back to the app the user came from.
    func dismiss() {
        cancelPendingHoverChange()
        reopenRequiresExit = hoverRect.contains(NSEvent.mouseLocation)
        setExpanded(false)
        if window.isKeyWindow {
            delegate?.restorePreviousActiveApp()
        }
    }

    // MARK: Swipe between tabs

    func handleScroll(_ event: NSEvent) {
        // Trackpad gestures only: a mouse wheel has no phase, and momentum would fire a
        // second switch after the fingers lift.
        guard appState.isExpanded, event.momentumPhase.isEmpty, !event.phase.isEmpty else { return }

        if event.phase.contains(.began) {
            swipeDistance = .zero
            swipeHandled = false
            let depth = screen.frame.maxY - NSEvent.mouseLocation.y
            swipeStartedInHeader = depth <= metrics.tabHeaderDepth
            return
        }
        guard event.phase.contains(.changed), !swipeHandled else { return }

        swipeDistance.width += event.scrollingDeltaX
        swipeDistance.height += event.scrollingDeltaY

        let threshold: CGFloat = 50
        guard abs(swipeDistance.width) > threshold,
              abs(swipeDistance.width) > abs(swipeDistance.height) * 2 else { return }

        // The clipboard tab's file shelf scrolls sideways itself, so there only a swipe
        // on the tab bar switches tabs.
        if appState.currentTab == .clipboard,
           !AppEnvironment.shared.fileShelf.files.isEmpty,
           !swipeStartedInHeader {
            return
        }

        swipeHandled = true
        // Deltas follow the content, not the fingers, under natural scrolling.
        let fingerDX = event.isDirectionInvertedFromDevice ? -swipeDistance.width : swipeDistance.width
        // Fingers moving left bring in the next tab, like turning a page.
        selectAdjacentTab(fingerDX < 0 ? 1 : -1)
    }

    private func selectAdjacentTab(_ step: Int) {
        let tabs = Preferences.shared.visibleTabs
        guard let index = tabs.firstIndex(of: appState.currentTab) else { return }
        let target = index + step
        guard tabs.indices.contains(target) else { return }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
            appState.currentTab = tabs[target]
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
