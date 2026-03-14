#!/usr/bin/env bash
# demo_05_psa.sh
# ACMS POC Demo — Section 5: PrincipalSystemArchitect Elicitation
# Mind Over Metadata LLC © 2026 — Peter Heller
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
BLUE='\033[0;34m'; RESET='\033[0m'

banner() {
  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║  $1$(printf '%*s' $((54 - ${#1})) '')║${RESET}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}\n"
}

section() { echo -e "\n${BOLD}${YELLOW}━━━ $1 ━━━${RESET}\n"; }

banner "ACMS POC — Section 5: PrincipalSystemArchitect"

# ── PSA overview ──────────────────────────────────────────────────────────────
section "5.1 — What is the PrincipalSystemArchitect?"
echo -e "The PSA is the ${BOLD}Navigator at the system level${RESET}."
echo -e "It is the only ACMS skill whose tools are other skills.\n"
echo -e "It orchestrates skill creation through a 6-step elicitation sequence:"
echo ""
echo -e "  Step 1  ${CYAN}ACMS_requirements_identity${RESET}    — name, persona, role, domain"
echo -e "  Step 2  ${CYAN}ACMS_requirements_mission${RESET}     — purpose, termination, success"
echo -e "  Step 3  ${CYAN}ACMS_requirements_authorities${RESET} — tools, constraints, permissions"
echo -e "  Step 4  ${CYAN}ACMS_requirements_lifecycle${RESET}   — hooks, pre/post conditions"
echo -e "  Step 5  ${CYAN}ACMS_requirements_cost_model${RESET}  — vendor, budget, thresholds"
echo -e "  Step 6  ${CYAN}ACMS_requirements_data${RESET}        — inputs, outputs, schemas"
echo -e "  Step 7  ${CYAN}SYNTHESIS${RESET}                     — assemble → system.md"
echo ""
echo -e "This is ${BOLD}task-call-task${RESET} at the meta level — the original DEC ACMS pattern."

read -p "Press Enter to view the PSA system.md →"

# ── PSA system.md ─────────────────────────────────────────────────────────────
section "5.2 — PSA system.md"
echo -e "${BOLD}FQSN: MetaArchitecture/PrincipalSystemArchitect/ACMS_principal_system_architect${RESET}\n"
cat MetaArchitecture/PrincipalSystemArchitect/ACMS_principal_system_architect/system.md | head -60
echo -e "\n${CYAN}... ($(wc -l < MetaArchitecture/PrincipalSystemArchitect/ACMS_principal_system_architect/system.md) lines total)${RESET}"

read -p "Press Enter to view a RequirementsGathering specialist →"

# ── Specialist example ────────────────────────────────────────────────────────
section "5.3 — Specialist: ACMS_requirements_identity"
echo -e "${BOLD}FQSN: CodingArchitecture/RequirementsGathering/ACMS_requirements_identity${RESET}\n"
cat CodingArchitecture/RequirementsGathering/ACMS_requirements_identity/system.md | head -40
echo -e "\n${CYAN}... ($(wc -l < CodingArchitecture/RequirementsGathering/ACMS_requirements_identity/system.md) lines total)${RESET}"

read -p "Press Enter to run a live PSA elicitation →"

# ── Live PSA simulation ───────────────────────────────────────────────────────
section "5.4 — Live PSA Elicitation: Dispatch identity specialist"
echo -e "Dispatching ${CYAN}ACMS_requirements_identity${RESET} via Fabric...\n"
echo -e "${YELLOW}Input: New skill — 'Extract cost metrics from cost_audit.log'${RESET}\n"

cat << 'INPUT' | fabric --model gemma3:12b \
  --temperature 0 \
  --pattern ACMS_requirements_identity
Skill intent: Extract cost metrics and anomalies from cost_audit.log
Target domain: TaskArchitecture
Target subdomain: CostAnalysis
INPUT

echo ""
section "5.5 — Six Specialist Skills (all deployed)"
ls -1 CodingArchitecture/RequirementsGathering/ | while read skill; do
  lines=$(wc -l < "CodingArchitecture/RequirementsGathering/$skill/system.md" 2>/dev/null || echo "?")
  echo -e "  ${GREEN}✓${RESET} $skill (${lines} lines)"
done

echo ""
echo -e "${BOLD}Completeness scoring (0-6):${RESET}"
echo -e "  6/6 — proceed to synthesis"
echo -e "  5/6 — flag missing section, offer to proceed"
echo -e "  4/6 — recommend re-running missing specialists"
echo -e "  <4/6 — do not synthesize, restart elicitation"

echo ""
echo -e "${GREEN}${BOLD}✓ Section 5 complete${RESET}"
echo ""
read -p "Press Enter for Section 6: Fabric Pipeline →"
