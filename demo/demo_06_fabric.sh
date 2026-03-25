#!/usr/bin/env bash
# demo_06_fabric.sh
# ACMS POC Demo — Section 6: Fabric Multi-Vendor Pipeline
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

banner "ACMS POC — Section 6: Fabric Multi-Vendor Pipeline"

# ── FabricStitch overview ─────────────────────────────────────────────────────
section "6.1 — FabricStitch Architecture"
echo -e "FabricStitch chains Fabric pattern invocations into a multi-step,"
echo -e "multi-vendor pipeline. Each step selects the best model for its task:\n"
echo -e "  ${BOLD}ACES_extract_wisdom pipeline:${RESET}"
echo -e "  Step 1  ${CYAN}extract_wisdom${RESET}   → gemini-2.0-flash   (cost-optimized)"
echo -e "  Step 2  ${CYAN}summarize${RESET}         → claude-sonnet-4-6  (quality)"
echo -e "  Step 3  ${CYAN}extract_insights${RESET}  → gemini-2.0-flash   (cost-optimized)"
echo -e "  Step 4  ${CYAN}create_tags${RESET}       → qwen3:8b (Ollama)  (zero cost)"
echo -e "  Step 5  ${CYAN}pandoc${RESET}            → no LLM             (free)"
echo ""
echo -e "  ${BOLD}Cost per run:${RESET} ~\$0.0002 (95% of cost is Anthropic Step 2)"
echo -e "  ${BOLD}TOON savings:${RESET} ~14% token reduction on wire format"

read -p "Press Enter to run a live Fabric extraction →"

# ── Live fabric invocation ────────────────────────────────────────────────────
section "6.2 — Live: extract_wisdom from fabric-guide.md"
echo -e "Running: ${CYAN}fabric --model gemma3:12b --pattern extract_wisdom${RESET}\n"
echo -e "${YELLOW}Input: docs/fabric-guide.md (977 lines)${RESET}\n"

T_START=$(date +%s%3N)
WISDOM=$(fabric --model gemma3:12b \
  --pattern extract_wisdom \
  < docs/fabric-guide.md)
T_ELAPSED=$(( $(date +%s%3N) - T_START ))

echo -e "${BOLD}Extracted wisdom:${RESET}\n"
echo "$WISDOM"
echo ""
echo -e "  Elapsed: ${CYAN}${T_ELAPSED}ms${RESET}"
echo -e "  Input tokens (est): ${CYAN}$(wc -c < docs/fabric-guide.md | awk '{print int($1/4)}')${RESET}"
echo -e "  Output tokens (est): ${CYAN}$(echo "$WISDOM" | wc -c | awk '{print int($1/4)}')${RESET}"

read -p "Press Enter to see Fabric transformer for ACMS →"

# ── ACMS transformer ──────────────────────────────────────────────────────────
section "6.3 — ACMS Transformer Patterns"
echo -e "The ACMS uses two custom Fabric patterns to generate derived artifacts:\n"

echo -e "${BOLD}from_system.md_to_system.yaml (transformer prompt):${RESET}"
YAML_TRANS="$HOME/.config/fabric/patterns_custom/system.md_transformers/from_system.md_to_system.yaml/system.md"
if [[ -f "$YAML_TRANS" ]]; then
  head -20 "$YAML_TRANS"
  echo -e "\n${CYAN}... ($(wc -l < "$YAML_TRANS") lines, $(wc -c < "$YAML_TRANS" | awk '{print int($1/4)}') tokens)${RESET}"
else
  echo -e "${YELLOW}Transformer not found at: $YAML_TRANS${RESET}"
  echo "Deploy with: ./sync_skill.sh --source <path> --generate all"
fi

echo ""
echo -e "${BOLD}from_system.md_to_system.toon (transformer prompt):${RESET}"
TOON_TRANS="$HOME/.config/fabric/patterns_custom/system.md_transformers/from_system.md_to_system.toon/system.md"
if [[ -f "$TOON_TRANS" ]]; then
  head -20 "$TOON_TRANS"
  echo -e "\n${CYAN}... ($(wc -l < "$TOON_TRANS") lines, $(wc -c < "$TOON_TRANS" | awk '{print int($1/4)}') tokens)${RESET}"
else
  echo -e "${YELLOW}Transformer not found at: $TOON_TRANS${RESET}"
fi

# ── Model comparison ──────────────────────────────────────────────────────────
section "6.4 — Model Selection Strategy"
echo -e "  ${BOLD}FreedomTower (RTX 5080) — local models:${RESET}"
echo -e "  gemma3:12b    12s  zero cost  ← sync_skill default"
echo -e "  qwen3:8b      23s  zero cost  ← fallback"
echo -e "  qwen3:30b     ~45s zero cost  ← higher quality"
echo ""
echo -e "  ${BOLD}Cloud models (via Fabric vendor routing):${RESET}"
echo -e "  gemini-2.0-flash   3-5s   \$0.000000375/in  ← FabricStitch steps"
echo -e "  claude-sonnet-4-6  5-8s   \$0.000003/in     ← quality steps"
echo ""
echo -e "  ${BOLD}Decision rule:${RESET}"
echo -e "  Use local for: transformers, tagging, structured output"
echo -e "  Use Gemini for: extraction, analysis (cost-optimized)"
echo -e "  Use Claude for: summarization, synthesis (quality)"

echo ""
echo -e "${GREEN}${BOLD}✓ Section 6 complete${RESET}"
echo ""
read -p "Press Enter for Section 7: ADR-009 Provenance Chain →"
