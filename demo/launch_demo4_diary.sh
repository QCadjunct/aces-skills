#!/usr/bin/env bash
# launch_demo4_diary.sh
# ACMS Demo Step 04 — open Navigator Diary in Obsidian.
# Architecture Standard: Mind Over Metadata LLC — Peter Heller
#
# Opens Obsidian to the NavigatorDiary vault graph view.
# Falls back to Windows Explorer if Obsidian URI fails.
#
# Usage:
#   ./launch_demo4_diary.sh

set -euo pipefail

NAVY='\033[0;34m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
DIM='\033[2m'
RESET='\033[0m'
BOLD='\033[1m'

VAULT_NAME="NavigatorDiary"
VAULT_WIN_PATH="C:\\Users\\pheller\\Documents\\Obsidian Vault\\NavigatorDiary"
# Obsidian URI — opens vault directly
OBSIDIAN_URI="obsidian://open?vault=${VAULT_NAME}"

echo ""
echo -e "${BOLD}${NAVY}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${NAVY}║  Demo Step 04 — Navigator Diary                  ║${RESET}"
echo -e "${BOLD}${NAVY}║  28 files · 39 diagrams · 97 cross-links         ║${RESET}"
echo -e "${BOLD}${NAVY}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${CYAN}Vault :${RESET} ${VAULT_NAME}"
echo -e "  ${CYAN}Path  :${RESET} ${VAULT_WIN_PATH}"
echo ""
echo -e "  ${DIM}Talking point: 'Everything I just showed you is documented here."
echo -e "  28 files. 39 Mermaid diagrams. 97 cross-links. Six months of"
echo -e "  architectural decisions. The Navigator role produces artifacts."
echo -e "  Not just code.'${RESET}"
echo ""
echo -e "  ${DIM}What to show: Graph view → 03-Lessons-Learned/ → flat-deploy-pattern.md${RESET}"
echo ""
echo -e "  ${DIM}──────────────────────────────────────────────────${RESET}"
echo ""

echo -e "  ${GREEN}→${RESET}  Opening Obsidian — ${VAULT_NAME}..."
explorer.exe "$OBSIDIAN_URI" 2>/dev/null || \
  explorer.exe "$VAULT_WIN_PATH" 2>/dev/null || \
  echo -e "  Open Obsidian manually and switch to vault: ${VAULT_NAME}"
