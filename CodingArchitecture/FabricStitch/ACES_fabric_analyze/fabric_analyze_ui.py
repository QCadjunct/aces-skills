# /// script
# requires-python = ">=3.11"
# dependencies = ["marimo>=0.10.0", "pyyaml>=6.0"]
# ///
"""
fabric_analyze_ui.py — ACES FabricStitch Navigator UI
FQSN: CodingArchitecture/FabricStitch/fabric_analyze
VERSION: 1.0.0

Marimo reactive DCG application.
Four nodes:
  Node 1 — Manifest Builder (Navigator form)
  Node 2 — DCG Visualizer  (SVG dependency graph)
  Node 3 — Code Generator  (YAML · JSON · shell command)
  Node 4 — Executor        (write manifest + run pipeline)

Run:
  marimo run fabric_analyze_ui.py          # browser UI
  marimo edit fabric_analyze_ui.py         # editable notebook
"""

import marimo as mo
import json
import yaml
import os
import subprocess
import textwrap
from pathlib import Path
from datetime import datetime

app = mo.App(width="full", app_title="fabric_analyze — ACES FabricStitch Navigator")

# ═══════════════════════════════════════════════════════════════════════════════
# CONSTANTS
# ═══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR = Path(__file__).parent
SHELL_SCRIPT = SCRIPT_DIR / "fabric_analyze.sh"

ROLES = {
    "full":       "Full analysis — all 6 patterns (primary source)",
    "primary":    "Primary — deep analysis, no idea inventory",
    "contrast":   "Contrast — claims + questions + summary only",
    "supporting": "Supporting — insight + idea harvest",
    "background": "Background — quick context only",
}

ROLE_PATTERNS = {
    "full":       ["extract_article_wisdom","extract_wisdom","extract_ideas","extract_questions","analyze_claims","summarize"],
    "primary":    ["extract_article_wisdom","extract_wisdom","extract_questions","analyze_claims","summarize"],
    "contrast":   ["analyze_claims","extract_questions","summarize"],
    "supporting": ["extract_wisdom","extract_ideas","summarize"],
    "background": ["summarize","extract_article_wisdom"],
}

ROLE_COLORS = {
    "full":       "#02C39A",
    "primary":    "#065A82",
    "contrast":   "#CC2222",
    "supporting": "#1C7293",
    "background": "#7B3F00",
}

ALL_PATTERNS = [
    "extract_article_wisdom", "extract_wisdom", "extract_ideas",
    "extract_questions", "analyze_claims", "summarize",
    "synthesize_eloquent_narrative_from_wisdom",
]

VENDORS = ["Ollama", "Anthropic", "OpenAI", "Gemini", "Azure"]
DEFAULT_VENDOR = "Ollama"
DEFAULT_MODEL  = "qwen3.5:397b-cloud"

# ═══════════════════════════════════════════════════════════════════════════════
# NODE 0 — PAGE HEADER (static)
# ═══════════════════════════════════════════════════════════════════════════════

@app.cell
def _header():
    mo.md("""
    <div style="background:#0d1b3e;padding:20px 28px 14px;border-bottom:3px solid #02C39A;margin-bottom:24px">
      <div style="color:#02C39A;font-size:11px;font-family:monospace;letter-spacing:2px;margin-bottom:4px">
        CodingArchitecture / FabricStitch / fabric_analyze · v2.0.0
      </div>
      <div style="color:#FFFFFF;font-size:24px;font-weight:bold;font-family:'Trebuchet MS',sans-serif">
        🧵 fabric_analyze — ACES FabricStitch Navigator
      </div>
      <div style="color:#8BAFC4;font-size:13px;margin-top:6px;font-style:italic">
        Build a multi-source Fabric analysis pipeline as a DCG.
        Configure agents → visualize the graph → generate manifest + shell command → execute.
      </div>
    </div>
    """)
    return


# ═══════════════════════════════════════════════════════════════════════════════
# NODE 1 — MANIFEST BUILDER (Navigator Form)
# ═══════════════════════════════════════════════════════════════════════════════

@app.cell
def _task_config():
    mo.md("## ① Task Configuration")
    return

