import AppKit
import FragmentsCore
import Observation
import UserNotifications

/// Finds a release newer than this app, says so in a notification and puts it in place of this app. The menu offers
/// `available`; the panel's update view installs it.
@MainActor @Observable
final class Updater {
    static let shared = Updater()

    /// What the last check found newer than this app.
    private(set) var available: Update?

    private var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Checks now and every 6 hours.
    func start() {
        Task {
            while true {
                await check()
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
            }
        }
    }

    /// `FRAGMENTS_RELEASES` names a file of GitHub's releases JSON to read instead (renders). Without it only a release
    /// build asks GitHub, so a build of your own never offers to replace itself. Offline, or a refusal such as a rate
    /// limit, keeps what the last check found.
    func check() async {
        var answer: Data?
        if let path = ProcessInfo.processInfo.environment["FRAGMENTS_RELEASES"] {
            answer = FileManager.default.contents(atPath: path)
        } else {
            #if !DEBUG
                var request = URLRequest(url: Update.releasesAPI)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                if let answered = try? await URLSession.shared.data(for: request),
                    (answered.1 as? HTTPURLResponse)?.statusCode == 200
                {
                    answer = answered.0
                }
            #endif
        }
        guard let answer else { return }
        available = Update(releases: answer, current: current)
        if let available { await announce(available) }
    }

    /// A notification, once per version; clicking it opens the update view (`AppDelegate`). macOS asks you to allow
    /// notifications the first time there's one to show. Turned down, the menu's item still offers the update.
    private func announce(_ update: Update) async {
        guard !CommandLine.arguments.contains("--snapshot"),
            UserDefaults.standard.string(forKey: Prefs.announcedUpdate) != update.version
        else { return }
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = "New version drop, \(update.version) is out!"
        // One identifier, so a newer version's notification replaces an older one's.
        guard
            (try? await center.add(UNNotificationRequest(identifier: "update", content: content, trigger: nil)))
                != nil
        else { return }
        UserDefaults.standard.set(update.version, forKey: Prefs.announcedUpdate)
    }

    /// Downloads the update, checks it's Fragments at that version, swaps it in and opens it on the list. Where this
    /// copy can't be replaced, opens the release page instead.
    func install(_ update: Update, model: AppModel) {
        let app = Bundle.main.bundleURL
        // Opened straight from Downloads, macOS runs a read-only copy of the app (App Translocation).
        guard !app.path.contains("/AppTranslocation/"),
            FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
        else {
            NSWorkspace.shared.open(update.page)
            model.installFailed(
                "Fragments can't replace itself where it is. Move it to Applications, or get \(update.version) "
                    + "from the release page.")
            return
        }
        Task {
            do {
                let new = try await download(update, beside: app)
                _ = try FileManager.default.replaceItemAt(app, withItemAt: new)
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.createsNewApplicationInstance = true  // this copy is still running
                configuration.arguments = ["--list"]
                _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
                NSApp.terminate(nil)
            } catch {
                model.installFailed("Couldn't install \(update.version): \(error.localizedDescription) ↩ tries again.")
            }
        }
    }

    /// The new app, unzipped into a folder only you can write, on the same volume as this one so the swap is a rename.
    /// A download Fragments makes itself carries no quarantine flag, so the new copy opens without Open Anyway.
    private func download(_ update: Update, beside app: URL) async throws -> URL {
        let folder = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)
        let (zip, response) = try await URLSession.shared.download(from: update.zip)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Problem("GitHub answered \(status).") }
        let unzipped = await Task.detached { Shell.run(["/usr/bin/ditto", "-x", "-k", zip.path, folder.path]) }.value
        guard unzipped.status == 0 else { throw Problem(unzipped.output) }
        let new = folder.appending(path: "Fragments.app")
        let bundle = Bundle(url: new)
        guard bundle?.bundleIdentifier == Bundle.main.bundleIdentifier,
            bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == update.version
        else { throw Problem("the download isn't Fragments \(update.version).") }
        return new
    }
}

struct Problem: LocalizedError {
    let errorDescription: String?

    init(_ description: String) {
        errorDescription = description
    }
}
