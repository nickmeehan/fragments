import FragmentsCore
import SwiftUI

struct PanelRoot: View {
    var model: AppModel

    var body: some View {
        Group {
            switch model.mode {
            case .capture: CaptureView(model: model)
            case .list: ListView(model: model)
            case .detail: DetailView(model: model)
            case .kickoffs: KickoffsView(model: model)
            case .actions: ActionsView(model: model)
            case .actionSettings(let id): ActionSettingsView(model: model, id: id)
            case .actionProblem(let id): ActionProblemView(model: model, id: id)
            }
        }
        .panelChrome()
    }
}

extension View {
    /// The floating panel's shape; every mode draws inside it.
    func panelChrome() -> some View {
        frame(width: 680, height: 400)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
    }
}

/// A fragment's own words, wherever the panel shows them. Change the face here and every screen follows.
extension Font {
    /// What you write: capture and detail.
    static let fragment = Font.system(size: 17, weight: .light, design: .rounded)
    /// A fragment's heading in the list, at the list's size.
    static let fragmentHeading = Font.system(.body, design: .rounded)
}

struct CaptureView: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Editor(text: $model.draft, focused: $focused)
            // When the actions don't fit on one line the last ones drop off; ⌘K lists them all.
            ViewThatFits(in: .horizontal) {
                ForEach((0...model.actions.filter(\.on).count).reversed(), id: \.self) { limit in
                    Footer(model.captureHints(actionLimit: limit))
                }
            }
        }
        .padding(16)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

struct DetailView: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Editor(text: $model.draft, focused: $focused)
            Footer(["esc back (saves)"])
        }
        .padding(16)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

struct ListView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.fragments.isEmpty {
                Spacer()
                Text("No fragments yet. Press ⌘N to capture one.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                FilterField(
                    prompt: "Filter by title or text…",
                    text: Binding(get: { model.listFilter }, set: { model.setListFilter($0) }),
                    focus: !model.isTitling)
                if model.shown.isEmpty {
                    Text("Nothing matches “\(model.listFilter)”.").foregroundStyle(.secondary).padding(8)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(model.shown.enumerated()), id: \.element.id) { index, fragment in
                                Row(
                                    fragment: fragment, icon: model.icon(for: fragment),
                                    jump: AppModel.jumpChords.indices.contains(index)
                                        ? AppModel.jumpChords[index].symbols : nil,
                                    selected: index == model.selection,
                                    title: model.isTitling && index == model.selection ? $model.titleDraft : nil
                                )
                                .id(fragment.id)
                            }
                        }
                    }
                    .onChange(of: model.selection) { _, index in
                        if model.shown.indices.contains(index) { proxy.scrollTo(model.shown[index].id) }
                    }
                }
            }
            Footer(footer)
        }
        .padding(16)
    }

    private var footer: [String] {
        if model.isTitling { return ["type a title", "↩ save", "esc cancel"] }
        return [
            "↑↓ move", "↩ open", "⌘1–9 jump", "⌘T title", "⌘N new", "⌘D trash", "⌘, actions",
            model.listFilter.isEmpty ? "esc close" : "esc clear",
        ]
    }
}

private struct Row: View {
    let fragment: Fragment
    let icon: String
    /// The chord that opens this row, ⌘1…⌘9; nil past the ninth.
    let jump: String?
    let selected: Bool
    /// Set while ⌘T edits this row's title.
    let title: Binding<String>?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(jump ?? "⌘1")
                .font(.system(.caption, design: .monospaced).bold())
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                // Past ⌘9 the badge keeps its space unseen, so every row's icon and title still line up.
                .opacity(jump == nil ? 0 : 1)
                .accessibilityHidden(jump == nil)
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)  // as in ⌘K, so every title starts at the same place whatever the icon
            if let title {
                // The first line is the placeholder: what the row says without a title.
                TextField(fragment.firstLine, text: title)
                    .font(.fragmentHeading)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onAppear { DispatchQueue.main.async { focused = true } }
                    .accessibilityIdentifier("title")
            } else {
                Text(fragment.heading).font(.fragmentHeading).lineLimit(1)
            }
            Spacer()
            Text(fragment.createdAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(selected ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct Editor: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        TextEditor(text: $text)
            .font(.fragment)
            .lineSpacing(2)
            .scrollContentBackground(.hidden)
            .focused(focused)
            .accessibilityIdentifier("draft")
    }
}

