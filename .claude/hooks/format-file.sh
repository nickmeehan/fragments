#!/usr/bin/env bash
# PostToolUse (Edit|Write): format the Swift file just written, then report what lint still rejects.
set -uo pipefail
input=$(cat)
hooks_dir="$(cd "$(dirname "$0")" && pwd)"
file=$(echo "$input" | python3 -I "$hooks_dir/json-field.py" tool_input.file_path)
case "$file" in
  *.swift ) ;;
  * ) exit 0 ;;
esac
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
[ -f "$file" ] || exit 0
xcrun swift-format format --in-place "$file" >/dev/null 2>&1
if ! out=$(xcrun swift-format lint --strict "$file" 2>&1); then
  session=$(echo "$input" | python3 -I "$hooks_dir/json-field.py" session_id)
  "$hooks_dir/audit-log.sh" format-file feedback "lint findings in $file" "$session"
  {
    echo "swift-format lint: findings in $file (formatting already applied):"
    echo "$out" | tail -20
    echo "Resolve these before finishing; bin/ci enforces them either way."
  } >&2
  exit 2
fi
exit 0
