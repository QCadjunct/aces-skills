#!/usr/bin/env bash
# launch_demo2_generators.sh
# ACMS Demo Step 02 — deploy_generators.sh nine-step pipeline.
# Architecture Standard: Mind Over Metadata LLC — Peter Heller
#
# Usage:
#   ./launch_demo2_generators.sh

set -euo pipefail

NAVY='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
RESET='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(dirname "$SCRIPT_DIR")"
SOURCE_MD="${SKILLS_ROOT}/CodingArchitecture/FabricStitch/ACMS_extract_wisdom/system.md"
DEPLOY_SCRIPT="${SKILLS_ROOT}/MetaArchitecture/ACMS_skill_deployers/ACMS_skill_deploy_generators/deploy_generators.sh"

echo ""
echo -e "${BOLD}${NAVY}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${NAVY}║  Demo Step 02 — Skill Deployment Pipeline        ║${RESET}"
echo -e "${BOLD}${NAVY}║  system.md → system.yaml + system.toon           ║${RESET}"
echo -e "${BOLD}${NAVY}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${CYAN}Source :${RESET} ${SOURCE_MD}"
echo -e "  ${CYAN}Steps  :${RESET} VALIDATE RESOLVE ARCHIVE GENERATE WRITE CONFIRM DEPLOY LOG COST"
echo -e "  ${CYAN}Env    :${RESET} dev"
echo ""
echo -e "  ${DIM}Talking point: 'Nine steps. system.md is the single source of truth."
echo -e "  The generator derives system.yaml and system.toon as artifacts."
echo -e "  TOON delivers 19% token reduction on the wire. Zero cost — local Ollama.'${RESET}"
echo ""
echo -e "  ${DIM}──────────────────────────────────────────────────${RESET}"
echo ""

if [[ ! -f "$SOURCE_MD" ]]; then
  echo -e "  ERROR: system.md not found at ${SOURCE_MD}"
  exit 1
fi

if [[ ! -x "$DEPLOY_SCRIPT" ]]; then
  echo -e "  ERROR: deploy_generators.sh not found or not executable at ${DEPLOY_SCRIPT}"
  exit 1
fi

bash "$DEPLOY_SCRIPT" \
  --source "$SOURCE_MD" \
  --generate all \
  --env dev