private struct Footer: View {
    let items: [String]

    init(_ items: [String]) {
        self.items = items
    }

    var body: some View {
        Text(items.joined(separator: "   ·   "))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: Kickoffs and actions

/// ⌘K in capture: every kickoff that is on, filtered as you type. ↩ sends the draft with the selected one.
struct KickoffsView: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FilterField(
                prompt: "Send with…", text: Binding(get: { model.kickoffFilter }, set: { model.setKickoffFilter($0) }))
            if model.kickoffs.isEmpty {
                Text("Nothing on matches “\(model.kickoffFilter)”.").foregroundStyle(.secondary).padding(8)
            }
            VStack(spacing: 2) {
                ForEach(Array(model.kickoffs.enumerated()), id: \.element.id) { index, kickoff in
                    LineRow(
                        name: kickoff.name, icon: kickoff.icon, match: model.kickoffFilter,
                        selected: index == model.kickoffSelection
                    ) {
                        Text(kickoff.chord.symbols).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            Footer(["type to filter", "↑↓ move", "↩ send", "esc back to the draft"])
        }
        .padding(16)
    }
}

/// The field at the top of ⌘K and of the list. It takes focus as it appears, and again when `focus` turns back on
/// (after the list's title field), so typing lands in it.
private struct FilterField: View {
    let prompt: String
    let text: Binding<String>
    var focus = true
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .focused($focused)
                .accessibilityIdentifier("filter")
        }
        .font(.system(size: 17))
        .padding(.horizontal, 8)
        .onAppear { if focus { DispatchQueue.main.async { focused = true } } }
        .onChange(of: focus) { _, on in if on { DispatchQueue.main.async { focused = true } } }
    }
}

