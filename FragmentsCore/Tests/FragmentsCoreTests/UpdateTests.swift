import Foundation
import Testing

@testable import FragmentsCore

/// GitHub's list of releases, as `api.github.com/repos/…/releases` answers: newest first, generated notes.
private func releases(_ entries: [(tag: String, body: String)], draft: String? = nil, prerelease: String? = nil)
    -> Data
{
    var list: [[String: Any]] = entries.map {
        ["tag_name": $0.tag, "body": $0.body, "draft": false, "prerelease": false]
    }
    if let draft { list.append(["tag_name": draft, "body": "* feat: unfinished", "draft": true, "prerelease": false]) }
    if let prerelease {
        list.append(["tag_name": prerelease, "body": "* feat: early", "draft": false, "prerelease": true])
    }
    return try! JSONSerialization.data(withJSONObject: list)
}

private let v060 = """
    ## What's Changed
    * feat: open a list row with ⌘1–⌘9 instead of a letter by @nickmeehan in https://github.com/nickmeehan/fragments/pull/19
    * feat: filter the list by typing by @nickmeehan in https://github.com/nickmeehan/fragments/pull/17


    **Full Changelog**: https://github.com/nickmeehan/fragments/compare/v0.5.0...v0.6.0
    """

private let v040 = """
    ## What's Changed
    * chore: drop plugin settings and agent skills by @nickmeehan in https://github.com/nickmeehan/fragments/pull/11
    * fix(list): keep the selection on trash by @nickmeehan in https://github.com/nickmeehan/fragments/pull/12
    * ci: drive the app by @nickmeehan in https://github.com/nickmeehan/fragments/pull/8
    """

@Suite struct UpdateTests {
    @Test func everyNewerReleaseNewestFirstWithItsNotesCleaned() throws {
        let json = releases([("v0.4.0", v040), ("v0.6.0", v060), ("v0.3.0", "* feat: yours already")])
        let update = try #require(Update(releases: json, current: "0.3.0"))
        #expect(update.version == "0.6.0")
        #expect(update.current == "0.3.0")
        #expect(
            update.releases == [
                .init(
                    version: "0.6.0",
                    notes: ["Open a list row with ⌘1–⌘9 instead of a letter", "Filter the list by typing"]),
                .init(version: "0.4.0", notes: ["Keep the selection on trash"]),
            ])
    }

    @Test func nothingNewerIsNoUpdate() {
        #expect(Update(releases: releases([("v0.6.0", v060)]), current: "0.6.0") == nil)
        #expect(Update(releases: releases([("v0.6.0", v060)]), current: "0.10.0") == nil)
        #expect(Update(releases: releases([]), current: "0.1.0") == nil)
    }

    @Test func draftsAndPrereleasesAreNeverOffered() {
        let json = releases([("v0.6.0", v060)], draft: "v0.7.0", prerelease: "v0.8.0")
        #expect(Update(releases: json, current: "0.1.0")?.releases.map(\.version) == ["0.6.0"])
    }

    /// A rate limit or an error page answers with something else; it is no update, not a crash.
    @Test func anythingButAListOfReleasesIsNoUpdate() {
        #expect(Update(releases: Data(#"{"message": "API rate limit exceeded"}"#.utf8), current: "0.1.0") == nil)
        #expect(Update(releases: Data("<html>".utf8), current: "0.1.0") == nil)
    }

    /// The version goes into the download URL, so only a v and dotted numbers make a release.
    @Test func aTagThatIsntAVersionIsSkipped() {
        let json = releases([("v1.0.0/../../evil", v060), ("latest", v060), ("v2..0", v060), ("v0.6.0", v060)])
        #expect(Update(releases: json, current: "0.1.0")?.releases.map(\.version) == ["0.6.0"])
    }

    @Test func versionsCompareByNumber() {
        #expect(Update.isNewer("0.10.0", than: "0.9.0"))
        #expect(Update.isNewer("1.0.0", than: "0.99.99"))
        #expect(!Update.isNewer("1.0", than: "1.0.0"))
        #expect(!Update.isNewer("0.5.0", than: "0.6.0"))
    }

    @Test func notesKeepWhatChangedTheApp() {
        let body = """
            * feat!: a breaking one by @someone in https://example.com/1
            * perf: faster list
            * docs: a readme by @nickmeehan in https://github.com/nickmeehan/fragments/pull/3
            * featured: not a type
            """
        #expect(Update.notes(body) == ["A breaking one", "Faster list"])
    }

    @Test func theSummaryIsTheNewestChangeAndACount() throws {
        let many = try #require(Update(releases: releases([("v0.6.0", v060), ("v0.4.0", v040)]), current: "0.1.0"))
        #expect(many.summary == "Open a list row with ⌘1–⌘9 instead of a letter, and 2 more")
        let one = try #require(Update(releases: releases([("v0.4.0", v040)]), current: "0.1.0"))
        #expect(one.summary == "Keep the selection on trash")
        let none = try #require(Update(releases: releases([("v1.0.0", "Hand-written notes")]), current: "0.1.0"))
        #expect(none.summary == "See what's new.")
    }

    @Test func theZipAndPageAreBuiltFromTheVersion() throws {
        let update = try #require(Update(releases: releases([("v0.6.0", v060)]), current: "0.1.0"))
        #expect(
            update.zip.absoluteString
                == "https://github.com/nickmeehan/fragments/releases/download/v0.6.0/Fragments.zip")
        #expect(update.page.absoluteString == "https://github.com/nickmeehan/fragments/releases/tag/v0.6.0")
    }
}

@MainActor @Suite struct UpdateViewTests {
    private func model() throws -> (AppModel, Update) {
        let store = FragmentStore(
            directory: FileManager.default.temporaryDirectory.appending(path: "fragments-\(UUID())"))
        let update = try #require(Update(releases: releases([("v0.6.0", v060)]), current: "0.1.0"))
        let model = AppModel(store: store)
        model.showUpdate(update)
        return (model, update)
    }

    @Test func enterInstallsOnce() throws {
        let (model, update) = try model()
        #expect(model.mode == .update)
        #expect(model.handle(.enter([])) == .install(update))
        #expect(model.isInstalling)
        #expect(model.handle(.enter([])) == .handled)
    }

    @Test func aFailedInstallSaysWhyAndEnterTriesAgain() throws {
        let (model, update) = try model()
        _ = model.handle(.enter([]))
        model.installFailed("offline")
        #expect(!model.isInstalling)
        #expect(model.updateProblem == "offline")
        model.showUpdate(update)
        #expect(model.updateProblem == "offline")
        #expect(model.handle(.enter([])) == .install(update))
        #expect(model.updateProblem == nil)
    }

    @Test func escapeShutsThePanel() throws {
        let (model, _) = try model()
        #expect(model.handle(.escape) == .close)
        #expect(model.handle(.char("x", [])) == .handled)
    }
}
