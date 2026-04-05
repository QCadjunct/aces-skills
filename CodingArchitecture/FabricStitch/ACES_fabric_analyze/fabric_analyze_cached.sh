#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# fabric_analyze_cached.sh — Cached RAG Analysis Pipeline
# FQSN: CodingArchitecture/FabricStitch/ACES_fabric_analyze
# VERSION: 1.0.0
#
# CONCEPT
#   Extract once. Generate many.
#   Raw pattern outputs are cached by SHA256(url+model) in ~/.fabric-cache/
#   Any number of themed documents can be generated from the cache at near-zero
#   cost — no re-fetching, no re-running patterns, just synthesis.
#
# USAGE
#   # Extract and cache (first run):
#   bash fabric_analyze_cached.sh --url="https://example.com/article"
#
#   # Generate a theme from cache (instant):
#   bash fabric_analyze_cached.sh \
#     --url="https://example.com/article" \
#     --theme=sme-discussion
#
#   # Generate all 5 themes from cache:
#   bash fabric_analyze_cached.sh \
#     --url="https://example.com/article" \
#     --all-themes
#
#   # Force re-extraction (bypass cache):
#   bash fabric_analyze_cached.sh \
#     --url="https://example.com/article" \
#     --refresh
#
#   # Use a custom theme YAML:
#   bash fabric_analyze_cached.sh \
#     --url="https://example.com/article" \
#     --theme-file=/path/to/my-theme.yaml
#
#   # List cached sources:
#   bash fabric_analyze_cached.sh --list-cache
#
#   # Show cache entry for a URL:
#   bash fabric_analyze_cached.sh \
#     --url="https://example.com/article" \
#     --cache-info
#
# OPTIONS
#   --url=<URL>           Source URL (any HTTP/HTTPS or YouTube)
#   --text-file=<PATH>    Local file (any pandoc-readable format)
#   --theme=<NAME>        Built-in theme name:
#                           executive-brief · sme-discussion · technical-deep-dive
#                           vision-analysis · course-material
#   --theme-file=<PATH>   Custom theme YAML file
#   --all-themes          Generate all 5 built-in themes from cache
#   --refresh             Force re-extraction, bypass cache
#   --vendor=<STRING>     Fabric vendor (default: Ollama)
#   --model=<STRING>      Model string (default: qwen3.5:397b-cloud)
#   --outdir=<PATH>       Output directory (default: ~/fabric-analysis/[slug])
#   --obsidian=<PATH>     Copy .md outputs to Obsidian vault path
#   --cache-dir=<PATH>    Override cache location (default: ~/.fabric-cache)
#   --list-cache          List all cached sources and exit
#   --cache-info          Show cache details for --url and exit
#   --skip-docx           Markdown only — skip pandoc
#   --dry-run             Show resolved config and exit
#   --help                Show this help
#
# CACHE STRUCTURE
#   ~/.fabric-cache/
#     [sha256-of-url+model]/
#       manifest.json           ← source, model, timestamp, patterns cached
#       extract_article_wisdom.md
#       extract_wisdom.md
#       extract_ideas.md
#       extract_questions.md
#       analyze_claims.md
#       summarize.md
#
# THEME YAML FORMAT
#   theme: my-theme-name
#   title_suffix: "My Theme Title"
#   word_limit: 3000
#   tone: "descriptive tone phrase"
#   synthesis_directive: |
#     Multi-line synthesis prompt passed to
#     synthesize_eloquent_narrative_from_wisdom
#   patterns_required:
#     - extract_article_wisdom
#     - analyze_claims
#
# AUTHOR: Peter Heller / Mind Over Metadata LLC
# REPO:   QCadjunct/aces-skills
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEMES_DIR="${SCRIPT_DIR}/themes"
SYNTH_PATTERN="synthesize_eloquent_narrative_from_wisdom"