/// ⌘, in the fragments list: every action, on or off, bundled or yours.
struct ActionsView: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions").font(.headline).padding(.horizontal, 8)
            if model.actions.isEmpty {
                Spacer()
                Text("No actions yet. Press o to open the folder yours go in.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                            let selected = index == model.actionSelection
                            LineRow(
                                name: action.name, icon: action.icon, on: action.on,
                                subtitle: action.origin == .bundled ? "Bundled" : "Yours", selected: selected
                            ) {
                                trailing(action, recording: selected && model.isRecording)
                            }
                            .id(action.id)
                        }
                    }
                }
                .onChange(of: model.actionSelection) { _, index in
                    if model.actions.indices.contains(index) { proxy.scrollTo(model.actions[index].id) }
                }
            }
            Footer(footer)
        }
        .padding(16)
    }

    private var footer: [String] {
        guard let action = model.selectedAction else { return ["o open folder", "esc back"] }
        if model.isRecording { return ["press the new chord", "esc keeps \(action.chord?.symbols ?? "none")"] }
        return [
            "j/k move", "space on/off", "r rebind", action.manifest == nil ? "↩ why" : "↩ settings", "o open folder",
            "esc back",
        ]
    }

    @ViewBuilder
    private func trailing(_ action: ActionInfo, recording: Bool) -> some View {
        if recording {
            Text(model.recordingProblem ?? "press a ⌘ chord…")
                .font(.caption)
                .foregroundStyle(model.recordingProblem == nil ? Color.accentColor : Color.red)
        } else if action.isBuilding {
            Text("compiling…").font(.caption).foregroundStyle(.secondary)
        } else if action.didNotCompile {
            Label("didn't compile", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
        } else if let problem = action.problem {
            Text(problem).font(.caption).foregroundStyle(.red).lineLimit(1)
        } else {
            Text(action.chord?.symbols ?? "").font(.caption).foregroundStyle(.secondary)
            Text(action.on ? "on" : "off").font(.caption).foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
    }
}

/// ↩ on an action: the rows its `@Setting` properties declare.
struct ActionSettingsView: View {
    @Bindable var model: AppModel
    let id: String
    @FocusState private var focused: Bool

    private var action: ActionInfo? { model.actions.first { $0.id == id } }
    private var specs: [SettingSpec] { action?.manifest?.settings ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(action?.name ?? id).font(.headline)
                Text((action?.origin == .bundled ? "Bundled" : "Yours") + " · " + id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            if specs.isEmpty {
                Spacer()
                Text("\(action?.name ?? id) has no settings.").foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            VStack(spacing: 2) {
                ForEach(Array(specs.enumerated()), id: \.element.key) { index, spec in
                    let selected = index == model.settingSelection
                    HStack(spacing: 10) {
                        Text(spec.label)
                        Spacer()
                        value(spec, editing: selected && model.isEditingSetting)
                    }
                    .padding(8)
                    .background(
                        selected ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            Spacer(minLength: 0)
            Footer(footer)
        }
        .padding(16)
    }

    private var footer: [String] {
        if model.isEditingSetting { return ["type", "↩ save", "esc cancel"] }
        guard specs.indices.contains(model.settingSelection) else { return ["esc back to actions"] }
        let enter =
            switch specs[model.settingSelection].kind {
            case .text, .folder: "↩ edit"
            case .toggle: "↩ switch"
            case .choice: "↩ next value"
            }
        return ["j/k move", enter, "esc back to actions"]
    }

    @ViewBuilder
    private func value(_ spec: SettingSpec, editing: Bool) -> some View {
        let stored = action?.settings[spec.key]
        switch spec.kind {
        case .toggle:
            Text((stored ?? spec.defaultValue) == "true" ? "on" : "off").foregroundStyle(.secondary)
        case .choice:
            HStack(spacing: 4) {
                Text((stored ?? spec.defaultValue).flatMap { $0.isEmpty ? nil : $0 } ?? "default")
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
            .foregroundStyle(.secondary)
        case .text, .folder:
            Group {
                if editing {
                    TextField(spec.placeholder ?? "", text: $model.settingDraft)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .onAppear { DispatchQueue.main.async { focused = true } }
                } else {
                    Text(stored ?? spec.placeholder ?? spec.defaultValue ?? "")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(width: 220, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(editing ? Color.accentColor : Color.secondary.opacity(0.3)))
        }
    }
}

/// ↩ on an action that didn't compile: the compiler's words, and the way to its folder.
struct ActionProblemView: View {
    var model: AppModel
    let id: String

    var body: some View {
        let action = model.actions.first { $0.id == id }
        VStack(alignment: .leading, spacing: 8) {
            Text(action?.name ?? id).font(.headline).padding(.horizontal, 8)
            ScrollView {
                Text(action?.problem ?? "")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            Footer(["o open folder", "esc back to actions"])
        }
        .padding(16)
    }
}

/// A row in ⌘K or ⌘, Actions, drawn like a fragment's row in the list.
private struct LineRow<Trailing: View>: View {
    let name: String
    let icon: String
    var on = true
    var subtitle: String? = nil
    var match = ""
    let selected: Bool
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18)
            Text(highlighted).foregroundStyle(on ? .primary : .secondary)
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            trailing
        }
        .padding(8)
        .background(selected ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }

    /// The part of the name the filter matched, in bold.
    private var highlighted: AttributedString {
        var text = AttributedString(name)
        if !match.isEmpty, let range = text.range(of: match, options: .caseInsensitive) {
            text[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return text
    }
}
