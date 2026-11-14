#!/usr/bin/env bash
# SessionStart: make sure the generated Xcode project exists and matches project.yml.
set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
bin/setup >/dev/null 2>&1 || echo "bin/setup failed — run it by hand before building" >&2
exit 0