@app.cell
def _task_form():
    task_title = mo.ui.text(
        value="UOR Framework — Multi-Source Fabric Analysis",
        label="Analysis Title",
        full_width=True,
    )
    task_vendor = mo.ui.dropdown(
        options=VENDORS, value=DEFAULT_VENDOR, label="Default Vendor"
    )
    task_model = mo.ui.text(
        value=DEFAULT_MODEL, label="Default Model", full_width=True
    )
    task_word_limit = mo.ui.slider(
        start=500, stop=10000, step=500, value=4000,
        label="Narrative Word Limit (default)"
    )
    task_outdir = mo.ui.text(
        value="~/fabric-analysis", label="Output Directory", full_width=True
    )
    task_obsidian = mo.ui.text(
        value="", label="Obsidian Vault Path (optional)", full_width=True
    )
    task_consolidated = mo.ui.checkbox(value=True, label="Consolidated final document (merge all agent outputs)")
    task_skip_synthesis = mo.ui.checkbox(value=False, label="Skip synthesis (Stage 7)")
    task_skip_qa = mo.ui.checkbox(value=False, label="Skip Q&A enrichment (Stage 8)")
    task_skip_docx = mo.ui.checkbox(value=False, label="Skip pandoc .docx conversion")

    mo.vstack([
        mo.hstack([task_title, task_vendor, task_model], gap="16px"),
        mo.hstack([task_word_limit, task_outdir, task_obsidian], gap="16px"),
        mo.hstack([task_consolidated, task_skip_synthesis, task_skip_qa, task_skip_docx], gap="24px"),
    ], gap="12px")

    return (task_title, task_vendor, task_model, task_word_limit,
            task_outdir, task_obsidian, task_consolidated,
            task_skip_synthesis, task_skip_qa, task_skip_docx)


@app.cell
def _agent_header():
    mo.md("## ② Agent Definitions\n*Each agent = one source processed by its assigned pattern group.*")
    return


@app.cell
def _agent_form():
    # ── Agent rows — each agent is a set of UI controls ──────────────────────
    # We build a fixed set of N agent slots. Slots with empty source are ignored.
    # This avoids dynamic cell creation while still supporting up to 8 agents.

    N_SLOTS = 8

    # Source inputs
    sources = [
        mo.ui.text(value="" if i > 0 else "https://next.redhat.com/2022/07/13/the-uor-framework/",
                   label=f"Agent {i+1} — Source (URL or file path)",
                   full_width=True)
        for i in range(N_SLOTS)
    ]

    # Title inputs
    titles = [
        mo.ui.text(value="" if i > 0 else "UOR Framework — Red Hat Article",
                   label="Title", full_width=True)
        for i in range(N_SLOTS)
    ]

    # Role dropdowns
    roles = [
        mo.ui.dropdown(
            options=list(ROLES.keys()),
            value="full" if i == 0 else "supporting",
            label="Role"
        )
        for i in range(N_SLOTS)
    ]

    # Per-agent model overrides (blank = use task default)
    models = [
        mo.ui.text(value="", label="Model override (blank=default)", full_width=True)
        for i in range(N_SLOTS)
    ]

    # Per-agent word limit (0 = use task default)
    word_limits = [
        mo.ui.number(start=0, stop=10000, step=500, value=0,
                     label="Word limit (0=default)")
        for i in range(N_SLOTS)
    ]

    # Enabled toggles
    enabled = [
        mo.ui.checkbox(value=(i == 0), label="Enabled")
        for i in range(N_SLOTS)
    ]

    # Render agent slots in a table-like layout
    def agent_row(i):
        bg = "#0d1b3e" if i % 2 == 0 else "#111f45"
        color = ROLE_COLORS.get(roles[i].value, "#1C7293")
        return mo.vstack([
            mo.md(f"<div style='background:{bg};border-left:4px solid {color};padding:10px 14px;border-radius:4px'>"),
            mo.hstack([
                mo.md(f"**Agent {i+1}**"),
                enabled[i],
                roles[i],
            ], gap="16px"),
            mo.hstack([sources[i], titles[i]], gap="12px"),
            mo.hstack([models[i], word_limits[i]], gap="12px"),
            mo.md("</div>"),
        ], gap="6px")

    mo.vstack([agent_row(i) for i in range(N_SLOTS)], gap="8px")

    return sources, titles, roles, models, word_limits, enabled, N_SLOTS


# ═══════════════════════════════════════════════════════════════════════════════
# TASK DICT — assembled from all form values, consumed by Nodes 2, 3, 4
# ═══════════════════════════════════════════════════════════════════════════════

