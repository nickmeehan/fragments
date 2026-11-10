---
paths:
  - "FragmentsCore/Tests/**/*.swift"
  - "FragmentsUITests/**/*.swift"
---

# Tests

- Core tests use a temp `FragmentStore`; never the real `~/.fragments`.
- UI tests launch with `FRAGMENTS_DIR` and `FRAGMENTS_NO_DICTATION=1` so they never touch user
  data or trigger Wispr Flow.
- No `XCTSkip`, no `.disabled` traits (hook-blocked). A test that can't run here is a documented
  `bin/ci --ui` step, not a deleted one.
