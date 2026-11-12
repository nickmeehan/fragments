import Foundation
import Testing

@testable import Cowork
@testable import FragmentsAction
@testable import FragmentsCore
@testable import Rex

/// An action with one setting of every kind, the way someone would write it in ~/.fragments/actions.
private struct Remind: RunAction {
    static let name = "Remind"
    static let chord: Chord = "cmd+control+return"

    @Setting("Project folder", kind: .folder) var folder = "~/code"
    @Setting("Model", placeholder: "default") var model: String?
    @Setting("Effort", choices: ["low", "high"]) var effort: String?
    @Setting("Notify") var notify = false

    func run(_ fragment: Fragment) throws {}
}

private let sample = Fragment(
    id: "20261111-090000-00ff", createdAt: Date(timeIntervalSince1970: 1_800_000_000), text: "buy stamps",
    action: "remind")

/// Answers one verb as the Remind program would, with `input` on its stdin.
private func respond(
    _ verb: String?, _ input: ActionInput? = nil, perform: (Remind, Fragment) throws -> Void = { _, _ in }
) throws -> Data? {
    let data = try input.map { try ActionWire.encoder.encode($0) } ?? Data("nope".utf8)
    return try ActionProgram.respond(
        to: verb, input: { data }, as: Remind.self, type: .run,
        perform: { action, _, fragment in
            try perform(action, fragment)
            return nil
        })
}

/// What `Ticket.attach` was handed, for the one test that checks it.
nonisolated(unsafe) private var attachedSessions: [String] = []

/// A launch action, the way someone would write one: it starts a session and can come back to it.
private struct Ticket: LaunchAction {
    static let name = "Ticket"
    static let chord: Chord = "cmd+t"

    @Setting("Folder", kind: .folder) var folder = "/work"

    func start(_ fragment: Fragment) throws -> Session { Session(id: "T-\(fragment.text.count)", folder: folder) }
    func attach(_ fragment: Fragment, to session: Session) throws { attachedSessions.append(session.id) }
}

private func launch(_ verb: String, _ fragment: Fragment) throws -> Data? {
    let data = try ActionWire.encoder.encode(ActionInput(fragment: fragment))
    return try ActionProgram.respond(
        to: verb, input: { data }, as: Ticket.self, type: .launch, perform: ActionProgram.launch)
}

