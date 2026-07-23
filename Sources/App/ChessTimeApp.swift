import SwiftUI
import AppKit
import Combine

/// Shared objects. A singleton because both the AppKit panel and the SwiftUI
/// Settings scene need the same instances, and `App` can't hand state to a
/// window it doesn't own.
@MainActor
final class AppEnvironment: ObservableObject {
    static let shared = AppEnvironment()

    let settings: AppSettings
    let store: UsageStore
    let poller: Poller

    private init() {
        let settings = AppSettings()
        let store = UsageStore()
        self.settings = settings
        self.store = store
        self.poller = Poller(store: store, settings: settings)
    }
}

@main
struct ChessTimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Gives us the standard ⌘, Settings window for free.
        Settings {
            SettingsView(
                settings: AppEnvironment.shared.settings,
                store: AppEnvironment.shared.store,
                poller: AppEnvironment.shared.poller
            )
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private var panel: DesktopPanel?
    private var onboardingWindow: NSWindow?
    private var observers: [AnyCancellable] = []

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment.shared

        NSApp.setActivationPolicy(environment.settings.hideDockIcon ? .accessory : .regular)

        showPanel()
        environment.poller.refreshPermissions()
        environment.poller.start()

        observeSettings()
        observeSleep()

        if !environment.settings.hasCompletedOnboarding {
            showOnboarding()
        }
    }

    // MARK: - Panel

    @MainActor
    private func showPanel() {
        let environment = AppEnvironment.shared
        let content = PanelView(
            store: environment.store,
            settings: environment.settings,
            poller: environment.poller,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onOpenPermissions: { BrowserBridge.openAutomationSettings() }
        )

        let panel = DesktopPanel(settings: environment.settings, content: content)
        panel.delegate = self
        panel.orderFront(nil)
        self.panel = panel
    }

    @MainActor
    private func openSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // The selector moved in macOS 14; try the current one first.
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    // MARK: - Onboarding

    @MainActor
    private func showOnboarding() {
        let environment = AppEnvironment.shared
        // Keep the note on top for as long as onboarding is up, then drop it to
        // wherever the user actually wants it.
        panel?.floatAboveEverything()

        let view = OnboardingView(settings: environment.settings) { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.panel?.applyLevel()
            AppEnvironment.shared.poller.refreshPermissions()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.title = "Welcome to ChessTime"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    // MARK: - Reacting to settings

    @MainActor
    private func observeSettings() {
        let settings = AppEnvironment.shared.settings
        settings.$panelLevel
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.panel?.applyLevel() }
            .store(in: &observers)
        settings.$panelOpacity
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.panel?.applyOpacity() }
            .store(in: &observers)
    }

    @MainActor
    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification,
                           object: nil, queue: .main) { _ in
            Task { @MainActor in AppEnvironment.shared.store.saveIfNeeded() }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification,
                           object: nil, queue: .main) { _ in
            Task { @MainActor in
                AppEnvironment.shared.poller.resetClock()
                AppEnvironment.shared.poller.refreshPermissions()
            }
        }
    }

    /// Undoes the temporary promotion `bringToFront()` applies in `.desktop`
    /// mode, so the note settles back onto the desktop once you move on.
    @MainActor
    func applicationDidResignActive(_ notification: Notification) {
        panel?.applyLevel()
    }

    // MARK: - Window delegate

    func windowDidMove(_ notification: Notification) {
        (notification.object as? DesktopPanel)?.persistFrame()
    }

    func windowDidResize(_ notification: Notification) {
        (notification.object as? DesktopPanel)?.persistFrame()
    }

    // MARK: - Lifecycle

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        AppEnvironment.shared.poller.stop()
        AppEnvironment.shared.store.save()
        panel?.persistFrame()
    }

    /// Clicking the Dock icon (or relaunching) surfaces the note. It notably does
    /// not open Settings — people click the icon to find the note, not to
    /// configure it.
    @MainActor
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if panel == nil { showPanel() }
        panel?.bringToFront()
        return true
    }
}
