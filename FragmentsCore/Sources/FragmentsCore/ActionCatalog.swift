import Foundation

/// An action folder Fragments found, bundled in the app or in `~/.fragments/actions/`, and what building it gave.
public struct FoundAction: Equatable, Sendable {
    public enum Origin: String, Sendable {
        case bundled, yours
    }

    public enum Build: Equatable, Sendable {
        case building
        case failed(String)
        case built(Manifest)
    }

    /// The folder's name.
    public var id: String
    public var origin: Origin
    public var program: URL
    public var build: Build

    public init(id: String, origin: Origin, program: URL, build: Build) {
        self.id = id
        self.origin = origin
        self.program = program
        self.build = build
    }
}

/// What you chose for one action in the Actions view. Anything unset falls back to the action's own default,
/// so only real choices are stored and a new action needs no migration.
public struct ActionChoice: Codable, Equatable, Sendable {
    public var on: Bool?
    /// Rebinds the action; empty or nil keeps the chord it declares.
    public var chord: String?
    public var settings: [String: String]?

    public init(on: Bool? = nil, chord: String? = nil, settings: [String: String]? = nil) {
        self.on = on
        self.chord = chord
        self.settings = settings
    }
}

/// An action as capture and Settings see it: what it says about itself merged with what you chose.
public struct ActionInfo: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var origin: FoundAction.Origin
    public var program: URL
    /// Nil while it compiles or when it didn't.
    public var manifest: Manifest?
    public var isBuilding: Bool
    /// The chord in effect: yours if you rebound it, else the action's.
    public var chord: KeyCombo?
    /// Offered in capture. False when you turned it off, and when a problem keeps it off.
    public var on: Bool
    /// Why it can't be on, in words for the Actions view.
    public var problem: String?
    /// Only the values you changed; the action supplies its own defaults for the rest.
    public var settings: [String: String]

    /// The capture footer's entry: `⌘⌥↩ Cowork`.
    public var hint: String {
        (chord?.symbols ?? "") + " " + name
    }

    /// Open, run or launch; nil until it has compiled and answered its manifest.
    public var kind: ActionType? {
        manifest.flatMap { ActionType(rawValue: $0.type) }
    }

    /// It never answered a manifest: the build failed, and `problem` says how.
    public var didNotCompile: Bool {
        manifest == nil && !isBuilding && problem != nil
    }
}

extension ActionChoice {
    /// One edit from the Actions view.
    public enum Change: Equatable, Sendable {
        case on(Bool)
        case chord(String)
        /// Nil or empty goes back to the action's default.
        case setting(key: String, value: String?)
    }

    /// Applies an edit, keeping only what differs from the defaults so the stored JSON stays small.
    public mutating func apply(_ change: Change) {
        switch change {
        case .on(let on):
            self.on = on
        case .chord(let chord):
            self.chord = chord
        case .setting(let key, let value):
            var settings = self.settings ?? [:]
            settings[key] = value.flatMap { $0.isEmpty ? nil : $0 }
            self.settings = settings.isEmpty ? nil : settings
        }
    }
}

/// What the shell runs: `<program> start` when a chord starts an action, `<program> attach` when ↩ in the list comes
/// back to a launch. The input goes on stdin.
public struct ActionRun: Equatable, Sendable {
    public var name: String
    public var program: URL
    public var verb: ActionVerb
    public var input: ActionInput
    /// A launch's start prints the session to keep; the shell reads it and hands it to `AppModel.started`.
    public var returnsSession: Bool

    public init(
        name: String, program: URL, verb: ActionVerb = .start, input: ActionInput, returnsSession: Bool = false
    ) {
        self.name = name
        self.program = program
        self.verb = verb
        self.input = input
        self.returnsSession = returnsSession
    }
}

/// Decides which actions capture offers: merges the bundled ones with yours, applies your choices, and keeps
/// every chord to one action.
public enum ActionCatalog {
    /// Bundled actions arrive off unless they are listed here; one of yours arrives on.
    public static let onByDefault: Set<String> = ["cowork", "rex"]

