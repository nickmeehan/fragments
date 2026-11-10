---
paths:
  - "Fragments/**/*.swift"
---

# Fragments app — the shell

- Map events into `Key`, ask `AppModel`, perform the `Command`. No domain decisions here.
- Processes go through `Shell.run` (login-shell PATH); Wispr Flow through `Dictation` (its URL scheme).
- Nothing here needs a privacy grant: hotkeys are Carbon, dictation is a URL. Keep it that way.
- Swift 6 strict concurrency: UI and model code is `@MainActor`; don't reach for `@unchecked`.
