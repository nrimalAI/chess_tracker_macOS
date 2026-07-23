import AppKit
import ApplicationServices

/// A browser ChessTime knows how to ask for its active tab.
struct Browser: Identifiable, Hashable {
    enum Family {
        /// `URL of current tab of front window`
        case safari
        /// `URL of active tab of front window` — the Chrome scripting dictionary,
        /// which every Chromium-based browser on macOS implements verbatim.
        case chromium
    }

    let bundleID: String
    let name: String
    let family: Family

    var id: String { bundleID }

    /// Every browser we can read. Chromium forks cost one line each because they
    /// share Chrome's dictionary.
    static let known: [Browser] = [
        Browser(bundleID: "com.apple.Safari", name: "Safari", family: .safari),
        Browser(bundleID: "com.apple.SafariTechnologyPreview", name: "Safari Technology Preview", family: .safari),
        Browser(bundleID: "com.google.Chrome", name: "Google Chrome", family: .chromium),
        Browser(bundleID: "com.google.Chrome.beta", name: "Google Chrome Beta", family: .chromium),
        Browser(bundleID: "com.google.Chrome.canary", name: "Google Chrome Canary", family: .chromium),
        Browser(bundleID: "com.brave.Browser", name: "Brave", family: .chromium),
        Browser(bundleID: "com.brave.Browser.beta", name: "Brave Beta", family: .chromium),
        Browser(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge", family: .chromium),
        Browser(bundleID: "com.microsoft.edgemac.Beta", name: "Microsoft Edge Beta", family: .chromium),
        Browser(bundleID: "company.thebrowser.Browser", name: "Arc", family: .chromium),
        Browser(bundleID: "com.vivaldi.Vivaldi", name: "Vivaldi", family: .chromium),
        Browser(bundleID: "com.operasoftware.Opera", name: "Opera", family: .chromium),
        Browser(bundleID: "com.operasoftware.OperaGX", name: "Opera GX", family: .chromium),
    ]

    static func known(bundleID: String) -> Browser? {
        known.first { $0.bundleID == bundleID }
    }

    /// The subset actually present on this Mac, for onboarding and settings.
    static var installed: [Browser] {
        known.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil
        }
    }

    var script: String {
        switch family {
        case .safari:
            return "tell application id \"\(bundleID)\" to return URL of current tab of front window"
        case .chromium:
            return "tell application id \"\(bundleID)\" to return URL of active tab of front window"
        }
    }
}

enum BrowserError: Error {
    /// The user hasn't granted (or has revoked) Automation access for this browser.
    case notPermitted
    /// Browser is running but has no window, or the tab has no URL yet.
    case noActiveTab
    case scriptFailed(code: Int, message: String)
}

/// Reads the frontmost tab's URL out of a browser over Apple Events.
///
/// `NSAppleScript` wants to be used from one thread at a time, and a wedged
/// browser can make an event block for seconds, so every call runs on a single
/// dedicated serial queue and reports back on the main queue. The UI never waits.
enum BrowserBridge {

    private static let queue = DispatchQueue(label: "com.chesstime.ChessTime.applescript")
    /// Compiling is the expensive part; a poll every few seconds would otherwise
    /// recompile the same one-liner forever.
    private static var compiled: [String: NSAppleScript] = [:]

    static func activeTabURL(for browser: Browser,
                             completion: @escaping (Result<String, BrowserError>) -> Void) {
        queue.async {
            let result = activeTabURLSync(for: browser)
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Must be called on `queue`.
    private static func activeTabURLSync(for browser: Browser) -> Result<String, BrowserError> {
        let script: NSAppleScript
        if let cached = compiled[browser.bundleID] {
            script = cached
        } else if let fresh = NSAppleScript(source: browser.script) {
            compiled[browser.bundleID] = fresh
            script = fresh
        } else {
            return .failure(.scriptFailed(code: 0, message: "Could not compile the lookup script."))
        }

        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)

        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            switch code {
            case -1743, -10004:
                return .failure(.notPermitted)
            case -1728, -1719, -600, -609, -1712:
                // No front window, empty window list, browser quit mid-poll, or timeout.
                return .failure(.noActiveTab)
            default:
                return .failure(.scriptFailed(code: code, message: message))
            }
        }

        guard let urlString = output.stringValue, !urlString.isEmpty else {
            return .failure(.noActiveTab)
        }
        return .success(urlString)
    }
}

/// Whether the user has allowed us to send Apple Events to a given browser.
enum AutomationPermission {
    case granted
    case denied
    /// Never asked — macOS will show the consent dialog on first real attempt.
    case notDetermined
    /// Browser isn't running, so macOS can't tell us anything yet.
    case unknown

    var isBlocking: Bool { self == .denied }
}

extension BrowserBridge {

    /// Queries macOS for the current Automation state. Pass `askIfNeeded: true`
    /// only in response to a user action — it can put up the consent dialog.
    static func permission(for browser: Browser, askIfNeeded: Bool = false) -> AutomationPermission {
        guard NSRunningApplication
            .runningApplications(withBundleIdentifier: browser.bundleID).first != nil
        else { return .unknown }

        let target = NSAppleEventDescriptor(bundleIdentifier: browser.bundleID)
        return withExtendedLifetime(target) {
            guard let desc = target.aeDesc else { return AutomationPermission.unknown }
            let status = AEDeterminePermissionToAutomateTarget(
                desc, typeWildCard, typeWildCard, askIfNeeded
            )
            switch status {
            case noErr: return .granted
            case OSStatus(errAEEventNotPermitted): return .denied
            case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
            default: return .unknown
            }
        }
    }

    /// Opens the exact System Settings pane where Automation is granted.
    static func openAutomationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
    }
}
