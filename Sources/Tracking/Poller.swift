import AppKit
import Combine

/// Samples the frontmost app and its active tab on a fixed interval, crediting
/// the elapsed time to whichever tracked site you were looking at.
///
/// Sampling means a focus change can be missed by up to one interval, which nets
/// out to a few seconds a day — far below the resolution anyone cares about, and
/// much cheaper than watching every window and tab event in every browser.
@MainActor
final class Poller: ObservableObject {

    static let interval: TimeInterval = 5

    /// What the panel is currently showing as "live".
    enum Activity: Equatable {
        /// Actively on a tracked site.
        case tracking(domain: String)
        /// You're at the Mac, just not on a tracked site.
        case idleElsewhere
        /// Away: locked screen, screen saver, or no input past the threshold.
        case away
    }

    @Published private(set) var activity: Activity = .idleElsewhere
    /// Browsers that have refused us Automation access, so the panel can say so
    /// instead of silently recording zero.
    @Published private(set) var blockedBrowsers: [Browser] = []

    private let store: UsageStore
    private let settings: AppSettings
    private let idle = IdleMonitor()

    private var timer: Timer?
    private var lastSample: Date?
    private var deniedBundleIDs: Set<String> = []
    /// Guards against a slow browser letting two lookups overlap.
    private var lookupInFlight = false

    /// `activity` is injectable so previews and tests can render the live state
    /// without a browser, a permission grant, or a five-second wait.
    init(store: UsageStore, settings: AppSettings, activity: Activity = .idleElsewhere) {
        self.store = store
        self.settings = settings
        self.activity = activity
    }

    func start() {
        guard timer == nil else { return }
        lastSample = Date()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // .common keeps the clock running while a menu is open or the panel is
        // being dragged, both of which spin the run loop in a modal mode.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Called when the Mac wakes: the elapsed-time clamp already prevents crediting
    /// a night of sleep, but resetting avoids a bogus partial credit too.
    func resetClock() {
        lastSample = Date()
    }

    private func tick() {
        let now = Date()
        // Clamp so a suspended timer (sleep, heavy load) can never dump a huge
        // block of time onto whatever happens to be frontmost on wake.
        let elapsed = min(now.timeIntervalSince(lastSample ?? now), Self.interval * 2)
        lastSample = now
        guard elapsed > 0 else { return }

        guard !idle.isScreenObscured,
              idle.secondsSinceLastInput < settings.idleThreshold
        else {
            activity = .away
            return
        }

        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              let browser = Browser.known(bundleID: bundleID)
        else {
            activity = .idleElsewhere
            return
        }

        guard !lookupInFlight else { return }
        lookupInFlight = true

        BrowserBridge.activeTabURL(for: browser) { [weak self] result in
            guard let self else { return }
            self.lookupInFlight = false

            switch result {
            case .success(let urlString):
                self.clearDenied(browser)
                if let domain = HostMatcher.trackedDomain(for: urlString,
                                                          in: self.settings.trackedSites) {
                    self.store.add(seconds: elapsed, to: domain)
                    self.activity = .tracking(domain: domain)
                } else {
                    self.activity = .idleElsewhere
                }

            case .failure(.notPermitted):
                self.markDenied(browser)
                self.activity = .idleElsewhere

            case .failure:
                self.clearDenied(browser)
                self.activity = .idleElsewhere
            }
        }
    }

    // MARK: - Permission bookkeeping

    private func markDenied(_ browser: Browser) {
        guard deniedBundleIDs.insert(browser.bundleID).inserted else { return }
        refreshBlocked()
    }

    private func clearDenied(_ browser: Browser) {
        guard deniedBundleIDs.remove(browser.bundleID) != nil else { return }
        refreshBlocked()
    }

    /// Re-checks every installed browser, e.g. after the user returns from
    /// System Settings, so a granted permission clears the warning immediately.
    func refreshPermissions() {
        for browser in Browser.installed {
            switch BrowserBridge.permission(for: browser) {
            case .denied: deniedBundleIDs.insert(browser.bundleID)
            case .granted: deniedBundleIDs.remove(browser.bundleID)
            case .notDetermined, .unknown: break
            }
        }
        refreshBlocked()
    }

    private func refreshBlocked() {
        blockedBrowsers = Browser.known.filter { deniedBundleIDs.contains($0.bundleID) }
    }
}
