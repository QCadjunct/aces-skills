#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# fabric_analyze.sh — Parametrized Fabric Analysis Pipeline
# FQSN: CodingArchitecture/FabricStitch/fabric_analyze
# VERSION: 2.0.0
# STATUS: Production
#
# USAGE
#   Single source:
#     bash fabric_analyze.sh --url="https://example.com/article"
#     bash fabric_analyze.sh --url="https://youtu.be/XXXXX"        # auto -y
#     bash fabric_analyze.sh --text-file="/path/to/file.pdf"        # any pandoc format
#
#   Manifest (multi-agent DCG):
#     bash fabric_analyze.sh --manifest=fabric_analyze_task.yaml
#     bash fabric_analyze.sh --manifest=fabric_analyze_task.json
#     bash fabric_analyze.sh --manifest=fabric_analyze_task.toon
#
# OPTIONS (single source)
#   --url=<URL>             Any HTTP/HTTPS — articles, web pages
#                           youtube.com/youtu.be auto-detected → Fabric -y flag
#   --text-file=<PATH>      Any pandoc-readable file (pdf docx pptx html
#                           json rst org epub odt csv md txt and more)
#   --title=<STRING>        Document title
#   --vendor=<STRING>       Fabric vendor (default: Ollama)
#   --model=<STRING>        Model (default: qwen3.5:397b-cloud)
#   --outdir=<PATH>         Output directory (default: ~/fabric-analysis/[slug])
#   --word-limit=<N>        Narrative word target 500-10000 (default: 4000)
#   --patterns=<LIST>       Comma-separated pattern list (overrides role)
#   --role=<ROLE>           full|primary|contrast|supporting|background
#   --skip-synthesis        Skip Stage 7 (narrative synthesis)
#   --skip-qa               Skip Stage 8 (discussion Q&A enrichment)
#   --skip-docx             Markdown only
#   --reference-doc=<PATH>  pandoc Word template
#   --obsidian=<PATH>       Copy .md to Obsidian vault path
#   --dry-run               Show resolved config, exit
#   --help                  Show this help
#
# OPTIONS (manifest / multi-agent)
#   --manifest=<PATH>       YAML, JSON, or TOON task definition file
#   --consolidated          Override: force consolidated output
#
# ROLE → PATTERN GROUPS
#   full        extract_article_wisdom extract_wisdom extract_ideas
#               extract_questions analyze_claims summarize
#   primary     extract_article_wisdom extract_wisdom
#               extract_questions analyze_claims summarize
#   contrast    analyze_claims extract_questions summarize
#   supporting  extract_wisdom extract_ideas summarize
#   background  summarize extract_article_wisdom
#
# AUTHOR: Peter Heller / Mind Over Metadata LLC
# REPO:   QCadjunct/aces-skills
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Pattern name — already installed via sync_patterns.sh
CUSTOM_PATTERN_NAME="synthesize_eloquent_narrative_from_wisdom"

# ── DEFAULTS ───────────────────────────────────────────────────────────────────
TARGET_URL=""; TEXT_FILE=""; MANIFEST_FILE=""
DOC_TITLE=""; VENDOR="Ollama"; MODEL="qwen3.5:397b-cloud"
OUTDIR=""; WORD_LIMIT=4000; CUSTOM_PATTERNS_CSV=""; ROLE="full"
SKIP_SYNTHESIS=false; SKIP_QA=false; SKIP_DOCX=false
REFERENCE_DOC=""; OBSIDIAN_PATH=""; DRY_RUN=false; CONSOLIDATED=false

# ── ROLE → PATTERNS ────────────────────────────────────────────────────────────
role_patterns() {
    case "$1" in
        full)        echo "extract_article_wisdom extract_wisdom extract_ideas extract_questions analyze_claims summarize" ;;
        primary)     echo "extract_article_wisdom extract_wisdom extract_questions analyze_claims summarize" ;;
        contrast)    echo "analyze_claims extract_questions summarize" ;;
        supporting)  echo "extract_wisdom extract_ideas summarize" ;;
        background)  echo "summarize extract_article_wisdom" ;;
        *) echo "extract_article_wisdom extract_wisdom extract_ideas extract_questions analyze_claims summarize" ;;
    esac
}

