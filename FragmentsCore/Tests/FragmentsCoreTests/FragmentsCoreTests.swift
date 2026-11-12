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
        let session = Session(id: "abc-123", folder: "/tmp/proj")
        let original = Fragment(
            id: "20261106-224512-00ff", createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            text: "look into: the thing\n\nsecond paragraph", action: "rex", session: session)
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

    /// Files written before launch actions: Rex was `claude`, kept its label in `session` and the id it needs in
    /// `claude_session`. The id survives; the label is rebuilt from the fragment id, and the next save writes the new
    /// shape.
    @Test func aRexFileFromBeforeLaunchActionsKeepsItsClaudeSession() throws {
        let old = "---\nid: x\naction: claude\nsession: frag-x\nclaude_session: abc-123\nfolder: /p\n---\n\nhi\n"
        let parsed = try #require(Fragment(markdown: old))
        #expect(parsed.action == "rex")
        #expect(parsed.session == Session(id: "abc-123", folder: "/p"))
        #expect(parsed.markdown.contains("action: rex\nsession: abc-123\nfolder: /p\n"))
        #expect(!parsed.markdown.contains("claude_session"))
        #expect(try #require(Fragment(markdown: parsed.markdown)) == parsed)
    }

    @Test func aSessionNeedNotHaveAFolder() throws {
        let original = Fragment(id: "x", text: "hi", action: "linear", session: Session(id: "ENG-42"))
        #expect(!original.markdown.contains("folder:"))
        #expect(try #require(Fragment(markdown: original.markdown)).session == Session(id: "ENG-42"))
    }

    /// Actions see id, date, text and action, plus the session once a launch has started one, so attach has it.
    @Test func theWireCarriesTheSessionOnlyWhenThereIsOne() throws {
        var fragment = Fragment(
            id: "20261111-090000-00ff", createdAt: Date(timeIntervalSince1970: 1_800_000_000), text: "a\nb",
            action: "cowork")
        let plain = String(decoding: try ActionWire.encoder.encode(fragment), as: UTF8.self)
        #expect(
            plain == #"{"action":"cowork","created":"2027-01-15T08:00:00Z","id":"20261111-090000-00ff","text":"a\nb"}"#)
        fragment.session = Session(id: "s-1", folder: "/p")
        let launched = try ActionWire.encoder.encode(fragment)
        #expect(String(decoding: launched, as: UTF8.self).contains(#""session":{"folder":"\/p","id":"s-1"}"#))
        #expect(try ActionWire.decoder.decode(Fragment.self, from: launched) == fragment)
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

    @Test func aComboIsWrittenTheWaySettingsReadsIt() {
        let combo = KeyCombo(modifiers: [.control, .command, .shift], key: "r")
        #expect(combo.written == "cmd+shift+control+r")
        #expect(KeyCombo(combo.written) == combo)
        #expect(KeyCombo(modifiers: .command, key: "return").written == "cmd+return")
    }

    @Test func comboSymbolsAreWhatTheFooterShows() {
        #expect(KeyCombo("cmd+option+return")?.symbols == "⌘⌥↩")
        #expect(KeyCombo("cmd+r")?.symbols == "⌘R")
        #expect(KeyCombo("cmd+shift+f5")?.symbols == "⌘⇧F5")
        #expect(KeyCombo("option+space")?.symbols == "⌥Space")
    }
}

@Suite struct LoginShellTests {
    @Test func rexIsOnThePathTheAppBuilds() {
        #expect(LoginShell.pathLine.hasPrefix(#"export PATH="$HOME/Library/Application Support/com.superlogical.rex/"#))
    }

    @Test func theCommandQuotesEachArgumentAfterThePath() {
        #expect(LoginShell.command(["/a b/action", "it's"]) == LoginShell.pathLine + "; '/a b/action' 'it'\\''s'")
    }
}

