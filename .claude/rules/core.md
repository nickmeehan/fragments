---
paths:
  - "FragmentsCore/**/*.swift"
---

# FragmentsCore — pure logic, zero dependencies

- No AppKit, SwiftUI or CoreGraphics here. Foundation and Observation only.
- Behavior goes on the type that owns the knowledge; side effects are returned as
  `AppModel.Command` values, never performed.
- Every public function gets a test in `Tests/FragmentsCoreTests` (Swift Testing, `#expect`).
- Markdown format changes must keep `Fragment(markdown:)` reading every file ever written.