@app.cell
def _build_task(
    task_title, task_vendor, task_model, task_word_limit,
    task_outdir, task_obsidian, task_consolidated,
    task_skip_synthesis, task_skip_qa, task_skip_docx,
    sources, titles, roles, models, word_limits, enabled, N_SLOTS
):
    agents = []
    for i in range(N_SLOTS):
        src = sources[i].value.strip()
        if not src or not enabled[i].value:
            continue
        agent = {
            "source": src,
            "title":  titles[i].value.strip() or f"Source {i+1}",
            "role":   roles[i].value,
            "enabled": True,
        }
        if models[i].value.strip():
            agent["model"] = models[i].value.strip()
        if word_limits[i].value and word_limits[i].value > 0:
            agent["word_limit"] = int(word_limits[i].value)
        agents.append(agent)

    task = {
        "task": {
            "title":          task_title.value,
            "vendor":         task_vendor.value,
            "model":          task_model.value,
            "word_limit":     int(task_word_limit.value),
            "outdir":         task_outdir.value,
            "consolidated":   task_consolidated.value,
            "skip_synthesis": task_skip_synthesis.value,
            "skip_qa":        task_skip_qa.value,
            "skip_docx":      task_skip_docx.value,
        },
        "agents": agents,
    }
    if task_obsidian.value.strip():
        task["task"]["obsidian"] = task_obsidian.value.strip()

    return task,


# ═══════════════════════════════════════════════════════════════════════════════
# NODE 2 — DCG VISUALIZER
# ═══════════════════════════════════════════════════════════════════════════════

@app.cell
def _dcg_header():
    mo.md("## ③ DCG — Dependency Graph")
    return

