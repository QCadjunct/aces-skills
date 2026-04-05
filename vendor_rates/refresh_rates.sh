#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# refresh_rates.sh — Daily LLM Rate Refresh
# FQSN: vendor_rates/refresh_rates.sh
# VERSION: 2.0.0
#
# Fetches current LLM pricing from pricepertoken.com (updated daily).
# Outputs:
#   1. vendor_rates.yaml     — human-readable, used by pipeline at runtime
#   2. rates_YYYYMMDD.jsonl  — JSONL append to cost_audit.log
#   3. rates_YYYYMMDD.parquet — timestamped Parquet for DuckDB insertion
#
# Cron (FreedomTower midnight):
#   0 0 * * * /home/pheller/projects/aces-skills/vendor_rates/refresh_rates.sh \
#             >> /home/pheller/.config/fabric/rate_refresh.log 2>&1
#
# AUTHOR: Peter Heller / Mind Over Metadata LLC
# REPO:   QCadjunct/aces-skills
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TIMESTAMP=$(date +"%Y%m%dT%H%M%S")
DATE=$(date +"%Y-%m-%d")
DATESTAMP=$(date +"%Y%m%d")

RATES_YAML="${SCRIPT_DIR}/vendor_rates.yaml"
AUDIT_LOG="${HOME}/.config/fabric/cost_audit.log"
PARQUET_DIR="${HOME}/.config/fabric/rates_history"
JSONL_ENTRY="${PARQUET_DIR}/rates_${DATESTAMP}.jsonl"
PARQUET_FILE="${PARQUET_DIR}/rates_${DATESTAMP}.parquet"

mkdir -p "$PARQUET_DIR"

echo "═══ refresh_rates.sh v2.0.0 — ${TIMESTAMP} ═══"

# ── STEP 1: Fetch pricing page from pricepertoken.com ────────────────────────
echo "  Fetching pricepertoken.com..."

RAW_HTML=$(curl -s --max-time 30 \
    -H "User-Agent: ACES-FabricStitch-RateRefresh/2.0 (QCadjunct/aces-skills)" \
    "https://pricepertoken.com/" 2>/dev/null) || {
    echo "  ✗ Fetch failed — using cached rates"
    exit 0
}

echo "  ✓ Page fetched ($(echo "$RAW_HTML" | wc -c) bytes)"

# ── STEP 2: Parse pricing via Python ─────────────────────────────────────────
echo "  Parsing model rates..."

python3 << PYEOF
import json
import re
import datetime
import pathlib
import sys

html = """${RAW_HTML}"""

# Extract JSON data embedded in the page (pricepertoken uses Next.js __NEXT_DATA__)
match = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', html, re.DOTALL)

models = []
if match:
    try:
        data = json.loads(match.group(1))
        # Navigate Next.js data structure
        props = data.get('props', {}).get('pageProps', {})
        raw_models = props.get('models', props.get('data', []))

        for m in raw_models:
            if isinstance(m, dict) and m.get('input') is not None:
                models.append({
                    'provider':       m.get('provider', m.get('vendor', 'unknown')),
                    'model':          m.get('model', m.get('name', 'unknown')),
                    'input_per_1m':   float(m.get('input', 0) or 0),
                    'output_per_1m':  float(m.get('output', 0) or 0),
                    'context_k':      m.get('context', None),
                    'fetched_at':     '${DATE}',
                })
    except Exception as e:
        print(f"  ⚠  JSON parse failed: {e}", file=sys.stderr)

# Fallback: hardcoded known rates for ACES stack models
# Updated manually when auto-fetch fails
KNOWN_RATES = [
    # Ollama local — always zero cost
    {'provider':'Ollama','model':'qwen3.5:397b-cloud','input_per_1m':0.0,'output_per_1m':0.0,'context_k':None,'fetched_at':'${DATE}'},
    {'provider':'Ollama','model':'qwen3:8b',          'input_per_1m':0.0,'output_per_1m':0.0,'context_k':8,'fetched_at':'${DATE}'},
    {'provider':'Ollama','model':'gemma4:31b-cloud',  'input_per_1m':0.0,'output_per_1m':0.0,'context_k':None,'fetched_at':'${DATE}'},
    {'provider':'Ollama','model':'gemma3:12b',        'input_per_1m':0.0,'output_per_1m':0.0,'context_k':128,'fetched_at':'${DATE}'},
    # Cloud vendors — per pricepertoken.com April 2026
    {'provider':'Anthropic','model':'claude-sonnet-4-6', 'input_per_1m':3.0, 'output_per_1m':15.0, 'context_k':200,'fetched_at':'${DATE}'},
    {'provider':'Anthropic','model':'claude-opus-4-6',   'input_per_1m':5.0, 'output_per_1m':25.0, 'context_k':200,'fetched_at':'${DATE}'},
    {'provider':'Anthropic','model':'claude-haiku-4-5',  'input_per_1m':1.0, 'output_per_1m':5.0,  'context_k':200,'fetched_at':'${DATE}'},
    {'provider':'OpenAI',   'model':'gpt-4o',            'input_per_1m':2.5, 'output_per_1m':10.0, 'context_k':128,'fetched_at':'${DATE}'},
    {'provider':'Google',   'model':'gemini-2.5-flash',  'input_per_1m':0.3, 'output_per_1m':2.5,  'context_k':1000,'fetched_at':'${DATE}'},
]

