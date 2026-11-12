---
paths:
  - "FragmentsCore/Tests/**/*.swift"
  - "FragmentsUITests/**/*.swift"
---

# Tests

- Core tests use a temp `FragmentStore`; never the real `~/.fragments`.
- UI tests launch with `FRAGMENTS_DIR`, `FRAGMENTS_NO_DICTATION=1` and `FRAGMENTS_CHOICES_IN_MEMORY=1` so
  they never touch user data or preferences, or trigger Wispr Flow. The test runner is sandboxed: it can't read
  the app's preferences, so check what the app shows or the files it writes in the temp folder.
- No `XCTSkip`, no `.disabled` traits (hook-blocked). A test that can't run here is a documented
  `bin/ci --ui` step, not a deleted one.
