#!/usr/bin/env bash
# Stop hook: "done means green," enforced. If source changed since the last green run, run bin/ci;
# a red build blocks the stop and injects the failures.
set -uo pipefail
input=$(cat)
echo "$input" | grep -Eq '"stop_hook_active": *true' && exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
[ -x bin/ci ] || exit 0
mkdir -p tmp
watched=(Fragments FragmentsCore FragmentsUITests project.yml bin .swift-format)

marker=tmp/.ci_green
if [ -f "$marker" ]; then
  # ponytail: mtime check misses pure deletions; the next full bin/ci catches those.
  changed=$(find "${watched[@]}" -type f -newer "$marker" 2>/dev/null | grep -v '/\.build/' | head -1)
  [ -z "$changed" ] && exit 0
elif [ -z "$(git status --porcelain -- "${watched[@]}" 2>/dev/null)" ]; then
  exit 0
fi

if bin/ci > tmp/ci_stop_hook.log 2>&1; then
  date > "$marker"
  exit 0
fi
hooks_dir="$(cd "$(dirname "$0")" && pwd)"
session=$(echo "$input" | python3 -I "$hooks_dir/json-field.py" session_id)
first_fail=$(grep "❌" tmp/ci_stop_hook.log | head -1)
"$hooks_dir/audit-log.sh" check-ci block "${first_fail:-bin/ci red at stop}" "$session"
{
  echo "bin/ci is RED — the task isn't done. Failing steps:"
  grep "❌" tmp/ci_stop_hook.log
  echo "--- last 40 lines (full log: tmp/ci_stop_hook.log) ---"
  tail -40 tmp/ci_stop_hook.log
  echo "Fix the causes (fix-ci skill), then finish."
} >&2
exit 2
