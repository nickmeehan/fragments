import Foundation
import Testing

@testable import Cowork
@testable import FragmentsAction
@testable import FragmentsCore

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
    return try ActionProgram.respond(to: verb, input: { data }, as: Remind.self, type: .run, perform: perform)
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
                found("remind"),
            ],
            choices: [:])
        #expect(actions.map(\.id) == ["cowork", "draft", "remind"])
        #expect(actions.map(\.on) == [true, false, true])
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

    @Test func reservedChordsBelongToKeepRexTheEditorAndMacOS() {
        let actions = ActionCatalog.resolve(
            [
                found("a", chord: "cmd+return"), found("b", chord: "cmd+shift+return"), found("c", chord: "cmd+v"),
                found("d", chord: "cmd+q"),
            ],
            choices: [:])
        #expect(actions.map(\.on) == [false, false, false, false])
        #expect(
            actions.map(\.problem) == ["keep uses ⌘↩.", "Rex uses ⌘⇧↩.", "the editor uses ⌘V.", "macOS uses ⌘Q."])
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
        let actions = ActionCatalog.resolve([newer, found("b", chord: "cmd+k", type: "launch")], choices: [:])
        #expect(actions.map(\.on) == [false, false])
        #expect(actions[0].problem == "It needs a newer Fragments (interface 2).")
        #expect(actions[1].problem == "This version of Fragments can't run “launch” actions yet.")
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

    @Test func theManifestIsReadThroughLoginShellNoise() {
        let output =
            "zprofile says hi\n" + #"{"chord":"cmd+r","name":"Remind","protocol":1,"settings":[],"type":"run"}"# + "\n"
        #expect(ActionBuild.manifest(in: output) == Manifest(name: "Remind", chord: "cmd+r", type: "run"))
        #expect(ActionBuild.manifest(in: "error: no such file") == nil)
        #expect(ActionBuild.manifest(in: "{not json}") == nil)
    }
}
