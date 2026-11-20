import Foundation
import FragmentsAction

/// Starts Claude Code on the thought in a Rex (Superlogical) session, and comes back to it: ↩ in the list shows the
/// session, or resumes the conversation in a new one when the session is gone (reboot, closed). The session's name
/// and the fragment's title follow each other, and trashing the fragment closes the session.
@main
struct Rex: LaunchAction {
    static let name = "Rex"
    static let chord: Chord = "cmd+shift+return"
    static let icon = "terminal"

    @Setting("Project folder", kind: .folder) var folder = "~"
    @Setting("Model", placeholder: "default") var model: String?
    @Setting("Effort", choices: ["low", "medium", "high", "xhigh", "max"]) var effort: String?
    @Setting("Permission mode", placeholder: "default") var permissionMode: String?

    /// The session is Rex's, found again by its id whatever it is called. The conversation is Claude's, chosen here, so
    /// attach can `claude --resume` it whatever happened to Rex.
    func start(_ fragment: Fragment) throws -> Session {
        let conversation = UUID().uuidString.lowercased()
        let id = try open(fragment, in: folder, running: claude(fragment, sessionID: conversation))
        // A start that can't be shown still started: Rex comes forward, and the fragment keeps its session.
        if show(id) != nil { bringRexForward() }
        return Session(id: id, folder: folder, resume: conversation)
    }

    /// Hands back the session it showed: the one found, or a new one resuming the conversation, so Fragments keeps
    /// Rex's id for it.
    func attach(_ fragment: Fragment, to session: Session) throws -> Session {
        let found = try running(fragment, in: session)
        let id =
            try found
            ?? open(fragment, in: session.folder ?? folder, running: ["claude", "--resume", session.conversation])
        if let problem = show(id) {
            guard found == nil else {
                throw Problem("The session is running in Rex, but couldn't be brought to the front.\n" + problem)
            }
            bringRexForward()  // as at start: the new session is open, and the fragment keeps it
        }
        return Session(id: id, folder: session.folder, resume: session.conversation)
    }

    /// Names the session after the new title. One that isn't running takes the title when attach opens it again.
    func retitle(_ fragment: Fragment, in session: Session) throws {
        guard let id = try running(fragment, in: session) else { return }
        try name(id, after: fragment)
    }

    /// Closes the session ↩ would show, Claude with it. The conversation stays on disk, so a fragment taken back out of
    /// the Trash resumes it in a new session (attach). Killed, not quit: a quit Claude asks whether to keep a worktree
    /// with work in it, and nobody is there to answer. A worktree is left as it was.
    func end(_ fragment: Fragment, in session: Session) throws {
        guard let id = try running(fragment, in: session) else { return }
        let killed = try Rex.run(Rex.kill(sessionID: id))
        guard killed.status == 0 else { throw Problem("Rex couldn't close the session.\n" + killed.output) }
    }

    /// What each fragment's session is called in Rex now, with one `rex session ls`; `frag-<id>` reads as no title.
    /// Says nothing when Rex isn't answering, or for a session it doesn't list.
    func titles(of fragments: [Fragment]) throws -> [Fragment.ID: String?] {
        let listed = try Rex.run(Rex.rex(["session", "ls", "--json"]))
        guard listed.status == 0 else { return [:] }
        let labels = Rex.labels(in: listed.output)
        var titles: [Fragment.ID: String?] = [:]
        for fragment in fragments {
            guard let id = fragment.session?.rexID, let label = labels[id] else { continue }
            titles[fragment.id] = label == "frag-\(fragment.id)" ? nil : label
        }
        return titles
    }

    /// Claude Code starting conversation `sessionID` with your settings as flags. The thought goes after `--`, so one
    /// that starts with a dash is a prompt, not an option.
    func claude(_ fragment: Fragment, sessionID: String) -> [String] {
        var claude = ["claude", "--session-id", sessionID]
        if let model { claude += ["--model", model] }
        if let effort { claude += ["--effort", effort] }
        if let permissionMode { claude += ["--permission-mode", permissionMode] }
        return claude + ["--", fragment.text]
    }

    /// Starts a session named after the fragment that runs `command` in `folder`; returns Rex's id for it. A title is
    /// set by a rename, because `rex new` would read one that starts with a dash as a flag.
    private func open(_ fragment: Fragment, in folder: String, running command: [String]) throws -> String {
        let script = Rex.script(folder: folder, command: command, path: ProcessInfo.processInfo.environment["PATH"])
        let created = try Rex.run(Rex.new(label: "frag-\(fragment.id)", folder: folder, script: script))
        guard created.status == 0 else { throw Problem("Rex couldn't start the session.\n" + created.output) }
        guard let id = Rex.sessionID(in: created.output) else {
            throw Problem("Rex didn't say which session it started.\n" + created.output)
        }
        if fragment.title != nil { try? name(id, after: fragment) }  // a session under its old name still works
        return id
    }

    /// Rex's id for the session the conversation runs in: by the id Fragments kept, else by the fragment's name (a
    /// session saved before Fragments kept Rex's id). Nil when none is running.
    private func running(_ fragment: Fragment, in session: Session) throws -> String? {
        for target in [session.rexID, fragment.title, "frag-\(fragment.id)"].compactMap({ $0 }) {
            let found = try Rex.run(Rex.rex(["session", "inspect", "--json", "--", target]))
            if found.status == 0, let id = Rex.sessionID(in: found.output) { return id }
        }
        return nil
    }

    private func name(_ id: String, after fragment: Fragment) throws {
        let renamed = try Rex.run(Rex.rename(sessionID: id, label: Rex.label(for: fragment)))
        guard renamed.status == 0 else { throw Problem("Rex couldn't rename the session.\n" + renamed.output) }
    }

