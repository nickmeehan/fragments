import Foundation
import FragmentsAction

/// Claude Cowork, in the Claude desktop app. The link fills Cowork's composer and does not send: Anthropic made
/// links stop short of sending on purpose, so the prompt is always seen before it runs. From "Open Claude Desktop
/// with a link" (updated 2026-06-30). Claude cuts the prompt at roughly 14,000 characters.
@main
struct Cowork: OpenAction {
    static let name = "Cowork"
    static let chord: Chord = "cmd+option+return"

    func link(for fragment: Fragment) -> URL {
        URL(string: "claude://cowork/new?q=" + fragment.text.queryEscaped)!  // cannot fail: the query is escaped
    }
}
