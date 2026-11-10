#!/usr/bin/env bash
# SessionStart: make sure the generated Xcode project exists and matches project.yml, and that the
# private decisions log (docs/, a gitignored clone of nickmeehan/fragments-docs) is present.
set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
bin/setup >/dev/null 2>&1 || echo "bin/setup failed — run it by hand before building" >&2
[ -d docs/.git ] || git clone -q git@github.com:nickmeehan/fragments-docs.git docs 2>/dev/null ||
  echo "docs/ (private decisions log) is unavailable here; put notes for Nick's hands in the PR description" >&2
exit 0
