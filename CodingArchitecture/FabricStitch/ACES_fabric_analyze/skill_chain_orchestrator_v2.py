#!/usr/bin/env python3
"""
skill_chain_orchestrator.py — ACES Skill Chain Orchestrator v2.0.0
FQSN: CodingArchitecture/FabricStitch/ACES_fabric_analyze

Three-phase sequential pipeline with $AND barrier per phase.
Each phase completes before the next starts.
Phase outputs are passed as context to subsequent phases.

Phase 1: Promise corpus  — extract claims from original source
Phase 2: Delivery corpus — extract current state from repo
Phase 3: Gap analysis    — promise vs delivery with AXIOM injection
Synthesis: Analytical brief — all phase outputs assembled

Author: Peter Heller / Mind Over Metadata LLC
Repo:   QCadjunct/aces-skills
"""

from __future__ import annotations

import argparse
import asyncio
import datetime
import json
import pathlib
import re
import subprocess
import sys
import time
import urllib.request
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional

import yaml


# ═══════════════════════════════════════════════════════════════════════════════
# DATA MODEL
# ═══════════════════════════════════════════════════════════════════════════════

class SubAgentStatus(Enum):
    COMPLETE  = "complete"
    FAILED    = "failed"
    CANCELLED = "cancelled"


@dataclass
class SubAgentDef:
    """One node in a phase execution graph."""
    pattern:        str
    label:          str  = ""
    vendor:         str  = "Ollama"
    model:          str  = "qwen3.5:397b-cloud"
    source:         str  = ""       # per-agent source override
    retry:          int  = 2
    timeout:        int  = 600
    enabled:        bool = True


@dataclass
class PhaseResult:
    """Result of one completed phase."""
    phase:       int
    label:       str
    pattern:     str
    output:      str
    elapsed_ms:  int
    attempts:    int
    status:      SubAgentStatus


@dataclass
class SynthesisNode:
    """Post-pipeline synthesis stage."""
    pattern:        str  = "synthesize_analysis_brief_from_wisdom"
    vendor:         str  = "Anthropic"
    model:          str  = "claude-opus-4-5"
    word_minimum:   int  = 5000
    word_target:    int  = 6500
    word_limit:     int  = 8000
    document_limit: int  = 15000
    directive:      str  = ""


@dataclass
class PhaseBarrier:
    """One phase with its $AND barrier."""
    phase:      int
    label:      str
    depends_on: list[int]
    agents:     list[SubAgentDef]


