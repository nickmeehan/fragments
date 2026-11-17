import Foundation
import FragmentsAction

/// Claude Cowork, in the Claude desktop app, and back to it: ↩ in the list opens the task the thought became. The
/// draft link fills Cowork's composer and does not send: Anthropic made links stop short of sending on purpose, so the
/// prompt is always seen before it runs. From "Open Claude Desktop with a link" (updated 2026-06-30). Claude cuts the
/// prompt at roughly 14,000 characters.
@main
struct Cowork: LaunchAction {
    static let name = "Cowork"
    static let chord: Chord = "cmd+option+return"
    static let icon = "bubble.left.and.text.bubble.right"

    /// A task gets its id only when you send it, so the session starts as a draft and the first ↩ finds the id.
    func start(_ fragment: Fragment) throws -> Session {
        try Cowork.open(Cowork.draft(for: fragment))
        return Session(id: Cowork.draftID)
    }

    /// Opens the task, and hands back its id so Fragments keeps it. One Claude doesn't have (never sent, or no longer
    /// cached) opens as a draft again, as Rex opens a new session when its own is gone.
    func attach(_ fragment: Fragment, to session: Session) throws -> Session {
        let found =
            session.id == Cowork.draftID ? Cowork.taskID(startingWith: fragment.text, in: Cowork.cache) : session.id
        guard let id = found else {
            try Cowork.open(Cowork.draft(for: fragment))
            return session
        }
        try Cowork.open(Cowork.task(id))
        return Session(id: id)
    }
}

// MARK: Links and Claude's cache, apart from the action so the tests can read them
// Verified against Claude 5.1231.2 on 2026-11-17: `claude://claude.ai/cowork/<cse_ id>` opened a task sent minutes
// before, and both test tasks were found by their opening words.

extension Cowork {
    struct Problem: Error, CustomStringConvertible {
        var description: String
        init(_ description: String) { self.description = description }
    }

    /// The session of a thought handed to Cowork but not yet found in Claude.
    static let draftID = "draft"

    static func draft(for fragment: Fragment) -> URL {
        URL(string: "claude://cowork/new?q=" + fragment.text.queryEscaped)!  // cannot fail: the query is escaped
    }

    /// One task in the Claude app. From the app's own link handler (`claude://claude.ai/cowork/…`), not its docs.
    static func task(_ id: String) -> URL {
        URL(string: "claude://claude.ai/cowork/" + id)!  // cannot fail: an id is letters, digits and `_`
    }

    /// Claude's IndexedDB, where it caches your tasks. `FRAGMENTS_CLAUDE_CACHE` names another folder, for tests.
    static var cache: URL {
        ProcessInfo.processInfo.environment["FRAGMENTS_CLAUDE_CACHE"].map { URL(filePath: $0) }
            ?? URL(filePath: NSHomeDirectory()).appending(path: "Library/Application Support/Claude/IndexedDB")
    }

    /// The id of the task that began with `text`: the `cse_` id nearest the thought's opening words in Claude's cache,
    /// within 1 KB of them. Nil when Claude has none.
    static func taskID(startingWith text: String, in folder: URL) -> String? {
        // shortcut: reads Claude's undocumented cache files as bytes. When Claude changes them, ↩ opens a fresh draft
        // instead of the task; switch to a documented way once Claude reports a task's id.
        let line = text.split(whereSeparator: \.isNewline).first?.trimmingCharacters(in: .whitespaces) ?? ""
        // Claude may keep the prompt as JSON, which escapes a quote or backslash, so match up to the first one.
        let opening = String(line.prefix(40).prefix { $0 != "\"" && $0 != "\\" })
        guard !opening.isEmpty, let utf16 = opening.data(using: .utf16LittleEndian) else { return nil }
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.compactMap {
            $0 as? URL
        }
        var best: (distance: Int, id: String)?
        for file in files ?? [] {
            guard let data = try? Data(contentsOf: file), case let ids = taskIDs(in: data), !ids.isEmpty else {
                continue
            }
            for needle in [Data(opening.utf8), utf16] {
                var from = data.startIndex
                while let found = data.range(of: needle, in: from..<data.endIndex) {
                    for (at, id) in ids {
                        let distance = abs(at - found.lowerBound)
                        if distance <= 1024, distance < best?.distance ?? .max { best = (distance, id) }
                    }
                    from = found.upperBound
                }
            }
        }
        return best?.id
    }

    /// Every `cse_` id in `data`, with where it starts. Claude keeps most as length-prefixed strings that the next
    /// field's type letter can follow straight away (`"\u{1c}cse_…N`), so a length byte just before an id caps it;
    /// elsewhere (JSON) the id runs to the first character that can't be in one.
    static func taskIDs(in data: Data) -> [(at: Int, id: String)] {
        let prefix = Data("cse_".utf8)
        var ids: [(at: Int, id: String)] = []
        var from = data.startIndex
        while let found = data.range(of: prefix, in: from..<data.endIndex) {
            var end = found.upperBound
            while end < data.endIndex, end - found.lowerBound < 128, isAlphanumeric(data[end]) { end += 1 }
            var length = end - found.lowerBound
            if found.lowerBound > data.startIndex, case let stated = Int(data[found.lowerBound - 1]),
                (24...68).contains(stated)
            {
                length = min(length, stated)
            }
            if length >= 24 {
                let id = data[found.lowerBound..<found.lowerBound + length]
                ids.append((found.lowerBound, String(decoding: id, as: UTF8.self)))
            }
            from = found.upperBound
        }
        return ids
    }

    private static func isAlphanumeric(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
    }

    /// Hands a link to the Claude app. `FRAGMENTS_OPEN` names a shell script to run in place of `open`, so tests never
    /// reach Claude.
    static func open(_ url: URL) throws {
        let process = Process()
        if let standIn = ProcessInfo.processInfo.environment["FRAGMENTS_OPEN"] {
            process.executableURL = URL(filePath: "/bin/sh")
            process.arguments = [standIn, url.absoluteString]
        } else {
            process.executableURL = URL(filePath: "/usr/bin/open")
            process.arguments = [url.absoluteString]
        }
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw Problem("The Claude app didn't open \(url.scheme ?? "")://… Is it installed?\n" + detail)
        }
    }
}
