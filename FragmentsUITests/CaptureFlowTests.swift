import XCTest

/// End-to-end flows against the real app: launch → type → chord → files and sessions appear.
/// Runs with a temp fragments folder and dictation off, so no user data or Wispr Flow is touched.
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
        XCTAssertTrue(contents.contains("session: frag-\(id)"))

        let script = folder.appending(path: ".sessions/\(id).sh")
        XCTAssertTrue(FileManager.default.fileExists(atPath: script.path))
        XCTAssertTrue(try String(contentsOf: script, encoding: .utf8).contains("'--effort' 'high'"))

        let alert = app.dialogs.firstMatch
        if alert.waitForExistence(timeout: 2) { alert.buttons.firstMatch.click() }
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