@dataclass
class SkillChain:
    """Complete phased skill chain definition."""
    title:      str
    source:     str
    vendor:     str
    model:      str
    outdir:     str
    obsidian:   str
    skip_docx:  bool
    phases:     list[PhaseBarrier]
    synthesis:  SynthesisNode

    @classmethod
    def from_yaml(cls, path: pathlib.Path) -> "SkillChain":
        data = yaml.safe_load(path.read_text())

        phases = []
        for ph in data.get("phases", []):
            agents = [
                SubAgentDef(
                    pattern = a["pattern"],
                    label   = a.get("label", a["pattern"]),
                    vendor  = a.get("vendor", data.get("vendor", "Ollama")),
                    model   = a.get("model",  data.get("model", "qwen3.5:397b-cloud")),
                    source  = a.get("source", ""),
                    retry   = a.get("retry",  2),
                    timeout = a.get("timeout", 600),
                    enabled = a.get("enabled", True),
                )
                for a in ph.get("agents", [])
            ]
            phases.append(PhaseBarrier(
                phase      = ph["phase"],
                label      = ph.get("label", f"Phase {ph['phase']}"),
                depends_on = ph.get("depends_on", []),
                agents     = agents,
            ))

        syn = data.get("synthesis", {})
        synthesis = SynthesisNode(
            pattern        = syn.get("pattern", "synthesize_analysis_brief_from_wisdom"),
            vendor         = syn.get("vendor", "Anthropic"),
            model          = syn.get("model",  "claude-opus-4-5"),
            word_minimum   = syn.get("word_minimum",   5000),
            word_target    = syn.get("word_target",    6500),
            word_limit     = syn.get("word_limit",     8000),
            document_limit = syn.get("document_limit", 15000),
            directive      = syn.get("directive", ""),
        )

        return cls(
            title     = data.get("title", "ACES Skill Chain Analysis"),
            source    = data.get("source", ""),
            vendor    = data.get("vendor", "Ollama"),
            model     = data.get("model",  "qwen3.5:397b-cloud"),
            outdir    = data.get("outdir", "~/fabric-analysis"),
            obsidian  = data.get("obsidian", ""),
            skip_docx = data.get("skip_docx", False),
            phases    = phases,
            synthesis = synthesis,
        )

    def dry_run(self) -> str:
        lines = [
            f"title:  {self.title}",
            f"source: {self.source}",
            f"phases: {len(self.phases)}",
            f"agents: {sum(len(p.agents) for p in self.phases)} total",
            "",
        ]
        for ph in self.phases:
            lines.append(f"Phase {ph.phase}: {ph.label}")
            lines.append(f"  depends_on: {ph.depends_on}")
            for a in ph.agents:
                src = a.source or "(chain.source)"
                lines.append(f"  [{a.pattern}] {a.vendor}/{a.model} → {src}")
            lines.append("")
        lines.append(f"synthesis: {self.synthesis.vendor}/{self.synthesis.model}")
        return "\n".join(lines)


# ═══════════════════════════════════════════════════════════════════════════════
# SOURCE DATE RESOLUTION
# ═══════════════════════════════════════════════════════════════════════════════

def resolve_source_date(source: str) -> Optional[datetime.date]:
    """
    Extract source publication date from URL or GitHub API.
    Articles: extract from URL path /YYYY/MM/DD/
    GitHub repos: fetch first commit date via API
    """
    # Strategy 1: date in URL path
    for pattern in [r"/(\d{4})/(\d{2})/(\d{2})/", r"(\d{4})-(\d{2})-(\d{2})"]:
        m = re.search(pattern, source)
        if m:
            try:
                return datetime.date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
            except ValueError:
                pass

    # Strategy 2: GitHub repo — fetch first commit date
    if "github.com" in source:
        try:
            gh = re.search(r"github\.com/([^/]+/[^/\s]+)", source)
            if gh:
                repo = gh.group(1).rstrip("/")
                url  = f"https://api.github.com/repos/{repo}/commits?per_page=1&order=asc"
                req  = urllib.request.Request(url, headers={
                    "User-Agent": "ACES-FabricStitch/2.0",
                    "Accept":     "application/vnd.github.v3+json",
                })
                with urllib.request.urlopen(req, timeout=10) as resp:
                    commits = json.loads(resp.read())
                    if commits:
                        raw = commits[-1]["commit"]["committer"]["date"][:10]
                        return datetime.date.fromisoformat(raw)
        except Exception:
            pass

    return None


# ═══════════════════════════════════════════════════════════════════════════════
# PHASE EXECUTOR
# ═══════════════════════════════════════════════════════════════════════════════