# ── ARGS ───────────────────────────────────────────────────────────────────────
for arg in "$@"; do
    case $arg in
        --url=*)              TARGET_URL="${arg#*=}" ;;
        --text-file=*)        TEXT_FILE="${arg#*=}" ;;
        --manifest=*)         MANIFEST_FILE="${arg#*=}" ;;
        --title=*)            DOC_TITLE="${arg#*=}" ;;
        --vendor=*)           VENDOR="${arg#*=}" ;;
        --model=*)            MODEL="${arg#*=}" ;;
        --outdir=*)           OUTDIR="${arg#*=}" ;;
        --word-limit=*)       WORD_LIMIT="${arg#*=}" ;;
        --patterns=*)         CUSTOM_PATTERNS_CSV="${arg#*=}" ;;
        --role=*)             ROLE="${arg#*=}" ;;
        --skip-synthesis)     SKIP_SYNTHESIS=true ;;
        --skip-qa)            SKIP_QA=true ;;
        --skip-docx)          SKIP_DOCX=true ;;
        --reference-doc=*)    REFERENCE_DOC="${arg#*=}" ;;
        --obsidian=*)         OBSIDIAN_PATH="${arg#*=}" ;;
        --consolidated)       CONSOLIDATED=true ;;
        --dry-run)            DRY_RUN=true ;;
        --help) grep "^#" "${BASH_SOURCE[0]}" | head -60 | sed 's/^# \{0,2\}//'; exit 0 ;;
        *) echo "Unknown: $arg  (--help for usage)" >&2; exit 1 ;;
    esac
done

# ── HELPERS ────────────────────────────────────────────────────────────────────
ms()       { python3 -c "import time; print(int(time.perf_counter()*1000))"; }
make_slug(){ echo "$1" | sed 's|https\?://||;s|[^a-zA-Z0-9]|-|g;s|-\+|-|g;s|^-||;s|-$||' | cut -c1-60; }

# YouTube auto-detect
is_youtube() { [[ "$1" =~ (youtube\.com/watch|youtu\.be/|youtube\.com/shorts/) ]]; }

# Universal file → plain text via pandoc
file_to_text() {
    local f="$1"
    if ! command -v pandoc &>/dev/null; then
        echo "ERROR: pandoc required for file input" >&2; return 1
    fi
    # pandoc handles: md txt pdf docx pptx html json rst org epub odt csv and more
    pandoc "$f" -t plain --wrap=none 2>/dev/null \
        || { echo "ERROR: pandoc could not read $f" >&2; return 1; }
}

# Parse manifest (YAML/JSON/TOON) → sets global arrays/vars via temp file
# Returns JSON array of agents on stdout
parse_manifest() {
    local mf="$1"
    local ext="${mf##*.}"
    ext="${ext,,}"

    python3 - "$mf" "$ext" << 'PYEOF'
import sys, json, pathlib

mf   = sys.argv[1]
ext  = sys.argv[2]
src  = pathlib.Path(mf).read_text()

if ext in ("yaml","yml"):
    import yaml
    data = yaml.safe_load(src)
elif ext == "json":
    data = json.loads(src)
elif ext == "toon":
    # TOON parser — key=value, agent[N].key=value
    data = {"task": {}, "agents": {}}
    for line in src.splitlines():
        line = line.strip()
        if not line or line.startswith("#"): continue
        k, _, v = line.partition("=")
        if k.startswith("agent["):
            idx_end = k.index("]")
            idx = int(k[6:idx_end])
            field = k[idx_end+2:]
            if idx not in data["agents"]:
                data["agents"][idx] = {}
            if field == "patterns":
                data["agents"][idx][field] = [p.strip() for p in v.split(",") if p.strip()]
            elif v.lower() in ("true","false"):
                data["agents"][idx][field] = v.lower() == "true"
            elif v.isdigit():
                data["agents"][idx][field] = int(v)
            else:
                data["agents"][idx][field] = v
        elif k.startswith("task."):
            field = k[5:]
            if v.lower() in ("true","false"):
                data["task"][field] = v.lower() == "true"
            elif v.isdigit():
                data["task"][field] = int(v)
            else:
                data["task"][field] = v
    # Convert agents dict → sorted list
    agents_list = [data["agents"][i] for i in sorted(data["agents"].keys())]
    data["agents"] = agents_list
else:
    print(f"ERROR: unsupported manifest format: {ext}", file=sys.stderr)
    sys.exit(1)

print(json.dumps(data))
PYEOF
}