@app.cell
def _dcg_viz(task):
    task = task[0]
    agents = task.get("agents", [])
    cfg    = task.get("task", {})

    if not agents:
        return mo.callout(mo.md("*No enabled agents — add at least one source above.*"), kind="warn"),

    # ── Layout constants ──────────────────────────────────────────────────────
    SVG_W    = 1200
    AGENT_W  = 180
    AGENT_H  = 80
    GAP_X    = 24
    START_X  = 40
    AGENT_Y  = 60
    SYN_Y    = 230
    EXEC_Y   = 340

    n        = len(agents)
    total_w  = max(SVG_W, n * (AGENT_W + GAP_X) + START_X * 2)
    SVG_H    = 420

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{total_w}" height="{SVG_H}" '
        f'viewBox="0 0 {total_w} {SVG_H}" style="background:#0d1b3e;border-radius:10px">',
        # Title bar
        f'<rect x="0" y="0" width="{total_w}" height="36" fill="#21295C"/>',
        f'<text x="{total_w//2}" y="24" text-anchor="middle" '
        f'font-family="Arial" font-size="13" font-weight="bold" fill="#02C39A" letter-spacing="1">'
        f'FABRIC ANALYZE — DCG · {n} agent{"s" if n!=1 else ""} · '
        f'{"consolidated" if cfg.get("consolidated") else "per-source"}</text>',
    ]

    # ── Draw arrows from agents → synthesis ──────────────────────────────────
    syn_cx  = total_w // 2
    syn_cy  = SYN_Y + 36

    for i, agent in enumerate(agents):
        ax = START_X + i * (AGENT_W + GAP_X)
        cx = ax + AGENT_W // 2
        cy = AGENT_Y + AGENT_H
        color = ROLE_COLORS.get(agent["role"], "#1C7293")

        if not cfg.get("skip_synthesis", False):
            # Draw line from agent bottom to synthesis top
            parts.append(
                f'<line x1="{cx}" y1="{cy}" x2="{syn_cx}" y2="{SYN_Y}" '
                f'stroke="{color}" stroke-width="1.5" stroke-dasharray="5,3" opacity="0.6"/>'
            )
            # Arrowhead
            parts.append(
                f'<polygon points="{syn_cx},{SYN_Y} {syn_cx-5},{SYN_Y-10} {syn_cx+5},{SYN_Y-10}" '
                f'fill="{color}" opacity="0.7"/>'
            )

    # ── Draw agent boxes ──────────────────────────────────────────────────────
    for i, agent in enumerate(agents):
        ax    = START_X + i * (AGENT_W + GAP_X)
        color = ROLE_COLORS.get(agent["role"], "#1C7293")
        src   = agent["source"]

        # Detect YouTube
        is_yt = "youtube.com" in src or "youtu.be" in src
        is_file = not src.startswith("http")
        icon = "▶" if is_yt else ("📄" if is_file else "🌐")

        # Truncate source label
        src_short = src.replace("https://","").replace("http://","")
        if len(src_short) > 22:
            src_short = src_short[:20] + "…"

        parts += [
            f'<rect x="{ax}" y="{AGENT_Y}" width="{AGENT_W}" height="{AGENT_H}" '
            f'rx="8" fill="#1B2A4A" stroke="{color}" stroke-width="2"/>',
            f'<rect x="{ax}" y="{AGENT_Y}" width="{AGENT_W}" height="26" '
            f'rx="8" fill="{color}"/>',
            f'<rect x="{ax}" y="{AGENT_Y+18}" width="{AGENT_W}" height="8" fill="{color}"/>',
            # Role label
            f'<text x="{ax+AGENT_W//2}" y="{AGENT_Y+17}" text-anchor="middle" '
            f'font-family="Arial" font-size="10" font-weight="bold" fill="#0d1b3e">'
            f'{icon} {agent["role"].upper()}</text>',
            # Title
            f'<text x="{ax+8}" y="{AGENT_Y+42}" '
            f'font-family="Arial" font-size="9" fill="#CADCFC">'
            f'{agent["title"][:22]}{"…" if len(agent["title"])>22 else ""}</text>',
            # Source
            f'<text x="{ax+8}" y="{AGENT_Y+56}" '
            f'font-family="Arial" font-size="8" fill="#8BAFC4" font-style="italic">'
            f'{src_short}</text>',
            f'<text x="{ax+8}" y="{AGENT_Y+70}" '
            f'font-family="Arial" font-size="8" fill="{color}">'
            f'{n_patterns} pattern{"s" if n_patterns!=1 else ""}</text>',
        ]

    # ── Synthesis node ────────────────────────────────────────────────────────
    if not cfg.get("skip_synthesis", False):
        syn_w = min(500, total_w - 100)
        syn_x = syn_cx - syn_w // 2
        parts += [
            f'<rect x="{syn_x}" y="{SYN_Y}" width="{syn_w}" height="72" '
            f'rx="10" fill="#21295C" stroke="#02C39A" stroke-width="2"/>',
            f'<rect x="{syn_x}" y="{SYN_Y}" width="{syn_w}" height="28" '
            f'rx="10" fill="#02C39A"/>',
            f'<rect x="{syn_x}" y="{SYN_Y+20}" width="{syn_w}" height="8" fill="#02C39A"/>',
            f'<text x="{syn_cx}" y="{SYN_Y+18}" text-anchor="middle" '
            f'font-family="Arial" font-size="12" font-weight="bold" fill="#0d1b3e">'
            f'synthesize_eloquent_narrative_from_wisdom v2.0.0-ACES</text>',
            f'<text x="{syn_cx}" y="{SYN_Y+44}" text-anchor="middle" '
            f'font-family="Arial" font-size="11" fill="#CADCFC">'
            f'word_limit={cfg.get("word_limit",4000)} · all agent outputs merged → one narrative</text>',
            f'<text x="{syn_cx}" y="{SYN_Y+62}" text-anchor="middle" '
            f'font-family="Arial" font-size="10" fill="#8BAFC4" font-style="italic">'
            f'Stage 7 of 8</text>',
        ]

        # Arrow synthesis → Q&A enrichment
        qa_cx = syn_cx
        qa_y  = SYN_Y + 72
        if not cfg.get("skip_qa", False):
            parts.append(
                f'<line x1="{qa_cx}" y1="{qa_y}" x2="{qa_cx}" y2="{EXEC_Y}" '
                f'stroke="#F59E0B" stroke-width="2" stroke-dasharray="5,3"/>'
            )
            parts.append(
                f'<polygon points="{qa_cx},{EXEC_Y} {qa_cx-5},{EXEC_Y-10} {qa_cx+5},{EXEC_Y-10}" '
                f'fill="#F59E0B"/>'
            )

    # ── Q&A / Output node ─────────────────────────────────────────────────────
    out_w = min(500, total_w - 100)
    out_x = syn_cx - out_w // 2
    out_color = "#F59E0B" if not cfg.get("skip_qa", False) else "#8BAFC4"
    out_label = "Q&A Enrichment + pandoc → .md + .docx"
    if cfg.get("skip_qa", False):
        out_label = "pandoc → .md + .docx (Q&A skipped)"
    if cfg.get("skip_docx", False):
        out_label = out_label.replace(" + .docx","")

    parts += [
        f'<rect x="{out_x}" y="{EXEC_Y}" width="{out_w}" height="56" '
        f'rx="10" fill="#21295C" stroke="{out_color}" stroke-width="2"/>',
        f'<rect x="{out_x}" y="{EXEC_Y}" width="{out_w}" height="24" '
        f'rx="10" fill="{out_color}"/>',
        f'<rect x="{out_x}" y="{EXEC_Y+16}" width="{out_w}" height="8" fill="{out_color}"/>',
        f'<text x="{syn_cx}" y="{EXEC_Y+16}" text-anchor="middle" '
        f'font-family="Arial" font-size="11" font-weight="bold" fill="#0d1b3e">'
        f'Stage 8 · Output</text>',
        f'<text x="{syn_cx}" y="{EXEC_Y+38}" text-anchor="middle" '
        f'font-family="Arial" font-size="11" fill="#CADCFC">'
        f'{out_label}</text>',
        f'<text x="{syn_cx}" y="{EXEC_Y+52}" text-anchor="middle" '
        f'font-family="Arial" font-size="10" fill="#8BAFC4" font-style="italic">'
        f'outdir: {cfg.get("outdir","~/fabric-analysis")}</text>',
    ]

    parts.append("</svg>")

    return mo.Html("\n".join(parts)),