@Suite struct ActionProgramTests {
    @Test func theManifestDescribesTheActionAndEverySetting() throws {
        let manifest = ActionProgram.manifest(of: Remind.self, type: .run)
        #expect(manifest.protocol == 1)
        #expect(manifest.name == "Remind")
        #expect(manifest.chord == "cmd+control+return")
        #expect(manifest.type == "run")
        #expect(
            manifest.settings == [
                SettingSpec(key: "folder", label: "Project folder", kind: .folder, defaultValue: "~/code"),
                SettingSpec(key: "model", label: "Model", kind: .text, placeholder: "default", optional: true),
                SettingSpec(key: "effort", label: "Effort", kind: .choice, choices: ["low", "high"], optional: true),
                SettingSpec(key: "notify", label: "Notify", kind: .toggle, defaultValue: "false"),
            ])
    }

    @Test func manifestIsTheJSONFragmentsCaches() throws {
        let data = try #require(try respond("manifest"))
        let manifest = try ActionWire.decoder.decode(Manifest.self, from: data)
        #expect(manifest == ActionProgram.manifest(of: Remind.self, type: .run))
    }

    /// Stored values fill the properties; anything not stored keeps the default the action declares.
    @Test func startFillsTheSettingsAndPassesTheFragment() throws {
        let input = ActionInput(
            fragment: sample, settings: ["model": "opus", "notify": "true", "folder": "~/elsewhere", "gone": "x"])
        var seen: [String] = []
        let output = try respond("start", input) { action, fragment in
            seen = [
                fragment.text, action.folder, action.model ?? "nil", action.effort ?? "nil", String(action.notify),
            ]
        }
        #expect(output == nil)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(seen == ["buy stamps", home + "/elsewhere", "opus", "nil", "true"])
    }

    @Test func emptyMeansUnsetAndDefaultsExpandTheirTilde() throws {
        let input = ActionInput(fragment: sample, settings: ["model": ""])
        var seen: [String] = []
        _ = try respond("start", input) { action, _ in
            seen = [action.folder, action.model ?? "nil", String(action.notify)]
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(seen == [home + "/code", "nil", "false"])
    }

    @Test func unreadableInputAndUnknownVerbsFail() {
        #expect(throws: ActionProgram.Failure.self) { try respond("start") }
        #expect(throws: ActionProgram.Failure.self) { try respond(nil, ActionInput(fragment: sample)) }
    }

    @Test func anErrorTheActionThrowsComesBack() {
        struct Refused: Error {}
        let input = ActionInput(fragment: sample)
        #expect(throws: Refused.self) {
            try respond("start", input) { _, _ in throw Refused() }
        }
    }

    @Test func aLaunchPrintsTheSessionItStarted() throws {
        let output = try #require(try launch("start", sample))
        #expect(
            try ActionWire.decoder.decode(LaunchResult.self, from: output).session
                == Session(id: "T-10", folder: "/work"))
        #expect(ActionProgram.manifest(of: Ticket.self, type: .launch).type == "launch")
    }

    @Test func attachGetsTheSessionBack() throws {
        var started = sample
        started.session = Session(id: "T-7")
        attachedSessions = []
        #expect(try launch("attach", started) == nil)
        #expect(attachedSessions == ["T-7"])
    }

    @Test func attachWithoutASessionSaysSo() {
        #expect(throws: ActionProgram.Failure.self) { try launch("attach", sample) }
    }

    /// Open and run actions hand the thought off; there is nothing to come back to.
    @Test func onlyALaunchActionAttaches() {
        #expect(throws: ActionProgram.Failure.self) { try respond("attach", ActionInput(fragment: sample)) }
    }

    @Test func inputRoundTripsThroughTheWire() throws {
        let input = ActionInput(fragment: sample, settings: ["model": "opus"])
        let data = try ActionWire.encoder.encode(input)
        #expect(try ActionWire.decoder.decode(ActionInput.self, from: data) == input)
    }

    /// `+`, `&` and `?` would each change the text under one query decoder or another if left bare.
    @Test func queryEscapingLeavesOnlyUnreservedCharacters() {
        #expect("1+1 & \"why\"?\n— caf\u{E9}".queryEscaped == "1%2B1%20%26%20%22why%22%3F%0A%E2%80%94%20caf%C3%A9")
        #expect("a-b_c.d~e".queryEscaped == "a-b_c.d~e")
    }
}

@Suite struct CoworkTests {
    @Test func coworkIsAnOpenActionOnCommandOptionReturn() {
        let manifest = ActionProgram.manifest(of: Cowork.self, type: .open)
        #expect(manifest == Manifest(name: "Cowork", chord: "cmd+option+return", type: "open"))
    }

    @Test func theLinkCarriesTheThoughtFullyEscaped() throws {
        let text = "Draft the Q2 update: 1+1 & \"why\"?\nsecond line — caf\u{E9}"
        var fragment = sample
        fragment.text = text
        let url = Cowork().link(for: fragment)
        let escaped =
            "Draft%20the%20Q2%20update%3A%201%2B1%20%26%20%22why%22%3F%0A"
            + "second%20line%20%E2%80%94%20caf%C3%A9"
        #expect(url.absoluteString == "claude://cowork/new?q=" + escaped)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems == [URLQueryItem(name: "q", value: text)])
    }
}

