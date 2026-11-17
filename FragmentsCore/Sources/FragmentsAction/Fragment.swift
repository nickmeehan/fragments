import Foundation

/// What a launch action hands back so Fragments can return to what it started. Saved in the fragment's front matter;
/// only the action named in `action:` reads it.
public struct Session: Codable, Equatable, Sendable {
    /// The session in the app the action launched into. For Rex, Rex's own session id.
    public var id: String
    /// Where it runs, when that means anything.
    public var folder: String?
    /// What brings it back once `id` is gone, when that is something else. For Rex, Claude's conversation id.
    public var resume: String?

    public init(id: String, folder: String? = nil, resume: String? = nil) {
        self.id = id
        self.folder = folder
        self.resume = resume
    }
}

/// One captured thought: a Markdown file with front matter in the fragments folder. It is also the one argument
/// every action receives.
public struct Fragment: Equatable, Identifiable, Sendable {
    public var id: String
    public var createdAt: Date
    public var text: String
    /// The name you gave it in the list, if any. A launch action hears when it changes (`retitle`); Rex names the
    /// session after it.
    public var title: String?
    /// The id of the action the thought was sent to: `keep`, or an action folder's name such as `rex`. A plain
    /// string, so a fragment whose action is gone keeps its id through an edit.
    public var action: String
    public var session: Session?

    public init(
        id: String = Fragment.newID(), createdAt: Date = .now, text: String, title: String? = nil,
        action: String = "keep", session: Session? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.title = title
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

    /// What the list shows: the title, else the first line.
    public var heading: String {
        title ?? firstLine
    }

    /// The first line, cut to fit a row.
    public var firstLine: String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return line.count > 80 ? String(line.prefix(80)) + "…" : line
    }

    // MARK: Markdown

    public var markdown: String {
        var head = ["id: \(id)", "created: \(createdAt.formatted(.iso8601))", "action: \(action)"]
        if let title { head.append("title: \(title)") }
        if let session {
            head.append("session: \(session.id)")
            if let resume = session.resume { head.append("resume: \(resume)") }
            if let folder = session.folder { head.append("folder: \(folder)") }
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
        let written = { (key: String) in fields[key].flatMap { $0.isEmpty ? nil : $0 } }
        title = written("title")
        // Before Rex was an action, its fragments said `claude`.
        action = written("action").map { $0 == "claude" ? "rex" : $0 } ?? "keep"
        // Before launch actions, Rex wrote its label as `session` and the id it needs as `claude_session`.
        session = (written("claude_session") ?? written("session")).map {
            Session(id: $0, folder: written("folder"), resume: written("resume"))
        }
    }
}

// MARK: On the wire

/// What an action sees of a fragment. The session is there once a launch action has started one, so `attach` has it.
extension Fragment: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, created, text, title, action, session
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            createdAt: try container.decode(Date.self, forKey: .created),
            text: try container.decode(String.self, forKey: .text),
            title: try container.decodeIfPresent(String.self, forKey: .title),
            action: try container.decode(String.self, forKey: .action),
            session: try container.decodeIfPresent(Session.self, forKey: .session))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .created)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(action, forKey: .action)
        try container.encodeIfPresent(session, forKey: .session)
    }
}
