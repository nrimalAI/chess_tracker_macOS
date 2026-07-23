import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: UsageStore
    @ObservedObject var poller: Poller

    var body: some View {
        TabView {
            GeneralSettings(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            SitesSettings(settings: settings, store: store)
                .tabItem { Label("Sites", systemImage: "globe") }
            PermissionsSettings(poller: poller)
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            DataSettings(store: store, settings: settings)
                .tabItem { Label("Data", systemImage: "tray.full") }
        }
        .frame(width: 460)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var settings: AppSettings
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Picker("Position:", selection: $settings.panelLevel) {
                ForEach(PanelLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            Text(settings.panelLevel.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(value: $settings.panelOpacity, in: 0.35...1.0) {
                Text("Opacity:")
            } minimumValueLabel: {
                Text("Faint").font(.caption)
            } maximumValueLabel: {
                Text("Solid").font(.caption)
            }

            Toggle("Show the week chart", isOn: $settings.showsWeekChart)

            Divider()

            Picker("Pause after:", selection: $settings.idleThreshold) {
                Text("30 seconds").tag(30.0)
                Text("1 minute").tag(60.0)
                Text("2 minutes").tag(120.0)
                Text("5 minutes").tag(300.0)
                Text("10 minutes").tag(600.0)
            }
            Text("Time stops counting when you stop touching the keyboard and mouse, or when the screen locks.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    settings.launchAtLogin = newValue
                }
            Toggle("Hide the Dock icon", isOn: $settings.hideDockIcon)
            Text("With the Dock icon hidden, reopen Settings by launching ChessTime again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = settings.launchAtLogin }
    }
}

// MARK: - Sites

private struct SitesSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: UsageStore

    @State private var newSite = ""
    @State private var selection: Set<String> = []
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ChessTime counts time on these domains and their subdomains.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List(selection: $selection) {
                ForEach(settings.trackedSites, id: \.self) { site in
                    HStack {
                        Text(site)
                        Spacer()
                        Text(DurationFormat.short(store.seconds(for: site)))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .tag(site)
                }
            }
            .frame(minHeight: 160)

            HStack {
                TextField("Add a domain, e.g. lichess.org", text: $newSite)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(newSite.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Remove") {
                    settings.removeSites(selection)
                    selection = []
                }
                .disabled(selection.isEmpty || settings.trackedSites.count <= selection.count)
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
    }

    private func add() {
        guard settings.addSite(newSite) else {
            error = HostMatcher.canonicalize(input: newSite) == nil
                ? "That doesn't look like a domain."
                : "You're already tracking that."
            return
        }
        newSite = ""
        error = nil
    }
}

// MARK: - Permissions

private struct PermissionsSettings: View {
    @ObservedObject var poller: Poller
    @State private var states: [(browser: Browser, permission: AutomationPermission)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("To measure time on a site, ChessTime asks your browser for the address of the active tab. That needs Automation permission, granted once per browser.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List(states, id: \.browser.id) { entry in
                HStack {
                    Text(entry.browser.name)
                    Spacer()
                    PermissionBadge(permission: entry.permission)
                }
            }
            .frame(minHeight: 150)

            HStack {
                Button("Open System Settings") { BrowserBridge.openAutomationSettings() }
                Button("Refresh") { refresh() }
                Spacer()
            }

            Text("“Not running” just means the browser is closed — ChessTime will ask the first time you use it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .onAppear(perform: refresh)
        // Catches the common flow of granting access in System Settings and
        // switching straight back to this window.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        states = Browser.installed.map { ($0, BrowserBridge.permission(for: $0)) }
        poller.refreshPermissions()
    }
}

private struct PermissionBadge: View {
    let permission: AutomationPermission

    var body: some View {
        Text(label)
            .font(.caption)
            .foregroundStyle(color)
    }

    private var label: String {
        switch permission {
        case .granted: return "Allowed"
        case .denied: return "Blocked"
        case .notDetermined: return "Not asked yet"
        case .unknown: return "Not running"
        }
    }

    private var color: Color {
        switch permission {
        case .granted: return .green
        case .denied: return .orange
        case .notDetermined, .unknown: return .secondary
        }
    }
}

// MARK: - Data

private struct DataSettings: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings

    @State private var confirmingErase = false

    private var history: [(day: String, seconds: Double)] {
        store.allTotals(domains: settings.trackedSites)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Everything ChessTime records lives in a single file on this Mac. Nothing is uploaded anywhere.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List(history, id: \.day) { entry in
                HStack {
                    Text(entry.day)
                    Spacer()
                    Text(DurationFormat.short(entry.seconds))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            .frame(minHeight: 150)

            HStack {
                Button("Export CSV…", action: exportCSV)
                Spacer()
                Button("Erase All History…", role: .destructive) { confirmingErase = true }
            }
        }
        .padding()
        .confirmationDialog("Erase all recorded time?", isPresented: $confirmingErase) {
            Button("Erase", role: .destructive) { store.eraseAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "chesstime-history.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? store.exportCSV().data(using: .utf8)?.write(to: url, options: .atomic)
    }
}
