import Foundation
import Observation

/// The panel's whole state machine: capture → keep or launch, list → open, attach or trash, detail → edit.
/// Pure state plus `Command`s for the app shell to perform, so every path runs under `swift test`.
@MainActor @Observable
public final class AppModel {
    public enum Mode: Equatable, Sendable {
        case capture
        case list
        case detail(Fragment.ID)
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
    }

    /// Built in: ⌘↩ keeps the thought and does nothing else.
    public static let keep = "keep"
    /// Rex keeps its own path until it becomes an action; the id stays what fragments on disk already say.
    public static let rex = "claude"

    public private(set) var mode: Mode = .capture
    public var draft = ""
    public private(set) var fragments: [Fragment] = []
    public private(set) var selection = 0
    public private(set) var pendingHint = ""
    public var prefs: LaunchPrefs
    /// Every action found, on or off; the shell refreshes it when capture opens.
    public var actions: [ActionInfo] = []
    public let store: FragmentStore

    public init(store: FragmentStore, prefs: LaunchPrefs) {
        self.store = store
        self.prefs = prefs
    }

    public var hints: [String] {
        HintLabels.labels(count: fragments.count)
    }

    /// The capture footer: keep, Rex, each action that is on, esc.
    public var captureHints: [String] {
        ["⌘↩ keep", "⌘⇧↩ Rex"] + actions.filter(\.on).map(\.hint) + ["esc discard"]
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

    private func handleCapture(_ key: Key) -> Command {
        switch key {
        case .escape:
            return .close
        case .enter(.command):
            commit(action: AppModel.keep)
            return .close
        case .enter([.command, .shift]):
            guard let fragment = commit(action: AppModel.rex) else { return .close }
            return .launch(fragment)
        case .enter(let modifiers) where modifiers.contains(.command):
            // A ⌘↩ chord no action owns is swallowed: the draft stays put and AppKit gets nothing to beep at.
            return start(KeyCombo(modifiers: modifiers, key: "return")) ?? .handled
        case .command(let chord):
            // Any other ⌘ chord no action owns belongs to the editor: ⌘A, ⌘V…
            return start(chord) ?? .ignored
        default:
            return .ignored
        }
    }

    /// Saves the draft for the action that is on for this chord and has the shell run it. Nil when no action
    /// owns the chord.
    private func start(_ chord: KeyCombo) -> Command? {
        guard let action = actions.first(where: { $0.on && $0.chord == chord }) else { return nil }
        guard let fragment = commit(action: action.id) else { return .close }
        let input = ActionInput(fragment: fragment, settings: action.settings)
        return .start(
            ActionRun(name: action.name, program: action.program, input: input, returnsSession: action.kind == .launch))
    }

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
}
