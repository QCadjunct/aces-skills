#!/usr/bin/env python3
"""
_manifest_agent.py — Extract one agent from manifest JSON by index.
Usage: echo "$MANIFEST_DATA" | python3 _manifest_agent.py INDEX
Prints JSON of that agent to stdout.
"""
import json, sys

data  = json.load(sys.stdin)
idx   = int(sys.argv[1])
agents = data.get("agents", [])
if idx < len(agents):
    print(json.dumps(agents[idx]))
else:
    print("{}")
