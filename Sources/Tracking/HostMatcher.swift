import Foundation

/// Turns a browser tab's URL into a tracked-domain match.
enum HostMatcher {

    /// Lowercased host with any leading `www.` removed. `nil` for anything that
    /// isn't an ordinary web page (about:blank, file://, chrome://, empty tabs).
    static func normalizedHost(of urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              var host = url.host?.lowercased(),
              !host.isEmpty
        else { return nil }

        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// True when `host` is the tracked domain itself or one of its subdomains.
    /// The dot matters: `notchess.com` must not match `chess.com`.
    static func matches(host: String, tracked: String) -> Bool {
        let tracked = tracked.lowercased()
        return host == tracked || host.hasSuffix("." + tracked)
    }

    /// The tracked domain a URL belongs to, or `nil`. When several entries match
    /// the most specific one wins, so tracking both `chess.com` and
    /// `beta.chess.com` reports beta traffic under the more precise label.
    static func trackedDomain(for urlString: String, in tracked: [String]) -> String? {
        guard let host = normalizedHost(of: urlString) else { return nil }
        return tracked
            .filter { matches(host: host, tracked: $0) }
            .max { $0.count < $1.count }
    }

    /// Cleans user input from the settings sheet: accepts `https://www.Chess.com/play`
    /// and stores `chess.com`.
    static func canonicalize(input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }

        if let range = text.range(of: "://") { text = String(text[range.upperBound...]) }
        if let slash = text.firstIndex(of: "/") { text = String(text[..<slash]) }
        if let colon = text.firstIndex(of: ":") { text = String(text[..<colon]) }
        if text.hasPrefix("www.") { text.removeFirst(4) }

        // Must look like a domain: at least one dot, no spaces, no stray characters.
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard text.contains("."),
              !text.hasPrefix("."), !text.hasSuffix("."),
              text.unicodeScalars.allSatisfy({ allowed.contains($0) })
        else { return nil }

        return text
    }
}
