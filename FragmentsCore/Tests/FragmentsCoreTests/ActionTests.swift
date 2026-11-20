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

/// A launch action, the way someone would write one: it starts a session and can come back to it. It writes neither
/// retitle nor titles.
private struct Ticket: LaunchAction {
    static let name = "Ticket"
    static let chord: Chord = "cmd+t"

    @Setting("Folder", kind: .folder) var folder = "/work"

    func start(_ fragment: Fragment) throws -> Session { Session(id: "T-\(fragment.text.count)", folder: folder) }
    func attach(_ fragment: Fragment, to session: Session) throws -> Session {
        Session(id: session.id + " again", folder: folder)
    }
}

private func launch(_ verb: String, _ fragment: Fragment) throws -> Data? {
    let data = try ActionWire.encoder.encode(ActionInput(fragment: fragment))
    return try ActionProgram.respond(
        to: verb, input: { data }, as: Ticket.self, type: .launch, perform: ActionProgram.launch)
}

private func launchTitles(_ fragments: [Fragment]) throws -> Data? {
    let data = try ActionWire.encoder.encode(TitlesInput(fragments: fragments))
    return try ActionProgram.respond(
        to: "titles", input: { data }, as: Ticket.self, type: .launch, titles: ActionProgram.titles,
        perform: ActionProgram.launch)
}

@Suite struct ActionProgramTests {
    @Test func theManifestDescribesTheActionAndEverySetting() throws {
        let manifest = ActionProgram.manifest(of: Remind.self, type: .run)
        #expect(manifest.protocol == 1)
        #expect(manifest.name == "Remind")
        #expect(manifest.chord == "cmd+control+return")
        #expect(manifest.type == "run")
        #expect(manifest.icon == "bolt")  // Remind names no icon, so it gets its kind's
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

    /// Attach gets the session and prints the one to keep in its place.
    @Test func attachGetsTheSessionBackAndPrintsTheOneToKeep() throws {
        var started = sample
        started.session = Session(id: "T-7")
        let output = try #require(try launch("attach", started))
        #expect(
            try ActionWire.decoder.decode(LaunchResult.self, from: output).session
                == Session(id: "T-7 again", folder: "/work"))
    }

    /// One run answers for every fragment; an action that doesn't write titles says nothing about any of them.
    @Test func titlesAnswerForEveryFragmentAtOnce() throws {
        var started = sample
        started.session = Session(id: "T-7")
        let output = try #require(try launchTitles([started, sample]))
        #expect(try ActionWire.decoder.decode(TitlesResult.self, from: output) == TitlesResult(titles: [:]))
        #expect(throws: ActionProgram.Failure.self) { try respond("titles", ActionInput(fragment: sample)) }
    }

    /// Null means "no title" and an absent id means "can't tell": both survive the wire.
    @Test func noTitleAndUnknownStayApartOnTheWire() throws {
        let result = TitlesResult(titles: ["a": "Login bug", "b": nil])
        let data = try ActionWire.encoder.encode(result)
        #expect(String(decoding: data, as: UTF8.self) == #"{"titles":{"a":"Login bug","b":null}}"#)
        let decoded = try ActionWire.decoder.decode(TitlesResult.self, from: data)
        #expect(decoded == result)
        #expect(decoded.titles["c"] == nil)
        #expect(decoded.titles["b"] == .some(nil))
    }

    @Test func attachWithoutASessionSaysSo() {
        #expect(throws: ActionProgram.Failure.self) { try launch("attach", sample) }
        #expect(throws: ActionProgram.Failure.self) { try launch("retitle", sample) }
        #expect(throws: ActionProgram.Failure.self) { try launch("end", sample) }
    }

    /// Ticket writes neither retitle nor end: it still compiles, and each does nothing.
    @Test func retitleAndEndDoNothingUnlessTheActionWritesThem() throws {
        var started = sample
        started.session = Session(id: "T-7")
        #expect(try launch("retitle", started) == nil)
        #expect(try launch("end", started) == nil)
        #expect(throws: ActionProgram.Failure.self) { try respond("end", ActionInput(fragment: started)) }
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

/// A folder standing in for Claude's IndexedDB: each file is written as given, bytes and all.
private func claudeCache(_ files: [String: Data]) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: "claude-cache-\(UUID())")
    for (name, data) in files {
        let file = folder.appending(path: name)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
    }
    return folder
}

