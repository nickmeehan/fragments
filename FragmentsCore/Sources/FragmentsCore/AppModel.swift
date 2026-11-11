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
        /// Hand the thought to another app through its link.
        case openURL(URL)
    }

    public private(set) var mode: Mode = .capture
    public var draft = ""
    public private(set) var fragments: [Fragment] = []
    public private(set) var selection = 0
    public private(set) var pendingHint = ""
    public var prefs: LaunchPrefs
    public let store: FragmentStore

    public init(store: FragmentStore, prefs: LaunchPrefs) {
        self.store = store
        self.prefs = prefs
    }

    public var hints: [String] {
        HintLabels.labels(count: fragments.count)
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

    public func handle(_ key: Key) -> Command {
        switch mode {
        case .capture: return handleCapture(key)
        case .list: return handleList(key)
        case .detail(let id): return handleDetail(key, id: id)
        }
    }

    /// Saves the draft as a fragment. Nil when there is nothing worth saving.
    @discardableResult
    public func commit(action: Action) -> Fragment? {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var fragment = Fragment(text: text, action: action)
        if action == .claude {
            fragment.session = Session(
                name: "frag-\(fragment.id)", claudeSessionID: UUID().uuidString.lowercased(), folder: prefs.folder)
        }
        try? store.save(fragment)
        draft = ""
        return fragment
    }

    private func handleCapture(_ key: Key) -> Command {
        switch key {
        case .escape:
            return .close
        case .enter(let modifiers) where modifiers.contains(.command):
            // A ⌘↩ chord no action owns is swallowed: the draft stays put and AppKit gets nothing to beep at.
            guard let action = Action.allCases.first(where: { $0.chord == modifiers }) else { return .handled }
            guard let fragment = commit(action: action) else { return .close }
            return kickoff(fragment)
        default:
            return .ignored
        }
    }

    /// How the shell starts a saved fragment's action. One arm per kickoff: `.launch` for a session Fragments
    /// can come back to, `.openURL` for a hand-off to another app.
    private func kickoff(_ fragment: Fragment) -> Command {
        switch fragment.action {
        case .keep: .close
        case .claude: .launch(fragment)
        case .cowork: .openURL(Launcher.coworkURL(prompt: fragment.text))
        }
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

    /// Esc and every capture chord save the edit and return to the list; the editor has no other use for them.
    private func handleDetail(_ key: Key, id: Fragment.ID) -> Command {
        guard key == .escape || Action.allCases.contains(where: { key == .enter($0.chord) }) else { return .ignored }
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

    private func open(_ index: Int) -> Command {
        guard fragments.indices.contains(index) else { return .handled }
        let fragment = fragments[index]
        selection = index
        if fragment.session != nil { return .attach(fragment) }
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

// MARK: Capture chords

extension Action {
    /// The modifiers that, held with ↩ in capture, choose this action. A new kickoff takes a free chord here;
    /// capture, the detail editor and the footer all read it from this one place.
    public var chord: Modifiers {
        switch self {
        case .keep: .command
        case .claude: [.command, .shift]
        case .cowork: [.command, .option]
        }
    }

    /// The chord as the capture footer shows it: `⌘⌥↩ Cowork`.
    public var hint: String {
        let name =
            switch self {
            case .keep: "keep"
            case .claude: "Rex"
            case .cowork: "Cowork"
            }
        return chord.symbols + "↩ " + name
    }
}
