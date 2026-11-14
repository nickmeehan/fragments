#!/usr/bin/env bash
# PreToolUse (Bash): hard stops no instruction can override.
set -uo pipefail
input=$(cat)
hooks_dir="$(cd "$(dirname "$0")" && pwd)"
cmd=$(echo "$input" | python3 -I "$hooks_dir/json-field.py" tool_input.command)
[ -n "$cmd" ] || exit 0

deny() {
  session=$(echo "$input" | python3 -I "$hooks_dir/json-field.py" session_id)
  "$hooks_dir/audit-log.sh" guard-bash deny "$cmd" "$session"
  echo "BLOCKED (hard guardrail): $1" >&2
  exit 2
}

# `git -C <dir> push` and `git -c <key>=<value> push` are pushes too.
push='\bgit( +-[Cc] +[^ |&;]+)* +push\b'
echo "$cmd" | grep -qE "$push"'[^|&;]*(--force|-f\b)' &&
  deny "force-push. Fix history locally or stop and ask the user."
echo "$cmd" | grep -qE "$push"'[^|&;]*\bmain\b' &&
  deny "direct push to main. Open a PR."
echo "$cmd" | grep -qE 'rm -r[f ]*[^|&;]*(~|\$HOME|/Users/[^/ ]+)/Fragments\b' &&
  deny "deleting the user's real fragments folder. Tests use FRAGMENTS_DIR in a temp dir."
echo "$cmd" | grep -qE '\btccutil\b' &&
  deny "resetting privacy permissions (tccutil). The user grants Accessibility by hand."
exit 0
