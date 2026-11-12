import Foundation
import FragmentsAction

/// Doesn't compile on purpose, so the renders show what the Actions view says about an action that didn't.
@main
struct Broken: RunAction {
    static let name = "Broken"
    static let chord: Chord = "cmd+b"

    func run(_ fragment: Fragment) throws {
        let count: Int = fragment.text
    }
}
