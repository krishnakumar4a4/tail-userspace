import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// .accessory hides app from the macOS Dock and App Switcher (menu bar only)
app.setActivationPolicy(.accessory)
app.run()