async def run_agent(
    agent:   SubAgentDef,
    source:  str,
    context: str = "",   # prior phase output passed as stdin context
) -> PhaseResult:
    """
    Execute one agent in a phase.
    If context is provided, prepend to stdin (for gap analysis).
    """
    effective_source = agent.source if agent.source else source
    is_url = effective_source.startswith("http")

    t_start = time.perf_counter()
    attempts = 0
    output   = ""

    for attempt in range(1, agent.retry + 2):
        attempts = attempt
        cmd = ["fabric", "-V", agent.vendor, "-m", agent.model, "-p", agent.pattern]

        stdin_data = None
        if context:
            # Gap analysis — receives prior phase outputs as stdin
            stdin_data = context.encode()
        elif is_url:
            cmd += ["-u", effective_source]
        else:
            if effective_source:
                stdin_data = effective_source.encode()

        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdin  = asyncio.subprocess.PIPE if stdin_data else None,
                stdout = asyncio.subprocess.PIPE,
                stderr = asyncio.subprocess.PIPE,
            )
            stdout, stderr = await asyncio.wait_for(
                proc.communicate(input=stdin_data),
                timeout=agent.timeout,
            )
            output = stdout.decode("utf-8", errors="replace").strip()
            if output:
                break
        except asyncio.TimeoutError:
            output = ""
        except Exception:
            output = ""

    elapsed = int((time.perf_counter() - t_start) * 1000)
    status  = SubAgentStatus.COMPLETE if output else SubAgentStatus.FAILED

    return PhaseResult(
        phase      = 0,   # set by caller
        label      = agent.label,
        pattern    = agent.pattern,
        output     = output,
        elapsed_ms = elapsed,
        attempts   = attempts,
        status     = status,
    )


# ═══════════════════════════════════════════════════════════════════════════════
# TEMPORAL AXIOM BUILDER
# ═══════════════════════════════════════════════════════════════════════════════

def build_temporal_axioms(chain: SkillChain) -> str:
    """
    Pre-calculate all temporal facts.
    Returns AXIOM: block — first content in any time-sensitive agent input.
    """
    today         = datetime.date.today()
    analysis_date = today.strftime("%Y-%m-%d")

    # Resolve source date from article URL or GitHub API
    # Use Phase 1 source (the promise source) as the reference date
    phase1_source = chain.source
    for ph in chain.phases:
        if ph.phase == 1 and ph.agents:
            s = ph.agents[0].source
            if s:
                phase1_source = s
            break

    source_date = resolve_source_date(phase1_source)

    if source_date:
        gap_days       = (today - source_date).days
        gap_years      = gap_days / 365.25
        short_elapsed  = gap_days > 730
        medium_elapsed = gap_days > 1826

        if medium_elapsed:
            horizon = "BOTH short-term (0-2yr) AND medium-term (2-5yr) ELAPSED"
            verdict = "Rate ALL short-term goals DELIVERED/PARTIAL/FAILED. No BEFORE."
        elif short_elapsed:
            horizon = "Short-term (0-2yr) ELAPSED. Medium-term (2-5yr) IN PROGRESS."
            verdict = "Rate ALL short-term goals DELIVERED/PARTIAL/FAILED. No BEFORE."
        else:
            horizon = f"Short-term NOT elapsed ({gap_days} of 730 days)"
            verdict = "BEFORE verdicts permitted for short-term goals."

        return (
            f"AXIOM:analysis_date={analysis_date}\n"
            f"AXIOM:source_date={source_date.strftime('%Y-%m-%d')}\n"
            f"AXIOM:gap_days={gap_days}\n"
            f"AXIOM:gap_years={gap_years:.1f}\n"
            f"AXIOM:short_elapsed={'yes' if short_elapsed else 'no'}\n"
            f"AXIOM:medium_elapsed={'yes' if medium_elapsed else 'no'}\n"
            f"AXIOM:horizon_status={horizon}\n"
            f"AXIOM:verdict_instruction={verdict}\n"
            "\n"
            f"PROTOCOL: analysis_date={analysis_date} is today. Not your training cutoff.\n"
            f"PROTOCOL: gap_days={gap_days} is pre-calculated. Do not recalculate.\n"
            "PROTOCOL: If axioms conflict with source timestamps, axioms win. Report conflict, then proceed.\n"
        )
    else:
        return (
            f"AXIOM:analysis_date={analysis_date}\n"
            "AXIOM:source_date=UNKNOWN\n"
            "AXIOM:gap_days=UNKNOWN\n"
            f"PROTOCOL: analysis_date={analysis_date} is today. Not your training cutoff.\n"
        )


