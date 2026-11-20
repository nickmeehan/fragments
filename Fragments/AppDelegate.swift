import AppKit
import FragmentsCore
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private(set) lazy var panel = PanelController()
    private var hotKeys: [HotKey] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        quitOtherCopies()
        Prefs.register()
        Prefs.moveClaudeCodeSettingsToRex()
        registerHotKeys()
        ActionHost.shared.refresh()  // compile what changed now, so the first capture has its actions
        UNUserNotificationCenter.current().delegate = self
        Updater.shared.start()
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

    /// Clicking the update notification opens the update view. Clicked after Fragments quit, it relaunches the app,
    /// which checks again first.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        await showUpdate()
    }

    /// Shown even while Fragments is the active app, as it is whenever the panel is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    private func showUpdate() async {
        if Updater.shared.available == nil { await Updater.shared.check() }
        if let update = Updater.shared.available { panel.showUpdate(update) }
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

    /// The copy you launched last wins, so a release and a `bin/run` build never fight over the hotkey. A copy on a
    /// test folder (`FRAGMENTS_DIR`: UI tests, `bin/renders`) leaves yours running.
    private func quitOtherCopies() {
        guard ProcessInfo.processInfo.environment["FRAGMENTS_DIR"] == nil, let id = Bundle.main.bundleIdentifier
        else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id).map(\.processIdentifier)
            .filter { $0 != getpid() }
        // A signal, like `bin/run`'s pkill: NSRunningApplication.terminate() is an Apple Event, which needs a grant.
        for pid in others { kill(pid, SIGTERM) }
        // Their hotkeys free up only once they've exited.
        let deadline = Date.now + 2
        while others.contains(where: { kill($0, 0) == 0 }), Date.now < deadline { usleep(20_000) }
    }

    @objc private func prefsChanged() {
        registerHotKeys()
        ActionHost.shared.resolve()
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
