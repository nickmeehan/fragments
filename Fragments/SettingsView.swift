import AppKit
import FragmentsCore
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
            ActionsSection(host: ActionHost.shared)
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

/// Settings → Actions: every action found, bundled or yours. The switch decides what capture offers, the chord can
/// be rebound, and the rows under it come from the action's own `@Setting` properties.
private struct ActionsSection: View {
    let host: ActionHost

    var body: some View {
        Section("Actions") {
            ForEach(host.actions) { action in
                ActionRow(action: action)
            }
            HStack {
                Text("Each folder in \(ActionHost.yoursDirectory.path.abbreviatingTilde) with a Swift action is yours.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reveal in Finder") { host.revealYours() }
            }
        }
    }
}

private struct ActionRow: View {
    let action: ActionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: on) {
                HStack {
                    Text(action.name)
                    Text(action.chord?.symbols ?? "").foregroundStyle(.secondary)
                }
            }
            .disabled(action.manifest == nil)
            Text(caption).font(.caption).foregroundStyle(.secondary)
            if let problem = action.problem {
                Text(problem).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if let manifest = action.manifest {
                DisclosureGroup("Chord and settings") {
                    TextField("Chord", text: chord, prompt: Text(manifest.chord))
                    ForEach(manifest.settings, id: \.key) { spec in
                        SettingField(actionID: action.id, spec: spec, stored: action.settings[spec.key])
                    }
                }
            }
        }
    }

    private var caption: String {
        let origin = action.origin == .bundled ? "Bundled" : "Yours"
        return action.isBuilding ? "\(origin) · \(action.id) · compiling…" : "\(origin) · \(action.id)"
    }

    private var chord: Binding<String> {
        Binding(
            get: { Prefs.actionChoices[action.id]?.chord ?? "" },
            set: { written in Prefs.updateChoice(for: action.id) { $0.chord = written.isEmpty ? nil : written } })
    }

    /// Shows whether capture offers it; turning it on can still leave it off when its chord is taken, and the
    /// problem line says by what.
    private var on: Binding<Bool> {
        Binding(get: { action.on }, set: { on in Prefs.updateChoice(for: action.id) { $0.on = on } })
    }
}

/// One `@Setting`: a field, a switch, a menu or a folder, by its kind. Empty means the action's default.
private struct SettingField: View {
    let actionID: String
    let spec: SettingSpec
    let stored: String?

    var body: some View {
        switch spec.kind {
        case .text:
            TextField(spec.label, text: value, prompt: Text(spec.placeholder ?? spec.defaultValue ?? ""))
        case .toggle:
            Toggle(spec.label, isOn: Binding(get: { current == "true" }, set: { save(String($0)) }))
        case .choice:
            Picker(spec.label, selection: Binding(get: { current }, set: { save($0) })) {
                if spec.optional { Text("default").tag("") }
                ForEach(spec.choices ?? [], id: \.self) { Text($0).tag($0) }
            }
        case .folder:
            HStack {
                TextField(spec.label, text: value, prompt: Text(spec.defaultValue ?? ""))
                Button("Choose…", action: chooseFolder)
            }
        }
    }

    private var current: String { stored ?? spec.defaultValue ?? "" }

    private var value: Binding<String> {
        Binding(get: { stored ?? "" }, set: { save($0) })
    }

    private func save(_ value: String) {
        Prefs.updateChoice(for: actionID) { choice in
            var settings = choice.settings ?? [:]
            settings[spec.key] = value.isEmpty ? nil : value
            choice.settings = settings.isEmpty ? nil : settings
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        save(url.path.abbreviatingTilde)
    }
}

extension String {
    fileprivate var abbreviatingTilde: String { (self as NSString).abbreviatingWithTildeInPath }
}
