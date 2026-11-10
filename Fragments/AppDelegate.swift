import AppKit
import FragmentsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) lazy var panel = PanelController()
    private var hotKeys: [HotKey] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()
        registerHotKeys()
        NotificationCenter.default.addObserver(
            self, selector: #selector(prefsChanged), name: UserDefaults.didChangeNotification, object: nil)
        // Launch arguments open the panel without a hotkey: UI tests and `bin/run --capture`.
        let arguments = CommandLine.arguments
        if arguments.contains("--capture") { panel.showCapture() }
        if arguments.contains("--list") { panel.showList() }
        if let i = arguments.firstIndex(of: "--snapshot"), i + 1 < arguments.count {
            Snapshot.run(into: URL(filePath: arguments[i + 1]), panel: panel)
        }
    }

    /// `fragments://new?text=…` and `fragments://list`, for scripts and other launchers.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let text =
                URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "text" }?.value ?? ""
            switch url.host {
            case "new": panel.showCapture(text: text)
            case "list": panel.showList()
            default: break
            }
        }
    }

    @objc private func prefsChanged() {
        registerHotKeys()
    }

    private func registerHotKeys() {
        for hotKey in hotKeys { hotKey.unregister() }
        let bindings: [(String, () -> Void)] = [
            (Prefs.newHotKey, { [weak self] in self?.panel.showCapture() }),
            (Prefs.listHotKey, { [weak self] in self?.panel.showList() }),
        ]
        hotKeys = bindings.compactMap { key, action in
            KeyCombo(Prefs.string(key)).flatMap { HotKey($0, action: action) }
        }
    }
}
