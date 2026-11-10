public struct Modifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = Modifiers(rawValue: 1)
    public static let shift = Modifiers(rawValue: 2)
    public static let option = Modifiers(rawValue: 4)
    public static let control = Modifiers(rawValue: 8)
}

/// A keystroke as the model sees it. The app maps NSEvent into this.
public enum Key: Equatable, Sendable {
    case char(Character, Modifiers)
    case enter(Modifiers)
    case escape
    case up
    case down
}

/// A hotkey written the way Settings stores it: `option+space`, `cmd+shift+f`.
public struct KeyCombo: Equatable, Sendable {
    public var modifiers: Modifiers
    /// Lowercase key name: `space`, `a`, `f5`.
    public var key: String

    public init?(_ string: String) {
        let parts = string.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last, !last.isEmpty else { return nil }
        var modifiers = Modifiers()
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command", "⌘": modifiers.insert(.command)
            case "shift", "⇧": modifiers.insert(.shift)
            case "option", "opt", "alt", "⌥": modifiers.insert(.option)
            case "control", "ctrl", "⌃": modifiers.insert(.control)
            default: return nil
            }
        }
        self.modifiers = modifiers
        key = last
    }
}
