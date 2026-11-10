import AppKit
import FragmentsCore

/// `--snapshot DIR`: show each panel mode, image our own window into DIR and quit. Lets an agent look at the UI
/// without a Screen Recording grant, which macOS waives for a process imaging its own windows.
@MainActor
enum Snapshot {
    static let sampleText =
        "Remind me to send the Q4 invoice to Arbor on Monday. Also look into why the staging deploy got slow."

    static func run(into directory: URL, panel: PanelController) {
        Task {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                panel.showCapture(text: sampleText)
                try await capture("capture", into: directory, panel: panel)
                panel.showList()
                try await capture("list", into: directory, panel: panel)
                _ = panel.model.handle(.enter([]))
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
