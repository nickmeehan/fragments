import Foundation

/// How the app runs a program: through a login zsh, with the PATH a GUI app lacks, so `xcrun`, the actions and what
/// they call (`rex`, `claude`) resolve as they do in a terminal.
public enum LoginShell {
    /// Rex adds its CLI to the PATH of terminals it opens, nowhere else; the server keeps it here.
    private static let rexBinDir =
        "$HOME/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/"
        + "Rex Server.app/Contents/MacOS"

    /// GUI apps inherit launchd's bare PATH; the user's tools live here.
    public static let pathLine =
        #"export PATH="\#(rexBinDir):$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH""#

    /// What `zsh -lc` runs for `argv`: the PATH, then the program with each argument quoted.
    public static func command(_ argv: [String]) -> String {
        pathLine + "; " + argv.map(\.shellQuoted).joined(separator: " ")
    }
}

extension String {
    /// Single-quoted for POSIX sh.
    public var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
