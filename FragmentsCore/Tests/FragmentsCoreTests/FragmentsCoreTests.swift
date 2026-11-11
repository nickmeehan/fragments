import Foundation
import Testing

@testable import Cowork
@testable import FragmentsAction
@testable import FragmentsCore

private func temporaryStore() -> FragmentStore {
    FragmentStore(directory: FileManager.default.temporaryDirectory.appending(path: "fragments-test-\(UUID())"))
}

@Suite struct FragmentTests {
    @Test func markdownRoundTripWithSession() throws {
        let session = Session(name: "frag-1", claudeSessionID: "abc-123", folder: "/tmp/proj")
        let original = Fragment(
            id: "20261106-224512-00ff", createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            text: "look into: the thing\n\nsecond paragraph", action: "claude", session: session)
        let parsed = try #require(Fragment(markdown: original.markdown))
        #expect(parsed == original)
    }

    @Test func plainNoteHasNoSession() throws {
        let parsed = try #require(Fragment(markdown: "---\nid: x\naction: keep\n---\n\nhello\n"))
        #expect(parsed.id == "x")
        #expect(parsed.text == "hello")
        #expect(parsed.session == nil)
    }

    /// An action that has been removed or renamed must not turn its fragments into notes on the next save.
    @Test func anActionIdSurvivesTheRoundTripEvenWhenNothingKnowsIt() throws {
        let original = Fragment(
            id: "20261111-090000-00ff", createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            text: "draft the update", action: "gone-since")
        #expect(original.markdown.contains("action: gone-since"))
        let parsed = try #require(Fragment(markdown: original.markdown))
        #expect(parsed == original)
        #expect(parsed.session == nil)
    }

    @Test func aFileWithoutAnActionIsAKeptNote() throws {
        let parsed = try #require(Fragment(markdown: "---\nid: x\n---\n\nhello\n"))
        #expect(parsed.action == "keep")
        #expect(try #require(Fragment(markdown: "---\nid: x\naction:\n---\n\nhello\n")).action == "keep")
    }

    /// Actions see id, date, text and action. The session is Rex's until launch actions exist.
    @Test func theWireCarriesTheFragmentWithoutItsSession() throws {
        let session = Session(name: "frag-1", claudeSessionID: "abc", folder: "/p")
        let fragment = Fragment(
            id: "20261111-090000-00ff", createdAt: Date(timeIntervalSince1970: 1_800_000_000), text: "a\nb",
            action: "claude", session: session)
        let json = String(decoding: try ActionWire.encoder.encode(fragment), as: UTF8.self)
        #expect(
            json == #"{"action":"claude","created":"2027-01-15T08:00:00Z","id":"20261111-090000-00ff","text":"a\nb"}"#)
        var withoutSession = fragment
        withoutSession.session = nil
        #expect(try ActionWire.decoder.decode(Fragment.self, from: Data(json.utf8)) == withoutSession)
    }

    @Test func rejectsFilesWithoutFrontMatter() {
        #expect(Fragment(markdown: "just text") == nil)
        #expect(Fragment(markdown: "---\naction: keep\n---\nno id") == nil)
    }

    @Test func idsSortChronologically() {
        let earlier = Fragment.newID(now: Date(timeIntervalSince1970: 1_800_000_000))
        let later = Fragment.newID(now: Date(timeIntervalSince1970: 1_800_000_100))
        #expect(earlier < later)
    }

    @Test func titleIsFirstLine() {
        #expect(Fragment(text: "first line\nsecond").title == "first line")
    }
}

@Suite struct FragmentStoreTests {
    @Test func savesAndListsNewestFirst() throws {
        let store = temporaryStore()
        #expect(try store.all().isEmpty)
        try store.save(Fragment(id: "20260101-000000-0001", text: "old"))
        try store.save(Fragment(id: "20260102-000000-0001", text: "new"))
        #expect(try store.all().map(\.text) == ["new", "old"])
    }
}

