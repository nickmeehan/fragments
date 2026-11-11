import SwiftUI

struct SettingsView: View {
    @AppStorage(Prefs.fragmentsDir) private var fragmentsDir = Prefs.Default.fragmentsDir
    @AppStorage(Prefs.projectFolder) private var projectFolder = Prefs.Default.projectFolder
    @AppStorage(Prefs.model) private var model = ""
    @AppStorage(Prefs.effort) private var effort = ""
    @AppStorage(Prefs.permissionMode) private var permissionMode = ""
    @AppStorage(Prefs.newHotKey) private var newHotKey = Prefs.Default.newHotKey
    @AppStorage(Prefs.listHotKey) private var listHotKey = Prefs.Default.listHotKey
    @AppStorage(Prefs.dictation) private var dictation = true

    var body: some View {
        Form {
            Section("Fragments") {
                TextField("Folder", text: $fragmentsDir)
            }
            Section("Claude Code") {
                TextField("Project folder", text: $projectFolder)
                TextField("Model", text: $model, prompt: Text("default"))
                Picker("Effort", selection: $effort) {
                    Text("default").tag("")
                    ForEach(["low", "medium", "high", "xhigh", "max"], id: \.self) { Text($0).tag($0) }
                }
                TextField("Permission mode", text: $permissionMode, prompt: Text("default"))
                Text("Sessions open in Rex (Superlogical). Remote Control must be on in Rex's settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Hotkeys") {
                TextField("New fragment", text: $newHotKey)
                TextField("Fragments list", text: $listHotKey)
                Text("Modifiers: cmd, shift, option, control. Keys: letters, digits, space, f1–f12.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Dictation") {
                Toggle("Start Wispr Flow hands-free when a fragment opens", isOn: $dictation)
                Text("Uses Wispr Flow's wispr-flow://start-hands-free URL, so Wispr Flow must be running.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}
