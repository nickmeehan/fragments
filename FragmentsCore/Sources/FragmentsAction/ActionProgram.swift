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

/// What Fragments sends on stdin when a chord starts an action: `<program> start`.
public struct ActionInput: Codable, Equatable, Sendable {
    public var fragment: Fragment
    /// Only the values you changed in Settings; every other setting keeps the default the action declares.
    public var settings: [String: String]

    public init(fragment: Fragment, settings: [String: String] = [:]) {
        self.fragment = fragment
        self.settings = settings
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

    /// Answers one verb. Pure apart from `perform`, so tests drive it without a process.
    static func respond<A: Action>(
        to verb: String?, input: () -> Data, as action: A.Type, type: ActionType,
        perform: (A, Fragment) throws -> Void
    ) throws -> Data? {
        switch verb {
        case "manifest":
            return try ActionWire.encoder.encode(manifest(of: A.self, type: type))
        case "start":
            let request: ActionInput
            do {
                request = try ActionWire.decoder.decode(ActionInput.self, from: input())
            } catch {
                throw Failure(description: "The input from Fragments couldn't be read: \(error)")
            }
            let action = A()
            Settings.fill(action, from: request.settings)
            try perform(action, request.fragment)
            return nil
        default:
            throw Failure(
                description: "usage: \(CommandLine.arguments.first ?? "action") manifest | start < input.json")
        }
    }

    static func main<A: Action>(_ action: A.Type, type: ActionType, perform: (A, Fragment) throws -> Void) {
        do {
            let output = try respond(
                to: CommandLine.arguments.dropFirst().first,
                input: { FileHandle.standardInput.readDataToEndOfFile() }, as: A.self, type: type, perform: perform)
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
