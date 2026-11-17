import AppKit
import CoreAudio

/// Starts and stops Wispr Flow's hands-free dictation through its URL scheme. Wispr's native helper reads the fn key at
/// the HID layer, so synthesized key events never reach it; the URL needs no Accessibility grant either.
@MainActor
enum Dictation {
    static let startURL = URL(string: "wispr-flow://start-hands-free")!
    static let stopURL = URL(string: "wispr-flow://stop-hands-free")!

    static func start() {
        guard Prefs.dictationEnabled else { return }
        open(startURL)
    }

    /// Wispr ignores this outside hands-free mode; inside it, Wispr types what it heard a moment later.
    static func stop() {
        open(stopURL)
    }

    /// Dictation is on and a Wispr Flow process is recording from a microphone. Wispr holds no microphone while idle,
    /// so this reads false once you've stopped it with fn. A read of CoreAudio's client list: it records nothing and
    /// needs no grant.
    static var isListening: Bool {
        guard Prefs.dictationEnabled else { return false }
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return false }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else { return false }
        return processes.contains { process in
            var bundleID: Unmanaged<CFString>?
            var recording: UInt32 = 0
            return read(kAudioProcessPropertyBundleID, of: process, into: &bundleID)
                && (bundleID?.takeRetainedValue() as String?)?.hasPrefix("com.electron.wispr-flow") == true
                && read(kAudioProcessPropertyIsRunningInput, of: process, into: &recording) && recording != 0
        }
    }

    private static func read<T>(_ selector: AudioObjectPropertySelector, of object: AudioObjectID, into value: inout T)
        -> Bool
    {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
    }

    private static func open(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false  // keep keyboard focus on our editor so Wispr types into it
        NSWorkspace.shared.open(url, configuration: configuration)
    }
}
