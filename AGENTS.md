# AGENTS.md

Fragments: a macOS menu-bar app (Swift 6, SwiftUI + AppKit, macOS 14+) for hotkey-driven capture of
thoughts that become notes or Claude Code sessions. "Done" means `bin/ci` is green. Most rules are
enforced by tooling (hooks, bin/ci); this file holds only what a machine can't check.

## Layout

- `FragmentsCore/` — Swift package, zero dependencies, pure logic: `FragmentStore` (the ~/.fragments folder),
  `AppModel` (the panel state machine), `ActionCatalog` (which actions capture offers), `ActionBuild` (how they
  compile), `LoginShell` (how the app runs a program with the user's PATH), `HintLabels`, `KeyCombo`. Everything here
  runs under `swift test` in seconds. Put logic here first.
- `FragmentsCore/Sources/FragmentsAction/` — what every action imports: `Fragment`, `Session`, the
  `OpenAction`/`RunAction`/`LaunchAction` protocols, `@Setting`, the JSON both sides speak. Foundation only: the app
  ships it as source and compiles it with the user's `swiftc`, so it must build on its own. Changing it changes a
  public interface (`Manifest.protocol`).
- `FragmentsCore/Actions/<id>/` — the bundled actions (Cowork; Rex, which starts Claude Code in a Rex session),
  shaped exactly like a user's `~/.fragments/actions/<id>/`. The app compiles both kinds the same way (`ActionBuild`,
  `Fragments/ActionHost`).
- `Fragments/` — the app shell: hotkeys (Carbon), the floating panel, SwiftUI views, Settings,
  Wispr Flow trigger, process execution. Thin; it maps events into Core and performs Core's Commands.
- `FragmentsUITests/` — XCUITests that press real keys in the built app (`bin/ci --ui`).
- `fixtures/` — the fragments and actions `bin/renders` draws: a note, a Rex launch, a Cowork hand-off, a long one; an
  action with a setting of each kind, and one that doesn't compile.
- `project.yml` — XcodeGen spec; the .xcodeproj is generated and git-ignored. Never edit the project
  file by hand; add files to disk and regenerate (`bin/setup`).
- Fragments on disk: `~/.fragments/<id>.md` with YAML-ish front matter; `~/.fragments/actions/<id>/*.swift` are the
  user's actions, compiled into `~/Library/Caches/Fragments/actions/`. Override with `FRAGMENTS_DIR` (tests do), and
  `rex` with `FRAGMENTS_REX` (UI tests point it at a stand-in).

## Commands

- `bin/ci` — format, lint, core tests, app build; `bin/ci --ui` adds the UI tests
- `bin/run [--capture|--list]` — build and relaunch the app
- `swift test --package-path FragmentsCore` — fast loop for Core
- `open 'fragments://new?text=hi'` / `open fragments://list` — drive a running app from a shell
- `bin/renders [--against REF]` — every panel screen drawn by the app itself from `fixtures/` (capture, ⌘K, the list,
  ⌘, Actions and each action's view, detail) into `tmp/renders/head/`; with `--against`, REF's into `base/` and the
  screens that differ in `summary.md`. Unchanged screens come out identical. Uses the app's `--snapshot DIR` mode.
- `bin/check-rex` — the real Rex and Claude Code, driven like ⌘⇧↩ and ↩ with a harmless prompt (Nick's Mac only)
- Red build? Use the fix-ci skill.

## Verifying a change

Run each layer your change can break, cheapest first, and say in the PR what you ran and saw.

- `bin/ci`: logic, every keystroke in `AppModel`, each bundled action against a stand-in. Every change.
- `bin/ci --ui`: the real app with real key presses (capture, list, hotkey, ⌘K, ⌘,, launch → attach, Rex against a
  stand-in). Any change to `Fragments/`, a view or an action.
- `bin/renders --against origin/main`: open every changed PNG. A change someone can see goes in front of Nick as
  these renders, never as a mock-up; a screen that changed and shouldn't have is a regression.
- CI runs all three on every PR (the `ui` job) and comments the changed screens. Without a Mac (a cloud session):
  push, `gh pr checks --watch`, then `gh run download <run id> -n renders -D tmp/renders` and look.
- Rex, Claude Code, Cowork and Wispr Flow exist only on Nick's Mac. A change to how Rex is driven: `bin/check-rex`
  there, or ask Nick to run it.

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
  goes in your final message, with what to verify once it's done.
