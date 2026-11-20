import FragmentsCore
import SwiftUI

@main
struct FragmentsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Fragments", image: "MenuBarGlyph") {
            UpdateItem { delegate.panel.showUpdate($0) }
            Button("New Fragment") { delegate.panel.showCapture() }
            Button("Fragments…") { delegate.panel.showList() }
            Divider()
            SettingsLink()
            Divider()
            Button("Quit Fragments") { NSApp.terminate(nil) }
        }
        Settings {
            SettingsView()
        }
    }
}

/// The menu's first item while a newer release is out. A view of its own, so it appears when a check finds one.
private struct UpdateItem: View {
    let open: (Update) -> Void

    var body: some View {
        if let update = Updater.shared.available {
            Button("Update to \(update.version)…") { open(update) }
            Divider()
        }
    }
}
