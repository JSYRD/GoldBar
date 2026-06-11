import Cocoa

// Entry point for GoldBar — a menu-bar-only macOS app
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // Hide from Dock, show only in menu bar
app.run()
