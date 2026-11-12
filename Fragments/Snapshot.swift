import AppKit
import FragmentsCore

/// `--snapshot DIR`: walk the panel through each mode (capture, ⌘K, list, ⌘, Actions and every action's own view,
/// detail), image our own window into DIR and quit. Lets an agent look at the UI without a Screen Recording grant,
/// which macOS waives for a process imaging its own windows.
@MainActor
enum Snapshot {
    static let sampleText =
        "Remind me to send the Q4 invoice to Arbor on Monday. Also look into why the staging deploy got slow."

    static func run(into directory: URL, panel: PanelController) {
        Task {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                // The Actions views need the actions compiled; a first build takes a few seconds.
                for _ in 0..<600 where ActionHost.shared.isRefreshing { try await Task.sleep(for: .milliseconds(200)) }
                let model = panel.model
                panel.showCapture(text: sampleText)
                try await capture("capture", into: directory, panel: panel)
                _ = model.handle(.command(AppModel.kickoffsChord))
                try await capture("kickoffs", into: directory, panel: panel)
                model.setKickoffFilter("co")
                try await capture("kickoffs-filtered", into: directory, panel: panel)
                panel.showList()
                try await capture("list", into: directory, panel: panel)
                _ = model.handle(.command(AppModel.actionsChord))
                try await capture("actions", into: directory, panel: panel)
                _ = model.handle(.char("r", []))
                try await capture("actions-recording", into: directory, panel: panel)
                _ = model.handle(.escape)
                // Each action's settings, or why it didn't compile.
                for action in model.actions {
                    _ = model.handle(.enter([]))
                    try await capture("action-\(action.id)", into: directory, panel: panel)
                    if model.mode != .actions { _ = model.handle(.escape) }
                    _ = model.handle(.down)
                }
                panel.showList()
                _ = model.handle(.enter([]))
                try await capture("detail", into: directory, panel: panel)
                NSApp.terminate(nil)
            } catch {
                log("snapshot failed: \(error)", in: directory)
                exit(1)
            }
        }
    }

    private static func capture(_ name: String, into directory: URL, panel: PanelController) async throws {
        try await Task.sleep(for: .milliseconds(700))  // let the window server composite the new content
        // ponytail: CGWindowListCreateImage is deprecated, but ScreenCaptureKit prompts for Screen Recording
        // even for our own window. Switch when Apple offers a permission-free replacement.
        guard
            let image = CGWindowListCreateImage(
                .null, .optionIncludingWindow, CGWindowID(panel.windowNumber), [.boundsIgnoreFraming, .bestResolution])
        else { throw CocoaError(.featureUnsupported) }
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: directory.appending(path: "\(name).png"))
    }

    /// stderr is lost when the app is launched through `open`, so failures land next to the images.
    private static func log(_ line: String, in directory: URL) {
        try? Data((line + "\n").utf8).write(to: directory.appending(path: "error.txt"))
    }
}
