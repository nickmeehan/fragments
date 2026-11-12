import Foundation
import FragmentsAction

/// Starts Claude Code on the thought in a Rex (Superlogical) session, and comes back to it: ↩ in the list shows the
/// session, or resumes the conversation in a new one when the session is gone (reboot, closed).
@main
struct Rex: LaunchAction {
    static let name = "Rex"
    static let chord: Chord = "cmd+shift+return"

    @Setting("Project folder", kind: .folder) var folder = "~"
    @Setting("Model", placeholder: "default") var model: String?
    @Setting("Effort", choices: ["low", "medium", "high", "xhigh", "max"]) var effort: String?
    @Setting("Permission mode", placeholder: "default") var permissionMode: String?

    /// The session id is Claude's, chosen here, so attach can `claude --resume` it whatever happened to Rex.
    func start(_ fragment: Fragment) throws -> Session {
        let session = Session(id: UUID().uuidString.lowercased(), folder: folder)
        let id = try open(fragment, in: folder, running: claude(fragment, sessionID: session.id))
        // A start that can't be shown still started: Rex comes forward, and the fragment keeps its session.
        if show(id) != nil { try? Rex.run(["/usr/bin/open", "-b", "com.superlogical.rex"]) }
        return session
    }

    func attach(_ fragment: Fragment, to session: Session) throws {
        let found = try Rex.run(Rex.rex(["session", "inspect", Rex.label(for: fragment), "--json"]))
        let id = found.status == 0 ? Rex.sessionID(in: found.output) : nil
        let shown = try id ?? open(fragment, in: session.folder ?? folder, running: ["claude", "--resume", session.id])
        if let problem = show(shown) {
            throw Problem("The session is running in Rex, but couldn't be brought to the front.\n" + problem)
        }
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

    /// Starts a session named after the fragment that runs `command` in `folder`; returns Rex's id for it.
    private func open(_ fragment: Fragment, in folder: String, running command: [String]) throws -> String {
        let script = Rex.script(folder: folder, command: command, path: ProcessInfo.processInfo.environment["PATH"])
        let created = try Rex.run(Rex.new(label: Rex.label(for: fragment), folder: folder, script: script))
        guard created.status == 0 else { throw Problem("Rex couldn't start the session.\n" + created.output) }
        guard let id = Rex.sessionID(in: created.output) else {
            throw Problem("Rex didn't say which session it started.\n" + created.output)
        }
        return id
    }

    /// Shows the session in the Rex app; nil when it did, else Rex's reason (no app connected, Remote Control off).
    private func show(_ id: String) -> String? {
        let clients = try? Rex.run(Rex.rex(["client", "list", "--json"]))
        let client = clients.flatMap { Rex.appClientID(in: $0.output) }
        guard let selected = try? Rex.run(Rex.select(sessionID: id, client: client)) else { return "rex didn't run." }
        return selected.status == 0 ? nil : selected.output
    }
}

// MARK: The commands Rex runs, apart from the action so the tests can read them
// Verified against Rex Beta 0.1.0 (1853) on 2026-11-09, the client listing against (1925) on 2026-11-10, and the
// inline script against (1925) on 2026-11-11.

extension Rex {
    struct Problem: Error, CustomStringConvertible {
        var description: String
        init(_ description: String) { self.description = description }
    }

    /// The Rex session a fragment's conversation lives in. Derived, so the fragment only stores Claude's id.
    static func label(for fragment: Fragment) -> String {
        "frag-\(fragment.id)"
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
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"), start < end,
            let root = try? JSONSerialization.jsonObject(with: Data(output[start...end].utf8)) as? [String: Any],
            let clients = root["clients"] as? [[String: Any]]
        else { return nil }
        let live = clients.first { client in
            let info = client["info"] as? [String: Any]
            return info?["kind"] as? String == "app" && client["connection_state"] as? String == "connected"
        }
        return live?["client_id"] as? String
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
