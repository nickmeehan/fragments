import Foundation

/// The releases newer than the running app, read from GitHub's list of releases: what the update view shows and what
/// ↩ installs.
public struct Update: Equatable, Sendable {
    public struct Release: Equatable, Sendable {
        public var version: String
        /// The release's `feat`, `fix` and `perf` lines, without the type or the "by @… in …" tail.
        public var notes: [String]
    }

    public static let releasesAPI = URL(string: "https://api.github.com/repos/nickmeehan/fragments/releases")!

    /// Newest first, never empty.
    public let releases: [Release]
    /// The version you have.
    public let current: String

    /// The version ↩ installs.
    public var version: String { releases[0].version }

    /// The notification's line: the newest change, and how many more there are.
    public var summary: String {
        let notes = releases.flatMap(\.notes)
        guard let first = notes.first else { return "See what's new." }
        return notes.count == 1 ? first : "\(first), and \(notes.count - 1) more"
    }

    /// The zip ↩ downloads. Built from the version, never taken from GitHub's answer.
    public var zip: URL {
        URL(string: "https://github.com/nickmeehan/fragments/releases/download/v\(version)/Fragments.zip")!
    }

    /// Where to get it by hand when the app can't replace itself.
    public var page: URL {
        URL(string: "https://github.com/nickmeehan/fragments/releases/tag/v\(version)")!
    }

    /// Nil when nothing published is newer than `current`, or `json` isn't GitHub's list of releases.
    public init?(releases json: Data, current: String) {
        struct Published: Decodable {
            var tagName: String
            var body: String?
            var draft: Bool?
            var prerelease: Bool?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let published = try? decoder.decode([Published].self, from: json) else { return nil }
        let newer = published.compactMap { release -> Release? in
            guard release.draft != true, release.prerelease != true,
                let version = Update.version(ofTag: release.tagName), Update.isNewer(version, than: current)
            else { return nil }
            return Release(version: version, notes: Update.notes(release.body ?? ""))
        }
        guard !newer.isEmpty else { return nil }
        releases = newer.sorted { Update.isNewer($0.version, than: $1.version) }
        self.current = current
    }

    /// `v1.2.3` → `1.2.3`. Nil for anything but a v and dotted numbers, so a tag can't put anything else in a URL.
    static func version(ofTag tag: String) -> String? {
        guard tag.hasPrefix("v") else { return nil }
        let version = tag.dropFirst()
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { ("0"..."9").contains($0) } }) else { return nil }
        return String(version)
    }

    /// By number, part by part: 0.10.0 is newer than 0.9.0, and 1.0 is 1.0.0.
    static func isNewer(_ version: String, than other: String) -> Bool {
        let a = version.split(separator: ".").map { Int($0) ?? 0 }
        let b = other.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// The lines of GitHub's generated notes that changed the app, as someone reading them in the app wants them:
    /// `* feat: filter the list by typing by @nick in https://…` → `Filter the list by typing`.
    static func notes(_ body: String) -> [String] {
        body.split(whereSeparator: \.isNewline).compactMap { line in
            guard
                let match = String(line).wholeMatch(
                    of: /\* (?:feat|fix|perf)(?:\([^)]*\))?!?: (.+?)(?: by @\S+ in \S+)?/)
            else { return nil }
            let text = match.1
            return text.prefix(1).uppercased() + text.dropFirst()
        }
    }
}
