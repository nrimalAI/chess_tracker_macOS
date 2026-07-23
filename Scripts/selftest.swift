// Exercises ChessTime's pure logic against the real source files — no Automation
// permission and no UI required.
//
//   swift Scripts/selftest.swift   (see Scripts/run_selftest.sh, which compiles
//                                   this together with the app sources)

import AppKit
import Foundation

var failures = 0
var checks = 0

func check(_ label: String, _ actual: some Equatable, _ expected: some Equatable) {
    checks += 1
    let ok = "\(actual)" == "\(expected)"
    if !ok {
        failures += 1
        print("  FAIL  \(label)\n        got \(actual), expected \(expected)")
    } else {
        print("  ok    \(label)")
    }
}

print("\nHostMatcher.normalizedHost")
check("https + www stripped",
      HostMatcher.normalizedHost(of: "https://www.chess.com/play/online") ?? "nil", "chess.com")
check("subdomain preserved",
      HostMatcher.normalizedHost(of: "https://support.chess.com/") ?? "nil", "support.chess.com")
check("uppercase folded",
      HostMatcher.normalizedHost(of: "HTTPS://WWW.Chess.COM/") ?? "nil", "chess.com")
check("chrome:// ignored",
      HostMatcher.normalizedHost(of: "chrome://newtab") ?? "nil", "nil")
check("file:// ignored",
      HostMatcher.normalizedHost(of: "file:///Users/x/index.html") ?? "nil", "nil")
check("empty ignored", HostMatcher.normalizedHost(of: "") ?? "nil", "nil")

print("\nHostMatcher.matches")
check("exact", HostMatcher.matches(host: "chess.com", tracked: "chess.com"), true)
check("subdomain", HostMatcher.matches(host: "www2.chess.com", tracked: "chess.com"), true)
// The dot in the suffix check is what stops look-alike domains matching.
check("lookalike rejected", HostMatcher.matches(host: "notchess.com", tracked: "chess.com"), false)
check("suffix-only rejected", HostMatcher.matches(host: "xchess.com", tracked: "chess.com"), false)
check("different tld rejected", HostMatcher.matches(host: "chess.org", tracked: "chess.com"), false)

print("\nHostMatcher.trackedDomain")
let tracked = ["chess.com", "lichess.org"]
check("plain match",
      HostMatcher.trackedDomain(for: "https://www.chess.com/puzzles", in: tracked) ?? "nil",
      "chess.com")
check("other site",
      HostMatcher.trackedDomain(for: "https://lichess.org/", in: tracked) ?? "nil",
      "lichess.org")
check("untracked",
      HostMatcher.trackedDomain(for: "https://news.ycombinator.com/", in: tracked) ?? "nil",
      "nil")
check("most specific wins",
      HostMatcher.trackedDomain(for: "https://beta.chess.com/x",
                                in: ["chess.com", "beta.chess.com"]) ?? "nil",
      "beta.chess.com")

print("\nHostMatcher.canonicalize")
check("full url", HostMatcher.canonicalize(input: "https://www.Chess.com/play") ?? "nil", "chess.com")
check("bare domain", HostMatcher.canonicalize(input: "  lichess.org  ") ?? "nil", "lichess.org")
check("port stripped", HostMatcher.canonicalize(input: "example.com:8080") ?? "nil", "example.com")
check("no dot rejected", HostMatcher.canonicalize(input: "localhost") ?? "nil", "nil")
check("spaces rejected", HostMatcher.canonicalize(input: "not a domain") ?? "nil", "nil")
check("empty rejected", HostMatcher.canonicalize(input: "") ?? "nil", "nil")

print("\nDurationFormat")
check("seconds", DurationFormat.short(45), "45s")
check("minutes", DurationFormat.short(23 * 60), "23m")
check("hours and minutes", DurationFormat.short(3600 + 23 * 60), "1h 23m")
check("exact hour", DurationFormat.short(7200), "2h 0m")
check("zero", DurationFormat.short(0), "0s")
check("spoken", DurationFormat.spoken(3600 + 60), "1 hour 1 minute")

print("\nUsageStore")
let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("chesstime-selftest-\(ProcessInfo.processInfo.processIdentifier)")
defer { try? FileManager.default.removeItem(at: temporary) }

let calendar = Calendar.current
let today = Date()
let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

MainActor.assumeIsolated {
    let store = UsageStore(directory: temporary)
    store.add(seconds: 60, to: "chess.com")
    store.add(seconds: 30, to: "chess.com")
    store.add(seconds: 10, to: "lichess.org")
    store.add(seconds: 120, to: "chess.com", on: yesterday)

    check("accumulates same day", store.seconds(for: "chess.com"), 90.0)
    check("separates domains", store.seconds(for: "lichess.org"), 10.0)
    check("day rollover keeps buckets apart",
          store.seconds(for: "chess.com", on: yesterday), 120.0)
    check("filtered total", store.seconds(domains: ["chess.com"]), 90.0)
    check("unfiltered total", store.seconds(), 100.0)
    check("zero seconds ignored", { store.add(seconds: 0, to: "x"); return store.seconds(for: "x") }(), 0.0)

    let week = store.recentDays(7, domains: ["chess.com"])
    check("week has 7 entries", week.count, 7)
    check("week ends today", DurationFormat.short(week[6].seconds), "1m")
    check("week includes yesterday", DurationFormat.short(week[5].seconds), "2m")

    // Persistence: save, then load a fresh store over the same directory.
    store.save()
    let reloaded = UsageStore(directory: temporary)
    check("survives reload", reloaded.seconds(for: "chess.com"), 90.0)
    check("reload keeps history", reloaded.seconds(for: "chess.com", on: yesterday), 120.0)

    let csv = reloaded.exportCSV()
    check("csv header", csv.split(separator: "\n")[0], "date,domain,seconds,hours")
    check("csv row count", csv.split(separator: "\n").count, 4)  // header + 3 rows

    reloaded.eraseAll()
    check("erase clears", reloaded.seconds(for: "chess.com"), 0.0)
}

print("\nBrowser catalogue")
check("Safari known", Browser.known(bundleID: "com.apple.Safari")?.name ?? "nil", "Safari")
check("Chrome known", Browser.known(bundleID: "com.google.Chrome")?.name ?? "nil", "Google Chrome")
check("Arc uses chrome dictionary",
      Browser.known(bundleID: "company.thebrowser.Browser").map { "\($0.family)" } ?? "nil",
      "chromium")
check("Firefox absent", Browser.known(bundleID: "org.mozilla.firefox")?.name ?? "nil", "nil")
check("safari script",
      Browser.known(bundleID: "com.apple.Safari")?.script ?? "",
      "tell application id \"com.apple.Safari\" to return URL of current tab of front window")
check("chrome script",
      Browser.known(bundleID: "com.google.Chrome")?.script ?? "",
      "tell application id \"com.google.Chrome\" to return URL of active tab of front window")
print("  info  installed on this Mac: \(Browser.installed.map(\.name).joined(separator: ", "))")

print("\n\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
