import Foundation
import Observation

/// The panel's whole state machine: capture → keep, launch or ⌘K; list → open, attach, trash or ⌘,; detail → edit;
/// Actions → on/off, rebind, settings. Pure state plus `Command`s for the app shell to perform, so every path runs
/// under `swift test`.
@MainActor @Observable
public final class AppModel {
    public enum Mode: Equatable, Sendable {
        case capture
        case list
        case detail(Fragment.ID)
        /// ⌘K in capture: every kickoff that is on, filtered as you type. The draft waits.
        case kickoffs
        /// ⌘, in the list: every action, on or off.
        case actions
        /// ↩ on an action: the settings it declares.
        case actionSettings(String)
        /// ↩ on an action that didn't compile: why.
        case actionProblem(String)
    }

    /// What the shell does after a keystroke.
    public enum Command: Equatable, Sendable {
        /// Not ours. Pass the event on, e.g. typing into the editor.
        case ignored
        case handled
        case close
        case startDictation
        case launch(Fragment)
        case attach(Fragment)
        /// Run an action's program on a saved fragment: `start`, or `attach` to a launch.
        case start(ActionRun)
        /// Store one edit to an action's choices in the `actions` preference.
        case choose(String, ActionChoice.Change)
        /// Show the folder your actions live in.
        case revealActions
    }

    /// One row of ⌘K.
    public struct Kickoff: Equatable, Sendable {
        public var id: String
        public var name: String
        public var chord: KeyCombo
        public var kind: ActionType
    }

    /// Built in: ⌘↩ keeps the thought and does nothing else.
    public static let keep = "keep"
    /// Rex keeps its own path until it becomes an action; the id stays what fragments on disk already say.
    public static let rex = "claude"
    public static let kickoffsChord = KeyCombo(modifiers: .command, key: "k")
    public static let actionsChord = KeyCombo(modifiers: .command, key: ",")
    private static let rexChord = KeyCombo(modifiers: [.command, .shift], key: "return")

    public private(set) var mode: Mode = .capture
    public var draft = ""
    public private(set) var fragments: [Fragment] = []
    public private(set) var selection = 0
    public private(set) var pendingHint = ""
    public var prefs: LaunchPrefs
    /// Every action found, on or off; the shell refreshes it when capture opens.
    public var actions: [ActionInfo] = []
    public let store: FragmentStore

    public private(set) var kickoffFilter = ""
    public private(set) var kickoffSelection = 0
    public private(set) var actionSelection = 0
    /// r was pressed on the selected action: the next ⌘ chord rebinds it.
    public private(set) var isRecording = false
    /// Why the chord just pressed while recording can't be used.
    public private(set) var recordingProblem: String?
    public private(set) var settingSelection = 0
    /// ↩ on a text or folder setting: typing goes into `settingDraft` until ↩ saves it or esc drops it.
    public private(set) var isEditingSetting = false
    public var settingDraft = ""

    public init(store: FragmentStore, prefs: LaunchPrefs) {
        self.store = store
        self.prefs = prefs
    }

    public var hints: [String] {
        HintLabels.labels(count: fragments.count)
    }

    /// The capture footer: keep, Rex, each action that is on, ⌘K, esc.
    public var captureHints: [String] {
        captureHints(actionLimit: nil)
    }

    /// The footer with only the first `actionLimit` actions, for when they don't all fit; ⌘K lists the rest.
    public func captureHints(actionLimit: Int?) -> [String] {
        let hints = actions.filter(\.on).map(\.hint)
        return ["⌘↩ keep", "⌘⇧↩ Rex"] + hints.prefix(actionLimit ?? hints.count) + ["⌘K all", "esc discard"]
    }