@Suite struct HintLabelTests {
    @Test func singleLettersWhenTheyFit() {
        #expect(HintLabels.labels(count: 3) == ["a", "s", "d"])
        #expect(HintLabels.labels(count: 0) == [])
    }

    @Test func twoLettersUniqueAndPrefixFree() {
        let labels = HintLabels.labels(count: 30)
        #expect(Set(labels).count == 30)
        #expect(labels.allSatisfy { $0.count == 2 })
        #expect(labels.first == "aa")
    }
}

@Suite struct KeyComboTests {
    @Test func parsesModifiersAndKey() {
        #expect(KeyCombo("option+space") == KeyCombo(modifiers: .option, key: "space"))
        #expect(KeyCombo("Cmd+Shift+F")?.modifiers == [.command, .shift])
        #expect(KeyCombo("Cmd+Shift+F")?.key == "f")
    }

    @Test func rejectsUnknownModifiers() {
        #expect(KeyCombo("hyper+space") == nil)
        #expect(KeyCombo("") == nil)
    }

    @Test func modifierSymbolsFollowTheOrderChordsAreWrittenIn() {
        #expect(Modifiers.command.symbols == "⌘")
        #expect(Modifiers([.control, .option, .shift, .command]).symbols == "⌘⇧⌥⌃")
        #expect(Modifiers().symbols.isEmpty)
    }

    @Test func chordsNameReturnEitherWay() {
        #expect(KeyCombo("cmd+option+return") == KeyCombo(modifiers: [.command, .option], key: "return"))
        #expect(KeyCombo("cmd+enter") == KeyCombo(modifiers: .command, key: "return"))
    }

    @Test func comboSymbolsAreWhatTheFooterShows() {
        #expect(KeyCombo("cmd+option+return")?.symbols == "⌘⌥↩")
        #expect(KeyCombo("cmd+r")?.symbols == "⌘R")
        #expect(KeyCombo("cmd+shift+f5")?.symbols == "⌘⇧F5")
        #expect(KeyCombo("option+space")?.symbols == "⌥Space")
    }
}

@Suite struct LauncherTests {
    @Test func startScriptPassesPromptAndFlags() {
        let prefs = LaunchPrefs(folder: "/Users/me/Code/it's here", model: "opus", effort: "high")
        let script = Launcher.startScript(prompt: "--fix it's\nbroken", prefs: prefs, sessionID: "sid")
        #expect(script.contains("cd '/Users/me/Code/it'\\''s here' || exit 1"))
        let claude = "'claude' '--session-id' 'sid' '--model' 'opus' '--effort' 'high' '--' '--fix it'\\''s\nbroken'"
        #expect(script.contains(claude))
        #expect(script.hasPrefix("#!/bin/sh\n"))
        #expect(script.contains("exec \"${SHELL:-/bin/zsh}\" -l"))
    }

    @Test func emptyPrefsOmitFlags() {
        let script = Launcher.startScript(prompt: "x", prefs: LaunchPrefs(folder: "/p"), sessionID: "sid")
        #expect(!script.contains("--model"))
        #expect(!script.contains("--effort"))
        #expect(!script.contains("--permission-mode"))
    }

