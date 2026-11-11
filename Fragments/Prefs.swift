import Foundation
import FragmentsCore

/// Settings keys shared by SettingsView (@AppStorage) and the launch code. Environment variables override
/// the folder and dictation so tests and scripts never touch real data or Wispr Flow.
enum Prefs {
    static let fragmentsDir = "fragmentsDir"
    static let projectFolder = "projectFolder"
    static let model = "model"
    static let effort = "effort"
    static let permissionMode = "permissionMode"
    static let newHotKey = "newHotKey"
    static let listHotKey = "listHotKey"
    static let dictation = "dictation"
    /// What you chose per action in Settings → Actions, as JSON: `{"remind": {"on": true}}`.
    static let actions = "actions"

    enum Default {
        static let fragmentsDir = "~/.fragments"
        static let projectFolder = "~"
        static let newHotKey = "option+space"
        static let listHotKey = "option+shift+space"
    }

    static func register() {
        UserDefaults.standard.register(defaults: [
            fragmentsDir: Default.fragmentsDir, projectFolder: Default.projectFolder,
            model: "", effort: "", permissionMode: "",
            newHotKey: Default.newHotKey, listHotKey: Default.listHotKey, dictation: true, actions: "{}",
        ])
    }

    static func string(_ key: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? ""
    }

    static var fragmentsDirectory: URL {
        let path = ProcessInfo.processInfo.environment["FRAGMENTS_DIR"] ?? string(fragmentsDir)
        return URL(filePath: (path as NSString).expandingTildeInPath)
    }

    static var dictationEnabled: Bool {
        ProcessInfo.processInfo.environment["FRAGMENTS_NO_DICTATION"] == nil
            && UserDefaults.standard.bool(forKey: dictation)
    }

    static var actionChoices: [String: ActionChoice] {
        (try? ActionWire.decoder.decode([String: ActionChoice].self, from: Data(string(actions).utf8))) ?? [:]
    }

    /// Changes one action's choices and stores them; ActionHost re-resolves on the defaults change.
    static func updateChoice(for id: String, _ change: (inout ActionChoice) -> Void) {
        var choices = actionChoices
        var choice = choices[id] ?? ActionChoice()
        change(&choice)
        choices[id] = choice
        guard let json = try? ActionWire.encoder.encode(choices) else { return }
        UserDefaults.standard.set(String(decoding: json, as: UTF8.self), forKey: actions)
    }

    static var launch: LaunchPrefs {
        LaunchPrefs(
            folder: (string(projectFolder) as NSString).expandingTildeInPath, model: string(model),
            effort: string(effort), permissionMode: string(permissionMode))
    }
}
