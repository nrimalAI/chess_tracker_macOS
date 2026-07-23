import AppKit
import Combine
import ServiceManagement

/// Where the sticky note sits in the window stack.
enum PanelLevel: String, CaseIterable, Identifiable {
    /// Pinned to the desktop, above the wallpaper and icons but behind every
    /// app window — a Stickies note you've clicked away from.
    case desktop
    /// An ordinary window that can be covered and raised.
    case normal
    /// Always visible above everything else.
    case top

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop: return "On the desktop"
        case .normal: return "Normal window"
        case .top: return "Always on top"
        }
    }

    var detail: String {
        switch self {
        case .desktop: return "Stays behind your apps. Clicking it still brings it forward."
        case .normal: return "Comes to the front when clicked, like a Stickies note."
        case .top: return "Floats above everything, including full-screen apps."
        }
    }

    var windowLevel: NSWindow.Level {
        switch self {
        case .desktop: return NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .normal: return .normal
        case .top: return .floating
        }
    }
}

/// User preferences, persisted in `UserDefaults`.
///
/// Hand-rolled rather than `@AppStorage` because that property wrapper only works
/// inside a `View`, and both the panel and the poller need to read this.
@MainActor
final class AppSettings: ObservableObject {

    private enum Key {
        static let trackedSites = "trackedSites"
        static let idleThreshold = "idleThresholdSeconds"
        static let panelLevel = "panelLevel"
        static let panelOpacity = "panelOpacity"
        static let showsWeekChart = "showsWeekChart"
        static let hideDockIcon = "hideDockIcon"
        static let hasOnboarded = "hasCompletedOnboarding"
        static let panelFrame = "panelFrame"
        static let levelBeforePin = "levelBeforePin"
    }

    private let defaults: UserDefaults

    @Published var trackedSites: [String] {
        didSet { defaults.set(trackedSites, forKey: Key.trackedSites) }
    }

    /// Seconds of no keyboard/mouse input before the clock pauses.
    @Published var idleThreshold: TimeInterval {
        didSet { defaults.set(idleThreshold, forKey: Key.idleThreshold) }
    }

    @Published var panelLevel: PanelLevel {
        didSet { defaults.set(panelLevel.rawValue, forKey: Key.panelLevel) }
    }

    @Published var panelOpacity: Double {
        didSet { defaults.set(panelOpacity, forKey: Key.panelOpacity) }
    }

    @Published var showsWeekChart: Bool {
        didSet { defaults.set(showsWeekChart, forKey: Key.showsWeekChart) }
    }

    @Published var hideDockIcon: Bool {
        didSet {
            defaults.set(hideDockIcon, forKey: Key.hideDockIcon)
            NSApp.setActivationPolicy(hideDockIcon ? .accessory : .regular)
        }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasOnboarded) }
    }

    /// Not `@Published`: the window writes this on every drag, and republishing
    /// would redraw the SwiftUI content for each mouse-move event.
    var panelFrame: NSRect? {
        get {
            guard let string = defaults.string(forKey: Key.panelFrame) else { return nil }
            let rect = NSRectFromString(string)
            return rect.width > 0 && rect.height > 0 ? rect : nil
        }
        set {
            guard let newValue else { return }
            defaults.set(NSStringFromRect(newValue), forKey: Key.panelFrame)
        }
    }

    /// Backed by the system rather than our own defaults, so it stays truthful if
    /// the user disables the login item in System Settings.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("ChessTime: login item change failed: \(error.localizedDescription)")
            }
            objectWillChange.send()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.trackedSites: ["chess.com"],
            // Five minutes, not two: thinking through a chess position involves
            // no keyboard or mouse input at all, and a two-minute cutoff quietly
            // discarded real usage.
            Key.idleThreshold: 300.0,
            Key.panelLevel: PanelLevel.normal.rawValue,
            Key.panelOpacity: 0.92,
            Key.showsWeekChart: true,
            Key.hideDockIcon: false,
            Key.hasOnboarded: false,
        ])

        trackedSites = defaults.stringArray(forKey: Key.trackedSites) ?? ["chess.com"]
        idleThreshold = defaults.double(forKey: Key.idleThreshold)
        panelLevel = PanelLevel(rawValue: defaults.string(forKey: Key.panelLevel) ?? "")
            ?? .normal
        panelOpacity = defaults.double(forKey: Key.panelOpacity)
        showsWeekChart = defaults.bool(forKey: Key.showsWeekChart)
        hideDockIcon = defaults.bool(forKey: Key.hideDockIcon)
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasOnboarded)
    }

    // MARK: - Pinning

    /// Pinned means "always on top" — the note stays above other apps while you
    /// work in them.
    var isPinned: Bool { panelLevel == .top }

    /// Unpinning returns the note to wherever it was before, so someone who
    /// keeps it on the desktop doesn't get silently switched to a normal window.
    func togglePin() {
        if isPinned {
            let previous = PanelLevel(rawValue: defaults.string(forKey: Key.levelBeforePin) ?? "")
            panelLevel = (previous == .top ? nil : previous) ?? .normal
        } else {
            defaults.set(panelLevel.rawValue, forKey: Key.levelBeforePin)
            panelLevel = .top
        }
    }

    // MARK: - Site list

    /// Returns false when the input isn't a usable domain or is already tracked.
    @discardableResult
    func addSite(_ input: String) -> Bool {
        guard let domain = HostMatcher.canonicalize(input: input),
              !trackedSites.contains(domain)
        else { return false }
        trackedSites.append(domain)
        return true
    }

    func removeSites(_ domains: Set<String>) {
        trackedSites.removeAll { domains.contains($0) }
    }
}
