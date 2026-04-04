#!/usr/bin/env python3
"""
_manifest_env.py — Extract task-level fields from manifest JSON.
Writes a bash-sourceable env file + prints N_AGENTS.

Usage: echo "$MANIFEST_DATA" | python3 _manifest_env.py /tmp/task_env_file
"""
import json, sys, pathlib

data = json.load(sys.stdin)
envf = pathlib.Path(sys.argv[1])
t    = data.get("task", {})
n    = len(data.get("agents", []))

def q(v):
    return "'" + str(v).replace("'", "'\\''") + "'"

lines = [
    f"TASK_TITLE={q(t.get('title', 'Analysis'))}",
    f"TASK_VENDOR={q(t.get('vendor', 'Ollama'))}",
    f"TASK_MODEL={q(t.get('model', 'qwen3.5:397b-cloud'))}",
    f"TASK_WLIMIT={t.get('word_limit', 4000)}",
    f"TASK_OUTDIR={q(t.get('outdir', '~/fabric-analysis'))}",
    f"TASK_OBSID={q(t.get('obsidian', ''))}",
    f"TASK_CONS={str(t.get('consolidated', False)).lower()}",
    f"TASK_SKIP_SYN={str(t.get('skip_synthesis', False)).lower()}",
    f"TASK_SKIP_QA={str(t.get('skip_qa', False)).lower()}",
    f"TASK_SKIP_DOC={str(t.get('skip_docx', False)).lower()}",
    f"N_AGENTS={n}",
]
envf.write_text("\n".join(lines) + "\n")
print(n)  # stdout: agent count for bash
