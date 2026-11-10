import SwiftUI

@main
struct FragmentsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Fragments", image: "MenuBarGlyph") {
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
