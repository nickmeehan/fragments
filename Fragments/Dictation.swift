import AppKit

/// Starts Wispr Flow's hands-free dictation through its URL scheme. Wispr's native helper reads the fn key at the
/// HID layer, so synthesized key events never reach it; the URL needs no Accessibility grant either.
@MainActor
enum Dictation {
    static let startURL = URL(string: "wispr-flow://start-hands-free")!

    static func start() {
        guard Prefs.dictationEnabled else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false  // keep keyboard focus on our editor so Wispr types into it
        NSWorkspace.shared.open(startURL, configuration: configuration)
    }
}
