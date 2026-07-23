import Foundation
import Combine

/// Per-day, per-domain second counts, persisted as one small JSON file.
///
/// The whole dataset is a single integer per site per day, so a database would be
/// all cost and no benefit: JSON keeps the app dependency-free, keeps the binary
/// small, and needs no migration story. A decade of daily use is well under a megabyte.
@MainActor
final class UsageStore: ObservableObject {

    /// `"2026-07-22" -> ["chess.com": 4832]`, seconds.
    @Published private(set) var days: [String: [String: Double]] = [:]

    private let fileURL: URL
    private var dirty = false
    private var saveTimer: Timer?

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dayKey(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    init(directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory()
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("usage.json")
        load()
        startAutosave()
    }

    private static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("ChessTime", isDirectory: true)
    }

    // MARK: - Recording

    func add(seconds: Double, to domain: String, on date: Date = Date()) {
        guard seconds > 0 else { return }
        let key = Self.dayKey(for: date)
        days[key, default: [:]][domain, default: 0] += seconds
        dirty = true
    }

    // MARK: - Queries

    func seconds(on date: Date = Date(), domains: [String]? = nil) -> Double {
        let bucket = days[Self.dayKey(for: date)] ?? [:]
        guard let domains else { return bucket.values.reduce(0, +) }
        return domains.reduce(0) { $0 + (bucket[$1] ?? 0) }
    }

    func seconds(for domain: String, on date: Date = Date()) -> Double {
        days[Self.dayKey(for: date)]?[domain] ?? 0
    }

    /// Oldest first, always exactly `count` entries so the chart keeps a stable
    /// shape on days with no activity.
    func recentDays(_ count: Int, domains: [String]? = nil, endingOn end: Date = Date())
        -> [(date: Date, seconds: Double)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: end)
        return (0..<count).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (date: date, seconds: seconds(on: date, domains: domains))
        }
    }

    /// Every day that has any recorded time, newest first.
    func allTotals(domains: [String]? = nil) -> [(day: String, seconds: Double)] {
        days.keys.sorted(by: >).compactMap { key in
            let bucket = days[key] ?? [:]
            let total = domains.map { list in list.reduce(0) { $0 + (bucket[$1] ?? 0) } }
                ?? bucket.values.reduce(0, +)
            return total > 0 ? (day: key, seconds: total) : nil
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([String: [String: Double]].self, from: data) {
            days = decoded
        }
    }

    private func startAutosave() {
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.saveIfNeeded() }
        }
        RunLoop.main.add(timer, forMode: .common)
        saveTimer = timer
    }

    func saveIfNeeded() {
        guard dirty else { return }
        save()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(days) else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
            dirty = false
        } catch {
            NSLog("ChessTime: could not write \(fileURL.path): \(error.localizedDescription)")
        }
    }

    // MARK: - Data management

    func exportCSV(domains: [String]? = nil) -> String {
        var lines = ["date,domain,seconds,hours"]
        for day in days.keys.sorted() {
            for (domain, seconds) in (days[day] ?? [:]).sorted(by: { $0.key < $1.key }) {
                if let domains, !domains.contains(domain) { continue }
                let hours = String(format: "%.4f", seconds / 3600)
                lines.append("\(day),\(domain),\(Int(seconds.rounded())),\(hours)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    func eraseAll() {
        days = [:]
        dirty = true
        save()
    }
}

/// Shared duration formatting: "1h 23m", "23m", "45s".
enum DurationFormat {
    static func short(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }

    /// Spoken form for accessibility, where "1h 23m" reads poorly.
    static func spoken(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        switch (hours, minutes) {
        case (0, 0): return "\(total) seconds"
        case (0, _): return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        case (_, 0): return "\(hours) hour\(hours == 1 ? "" : "s")"
        default: return "\(hours) hour\(hours == 1 ? "" : "s") \(minutes) minute\(minutes == 1 ? "" : "s")"
        }
    }
}