/// Rex against a stand-in `rex` (`FRAGMENTS_REX`) that logs what it was asked and answers like Rex Beta 1925. Serial,
/// because the stand-in is named in the process environment.
@Suite(.serialized) struct RexTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "rex-test-\(UUID())")
    private var log: String { (try? String(contentsOf: folder.appending(path: "log"), encoding: .utf8)) ?? "" }

    /// `alive` makes `session inspect` find the session; `select-fails` makes Rex refuse to show it.
    private func rex(settings: [String: String] = [:], _ flags: String...) throws -> Rex {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for flag in flags { FileManager.default.createFile(atPath: folder.appending(path: flag).path, contents: nil) }
        let fake = folder.appending(path: "rex")
        try """
        cd '\(folder.path)'
        printf '%s\\n' "$*" >> log
        case "$1 $2" in
        "new "*) echo '{"session_id": "session:new"}' ;;
        "session inspect") [ -e alive ] && echo '{"session_id": "session:alive"}' || { echo not found; exit 3; } ;;
        "client list") echo '{"clients": [{"client_id": "client:app", "info": {"kind": "app"},
            "connection_state": "connected"}]}' ;;
        *) if [ -e select-fails ]; then echo 'Turn on Remote Control'; exit 1; fi ;;
        esac
        """.write(to: fake, atomically: true, encoding: .utf8)
        setenv("FRAGMENTS_REX", fake.path, 1)
        let rex = Rex()
        Settings.fill(rex, from: settings)
        return rex
    }

    @Test func rexIsALaunchActionOnCommandShiftReturnWithClaudeCodesSettings() {
        let manifest = ActionProgram.manifest(of: Rex.self, type: .launch)
        #expect(manifest.name == "Rex")
        #expect(manifest.chord == "cmd+shift+return")
        #expect(manifest.settings.map(\.key) == ["folder", "model", "effort", "permissionMode"])
        #expect(manifest.settings[0].kind == .folder)
        #expect(manifest.settings[0].defaultValue == "~")
        #expect(manifest.settings[2].choices == ["low", "medium", "high", "xhigh", "max"])
    }

    @Test func claudeGetsTheThoughtAfterItsFlags() throws {
        var fragment = sample
        fragment.text = "--fix it's\nbroken"
        #expect(try rex().claude(fragment, sessionID: "sid") == ["claude", "--session-id", "sid", "--", fragment.text])
        let tuned = try rex(settings: ["model": "opus", "effort": "high", "permissionMode": "plan"])
        #expect(
            tuned.claude(fragment, sessionID: "sid") == [
                "claude", "--session-id", "sid", "--model", "opus", "--effort", "high", "--permission-mode", "plan",
                "--", fragment.text,
            ])
    }

    @Test func theScriptRunsTheCommandInTheFolderThenKeepsAShell() {
        let script = Rex.script(
            folder: "/Code/it's here", command: ["claude", "--", "--fix it's\nbroken"], path: "/a b")
        #expect(
            script == """
                export PATH="$PATH":'/a b'
                cd '/Code/it'\\''s here' || exit 1
                'claude' '--' '--fix it'\\''s
                broken'
                exec "${SHELL:-/bin/zsh}" -l
                """)
    }

    @Test func startOpensASessionNamedAfterTheFragmentAndShowsIt() throws {
        let session = try rex(settings: ["folder": folder.path]).start(sample)
        #expect(UUID(uuidString: session.id) != nil)
        #expect(session.folder == folder.path)
        let calls = log.split(separator: "\n")
        #expect(calls.first?.hasPrefix("new frag-20261111-090000-00ff --cwd \(folder.path) --shell zsh") == true)
        #expect(log.contains("'claude' '--session-id' '\(session.id)' '--' 'buy stamps'"))
        #expect(calls.suffix(2) == ["client list --json", "-C client:app do session.select session_id=session:new"])
    }

    @Test func attachShowsTheSessionWhileItIsAlive() throws {
        try rex("alive").attach(sample, to: Session(id: "sid", folder: "/p"))
        #expect(
            log.split(separator: "\n") == [
                "session inspect frag-20261111-090000-00ff --json", "client list --json",
                "-C client:app do session.select session_id=session:alive",
            ])
    }

    @Test func attachResumesTheConversationWhenTheSessionIsGone() throws {
        try rex().attach(sample, to: Session(id: "sid", folder: folder.path))
        #expect(log.contains("new frag-20261111-090000-00ff --cwd \(folder.path)"))
        #expect(log.contains("'claude' '--resume' 'sid'"))
        #expect(log.hasSuffix("do session.select session_id=session:new\n"))
    }

    @Test func attachSaysWhyRexWouldNotShowTheSession() throws {
        let rex = try rex("alive", "select-fails")
        #expect(throws: Rex.Problem.self) { try rex.attach(sample, to: Session(id: "sid")) }
        do {
            try rex.attach(sample, to: Session(id: "sid"))
        } catch {
            #expect("\(error)".hasSuffix("Turn on Remote Control\n"))
        }
    }
}

