#!/usr/bin/env bash
# Append one JSONL line to the agent audit ledger: audit-log.sh <hook> <decision> <detail> [session_id]
# The ledger (log/agent_audit.jsonl, gitignored) is the observability layer; post-pr-audit.sh attaches
# it to PRs. Recurring entries usually mean a miscalibrated gate, not a bad agent.
set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
mkdir -p log
python3 -I -c '
import json, sys, datetime
print(json.dumps({"ts": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
  "hook": sys.argv[1], "decision": sys.argv[2], "detail": sys.argv[3][:300], "session": sys.argv[4]}))
' "${1:-unknown}" "${2:-}" "${3:-}" "${4:-}" >> log/agent_audit.jsonl 2>/dev/null
exit 0
