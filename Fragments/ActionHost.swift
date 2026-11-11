import AppKit
import FragmentsCore
import Observation

/// Finds the action folders, compiles the ones whose source changed with the user's swiftc, and runs an action's
/// program when its chord is pressed. Which actions capture offers is Core's decision (`ActionCatalog`); this is
/// the file and process work around it.
@MainActor @Observable
final class ActionHost {
    static let shared = ActionHost()

    /// Every action found, on or off, as Settings lists them.
    private(set) var actions: [ActionInfo] = []
    /// Called whenever `actions` changes, so the panel's model follows.
    @ObservationIgnored var onChange: ((_ actions: [ActionInfo]) -> Void)?

    @ObservationIgnored private var found: [FoundAction] = []
    @ObservationIgnored private var compiler: String?
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var refreshAgain = false

    /// `~/.fragments/actions`, or under `FRAGMENTS_DIR` when that is set.
    static var yoursDirectory: URL { Prefs.fragmentsDirectory.appending(path: "actions") }

    private var locations: ActionFolders {
        let resources = Bundle.main.resourceURL
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return ActionFolders(
            bundled: resources?.appending(path: "Actions"), library: resources?.appending(path: "FragmentsAction"),
            yours: ActionHost.yoursDirectory, cache: caches.appending(path: "Fragments/actions"))
    }

    /// Lists the folders, compiles what changed since its last build, and asks each new program for its manifest.
    /// Cheap when nothing changed: it reads the sources and compares them with what each program was built from.
    func refresh() {
        guard !refreshing else {
            refreshAgain = true
            return
        }
        refreshing = true
        let folders = locations
        let known = compiler
        Task.detached(priority: .utility) {
            let compiler = known ?? ActionFolders.compilerVersion()
            let found = folders.scan(compiler: compiler)
            await self.publish(found, compiler: compiler)
            if found.contains(where: { $0.build == .building }) {
                await self.publish(folders.buildStale(found, compiler: compiler), compiler: compiler)
            }
            await self.finishRefresh()
        }
    }

    /// Re-applies your choices after Settings changes them; nothing is compiled.
    func resolve() {
        actions = ActionCatalog.resolve(found, choices: Prefs.actionChoices)
        onChange?(actions)
    }

    /// Runs the action's program on a saved fragment. The panel is already gone; the fragment is already saved, so
    /// a failure only costs the hand-off, and the alert says why.
    func start(_ run: ActionRun) {
        Task.detached(priority: .userInitiated) {
            let input = (try? ActionWire.encoder.encode(run.input)) ?? Data()
            let result = Shell.run([run.program.path, "start"], input: input, timeout: 10)
            guard result.status != 0 else { return }
            await MainActor.run {
                Runner.fail("\(run.name) didn't finish. The fragment is kept.", result.output)
            }
        }
    }

    func revealYours() {
        try? FileManager.default.createDirectory(at: ActionHost.yoursDirectory, withIntermediateDirectories: true)
        _ = NSWorkspace.shared.open(ActionHost.yoursDirectory)
    }

    private func publish(_ found: [FoundAction], compiler: String) {
        self.found = found
        self.compiler = compiler
        resolve()
    }

    private func finishRefresh() {
        refreshing = false
        guard refreshAgain else { return }
        refreshAgain = false
        refresh()
    }
}

/// The folders and the compiler behind `ActionHost`, used off the main thread. Each program lives in the cache at
/// `<origin>/<id>/action`, beside the manifest it gave and the stamp of what it was built from.
struct ActionFolders: Sendable {
    let bundled: URL?
    let library: URL?
    let yours: URL
    let cache: URL

    private struct Folder {
        let id: String
        let origin: FoundAction.Origin
        let sources: [URL]
    }

    private var libraryDirectory: URL { cache.appending(path: "lib") }

    static func compilerVersion() -> String {
        Shell.run(["xcrun", "swiftc", "--version"]).output
    }

    /// Every action folder, with the ones already current marked built and the rest marked building.
    func scan(compiler: String) -> [FoundAction] {
        folders().map { folder in
            FoundAction(
                id: folder.id, origin: folder.origin, program: program(for: folder),
                build: current(folder, compiler: compiler) ?? .building)
        }
    }

