// Renders PanelView offscreen to a PNG so the design can be reviewed without
// running the app. Invoked by Scripts/render_preview.sh.

import AppKit
import SwiftUI

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "panel-preview.png"

MainActor.assumeIsolated {
    let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("chesstime-preview-\(ProcessInfo.processInfo.processIdentifier)")
    defer { try? FileManager.default.removeItem(at: temporary) }

    let store = UsageStore(directory: temporary)
    let settings = AppSettings(defaults: UserDefaults(suiteName: "chesstime.preview")!)
    settings.trackedSites = ["chess.com"]
    // "live" renders the state shown while chess.com is the active tab.
    let wantsLive = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "live"
    let poller = Poller(store: store, settings: settings,
                        activity: wantsLive ? .tracking(domain: "chess.com") : .idleElsewhere)

    // A plausible week so the chart shows real shape rather than empty bars.
    let calendar = Calendar.current
    let minutesByDayOffset: [Int: Double] = [6: 41, 5: 12, 4: 96, 3: 0, 2: 63, 1: 128, 0: 83]
    for (offset, minutes) in minutesByDayOffset {
        let date = calendar.date(byAdding: .day, value: -offset, to: Date())!
        store.add(seconds: minutes * 60, to: "chess.com", on: date)
    }

    // Pass "pinned" as a second argument to preview the pinned state. Set both
    // ways explicitly — the preview suite persists between runs, so a previous
    // pinned render would otherwise leak into the next plain one.
    let wantsPinned = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "pinned"
    settings.panelLevel = wantsPinned ? .top : .normal

    let content = PanelView(
        store: store,
        settings: settings,
        poller: poller,
        onOpenSettings: {},
        onOpenPermissions: {},
        showsWindowChrome: false
    )

    // ImageRenderer, not NSHostingView.cacheDisplay: SwiftUI draws text into
    // layers that cacheDisplay doesn't capture, which yields a blank image.
    // The dark rounded background stands in for the blurred NSVisualEffectView,
    // which has nothing to sample offscreen.
    let size = CGSize(width: 260, height: 168)
    let framed = content
        .frame(width: size.width, height: size.height)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.17))
        )
        .environment(\.colorScheme, .dark)

    let renderer = ImageRenderer(content: framed)
    renderer.scale = 3

    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("could not encode png")
        exit(1)
    }
    try? png.write(to: URL(fileURLWithPath: outputPath))
    print("wrote \(outputPath)")
}
