public struct Modifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = Modifiers(rawValue: 1)
    public static let shift = Modifiers(rawValue: 2)
    public static let option = Modifiers(rawValue: 4)
    public static let control = Modifiers(rawValue: 8)

    /// The glyphs, in the order the app writes its chords: `⌘⇧⌥⌃`.
    public var symbols: String {
        var symbols = ""
        if contains(.command) { symbols += "⌘" }
        if contains(.shift) { symbols += "⇧" }
        if contains(.option) { symbols += "⌥" }
        if contains(.control) { symbols += "⌃" }
        return symbols
    }
}

/// A keystroke as the model sees it. The app maps NSEvent into this.
public enum Key: Equatable, Sendable {
    case char(Character, Modifiers)
    case enter(Modifiers)
    /// Any other key held with ⌘: an action's chord, or the editor's (⌘A, ⌘V…) when no action owns it.
    case command(KeyCombo)
    case escape
    case up
    case down
}

/// A hotkey written the way Settings stores it: `option+space`, `cmd+shift+f`. Also an action's chord in the
/// capture panel: `cmd+option+return`, `cmd+r`.
public struct KeyCombo: Hashable, Sendable {
    public var modifiers: Modifiers
    /// Lowercase key name: `space`, `a`, `f5`, `return`.
    public var key: String

    public init(modifiers: Modifiers, key: String) {
        self.modifiers = modifiers
        self.key = key
    }

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
        key = ["enter": "return", "esc": "escape"][last] ?? last
    }

    /// As the footer and Settings show it: `⌘⌥↩`, `⌘R`, `⌘F5`.
    public var symbols: String {
        let glyphs = ["return": "↩", "space": "Space", "tab": "⇥", "delete": "⌫", "escape": "esc"]
        return modifiers.symbols + (glyphs[key] ?? key.uppercased())
    }
}