    @Test func rexSessionIsLabelledAndRunsTheScript() {
        let argv = Launcher.rexNew(label: "frag-1", folder: "/p", script: URL(filePath: "/f/.sessions/1.sh"))
        #expect(
            argv == [
                "rex", "new", "frag-1", "--cwd", "/p", "--shell", "zsh", "--keep-open", "--json", "--", "/bin/sh",
                "/f/.sessions/1.sh",
            ])
        #expect(Launcher.rexInspect(label: "frag-1") == ["rex", "session", "inspect", "frag-1", "--json"])
        #expect(Launcher.rexSelect(sessionID: "session:1") == ["rex", "do", "session.select", "session_id=session:1"])
    }

    @Test func rexIsOnThePathTheAppBuilds() {
        #expect(Launcher.pathLine.hasPrefix(#"export PATH="$HOME/Library/Application Support/com.superlogical.rex/"#))
    }

    @Test func sessionIDIsReadFromRexJSONDespiteShellNoise() {
        let created = "zprofile noise\n{\n  \"session_id\": \"session:01a1\",\n  \"initial_windows\": []\n}\n"
        #expect(Launcher.sessionID(in: created) == "session:01a1")
        #expect(Launcher.sessionID(in: "Error: session target \"frag-nope\" not found\n") == nil)
    }

    /// Trimmed from `rex client list --json` (Rex Beta 1925): a lost app client left behind by an update,
    /// the live app, a client with no `info`, and the CLI itself.
    private let clientList = """
        zprofile noise
        {
          "clients": [
            {
              "client_id": "client:stale",
              "info": { "kind": "app", "name": "Rex Beta", "version": "0.1.0 (1853)" },
              "connection_state": "lost"
            },
            {
              "client_id": "client:live",
              "info": { "kind": "app", "name": "Rex Beta", "version": "0.1.0 (1925)" },
              "connection_state": "connected",
              "session_ids": ["session:1"]
            },
            { "client_id": "client:anon", "connection_state": "connected" },
            {
              "client_id": "client:cli",
              "info": { "kind": "cli", "name": "rex" },
              "connection_state": "connected"
            }
          ]
        }

        """

    @Test func appClientIsTheConnectedAppNotAStaleOne() {
        #expect(Launcher.appClientID(in: clientList) == "client:live")
    }

    @Test func appClientIsNilWithoutALiveApp() {
        let onlyCLIs = clientList.replacingOccurrences(of: "\"kind\": \"app\"", with: "\"kind\": \"cli\"")
        #expect(Launcher.appClientID(in: onlyCLIs) == nil)
        #expect(Launcher.appClientID(in: "{\"clients\": []}") == nil)
        #expect(Launcher.appClientID(in: "Error: no server\n") == nil)
        #expect(Launcher.appClientID(in: "}{") == nil)
    }

    @Test func rexSelectNamesTheClientWhenKnown() {
        #expect(Launcher.rexSelect(sessionID: "session:1") == ["rex", "do", "session.select", "session_id=session:1"])
        #expect(
            Launcher.rexSelect(sessionID: "session:1", client: "client:live") == [
                "rex", "-C", "client:live", "do", "session.select", "session_id=session:1",
            ])
    }

    @Test func shellQuoting() {
        #expect("it's".shellQuoted == "'it'\\''s'")
    }
}

@MainActor @Suite struct AppModelTests {
    private func makeModel() -> AppModel {
        AppModel(store: temporaryStore(), prefs: LaunchPrefs(folder: "/tmp/proj"))
    }

    /// Cowork on ⌘⌥↩, Remind on ⌘R with a stored setting, Standup off.
    private func makeModelWithActions() -> AppModel {
        let model = makeModel()
        let program = URL(filePath: "/cache/bundled/cowork/action")
        model.actions = ActionCatalog.resolve(
            [
                FoundAction(
                    id: "cowork", origin: .bundled, program: program,
                    build: .built(Manifest(name: "Cowork", chord: "cmd+option+return", type: "open"))),
                FoundAction(
                    id: "remind", origin: .yours, program: URL(filePath: "/cache/yours/remind/action"),
                    build: .built(Manifest(name: "Remind", chord: "cmd+r", type: "run"))),
                FoundAction(
                    id: "standup", origin: .yours, program: URL(filePath: "/cache/yours/standup/action"),
                    build: .built(Manifest(name: "Standup", chord: "cmd+u", type: "run"))),
            ],
            choices: ["remind": ActionChoice(settings: ["list": "Errands"]), "standup": ActionChoice(on: false)])
        return model
    }

    @Test func keepSavesAndCloses() throws {
        let model = makeModel()
        model.draft = "  remember the milk \n"
        #expect(model.handle(.enter(.command)) == .close)
        let saved = try model.store.all()
        #expect(saved.map(\.text) == ["remember the milk"])
        #expect(saved.first?.action == "keep")
        #expect(model.draft.isEmpty)
    }

