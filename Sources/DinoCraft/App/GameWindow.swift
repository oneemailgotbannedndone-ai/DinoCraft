import AppKit
import MetalKit

/// Borderless-feeling game window: transparent title bar, full-size content,
/// native full screen support.
final class GameWindow: NSWindow {
    let gameView: GameView

    init(size: NSSize) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1600, height: 1000)
        let w = min(size.width, screen.width * 0.95), h = min(size.height, screen.height * 0.95)
        let frame = NSRect(x: screen.midX - w / 2, y: screen.midY - h / 2, width: w, height: h)
        gameView = GameView(frame: NSRect(origin: .zero, size: frame.size), device: nil)
        super.init(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = "DinoCraft"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        backgroundColor = .black
        collectionBehavior = [.fullScreenPrimary, .managed]
        minSize = NSSize(width: 960, height: 540)
        contentView = gameView
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        initialFirstResponder = gameView
        setFrameAutosaveName("DinoCraftMainWindow")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Metal-backed view that funnels all keyboard and mouse events to `Input`.
final class GameView: MTKView {
    weak var input: Input?
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .inVisibleRect, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func keyDown(with event: NSEvent) { input?.handleKeyDown(event) }
    override func keyUp(with event: NSEvent) { input?.handleKeyUp(event) }
    override func flagsChanged(with event: NSEvent) { input?.handleFlagsChanged(event) }

    override func mouseDown(with event: NSEvent) { input?.handleMouseDown(event, button: 0, view: self) }
    override func mouseUp(with event: NSEvent) { input?.handleMouseUp(event, button: 0, view: self) }
    override func rightMouseDown(with event: NSEvent) { input?.handleMouseDown(event, button: 1, view: self) }
    override func rightMouseUp(with event: NSEvent) { input?.handleMouseUp(event, button: 1, view: self) }
    override func otherMouseDown(with event: NSEvent) { input?.handleMouseDown(event, button: Int(event.buttonNumber), view: self) }
    override func otherMouseUp(with event: NSEvent) { input?.handleMouseUp(event, button: Int(event.buttonNumber), view: self) }

    override func mouseMoved(with event: NSEvent) { input?.handleMouseMoved(event, view: self) }
    override func mouseDragged(with event: NSEvent) { input?.handleMouseMoved(event, view: self) }
    override func rightMouseDragged(with event: NSEvent) { input?.handleMouseMoved(event, view: self) }
    override func otherMouseDragged(with event: NSEvent) { input?.handleMouseMoved(event, view: self) }
    override func scrollWheel(with event: NSEvent) { input?.handleScroll(event) }

    // Swallow the system beep for unhandled keys.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) { return super.performKeyEquivalent(with: event) }
        return false
    }
}