@Suite struct ActionCatalogTests {
    private func found(
        _ id: String, _ origin: FoundAction.Origin = .yours, chord: String = "cmd+r", type: String = "run",
        name: String? = nil
    ) -> FoundAction {
        FoundAction(
            id: id, origin: origin, program: URL(filePath: "/cache/\(origin.rawValue)/\(id)/action"),
            build: .built(Manifest(name: name ?? id.capitalized, chord: chord, type: type)))
    }

    @Test func bundledActionsArriveOffUnlessListedAndYoursArriveOn() {
        let actions = ActionCatalog.resolve(
            [
                found("cowork", .bundled, chord: "cmd+option+return"), found("draft", .bundled, chord: "cmd+1"),
                found("rex", .bundled, chord: "cmd+shift+return", type: "launch"), found("remind"),
            ],
            choices: [:])
        #expect(actions.map(\.id) == ["cowork", "draft", "rex", "remind"])
        #expect(actions.map(\.on) == [true, false, true, true])
        #expect(actions.allSatisfy { $0.problem == nil })
    }

    @Test func yoursReplacesTheBundledActionWithItsId() {
        let actions = ActionCatalog.resolve(
            [found("cowork", .bundled, chord: "cmd+option+return"), found("cowork", chord: "cmd+k", name: "Mine")],
            choices: [:])
        #expect(actions.count == 1)
        #expect(actions.first?.origin == .yours)
        #expect(actions.first?.name == "Mine")
        #expect(actions.first?.program == URL(filePath: "/cache/yours/cowork/action"))
    }

    /// Two actions that are on can't share a chord: the earlier keeps it and the later says why it is off.
    @Test func aChordClashTurnsTheLaterActionOffWithTheReason() {
        let actions = ActionCatalog.resolve(
            [found("remind", chord: "cmd+control+return"), found("standup", chord: "cmd+control+return")],
            choices: [:])
        #expect(actions.map(\.on) == [true, false])
        #expect(actions[1].problem == "Remind uses ⌘⌃↩.")
    }

    @Test func turningOneOffFreesItsChord() {
        let actions = ActionCatalog.resolve(
            [found("remind", chord: "cmd+control+return"), found("standup", chord: "cmd+control+return")],
            choices: ["remind": ActionChoice(on: false)])
        #expect(actions.map(\.on) == [false, true])
        #expect(actions.allSatisfy { $0.problem == nil })
    }

    @Test func rebindingReplacesTheDeclaredChord() {
        let actions = ActionCatalog.resolve(
            [found("remind", chord: "cmd+control+return"), found("standup", chord: "cmd+control+return")],
            choices: ["standup": ActionChoice(chord: "cmd+shift+u"), "remind": ActionChoice(chord: "")])
        #expect(actions.map(\.chord) == [KeyCombo("cmd+control+return"), KeyCombo("cmd+shift+u")])
        #expect(actions.map(\.on) == [true, true])
    }

