import AppKit
import CoreGraphics

/// Answers "is the user actually here?" so time doesn't accrue while you're away.
final class IdleMonitor {

    /// `kCGAnyInputEventType` can't be expressed as a `CGEventType` in Swift, so
    /// we ask for each interesting event type and take the most recent one.
    private static let inputTypes: [CGEventType] = [
        .keyDown, .flagsChanged,
        .mouseMoved, .scrollWheel,
        .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .leftMouseDragged, .rightMouseDragged,
    ]

    /// Seconds since the user last touched the keyboard, mouse or trackpad.
    var secondsSinceLastInput: TimeInterval {
        Self.inputTypes
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }

    /// True while the screen is locked, the screen saver is up, or the display slept.
    private(set) var isScreenObscured = false

    private var tokens: [NSObjectProtocol] = []

    init() {
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter

        func observe(_ center: NotificationCenter, _ name: Notification.Name, obscured: Bool) {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.isScreenObscured = obscured
            })
        }
        func observeDistributed(_ name: String, obscured: Bool) {
            tokens.append(distributed.addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in
                self?.isScreenObscured = obscured
            })
        }

        observeDistributed("com.apple.screenIsLocked", obscured: true)
        observeDistributed("com.apple.screenIsUnlocked", obscured: false)
        observeDistributed("com.apple.screensaver.didstart", obscured: true)
        observeDistributed("com.apple.screensaver.didstop", obscured: false)

        observe(workspace, NSWorkspace.screensDidSleepNotification, obscured: true)
        observe(workspace, NSWorkspace.screensDidWakeNotification, obscured: false)
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification, obscured: true)
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification, obscured: false)
    }

    deinit {
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        for token in tokens {
            distributed.removeObserver(token)
            workspace.removeObserver(token)
        }
    }
}