# ═══════════════════════════════════════════════════════════════════════════════
# NODE 3 — CODE GENERATOR
# Three tabs: YAML manifest · JSON manifest · Shell command
# ═══════════════════════════════════════════════════════════════════════════════

@app.cell
def _codegen_header():
    mo.md("## ④ Generated Manifests & Shell Command")
    return

@app.cell
def _codegen(task):
    task = task[0]
    agents = task.get("agents", [])
    cfg    = task.get("task", {})

    if not agents:
        return mo.callout(mo.md("*No enabled agents — nothing to generate.*"), kind="warn"),

    # ── Enrich agents with resolved patterns ──────────────────────────────────
    def enrich_agent(a):
        out = dict(a)
        if "patterns" not in out:
            out["patterns"] = ROLE_PATTERNS.get(out["role"], ROLE_PATTERNS["full"])
        # YouTube detection note
        src = out["source"]
        if "youtube.com" in src or "youtu.be" in src:
            out["_input_flag"] = "-y  # YouTube transcript via yt-dlp"
        elif src.startswith("http"):
            out["_input_flag"] = "-u  # HTTP fetch"
        else:
            out["_input_flag"] = "stdin  # pandoc → plain text → pipe"
        return out

    enriched = [enrich_agent(a) for a in agents]

    # ── YAML ──────────────────────────────────────────────────────────────────
    # Build clean dict (no private _keys for export)
    export_agents = []
    for a in enriched:
        ea = {k: v for k, v in a.items() if not k.startswith("_")}
        export_agents.append(ea)

    yaml_dict = {
        "task":   cfg,
        "agents": export_agents,
    }
    yaml_str = yaml.dump(yaml_dict, default_flow_style=False,
                         sort_keys=False, allow_unicode=True,
                         width=100)

    yaml_header = textwrap.dedent(f"""\
        # fabric_analyze Task Definition
        # FQSN: CodingArchitecture/FabricStitch/fabric_analyze
        # Generated: {datetime.now().strftime("%Y-%m-%d %H:%M")}
        # Run: bash fabric_analyze.sh --manifest=fabric_analyze_task.yaml
        #
        # ROLES:  full | primary | contrast | supporting | background
        # INPUTS: any URL · youtube.com/youtu.be (auto -y) · any pandoc-readable file
        """)
    yaml_out = yaml_header + "\n" + yaml_str

    # ── JSON ──────────────────────────────────────────────────────────────────
    json_out = json.dumps({"task": cfg, "agents": export_agents},
                          indent=2, ensure_ascii=False)

    # ── TOON (Token-Optimised Object Notation) ────────────────────────────────
    # TOON: flat, tabular, minimal punctuation — efficient for LLM context
    toon_lines = [
        f"task.title={cfg.get('title','')}",
        f"task.vendor={cfg.get('vendor','')}",
        f"task.model={cfg.get('model','')}",
        f"task.word_limit={cfg.get('word_limit',4000)}",
        f"task.outdir={cfg.get('outdir','')}",
        f"task.consolidated={str(cfg.get('consolidated',True)).lower()}",
        f"task.skip_synthesis={str(cfg.get('skip_synthesis',False)).lower()}",
        f"task.skip_qa={str(cfg.get('skip_qa',False)).lower()}",
        f"task.skip_docx={str(cfg.get('skip_docx',False)).lower()}",
        "",
    ]
    for i, a in enumerate(export_agents):
        toon_lines.append(f"agent[{i}].source={a['source']}")
        toon_lines.append(f"agent[{i}].title={a.get('title','')}")
        toon_lines.append(f"agent[{i}].role={a.get('role','full')}")
        toon_lines.append(f"agent[{i}].patterns={','.join(a.get('patterns',[]))}")
        if "model" in a:
            toon_lines.append(f"agent[{i}].model={a['model']}")
        if "word_limit" in a:
            toon_lines.append(f"agent[{i}].word_limit={a['word_limit']}")
        toon_lines.append("")
    toon_out = "\n".join(toon_lines)

    # ── Shell command ─────────────────────────────────────────────────────────
    manifest_path = Path(cfg.get("outdir","~/fabric-analysis")).expanduser()
    manifest_yaml = "fabric_analyze_task.yaml"
    manifest_json = "fabric_analyze_task.json"

    # Single-source shorthand (if only one agent)
    if len(enriched) == 1:
        a = enriched[0]
        src = a["source"]
        flag = "--url" if src.startswith("http") else "--text-file"
        cmd_single = (
            f'bash fabric_analyze.sh \\\n'
            f'  {flag}="{src}" \\\n'
            f'  --title="{a.get("title","Analysis")}" \\\n'
            f'  --role={a.get("role","full")} \\\n'
            f'  --vendor={cfg.get("vendor","Ollama")} \\\n'
            f'  --model="{cfg.get("model",DEFAULT_MODEL)}" \\\n'
            f'  --word-limit={cfg.get("word_limit",4000)}'
        )
        if cfg.get("obsidian"):
            cmd_single += f' \\\n  --obsidian="{cfg["obsidian"]}"'
    else:
        cmd_single = None

    cmd_manifest = (
        f'# Write manifest first:\n'
        f'cat > fabric_analyze_task.yaml << EOF\n'
        f'{yaml_out}\n'
        f'EOF\n\n'
        f'# Then run:\n'
        f'bash fabric_analyze.sh --manifest=fabric_analyze_task.yaml'
    )

    # ── DCG execution order ───────────────────────────────────────────────────
    exec_steps = []
    for i, a in enumerate(enriched):
        patterns = a.get("patterns", ROLE_PATTERNS.get(a["role"], []))
        model    = a.get("model") or cfg.get("model", DEFAULT_MODEL)
        vendor   = a.get("vendor") or cfg.get("vendor", "Ollama")
        flag     = a["_input_flag"].split("#")[0].strip()
        exec_steps.append(
            f"  Step {i+1}: [{a['role'].upper()}] {a['title']}\n"
            f"    Source  : {a['source']}\n"
            f"    Input   : {flag}\n"
            f"    Vendor  : {vendor} / {model}\n"
            f"    Patterns: {' → '.join(patterns)}\n"
        )
    if not cfg.get("skip_synthesis"):
        exec_steps.append(
            f"  Step {len(enriched)+1}: [SYNTHESIS] synthesize_eloquent_narrative_from_wisdom\n"
            f"    Input   : all agent outputs combined\n"
            f"    Words   : {cfg.get('word_limit',4000)}\n"
        )
    if not cfg.get("skip_qa"):
        exec_steps.append(
            f"  Step {len(enriched)+2}: [Q&A] Inferred expert positions + follow-up probes\n"
            f"    Input   : extract_questions output + summarize context\n"
        )
    exec_steps.append(
        f"  Final   : pandoc → .md + "
        f"{'.docx' if not cfg.get('skip_docx') else '(docx skipped)'}\n"
        f"    Outdir  : {cfg.get('outdir','~/fabric-analysis')}\n"
    )
    exec_plan = "\n".join(exec_steps)

    # ── Render tabs ───────────────────────────────────────────────────────────
    result = mo.tabs({
        "YAML Manifest": mo.vstack([
            mo.md("*Copy → save as `fabric_analyze_task.yaml` → run the shell command below.*"),
            mo.ui.code_editor(value=yaml_out, language="yaml",
                              disabled=True, min_height="400px"),
        ]),
        "JSON Manifest": mo.vstack([
            mo.md("*Alternative format — same semantics as YAML.*"),
            mo.ui.code_editor(value=json_out, language="json",
                              disabled=True, min_height="400px"),
        ]),
        "TOON Manifest": mo.vstack([
            mo.md("*Token-Optimised Object Notation — efficient for LLM context windows. See toonformat.dev*"),
            mo.ui.code_editor(value=toon_out, language="text",
                              disabled=True, min_height="400px"),
        ]),
        "Shell Command": mo.vstack([
            mo.md("*Paste directly into FreedomTower WSL2 terminal.*"),
            mo.ui.code_editor(
                value=(cmd_single if cmd_single else cmd_manifest),
                language="bash", disabled=True, min_height="200px"
            ),
            mo.md("**Manifest-based command (for multi-agent):**") if cmd_single else mo.md(""),
            mo.ui.code_editor(value=cmd_manifest, language="bash",
                              disabled=True, min_height="200px") if cmd_single else mo.md(""),
        ]),
        "Execution Plan": mo.vstack([
            mo.md("*DCG execution order — what runs, in what sequence, with which patterns.*"),
            mo.ui.code_editor(value=exec_plan, language="text",
                              disabled=True, min_height="400px"),
        ]),
    })

    return result,


