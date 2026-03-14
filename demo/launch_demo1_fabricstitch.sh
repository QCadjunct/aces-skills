#!/usr/bin/env bash
# launch_demo1_fabricstitch.sh
# ACMS Demo Step 01 — FabricStitch multi-vendor AI pipeline.
# Architecture Standard: Mind Over Metadata LLC — Peter Heller
#
# Usage:
#   ./launch_demo1_fabricstitch.sh              # uses default URL
#   ./launch_demo1_fabricstitch.sh --url "..."  # override URL
#
# Default: Rick Astley "Never Gonna Give You Up" — deterministic, known-good output.

set -euo pipefail

NAVY='\033[0;34m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
DIM='\033[2m'
RESET='\033[0m'
BOLD='\033[1m'

DEFAULT_URL="https://www.youtube.com/watch?v=dQw4w9WgXcQ"
URL="$DEFAULT_URL"

# Parse --url override
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) URL="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(dirname "$SCRIPT_DIR")"
SKILL_DIR="${SKILLS_ROOT}/CodingArchitecture/FabricStitch/ACMS_extract_wisdom"
FABRIC_STITCH="${SKILL_DIR}/fabric_stitch.sh"

echo ""
echo -e "${BOLD}${NAVY}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${NAVY}║  Demo Step 01 — FabricStitch Pipeline            ║${RESET}"
echo -e "${BOLD}${NAVY}║  Multi-vendor AI — Gemini · Claude · Ollama      ║${RESET}"
echo -e "${BOLD}${NAVY}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${CYAN}URL   :${RESET} ${URL}"
echo -e "  ${CYAN}Skill :${RESET} ${SKILL_DIR}"
echo -e "  ${CYAN}Env   :${RESET} dev"
echo ""
echo -e "  ${DIM}Talking point: 'This is a multi-vendor AI pipeline — Gemini Flash,"
echo -e "  Claude Sonnet, local Ollama. One command. Every step is counted,"
echo -e "  every token is billed, every cost is receipted.'${RESET}"
echo ""
echo -e "  ${DIM}──────────────────────────────────────────────────${RESET}"
echo ""

if [[ ! -x "$FABRIC_STITCH" ]]; then
  echo -e "  ERROR: fabric_stitch.sh not found at ${FABRIC_STITCH}"
  exit 1
fi

cd "$SKILL_DIR"
bash "$FABRIC_STITCH" --url "$URL" --env dev