    /// Compiles every action marked building. The library goes first; if it can't compile, nothing can.
    func buildStale(_ found: [FoundAction], compiler: String) -> [FoundAction] {
        let libraryFailure = buildLibrary(compiler: compiler)
        let folders = Dictionary(folders().map { ("\($0.origin.rawValue)/\($0.id)", $0) }) { first, _ in first }
        return found.map { action in
            guard action.build == .building, let folder = folders["\(action.origin.rawValue)/\(action.id)"] else {
                return action
            }
            var built = action
            built.build = libraryFailure.map { .failed($0) } ?? build(folder, compiler: compiler)
            return built
        }
    }

    private func folders() -> [Folder] {
        func list(_ directory: URL?, _ origin: FoundAction.Origin) -> [Folder] {
            guard let directory else { return [] }
            return entries(of: directory).compactMap { entry in
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
                let sources = swiftFiles(in: entry)
                return sources.isEmpty ? nil : Folder(id: entry.lastPathComponent, origin: origin, sources: sources)
            }
        }
        return list(bundled, .bundled) + list(yours, .yours)
    }

    private func entries(of directory: URL) -> [URL] {
        let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        return (entries ?? []).sorted { $0.path < $1.path }
    }

    private func swiftFiles(in directory: URL) -> [URL] {
        entries(of: directory).filter { $0.pathExtension == "swift" }
    }

    private func program(for folder: Folder) -> URL {
        cache.appending(path: "\(folder.origin.rawValue)/\(folder.id)/action")
    }

    private func read(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func stamp(for sources: [URL], compiler: String) -> String {
        ActionBuild.stamp(compiler: compiler, sources: sources.map(read))
    }

    private func librarySources() -> [URL] {
        library.map(swiftFiles(in:)) ?? []
    }

    private func current(_ folder: Folder, compiler: String) -> FoundAction.Build? {
        let directory = program(for: folder).deletingLastPathComponent()
        guard
            read(directory.appending(path: "stamp"))
                == stamp(for: librarySources() + folder.sources, compiler: compiler),
            let manifest = ActionBuild.manifest(in: read(directory.appending(path: "manifest.json")))
        else { return nil }
        return .built(manifest)
    }

    /// Nil when the library is current or was just compiled; otherwise why it couldn't be.
    private func buildLibrary(compiler: String) -> String? {
        let stampFile = libraryDirectory.appending(path: "stamp")
        let stamp = stamp(for: librarySources(), compiler: compiler)
        guard read(stampFile) != stamp else { return nil }
        try? FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        let compiled = Shell.run(ActionBuild.libraryArguments(sources: librarySources(), into: libraryDirectory))
        guard compiled.status == 0 else {
            return "Fragments couldn't compile its action library. Actions need Xcode or the Command Line Tools "
                + "(xcode-select --install).\n" + String(compiled.output.prefix(2000))
        }
        try? stamp.write(to: stampFile, atomically: true, encoding: .utf8)
        return nil
    }

    private func build(_ folder: Folder, compiler: String) -> FoundAction.Build {
        let program = program(for: folder)
        let directory = program.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let compiled = Shell.run(
            ActionBuild.actionArguments(sources: folder.sources, library: libraryDirectory, program: program))
        guard compiled.status == 0 else { return .failed(String(compiled.output.prefix(2000))) }
        let answer = Shell.run([program.path, "manifest"])
        guard answer.status == 0, let manifest = ActionBuild.manifest(in: answer.output) else {
            return .failed("It compiled, but didn't answer `action manifest`:\n" + String(answer.output.prefix(2000)))
        }
        if let json = try? ActionWire.encoder.encode(manifest) {
            try? json.write(to: directory.appending(path: "manifest.json"))
        }
        let stamp = stamp(for: librarySources() + folder.sources, compiler: compiler)
        try? stamp.write(to: directory.appending(path: "stamp"), atomically: true, encoding: .utf8)
        return .built(manifest)
    }
}