    @Test func emptyDraftJustCloses() throws {
        let model = makeModel()
        model.draft = "   "
        #expect(model.handle(.enter(.command)) == .close)
        #expect(try model.store.all().isEmpty)
        #expect(model.handle(.escape) == .close)
    }

    @Test func claudeChordCreatesSessionAndLaunches() throws {
        let model = makeModel()
        model.draft = "investigate flaky test"
        guard case .launch(let fragment) = model.handle(.enter([.command, .shift])) else {
            Issue.record("expected launch")
            return
        }
        let session = try #require(fragment.session)
        #expect(session.name == "frag-\(fragment.id)")
        #expect(session.folder == "/tmp/proj")
        #expect(UUID(uuidString: session.claudeSessionID) != nil)
        #expect(try model.store.all().first?.session == session)
    }

    @Test func anActionsChordSavesTheFragmentAndStartsItsProgram() throws {
        let model = makeModelWithActions()
        model.draft = "plan the offsite"
        guard case .start(let run) = model.handle(.enter([.command, .option])) else {
            Issue.record("expected start")
            return
        }
        let saved = try #require(try model.store.all().first)
        #expect(saved.text == "plan the offsite")
        #expect(saved.action == "cowork")
        #expect(saved.session == nil)
        #expect(run.name == "Cowork")
        #expect(run.program == URL(filePath: "/cache/bundled/cowork/action"))
        #expect(run.input.fragment.id == saved.id)
        #expect(run.input.fragment.text == "plan the offsite")
        #expect(run.input.settings.isEmpty)
        #expect(model.draft.isEmpty)
    }

    /// A chord can be any key with ⌘, and the run carries only the settings you changed.
    @Test func aCommandLetterStartsTheActionThatOwnsIt() throws {
        let model = makeModelWithActions()
        model.draft = "buy stamps"
        guard case .start(let run) = model.handle(.command(KeyCombo(modifiers: .command, key: "r"))) else {
            Issue.record("expected start")
            return
        }
        #expect(run.name == "Remind")
        #expect(run.input.fragment.action == "remind")
        #expect(run.input.settings == ["list": "Errands"])
    }

    /// ⌘A must still select all: a ⌘ chord no action owns goes to the editor, untouched.
    @Test func aCommandChordNoActionOwnsGoesToTheEditor() throws {
        let model = makeModelWithActions()
        model.draft = "not yet"
        #expect(model.handle(.command(KeyCombo(modifiers: .command, key: "a"))) == .ignored)
        #expect(model.handle(.command(KeyCombo(modifiers: .command, key: "u"))) == .ignored)  // Standup is off
        #expect(model.draft == "not yet")
        #expect(try model.store.all().isEmpty)
    }

    @Test func anEmptyDraftStartsNothing() throws {
        let model = makeModelWithActions()
        model.draft = "  "
        #expect(model.handle(.enter([.command, .option])) == .close)
        #expect(try model.store.all().isEmpty)
    }