# ═══════════════════════════════════════════════════════════════════════════════
# PHASED ORCHESTRATOR
# ═══════════════════════════════════════════════════════════════════════════════

async def run_phase(
    phase:          PhaseBarrier,
    chain:          SkillChain,
    phase_outputs:  dict[int, PhaseResult],
    axioms:         str,
) -> PhaseResult:
    """
    Execute one phase — single agent with $AND barrier.
    Phase 3 (ACES_gap_analysis) receives prior phase outputs as structured context.
    """
    agent = phase.agents[0]   # one agent per phase in v4.0.0

    # Build context for gap analysis phase
    context = ""
    if phase.phase == 3 and phase.depends_on:
        promise  = phase_outputs.get(1)
        delivery = phase_outputs.get(2)

        context = (
            f"{axioms}\n\n"
            "=== PROMISE CORPUS (original source — what was claimed) ===\n"
            f"{promise.output if promise else 'NO PROMISE OUTPUT'}\n\n"
            "=== DELIVERY CORPUS (current repo — what was delivered) ===\n"
            f"{delivery.output if delivery else 'NO DELIVERY OUTPUT'}\n\n"
            "Analyze the gap between PROMISE and DELIVERY using the AXIOM dates above."
        )

    result = await run_agent(agent, chain.source, context=context)
    result.phase = phase.phase
    return result


async def orchestrate(chain: SkillChain) -> None:
    """
    Phased sequential orchestrator:
      Phase 1 → $AND barrier → Phase 2 → $AND barrier → Phase 3 → Synthesis
    """
    print(f"\n{'═'*62}")
    print(f"  ACES SKILL CHAIN ORCHESTRATOR v2.0.0")
    print(f"  {chain.title}")
    print(f"{'─'*62}")
    print(f"  Source    : {chain.source}")
    print(f"  Phases    : {len(chain.phases)} sequential")
    print(f"  Synthesis : {chain.synthesis.pattern}")
    print(f"{'═'*62}")

    t_total = time.perf_counter()
    axioms  = build_temporal_axioms(chain)
    phase_outputs: dict[int, PhaseResult] = {}
    all_results:   list[PhaseResult]      = []

    # ── Execute phases sequentially ───────────────────────────────────────────
    for phase in sorted(chain.phases, key=lambda p: p.phase):

        # Wait for dependencies (already sequential but explicit)
        for dep in phase.depends_on:
            if dep not in phase_outputs:
                print(f"\n✗ Phase {phase.phase} dependency Phase {dep} not complete.")
                sys.exit(1)

        agent = phase.agents[0]
        print(f"\n{'─'*62}")
        print(f"  PHASE {phase.phase} — {phase.label}")
        print(f"  Pattern : {agent.pattern}")
        print(f"  Model   : {agent.vendor} / {agent.model}")
        src = agent.source or chain.source
        print(f"  Source  : {src[:60]}")
        print(f"{'─'*62}")

        t_phase = time.perf_counter()
        result  = await run_phase(phase, chain, phase_outputs, axioms)
        elapsed = int((time.perf_counter() - t_phase) * 1000)

        status_icon = "✓" if result.status == SubAgentStatus.COMPLETE else "✗"
        wc = len(result.output.split()) if result.output else 0
        print(f"  {status_icon}  {elapsed:,}ms · {wc:,} words · attempt={result.attempts}")

        if result.status == SubAgentStatus.FAILED:
            print(f"  ✗ Phase {phase.phase} failed — aborting pipeline.")
            sys.exit(1)

        phase_outputs[phase.phase] = result
        all_results.append(result)

    # ── Synthesis ─────────────────────────────────────────────────────────────
    print(f"\n{'─'*62}")
    print(f"  SYNTHESIS NODE")
    print(f"  Pattern : {chain.synthesis.pattern}")
    print(f"  Model   : {chain.synthesis.vendor} / {chain.synthesis.model}")
    print(f"{'─'*62}")

    narrative = await run_synthesis(chain, phase_outputs, axioms)

    wall_ms = int((time.perf_counter() - t_total) * 1000)

    if not narrative:
        print("\n✗ Synthesis returned empty output.")
        sys.exit(1)

    # ── Output ────────────────────────────────────────────────────────────────
    md_path, docx_path = write_output(chain, narrative, all_results, phase_outputs, wall_ms)

    print(f"\n{'═'*62}")
    print(f"  COMPLETE — {wall_ms:,}ms total wall time")
    seq = sum(r.elapsed_ms for r in all_results)
    print(f"  Sequential (phases)  : {seq:,}ms")
    print(f"  Markdown  : {md_path}")
    if docx_path:
        print(f"  Word doc  : {docx_path}")
    print(f"{'═'*62}\n")