private func bytes(_ parts: String...) -> Data {
    Data(parts.joined().utf8)
}

@Suite struct CoworkTests {
    @Test func coworkIsALaunchActionOnCommandOptionReturn() {
        let manifest = ActionProgram.manifest(of: Cowork.self, type: .launch)
        #expect(
            manifest
                == Manifest(
                    name: "Cowork", chord: "cmd+option+return", type: "launch",
                    icon: "bubble.left.and.text.bubble.right"))
    }

    @Test func theDraftLinkCarriesTheThoughtFullyEscaped() throws {
        let text = "Draft the Q2 update: 1+1 & \"why\"?\nsecond line — caf\u{E9}"
        var fragment = sample
        fragment.text = text
        let url = Cowork.draft(for: fragment)
        let escaped =
            "Draft%20the%20Q2%20update%3A%201%2B1%20%26%20%22why%22%3F%0A"
            + "second%20line%20%E2%80%94%20caf%C3%A9"
        #expect(url.absoluteString == "claude://cowork/new?q=" + escaped)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems == [URLQueryItem(name: "q", value: text)])
        #expect(Cowork.task("cse_01AA").absoluteString == "claude://claude.ai/cowork/cse_01AA")
    }

    /// Shaped like Claude's cache on 2026-11-17: an id as a length-prefixed string (`"`, 28, the id, then the next
    /// field's type letter), a hundred-odd bytes from the prompt the task began with.
    @Test func aTaskIsFoundByItsOpeningWordsNearestFirst() throws {
        let filler = String(repeating: "\u{1}x", count: 60)
        let first = "Draft the Q2 update for Arbor, then the deck"
        let cache = try claudeCache([
            "leveldb/000507.log": bytes(
                "\"\u{1c}cse_01AAAAAAAAAAAAAAAAAAAAAAN", filler, first, filler,
                "e:cse_01BBBBBBBBBBBBBBBBBBBBBB\"", filler, "buy stamps on the way home"),
            "blob/a7/8f/8fea": bytes(String(repeating: filler, count: 9), "the end"),
        ])
        #expect(Cowork.taskID(startingWith: first + "\nmore", in: cache) == "cse_01AAAAAAAAAAAAAAAAAAAAAA")
        #expect(Cowork.taskID(startingWith: "buy stamps on the way home", in: cache) == "cse_01BBBBBBBBBBBBBBBBBBBBBB")
        #expect(Cowork.taskID(startingWith: "never sent", in: cache) == nil)
        #expect(Cowork.taskID(startingWith: "the end", in: cache) == nil)  // no id within 1 KB
        #expect(Cowork.taskID(startingWith: "  \n", in: cache) == nil)
    }

    /// A prompt kept as two-byte text, or as JSON that escapes its quotes, is still found by its opening words.
    @Test func aTaskIsFoundWhateverTheEncoding() throws {
        var twoByte = Data("\"\u{1c}cse_01AAAAAAAAAAAAAAAAAAAAAA".utf8)
        twoByte.append("Café — the Q4 invoice".data(using: .utf16LittleEndian)!)
        let cache = try claudeCache([
            "a": twoByte, "b": bytes(#"{"id":"cse_01BBBBBBBBBBBBBBBBBBBBBB","prompt":"Ask \"Arbor\" why"}"#),
        ])
        #expect(Cowork.taskID(startingWith: "Café — the Q4 invoice", in: cache) == "cse_01AAAAAAAAAAAAAAAAAAAAAA")
        #expect(Cowork.taskID(startingWith: "Ask \"Arbor\" why", in: cache) == "cse_01BBBBBBBBBBBBBBBBBBBBBB")
    }

    /// The length byte caps an id the next field's letter follows; a JSON id ends at its quote; a stub is no id.
    @Test func idsAreReadWholeAndNoFurther() {
        let ids = Cowork.taskIDs(
            in: bytes("cse_short \"\u{1c}cse_01AAAAAAAAAAAAAAAAAAAAAAN \"cse_01BBBBBBBBBBBBBBBBBBBBBB\" cse_"))
        #expect(ids.map(\.id) == ["cse_01AAAAAAAAAAAAAAAAAAAAAA", "cse_01BBBBBBBBBBBBBBBBBBBBBB"])
        #expect(ids.first?.at == 12)
    }
}