    /// Shows the session in the Rex app; nil when it did, else Rex's reason (no app connected, Remote Control off).
    private func show(_ id: String) -> String? {
        let clients = try? Rex.run(Rex.rex(["client", "list", "--json"]))
        let client = clients.flatMap { Rex.appClientID(in: $0.output) }
        guard let selected = try? Rex.run(Rex.select(sessionID: id, client: client)) else { return "rex didn't run." }
        return selected.status == 0 ? nil : selected.output
    }

    private func bringRexForward() {
        _ = try? Rex.run(["/usr/bin/open", "-b", "com.superlogical.rex"])
    }
}

extension Session {
    /// Rex's id for the session; nil in one saved before `resume:`, whose id is Claude's.
    fileprivate var rexID: String? { resume == nil ? nil : id }
    /// Claude's conversation: `resume`, or the id itself in a session saved before `resume:`.
    fileprivate var conversation: String { resume ?? id }
}

// MARK: The commands Rex runs, apart from the action so the tests can read them
// Verified against Rex Beta 0.1.0 (1853) on 2026-11-09, the client listing against (1925) on 2026-11-10, the
// inline script against (1925) on 2026-11-11, and the kill against (2042) on 2026-11-19.

extension Rex {
    struct Problem: Error, CustomStringConvertible {
        var description: String
        init(_ description: String) { self.description = description }
    }

    /// What the Rex session is called: the fragment's title, else `frag-<id>`. A name changed in Rex comes back as the
    /// title when the list next opens (`titles`).
    static func label(for fragment: Fragment) -> String {
        fragment.title ?? "frag-\(fragment.id)"
    }

    /// `rex` and its arguments. `FRAGMENTS_REX` names a shell script to run in its place, so tests need neither Rex
    /// nor Claude. Run through `sh`, because macOS won't execute a file the sandboxed UI test runner wrote.
    static func rex(_ arguments: [String]) -> [String] {
        (ProcessInfo.processInfo.environment["FRAGMENTS_REX"].map { ["/bin/sh", $0] } ?? ["rex"]) + arguments
    }

    /// Runs `command` in `folder`, then drops into a login shell so the window survives. Rex's own PATH comes first,
    /// as in any terminal it opens (nvm, asdf…); the one this action got from Fragments follows, so whatever found
    /// `rex` here also finds `claude` there.
    static func script(folder: String, command: [String], path: String?) -> String {
        """
        \(path.map { #"export PATH="$PATH":"# + $0.quoted } ?? "")
        cd \(folder.quoted) || exit 1
        \(command.map(\.quoted).joined(separator: " "))
        exec "${SHELL:-/bin/zsh}" -l
        """
    }

    /// Starts a session that runs the script through zsh's login environment, and prints the session as JSON. The
    /// script goes inline: Rex passes arguments through unchanged, so there's no file to write or clean up.
    static func new(label: String, folder: String, script: String) -> [String] {
        rex(["new", label, "--cwd", folder, "--shell", "zsh", "--keep-open", "--json", "--", "/bin/sh", "-c", script])
    }

    /// Renames a session by Rex's id. `--`, so a label that starts with a dash isn't read as a flag.
    static func rename(sessionID: String, label: String) -> [String] {
        rex(["session", "rename", "--", sessionID, label])
    }

    /// Closes a session by Rex's id, ending what runs in it.
    static func kill(sessionID: String) -> [String] {
        rex(["session", "kill", "--", sessionID])
    }

    /// Shows the session in the Rex app; `rex focus` only moves focus inside a session. Names the app client when
    /// known, so a stale client left by an update never makes Rex's default target ambiguous. Needs Remote Control
    /// on in Rex's settings; Rex says so when it is off.
    static func select(sessionID: String, client: String? = nil) -> [String] {
        rex((client.map { ["-C", $0] } ?? []) + ["do", "session.select", "session_id=\(sessionID)"])
    }

    /// The `session_id` in `rex new --json` or `rex session inspect --json` output. A regex, not a JSON parse, so
    /// noise around it can't hide it.
    static func sessionID(in output: String) -> String? {
        output.firstMatch(of: #/"session_id"\s*:\s*"([^"]+)"/#).map { String($0.1) }
    }

    /// The `client_id` of the live Rex app in `rex client list --json` output; nil when none is connected. A real
    /// parse, because kind and state are sibling keys a regex can't tie to one client.
    static func appClientID(in output: String) -> String? {
        guard let clients = json(in: output)?["clients"] as? [[String: Any]] else { return nil }
        let live = clients.first { client in
            let info = client["info"] as? [String: Any]
            return info?["kind"] as? String == "app" && client["connection_state"] as? String == "connected"
        }
        return live?["client_id"] as? String
    }

    /// Every session's name by its id, from `rex session ls --json` output.
    static func labels(in output: String) -> [String: String] {
        let sessions = json(in: output)?["sessions"] as? [[String: Any]] ?? []
        var labels: [String: String] = [:]
        for session in sessions {
            if let id = session["session_id"] as? String, let label = session["label"] as? String { labels[id] = label }
        }
        return labels
    }

    /// The JSON object in a command's output, ignoring anything printed around it.
    private static func json(in output: String) -> [String: Any]? {
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"), start < end else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: Data(output[start...end].utf8)) as? [String: Any]
    }

    /// Runs a program found on the PATH, with stdout and stderr together.
    static func run(_ argv: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = argv
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()  // before waiting, so a full pipe can't stall it
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output, as: UTF8.self))
    }
}

extension String {
    /// Single-quoted for POSIX sh.
    fileprivate var quoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
