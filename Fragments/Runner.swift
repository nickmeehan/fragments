import AppKit
import FragmentsCore
import os

/// Runs an argv through a login shell so claude, rex, xcrun and whatever an action calls resolve from the user's
/// real PATH.
enum Shell {
    private static let log = Logger(subsystem: "tech.meehan.fragments", category: "shell")

    /// `input`, when given, goes to the program's stdin. After `timeout` seconds the program is stopped and the
    /// status is -2. Blocks: call it off the main thread for anything slow.
    @discardableResult
    static func run(_ argv: [String], input: Data? = nil, timeout: TimeInterval? = nil) -> (
        status: Int32, output: String
    ) {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = ["-lc", Launcher.pathLine + "; " + argv.map(\.shellQuoted).joined(separator: " ")]
        let pipe = Pipe()  // ponytail: blocks on >64KB of output; these commands print a screenful at most.
        process.standardOutput = pipe
        process.standardError = pipe
        let stdin = input.map { _ in Pipe() }
        if let stdin { process.standardInput = stdin }
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        if let stdin, let input {
            stdin.fileHandleForWriting.write(input)
            try? stdin.fileHandleForWriting.close()
        }
        if let timeout {
            let deadline = Date.now.addingTimeInterval(timeout)
            while process.isRunning, Date.now < deadline { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
                log.info("\(argv.joined(separator: " "), privacy: .public) → stopped after \(timeout)s")
                return (-2, "It was still running after \(Int(timeout)) seconds, so Fragments stopped it.")
            }
        }
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        log.info("\(argv.joined(separator: " "), privacy: .public) → \(process.terminationStatus)")
        return (process.terminationStatus, output)
    }
}

/// Starts and re-opens Claude Code sessions for fragments in Rex.
@MainActor
enum Runner {
    static func launch(_ fragment: Fragment, store: FragmentStore) {
        guard let session = fragment.session else { return }
        let contents = Launcher.startScript(prompt: fragment.text, prefs: Prefs.launch, sessionID: session.id)
        guard let script = write(contents, for: fragment, store: store) else { return }
        start(fragment, in: folder(of: session), script: script)
    }

    /// Brings the session forward. A session that is gone (reboot, closed) is rebuilt around
    /// `claude --resume`, so the conversation is never lost.
    static func attach(_ fragment: Fragment, store: FragmentStore) {
        guard let session = fragment.session else { return }
        let found = Shell.run(Launcher.rexInspect(label: Launcher.label(for: fragment)))
        if found.status == 0, let id = Launcher.sessionID(in: found.output) {
            show(id)
            return
        }
        let resume = Launcher.resumeScript(folder: folder(of: session), sessionID: session.id)
        guard let script = write(resume, for: fragment, store: store) else { return }
        start(fragment, in: folder(of: session), script: script)
    }

    /// Rex's sessions always record a folder; the project folder covers one written without.
    private static func folder(of session: Session) -> String {
        session.folder ?? Prefs.launch.folder
    }

    /// `rex new` prints the new session's id; `session.select` then shows it in the app.
    private static func start(_ fragment: Fragment, in folder: String, script: URL) {
        let created = Shell.run(
            Launcher.rexNew(label: Launcher.label(for: fragment), folder: folder, script: script))
        guard check(created, "Rex could not start the session.") else { return }
        guard let id = Launcher.sessionID(in: created.output) else {
            fail("Rex did not report the new session's id.", created.output)
            return
        }
        show(id)
    }

    /// Selecting can fail while the session runs fine (no app client, a stale one beside the live one, Remote
    /// Control off), so Rex comes forward regardless and the alert says why the session isn't on top.
    private static func show(_ sessionID: String) {
        let client = Launcher.appClientID(in: Shell.run(Launcher.rexClients()).output)
        let selected = Shell.run(Launcher.rexSelect(sessionID: sessionID, client: client))
        guard selected.status != 0 else { return }
        // The alert first (it is modal), then Rex, so the explanation is not left behind Rex's window.
        fail("The session is running in Rex, but Fragments could not bring it to the front.", selected.output)
        if let rex = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.superlogical.rex") {
            NSWorkspace.shared.openApplication(at: rex, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private static func write(_ contents: String, for fragment: Fragment, store: FragmentStore) -> URL? {
        do {
            return try store.writeScript(contents, for: fragment)
        } catch {
            fail("Could not write the session script.", error.localizedDescription)
            return nil
        }
    }

    @discardableResult
    private static func check(_ result: (status: Int32, output: String), _ message: String) -> Bool {
        guard result.status != 0 else { return true }
        fail(message, result.output)
        return false
    }

    static func fail(_ message: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }
}
