# Prints one dotted field from the hook's stdin JSON. Usage: json-field.py tool_input.command
import json
import sys

try:
    value = json.load(sys.stdin)
    for part in sys.argv[1].split("."):
        value = value.get(part, "") if isinstance(value, dict) else ""
    if isinstance(value, list):
        value = "\n".join(str(v) for v in value)
    print(value if value is not None else "")
except Exception:
    print("")