# Run one fabric pattern against a source — handles URL/YouTube/file
run_pattern() {
    local pattern="$1"
    local source="$2"
    local vendor="$3"
    local model="$4"
    local log="$5"
    local result=""

    local cmd_base="fabric -V ${vendor} -m ${model} -p ${pattern}"

    if [[ "$source" =~ ^https?:// ]]; then
        if is_youtube "$source"; then
            result=$(eval "$cmd_base -y '$source'" 2>/dev/null) || result=""
            if [[ -z "$result" ]]; then
                result=$(eval "$cmd_base -y '$source'" 2>/dev/null) || result=""
            fi
        else
            result=$(eval "$cmd_base -u '$source'" 2>/dev/null) || result=""
            if [[ -z "$result" ]]; then
                result=$(eval "$cmd_base -u '$source'" 2>/dev/null) || result=""
            fi
        fi
    else
        # Local file — convert to text via pandoc then pipe
        local text
        text=$(file_to_text "$source") || text=""
        if [[ -n "$text" ]]; then
            result=$(echo "$text" | eval "$cmd_base" 2>/dev/null) || result=""
            if [[ -z "$result" ]]; then
                result=$(echo "$text" | eval "$cmd_base" 2>/dev/null) || result=""
            fi
        fi
    fi

    echo "$result"
}

# ── SINGLE-AGENT PIPELINE ──────────────────────────────────────────────────────
run_single_agent() {
    local source="$1"
    local title="$2"
    local vendor="$3"
    local model="$4"
    local word_limit="$5"
    local role="$6"
    local patterns_override="$7"  # space-separated, empty=use role
    local outdir="$8"
    local obsidian="$9"
    local log="${10}"

    # Resolve pattern list
    local patterns
    if [[ -n "$patterns_override" ]]; then
        read -ra patterns <<< "$patterns_override"
    else
        read -ra patterns <<< "$(role_patterns "$role")"
    fi

    local slug
    slug=$(make_slug "$source")
    local timestamp
    timestamp=$(date +"%Y-%m-%d-%H%M")
    local md_out="${outdir}/${slug}-${timestamp}.md"
    local docx_out="${outdir}/${slug}-${timestamp}.docx"

    mkdir -p "$outdir"

    echo "  Agent: $title" | tee -a "$log"
    echo "  Source: $source" | tee -a "$log"
    is_youtube "$source" && echo "  Input: YouTube → -y flag (yt-dlp transcript)" | tee -a "$log" \
        || { [[ "$source" =~ ^https?:// ]] && echo "  Input: URL → -u flag" | tee -a "$log" \
            || echo "  Input: file → pandoc → plain text → pipe" | tee -a "$log"; }
    echo "  Vendor/Model: $vendor / $model" | tee -a "$log"
    echo "  Patterns: ${patterns[*]}" | tee -a "$log"
    echo "─────────────────────────────────────────────────────────────" | tee -a "$log"

    # Run each pattern
    declare -A STAGE_OUT
    declare -A STAGE_TIME
    declare -A STAGE_STAT

    for p in "${patterns[@]}"; do
        printf "  [%-30s] " "$p" | tee -a "$log"
        T_S=$(ms)
        result=$(run_pattern "$p" "$source" "$vendor" "$model" "$log")
        T_E=$(ms)
        EL=$((T_E - T_S))
        STAGE_TIME["$p"]="${EL}ms"

        if [[ -z "$result" ]]; then
            printf "FAIL  %sms\n" "$EL" | tee -a "$log"
            STAGE_STAT["$p"]="FAIL"
            STAGE_OUT["$p"]=$(printf '> **Pattern `%s` returned no output.**\n> Re-run: `fabric -V %s -m %s -p %s -u "%s"`\n' \
                "$p" "$vendor" "$model" "$p" "$source")
        else
            printf "OK    %sms\n" "$EL" | tee -a "$log"
            STAGE_STAT["$p"]="OK"
            STAGE_OUT["$p"]="$result"
        fi
    done

    # Stage 7: synthesis
    local SYNTHESIS="*Synthesis skipped (--skip-synthesis).*"
    local SYN_EL=0
    if [[ "$SKIP_SYNTHESIS" == "false" ]]; then
        printf "  [%-30s] " "$CUSTOM_PATTERN_NAME" | tee -a "$log"
        SYN_IN="word_limit=${word_limit}\n\nSource: ${source}\n\n"
        for stage in summarize extract_article_wisdom extract_wisdom extract_ideas; do
            [[ -n "${STAGE_OUT[$stage]+x}" ]] && SYN_IN+="== ${stage^^} ==\n${STAGE_OUT[$stage]}\n\n"
        done
        T_S=$(ms)
        SYNTHESIS=$(printf '%b' "$SYN_IN" \
            | fabric -V "$vendor" -m "$model" -p "$CUSTOM_PATTERN_NAME" 2>/dev/null) || SYNTHESIS=""
        SYN_EL=$(( $(ms) - T_S ))
        [[ -z "$SYNTHESIS" ]] \
            && { printf "FAIL  %sms\n" "$SYN_EL" | tee -a "$log"
                 SYNTHESIS="> **Synthesis failed (${SYN_EL}ms).** Run: fabric -V $vendor -m $model -p synthesize_eloquent_narrative_from_wisdom"; } \
            || printf "OK    %sms\n" "$SYN_EL" | tee -a "$log"
    fi

    # Stage 8: Q&A enrichment
    local INFERRED_QA="*Q&A enrichment skipped.*"
    local QA_EL=0
    if [[ "$SKIP_QA" == "false" && "${STAGE_STAT[extract_questions]:-FAIL}" == "OK" ]]; then
        printf "  [%-30s] " "inferred-qa" | tee -a "$log"
        QA_PROMPT="You are preparing for a discussion with the author of: ${source}

For each question below, produce:
1. Restated question (precise)
2. Why it matters (2-3 sentences, grounded in the source's argument)
3. Inferred author position (from the text)
4. Follow-up probe (one sharpening question)

Format each as:
---
**Q[N]: [Restated question]**
*Why it matters:* [relevance]
*Inferred author position:* [what the text implies]
*Follow-up probe:* [sharpening question]
---

Summary context:
${STAGE_OUT[summarize]:-N/A}

Raw questions:
${STAGE_OUT[extract_questions]}"

        T_S=$(ms)
        INFERRED_QA=$(echo "$QA_PROMPT" \
            | fabric -V "$vendor" -m "$model" --text 2>/dev/null) || INFERRED_QA=""
        QA_EL=$(( $(ms) - T_S ))
        if [[ -z "$INFERRED_QA" ]]; then
            printf "FAIL  %sms\n" "$QA_EL" | tee -a "$log"
            INFERRED_QA="${STAGE_OUT[extract_questions]}"
            INFERRED_QA+=$'\n\n> *Enrichment failed — raw questions shown.*'
        else
            printf "OK    %sms\n" "$QA_EL" | tee -a "$log"
        fi
    fi

    # Build timing summary
    local TIMING=""
    for p in "${patterns[@]}"; do
        TIMING+=$(printf "  %-35s %s  [%s]\n" "$p" "${STAGE_TIME[$p]:-n/a}" "${STAGE_STAT[$p]:-SKIP}")
    done
    TIMING+=$(printf "  %-35s %sms\n" "synthesize" "$SYN_EL")
    TIMING+=$(printf "  %-35s %sms\n" "inferred-qa" "$QA_EL")

    # Build dynamic sections
    local SECTIONS=""
    for p in extract_article_wisdom extract_wisdom extract_ideas analyze_claims; do
        [[ -n "${STAGE_OUT[$p]+x}" ]] || continue
        local SECTION_TITLE
        case "$p" in
            extract_article_wisdom) SECTION_TITLE="Article Wisdom" ;;
            extract_wisdom)         SECTION_TITLE="Deep Insights" ;;
            extract_ideas)          SECTION_TITLE="Idea Inventory" ;;
            analyze_claims)         SECTION_TITLE="Claims Analysis" ;;
            *)                      SECTION_TITLE="$p" ;;
        esac
        SECTIONS+="---

# ${SECTION_TITLE}

*Pattern: \`${p}\`*

${STAGE_OUT[$p]}

"
    done

    # Write Markdown
    cat > "$md_out" << MDEOF
---
title: "${title}"
subtitle: "Fabric Analysis — ACES FabricStitch v2.0.0"
author: "Peter Heller / Mind Over Metadata LLC"
date: "$(date +"%B %d, %Y")"
source: "${source}"
vendor: "${vendor}"
model: "${model}"
role: "${role}"
word_limit: "${word_limit}"
patterns: "${patterns[*]}"
---

\newpage

# ${title}

| | |
|---|---|
| **Source** | ${source} |
| **Analyzed** | $(date +"%B %d, %Y at %H:%M") |
| **Model** | ${vendor} / ${model} |
| **Role** | ${role} |
| **Patterns** | ${patterns[*]} |

\newpage

---

# Part 1 — Narrative Synthesis

*synthesize_eloquent_narrative_from_wisdom v2.0.0-ACES · word_limit=${word_limit}*

${SYNTHESIS}

\newpage

---

# Part 2 — Executive Summary

${STAGE_OUT[summarize]:-*summarize not in active patterns.*}

\newpage

${SECTIONS}

---

# Part 7 — Discussion Questions

${INFERRED_QA}

\newpage

---

# Appendix — Pipeline Health

\`\`\`
$(cat "$log")

Timing:
${TIMING}
\`\`\`

*fabric_analyze.sh v2.0.0 · CodingArchitecture/FabricStitch/fabric_analyze*
MDEOF

    echo "  ✓ Markdown: $md_out" | tee -a "$log"

    # pandoc conversion
    if [[ "$SKIP_DOCX" == "false" ]]; then
        local PANDOC_OPTS=(--from markdown --to docx --highlight-style tango --toc --toc-depth=2)
        [[ -n "$REFERENCE_DOC" && -f "$REFERENCE_DOC" ]] && PANDOC_OPTS+=(--reference-doc "$REFERENCE_DOC")
        [[ -f "${SCRIPT_DIR}/reference.docx" ]] && PANDOC_OPTS+=(--reference-doc "${SCRIPT_DIR}/reference.docx")
        pandoc "$md_out" "${PANDOC_OPTS[@]}" -o "$docx_out" 2>&1 | tee -a "$log"
        echo "  ✓ Word doc: $docx_out" | tee -a "$log"
    fi

    [[ -n "$obsidian" ]] && {
        mkdir -p "$obsidian"
        cp "$md_out" "${obsidian}/$(basename "$md_out")"
        echo "  ✓ Obsidian: ${obsidian}/$(basename "$md_out")" | tee -a "$log"
    }

    # Return paths for consolidated merge
    echo "$md_out"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

command -v fabric &>/dev/null || { echo "ERROR: fabric not in PATH" >&2; exit 1; }

TIMESTAMP=$(date +"%Y-%m-%d-%H%M")

# ── MANIFEST MODE ──────────────────────────────────────────────────────────────
if [[ -n "$MANIFEST_FILE" ]]; then
    echo "═══ fabric_analyze.sh v2.0.0 — MANIFEST MODE ═══" | tee /tmp/fa_main_${TIMESTAMP}.log
    echo "Manifest: $MANIFEST_FILE" | tee -a /tmp/fa_main_${TIMESTAMP}.log

    MANIFEST_DATA=$(parse_manifest "$MANIFEST_FILE")

    # Extract all task fields + agent count in one call — no quoting conflicts
    _TASK_ENV=$(mktemp)
    N_AGENTS=$(echo "$MANIFEST_DATA" | python3 "${SCRIPT_DIR}/_manifest_env.py" "$_TASK_ENV")
    # shellcheck disable=SC1090
    source "$_TASK_ENV"
    rm -f "$_TASK_ENV"

    # Apply command-line flag overrides over manifest values
    [[ "$CONSOLIDATED" == "true" ]] && TASK_CONS=true
    [[ "$TASK_SKIP_SYN" == "true" ]]  && SKIP_SYNTHESIS=true
    [[ "$TASK_SKIP_QA"  == "true" ]]  && SKIP_QA=true
    [[ "$TASK_SKIP_DOC" == "true" ]]  && SKIP_DOCX=true
    [[ "$TASK_CONS"     == "true" ]]  && CONSOLIDATED=true
    TASK_OUTDIR="${TASK_OUTDIR/#~/$HOME}"

    echo "Agents: $N_AGENTS  Title: $TASK_TITLE" | tee -a "$MAIN_LOG"
    echo "─────────────────────────────────────────────────────────────" | tee -a "$MAIN_LOG"

    AGENT_MD_FILES=()

    for idx in $(seq 0 $((N_AGENTS - 1))); do
        AGENT=$(echo "$MANIFEST_DATA" | python3 "${SCRIPT_DIR}/_manifest_agent.py" "$idx")
        # Extract all agent fields — single Python call, no quoting issues
        _AGENT_ENV=$(mktemp)
        echo "$AGENT" | python3 "${SCRIPT_DIR}/_agent_env.py" "$_AGENT_ENV"
        # shellcheck disable=SC1090
        source "$_AGENT_ENV"
        rm -f "$_AGENT_ENV"

        [[ "$A_ENABLED" == "false" ]] && {
            echo "  Agent $idx: SKIP (enabled=false)" | tee -a "$MAIN_LOG"
            continue
        }

        # Resolve per-agent overrides
        EFF_VENDOR="${A_VENDOR:-$TASK_VENDOR}"
        EFF_MODEL="${A_MODEL:-$TASK_MODEL}"
        EFF_WLIMIT="${A_WLIMIT:-$TASK_WLIMIT}"
        [[ "$EFF_WLIMIT" == "0" ]] && EFF_WLIMIT="$TASK_WLIMIT"
        EFF_OBSID="${A_OBSID:-$TASK_OBSID}"
        EFF_OBSID="${EFF_OBSID/#\~/$HOME}"

        echo "" | tee -a "$MAIN_LOG"
        echo "AGENT $((idx+1))/$N_AGENTS — ${A_TITLE}" | tee -a "$MAIN_LOG"

        AGENT_LOG="${TASK_OUTDIR}/agent-${idx}-health-${TIMESTAMP}.log"

        MD=$(run_single_agent \
            "$A_SOURCE" "$A_TITLE" "$EFF_VENDOR" "$EFF_MODEL" \
            "$EFF_WLIMIT" "$A_ROLE" "$A_PATS" \
            "$TASK_OUTDIR" "$EFF_OBSID" "$AGENT_LOG")

        cat "$AGENT_LOG" >> "$MAIN_LOG"
        [[ -n "$MD" ]] && AGENT_MD_FILES+=("$MD")
    done

    # Consolidated document
    if [[ "$CONSOLIDATED" == "true" && ${#AGENT_MD_FILES[@]} -gt 1 ]]; then
        echo "" | tee -a "$MAIN_LOG"
        echo "CONSOLIDATED OUTPUT" | tee -a "$MAIN_LOG"
        echo "─────────────────────────────────────────────────────────────" | tee -a "$MAIN_LOG"

        CONS_MD="${TASK_OUTDIR}/consolidated-${TIMESTAMP}.md"
        CONS_DOCX="${TASK_OUTDIR}/consolidated-${TIMESTAMP}.docx"

        python3 "${SCRIPT_DIR}/consolidate.py" \
            "$CONS_MD" \
            "${CONSOLIDATED_TITLE:-$TASK_TITLE}" \
            "$MAIN_LOG" \
            "${AGENT_MD_FILES[@]}"

        echo "  ✓ Consolidated Markdown: $CONS_MD" | tee -a "$MAIN_LOG"

        if [[ "$SKIP_DOCX" == "false" ]] && command -v pandoc &>/dev/null; then
            PANDOC_OPTS=(--from markdown --to docx --highlight-style tango --toc --toc-depth=3)
            [[ -f "${SCRIPT_DIR}/reference.docx" ]] && PANDOC_OPTS+=(--reference-doc "${SCRIPT_DIR}/reference.docx")
            pandoc "$CONS_MD" "${PANDOC_OPTS[@]}" -o "$CONS_DOCX" 2>&1 | tee -a "$MAIN_LOG"
            echo "  ✓ Consolidated Word doc: $CONS_DOCX" | tee -a "$MAIN_LOG"
        fi

        [[ -n "$TASK_OBSID" ]] && {
            TASK_OBSID="${TASK_OBSID/#\~/$HOME}"
            mkdir -p "$TASK_OBSID"
            cp "$CONS_MD" "${TASK_OBSID}/$(basename "$CONS_MD")"
            echo "  ✓ Obsidian: ${TASK_OBSID}/$(basename "$CONS_MD")" | tee -a "$MAIN_LOG"
        }
    fi

    echo "" | tee -a "$MAIN_LOG"
    echo "═══ COMPLETE $(date) ═══" | tee -a "$MAIN_LOG"
    echo "Health log: $MAIN_LOG"
    command -v explorer.exe &>/dev/null && explorer.exe "$(wslpath -w "$TASK_OUTDIR")" 2>/dev/null || true
    exit 0
fi

# ── SINGLE-SOURCE MODE ─────────────────────────────────────────────────────────
[[ -z "$TARGET_URL" && -z "$TEXT_FILE" ]] && {
    echo "ERROR: --url, --text-file, or --manifest required" >&2; exit 1; }

SOURCE="${TARGET_URL:-$TEXT_FILE}"
if [[ -z "$DOC_TITLE" ]]; then
    _slug=$(make_slug "$SOURCE")
    DOC_TITLE="${_slug//-/ }"
    DOC_TITLE="${DOC_TITLE:0:80}"
fi
[[ -z "$OUTDIR" ]] && OUTDIR="${HOME}/fabric-analysis/$(make_slug "$SOURCE")"
OUTDIR="${OUTDIR/#\~/$HOME}"

MAIN_LOG="${OUTDIR}/pipeline-health-${TIMESTAMP}.log"
mkdir -p "$OUTDIR"

echo "═══ fabric_analyze.sh v2.0.0 — SINGLE MODE ═══" | tee "$MAIN_LOG"
echo "Source: $SOURCE" | tee -a "$MAIN_LOG"
echo "Model:  $VENDOR / $MODEL" | tee -a "$MAIN_LOG"

PATTERNS_OVERRIDE=""
[[ -n "$CUSTOM_PATTERNS_CSV" ]] && PATTERNS_OVERRIDE="${CUSTOM_PATTERNS_CSV//,/ }"

[[ "$DRY_RUN" == "true" ]] && {
    echo "DRY RUN — config resolved, no patterns will run"
    echo "Role: $ROLE  Patterns: ${PATTERNS_OVERRIDE:-$(role_patterns "$ROLE")}"
    exit 0
}

run_single_agent \
    "$SOURCE" "$DOC_TITLE" "$VENDOR" "$MODEL" \
    "$WORD_LIMIT" "$ROLE" "$PATTERNS_OVERRIDE" \
    "$OUTDIR" "$OBSIDIAN_PATH" "$MAIN_LOG"

echo "═══ COMPLETE $(date) ═══" | tee -a "$MAIN_LOG"
command -v explorer.exe &>/dev/null && explorer.exe "$(wslpath -w "$OUTDIR")" 2>/dev/null || true
