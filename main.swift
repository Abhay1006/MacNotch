import Cocoa
import SwiftUI

// Global strong reference to keep the AppDelegate alive in memory
var appDelegate: AppDelegate?

class AppState: ObservableObject {
    @Published var isExpanded: Bool = false
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: TouchBarWindow!
    let appState = AppState()
    private var mouseTimer: Timer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setbuf(stdout, nil)
        // Set accessory activation policy so the app doesn't show in the Dock
        NSApp.setActivationPolicy(.accessory)
        
        let initialSize = CGSize(width: 240, height: 35)
        let screen = NSScreen.screens.first ?? NSScreen.main ?? NSScreen.screens[0]
        
        let x = (screen.frame.width - initialSize.width) / 2
        let y = screen.frame.maxY - initialSize.height
        
        // Create a custom borderless panel that floats on top of other windows and doesn't take focus away automatically
        window = TouchBarWindow(
            contentRect: NSRect(x: x, y: y, width: initialSize.width, height: initialSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Floating level above most menus but below screen saver / overlay
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        
        // Instantiate our SwiftUI view and pass the appState and resizing handler
        let contentView = NotchIslandView(appState: appState) { [weak self] newSize in
            self?.resizeWindow(to: newSize)
        }
        
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        
        startMouseMonitoring()
    }
    
    private var targetSize = CGSize(width: 240, height: 35)
    
    private func startMouseMonitoring() {
        mouseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkMouseHover()
        }
    }
    
    private func checkMouseHover() {
        guard let window = self.window else { return }
        let screen = window.screen ?? NSScreen.screens.first ?? NSScreen.main ?? NSScreen.screens[0]
        let midX = screen.frame.midX
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
        guard let window = self.window else { return }
        self.targetSize = size
        let screen = window.screen ?? NSScreen.screens.first ?? NSScreen.main ?? NSScreen.screens[0]
        let midX = screen.frame.midX
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
