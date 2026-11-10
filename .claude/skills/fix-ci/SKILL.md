---
name: fix-ci
description: Use when bin/ci is red, a Stop hook reports failing steps, xcodebuild or swift test fails, or swift-format lint rejects a file. Diagnose from the first ❌, fix the cause, never the gate.
---

# Fix CI

`bin/ci` runs: xcodegen → format → lint → core tests → app build (→ ui tests with `--ui`). The first
❌ is the one to fix; later steps often fail as a consequence.

1. Read `tmp/ci_stop_hook.log` (or re-run the single step from `bin/ci` by hand).
2. **lint**: the formatter already ran; what's left is a real rule. Fix the code. Never add
   `swift-format-ignore` (hook-blocked).
3. **core tests**: `swift test --package-path FragmentsCore --filter <SuiteName>` to iterate fast.
   A failing test is a spec; change the code unless the test contradicts the task.
4. **app build**: `xcodebuild … build 2>&1 | grep -E 'error:'`. Swift 6 concurrency errors mean a
   value crossed an isolation boundary; fix with `@MainActor`, `Sendable`, or by keeping the work
   on the main actor, not with `@unchecked` or `nonisolated(unsafe)`.
5. **ui tests**: need a logged-in desktop and Accessibility for Xcode's test runner. If the
   environment can't provide that, say so; don't delete the test.
6. Re-run `bin/ci` until green. Weakening thresholds, disabling tests, or skipping steps is not a fix.
