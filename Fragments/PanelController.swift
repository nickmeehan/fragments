import AppKit
import FragmentsCore
import SwiftUI

/// Borderless panels refuse key status by default; this one takes it so the editor can receive typing.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Owns the one floating panel and routes keystrokes: NSEvent → Key → AppModel → Command → side effect.
@MainActor
final class PanelController {
    let model: AppModel
    private let panel: FloatingPanel
    var windowNumber: Int { panel.windowNumber }

    init() {
        let store = FragmentStore(directory: Prefs.fragmentsDirectory)
        model = AppModel(store: store, prefs: Prefs.launch)
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 400), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false  // we never activate; the panel takes key focus on its own
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: PanelRoot(model: model))
        // `self?.handle(event) ?? event` would also resurrect the keys handle() swallows (nil means both
        // "no self" and "consumed"), handing them to AppKit to beep at; keep the two cases apart.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
        // Clicking anywhere else dismisses the panel, like Spotlight.
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main)
        {
            [weak self] _ in MainActor.assumeIsolated { self?.hide() }
        }
    }

    func showCapture(text: String = "") {
        model.prefs = Prefs.launch
        model.beginCapture(text: text)
        show()
        startDictationSoon()
    }

    func showList() {
        model.prefs = Prefs.launch
        model.showList()
        show()
    }

    private func show() {
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + 80))
        }
        // A non-activating panel takes keyboard focus without activating the app, so it appears even when
        // macOS 14 refuses activation (launched from a script). Activation is still requested so that tools
        // which target the frontmost app (Wispr Flow's text insertion) see us when the system allows it.
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func hide() {
        panel.orderOut(nil)
        if NSApp.isActive { NSApp.hide(nil) }  // hands focus back to whatever was in front
    }

    /// Wispr types into the focused field, so the editor must be first responder before the trigger fires.
    private func startDictationSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Dictation.start() }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        // isKeyWindow can read false for a non-activating panel while the app is inactive; the event's window
        // says where AppKit will deliver it.
        guard event.window === panel else { return event }
        let command = Key(event).map { model.handle($0) } ?? .ignored
        switch command {
        case .ignored:
            // A pass-through has one taker, the editor (typing; ⌘A, ⌘V… via the menu). Anywhere else, the list or
            // the editor before focus lands, the key would run off the end of the responder chain and beep.
            return panel.firstResponder is NSTextView ? event : nil
        case .handled:
            break
        case .close:
            hide()
        case .startDictation:
            startDictationSoon()
        case .launch(let fragment):
            hide()
            Runner.launch(fragment, store: model.store)
        case .attach(let fragment):
            hide()
            Runner.attach(fragment, store: model.store)
        }
        return nil
    }
}

extension Key {
    /// Command and control chords stay with AppKit (⌘A, ⌘V…) unless they are enter.
    init?(_ event: NSEvent) {
        var modifiers = Modifiers()
        let flags = event.modifierFlags
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        switch event.keyCode {
        case 53: self = .escape
        case 36, 76: self = .enter(modifiers)
        case 126: self = .up
        case 125: self = .down
        default:
            guard !modifiers.contains(.command), !modifiers.contains(.control),
                let character = event.charactersIgnoringModifiers?.first
            else { return nil }
            self = .char(character, modifiers)
        }
    }
}
