#!/usr/bin/env bash
# demo_03_cost.sh
# ACES POC Demo — Section 3: D⁴ MDLC Cost Intelligence
# Mind Over Metadata LLC © 2026 — Peter Heller
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RESET='\033[0m'

banner() {
  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║  $1$(printf '%*s' $((54 - ${#1})) '')║${RESET}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}\n"
}

section() { echo -e "\n${BOLD}${YELLOW}━━━ $1 ━━━${RESET}\n"; }

banner "ACES POC — Section 3: D⁴ MDLC Cost Intelligence"

# ── ADR-009 format explanation ────────────────────────────────────────────────
section "3.1 — ADR-009: Cost Audit Log Format"
echo -e "Every pipeline component writes to ${CYAN}~/.config/fabric/cost_audit.log${RESET}"
echo -e "Format: 16-field pipe-delimited (ADR-009)"
echo ""
echo -e "  [TIMESTAMP] | component | RUN_ID | skill_fqsn | artifact |"
echo -e "  vendor | model | tokens_in | tokens_out |"
echo -e "  cost_in | cost_out | cost_total | elapsed_ms | env | upstream_id | notes"
echo ""

section "3.2 — Live cost_audit.log (from Section 2 sync run)"
AUDIT_LOG="$HOME/.config/fabric/cost_audit.log"
if [[ -f "$AUDIT_LOG" ]] && [[ -s "$AUDIT_LOG" ]]; then
  echo -e "${BOLD}Raw log entries:${RESET}"
  cat "$AUDIT_LOG"
  echo ""
  echo -e "${BOLD}Entry count: $(wc -l < "$AUDIT_LOG")${RESET}"
else
  echo -e "${YELLOW}No live entries — run Section 2 first to populate${RESET}"
  echo -e "Seeding with test data for demonstration..."
  uv run python3 cost/cost_analyzer.py --seed 2>/dev/null || true
fi

echo ""
read -p "Press Enter to run cost_analyzer.py →"

# ── Summary report ────────────────────────────────────────────────────────────
section "3.3 — Cost Summary Report"
uv run python3 cost/cost_analyzer.py

read -p "Press Enter for bloat detection →"

# ── Bloat detection ───────────────────────────────────────────────────────────
section "3.4 — Bloat Detection (Boris Cherney Principle)"
echo -e "A bloated ${CYAN}skill.system.md${RESET} inflates every downstream consumer."
echo -e "Threshold: > 800 tokens = review recommended\n"
uv run python3 cost/cost_analyzer.py --bloat

read -p "Press Enter for TOON efficiency comparison →"

# ── TOON comparison ───────────────────────────────────────────────────────────
section "3.5 — TOON Efficiency: yaml vs toon"
echo -e "TOON (Token-Optimized Object Notation) reduces wire-format tokens."
echo -e "Target: ≥15% reduction vs YAML equivalent\n"
uv run python3 cost/cost_analyzer.py --compare

# ── D⁴ MDLC chain ────────────────────────────────────────────────────────────
section "3.6 — D⁴ MDLC Artifact Tier Chain"
echo -e "The cost chain follows the artifact tier hierarchy:"
echo ""
echo -e "  ${CYAN}tier_0_elicitation${RESET}  — requirements_*.system.md (PSA specialists)"
echo -e "  ${CYAN}tier_1_source${RESET}       — skill.system.md + transformer prompts"
echo -e "  ${CYAN}tier_2_derived${RESET}      — skill.system.yaml + skill.system.toon"
echo -e "  ${CYAN}tier_3_execution${RESET}    — fabric_stitch steps, langgraph nodes, hooks"
echo -e "  ${CYAN}tier_4_session${RESET}      — session.total (aggregated)"
echo ""
echo -e "The RUN_ID chains all artifacts from a single sync run."
echo -e "The UPSTREAM_ID chains execution back to the sync that produced the artifacts."

echo ""
echo -e "${GREEN}${BOLD}✓ Section 3 complete${RESET}"
echo ""
read -p "Press Enter for Section 4: Marimo Monitor →"
