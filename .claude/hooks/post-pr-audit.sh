#!/usr/bin/env bash
# PostToolUse (Bash): after `gh pr create`, attach the audit ledger to the PR as a comment and rotate it.
set -uo pipefail
input=$(cat)
hooks_dir="$(cd "$(dirname "$0")" && pwd)"
cmd=$(echo "$input" | python3 -I "$hooks_dir/json-field.py" tool_input.command)
echo "$cmd" | grep -qE '\bgh pr create\b' || exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
ledger=log/agent_audit.jsonl
[ -s "$ledger" ] || exit 0

summary=$(python3 -I -c '
import json, sys, collections
events = []
for line in open(sys.argv[1]):
    try: events.append(json.loads(line))
    except Exception: pass
if not events: sys.exit(0)
print(f"<details><summary>Agent guardrail ledger ({len(events)} events)</summary>\n")
groups = collections.OrderedDict()
for e in events: groups.setdefault((e.get("hook"), e.get("decision")), []).append(e)
for (hook, decision), es in groups.items():
    print(f"- **{hook} → {decision}** ×{len(es)}")
    for e in es[-3:]: print(f"  - `{e.get(\"detail\")}`")
print("\n_Recurring entries here usually mean a gate needs recalibrating, not that the agent misbehaved._\n</details>")
' "$ledger" 2>/dev/null)
[ -n "$summary" ] || exit 0
if gh pr comment --body "$summary" >/dev/null 2>&1; then
  : > "$ledger"
fi
exit 0
