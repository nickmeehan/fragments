import XCTest

/// End-to-end flows against the real app: launch → type → chord → files and sessions appear.
/// Runs with a temp fragments folder, dictation off and action choices in memory, so no user data, preference or
/// Wispr Flow is touched.
final class CaptureFlowTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        continueAfterFailure = false
        folder = FileManager.default.temporaryDirectory.appending(path: "fragments-ui-\(UUID())")
    }

    private func launch(arguments: [String] = ["--capture"], defaults: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FRAGMENTS_DIR"] = folder.path
        app.launchEnvironment["FRAGMENTS_NO_DICTATION"] = "1"
        app.launchEnvironment["FRAGMENTS_CHOICES_IN_MEMORY"] = "1"
        // `-key value` pairs land in UserDefaults' argument domain, overriding Settings for this launch.
        app.launchArguments = arguments + defaults.flatMap { ["-\($0.key)", $0.value] }
        app.launch()
        return app
    }

    private func waitForMarkdown(timeout: TimeInterval = 5) -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
                .filter { $0.hasSuffix(".md") }
            if !files.isEmpty { return files }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return []
    }

    /// Saves a PNG of the app's windows when FRAGMENTS_SHOT names a path (pass via TEST_RUNNER_FRAGMENTS_SHOT).
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        guard let base = ProcessInfo.processInfo.environment["FRAGMENTS_SHOT"] else { return }
        try? app.screenshot().pngRepresentation.write(to: URL(filePath: "\(base)-\(name).png"))
    }

    func testKeepWritesMarkdown() throws {
        let app = launch()
        let editor = app.textViews["draft"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("hello from the ui test")
        snapshot(app, "capture")
        editor.typeKey(.return, modifierFlags: .command)

        let files = waitForMarkdown()
        XCTAssertEqual(files.count, 1, "expected one fragment in \(folder.path)")
        let contents = try String(contentsOf: folder.appending(path: files[0]), encoding: .utf8)
        XCTAssertTrue(contents.contains("hello from the ui test"))
        XCTAssertTrue(contents.contains("action: keep"))
        XCTAssertFalse(editor.exists, "panel should close after keep")
    }

    func testListShowsFragmentsWithHints() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (index, text) in ["first thought", "second thought"].enumerated() {
            try "---\nid: 20260101-00000\(index)-0000\naction: keep\n---\n\n\(text)\n"
                .write(to: folder.appending(path: "20260101-00000\(index)-0000.md"), atomically: true, encoding: .utf8)
        }
        let app = launch(arguments: ["--list"])
        XCTAssertTrue(app.staticTexts["second thought"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["first thought"].exists)
        snapshot(app, "list")
        app.typeKey("s", modifierFlags: [])  // hint "s" = second row = the older fragment
        let editor = app.textViews["draft"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.value as? String, "first thought")
        snapshot(app, "detail")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["second thought"].waitForExistence(timeout: 3))
    }

    /// ⌘⇧↩ must record the session in the fragment and write the script Rex will run. Rex itself may be absent
    /// on the test machine; the app then shows an alert, which the test dismisses.
    func testClaudeChordWritesSessionScript() throws {
        let app = launch(defaults: ["projectFolder": folder.path, "effort": "high"])
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let editor = app.textViews["draft"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("start an investigation")
        editor.typeKey(.return, modifierFlags: [.command, .shift])

        let files = waitForMarkdown()
        XCTAssertEqual(files.count, 1)
        let id = String(files[0].dropLast(3))
        let contents = try String(contentsOf: folder.appending(path: files[0]), encoding: .utf8)
        XCTAssertTrue(contents.contains("action: claude"))
        // The session is the Claude session id; Rex's label is built from the fragment id, not stored.
        let session = contents.split(separator: "\n").first { $0.hasPrefix("session: ") }?.dropFirst(9)
        XCTAssertNotNil(session.flatMap { UUID(uuidString: String($0)) }, "session should be a UUID in \(contents)")
        XCTAssertFalse(contents.contains("claude_session"))

        let script = folder.appending(path: ".sessions/\(id).sh")
        XCTAssertTrue(FileManager.default.fileExists(atPath: script.path))
        XCTAssertTrue(try String(contentsOf: script, encoding: .utf8).contains("'--effort' 'high'"))

        let alert = app.dialogs.firstMatch
        if alert.waitForExistence(timeout: 2) { alert.buttons.firstMatch.click() }
    }

    // MARK: Actions

    /// Writes an action into the temp folder's `actions/`, where the app compiles it at launch.
    private func addAction(_ id: String, _ source: String) throws {
        let directory = folder.appending(path: "actions/\(id)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try source.write(to: directory.appending(path: "\(id.capitalized).swift"), atomically: true, encoding: .utf8)
        addTeardownBlock {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            try? FileManager.default.removeItem(at: caches.appending(path: "Fragments/actions/yours/\(id)"))
        }
    }

    /// A run action that writes what it was sent, with its one setting in front, to `echo.txt` in the temp folder.
    private func addEcho() throws {
        try addAction(
            "echo",
            """
            import Foundation
            import FragmentsAction

            @main
            struct Echo: RunAction {
                static let name = "Echo"
                static let chord: Chord = "cmd+e"

                @Setting("Prefix", placeholder: "none") var prefix: String?

                func run(_ fragment: Fragment) throws {
                    try ((prefix ?? "") + fragment.text)
                        .write(toFile: "\(folder.path)/echo.txt", atomically: true, encoding: .utf8)
                }
            }
            """)
    }

    private func waitForFile(_ name: String, containing text: String, timeout: TimeInterval = 15) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let contents = try? String(contentsOf: folder.appending(path: name), encoding: .utf8),
                contents.contains(text)
            {
                return true
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    /// ⌘K lists the kickoffs that are on; typing filters and ↩ sends through the action's own path.
    func testCommandKSendsWithAKickoff() throws {
        try addEcho()
        let app = launch()
        let editor = app.textViews["draft"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("sent from kickoffs")
        editor.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Echo"].waitForExistence(timeout: 90), "Echo should compile and be listed")
        snapshot(app, "kickoffs")
        app.textFields.firstMatch.typeText("ech")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForFile("echo.txt", containing: "sent from kickoffs"))
        let fragment = try XCTUnwrap(waitForMarkdown().first)
        XCTAssertTrue(
            try String(contentsOf: folder.appending(path: fragment), encoding: .utf8).contains("action: echo"))
    }

    /// ⌘, in the list: space turns an action off and on, r refuses a taken chord and takes a free one, and ↩ edits a
    /// setting that then reaches the action. Choices stay in memory for this launch, never in your preferences.
    func testCommandCommaManagesActions() throws {
        try addEcho()
        let app = launch(arguments: ["--list"])
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Actions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Echo"].waitForExistence(timeout: 90), "Echo should compile and be listed")
        app.typeKey("j", modifierFlags: [])  // Cowork is first, bundled; Echo is yours
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(app.staticTexts["off"].waitForExistence(timeout: 3), "space should turn Echo off")
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(app.staticTexts["off"].waitForNonExistence(timeout: 3), "space again should turn it back on")

        app.typeKey("r", modifierFlags: [])
        XCTAssertTrue(app.staticTexts["press a ⌘ chord…"].waitForExistence(timeout: 3))
        app.typeKey(.return, modifierFlags: [.command, .option])
        XCTAssertTrue(app.staticTexts["⌘⌥↩ is Cowork's. Press another."].waitForExistence(timeout: 3))
        snapshot(app, "actions-taken")
        app.typeKey("e", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.staticTexts["⌘⇧E"].waitForExistence(timeout: 3), "a free chord should be taken")

        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Prefix"].waitForExistence(timeout: 3))
        app.typeKey(.return, modifierFlags: [])
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("pre-")
        snapshot(app, "setting-editing")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["pre-"].waitForExistence(timeout: 3))

        // Both reach the action: back to the list, n for a new fragment, and the new chord sends it with the prefix.
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("n", modifierFlags: [])
        let editor = app.textViews["draft"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("echoed")
        editor.typeKey("e", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForFile("echo.txt", containing: "pre-echoed"))
    }

    /// A launch action's start returns a session the fragment keeps; ↩ on that fragment in the list attaches.
    func testLaunchActionStartsThenAttachesFromTheList() throws {
        try addAction(
            "ticket",
            """
            import Foundation
            import FragmentsAction

            @main
            struct Ticket: LaunchAction {
                static let name = "Ticket"
                static let chord: Chord = "cmd+t"

                func start(_ fragment: Fragment) throws -> Session {
                    Session(id: "T-1")
                }

                func attach(_ fragment: Fragment, to session: Session) throws {
                    try "attach \\(session.id)"
                        .write(toFile: "\(folder.path)/attached.txt", atomically: true, encoding: .utf8)
                }
            }
            """)
        var app = launch()
        let editor = app.textViews["draft"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("file a ticket")
        editor.typeKey("k", modifierFlags: .command)  // wait in ⌘K until Ticket has compiled
        XCTAssertTrue(app.staticTexts["Ticket"].waitForExistence(timeout: 90), "Ticket should compile and be listed")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeKey("t", modifierFlags: .command)

        let fragment = try XCTUnwrap(waitForMarkdown().first)
        XCTAssertTrue(waitForFile(fragment, containing: "session: T-1"), "the session should be saved in the fragment")
        app = launch(arguments: ["--list"])
        XCTAssertTrue(app.staticTexts["file a ticket"].waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForFile("attached.txt", containing: "attach T-1"))
    }

    /// The global hotkey is the real entry point: nothing else is frontmost when it fires.
    func testGlobalHotkeyOpensCapture() throws {
        let app = launch(arguments: [])
        XCTAssertFalse(app.textViews["draft"].exists)
        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
        app.typeKey(" ", modifierFlags: .option)
        XCTAssertTrue(app.textViews["draft"].waitForExistence(timeout: 5))
    }
}
