import Cocoa
import SwiftUI

// Global strong reference to keep the AppDelegate alive in memory
var appDelegate: AppDelegate?

class AppState: ObservableObject {
    @Published var isExpanded: Bool = false
    @Published var hoverLocked: Bool = false
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [NotchWindowController] = []
    private(set) var previousActiveApp: NSRunningApplication?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setbuf(stdout, nil)
        // Set accessory activation policy so the app doesn't show in the Dock
        NSApp.setActivationPolicy(.accessory)
        
        // Track the previously active application
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let newApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                if newApp.bundleIdentifier != Bundle.main.bundleIdentifier {
                    self?.previousActiveApp = newApp
                }
            }
        }
        
        setupWindows()
        
        // Listen to screen changes (plugging in / unplugging external monitors)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setupWindows()
        }
    }
    
    func setupWindows() {
        // Clear existing controllers and close their windows
        for controller in controllers {
            controller.window.close()
        }
        controllers.removeAll()
        
        // Create a controller for each screen
        for screen in NSScreen.screens {
            let controller = NotchWindowController(screen: screen, delegate: self)
            controllers.append(controller)
        }
    }
    
    func restorePreviousActiveApp() {
        if let app = previousActiveApp {
            app.activate()
        }
    }
}

class NotchWindowController {
    let window: TouchBarWindow
    let appState: AppState
    let screen: NSScreen
    weak var delegate: AppDelegate?
    
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var isMenuTracking = false
    private var menuCooldownActive = false
    private var targetSize = CGSize(width: 240, height: 35)
    
    private var menuBeginObserver: Any?
    private var menuEndObserver: Any?
    
    init(screen: NSScreen, delegate: AppDelegate) {
        self.screen = screen
        self.delegate = delegate
        self.appState = AppState()
        
        let initialSize = CGSize(width: 240, height: 35)
        let x = screen.frame.minX + (screen.frame.width - initialSize.width) / 2
        let y = screen.frame.maxY - initialSize.height
        
        window = TouchBarWindow(
            contentRect: NSRect(x: x, y: y, width: initialSize.width, height: initialSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        
        let contentView = NotchIslandView(appState: appState) { [weak self] newSize in
            self?.resizeWindow(to: newSize)
        }
        
        class AcceptsFirstMouseHostingView<Content: View>: NSHostingView<Content> {
            override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
                return true
            }
        }
        
        window.contentView = AcceptsFirstMouseHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        
        startMouseMonitoring()
        setupMenuObservers()
    }
    
    deinit {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let observer = menuBeginObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = menuEndObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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
            
            // Grace period to move mouse back to Notch
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.menuCooldownActive = false
                self?.checkMouseHover()
            }
        }
    }
    
    private func startMouseMonitoring() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            self?.checkMouseHover()
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: handler)
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.checkMouseHover()
            return event
        }
    }
    
    private func checkMouseHover() {
        guard !appState.hoverLocked else { return }
        guard !isMenuTracking else { return }
        guard !menuCooldownActive else { return }
        
        let midX = screen.frame.minX + screen.frame.width / 2
        let maxY = screen.frame.maxY
        
        let detectionWidth = max(240, targetSize.width)
        let detectionHeight = max(35, targetSize.height)
        let targetFrame = NSRect(
            x: midX - detectionWidth / 2,
            y: maxY - detectionHeight,
            width: detectionWidth,
            height: detectionHeight
        )
        
        let mouseLoc = NSEvent.mouseLocation
        let isInside = targetFrame.contains(mouseLoc)
        
        if isInside != appState.isExpanded {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                appState.isExpanded = isInside
            }
        }
    }
    
    func resizeWindow(to size: CGSize) {
        if self.targetSize == size { return } // Prevent continuous redundant animations
        self.targetSize = size
        
        let midX = screen.frame.minX + screen.frame.width / 2
        let maxY = screen.frame.maxY
        
        let newFrame = NSRect(
            x: midX - size.width / 2,
            y: maxY - size.height,
            width: size.width,
            height: size.height
        )
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }, completionHandler: nil)
    }
}

class TouchBarWindow: NSPanel {
    override var canBecomeKey: Bool {
        // Return true so text fields (like clipboard search) can get focus
        return true
    }
    
    override var canBecomeMain: Bool {
        return false
    }
    
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        
        // Keep the panel floating and clear of titlebar
        self.isMovable = false
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.acceptsMouseMovedEvents = true
    }
}

// Start NSApplication manually
let app = NSApplication.shared
let delegate = AppDelegate()
appDelegate = delegate
app.delegate = delegate
app.run()
