import Foundation

/// What an action tells Fragments about itself, once per build: `<program> manifest`.
public struct Manifest: Codable, Equatable, Sendable {
    /// The version of this interface. Fragments refuses a manifest from a newer one rather than misread it.
    public static let currentProtocol = 1

    public var `protocol`: Int
    public var name: String
    public var chord: String
    /// A string, not `ActionType`, so a type this version of Fragments doesn't know still decodes and can be
    /// reported as such.
    public var type: String
    public var settings: [SettingSpec]

    public init(
        protocol: Int = Manifest.currentProtocol, name: String, chord: String, type: String,
        settings: [SettingSpec] = []
    ) {
        self.protocol = `protocol`
        self.name = name
        self.chord = chord
        self.type = type
        self.settings = settings
    }
}

/// What Fragments asks of an action's program, with an `ActionInput` on stdin (a `TitlesInput` for `titles`). Only a
/// launch action attaches, retitles or answers for titles.
public enum ActionVerb: String, Codable, Sendable {
    case start, attach, retitle, titles
}

/// What Fragments sends on stdin when a chord starts an action (`<program> start`), when ↩ in the list comes
/// back to a launch (`<program> attach`), or when t in the list titles one (`<program> retitle`).
public struct ActionInput: Codable, Equatable, Sendable {
    public var fragment: Fragment
    /// Only the values you changed; every other setting keeps the default the action declares.
    public var settings: [String: String]

    public init(fragment: Fragment, settings: [String: String] = [:]) {
        self.fragment = fragment
        self.settings = settings
    }
}

/// What a launch action prints after `start` and `attach`: the session Fragments keeps so ↩ can come back to it.
public struct LaunchResult: Codable, Equatable, Sendable {
    public var session: Session

    public init(session: Session) {
        self.session = session
    }
}

/// What Fragments sends for `<program> titles` when the list opens: every fragment the action launched, so one run
/// answers for all of them.
public struct TitlesInput: Codable, Equatable, Sendable {
    public var fragments: [Fragment]
    public var settings: [String: String]

    public init(fragments: [Fragment], settings: [String: String] = [:]) {
        self.fragments = fragments
        self.settings = settings
    }
}

/// What a launch action prints after `titles`: by fragment id, the title its session has now; null for none.
public struct TitlesResult: Codable, Equatable, Sendable {
    public var titles: [String: String?]

    public init(titles: [String: String?]) {
        self.titles = titles
    }
}

/// The JSON both sides speak, with dates as ISO 8601 so a person can read a captured input.
public enum ActionWire {
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// The `main` every action gets from its protocol: reads the verb and the input, calls the action, reports.
enum ActionProgram {
    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    static func manifest<A: Action>(of action: A.Type, type: ActionType) -> Manifest {
        Manifest(name: A.name, chord: A.chord.rawValue, type: type.rawValue, settings: Settings.specs(of: A()))
    }

    /// Answers one verb. Pure apart from `perform` and `titles`, so tests drive it without a process. Each returns
    /// what to print, if anything; `titles` answers its verb with every fragment at once.
    static func respond<A: Action>(
        to verb: String?, input: () -> Data, as action: A.Type, type: ActionType,
        titles: ((A, [Fragment]) throws -> Data)? = nil, perform: (A, ActionVerb, Fragment) throws -> Data?
    ) throws -> Data? {
        if verb == "manifest" { return try ActionWire.encoder.encode(manifest(of: A.self, type: type)) }
        guard let verb = verb.flatMap(ActionVerb.init(rawValue:)) else {
            throw Failure(
                description:
                    "usage: \(CommandLine.arguments.first ?? "action") manifest | start < input.json | attach < input.json"
                    + " | retitle < input.json | titles < input.json"
            )
        }
        guard verb == .start || type == .launch else {
            throw Failure(
                description: "Only a launch action can \(verb.rawValue); \(A.name) hands the thought off and is done.")
        }
        let action = A()
        if verb == .titles {
            let request = try read(TitlesInput.self, from: input())
            Settings.fill(action, from: request.settings)
            return try titles?(action, request.fragments)
        }
        let request = try read(ActionInput.self, from: input())
        Settings.fill(action, from: request.settings)
        return try perform(action, verb, request.fragment)
    }

    private static func read<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try ActionWire.decoder.decode(T.self, from: data)
        } catch {
            throw Failure(description: "The input from Fragments couldn't be read: \(error)")
        }
    }

    /// A launch's verbs: `start` prints the session it began, `attach` the session to keep, `retitle` passes on a new
    /// title.
    static func launch<A: LaunchAction>(_ action: A, _ verb: ActionVerb, _ fragment: Fragment) throws -> Data? {
        if verb == .start { return try ActionWire.encoder.encode(LaunchResult(session: action.start(fragment))) }
        guard let session = fragment.session else {
            throw Failure(description: "Nothing to \(verb.rawValue): fragment \(fragment.id) has no session.")
        }
        switch verb {
        case .attach: return try ActionWire.encoder.encode(LaunchResult(session: action.attach(fragment, to: session)))
        case .retitle: try action.retitle(fragment, in: session)
        case .start, .titles: break  // start is answered above, titles by `titles` with every fragment at once
        }
        return nil
    }

    /// `titles` for every fragment the action launched, as one answer.
    static func titles<A: LaunchAction>(_ action: A, _ fragments: [Fragment]) throws -> Data {
        try ActionWire.encoder.encode(TitlesResult(titles: action.titles(of: fragments)))
    }

    static func main<A: Action>(
        _ action: A.Type, type: ActionType, titles: ((A, [Fragment]) throws -> Data)? = nil,
        perform: (A, ActionVerb, Fragment) throws -> Data?
    ) {
        do {
            let output = try respond(
                to: CommandLine.arguments.dropFirst().first,
                input: { FileHandle.standardInput.readDataToEndOfFile() }, as: A.self, type: type, titles: titles,
                perform: perform)
            if let output { FileHandle.standardOutput.write(output) }
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }

    /// Hands a link to the app that answers its scheme.
    static func open(_ url: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw Failure(description: "Nothing opened \(url.scheme ?? "")://… \(detail)")
        }
    }
}
