import Foundation

/// Something to do with a captured thought, chosen by a chord in the capture panel. Write one as a type with
/// `@main` that conforms to `OpenAction` or `RunAction`; the protocol is its interaction type. Fragments compiles
/// the folder it lives in and runs it as its own program, so a crash or a hang stays in the action.
public protocol Action {
    /// What the capture footer shows beside the chord: `⌘⌥↩ Cowork`.
    static var name: String { get }
    /// The key that sends a thought here: any key held with ⌘. Settings can rebind it.
    static var chord: Chord { get }
    init()
}

/// Hands the thought to another app by link. The library opens the link; nothing comes back to Fragments.
public protocol OpenAction: Action {
    func link(for fragment: Fragment) throws -> URL
}

/// Does something with the thought and is done.
public protocol RunAction: Action {
    func run(_ fragment: Fragment) throws
}

/// A key combination written the way Settings writes hotkeys: `cmd+option+return`, `cmd+r`, `cmd+1`.
/// Fragments checks it when it loads the action, so a typo shows up in Settings rather than here.
public struct Chord: Equatable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(stringLiteral value: String) {
        rawValue = value
    }
}

/// The interaction types, as the manifest names them.
public enum ActionType: String, Codable, Sendable {
    case open, run
}

// MARK: Entry points

extension OpenAction {
    public static func main() {
        ActionProgram.main(Self.self, type: .open) { action, fragment in
            try ActionProgram.open(action.link(for: fragment))
        }
    }
}

extension RunAction {
    public static func main() {
        ActionProgram.main(Self.self, type: .run) { action, fragment in try action.run(fragment) }
    }
}

extension String {
    /// Escaped for a URL query: everything but RFC 3986's unreserved characters, so a `+` or `&` in a thought
    /// arrives intact however the receiving app decodes its query.
    public var queryEscaped: String {
        addingPercentEncoding(withAllowedCharacters: .unreserved) ?? ""
    }
}

extension CharacterSet {
    /// RFC 3986's unreserved characters: the only ones every query decoder leaves alone.
    fileprivate static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