# ═══════════════════════════════════════════════════════════════════════════════
# SYNTHESIS
# ═══════════════════════════════════════════════════════════════════════════════

async def run_synthesis(
    chain:         SkillChain,
    phase_outputs: dict[int, PhaseResult],
    axioms:        str,
) -> str:
    """Assemble synthesis input from all phase outputs and run synthesis."""

    def _compress(text: str, max_words: int = 500) -> str:
        words = text.split()
        if len(words) <= max_words:
            return text
        return " ".join(words[:max_words]) + "\n\n[...full output in Tier 2 archive]"

    p1 = phase_outputs.get(1)
    p2 = phase_outputs.get(2)
    p3 = phase_outputs.get(3)

    lines = [
        # AXIOMS FIRST — unmissable
        axioms,
        "",
        # Word budget
        f"word_minimum={chain.synthesis.word_minimum}",
        f"word_target={chain.synthesis.word_target}",
        f"word_limit={chain.synthesis.word_limit}",
        f"document_limit={chain.synthesis.document_limit}",
        "",
        # Section word ceilings — both floors AND ceilings enforced
        "SECTION WORD BUDGETS (floors AND ceilings — both enforced):",
        "  §1 Analytical Summary:        500-700 words.  Stop at 700.",
        "  §2 Vision & Strategic Intent: 900-1100 words. Stop at 1100.",
        "  §3 Goals by Horizon:         1700-2000 words. Stop at 2000.",
        "  §4 Temporal Gap Assessment:   400-600 words.  Stop at 600.",
        "  §5 Claims Verdict Table:      Complete ALL rows. No truncation.",
        "  §6 Discussion Questions:     1000-1300 words. Stop at 1300.",
        "  §7 Recommended Reading:       300-500 words.  Stop at 500.",
        "",
        "HARD REQUIREMENT: Complete ALL 7 sections before stopping.",
        "HARD REQUIREMENT: Do NOT expand §1-§3 beyond their ceilings.",
        "",
        "# STEP 1 — PROMISE CORPUS (2022 article — what was claimed)",
        _compress(p1.output) if p1 else "NO PROMISE OUTPUT",
        "",
        "# STEP 2 — DELIVERY CORPUS (current repo — what was delivered)",
        _compress(p2.output) if p2 else "NO DELIVERY OUTPUT",
        "",
        "# STEP 3 — GAP ANALYSIS (promise vs delivery)",
        _compress(p3.output) if p3 else "NO GAP ANALYSIS OUTPUT",
        "",
    ]

    synthesis_input = "\n".join(lines)

    cmd = [
        "fabric",
        "-V", chain.synthesis.vendor,
        "-m", chain.synthesis.model,
        "-p", chain.synthesis.pattern,
    ]

    t_s = time.perf_counter()
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdin  = asyncio.subprocess.PIPE,
        stdout = asyncio.subprocess.PIPE,
        stderr = asyncio.subprocess.PIPE,
    )
    stdout, stderr_out = await asyncio.wait_for(
        proc.communicate(input=synthesis_input.encode()),
        timeout=600,
    )
    elapsed = int((time.perf_counter() - t_s) * 1000)
    output  = stdout.decode("utf-8", errors="replace").strip()
    wc      = len(output.split())

    if not output and stderr_out:
        err = stderr_out.decode("utf-8", errors="replace").strip()
        print(f"  ✗  {elapsed:,}ms · stderr: {err[:200]}")
    else:
        print(f"  ✓  {elapsed:,}ms · {wc:,} words")

    return output