    @Test func reservedChordsBelongToKeepTheEditorAndMacOS() {
        let actions = ActionCatalog.resolve(
            [found("a", chord: "cmd+return"), found("c", chord: "cmd+v"), found("d", chord: "cmd+q")], choices: [:])
        #expect(actions.map(\.on) == [false, false, false])
        #expect(actions.map(\.problem) == ["keep uses ⌘↩.", "the editor uses ⌘V.", "macOS uses ⌘Q."])
    }

    @Test func aChordNeedsCommandAndHasToParse() {
        let actions = ActionCatalog.resolve(
            [found("a", chord: "control+r"), found("b", chord: "hyper+r")], choices: [:])
        #expect(actions.map(\.on) == [false, false])
        #expect(actions[0].problem == "⌃R needs ⌘: without it the key types into the editor.")
        #expect(actions[1].problem == "“hyper+r” isn't a key combination.")
    }

    @Test func aManifestFromANewerFragmentsIsRefusedNotMisread() {
        var newer = found("a")
        newer.build = .built(Manifest(protocol: 2, name: "A", chord: "cmd+r", type: "run"))
        let actions = ActionCatalog.resolve([newer, found("b", chord: "cmd+j", type: "schedule")], choices: [:])
        #expect(actions.map(\.on) == [false, false])
        #expect(actions[0].problem == "It needs a newer Fragments (interface 2).")
        #expect(actions[1].problem == "This version of Fragments can't run “schedule” actions yet.")
    }

    @Test func buildingAndFailedActionsAreListedButOff() {
        let program = URL(filePath: "/p")
        let actions = ActionCatalog.resolve(
            [
                FoundAction(id: "a", origin: .yours, program: program, build: .building),
                FoundAction(id: "b", origin: .yours, program: program, build: .failed("B.swift:3: error")),
            ], choices: [:])
        #expect(actions.map(\.isBuilding) == [true, false])
        #expect(actions.map(\.on) == [false, false])
        #expect(actions.map(\.name) == ["a", "b"])
        #expect(actions[1].problem == "It didn't compile:\nB.swift:3: error")
    }

    @Test func storedSettingsTravelWithTheAction() {
        let actions = ActionCatalog.resolve(
            [found("remind")], choices: ["remind": ActionChoice(settings: ["model": "opus"])])
        #expect(actions.first?.settings == ["model": "opus"])
        #expect(actions.first?.hint == "⌘R Remind")
    }

    @Test func launchActionsAreAKindTheCatalogKnows() {
        let actions = ActionCatalog.resolve([found("ticket", chord: "cmd+t", type: "launch")], choices: [:])
        #expect(actions.first?.kind == .launch)
        #expect(actions.first?.on == true)
        #expect(actions.first?.problem == nil)
    }

    /// The Actions view records a new chord only when nobody else has it.
    @Test func aChordsOwnerIsAReservedNameOrAnotherActionThatIsOn() {
        let actions = ActionCatalog.resolve(
            [found("remind", chord: "cmd+r"), found("standup", chord: "cmd+u")],
            choices: ["standup": ActionChoice(on: false)])
        #expect(ActionCatalog.owner(of: KeyCombo("cmd+r")!, among: actions, except: "standup") == "Remind")
        #expect(ActionCatalog.owner(of: KeyCombo("cmd+r")!, among: actions, except: "remind") == nil)
        #expect(ActionCatalog.owner(of: KeyCombo("cmd+u")!, among: actions, except: "remind") == nil)  // off
        #expect(ActionCatalog.owner(of: KeyCombo("cmd+k")!, among: actions, except: "remind") == "the kickoff list")
        #expect(ActionCatalog.owner(of: KeyCombo("cmd+return")!, among: actions, except: "remind") == "keep")
    }

