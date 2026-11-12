import Foundation
import FragmentsAction

/// A run action with one setting of each kind, so the renders show every row the settings view can draw. Renders
/// never run it.
@main
struct Remind: RunAction {
    static let name = "Remind"
    static let chord: Chord = "cmd+r"

    @Setting("List", placeholder: "Inbox") var list: String?
    @Setting("Folder", kind: .folder) var folder = "~/Notes"
    @Setting("When", choices: ["today", "tomorrow", "next week"]) var when: String?
    @Setting("Notify when done") var notify = false

    func run(_ fragment: Fragment) throws {}
}
