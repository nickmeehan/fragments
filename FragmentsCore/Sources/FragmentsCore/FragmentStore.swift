import Foundation

/// The fragments folder: one `<id>.md` per fragment, plus `.sessions/` for the scripts that start agents.
public struct FragmentStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func url(for fragment: Fragment) -> URL {
        directory.appending(path: "\(fragment.id).md")
    }

    public func scriptURL(for fragment: Fragment) -> URL {
        directory.appending(path: ".sessions/\(fragment.id).sh")
    }

    /// Newest first. A missing folder is an empty list, not an error.
    public func all() throws -> [Fragment] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .compactMap(Fragment.init(markdown:))
            .sorted { $0.id > $1.id }
    }

    public func save(_ fragment: Fragment) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try fragment.markdown.write(to: url(for: fragment), atomically: true, encoding: .utf8)
    }

    @discardableResult
    public func writeScript(_ contents: String, for fragment: Fragment) throws -> URL {
        let url = scriptURL(for: fragment)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Moves the file to the Trash, so a stray `x` is recoverable.
    public func trash(_ fragment: Fragment) throws {
        try FileManager.default.trashItem(at: url(for: fragment), resultingItemURL: nil)
    }
}
