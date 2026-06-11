import Cocoa

// Global strong reference to keep the AppDelegate alive in memory
var appDelegate: AppDelegate?

// Start NSApplication manually
let app = NSApplication.shared
let delegate = AppDelegate()
appDelegate = delegate
app.delegate = delegate
app.run()
