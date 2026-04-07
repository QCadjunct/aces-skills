#!/usr/bin/env bash
# demo_02_sync.sh
# ACES POC Demo — Section 2: Live Sync Pipeline
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

banner "ACES POC — Section 2: Live Sync Pipeline"

# ── sync_skill.sh overview ────────────────────────────────────────────────────
section "2.1 — sync_skill.sh — Nine-Step Pipeline"
echo -e "sync_skill.sh is the ACES Task Definition Language executor."
echo -e "It transforms system.md into system.yaml + system.toon via Fabric.\n"
echo -e "  Step 1  VALIDATE    — required sections present"
echo -e "  Step 2  HASH        — MD5 change detection"
echo -e "  Step 3  DIFF        — show what changed"
echo -e "  Step 4  ARCHIVE     — timestamped backup of prior artifacts"
echo -e "  Step 5  GENERATE    — fabric transformer invocations"
echo -e "  Step 6  VALIDATE    — YAML parse + TOON line count"
echo -e "  Step 7  DEPLOY      — copy to patterns_custom/"
echo -e "  Step 8  HASH-STORE  — save new MD5"
echo -e "  Step 9  COST        — ADR-009 per-artifact cost entries"
echo ""
echo -e "Model: ${CYAN}gemma3:12b${RESET} (local, zero cost, ~12s per transformer)"
echo ""
read -p "Press Enter to run a DRY RUN first →"

# ── Dry run ───────────────────────────────────────────────────────────────────
section "2.2 — Dry Run (no files written)"
./sync_skill.sh \
  --source CodingArchitecture/FabricStitch/ACES_extract_wisdom/system.md \
  --generate all \
  --env dev \
  --dry-run \
  --force

echo ""
read -p "Press Enter to run LIVE (generates yaml + toon via gemma3:12b) →"

# ── Live run ──────────────────────────────────────────────────────────────────
section "2.3 — Live Run (~25 seconds)"
echo -e "${YELLOW}Generating system.yaml and system.toon via gemma3:12b...${RESET}\n"

> ~/.config/fabric/cost_audit.log

./sync_skill.sh \
  --source CodingArchitecture/FabricStitch/ACES_extract_wisdom/system.md \
  --generate all \
  --env dev \
  --force

# ── Show generated artifacts ──────────────────────────────────────────────────
section "2.4 — Generated Artifacts"
SKILL="CodingArchitecture/FabricStitch/ACES_extract_wisdom"

echo -e "${BOLD}system.yaml (full):${RESET}"
cat "$SKILL/system.yaml"
echo ""
echo -e "${BOLD}system.toon (full):${RESET}"
cat "$SKILL/system.toon"

# ── Token comparison ──────────────────────────────────────────────────────────
section "2.5 — Token Comparison: yaml vs toon"
YAML_TOKENS=$(wc -c < "$SKILL/system.yaml" | awk '{print int($1/4)}')
TOON_TOKENS=$(wc -c < "$SKILL/system.toon" | awk '{print int($1/4)}')
SRC_TOKENS=$(wc -c < "$SKILL/system.md" | awk '{print int($1/4)}')
REDUCTION=$(python3 -c "print(f'{($YAML_TOKENS - $TOON_TOKENS) / $YAML_TOKENS * 100:.1f}')")

echo -e "  skill.system.md   : ${CYAN}${SRC_TOKENS} tokens${RESET} (source)"
echo -e "  skill.system.yaml : ${CYAN}${YAML_TOKENS} tokens${RESET} (derived)"
echo -e "  skill.system.toon : ${CYAN}${TOON_TOKENS} tokens${RESET} (derived)"
echo -e "  TOON reduction    : ${GREEN}${REDUCTION}%${RESET}"
echo ""

echo -e "${GREEN}${BOLD}✓ Section 2 complete${RESET}"
echo ""
read -p "Press Enter for Section 3: Cost Intelligence →"
