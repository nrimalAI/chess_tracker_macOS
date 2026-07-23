import AppKit
import SwiftUI

/// The sticky note itself: a borderless, translucent window.
///
/// Deliberately an `NSWindow` and not an `NSPanel`. Panels carry auxiliary-window
/// semantics — they are meant to float beside a main window rather than be one —
/// and that fought click-to-activate at every turn. A plain window gets ordinary
/// activation behaviour for free, with nothing to work around.
final class DesktopPanel: NSWindow {

    private let settings: AppSettings
    private var levelObserver: AnyObject?

    static let defaultSize = NSSize(width: 260, height: 168)
    static let minSize = NSSize(width: 200, height: 108)
    static let maxSize = NSSize(width: 560, height: 460)

    init(settings: AppSettings, content: some View) {
        self.settings = settings

        super.init(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        contentMinSize = Self.minSize
        contentMaxSize = Self.maxSize

        // Present on every Space and unmoved by Mission Control, so it behaves
        // like part of the desktop instead of a window that follows you around.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: AnyView(content))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: blur.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])

        contentView = blur
        applyLevel()
        applyOpacity()
        restoreFrame()
    }

    // Borderless windows refuse key and main status unless asked. Without both,
    // AppKit treats the note as auxiliary and won't activate the app on click.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - Appearance

    /// Forces the note above everything regardless of the user's preference,
    /// used during onboarding. A note at desktop level is invisible whenever a
    /// window covers the desktop, so on first launch it has to announce itself
    /// or people reasonably conclude the app didn't start.
    func floatAboveEverything() {
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        orderFrontRegardless()
    }

    /// Every click on the note surfaces it, wherever it lands.
    ///
    /// Doing this in a subview's `mouseDown` doesn't work: `NSHostingView`
    /// swallows the event before it reaches the drag surface underneath, so the
    /// click was being handled without ever raising the window. Intercepting in
    /// `sendEvent` catches it before view dispatch.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            bringToFront()
        default:
            break
        }
        super.sendEvent(event)
    }

    /// Raises the note and activates the app, so a click surfaces it from behind
    /// whatever was covering it.
    ///
    /// In `.desktop` mode the level itself keeps the window below every app, and
    /// no amount of ordering changes that — so a click there temporarily promotes
    /// it to a normal window. It drops back the next time the app deactivates.
    func bringToFront() {
        if settings.panelLevel == .desktop {
            level = .normal
        }
        // .activateAllWindows rather than the plain activate(): a background app
        // asking to come forward is subject to macOS's cooperative activation
        // rules, and the bare call gets quietly ignored.
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }

    func applyLevel() {
        level = settings.panelLevel.windowLevel
        // Only the always-on-top mode should ride above full-screen apps.
        collectionBehavior = settings.panelLevel == .top
            ? [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            : [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    func applyOpacity() {
        alphaValue = max(0.35, min(1.0, settings.panelOpacity))
    }

    // MARK: - Frame persistence

    private func restoreFrame() {
        guard let saved = settings.panelFrame, isOnAnyScreen(saved) else {
            positionInTopRight()
            return
        }
        setFrame(saved, display: false)
    }

    /// A note restored onto a monitor that's since been unplugged would be
    /// invisible and unrecoverable, so fall back to a fresh position.
    private func isOnAnyScreen(_ rect: NSRect) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.intersects(rect) }
    }

    private func positionInTopRight() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.maxX - Self.defaultSize.width - 28,
            y: visible.maxY - Self.defaultSize.height - 28
        )
        setFrame(NSRect(origin: origin, size: Self.defaultSize), display: false)
    }

    func persistFrame() {
        settings.panelFrame = frame
    }
}

/// Lets the user drag the note by any empty part of its body.
///
/// `isMovableByWindowBackground` alone is unreliable once SwiftUI content is in
/// the hierarchy, because `NSHostingView` swallows the mouse-down. This sits
/// behind the content and starts a real window drag.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            // Raise before dragging: a click on the note should surface it even
            // when the drag turns out to be a plain click.
            (window as? DesktopPanel)?.bringToFront()
            window?.performDrag(with: event)
        }
        // Never take focus; this is purely a drag surface.
        override var acceptsFirstResponder: Bool { false }
        // Deliberately NOT overriding acceptsFirstMouse to true. Doing so tells
        // AppKit to route the click straight to this view when the app is
        // inactive, bypassing the standard click-to-activate path. The cost is
        // that the click which brings the note forward doesn't also drag it.
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}

/// A resize grip for the bottom-right corner. Borderless windows don't get
/// reliable edge-drag resizing, so the note grows from an explicit handle.
struct WindowResizeCorner: NSViewRepresentable {
    final class GripView: NSView {
        private var startFrame: NSRect = .zero
        private var startMouse: NSPoint = .zero

        override func resetCursorRects() {
            // No dedicated diagonal-resize cursor is public; crosshair reads as
            // "this handle does something" without misleading.
            addCursorRect(bounds, cursor: .crosshair)
        }

        override func mouseDown(with event: NSEvent) {
            (window as? DesktopPanel)?.bringToFront()
            startFrame = window?.frame ?? .zero
            startMouse = NSEvent.mouseLocation
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let now = NSEvent.mouseLocation
            let dx = now.x - startMouse.x
            let dy = now.y - startMouse.y

            let min = DesktopPanel.minSize
            let max = DesktopPanel.maxSize
            let width = Swift.min(Swift.max(startFrame.width + dx, min.width), max.width)
            let height = Swift.min(Swift.max(startFrame.height - dy, min.height), max.height)

            // macOS origins are bottom-left, so growing downward means moving the
            // origin down by however much the height grew, pinning the top edge.
            let origin = NSPoint(x: startFrame.origin.x,
                                 y: startFrame.maxY - height)
            window.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)),
                            display: true)
        }

        override func mouseUp(with event: NSEvent) {
            (window as? DesktopPanel)?.persistFrame()
        }
    }

    func makeNSView(context: Context) -> GripView { GripView() }
    func updateNSView(_ nsView: GripView, context: Context) {}
}
