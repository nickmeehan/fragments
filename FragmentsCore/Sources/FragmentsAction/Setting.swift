import Foundation

/// A setting the action offers in the panel: ⌘, in the fragments list, then ↩ on the action. Declare it as a
/// property; Fragments draws a row for it, keeps what you choose, and fills the property in before your method runs:
///
///     @Setting("Project folder", kind: .folder) var folder = "~"
///     @Setting("Model", placeholder: "default") var model: String?
///     @Setting("Effort", choices: ["low", "medium", "high"]) var effort: String?
///     @Setting("Notify when done") var notify = false
@propertyWrapper
public struct Setting<Value: SettingValue> {
    fileprivate let storage: SettingStorage
    private let defaultValue: Value

    public init(
        wrappedValue: Value, _ label: String, placeholder: String? = nil, choices: [String]? = nil,
        kind: SettingKind? = nil
    ) {
        defaultValue = wrappedValue
        storage = SettingStorage(
            label: label, kind: kind ?? (choices == nil ? Value.kind : .choice), placeholder: placeholder,
            choices: choices, optional: Value.canBeUnset, defaultValue: wrappedValue.rawValue)
    }

    public init(_ label: String, placeholder: String? = nil, choices: [String]? = nil, kind: SettingKind? = nil)
    where Value: ExpressibleByNilLiteral {
        self.init(wrappedValue: nil, label, placeholder: placeholder, choices: choices, kind: kind)
    }

    public var wrappedValue: Value {
        guard let raw = storage.value ?? storage.defaultValue else { return defaultValue }
        return Value(rawValue: storage.kind == .folder ? raw.expandingTilde : raw) ?? defaultValue
    }
}

/// How Settings shows a setting.
public enum SettingKind: String, Codable, Sendable {
    case text, toggle, choice, folder
}

/// A setting as the manifest describes it to Settings.
public struct SettingSpec: Codable, Equatable, Sendable {
    /// The property's name.
    public var key: String
    public var label: String
    public var kind: SettingKind
    public var placeholder: String?
    public var choices: [String]?
    /// Empty means unset, and the action sees `nil`.
    public var optional: Bool
    public var defaultValue: String?

    public init(
        key: String, label: String, kind: SettingKind, placeholder: String? = nil, choices: [String]? = nil,
        optional: Bool = false, defaultValue: String? = nil
    ) {
        self.key = key
        self.label = label
        self.kind = kind
        self.placeholder = placeholder
        self.choices = choices
        self.optional = optional
        self.defaultValue = defaultValue
    }
}

/// The types a setting can hold. Values travel as strings; a `Bool` as `true` or `false`.
public protocol SettingValue {
    init?(rawValue: String)
    var rawValue: String? { get }
    static var kind: SettingKind { get }
    static var canBeUnset: Bool { get }
}

extension SettingValue {
    public static var canBeUnset: Bool { false }
}

extension String: SettingValue {
    public init?(rawValue: String) { self = rawValue }
    public var rawValue: String? { self }
    public static var kind: SettingKind { .text }
}

extension Bool: SettingValue {
    public init?(rawValue: String) { self.init(rawValue) }
    public var rawValue: String? { String(self) }
    public static var kind: SettingKind { .toggle }
}

extension Optional: SettingValue where Wrapped == String {
    public init?(rawValue: String) { self = rawValue.isEmpty ? nil : rawValue }
    public var rawValue: String? { self }
    public static var kind: SettingKind { .text }
    public static var canBeUnset: Bool { true }
}

// MARK: Filling them in

/// A class, so the library can fill in a setting it found by reflection without the action being mutable.
final class SettingStorage {
    let label: String
    let kind: SettingKind
    let placeholder: String?
    let choices: [String]?
    let optional: Bool
    let defaultValue: String?
    var value: String?

    init(
        label: String, kind: SettingKind, placeholder: String?, choices: [String]?, optional: Bool,
        defaultValue: String?
    ) {
        self.label = label
        self.kind = kind
        self.placeholder = placeholder
        self.choices = choices
        self.optional = optional
        self.defaultValue = defaultValue
    }
}

extension Setting: DeclaredSetting {
    var settingStorage: SettingStorage { storage }
}

protocol DeclaredSetting {
    var settingStorage: SettingStorage { get }
}

enum Settings {
    /// Each `@Setting` property on the action, named after its property.
    static func declared(on action: Any) -> [(key: String, storage: SettingStorage)] {
        Mirror(reflecting: action).children.compactMap { child in
            guard let label = child.label, let setting = child.value as? any DeclaredSetting else { return nil }
            return (label.hasPrefix("_") ? String(label.dropFirst()) : label, setting.settingStorage)
        }
    }

    static func specs(of action: Any) -> [SettingSpec] {
        declared(on: action).map { key, storage in
            SettingSpec(
                key: key, label: storage.label, kind: storage.kind, placeholder: storage.placeholder,
                choices: storage.choices, optional: storage.optional, defaultValue: storage.defaultValue)
        }
    }

    /// Gives each declared setting its stored value. Keys the action no longer declares are ignored.
    static func fill(_ action: Any, from values: [String: String]) {
        for (key, storage) in declared(on: action) {
            storage.value = values[key]
        }
    }
}

extension String {
    fileprivate var expandingTilde: String {
        guard hasPrefix("~") else { return self }
        return FileManager.default.homeDirectoryForCurrentUser.path + dropFirst()
    }
}