if not models:
    print("  ⚠  Auto-fetch produced no models — using known rates fallback")
    models = KNOWN_RATES
else:
    # Merge known Ollama rates (not on pricepertoken)
    known_keys = {(m['provider'], m['model']) for m in models}
    for r in KNOWN_RATES:
        if (r['provider'], r['model']) not in known_keys:
            models.append(r)
    print(f"  ✓ {len(models)} models parsed from pricepertoken.com")

# ── Write vendor_rates.yaml ───────────────────────────────────────────────────
import yaml

# Group by provider
by_provider = {}
for m in models:
    p = m['provider']
    if p not in by_provider:
        by_provider[p] = {}
    by_provider[p][m['model']] = {
        'input_per_1m':  m['input_per_1m'],
        'output_per_1m': m['output_per_1m'],
    }
    if m.get('context_k'):
        by_provider[p][m['model']]['context_k'] = m['context_k']

yaml_data = {
    'updated':  '${DATE}',
    'source':   'pricepertoken.com',
    'fetched':  '${TIMESTAMP}',
    'vendors':  by_provider,
}

yaml_path = pathlib.Path('${RATES_YAML}')
yaml_path.write_text(yaml.dump(yaml_data, default_flow_style=False, sort_keys=False))
print(f"  ✓ vendor_rates.yaml written ({len(models)} models)")

# ── Write JSONL entries ───────────────────────────────────────────────────────
jsonl_path = pathlib.Path('${JSONL_ENTRY}')
with open(jsonl_path, 'w') as f:
    for m in models:
        entry = {
            'event':          'rate_refresh',
            'timestamp':      '${TIMESTAMP}',
            'date':           '${DATE}',
            'provider':       m['provider'],
            'model':          m['model'],
            'input_per_1m':   m['input_per_1m'],
            'output_per_1m':  m['output_per_1m'],
            'source':         'pricepertoken.com',
        }
        f.write(json.dumps(entry) + '\n')
print(f"  ✓ JSONL written: {jsonl_path}")

# ── Append to cost_audit.log ──────────────────────────────────────────────────
audit_path = pathlib.Path('${AUDIT_LOG}')
audit_path.parent.mkdir(parents=True, exist_ok=True)
with open(audit_path, 'a') as f:
    entry = {
        'event':       'rate_refresh',
        'timestamp':   '${TIMESTAMP}',
        'date':        '${DATE}',
        'models_count': len(models),
        'source':      'pricepertoken.com',
        'output_yaml': '${RATES_YAML}',
        'output_jsonl':'${JSONL_ENTRY}',
    }
    f.write(json.dumps(entry) + '\n')
print(f"  ✓ cost_audit.log entry appended")

# ── Write Parquet via DuckDB ──────────────────────────────────────────────────
try:
    import duckdb
    con = duckdb.connect()

    # Create table from models list
    con.execute("""
        CREATE TABLE rates AS
        SELECT * FROM (VALUES """ +
        ','.join(
            f"('{m['provider']}','{m['model']}',{m['input_per_1m']},{m['output_per_1m']},'{m['fetched_at']}')"
            for m in models
        ) +
        """) t(provider, model, input_per_1m, output_per_1m, fetched_at)
    """)

    con.execute(f"COPY rates TO '${PARQUET_FILE}' (FORMAT PARQUET)")
    con.close()
    print(f"  ✓ Parquet written: ${PARQUET_FILE}")

except ImportError:
    print("  ⚠  duckdb not installed — skipping Parquet (pip install duckdb --break-system-packages)")
except Exception as e:
    print(f"  ⚠  Parquet write failed: {e}")

print(f"  Done: {len(models)} models refreshed")
PYEOF

# ── STEP 3: Commit to aces-skills ────────────────────────────────────────────
echo ""
echo "  Committing vendor_rates.yaml to aces-skills..."

cd "$REPO_DIR"
git add vendor_rates/vendor_rates.yaml
git diff --cached --quiet && {
    echo "  ✓ No rate changes — nothing to commit"
} || {
    git commit -m "chore(vendor_rates): daily rate refresh ${DATE}

Source: pricepertoken.com
Fetched: ${TIMESTAMP}
All cluster nodes get updated rates on next git pull."
    git push
    echo "  ✓ Committed and pushed"
}

echo ""
echo "═══ refresh_rates.sh COMPLETE — ${TIMESTAMP} ═══"
