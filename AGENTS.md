# AGENTS.md

Fragments: a macOS menu-bar app (Swift 6, SwiftUI + AppKit, macOS 14+) for hotkey-driven capture of
thoughts that become notes or Claude Code sessions. "Done" means `bin/ci` is green. Most rules are
enforced by tooling (hooks, bin/ci); this file holds only what a machine can't check.

## Layout

- `FragmentsCore/` — Swift package, zero dependencies, pure logic: `FragmentStore` (the ~/.fragments folder),
  `AppModel` (the panel state machine), `ActionCatalog` (which actions capture offers), `ActionBuild` (how they
  compile), `Launcher` (the script and `rex` commands that start sessions), `HintLabels`, `KeyCombo`. Everything here runs under `swift test`
  in seconds. Put logic here first.
- `FragmentsCore/Sources/FragmentsAction/` — what every action imports: `Fragment`, the `OpenAction`/`RunAction`
  protocols, `@Setting`, the JSON both sides speak. Foundation only: the app ships it as source and compiles it with
  the user's `swiftc`, so it must build on its own. Changing it changes a public interface (`Manifest.protocol`).
- `FragmentsCore/Actions/<id>/` — the bundled actions (Cowork), shaped exactly like a user's
  `~/.fragments/actions/<id>/`. The app compiles both kinds the same way (`ActionBuild`, `Fragments/ActionHost`).
- `Fragments/` — the app shell: hotkeys (Carbon), the floating panel, SwiftUI views, Settings,
  Wispr Flow trigger, process execution. Thin; it maps events into Core and performs Core's Commands.
- `FragmentsUITests/` — one XCUITest smoke flow (`bin/ci --ui`).
- `project.yml` — XcodeGen spec; the .xcodeproj is generated and git-ignored. Never edit the project
  file by hand; add files to disk and regenerate (`bin/setup`).
- Fragments on disk: `~/.fragments/<id>.md` with YAML-ish front matter; `~/.fragments/.sessions/*.sh`
  are the scripts that start agents; `~/.fragments/actions/<id>/*.swift` are the user's actions, compiled into
  `~/Library/Caches/Fragments/actions/`. Override with `FRAGMENTS_DIR` (tests do).

## Commands

- `bin/ci` — format, lint, core tests, app build; `bin/ci --ui` adds the UI smoke test
- `bin/run [--capture|--list]` — build and relaunch the app
- `swift test --package-path FragmentsCore` — fast loop for Core
- `open 'fragments://new?text=hi'` / `open fragments://list` — drive a running app from a shell
- `open -n build/DerivedData/Build/Products/Debug/Fragments.app --args --snapshot DIR -fragmentsDir FIXTURES -dictation NO`
  — image the capture, list and detail panels into DIR as PNGs, then quit. Needs no Screen Recording
  grant; seed FIXTURES with a few `.md` fragments first.
- Red build? Use the fix-ci skill.

## Judgment (what tooling can't check)

- Surface assumptions before building. Multiple readings of the task? Name them and pick one out
  loud, or ask. Simpler approach? Say so; push back.
- Changes are surgical: every changed line traces to the task. When a change exposes a design
  problem, propose the refactor; don't do it unbidden.
- New module or interface? Sketch two approaches and pick with reasons (design-it-twice). Deep lens:
  the philosophy-of-software-design skill. Where behavior lives: the domain-modeling skill.
- Side effects (processes, key events, windows) stay in `Fragments/`; state and decisions stay in
  `FragmentsCore/` where they are testable.
- Commits follow Conventional Commits v1.0.0 (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`,
  `chore:`), imperative mood, one logical change each.
- Never weaken a gate to get green: no disabled tests, no `swift-format-ignore`, no skipped steps.
  Genuinely blocked? Stop and surface it with your analysis instead of routing around.
- Anything that needs the user's hands (the UI-test automation grant, Xcode sign-in, an OS upgrade for Rex)
  is noted in `docs/decisions.md` with what to verify once it's done. `docs/` is private: a gitignored
  clone of `nickmeehan/fragments-docs` that the session-start hook creates, never tracked here.
  Commit inside it and push with `git -C docs push`. Where `docs/` is missing (cloud sessions), put
  the note in the PR description instead.
