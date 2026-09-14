import AppKit

// DinoCraft entry point: a native AppKit application driving a Metal renderer.
let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.regular)
application.run()
