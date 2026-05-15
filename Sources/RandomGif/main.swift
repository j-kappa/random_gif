import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
// AppDelegate is an NSObject subclass; delegate callbacks always run on main thread
let delegate = AppDelegate()
app.delegate = delegate
app.run()