@MainActor @Suite struct AppModelTests {
    private func makeModel() -> AppModel {
        AppModel(store: temporaryStore())
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

    @Test func theFooterListsKeepTheActionsThatAreOnAndCommandK() {
        let model = makeModelWithActions()
        #expect(model.captureHints == ["⌘↩ keep", "⌘⌥↩ Cowork", "⌘R Remind", "⌘K all", "esc discard"])
        // When the line is full the last actions drop off; ⌘K and esc always stay.
        #expect(model.captureHints(actionLimit: 1) == ["⌘↩ keep", "⌘⌥↩ Cowork", "⌘K all", "esc discard"])
        #expect(model.captureHints(actionLimit: 0) == ["⌘↩ keep", "⌘K all", "esc discard"])
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

    /// Rex is an action like any other, and a fragment it started before it was one still comes back to it.
    @Test func anOldRexFragmentAttachesThroughTheRexAction() throws {
        let model = makeModel()
        model.actions = ActionCatalog.resolve(
            [
                FoundAction(
                    id: "rex", origin: .bundled, program: URL(filePath: "/cache/bundled/rex/action"),
                    build: .built(Manifest(name: "Rex", chord: "cmd+shift+return", type: "launch")))
            ],
            choices: ["rex": ActionChoice(settings: ["effort": "high"])])
        let old = "---\nid: 20260101-000001-0000\naction: claude\nsession: frag-x\nclaude_session: sid\n---\n\nagent\n"
        try FileManager.default.createDirectory(at: model.store.directory, withIntermediateDirectories: true)
        try old.write(
            to: model.store.directory.appending(path: "20260101-000001-0000.md"), atomically: true, encoding: .utf8)
        model.showList()
        guard case .start(let run) = model.handle(.char("a", [])) else {
            Issue.record("expected attach")
            return
        }
        #expect(run.verb == .attach)
        #expect(run.program == URL(filePath: "/cache/bundled/rex/action"))
        #expect(run.input.fragment.session == Session(id: "sid"))
        #expect(run.input.settings == ["effort": "high"])
    }

    /// Everything the Actions view meets: Cowork bundled; Post yours and broken; Remind yours with a setting of each
    /// kind; Standup off; Ticket a launch. In order: cowork, post, remind, standup, ticket.
    private func makeFullModel() -> AppModel {
        let model = makeModel()
        func yours(_ id: String, _ build: FoundAction.Build) -> FoundAction {
            FoundAction(id: id, origin: .yours, program: URL(filePath: "/cache/yours/\(id)/action"), build: build)
        }
        let settings = [
            SettingSpec(key: "list", label: "List", kind: .text, defaultValue: "Inbox"),
            SettingSpec(key: "notify", label: "Notify when done", kind: .toggle, defaultValue: "false"),
            SettingSpec(key: "effort", label: "Effort", kind: .choice, choices: ["low", "high"], optional: true),
        ]
        model.actions = ActionCatalog.resolve(
            [
                FoundAction(
                    id: "cowork", origin: .bundled, program: URL(filePath: "/cache/bundled/cowork/action"),
                    build: .built(Manifest(name: "Cowork", chord: "cmd+option+return", type: "open"))),
                yours("post", .failed("Post.swift:12: cannot find 'send' in scope")),
                yours("remind", .built(Manifest(name: "Remind", chord: "cmd+r", type: "run", settings: settings))),
                yours("standup", .built(Manifest(name: "Standup", chord: "cmd+u", type: "run"))),
                yours("ticket", .built(Manifest(name: "Ticket", chord: "cmd+t", type: "launch"))),
            ],
            choices: ["remind": ActionChoice(settings: ["list": "Errands"]), "standup": ActionChoice(on: false)])
        return model
    }

    @Test func aLaunchChordSavesTheFragmentAndKeepsTheSessionItReturns() throws {
        let model = makeFullModel()
        model.draft = "fix the login bug"
        guard case .start(let run) = model.handle(.command(KeyCombo(modifiers: .command, key: "t"))) else {
            Issue.record("expected start")
            return
        }
        #expect(run.verb == .start)
        #expect(run.returnsSession)
        let saved = try #require(try model.store.all().first)
        #expect(saved.action == "ticket")
        #expect(saved.session == nil)
        model.started(saved.id, session: Session(id: "ENG-42"))
        #expect(try model.store.all().first?.session == Session(id: "ENG-42"))
    }

    @Test func enterOnALaunchedFragmentAttaches() throws {
        let model = makeFullModel()
        let session = Session(id: "ENG-42", folder: "/w")
        try model.store.save(Fragment(id: "20260101-000001-0000", text: "bug", action: "ticket", session: session))
        model.showList()
        guard case .start(let run) = model.handle(.enter([])) else {
            Issue.record("expected attach")
            return
        }
        #expect(run.verb == .attach)
        #expect(!run.returnsSession)
        #expect(run.name == "Ticket")
        #expect(run.input.fragment.session == session)
    }

    /// Its folder deleted, a launch still opens: as a note, with the session kept in the file.
    @Test func aLaunchWhoseActionIsGoneOpensAsANote() throws {
        let model = makeFullModel()
        try model.store.save(
            Fragment(id: "20260101-000001-0000", text: "bug", action: "gone", session: Session(id: "ENG-42")))
        model.showList()
        #expect(model.handle(.enter([])) == .handled)
        #expect(model.mode == .detail("20260101-000001-0000"))
    }

    @Test func commandKListsTheKickoffsThatAreOnAndSendsTheSelectedOne() throws {
        let model = makeFullModel()
        model.draft = "buy stamps"
        #expect(model.handle(.command(AppModel.kickoffsChord)) == .handled)
        #expect(model.mode == .kickoffs)
        #expect(model.kickoffs.map(\.name) == ["Cowork", "Remind", "Ticket"])
        #expect(model.kickoffs.map(\.kind) == [.open, .run, .launch])
        #expect(model.handle(.char("r", [])) == .ignored)  // typing goes to the filter field
        _ = model.handle(.down)
        model.setKickoffFilter("REM")
        #expect(model.kickoffs.map(\.name) == ["Remind"])
        #expect(model.kickoffSelection == 0)
        guard case .start(let run) = model.handle(.enter([])) else {
            Issue.record("expected start")
            return
        }
        #expect(run.name == "Remind")
        #expect(try model.store.all().first?.action == "remind")
    }

    @Test func escapeFromKickoffsKeepsTheDraft() {
        let model = makeFullModel()
        model.draft = "not yet"
        _ = model.handle(.command(AppModel.kickoffsChord))
        _ = model.handle(.up)
        #expect(model.kickoffSelection == 0)
        for _ in 0..<9 { _ = model.handle(.down) }
        #expect(model.kickoffSelection == 2)
        #expect(model.handle(.escape) == .handled)
        #expect(model.mode == .capture)
        #expect(model.draft == "not yet")
    }

    @Test func commandCommaInTheListOpensActions() {
        let model = makeFullModel()
        model.showList()
        #expect(model.handle(.command(AppModel.actionsChord)) == .handled)
        #expect(model.mode == .actions)
        #expect(model.selectedAction?.id == "cowork")
        _ = model.handle(.char("j", []))
        _ = model.handle(.char("j", []))
        #expect(model.selectedAction?.id == "remind")
        #expect(model.handle(.char(" ", [])) == .choose("remind", .on(false)))
        _ = model.handle(.char("j", []))
        #expect(model.handle(.char(" ", [])) == .choose("standup", .on(true)))
        #expect(model.handle(.char("o", [])) == .revealActions)
        #expect(model.handle(.escape) == .handled)
        #expect(model.mode == .list)
    }

    @Test func rebindingWaitsForAChordNobodyHas() {
        let model = makeFullModel()
        model.showList()
        _ = model.handle(.command(AppModel.actionsChord))
        _ = model.handle(.down)
        _ = model.handle(.down)
        _ = model.handle(.char("r", []))
        #expect(model.isRecording)
        #expect(model.handle(.char("x", [])) == .handled)  // only a ⌘ chord binds
        #expect(model.handle(.enter([.command, .option])) == .handled)
        #expect(model.recordingProblem == "⌘⌥↩ is Cowork's. Press another.")
        #expect(model.handle(.command(AppModel.kickoffsChord)) == .handled)
        #expect(model.recordingProblem == "⌘K is the kickoff list's. Press another.")
        #expect(
            model.handle(.command(KeyCombo(modifiers: [.command, .shift], key: "r")))
                == .choose("remind", .chord("cmd+shift+r")))
        #expect(!model.isRecording)
        _ = model.handle(.char("r", []))
        #expect(model.handle(.escape) == .handled)
        #expect(!model.isRecording)
        #expect(model.mode == .actions)
    }

    @Test func settingsEditTextFlipSwitchesAndStepThroughMenus() {
        let model = makeFullModel()
        model.showList()
        _ = model.handle(.command(AppModel.actionsChord))
        _ = model.handle(.down)
        _ = model.handle(.down)
        _ = model.handle(.enter([]))
        #expect(model.mode == .actionSettings("remind"))
        _ = model.handle(.enter([]))
        #expect(model.isEditingSetting)
        #expect(model.settingDraft == "Errands")
        #expect(model.handle(.char("G", [])) == .ignored)  // typing goes to the field
        model.settingDraft = "Groceries"
        #expect(model.handle(.enter([])) == .choose("remind", .setting(key: "list", value: "Groceries")))
        _ = model.handle(.enter([]))
        model.settingDraft = "Inbox"  // the default: stored as unset
        #expect(model.handle(.enter([])) == .choose("remind", .setting(key: "list", value: nil)))
        _ = model.handle(.enter([]))
        #expect(model.handle(.escape) == .handled)
        #expect(!model.isEditingSetting)
        _ = model.handle(.char("j", []))
        #expect(model.handle(.enter([])) == .choose("remind", .setting(key: "notify", value: "true")))
        _ = model.handle(.down)
        #expect(model.handle(.enter([])) == .choose("remind", .setting(key: "effort", value: "low")))
        _ = model.handle(.escape)
        #expect(model.mode == .actions)
    }

    @Test func aBrokenActionCantBeTurnedOnAndSaysWhy() {
        let model = makeFullModel()
        model.showList()
        _ = model.handle(.command(AppModel.actionsChord))
        _ = model.handle(.down)
        #expect(model.selectedAction?.didNotCompile == true)
        #expect(model.handle(.char(" ", [])) == .handled)
        _ = model.handle(.char("r", []))
        #expect(!model.isRecording)
        _ = model.handle(.enter([]))
        #expect(model.mode == .actionProblem("post"))
        #expect(model.handle(.char("o", [])) == .revealActions)
        _ = model.handle(.escape)
        #expect(model.mode == .actions)
    }

    @Test func newFromListStartsCapture() {
        let model = makeModel()
        model.showList()
        #expect(model.handle(.char("n", [])) == .startDictation)
        #expect(model.mode == .capture)
    }
}
