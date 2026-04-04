#!/usr/bin/env python3
"""
_agent_env.py — Extract agent fields from JSON to a bash-sourceable env file.
Called by fabric_analyze.sh for each agent in manifest mode.
Usage: echo "$AGENT_JSON" | python3 _agent_env.py /tmp/agent_env_file
"""
import json, sys, pathlib

a    = json.load(sys.stdin)
envf = pathlib.Path(sys.argv[1])
pats = a.get("patterns", [])

def q(v):
    """Quote a value for bash sourcing — wrap in single quotes, escape any internal ones."""
    return "'" + str(v).replace("'", "'\\''") + "'"

lines = [
    f"A_ENABLED={str(a.get('enabled', True)).lower()}",
    f"A_SOURCE={q(a.get('source', ''))}",
    f"A_TITLE={q(a.get('title', ''))}",
    f"A_ROLE={q(a.get('role', 'full'))}",
    f"A_VENDOR={q(a.get('vendor', ''))}",
    f"A_MODEL={q(a.get('model', ''))}",
    f"A_WLIMIT={a.get('word_limit', 0)}",
    f"A_OBSID={q(a.get('obsidian', ''))}",
    f"A_PATS={q(' '.join(pats))}",
]
envf.write_text("\n".join(lines) + "\n")