# ═══════════════════════════════════════════════════════════════════════════════
# OUTPUT WRITER
# ═══════════════════════════════════════════════════════════════════════════════

def write_output(
    chain:         SkillChain,
    narrative:     str,
    results:       list[PhaseResult],
    phase_outputs: dict[int, PhaseResult],
    wall_ms:       int,
) -> tuple[pathlib.Path, pathlib.Path | None]:

    outdir = pathlib.Path(chain.outdir.replace("~", str(pathlib.Path.home())))
    outdir.mkdir(parents=True, exist_ok=True)

    slug = re.sub(r"[^\w-]", "-", chain.source.replace("https://", ""))[:50]
    ts   = datetime.datetime.now().strftime("%Y-%m-%d-%H%M")

    md_path   = outdir / f"{slug}-gap-{ts}.md"
    docx_path = outdir / f"{slug}-gap-{ts}.docx"

    # Phase timing table
    timing_rows = "\n".join(
        f"  Phase {r.phase}: {r.pattern:<35} {r.elapsed_ms:>8,}ms  [{r.status.value}]"
        for r in results
    )

    # Tier 2 WORM archive
    tier2 = "\n\n".join(
        f"## Phase {ph}: {res.pattern}\n\n{res.output}"
        for ph, res in sorted(phase_outputs.items())
    )

    md_content = f"""---
title: "{chain.title}"
subtitle: "Three-Phase Gap Analysis · ACES FabricStitch v2.0.0"
author: "Peter Heller / Mind Over Metadata LLC"
date: "{datetime.datetime.now().strftime('%B %d, %Y')}"
source: "{chain.source}"
phases: "{len(results)}"
completed: "{len([r for r in results if r.status == SubAgentStatus.COMPLETE])}"
wall_time_ms: "{wall_ms}"
---

{narrative}

---
*TIER 2 — Phase Output Archive · WORM · Do not edit*

---

{tier2}

---

## Appendix — Phase Execution Health

```
Skill Chain : {chain.title}
Source      : {chain.source}
Wall time   : {wall_ms:,}ms

PHASE RESULTS
{timing_rows}

Synthesis   : {chain.synthesis.pattern}
              {chain.synthesis.vendor} / {chain.synthesis.model}
```

*skill_chain_orchestrator.py v2.0.0 · CodingArchitecture/FabricStitch/ACES_fabric_analyze*
"""

    md_path.write_text(md_content)

    if not chain.skip_docx:
        try:
            subprocess.run(
                ["pandoc", str(md_path),
                 "--from", "markdown-yaml_metadata_block",
                 "--to", "docx", "--toc", "-o", str(docx_path)],
                check=True, capture_output=True,
            )
        except (subprocess.CalledProcessError, FileNotFoundError):
            docx_path = None

    return md_path, docx_path


# ═══════════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(description="ACES Skill Chain Orchestrator v2.0.0")
    parser.add_argument("--chain",    required=True, help="Path to skill_chain.yaml")
    parser.add_argument("--dry-run",  action="store_true")
    args = parser.parse_args()

    chain_path = pathlib.Path(args.chain).expanduser()
    if not chain_path.exists():
        print(f"✗ Chain file not found: {chain_path}")
        sys.exit(1)

    chain = SkillChain.from_yaml(chain_path)

    if args.dry_run:
        print(f"\n═══ DRY RUN ═══\n{chain.dry_run()}")
        return

    asyncio.run(orchestrate(chain))


if __name__ == "__main__":
    main()