/// Cowork against a stand-in `open` (`FRAGMENTS_OPEN`) that logs each link, and a stand-in cache
/// (`FRAGMENTS_CLAUDE_CACHE`). Serial, because both are named in the process environment.
@Suite(.serialized) struct CoworkLaunchTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "cowork-test-\(UUID())")
    private var opened: [String] {
        ((try? String(contentsOf: folder.appending(path: "log"), encoding: .utf8)) ?? "").split(separator: "\n").map(
            String.init)
    }

    private func cowork(cache: [String: Data] = [:]) throws -> Cowork {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let standIn = folder.appending(path: "open")
        try "printf '%s\\n' \"$1\" >> '\(folder.path)/log'".write(to: standIn, atomically: true, encoding: .utf8)
        setenv("FRAGMENTS_OPEN", standIn.path, 1)
        setenv("FRAGMENTS_CLAUDE_CACHE", try claudeCache(cache).path, 1)
        return Cowork()
    }

    @Test func startOpensADraftAndKeepsTheSessionAsOne() throws {
        let session = try cowork().start(sample)
        #expect(session == Session(id: "draft"))
        #expect(opened == ["claude://cowork/new?q=buy%20stamps"])
    }

    /// Sent since: found by its opening words, opened, and handed back to be kept.
    @Test func attachFindsTheSentTaskAndHandsItBack() throws {
        let cowork = try cowork(cache: ["log": bytes("\"\u{1c}cse_01AAAAAAAAAAAAAAAAAAAAAAS\u{4}", "buy stamps")])
        let kept = try cowork.attach(sample, to: Session(id: "draft"))
        #expect(kept == Session(id: "cse_01AAAAAAAAAAAAAAAAAAAAAA"))
        #expect(opened == ["claude://claude.ai/cowork/cse_01AAAAAAAAAAAAAAAAAAAAAA"])
    }

    /// A known task opens straight away, with no look in the cache.
    @Test func attachOpensAKnownTask() throws {
        let kept = try cowork().attach(sample, to: Session(id: "cse_01BBBBBBBBBBBBBBBBBBBBBB"))
        #expect(kept == Session(id: "cse_01BBBBBBBBBBBBBBBBBBBBBB"))
        #expect(opened == ["claude://claude.ai/cowork/cse_01BBBBBBBBBBBBBBBBBBBBBB"])
    }

    /// Never sent, or no longer cached: the thought opens as a draft again, and stays one.
    @Test func attachOpensTheDraftAgainWhenClaudeHasNoTask() throws {
        let kept = try cowork().attach(sample, to: Session(id: "draft"))
        #expect(kept == Session(id: "draft"))
        #expect(opened == ["claude://cowork/new?q=buy%20stamps"])
    }
}

