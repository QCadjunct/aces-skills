#!/usr/bin/env bash
# ============================================================
# ACMS_skill_deploy_generators — deploy_generators.sh
# FQSN: MetaArchitecture/ACMS_skill_deployers/ACMS_skill_deploy_generators
# Mind Over Metadata LLC — Spec-Driven Development (SDD)
# ============================================================

set -euo pipefail

PATTERNS_DEV="$HOME/.config/fabric/patterns_custom"
PATTERNS_QA="$HOME/.config/fabric/patterns_qa"
PATTERNS_PROD="$HOME/.config/fabric/patterns"
AUDIT_LOG="$HOME/.config/fabric/deploy_audit.log"
SCRIPT_VERSION="1.0.0"

SOURCE=""
GENERATE="all"
ARCHIVE="true"
ENV="dev"

RED='\033[0;31m'; YLW='\033[0;33m'; GRN='\033[0;32m'
CYN='\033[0;36m'; BLD='\033[1m';    RST='\033[0m'

usage() {
    echo -e "${BLD}ACMS Skill Deploy Generators v${SCRIPT_VERSION}${RST}"
    echo "Usage: deploy_generators.sh --source <path/to/system.md> [options]"
    echo "  --source    <path>           Path to source system.md (required)"
    echo "  --generate  [yaml|toon|all]  Artifacts to generate   (default: all)"
    echo "  --archive   [true|false]     Archive previous versions(default: true)"
    echo "  --env       [dev|qa|prod]    Target environment       (default: dev)"
    exit 0
}

[[ $# -eq 0 ]] && usage

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source)   SOURCE="$2";   shift 2 ;;
        --generate) GENERATE="$2"; shift 2 ;;
        --archive)  ARCHIVE="$2";  shift 2 ;;
        --env)      ENV="$2";      shift 2 ;;
        --help|-h)  usage ;;
        *) echo -e "${RED}ERROR: Unknown parameter: $1${RST}" >&2; exit 1 ;;
    esac
done

step() { echo -e "${CYN}${BLD}[$1]${RST} $2" >&2; }
ok()   { echo -e "${GRN}  ✓ $1${RST}" >&2; }
warn() { echo -e "${YLW}  ⚠ $1${RST}" >&2; }
fail() { echo -e "${RED}  ✗ $1${RST}" >&2; exit 1; }

step "1" "VALIDATE"
[[ -z "$SOURCE" ]] && fail "--source is required"
[[ ! -f "$SOURCE" ]] && fail "system.md not found: $SOURCE"
[[ ! "$GENERATE" =~ ^(yaml|toon|all)$ ]] && fail "--generate must be yaml, toon, or all"
[[ ! "$ARCHIVE"  =~ ^(true|false)$ ]]    && fail "--archive must be true or false"
[[ ! "$ENV"      =~ ^(dev|qa|prod)$ ]]   && fail "--env must be dev, qa, or prod"
ok "Parameters valid: generate=$GENERATE archive=$ARCHIVE env=$ENV"

step "2" "RESOLVE"
SOURCE_DIR=$(dirname "$SOURCE")
SKILL_FOLDER=$(basename "$SOURCE_DIR")
ok "Skill folder: $SKILL_FOLDER"

case "$ENV" in
    dev)
        TARGET_BASE="$PATTERNS_DEV"
        DO_ARCHIVE="$ARCHIVE"
        REQUIRE_CONFIRM="false"
        ;;
    qa)
        if [[ ! -d "$PATTERNS_QA" ]]; then
            warn "patterns_qa/ not configured — defaulting to DEV"
            TARGET_BASE="$PATTERNS_DEV"
            ENV="dev"
        else
            TARGET_BASE="$PATTERNS_QA"
        fi
        DO_ARCHIVE="false"
        REQUIRE_CONFIRM="false"
        ;;
    prod)
        TARGET_BASE="$PATTERNS_PROD"
        DO_ARCHIVE="false"
        REQUIRE_CONFIRM="true"
        ;;
esac

TARGET_DIR="$TARGET_BASE/$SKILL_FOLDER"
mkdir -p "$TARGET_DIR"
ok "Target: $TARGET_DIR"

step "3" "ARCHIVE"
if [[ "$DO_ARCHIVE" == "true" ]]; then
    UUID=$(python3 -c "
from datetime import datetime, timezone
import random, string
ts = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S')
suffix = ''.join(random.choices('0123456789abcdef', k=8))
print(f'{ts}_{suffix}')
")
    ARCHIVED=0
    for artifact in system.md system.yaml system.toon; do
        if [[ -f "$TARGET_DIR/$artifact" ]]; then
            mv "$TARGET_DIR/$artifact" "$TARGET_DIR/${artifact}_${UUID}"
            ok "Archived: ${artifact} → ${artifact}_${UUID}"
            ARCHIVED=$((ARCHIVED + 1))
        fi
    done
    [[ $ARCHIVED -eq 0 ]] && ok "No previous artifacts to archive"
else
    ok "Archive skipped (env=$ENV)"
fi

step "4" "GENERATE"
GEN_YAML="false"; GEN_TOON="false"
[[ "$GENERATE" == "yaml" || "$GENERATE" == "all" ]] && GEN_YAML="true"
[[ "$GENERATE" == "toon" || "$GENERATE" == "all" ]] && GEN_TOON="true"

[[ "$GEN_YAML" == "true" ]] && {
    cat "$SOURCE" | fabric --pattern from_system.md_to_system.yaml > "$TARGET_DIR/system.yaml" \
        || fail "fabric pattern from_system.md_to_system.yaml failed"
    ok "system.yaml generated"
}
[[ "$GEN_TOON" == "true" ]] && {
    cat "$SOURCE" | fabric --pattern from_system.md_to_system.toon > "$TARGET_DIR/system.toon" \
        || fail "fabric pattern from_system.md_to_system.toon failed"
    ok "system.toon generated"
}

step "5" "WRITE"
cp "$SOURCE" "$TARGET_DIR/system.md"
ok "system.md copied to $TARGET_DIR"

step "6" "CONFIRM"
if [[ "$REQUIRE_CONFIRM" == "true" ]]; then
    echo -e "${YLW}${BLD}"
    echo "  ╔══════════════════════════════════════╗"
    echo "  ║  PRODUCTION DEPLOYMENT CONFIRMATION  ║"
    echo "  ║  Skill:  $SKILL_FOLDER"
    echo "  ║  Deploy to PROD? [y/n]               ║"
    echo "  ╚══════════════════════════════════════╝"
    echo -e "${RST}"
    read -r CONFIRM
    [[ ! "$CONFIRM" =~ ^[Yy]$ ]] && { warn "PROD deployment cancelled."; exit 0; }
    ok "PROD confirmed"
else
    ok "Confirmation not required for env=$ENV"
fi

step "7" "DEPLOY"
ls -lh "$TARGET_DIR/"
ok "Deployed: $SKILL_FOLDER → $ENV"

step "8" "LOG"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "${TIMESTAMP} | ${SKILL_FOLDER} | ${ENV} | ${GENERATE} | ${DO_ARCHIVE} | SUCCESS | $(whoami)" >> "$AUDIT_LOG"
ok "Audit log updated"

echo -e "\n${GRN}${BLD}════════════════════════════════════════${RST}" >&2
echo -e "${GRN}${BLD}  DONE — $SKILL_FOLDER → $ENV ${RST}" >&2
echo -e "${GRN}${BLD}════════════════════════════════════════${RST}" >&2
