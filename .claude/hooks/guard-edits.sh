#!/usr/bin/env bash
# PreToolUse (Edit|Write): block the dodges that turn a red build green. Scans only ADDED content.
set -uo pipefail
input=$(cat)
hooks_dir="$(cd "$(dirname "$0")" && pwd)"
file=$(echo "$input" | python3 -I "$hooks_dir/json-field.py" tool_input.file_path)
case "$file" in
  *.md | *.claude/* ) exit 0 ;;
esac
added=$(echo "$input" | python3 -I -c '
import json, sys
ti = json.load(sys.stdin).get("tool_input", {})
parts = [ti.get("new_string"), ti.get("content")] + [e.get("new_string") for e in ti.get("edits", [])]
print("\n".join(p for p in parts if p))
' 2>/dev/null)
[ -n "$added" ] || exit 0

if echo "$added" | grep -qE 'XCTSkip|swift-format-ignore|@Test\([^)]*\.disabled|\.disabled\(["(]'; then
  session=$(echo "$input" | python3 -I "$hooks_dir/json-field.py" session_id)
  "$hooks_dir/audit-log.sh" guard-edits deny "forbidden token added to $file" "$session"
  echo "BLOCKED (hard guardrail): this edit skips or disables a test or a lint. Fix the cause instead (fix-ci skill). If you believe this is a legitimate exception, stop and ask the user." >&2
  exit 2
fi
exit 0
