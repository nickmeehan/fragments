---
name: domain-modeling
description: Use when deciding where behavior lives in Fragments — designing a type in FragmentsCore, adding a panel mode or keystroke, a new action (Codex, another terminal), or asking "should this be a manager / service / coordinator". Triggers on "how should I model X", "where does this logic go", or any restructuring of Fragment, FragmentStore, AppModel, Launcher or the app shell.
---

# Domain Modeling

Rich domain types, thin shell, no ceremony. Ported from Jordan Byron's Rails domain-modeling
notes (https://gist.github.com/jordanbyron/5e6e4a25ed6c7365f5c2634e12f31a02) to this Swift app.
Strong defaults, not commandments.

## The Core Idea

The domain model *is* the application and it lives in `FragmentsCore`: `Fragment` knows how to
read and write itself as Markdown, `FragmentStore` knows the folder, `AppModel` knows every
keystroke's meaning and every mode transition, `Launcher` knows exactly which shell lines start
and re-open an agent. The app target (`Fragments/`) is the shell: it turns NSEvents into `Key`s,
hands them to `AppModel`, and performs the `Command` that comes back (show a window, run a
process, post a key event). Views render state.

When someone asks "where should this logic go?", the answer is almost always: on the Core type
that owns that knowledge. Not in a view. Not in a `SessionManager`, `CaptureCoordinator` or
`LaunchService`. If it can be expressed without AppKit, it goes in Core and gets a test.

## Rich Types, Thin Shell

The shell should read like a table of contents. `PanelController.handle` is the model: map the
event, ask the model, switch on the command. If a shell method grows domain decisions ("if the
draft is empty…", "if Rex is not installed…"), that decision belongs on the model or on
`Launcher`.

```swift
// Good — the shell states intent, Core decides
switch model.handle(key) {
case .launch(let fragment): hide(); Runner.launch(fragment, store: model.store)
...
}

// Core owns the rules
public func commit(action: Action) -> Fragment?  // trims, refuses empties, mints the session
```

## Decomposition: Extensions and Nested Types, Not Services

A Core type that accumulates behavior is decomposed with extensions grouped by capability and
nested types (`Session.Runner`, `AppModel.Mode`, `AppModel.Command`). The type's main declaration
is a manifest of its stored state; extensions hold cohesive slices (Markdown, navigation, launch).

Extract an extension when a cluster of methods serves one capability you can name. Don't extract
for a single method, and never to hide complexity you haven't actually reduced.

## Commands as the Boundary

Side effects are *values* (`AppModel.Command`) returned to the shell, never performed by Core.
That is what lets the whole keystroke grammar — hints, j/k, chords, esc semantics — run under
`swift test` without a window. A new side effect is a new `Command` case plus one `switch` arm in
`PanelController`; it is not a closure injected into the model.

## Naming and Language

Name things after what they *are* in the domain: `Fragment`, `Session`, `Launcher`,
`HintLabels`. Not after patterns: no `FragmentManager`, `SessionService`, `LaunchStrategy`.
If you reach for "-er"/"-or" nouns, first try a verb on the type that owns the data.

## State as Values

Modes are an enum with payloads (`.detail(id)`), not a cluster of booleans. A session's existence
is `fragment.session != nil`, with its ids and folder attached, not an `isAgent` flag plus loose
fields. Prefer modeling a transition as producing a new value over mutating flags.

## Keep Dependencies at Zero

`FragmentsCore` has none and the app has none beyond Apple frameworks. Carbon hotkeys, CGEvent,
NSPanel and `Process` cover what a KeyboardShortcuts/HotKey/ShellOut package would. Fight hard
before adding one; every dependency is an upgrade burden and another thing an agent must learn.

## Summary of Defaults

| Situation | Default approach |
|---|---|
| Where does behavior go? | On the Core type that owns the knowledge |
| New keystroke or mode? | `Key`/`Mode`/`Command` in `AppModel`, with a test |
| New way to run an agent? | `Session.Runner` case + `Launcher` functions + a `Runner` switch arm |
| New kickoff (Codex, Reminders…)? | An action, not app code: a folder with one `@main` type conforming to `OpenAction` or `RunAction`, bundled in `FragmentsCore/Actions/<id>/` or yours in `~/.fragments/actions/<id>/`. Its options are `@Setting` properties |
| New interaction type? | Rare: a protocol and `ActionType` case in `FragmentsAction`, its handling in `ActionCatalog`/`AppModel`, and a `Manifest.currentProtocol` bump only if old actions would be misread |
| Shell growing decisions? | Move the decision into Core, return a `Command` |
| "Should I add a package?" | Probably not |
| "Should I make a Manager/Service?" | No — extension on the owning type |
