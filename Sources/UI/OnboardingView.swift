import SwiftUI

/// First run: explain what the app needs and why, then trigger the Automation
/// prompts deliberately.
///
/// Without this the user meets a bare "ChessTime wants to control Safari" dialog
/// with no context, which is the single most common reason people deny access and
/// then report the app as broken.
struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    var onFinish: () -> Void

    @State private var browsers = Browser.installed
    @State private var requesting: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Track your time on chess.com")
                    .font(.title2.weight(.semibold))
                Text("ChessTime keeps a small note on your desktop showing how long you've spent on the sites you choose.")
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("It reads only the address of your active tab — never the page itself.",
                          systemImage: "eye.slash")
                    Label("Everything stays in one file on this Mac. No account, no network.",
                          systemImage: "lock")
                    Label("The clock pauses when you're away or the screen locks.",
                          systemImage: "pause.circle")
                }
                .font(.callout)
                .padding(6)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Allow access to your browsers")
                    .font(.headline)
                Text("macOS will ask once per browser. ChessTime can't measure anything until you allow it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ForEach(browsers) { browser in
                    HStack {
                        Text(browser.name)
                        Spacer()
                        if requesting == browser.bundleID {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Allow…") { request(browser) }
                        }
                    }
                }

                if browsers.isEmpty {
                    Text("No supported browsers found. ChessTime works with Safari, Chrome, Brave, Edge, Arc, Vivaldi and Opera.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("The note is in the top-right corner. Drag it anywhere.")
                    .font(.callout)
                Text("It sits on the desktop behind your windows by default. Right-click it to float it on top instead, or to open Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Firefox doesn't let any app read its tabs, so it can't be tracked.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Spacer()
                Button("Start Tracking") {
                    settings.hasCompletedOnboarding = true
                    onFinish()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    /// Sends a real lookup, which is what actually surfaces the consent dialog.
    /// The browser has to be running for macOS to ask, so launch it if needed.
    private func request(_ browser: Browser) {
        requesting = browser.bundleID

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) else {
            requesting = nil
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                BrowserBridge.activeTabURL(for: browser) { _ in
                    requesting = nil
                }
            }
        }
    }
}