# ═══════════════════════════════════════════════════════════════════════════════
# NODE 4 — SAVE + EXECUTOR
# ═══════════════════════════════════════════════════════════════════════════════

@app.cell
def _executor_header():
    mo.md("## ⑤ Save Manifest & Execute Pipeline")
    return

@app.cell
def _executor_controls():
    save_dir   = mo.ui.text(
        value=str(SCRIPT_DIR),
        label="Save manifest to directory",
        full_width=True,
    )
    run_button = mo.ui.run_button(label="▶  Run fabric_analyze.sh")
    save_button = mo.ui.run_button(label="💾  Save Manifests Only")

    mo.hstack([
        mo.vstack([
            mo.md("**Save directory**"),
            save_dir,
        ]),
        mo.vstack([
            mo.md("&nbsp;"),
            mo.hstack([save_button, run_button], gap="12px"),
        ]),
    ], gap="24px", align="end")

    return save_dir, run_button, save_button


@app.cell
def _executor(task, save_dir, run_button, save_button):
    task = task[0]
    agents = task.get("agents", [])
    cfg    = task.get("task", {})

    if not agents:
        return mo.callout(mo.md("*No enabled agents — nothing to save or run.*"), kind="warn"),

    # Validation
    errors = []
    for i, a in enumerate(agents):
        if not a.get("source","").strip():
            errors.append(f"Agent {i+1}: source is empty")
    if errors:
        return mo.callout(
            mo.md("**Validation errors:**\n\n" + "\n".join(f"- {e}" for e in errors)),
            kind="danger"
        ),

    outpath = Path(save_dir.value).expanduser()

    def write_manifests():
        outpath.mkdir(parents=True, exist_ok=True)

        # Enrich agents
        def enrich(a):
            out = dict(a)
            if "patterns" not in out:
                out["patterns"] = ROLE_PATTERNS.get(out["role"], ROLE_PATTERNS["full"])
            return out

        enriched_agents = [enrich(a) for a in agents]
        export = {"task": cfg, "agents": enriched_agents}

        yaml_path = outpath / "fabric_analyze_task.yaml"
        json_path = outpath / "fabric_analyze_task.json"
        toon_path = outpath / "fabric_analyze_task.toon"

        with open(yaml_path, "w") as f:
            header = (
                f"# fabric_analyze Task Definition\n"
                f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}\n"
                f"# Run: bash fabric_analyze.sh --manifest=fabric_analyze_task.yaml\n\n"
            )
            f.write(header)
            yaml.dump(export, f, default_flow_style=False,
                      sort_keys=False, allow_unicode=True, width=100)

        with open(json_path, "w") as f:
            json.dump(export, f, indent=2, ensure_ascii=False)

        toon_lines = [f"task.{k}={v}" for k, v in cfg.items()]
        toon_lines.append("")
        for i, a in enumerate(enriched_agents):
            for k, v in a.items():
                val = ",".join(v) if isinstance(v, list) else str(v)
                toon_lines.append(f"agent[{i}].{k}={val}")
            toon_lines.append("")
        with open(toon_path, "w") as f:
            f.write("\n".join(toon_lines))

        return yaml_path, json_path, toon_path

    output_parts = []

    # ── Save manifests ────────────────────────────────────────────────────────
    if save_button.value:
        yaml_path, json_path, toon_path = write_manifests()
        output_parts.append(mo.callout(mo.md(
            f"**Manifests saved:**\n\n"
            f"- `{yaml_path}`\n"
            f"- `{json_path}`\n"
            f"- `{toon_path}`"
        ), kind="success"))

    # ── Execute pipeline ──────────────────────────────────────────────────────
    if run_button.value:
        if not SHELL_SCRIPT.exists():
            output_parts.append(mo.callout(
                mo.md(f"**Script not found:** `{SHELL_SCRIPT}`\n\n"
                      "Ensure `fabric_analyze.sh` is in the same directory as this file."),
                kind="danger"
            ))
        else:
            yaml_path, json_path, toon_path = write_manifests()
            output_parts.append(mo.callout(
                mo.md(f"**Manifests written.** Launching pipeline..."), kind="info"
            ))

            try:
                cmd = ["bash", str(SHELL_SCRIPT), f"--manifest={yaml_path}"]
                result = subprocess.run(
                    cmd,
                    capture_output=True,
                    text=True,
                    timeout=600,   # 10-minute timeout for large multi-agent runs
                )
                stdout = result.stdout or ""
                stderr = result.stderr or ""
                log    = (stdout + "\n" + stderr).strip()

                if result.returncode == 0:
                    output_parts.append(mo.callout(
                        mo.md("**Pipeline complete.**"), kind="success"
                    ))
                else:
                    output_parts.append(mo.callout(
                        mo.md(f"**Pipeline exited with code {result.returncode}.**"),
                        kind="danger"
                    ))

                output_parts.append(mo.vstack([
                    mo.md("**Health Log:**"),
                    mo.ui.code_editor(
                        value=log or "(no output)",
                        language="text",
                        disabled=True,
                        min_height="300px",
                    ),
                ]))

            except subprocess.TimeoutExpired:
                output_parts.append(mo.callout(
                    mo.md("**Timeout (10 min).** The pipeline is still running in the background.\n\n"
                          f"Check the health log in: `{cfg.get('outdir','~/fabric-analysis')}`"),
                    kind="warn"
                ))
            except Exception as ex:
                output_parts.append(mo.callout(
                    mo.md(f"**Exception:** `{ex}`"), kind="danger"
                ))

    if not output_parts:
        return mo.md(
            "*Use the buttons above to save manifests or run the full pipeline.*\n\n"
            f"**Script:** `{SHELL_SCRIPT}`  \n"
            f"**Agents ready:** {len(agents)}"
        ),

    return mo.vstack(output_parts),


