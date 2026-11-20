import FragmentsCore
import SwiftUI

@main
struct FragmentsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            UpdateItem { delegate.panel.showUpdate($0) }
            Button("New Fragment") { delegate.panel.showCapture() }
            Button("Fragments…") { delegate.panel.showList() }
            Divider()
            SettingsLink()
            Divider()
            Button("Quit Fragments") { NSApp.terminate(nil) }
        } label: {
            MenuBarGlyph()
        }
        Settings {
            SettingsView()
        }
    }
}

/// The menu's first item while a newer release is out. Views of their own, so each redraws when a check finds one.
private struct UpdateItem: View {
    let open: (Update) -> Void

    var body: some View {
        if let update = Updater.shared.available {
            Button("Update to \(update.version)…") { open(update) }
            Divider()
        }
    }
}

/// The glyph, with a dot at its top right while an update waits. A template image, so macOS tints the dot with it.
private struct MenuBarGlyph: View {
    var body: some View {
        Label {
            Text("Fragments")
        } icon: {
            if Updater.shared.available == nil { Image("MenuBarGlyph") } else { Image(nsImage: Self.dotted) }
        }
    }

    private static let dotted: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSImage(named: "MenuBarGlyph")?.draw(in: rect)
            let dot = NSRect(x: rect.maxX - 5, y: rect.maxY - 5, width: 5, height: 5)
            // A clear ring keeps the dot apart from the stroke wherever they meet.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1, dy: -1)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