    @Test func theFooterListsKeepRexAndTheActionsThatAreOn() {
        #expect(
            makeModelWithActions().captureHints == ["⌘↩ keep", "⌘⇧↩ Rex", "⌘⌥↩ Cowork", "⌘R Remind", "esc discard"])
    }

    @Test func commandChordNoActionOwnsLeavesTheDraftAlone() throws {
        let model = makeModel()
        model.draft = "not yet"
        #expect(model.handle(.enter([.command, .control])) == .handled)
        #expect(model.draft == "not yet")
        #expect(try model.store.all().isEmpty)
    }

    @Test func typingPassesThroughInCapture() {
        let model = makeModel()
        #expect(model.handle(.char("a", [])) == .ignored)
        #expect(model.handle(.enter([])) == .ignored)
    }

    @Test func listNavigationAndHints() throws {
        let model = makeModel()
        for index in 1...3 {
            try model.store.save(Fragment(id: "20260101-00000\(index)-0000", text: "note \(index)"))
        }
        model.showList()
        #expect(model.mode == .list)
        #expect(model.hints == ["a", "s", "d"])
        #expect(model.selection == 0)
        #expect(model.handle(.char("j", [])) == .handled)
        #expect(model.handle(.down) == .handled)
        #expect(model.handle(.down) == .handled)
        #expect(model.selection == 2)
        #expect(model.handle(.char("k", [])) == .handled)
        #expect(model.selection == 1)
        #expect(model.handle(.char("d", [])) == .handled)
        #expect(model.mode == .detail("20260101-000001-0000"))
        #expect(model.draft == "note 1")
    }

    @Test func twoLetterHintsNeedBothKeys() throws {
        let model = makeModel()
        for index in 10...19 {
            try model.store.save(Fragment(id: "20260101-0000\(index)-0000", text: "note \(index)"))
        }
        model.showList()
        #expect(model.hints.count == 10)
        #expect(model.handle(.char("a", [])) == .handled)
        #expect(model.pendingHint == "a")
        #expect(model.mode == .list)
        #expect(model.handle(.escape) == .handled)
        #expect(model.pendingHint.isEmpty)
        #expect(model.handle(.char("a", [])) == .handled)
        #expect(model.handle(.char("s", [])) == .handled)
        #expect(model.mode == .detail(model.fragments[1].id))
    }

    @Test func escapeInDetailSavesEditAndReturnsToList() throws {
        let model = makeModel()
        try model.store.save(Fragment(id: "20260101-000001-0000", text: "draft"))
        model.showList()
        #expect(model.handle(.enter([])) == .handled)
        model.draft = "draft, revised"
        #expect(model.handle(.escape) == .handled)
        #expect(model.mode == .list)
        #expect(try model.store.all().first?.text == "draft, revised")
    }

    @Test func captureChordsInDetailSaveLikeEscape() throws {
        let model = makeModel()
        try model.store.save(Fragment(id: "20260101-000001-0000", text: "draft"))
        model.showList()
        #expect(model.handle(.enter([])) == .handled)
        model.draft = "draft, revised"
        #expect(model.handle(.enter([.command, .shift])) == .handled)
        #expect(model.mode == .list)
        #expect(try model.store.all().first?.text == "draft, revised")
        #expect(model.handle(.enter([])) == .handled)
        #expect(model.handle(.enter(.command)) == .handled)
        #expect(model.mode == .list)
        #expect(model.handle(.enter([])) == .handled)
        #expect(model.handle(.enter([.command, .option])) == .handled)
        #expect(model.mode == .list)
        #expect(model.handle(.enter([])) == .handled)
        #expect(model.handle(.command(KeyCombo(modifiers: .command, key: "a"))) == .ignored)
        #expect(model.mode == .detail("20260101-000001-0000"))
    }

    /// Open and run actions report no session, so there is nothing to attach to: the fragment opens as a note.
    @Test func handedOffFragmentsOpenAsNotes() throws {
        let model = makeModel()
        try model.store.save(Fragment(id: "20260101-000001-0000", text: "handed off", action: "cowork"))
        model.showList()
        #expect(model.handle(.enter([])) == .handled)
        #expect(model.mode == .detail("20260101-000001-0000"))
    }

    @Test func sessionFragmentsAttach() throws {
        let model = makeModel()
        let session = Session(name: "frag-x", claudeSessionID: "sid", folder: "/p")
        try model.store.save(Fragment(id: "20260101-000001-0000", text: "agent", action: "claude", session: session))
        model.showList()
        guard case .attach(let fragment) = model.handle(.char("a", [])) else {
            Issue.record("expected attach")
            return
        }
        #expect(fragment.session == session)
    }

    @Test func newFromListStartsCapture() {
        let model = makeModel()
        model.showList()
        #expect(model.handle(.char("n", [])) == .startDictation)
        #expect(model.mode == .capture)
    }
}