    @Test func editsFromTheActionsViewKeepOnlyWhatDiffers() {
        var choice = ActionChoice()
        choice.apply(.on(false))
        choice.apply(.chord("cmd+shift+r"))
        choice.apply(.setting(key: "list", value: "Errands"))
        #expect(choice == ActionChoice(on: false, chord: "cmd+shift+r", settings: ["list": "Errands"]))
        choice.apply(.setting(key: "list", value: ""))
        #expect(choice.settings == nil)
        choice.apply(.setting(key: "list", value: nil))
        #expect(choice.settings == nil)
    }

    @Test func choicesAreStoredAsCompactJSON() throws {
        let choices = ["standup": ActionChoice(on: false, chord: "cmd+shift+u")]
        let json = String(decoding: try ActionWire.encoder.encode(choices), as: UTF8.self)
        #expect(json == #"{"standup":{"chord":"cmd+shift+u","on":false}}"#)
        #expect(try ActionWire.decoder.decode([String: ActionChoice].self, from: Data(json.utf8)) == choices)
    }
}

@Suite struct ActionBuildTests {
    @Test func theLibraryBuildsOnceAsAModule() {
        let argv = ActionBuild.libraryArguments(
            sources: [URL(filePath: "/app/FragmentsAction/Action.swift")], into: URL(filePath: "/cache/lib"))
        #expect(
            argv == [
                "xcrun", "swiftc", "-O", "-parse-as-library", "-emit-library", "-static", "-module-name",
                "FragmentsAction", "-emit-module", "-emit-module-path", "/cache/lib/FragmentsAction.swiftmodule", "-o",
                "/cache/lib/libFragmentsAction.a", "/app/FragmentsAction/Action.swift",
            ])
    }

    @Test func anActionLinksAgainstTheLibrary() {
        let argv = ActionBuild.actionArguments(
            sources: [URL(filePath: "/a/remind/Remind.swift"), URL(filePath: "/a/remind/More.swift")],
            library: URL(filePath: "/cache/lib"), program: URL(filePath: "/cache/yours/remind/action"))
        #expect(
            argv == [
                "xcrun", "swiftc", "-O", "-parse-as-library", "-I", "/cache/lib", "-L", "/cache/lib",
                "-lFragmentsAction", "-o", "/cache/yours/remind/action", "/a/remind/Remind.swift",
                "/a/remind/More.swift",
            ])
    }

    /// Any change to the compiler, the library or the action's own source means a rebuild.
    @Test func theStampChangesWithAnythingTheProgramIsBuiltFrom() {
        let stamp = ActionBuild.stamp(compiler: "swift 6.0", sources: ["lib", "action"])
        #expect(stamp == ActionBuild.stamp(compiler: "swift 6.0", sources: ["lib", "action"]))
        #expect(stamp != ActionBuild.stamp(compiler: "swift 6.1", sources: ["lib", "action"]))
        #expect(stamp != ActionBuild.stamp(compiler: "swift 6.0", sources: ["lib", "action changed"]))
        #expect(stamp != ActionBuild.stamp(compiler: "swift 6.0", sources: ["lib", "action", "more"]))
    }

    @Test func aLaunchsSessionIsReadThroughLoginShellNoise() {
        let output = "zprofile says hi\n{\"session\":{\"folder\":\"/p\",\"id\":\"T-1\"}}\n"
        #expect(ActionBuild.session(in: output) == Session(id: "T-1", folder: "/p"))
        #expect(ActionBuild.session(in: "no json here") == nil)
    }

    @Test func theManifestIsReadThroughLoginShellNoise() {
        let output =
            "zprofile says hi\n" + #"{"chord":"cmd+r","name":"Remind","protocol":1,"settings":[],"type":"run"}"# + "\n"
        #expect(ActionBuild.manifest(in: output) == Manifest(name: "Remind", chord: "cmd+r", type: "run"))
        #expect(ActionBuild.manifest(in: "error: no such file") == nil)
        #expect(ActionBuild.manifest(in: "{not json}") == nil)
    }
}
