import Foundation

/// What the user asked Fragments to do with a captured thought.
public enum Action: String, CaseIterable, Sendable {
    case keep
    case claude
}

/// A Claude Code session that was started from a fragment, living in a Rex terminal session.
public struct Session: Equatable, Sendable {
    /// Rex session label.
    public var name: String
    public var claudeSessionID: String
    public var folder: String

    public init(name: String, claudeSessionID: String, folder: String) {
        self.name = name
        self.claudeSessionID = claudeSessionID
        self.folder = folder
    }
}

/// One captured thought: a Markdown file with front matter in the fragments folder.
public struct Fragment: Equatable, Identifiable, Sendable {
    public var id: String
    public var createdAt: Date
    public var text: String
    public var action: Action
    public var session: Session?

    public init(
        id: String = Fragment.newID(), createdAt: Date = .now, text: String, action: Action = .keep,
        session: Session? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.action = action
        self.session = session
    }

    /// Sortable and filesystem-safe: `20261106-224512-3f9a`.
    public static func newID(now: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: now) + "-" + String(format: "%04x", UInt16.random(in: .min ... .max))
    }

    /// First line, for the list.
    public var title: String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return line.count > 80 ? String(line.prefix(80)) + "…" : line
    }

    // MARK: Markdown

    public var markdown: String {
        var head = ["id: \(id)", "created: \(createdAt.formatted(.iso8601))", "action: \(action.rawValue)"]
        if let session {
            head += [
                "session: \(session.name)", "claude_session: \(session.claudeSessionID)",
                "folder: \(session.folder)",
            ]
        }
        return "---\n" + head.joined(separator: "\n") + "\n---\n\n" + text + "\n"
    }

    public init?(markdown: String) {
        var lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)[...]
        guard lines.first == "---" else { return nil }
        lines = lines.dropFirst()
        var fields: [String: String] = [:]
        while let line = lines.first, line != "---" {
            lines = lines.dropFirst()
            guard let colon = line.firstIndex(of: ":") else { continue }
            fields[String(line[..<colon])] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard lines.first == "---", let id = fields["id"] else { return nil }
        self.id = id
        createdAt = fields["created"].flatMap { try? Date($0, strategy: .iso8601) } ?? .distantPast
        text = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        action = fields["action"].flatMap(Action.init(rawValue:)) ?? .keep
        if let name = fields["session"] {
            session = Session(
                name: name, claudeSessionID: fields["claude_session"] ?? "", folder: fields["folder"] ?? "")
        } else {
            session = nil
        }
    }
}
