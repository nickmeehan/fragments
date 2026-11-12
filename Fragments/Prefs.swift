import Foundation
import FragmentsCore

/// Settings keys shared by SettingsView (@AppStorage) and the launch code. Environment variables override
/// the folder, dictation and action choices so tests and scripts never touch real data, preferences or Wispr Flow.
enum Prefs {
    static let fragmentsDir = "fragmentsDir"
    static let newHotKey = "newHotKey"
    static let listHotKey = "listHotKey"
    static let dictation = "dictation"
    /// What you chose per action in ⌘, Actions, as JSON: `{"remind": {"on": true}}`.
    static let actions = "actions"

    enum Default {
        static let fragmentsDir = "~/.fragments"
        static let newHotKey = "option+space"
        static let listHotKey = "option+shift+space"
    }

    static func register() {
        UserDefaults.standard.register(defaults: [
            fragmentsDir: Default.fragmentsDir, newHotKey: Default.newHotKey, listHotKey: Default.listHotKey,
            dictation: true, actions: "{}",
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

    /// `FRAGMENTS_CHOICES_IN_MEMORY` (UI tests): choices last only for this launch, so a test never changes yours.
    @MainActor private static var choicesInMemory: String? =
        ProcessInfo.processInfo.environment["FRAGMENTS_CHOICES_IN_MEMORY"] == nil ? nil : "{}"

    @MainActor static var actionChoices: [String: ActionChoice] {
        let json = choicesInMemory ?? string(actions)
        return (try? ActionWire.decoder.decode([String: ActionChoice].self, from: Data(json.utf8))) ?? [:]
    }

    /// Changes one action's choices and stores them; ActionHost re-resolves on the defaults change.
    @MainActor static func updateChoice(for id: String, _ change: (inout ActionChoice) -> Void) {
        var choices = actionChoices
        var choice = choices[id] ?? ActionChoice()
        change(&choice)
        choices[id] = choice
        guard let json = try? ActionWire.encoder.encode(choices) else { return }
        let text = String(decoding: json, as: UTF8.self)
        guard choicesInMemory == nil else {
            choicesInMemory = text
            // What a real write would trigger: AppDelegate re-resolves the actions.
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
            return
        }
        UserDefaults.standard.set(text, forKey: actions)
    }

    /// Settings → Claude Code, from before Rex was an action: each old key and the Rex setting it became.
    private static let claudeCode = [
        "projectFolder": "folder", "model": "model", "effort": "effort", "permissionMode": "permissionMode",
    ]

    /// Moves what you set in Settings → Claude Code into Rex's settings, once: the old key goes after. With choices
    /// in memory (UI tests) it copies into memory and removes nothing, so a test can set them without touching yours.
    @MainActor static func moveClaudeCodeSettingsToRex() {
        for (old, setting) in claudeCode {
            guard let value = UserDefaults.standard.string(forKey: old), !value.isEmpty else { continue }
            updateChoice(for: "rex") { $0.apply(.setting(key: setting, value: value)) }
            if choicesInMemory == nil { UserDefaults.standard.removeObject(forKey: old) }
        }
    }
}