# ═══════════════════════════════════════════════════════════════════════════════
# NODE 5 — PATTERN REFERENCE (static reference card)
# ═══════════════════════════════════════════════════════════════════════════════

@app.cell
def _reference():
    rows = []
    for role, patterns in ROLE_PATTERNS.items():
        color = ROLE_COLORS[role]
        rows.append(
            f"| <span style='color:{color};font-weight:bold'>{role}</span> "
            f"| {ROLES[role]} "
            f"| `{'` · `'.join(patterns)}` |"
        )

    mo.accordion({
        "Pattern Reference — Role Groups & All Available Patterns": mo.vstack([
            mo.md(
                "| Role | Description | Default Patterns |\n"
                "|---|---|---|\n" +
                "\n".join(rows)
            ),
            mo.md("**All available Fabric patterns in this pipeline:**\n\n" +
                  " · ".join(f"`{p}`" for p in ALL_PATTERNS)),
            mo.md(
                "**YouTube:** URLs containing `youtube.com/watch`, `youtu.be/`, or "
                "`youtube.com/shorts/` are auto-detected and routed to Fabric `-y` flag (yt-dlp transcript).\n\n"
                "**Files:** Any format pandoc can read — `.md .txt .pdf .docx .pptx .html "
                ".json .rst .org .epub .odt .csv` and more. pandoc converts to plain text, "
                "which is then piped to Fabric."
            ),
        ])
    })
    return


if __name__ == "__main__":
    app.run()
