import SwiftUI

/// The contents of the sticky note: today's total, a week of history, and a
/// quiet indicator of whether the clock is currently running.
struct PanelView: View {

    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var poller: Poller

    var onOpenSettings: () -> Void
    var onOpenPermissions: () -> Void

    /// The drag surface and resize grip are `NSViewRepresentable`s, which
    /// `ImageRenderer` can't draw. Off for offscreen previews.
    var showsWindowChrome = true

    private var todaySeconds: Double {
        store.seconds(domains: settings.trackedSites)
    }

    private var week: [(date: Date, seconds: Double)] {
        store.recentDays(7, domains: settings.trackedSites)
    }

    /// True only while the clock is genuinely running.
    private var isLive: Bool {
        if case .tracking = poller.activity { return true }
        return false
    }

    /// The site being counted right now, which may not be the only tracked one.
    private var liveDomain: String? {
        if case .tracking(let domain) = poller.activity { return domain }
        return nil
    }

    private var headline: String {
        if settings.trackedSites.count == 1 {
            return settings.trackedSites[0]
        }
        return "\(settings.trackedSites.count) sites"
    }

    var body: some View {
        ZStack {
            // Behind everything, so dragging works from any non-interactive spot.
            if showsWindowChrome { WindowDragArea() }

            VStack(alignment: .leading, spacing: 8) {
                header
                total
                if settings.showsWeekChart { WeekChart(days: week) }
                if !poller.blockedBrowsers.isEmpty { permissionWarning }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // A glow around the whole note, so "it's counting" is legible from
            // across the room rather than only if you look at the dot.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.green.opacity(isLive ? 0.7 : 0), lineWidth: 1.5)
                .shadow(color: .green.opacity(isLive ? 0.5 : 0), radius: 5)
                .allowsHitTesting(false)

            if showsWindowChrome {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        WindowResizeCorner()
                            .frame(width: 16, height: 16)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isLive)
        .contextMenu { menu }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 6) {
            StatusDot(isLive: isLive)
            Text(liveDomain ?? headline)
                .font(.system(size: 11, weight: isLive ? .semibold : .medium))
                .foregroundStyle(isLive ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel("Tracking \(headline). \(poller.activity.accessibilityDescription)")
            Spacer(minLength: 0)
            PinButton(isPinned: settings.isPinned) {
                withAnimation(.easeOut(duration: 0.15)) { settings.togglePin() }
            }
        }
    }

    private var total: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(DurationFormat.short(todaySeconds))
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            // The number is always today's total; the label doubles as the
            // plainest possible statement of whether the clock is moving.
            Text(isLive ? "counting now" : "today")
                .font(.system(size: 10, weight: isLive ? .semibold : .medium))
                .foregroundStyle(isLive ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary))
                .textCase(.uppercase)
                .tracking(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(DurationFormat.spoken(todaySeconds)) today")
    }

    private var permissionWarning: some View {
        Button(action: onOpenPermissions) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(poller.blockedBrowsers.count == 1
                     ? "\(poller.blockedBrowsers[0].name) access blocked"
                     : "\(poller.blockedBrowsers.count) browsers blocked")
                    .lineLimit(1)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.orange)
        }
        .buttonStyle(.plain)
        .help("ChessTime can't read this browser's tabs. Click to fix in System Settings.")
    }

    @ViewBuilder
    private var menu: some View {
        Button("Settings…") { onOpenSettings() }
        Divider()
        Picker("Position", selection: $settings.panelLevel) {
            ForEach(PanelLevel.allCases) { level in
                Text(level.title).tag(level)
            }
        }
        Toggle("Show week chart", isOn: $settings.showsWeekChart)
        Divider()
        Button("Quit ChessTime") { NSApp.terminate(nil) }
    }
}

/// Keeps the note above other apps so you can watch the clock while working
/// somewhere else.
///
/// Dim until you hover, so it doesn't compete with the number — but never fully
/// hidden, or nobody would discover it. Solid and tinted once pinned, since that
/// state needs to be obvious at a glance.
private struct PinButton: View {
    let isPinned: Bool
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
                .opacity(isPinned || isHovering ? 1 : 0.4)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isPinned
              ? "Unpin — let other windows cover the note"
              : "Pin — keep the note above other apps")
        .accessibilityLabel(isPinned ? "Unpin note" : "Pin note above other apps")
        .accessibilityAddTraits(isPinned ? [.isSelected] : [])
    }
}

/// A recording light: solid green with an expanding halo while the clock runs,
/// a hollow ring when it doesn't. The pulse is what catches the eye — a static
/// dot is too easy to overlook on a small note.
private struct StatusDot: View {
    let isLive: Bool

    @State private var pulse = false

    var body: some View {
        ZStack {
            if isLive {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulse ? 2.4 : 1)
                    .opacity(pulse ? 0 : 0.55)
            }
            Circle()
                .fill(isLive ? Color.green : Color.clear)
                .overlay(
                    Circle().strokeBorder(.secondary.opacity(isLive ? 0 : 0.6), lineWidth: 1)
                )
                .frame(width: 8, height: 8)
                .shadow(color: isLive ? Color.green.opacity(0.9) : .clear, radius: 4)
        }
        .frame(width: 20, height: 20)
        .onAppear { if isLive { startPulse() } }
        .onChange(of: isLive) { _, live in
            if live { startPulse() } else { pulse = false }
        }
        .accessibilityHidden(true)
    }

    private func startPulse() {
        // Reset first: repeatForever never returns to the starting value, so a
        // stopped-and-restarted pulse would otherwise begin mid-flight.
        pulse = false
        withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
            pulse = true
        }
    }
}

private extension Poller.Activity {
    var accessibilityDescription: String {
        switch self {
        case .tracking(let domain): return "Currently counting time on \(domain)."
        case .idleElsewhere: return "Not on a tracked site."
        case .away: return "Paused, you're away."
        }
    }
}

/// Seven bars, oldest to newest, each scaled against the busiest day on screen.
private struct WeekChart: View {
    let days: [(date: Date, seconds: Double)]

    private var peak: Double {
        max(days.map(\.seconds).max() ?? 0, 1)
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"  // single-letter weekday
        return formatter
    }()

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                let isToday = index == days.count - 1
                VStack(spacing: 3) {
                    GeometryReader { geometry in
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(isToday ? Color.accentColor : Color.secondary.opacity(0.45))
                                // Always leave a 2pt sliver so empty days read as
                                // "zero", not "missing".
                                .frame(height: max(2, geometry.size.height * day.seconds / peak))
                        }
                    }
                    Text(Self.weekdayFormatter.string(from: day.date))
                        .font(.system(size: 8, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? .secondary : .tertiary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(day.date.formatted(.dateTime.weekday(.wide))): \(DurationFormat.spoken(day.seconds))"
                )
            }
        }
        .frame(height: 42)
    }
}