/// Rex against a stand-in `rex` (`FRAGMENTS_REX`) that logs what it was asked and answers like Rex Beta 1925. Serial,
/// because the stand-in is named in the process environment.
@Suite(.serialized) struct RexTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "rex-test-\(UUID())")
    private var log: String { (try? String(contentsOf: folder.appending(path: "log"), encoding: .utf8)) ?? "" }

    /// `alive` makes `session inspect` find the session; `select-fails` makes Rex refuse everything else (show, rename,
    /// kill); `ls-fails` makes `session ls` fail. `session ls` prints the file `sessions`.
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
        "session ls") [ -e ls-fails ] && { echo 'no server'; exit 1; } || cat sessions ;;
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
        #expect(manifest.icon == "terminal")
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

    /// The session is Rex's; what resumes it is Claude's conversation, chosen here.
    @Test func startOpensASessionNamedAfterTheFragmentAndShowsIt() throws {
        let session = try rex(settings: ["folder": folder.path]).start(sample)
        #expect(session.id == "session:new")
        let conversation = try #require(session.resume)
        #expect(UUID(uuidString: conversation) != nil)
        #expect(session.folder == folder.path)
        let calls = log.split(separator: "\n")
        #expect(calls.first?.hasPrefix("new frag-20261111-090000-00ff --cwd \(folder.path) --shell zsh") == true)
        #expect(log.contains("'claude' '--session-id' '\(conversation)' '--' 'buy stamps'"))
        #expect(calls.suffix(2) == ["client list --json", "-C client:app do session.select session_id=session:new"])
    }

    /// A fragment from before `resume:` kept Claude's id as its session: found by the name it was started under, and
    /// handed back in the new shape.
    @Test func attachShowsTheSessionWhileItIsAlive() throws {
        let kept = try rex("alive").attach(sample, to: Session(id: "sid", folder: "/p"))
        #expect(
            log.split(separator: "\n") == [
                "session inspect --json -- frag-20261111-090000-00ff", "client list --json",
                "-C client:app do session.select session_id=session:alive",
            ])
        #expect(kept == Session(id: "session:alive", folder: "/p", resume: "sid"))
    }

    /// By Rex's id first, so a session renamed in Rex is still found.
    @Test func attachFindsTheSessionByRexsIdWhateverItIsCalled() throws {
        let session = Session(id: "session:started", resume: "sid")
        try _ = rex("alive").attach(sample, to: session)
        #expect(log.hasPrefix("session inspect --json -- session:started\nclient list --json\n"))
    }

    /// Gone (a reboot): a new session resumes the conversation, and its id is handed back to be kept.
    @Test func attachResumesTheConversationWhenTheSessionIsGone() throws {
        let kept = try rex().attach(sample, to: Session(id: "session:gone", folder: folder.path, resume: "sid"))
        #expect(
            log.hasPrefix(
                "session inspect --json -- session:gone\nsession inspect --json -- frag-20261111-090000-00ff\n"
                    + "new frag-20261111-090000-00ff --cwd \(folder.path)"))
        #expect(log.contains("'claude' '--resume' 'sid'"))
        #expect(log.hasSuffix("do session.select session_id=session:new\n"))
        #expect(kept == Session(id: "session:new", folder: folder.path, resume: "sid"))
    }

    /// The session it opened is open whether or not Rex will show it, so the fragment keeps it and Rex comes forward.
    @Test func aSessionOpenedAgainIsKeptWhenRexWontShowIt() throws {
        let kept = try rex("select-fails").attach(sample, to: Session(id: "session:gone", resume: "sid"))
        #expect(kept.id == "session:new")
    }

    /// Opened again, a titled fragment's session takes the title by a rename, so one that starts with a dash is safe.
    @Test func aSessionOpenedAgainTakesTheTitle() throws {
        var titled = sample
        titled.title = "-fix it's broken"
        try _ = rex().attach(titled, to: Session(id: "sid", folder: folder.path))
        let calls = log.split(separator: "\n")
        #expect(
            calls.prefix(2) == [
                "session inspect --json -- -fix it's broken", "session inspect --json -- frag-20261111-090000-00ff",
            ])
        #expect(calls.contains("session rename -- session:new -fix it's broken"))
    }

    @Test func retitleRenamesTheRunningSession() throws {
        var titled = sample
        titled.title = "Login bug"
        try rex("alive").retitle(titled, in: Session(id: "session:started", resume: "sid"))
        #expect(
            log.split(separator: "\n") == [
                "session inspect --json -- session:started", "session rename -- session:alive Login bug",
            ])
        try rex("alive").retitle(sample, in: Session(id: "session:started", resume: "sid"))
        #expect(log.hasSuffix("session rename -- session:alive frag-20261111-090000-00ff\n"))
    }

    /// Nothing running: nothing to rename. Attach opens it again under the new title.
    @Test func retitleLeavesASessionThatIsGone() throws {
        var titled = sample
        titled.title = "Login bug"
        try rex().retitle(titled, in: Session(id: "session:gone", resume: "sid"))
        #expect(!log.contains("rename"))
        #expect(!log.contains("new "))
    }

    /// The session ↩ would show is the one that closes: found by Rex's id, killed by it.
    @Test func endClosesTheRunningSession() throws {
        try rex("alive").end(sample, in: Session(id: "session:started", resume: "sid"))
        #expect(
            log.split(separator: "\n") == [
                "session inspect --json -- session:started", "session kill -- session:alive",
            ])
    }

    /// Nothing running (closed, a reboot): nothing to close, and nothing is opened to close it.
    @Test func endLeavesASessionThatIsGone() throws {
        try rex().end(sample, in: Session(id: "session:gone", resume: "sid"))
        #expect(!log.contains("kill"))
        #expect(!log.contains("new "))
    }

    @Test func endSaysWhyRexWouldNotClose() throws {
        let rex = try rex("alive", "select-fails")
        #expect(throws: Rex.Problem.self) { try rex.end(sample, in: Session(id: "session:started", resume: "sid")) }
    }

    /// One `rex session ls` answers for every fragment. A name of its own is the title, `frag-<id>` is none, and a
    /// session Rex doesn't list or a fragment from before `resume:` says nothing.
    @Test func titlesAreTheNamesRexListsNow() throws {
        let rex = try rex()
        try """
        {"sessions": [{"session_id": "session:a", "label": "Renamed in Rex"},
          {"session_id": "session:b", "label": "frag-20261111-090000-00ff"}]}
        """.write(to: folder.appending(path: "sessions"), atomically: true, encoding: .utf8)
        func launched(_ id: String, _ session: Session) -> Fragment {
            var fragment = sample
            fragment.id = id
            fragment.session = session
            return fragment
        }
        let titles = try rex.titles(of: [
            launched("x", Session(id: "session:a", resume: "s1")),
            launched("20261111-090000-00ff", Session(id: "session:b", resume: "s2")),
            launched("y", Session(id: "session:gone", resume: "s3")),
            launched("z", Session(id: "session:a")),
        ])
        #expect(titles == ["x": "Renamed in Rex", "20261111-090000-00ff": nil])
        #expect(log == "session ls --json\n")
    }

    @Test func titlesSayNothingWhenRexIsntAnswering() throws {
        let titles = try rex("ls-fails").titles(of: [sample])
        #expect(titles.isEmpty)
    }

    @Test func retitleSaysWhyRexWouldNotRename() throws {
        let rex = try rex("alive", "select-fails")
        #expect(throws: Rex.Problem.self) { try rex.retitle(sample, in: Session(id: "sid")) }
    }

    @Test func attachSaysWhyRexWouldNotShowTheSession() throws {
        let rex = try rex("alive", "select-fails")
        #expect(throws: Rex.Problem.self) { try rex.attach(sample, to: Session(id: "sid")) }
        do {
            _ = try rex.attach(sample, to: Session(id: "sid"))
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

    /// An action is drawn with the icon it names; a manifest from before icons gets its kind's, and one still
    /// building gets a run's bolt.
    @Test func anActionsIconIsItsOwnElseItsKinds() {
        var named = found("rex", type: "launch")
        named.build = .built(Manifest(name: "Rex", chord: "cmd+r", type: "launch", icon: "terminal"))
        let building = FoundAction(
            id: "new", origin: .yours, program: URL(filePath: "/cache/yours/new/action"), build: .building)
        let actions = ActionCatalog.resolve(
            [named, found("ticket", chord: "cmd+t", type: "launch"), building], choices: [:])
        #expect(
            Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0.icon) })
                == ["rex": "terminal", "ticket": "arrow.uturn.backward.square", "new": "bolt"])
        #expect(ActionProgram.manifest(of: Ticket.self, type: .launch).icon == "arrow.uturn.backward.square")
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