    /// Chords no action may take, with what owns them.
    public static let reserved: [KeyCombo: String] = {
        var owners: [KeyCombo: String] = [
            KeyCombo(modifiers: .command, key: "return"): "keep",
            KeyCombo(modifiers: [.command, .shift], key: "z"): "the editor",
        ]
        for key in ["a", "c", "v", "x", "z"] { owners[KeyCombo(modifiers: .command, key: key)] = "the editor" }
        for key in ["q", "w", "h", ","] { owners[KeyCombo(modifiers: .command, key: key)] = "macOS" }
        owners[KeyCombo(modifiers: .command, key: "k")] = "the kickoff list"
        return owners
    }()

    /// Who already has this chord, for the Actions view while it records a new one: a reserved owner, or another
    /// action that is on. Nil when it's free.
    public static func owner(of chord: KeyCombo, among actions: [ActionInfo], except id: String) -> String? {
        reserved[chord] ?? actions.first { $0.id != id && $0.on && $0.chord == chord }?.name
    }

    /// Bundled actions first, then yours, each in folder order; one of yours replaces a bundled action with the
    /// same id. An earlier action that is on keeps a chord a later one also wants.
    public static func resolve(_ found: [FoundAction], choices: [String: ActionChoice]) -> [ActionInfo] {
        let yours = Dictionary(found.filter { $0.origin == .yours }.map { ($0.id, $0) }) { first, _ in first }
        let bundled = found.filter { $0.origin == .bundled }.sorted { $0.id < $1.id }
        let ordered =
            bundled.map { yours[$0.id] ?? $0 }
            + found.filter { $0.origin == .yours && !bundled.map(\.id).contains($0.id) }.sorted { $0.id < $1.id }
        var taken = reserved
        return ordered.map { action in
            var info = describe(action, choice: choices[action.id] ?? ActionChoice())
            if info.on, let chord = info.chord {
                if let owner = taken[chord] {
                    info.on = false
                    info.problem = "\(owner) uses \(chord.symbols)."
                } else {
                    taken[chord] = info.name
                }
            }
            return info
        }
    }

    private static func describe(_ action: FoundAction, choice: ActionChoice) -> ActionInfo {
        var info = ActionInfo(
            id: action.id, name: action.id, origin: action.origin, program: action.program, manifest: nil,
            isBuilding: false, chord: nil, on: false, problem: nil, settings: choice.settings ?? [:])
        let wanted = choice.on ?? (action.origin == .yours || onByDefault.contains(action.id))
        switch action.build {
        case .building:
            info.isBuilding = true
        case .failed(let log):
            info.problem = "It didn't compile:\n" + log
        case .built(let manifest):
            info.manifest = manifest
            info.name = manifest.name
            if let problem = problem(with: manifest) {
                info.problem = problem
                break
            }
            let written = choice.chord.flatMap { $0.isEmpty ? nil : $0 } ?? manifest.chord
            switch chordProblem(written) {
            case .some(let problem): info.problem = problem
            case .none:
                info.chord = KeyCombo(written)
                info.on = wanted
            }
        }
        return info
    }

    private static func problem(with manifest: Manifest) -> String? {
        if manifest.protocol > Manifest.currentProtocol {
            return "It needs a newer Fragments (interface \(manifest.protocol))."
        }
        if ActionType(rawValue: manifest.type) == nil {
            return "This version of Fragments can't run “\(manifest.type)” actions yet."
        }
        return nil
    }

    /// Nil when the chord can be bound. Reserved chords are reported later with their owner, like any clash.
    static func chordProblem(_ written: String) -> String? {
        guard let chord = KeyCombo(written) else { return "“\(written)” isn't a key combination." }
        guard chord.modifiers.contains(.command) else {
            return "\(chord.symbols) needs ⌘: without it the key types into the editor."
        }
        return nil
    }
}
