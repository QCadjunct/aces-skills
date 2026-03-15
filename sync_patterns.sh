#!/usr/bin/env bash
# sync_patterns.sh
# Sync ACMS custom patterns to Fabric's flat patterns/ directory.
# Copies system.md + system.yaml + system.toon from each leaf skill
# in patterns_custom/ to a flat folder in patterns/.
#
# Architecture:
#   patterns_custom/  — ACMS taxonomy (conservation, survives fabric --updatepatterns)
#   patterns/         — Fabric flat namespace (what fabric --pattern invokes)
#
# Usage:
#   ./sync_patterns.sh              — sync all custom patterns
#   ./sync_patterns.sh --dry-run    — preview without writing
#   ./sync_patterns.sh --verbose    — show all files copied
#
# Run after: fabric --updatepatterns (to restore customizations)
# Run after: any new skill is synced via sync_skill.sh
#
# Mind Over Metadata LLC © 2026 — Peter Heller
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

PATTERNS_DIR="$HOME/.config/fabric/patterns"
CUSTOM_DIR="$HOME/.config/fabric/patterns_custom"
DRY_RUN=false
VERBOSE=false
COPIED=0
SKIPPED=0
UPDATED=0

BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'
YELLOW='\033[0;33m'; RESET='\033[0m'

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --verbose) VERBOSE=true ;;
  esac
done

echo -e "\n${BOLD}${CYAN}sync_patterns.sh — ACMS Custom Pattern Sync${RESET}"
echo -e "  Source: $CUSTOM_DIR"
echo -e "  Target: $PATTERNS_DIR"
[[ "$DRY_RUN" == true ]] && echo -e "  ${YELLOW}[DRY RUN] No files will be written${RESET}"
echo ""

# ── Find all leaf skill directories (contain system.md directly) ───────────────
# A leaf is a directory that contains system.md at its immediate level
# This handles both flat (patterns_custom/SKILL_NAME/system.md)
# and nested (patterns_custom/ACMS_Skills/.../SKILL_NAME/system.md)

while IFS= read -r system_md; do
  skill_dir=$(dirname "$system_md")
  skill_name=$(basename "$skill_dir")

  # Skip archive directories
  [[ "$skill_dir" == *"_archive"* ]] && continue
  [[ "$skill_name" == "_archive" ]] && continue

  target_dir="$PATTERNS_DIR/$skill_name"

  # Check if any of the three files need updating
  needs_update=false
  files_to_copy=()

  for artifact in system.md system.yaml system.toon; do
    src="$skill_dir/$artifact"
    dst="$target_dir/$artifact"
    if [[ -f "$src" ]]; then
      if [[ ! -f "$dst" ]] || ! cmp -s "$src" "$dst"; then
        needs_update=true
        files_to_copy+=("$artifact")
      fi
    fi
  done

  if [[ "$needs_update" == true ]]; then
    if [[ "$DRY_RUN" == false ]]; then
      mkdir -p "$target_dir"
      for artifact in "${files_to_copy[@]}"; do
        src="$skill_dir/$artifact"
        dst="$target_dir/$artifact"
        cp "$src" "$dst"
        chmod +x "$dst"  # Fabric requires executable bit on system.md
        [[ "$VERBOSE" == true ]] && echo -e "  ${GREEN}✓${RESET} $skill_name/$artifact"
      done
    fi

    if [[ -d "$target_dir" ]] && [[ "$DRY_RUN" == false ]]; then
      echo -e "  ${GREEN}✓${RESET} Updated: ${CYAN}$skill_name${RESET} (${files_to_copy[*]})"
      UPDATED=$((UPDATED + 1))
    else
      echo -e "  ${YELLOW}→${RESET} Would update: ${CYAN}$skill_name${RESET} (${files_to_copy[*]})"
      UPDATED=$((UPDATED + 1))
    fi
  else
    SKIPPED=$((SKIPPED + 1))
    [[ "$VERBOSE" == true ]] && echo -e "  ─ Skipped (current): $skill_name"
  fi

  COPIED=$((COPIED + 1))

done < <(find "$CUSTOM_DIR" -name "system.md" | grep -v "_archive" | sort)

echo ""
echo -e "  ${BOLD}Summary:${RESET} $COPIED skills scanned · $UPDATED updated · $SKIPPED already current"
[[ "$DRY_RUN" == true ]] && echo -e "  ${YELLOW}Dry run — no files written${RESET}"
echo ""
