import Foundation

/// Everything a launch needs from Settings. The app reads it from UserDefaults.
public struct LaunchPrefs: Equatable, Sendable {
    public var folder: String
    public var model: String
    public var effort: String
    public var permissionMode: String

    public init(folder: String, model: String = "", effort: String = "", permissionMode: String = "") {
        self.folder = folder
        self.model = model
        self.effort = effort
        self.permissionMode = permissionMode
    }
}

/// Builds the shell scripts and argv vectors that start and re-open agent sessions in Rex. Pure: nothing runs here.
public enum Launcher {
    /// Rex adds its CLI to the PATH of terminals it opens, nowhere else; the server keeps it here.
    private static let rexBinDir =
        "$HOME/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/"
        + "Rex Server.app/Contents/MacOS"

    /// GUI apps inherit launchd's bare PATH; the user's tools live here.
    public static let pathLine =
        #"export PATH="\#(rexBinDir):$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH""#

    /// Starts Claude Code with the fragment's text as its first prompt, then drops into a shell so the window
    /// survives. The text is the body only, never the front matter, and goes after `--` so a leading dash is a
    /// prompt and not an option.
    public static func startScript(prompt: String, prefs: LaunchPrefs, sessionID: String) -> String {
        var claude = ["claude", "--session-id", sessionID]
        if !prefs.model.isEmpty { claude += ["--model", prefs.model] }
        if !prefs.effort.isEmpty { claude += ["--effort", prefs.effort] }
        if !prefs.permissionMode.isEmpty { claude += ["--permission-mode", prefs.permissionMode] }
        let command = (claude + ["--", prompt]).map(\.shellQuoted).joined(separator: " ")
        return script(folder: prefs.folder, command: command)
    }

    /// The Rex session a fragment's Claude conversation lives in. Derived, so the fragment only stores the id.
    public static func label(for fragment: Fragment) -> String {
        "frag-\(fragment.id)"
    }

    /// Re-opens a Claude conversation whose Rex session is gone (reboot, closed).
    public static func resumeScript(folder: String, sessionID: String) -> String {
        script(folder: folder, command: "claude --resume \(sessionID.shellQuoted)")
    }

    static func script(folder: String, command: String) -> String {
        """
        #!/bin/sh
        \(pathLine)
        cd \(folder.shellQuoted) || exit 1
        \(command)
        exec "${SHELL:-/bin/zsh}" -l

        """
    }

    // MARK: Rex (Superlogical)
    // Verified against Rex Beta 0.1.0 (1853) on 2026-11-09, the client listing against (1925) on 2026-11-10 —
    // see docs/decisions.md.

    /// Starts a session that runs the script through zsh's login environment, and prints the session as JSON.
    public static func rexNew(label: String, folder: String, script: URL) -> [String] {
        [
            "rex", "new", label, "--cwd", folder, "--shell", "zsh", "--keep-open", "--json", "--", "/bin/sh",
            script.path,
        ]
    }

    /// Finds the session by label; fails (status 3) when it is gone.
    public static func rexInspect(label: String) -> [String] {
        ["rex", "session", "inspect", label, "--json"]
    }

    /// Lists Rex's connected clients as JSON; the app is one of them.
    public static func rexClients() -> [String] {
        ["rex", "client", "list", "--json"]
    }

    /// Shows the session in the Rex app. `rex focus` only moves focus inside a session. Names the app client
    /// when known, so a stale lost client never makes Rex's default target ambiguous. Needs Remote Control
    /// on in Rex's settings; Rex says so when it is off.
    public static func rexSelect(sessionID: String, client: String? = nil) -> [String] {
        ["rex"] + (client.map { ["-C", $0] } ?? []) + ["do", "session.select", "session_id=\(sessionID)"]
    }

    /// The `session_id` in `rex new --json` or `rex session inspect --json` output. A regex, not a JSON parse,
    /// because the login shell the app runs it through may print noise around it.
    public static func sessionID(in output: String) -> String? {
        output.firstMatch(of: #/"session_id"\s*:\s*"([^"]+)"/#).map { String($0.1) }
    }

    /// The `client_id` of the live Rex app in `rex client list --json` output; nil when none is connected.
    /// A real parse, because kind and state are sibling keys a regex can't tie to one client; the shell noise
    /// around the JSON is dropped by keeping only the outermost braces.
    public static func appClientID(in output: String) -> String? {
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
}

extension String {
    /// Single-quoted for POSIX sh.
    public var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
