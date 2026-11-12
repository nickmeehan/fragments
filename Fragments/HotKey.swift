import Carbon.HIToolbox
import FragmentsCore
import os

/// A system-wide hotkey through Carbon's RegisterEventHotKey: fires while any app is frontmost and needs no
/// Accessibility permission.
@MainActor
final class HotKey {
    private static let log = Logger(subsystem: "tech.meehan.fragments", category: "hotkey")
    private static var nextID: UInt32 = 1
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false

    private let id: UInt32
    private var ref: EventHotKeyRef?

    init?(_ combo: KeyCombo, action: @escaping () -> Void) {
        guard let code = HotKey.keyCodes[combo.key] else { return nil }
        HotKey.installHandler()
        id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.actions[id] = action
        var modifiers: UInt32 = 0
        if combo.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        if combo.modifiers.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if combo.modifiers.contains(.option) { modifiers |= UInt32(optionKey) }
        if combo.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        let hotKeyID = EventHotKeyID(signature: 0x4652_4147, id: id)  // "FRAG"
        let status = RegisterEventHotKey(code, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else {
            HotKey.log.error("could not register \(combo.key, privacy: .public): OSStatus \(status)")
            HotKey.actions[id] = nil
            return nil
        }
        HotKey.log.info("registered hotkey \(String(describing: combo), privacy: .public)")
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        HotKey.actions[id] = nil
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                MainActor.assumeIsolated { HotKey.actions[hotKeyID.id]?() }
                return noErr
            }, 1, &spec, nil, nil)
    }

    /// Virtual key codes for a US layout (Carbon's kVK_* values).
    nonisolated static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
        "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "return": 36,
        "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
        "tab": 48, "space": 49, "`": 50, "delete": 51, "escape": 53, "f1": 122, "f2": 120, "f3": 99, "f4": 118,
        "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]

    /// The key names above by key code, for reading a pressed chord the way Settings writes it.
    nonisolated static let keyNames: [UInt16: String] = Dictionary(
        keyCodes.map { (UInt16($0.value), $0.key) }, uniquingKeysWith: { first, _ in first })
}