# ── DEFAULTS ───────────────────────────────────────────────────────────────────
TARGET_URL=""
TEXT_FILE=""
THEME_NAME=""
THEME_FILE=""
ALL_THEMES=false
REFRESH=false
VENDOR="Ollama"
MODEL="qwen3.5:397b-cloud"
OUTDIR=""
OBSIDIAN_PATH=""
CACHE_DIR="${HOME}/.fabric-cache"
SKIP_DOCX=false
DRY_RUN=false
LIST_CACHE=false
CACHE_INFO=false

# ── ARGS ───────────────────────────────────────────────────────────────────────
for arg in "$@"; do
    case $arg in
        --url=*)         TARGET_URL="${arg#*=}" ;;
        --text-file=*)   TEXT_FILE="${arg#*=}" ;;
        --theme=*)       THEME_NAME="${arg#*=}" ;;
        --theme-file=*)  THEME_FILE="${arg#*=}" ;;
        --all-themes)    ALL_THEMES=true ;;
        --refresh)       REFRESH=true ;;
        --vendor=*)      VENDOR="${arg#*=}" ;;
        --model=*)       MODEL="${arg#*=}" ;;
        --outdir=*)      OUTDIR="${arg#*=}" ;;
        --obsidian=*)    OBSIDIAN_PATH="${arg#*=}" ;;
        --cache-dir=*)   CACHE_DIR="${arg#*=}" ;;
        --skip-docx)     SKIP_DOCX=true ;;
        --dry-run)       DRY_RUN=true ;;
        --list-cache)    LIST_CACHE=true ;;
        --cache-info)    CACHE_INFO=true ;;
        --help)
            grep "^#" "${BASH_SOURCE[0]}" | head -80 | sed 's/^# \{0,2\}//'
            exit 0 ;;
        *) echo "Unknown: $arg  (--help for usage)" >&2; exit 1 ;;
    esac
done

# ── HELPERS ────────────────────────────────────────────────────────────────────
ms() { python3 -c "import time; print(int(time.perf_counter()*1000))"; }

is_youtube() { [[ "$1" =~ (youtube\.com/watch|youtu\.be/|youtube\.com/shorts/) ]]; }

make_slug() {
    echo "$1" \
      | sed 's|https\?://||' \
      | sed 's|[^a-zA-Z0-9]|-|g' \
      | sed 's|-\+|-|g' \
      | sed 's|^-||; s|-$||' \
      | cut -c1-60
}

# Cache key = SHA256(url + "|" + model)
cache_key() {
    echo -n "${1}|${2}" | sha256sum | awk '{print $1}' | cut -c1-16
}

