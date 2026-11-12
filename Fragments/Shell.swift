import Foundation
import FragmentsCore
import os

/// Runs an argv through a login shell so xcrun, the actions and whatever they call resolve from the user's real PATH.
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
        process.arguments = ["-lc", LoginShell.command(argv)]
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
