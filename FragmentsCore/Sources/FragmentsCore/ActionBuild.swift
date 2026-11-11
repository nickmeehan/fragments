import Foundation

/// The compiler lines that turn an action folder into a program, and how to tell a program is out of date.
/// Pure: the shell runs the lines and reads the files.
///
/// `FragmentsAction` ships inside the app as source. It is compiled once into a module per app and compiler
/// version, so an action's `import FragmentsAction` always matches the Fragments that runs it.
public enum ActionBuild {
    public static let moduleName = "FragmentsAction"

    public static func libraryArguments(sources: [URL], into directory: URL) -> [String] {
        [
            "xcrun", "swiftc", "-O", "-parse-as-library", "-emit-library", "-static", "-module-name", moduleName,
            "-emit-module", "-emit-module-path", directory.appending(path: "\(moduleName).swiftmodule").path,
            "-o", directory.appending(path: "lib\(moduleName).a").path,
        ] + sources.map(\.path)
    }

    public static func actionArguments(sources: [URL], library: URL, program: URL) -> [String] {
        [
            "xcrun", "swiftc", "-O", "-parse-as-library", "-I", library.path, "-L", library.path,
            "-l\(moduleName)", "-o", program.path,
        ] + sources.map(\.path)
    }

    /// What a program was built from. A program whose saved stamp differs is rebuilt. Contents, not dates: an app
    /// update can bring sources dated before the program built from the old ones.
    public static func stamp(compiler: String, sources: [String]) -> String {
        ([compiler] + sources).joined(separator: "\n\u{1F}\n")
    }

    /// The manifest in `<program> manifest` output, ignoring anything the login shell printed around it.
    public static func manifest(in output: String) -> Manifest? {
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"), start < end else {
            return nil
        }
        return try? ActionWire.decoder.decode(Manifest.self, from: Data(output[start...end].utf8))
    }
}