# List cache
if [[ "$LIST_CACHE" == "true" ]]; then
    echo "═══ ~/.fabric-cache — Cached Sources ═══"
    if [[ ! -d "$CACHE_DIR" ]] || [[ -z "$(ls -A "$CACHE_DIR" 2>/dev/null)" ]]; then
        echo "  (empty)"
    else
        for d in "${CACHE_DIR}"/*/; do
            mf="${d}manifest.json"
            [[ -f "$mf" ]] || continue
            src=$(python3 -c "import json; d=json.load(open('${mf}')); print(d.get('source','?'))")
            mdl=$(python3 -c "import json; d=json.load(open('${mf}')); print(d.get('model','?'))")
            ts=$(python3  -c "import json; d=json.load(open('${mf}')); print(d.get('cached_at','?'))")
            pats=$(python3 -c "import json; d=json.load(open('${mf}')); print(' '.join(d.get('patterns',[])))")
            echo ""
            echo "  Key   : $(basename "$d")"
            echo "  Source: $src"
            echo "  Model : $mdl"
            echo "  Cached: $ts"
            echo "  Pats  : $pats"
        done
    fi
    echo ""
    exit 0
fi

# ── VALIDATE ───────────────────────────────────────────────────────────────────
[[ -z "$TARGET_URL" && -z "$TEXT_FILE" ]] && {
    echo "ERROR: --url or --text-file required" >&2
    echo "Run with --help" >&2
    exit 1
}

SOURCE="${TARGET_URL:-$TEXT_FILE}"
SLUG=$(make_slug "$SOURCE")
KEY=$(cache_key "$SOURCE" "$MODEL")
CACHE_ENTRY="${CACHE_DIR}/${KEY}"
MANIFEST="${CACHE_ENTRY}/manifest.json"
TIMESTAMP=$(date +"%Y-%m-%d-%H%M")

[[ -z "$OUTDIR" ]] && OUTDIR="${HOME}/fabric-analysis/${SLUG}"
OUTDIR="${OUTDIR/#\~/$HOME}"
OBSIDIAN_PATH="${OBSIDIAN_PATH/#\~/$HOME}"

# ── CACHE INFO ─────────────────────────────────────────────────────────────────
if [[ "$CACHE_INFO" == "true" ]]; then
    if [[ -f "$MANIFEST" ]]; then
        echo "═══ Cache entry for: $SOURCE ═══"
        python3 -c "import json; d=json.load(open('${MANIFEST}')); print(json.dumps(d, indent=2))"
        echo ""
        ls -lh "${CACHE_ENTRY}/"
    else
        echo "No cache entry for: $SOURCE"
        echo "Key would be: $KEY"
        echo "Run without --cache-info to extract and cache."
    fi
    exit 0
fi

# ── DRY RUN ────────────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == "true" ]]; then
    echo "═══ DRY RUN ═══"
    echo "Source   : $SOURCE"
    echo "Cache key: $KEY"
    echo "Cached   : $([[ -f "$MANIFEST" ]] && echo YES || echo NO)"
    echo "Refresh  : $REFRESH"
    echo "Theme    : ${THEME_NAME:-${THEME_FILE:-none (extract only)}}"
    echo "All themes: $ALL_THEMES"
    echo "Vendor   : $VENDOR / $MODEL"
    echo "Output   : $OUTDIR"
    exit 0
fi

# ── STEP 1: EXTRACT + CACHE (or load from cache) ──────────────────────────────
CACHE_HIT=false
ALL_PATTERNS=(extract_article_wisdom extract_wisdom extract_ideas extract_questions analyze_claims summarize)

if [[ -f "$MANIFEST" && "$REFRESH" == "false" ]]; then
    CACHE_HIT=true
    echo "✓ Cache hit: $KEY"
    echo "  Source : $SOURCE"
    python3 -c "
import json
d = json.load(open('${MANIFEST}'))
print(f'  Model  : {d.get(\"model\",\"?\")}')
print(f'  Cached : {d.get(\"cached_at\",\"?\")}')
print(f'  Patterns: {\" \".join(d.get(\"patterns\",[]))}')
"
else
    [[ "$REFRESH" == "true" && -d "$CACHE_ENTRY" ]] && {
        rm -rf "$CACHE_ENTRY"
        echo "⟳ Cache cleared — re-extracting..."
    }
    mkdir -p "$CACHE_ENTRY"
    echo "═══ Extracting and caching: $SOURCE"
    echo "  Model: $VENDOR / $MODEL"
    echo "  Key  : $KEY"
    echo ""

    CACHED_PATTERNS=()

    for pattern in "${ALL_PATTERNS[@]}"; do
        printf "  [%-30s] " "$pattern"
        T_S=$(ms)

        local_result=""
        if [[ -n "$TARGET_URL" ]]; then
            if is_youtube "$TARGET_URL"; then
                local_result=$(fabric -V "$VENDOR" -m "$MODEL" -p "$pattern" \
                    -y "$TARGET_URL" 2>/dev/null) || local_result=""
            else
                local_result=$(fabric -V "$VENDOR" -m "$MODEL" -p "$pattern" \
                    -u "$TARGET_URL" 2>/dev/null) || local_result=""
            fi
        else
            local_result=$(pandoc "$TEXT_FILE" -t plain --wrap=none 2>/dev/null \
                | fabric -V "$VENDOR" -m "$MODEL" -p "$pattern" 2>/dev/null) \
                || local_result=""
        fi

        # Retry once on empty
        if [[ -z "$local_result" ]]; then
            printf "[retry] "
            if [[ -n "$TARGET_URL" ]]; then
                if is_youtube "$TARGET_URL"; then
                    local_result=$(fabric -V "$VENDOR" -m "$MODEL" -p "$pattern" \
                        -y "$TARGET_URL" 2>/dev/null) || local_result=""
                else
                    local_result=$(fabric -V "$VENDOR" -m "$MODEL" -p "$pattern" \
                        -u "$TARGET_URL" 2>/dev/null) || local_result=""
                fi
            fi
        fi

        T_E=$(ms)
        EL=$((T_E - T_S))

        if [[ -z "$local_result" ]]; then
            printf "FAIL  %sms\n" "$EL"
        else
            printf "OK    %sms\n" "$EL"
            echo "$local_result" > "${CACHE_ENTRY}/${pattern}.md"
            CACHED_PATTERNS+=("$pattern")
        fi
    done

    # Write manifest
    python3 - "$MANIFEST" "$SOURCE" "$VENDOR" "$MODEL" "${CACHED_PATTERNS[@]}" << 'PYEOF'
import json, sys, datetime, pathlib
mf      = pathlib.Path(sys.argv[1])
source  = sys.argv[2]
vendor  = sys.argv[3]
model   = sys.argv[4]
patterns = list(sys.argv[5:])
manifest = {
    "source":     source,
    "vendor":     vendor,
    "model":      model,
    "cached_at":  datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
    "patterns":   patterns,
    "cache_key":  mf.parent.name,
}
mf.write_text(json.dumps(manifest, indent=2))
print(f"  ✓ Manifest written: {len(patterns)} patterns cached")
PYEOF
    echo ""
fi

# Load cache into memory
declare -A PAT
for pattern in "${ALL_PATTERNS[@]}"; do
    f="${CACHE_ENTRY}/${pattern}.md"
    [[ -f "$f" ]] && PAT["$pattern"]=$(cat "$f") || PAT["$pattern"]=""
done

# If no theme requested — extraction/cache only, done
if [[ -z "$THEME_NAME" && -z "$THEME_FILE" && "$ALL_THEMES" == "false" ]]; then
    echo "✓ Extraction complete. Cache: $CACHE_ENTRY"
    echo "  Run with --theme=<name> or --all-themes to generate documents."
    echo "  Available themes:"
    for f in "${THEMES_DIR}"/*.yaml; do
        name=$(basename "$f" .yaml)
        echo "    --theme=$name"
    done
    exit 0
fi

# ── STEP 2: THEME GENERATION FUNCTION ─────────────────────────────────────────
generate_theme() {
    local theme_file="$1"
    [[ ! -f "$theme_file" ]] && { echo "Theme not found: $theme_file" >&2; return 1; }

    # Parse theme YAML
    local theme_name word_limit title_suffix synthesis_directive
    theme_name=$(python3 -c "
import yaml, sys
d = yaml.safe_load(open('${theme_file}'))
print(d.get('theme','unknown'))
")
    title_suffix=$(python3 -c "
import yaml, sys
d = yaml.safe_load(open('${theme_file}'))
print(d.get('title_suffix','Analysis'))
")
    word_limit=$(python3 -c "
import yaml, sys
d = yaml.safe_load(open('${theme_file}'))
print(d.get('word_limit',3000))
")
    synthesis_directive=$(python3 -c "
import yaml, sys
d = yaml.safe_load(open('${theme_file}'))
print(d.get('synthesis_directive','Write a comprehensive analysis.'))
")
    # Which patterns this theme needs
    local patterns_needed
    patterns_needed=$(python3 -c "
import yaml, sys
d = yaml.safe_load(open('${theme_file}'))
print(' '.join(d.get('patterns_required', ['extract_article_wisdom','summarize'])))
")

    echo ""
    echo "═══ Theme: $theme_name ($word_limit words) ═══"

    # Build synthesis input from relevant cached patterns
    local syn_input="word_limit=${word_limit}"$'\n\n'
    syn_input+="Source: ${SOURCE}"$'\n\n'
    syn_input+="SYNTHESIS DIRECTIVE:"$'\n'"${synthesis_directive}"$'\n\n'

    for p in $patterns_needed; do
        if [[ -n "${PAT[$p]:-}" ]]; then
            syn_input+="== ${p^^} =="$'\n'"${PAT[$p]}"$'\n\n'
        else
            echo "  ⚠  Pattern $p not in cache — skipping"
        fi
    done

    # Run synthesis
    printf "  [%-30s] " "$SYNTH_PATTERN"
    T_S=$(ms)
    local synthesis
    synthesis=$(echo "$syn_input" \
        | fabric -V "$VENDOR" -m "$MODEL" -p "$SYNTH_PATTERN" 2>/dev/null) \
        || synthesis=""
    T_E=$(ms)
    EL=$((T_E - T_S))

    if [[ -z "$synthesis" ]]; then
        printf "FAIL  %sms\n" "$EL"
        return 1
    fi
    printf "OK    %sms\n" "$EL"

    local wc_out
    wc_out=$(echo "$synthesis" | wc -w)
    echo "  Words: $wc_out / $word_limit target"

    # Write output files
    mkdir -p "$OUTDIR"
    local safe_slug
    safe_slug=$(make_slug "$SOURCE")
    local md_out="${OUTDIR}/${safe_slug}-${theme_name}-${TIMESTAMP}.md"
    local docx_out="${OUTDIR}/${safe_slug}-${theme_name}-${TIMESTAMP}.docx"

    cat > "$md_out" << MDEOF
---
title: "$(basename "$SOURCE" | cut -c1-60) — ${title_suffix}"
subtitle: "Cached RAG Analysis · Theme: ${theme_name}"
author: "Peter Heller / Mind Over Metadata LLC"
date: "$(date +"%B %d, %Y")"
source: "${SOURCE}"
model: "${VENDOR} / ${MODEL}"
theme: "${theme_name}"
word_count: "${wc_out}"
cache_key: "${KEY}"
---

${synthesis}

---

*fabric_analyze_cached.sh v1.0.0 · ACES_fabric_analyze*
*Theme: ${theme_name} · Cache key: ${KEY} · ${wc_out} words · $(date +"%H:%M")*
MDEOF

    echo "  ✓ Markdown: $md_out"

    if [[ "$SKIP_DOCX" == "false" ]] && command -v pandoc &>/dev/null; then
        pandoc "$md_out" \
            --from markdown --to docx \
            --highlight-style tango --toc \
            -o "$docx_out" 2>/dev/null
        echo "  ✓ Word doc: $docx_out"
    fi

    if [[ -n "$OBSIDIAN_PATH" ]]; then
        mkdir -p "$OBSIDIAN_PATH"
        cp "$md_out" "${OBSIDIAN_PATH}/$(basename "$md_out")"
        echo "  ✓ Obsidian: ${OBSIDIAN_PATH}/$(basename "$md_out")"
    fi
}

# ── STEP 3: RESOLVE AND RUN THEMES ────────────────────────────────────────────
if [[ "$ALL_THEMES" == "true" ]]; then
    echo ""
    echo "Generating all 5 themes from cache..."
    for tf in "${THEMES_DIR}"/*.yaml; do
        generate_theme "$tf"
    done

elif [[ -n "$THEME_FILE" ]]; then
    generate_theme "$THEME_FILE"

elif [[ -n "$THEME_NAME" ]]; then
    tf="${THEMES_DIR}/${THEME_NAME}.yaml"
    if [[ ! -f "$tf" ]]; then
        echo "ERROR: Theme not found: $THEME_NAME" >&2
        echo "Available themes:"
        for f in "${THEMES_DIR}"/*.yaml; do
            echo "  $(basename "$f" .yaml)"
        done
        exit 1
    fi
    generate_theme "$tf"
fi

# ── DONE ───────────────────────────────────────────────────────────────────────
echo ""
echo "═══ COMPLETE $(date +"%H:%M") ═══"
echo "  Cache  : $CACHE_ENTRY"
echo "  Output : $OUTDIR"

command -v explorer.exe &>/dev/null && \
    explorer.exe "$(wslpath -w "$OUTDIR")" 2>/dev/null || true
