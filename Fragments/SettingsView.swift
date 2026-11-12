import SwiftUI

struct SettingsView: View {
    @AppStorage(Prefs.fragmentsDir) private var fragmentsDir = Prefs.Default.fragmentsDir
    @AppStorage(Prefs.newHotKey) private var newHotKey = Prefs.Default.newHotKey
    @AppStorage(Prefs.listHotKey) private var listHotKey = Prefs.Default.listHotKey
    @AppStorage(Prefs.dictation) private var dictation = true

    var body: some View {
        Form {
            Section("Fragments") {
                TextField("Folder", text: $fragmentsDir)
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