    /// What ⌘K offers: Rex, then every action that is on, narrowed to names containing the filter.
    public var kickoffs: [Kickoff] {
        let all =
            [Kickoff(id: AppModel.rex, name: "Rex", chord: AppModel.rexChord, kind: .launch)]
            + actions.compactMap { action in
                guard action.on, let chord = action.chord, let kind = action.kind else { return nil }
                return Kickoff(id: action.id, name: action.name, chord: chord, kind: kind)
            }
        guard !kickoffFilter.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(kickoffFilter) }
    }

    public var selectedAction: ActionInfo? {
        actions.indices.contains(actionSelection) ? actions[actionSelection] : nil
    }

    public func beginCapture(text: String = "") {
        mode = .capture
        draft = text
    }

    public func showList() {
        reload()
        selection = min(selection, max(fragments.count - 1, 0))
        pendingHint = ""
        mode = .list
    }

    public func reload() {
        fragments = (try? store.all()) ?? []
    }

    /// The ⌘K filter field writes here; a new filter starts again at the top.
    public func setKickoffFilter(_ text: String) {
        kickoffFilter = text
        kickoffSelection = 0
    }

    /// A launch action answered its start: keep the session on the fragment, so ↩ in the list comes back to it.
    public func started(_ id: Fragment.ID, session: Session) {
        // ponytail: reads the whole folder to find one file; a lookup by id if the folder ever gets large
        guard var fragment = (try? store.all())?.first(where: { $0.id == id }) else { return }
        fragment.session = session
        try? store.save(fragment)
        if mode == .list { reload() }
    }

    public func handle(_ key: Key) -> Command {
        switch mode {
        case .capture: return handleCapture(key)
        case .list: return handleList(key)
        case .detail(let id): return handleDetail(key, id: id)
        case .kickoffs: return handleKickoffs(key)
        case .actions: return isRecording ? handleRecording(key) : handleActions(key)
        case .actionSettings(let id): return isEditingSetting ? handleEditing(key, id: id) : handleSettings(key, id: id)
        case .actionProblem: return handleProblem(key)
        }
    }

    /// Saves the draft as a fragment. Nil when there is nothing worth saving.
    @discardableResult
    public func commit(action: String) -> Fragment? {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var fragment = Fragment(text: text, action: action)
        if action == AppModel.rex {
            fragment.session = Session(id: UUID().uuidString.lowercased(), folder: prefs.folder)
        }
        try? store.save(fragment)
        draft = ""
        return fragment
    }

    // MARK: Capture and ⌘K

    private func handleCapture(_ key: Key) -> Command {
        switch key {
        case .escape:
            return .close
        case .enter(.command):
            commit(action: AppModel.keep)
            return .close
        case .enter([.command, .shift]):
            return launchRex()
        case .enter(let modifiers) where modifiers.contains(.command):
            // A ⌘↩ chord no action owns is swallowed: the draft stays put and AppKit gets nothing to beep at.
            return start(KeyCombo(modifiers: modifiers, key: "return")) ?? .handled
        case .command(AppModel.kickoffsChord):
            kickoffFilter = ""
            kickoffSelection = 0
            mode = .kickoffs
            return .handled
        case .command(let chord):
            // Any other ⌘ chord no action owns belongs to the editor: ⌘A, ⌘V…
            return start(chord) ?? .ignored
        default:
            return .ignored
        }
    }

    private func handleKickoffs(_ key: Key) -> Command {
        switch key {
        case .escape:
            mode = .capture
        case .up:
            kickoffSelection = max(kickoffSelection - 1, 0)
        case .down:
            kickoffSelection = min(kickoffSelection + 1, max(kickoffs.count - 1, 0))
        case .enter([]):
            let offered = kickoffs
            guard offered.indices.contains(kickoffSelection) else { return .handled }
            let id = offered[kickoffSelection].id
            if id == AppModel.rex { return launchRex() }
            return actions.first { $0.id == id }.map { start($0) } ?? .handled
        case .enter:
            break
        default:
            return .ignored  // typing goes to the filter
        }
        return .handled
    }

    private func launchRex() -> Command {
        guard let fragment = commit(action: AppModel.rex) else { return .close }
        return .launch(fragment)
    }

    /// Saves the draft for the action that is on for this chord and has the shell run it. Nil when no action
    /// owns the chord.
    private func start(_ chord: KeyCombo) -> Command? {
        actions.first { $0.on && $0.chord == chord }.map { start($0) }
    }

    private func start(_ action: ActionInfo) -> Command {
        guard let fragment = commit(action: action.id) else { return .close }
        let input = ActionInput(fragment: fragment, settings: action.settings)
        return .start(
            ActionRun(name: action.name, program: action.program, input: input, returnsSession: action.kind == .launch))
    }

    // MARK: List and detail

    private func handleList(_ key: Key) -> Command {
        switch key {
        case .escape:
            guard pendingHint.isEmpty else {
                pendingHint = ""
                return .handled
            }
            return .close
        case .down:
            move(1)
        case .up:
            move(-1)
        case .enter:
            return open(selection)
        case .command(AppModel.actionsChord):
            actionSelection = min(actionSelection, max(actions.count - 1, 0))
            isRecording = false
            mode = .actions
        case .char(let character, let modifiers) where modifiers.isEmpty:
            switch character {
            case "j": move(1)
            case "k": move(-1)
            case "x": trashSelected()
            case "n":
                beginCapture()
                return .startDictation
            default:
                guard HintLabels.alphabet.contains(character) else { return .handled }
                pendingHint.append(character)
                if let index = hints.firstIndex(of: pendingHint) {
                    pendingHint = ""
                    return open(index)
                }
                if !hints.contains(where: { $0.hasPrefix(pendingHint) }) { pendingHint = "" }
            }
        default:
            break
        }
        return .handled
    }

    /// Esc and every ⌘↩ chord save the edit and return to the list; the editor has no other use for them.
    private func handleDetail(_ key: Key, id: Fragment.ID) -> Command {
        switch key {
        case .escape: break
        case .enter(let modifiers) where modifiers.contains(.command): break
        default: return .ignored
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if var fragment = fragments.first(where: { $0.id == id }), fragment.text != text, !text.isEmpty {
            fragment.text = text
            try? store.save(fragment)
        }
        showList()
        return .handled
    }

    private func move(_ delta: Int) {
        selection = min(max(selection + delta, 0), max(fragments.count - 1, 0))
        pendingHint = ""
    }

    /// A launched fragment goes back to what it started; anything else opens in the editor, including a launch
    /// whose action is gone.
    private func open(_ index: Int) -> Command {
        guard fragments.indices.contains(index) else { return .handled }
        let fragment = fragments[index]
        selection = index
        if fragment.session != nil {
            if fragment.action == AppModel.rex { return .attach(fragment) }
            if let action = actions.first(where: { $0.id == fragment.action && $0.kind == .launch }) {
                let input = ActionInput(fragment: fragment, settings: action.settings)
                return .start(ActionRun(name: action.name, program: action.program, verb: .attach, input: input))
            }
        }
        draft = fragment.text
        mode = .detail(fragment.id)
        return .handled
    }

    private func trashSelected() {
        guard fragments.indices.contains(selection) else { return }
        try? store.trash(fragments[selection])
        reload()
        selection = min(selection, max(fragments.count - 1, 0))
    }

    // MARK: ⌘, Actions

    private func handleActions(_ key: Key) -> Command {
        switch key {
        case .escape:
            showList()
        case .down:
            moveAction(1)
        case .up:
            moveAction(-1)
        case .enter([]):
            guard let action = selectedAction else { break }
            if action.manifest != nil {
                settingSelection = 0
                isEditingSetting = false
                mode = .actionSettings(action.id)
            } else if action.didNotCompile {
                mode = .actionProblem(action.id)
            }
        case .char(let character, let modifiers) where modifiers.isEmpty:
            switch character {
            case "j": moveAction(1)
            case "k": moveAction(-1)
            case "o": return .revealActions
            case " ":
                guard let action = selectedAction, action.manifest != nil else { break }
                return .choose(action.id, .on(!action.on))
            case "r":
                guard selectedAction?.manifest != nil else { break }
                isRecording = true
                recordingProblem = nil
            default: break
            }
        default:
            break
        }
        return .handled
    }

    /// Only a ⌘ chord can bind. One that is taken says by whom and waits for another; esc keeps the old one.
    private func handleRecording(_ key: Key) -> Command {
        let chord: KeyCombo
        switch key {
        case .escape:
            isRecording = false
            recordingProblem = nil
            return .handled
        case .command(let pressed):
            chord = pressed
        case .enter(let modifiers) where modifiers.contains(.command):
            chord = KeyCombo(modifiers: modifiers, key: "return")
        default:
            return .handled
        }
        guard let action = selectedAction else { return .handled }
        if let owner = ActionCatalog.owner(of: chord, among: actions, except: action.id) {
            recordingProblem = "\(chord.symbols) is \(owner)'s. Press another."
            return .handled
        }
        isRecording = false
        recordingProblem = nil
        return .choose(action.id, .chord(chord.written))
    }

    private func moveAction(_ delta: Int) {
        actionSelection = min(max(actionSelection + delta, 0), max(actions.count - 1, 0))
    }

    // MARK: An action's settings

    private func settings(of id: String) -> (ActionInfo, [SettingSpec])? {
        guard let action = actions.first(where: { $0.id == id }), let specs = action.manifest?.settings else {
            return nil
        }
        return (action, specs)
    }

    private func handleSettings(_ key: Key, id: String) -> Command {
        guard let (action, specs) = settings(of: id) else {
            mode = .actions  // it stopped compiling while its settings were open
            return .handled
        }
        switch key {
        case .escape:
            mode = .actions
        case .down, .char("j", []):
            settingSelection = min(settingSelection + 1, max(specs.count - 1, 0))
        case .up, .char("k", []):
            settingSelection = max(settingSelection - 1, 0)
        case .enter([]):
            guard specs.indices.contains(settingSelection) else { break }
            let spec = specs[settingSelection]
            let current = action.settings[spec.key] ?? spec.defaultValue ?? ""
            switch spec.kind {
            case .text, .folder:
                settingDraft = action.settings[spec.key] ?? ""
                isEditingSetting = true
            case .toggle:
                return choose(id, spec, current == "true" ? "false" : "true")
            case .choice:
                let options = (spec.optional ? [""] : []) + (spec.choices ?? [])
                guard !options.isEmpty else { break }
                let next = options[((options.firstIndex(of: current) ?? -1) + 1) % options.count]
                return choose(id, spec, next)
            }
        default:
            break
        }
        return .handled
    }

    private func handleEditing(_ key: Key, id: String) -> Command {
        switch key {
        case .escape:
            isEditingSetting = false
            return .handled
        case .enter:
            isEditingSetting = false
            guard let (_, specs) = settings(of: id), specs.indices.contains(settingSelection) else { return .handled }
            return choose(id, specs[settingSelection], settingDraft)
        default:
            return .ignored  // typing goes to the field
        }
    }

    /// A value equal to the action's default is stored as unset, so a later change to the default reaches you.
    private func choose(_ id: String, _ spec: SettingSpec, _ value: String) -> Command {
        .choose(id, .setting(key: spec.key, value: value == spec.defaultValue ? nil : value))
    }

    private func handleProblem(_ key: Key) -> Command {
        switch key {
        case .escape: mode = .actions
        case .char("o", []): return .revealActions
        default: break
        }
        return .handled
    }
}
