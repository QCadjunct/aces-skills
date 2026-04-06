#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# install_aces_stack.sh — Install ACES + LangGraph + Registry dependencies
# Run from: ~/projects/aces-skills
# Uses uv exclusively — no pip
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail
echo "═══ ACES Stack Installation (uv) ═══"

cd ~/projects/aces-skills

# ── Core ACES dependencies (already installed) ────────────────────────────────
echo "  Verifying existing dependencies..."
uv run python -c "import duckdb, yaml, marimo; print('  ✓ Core deps present')"

# ── LangGraph ecosystem ───────────────────────────────────────────────────────
echo "  Adding LangGraph ecosystem..."
uv add langgraph
uv add langchain-ollama
uv add langchain-anthropic
uv add langsmith

# ── Search + RAG ──────────────────────────────────────────────────────────────
echo "  Adding Tavily (web search for delivery phase)..."
uv add tavily-python

# ── PostgreSQL + pgvector ─────────────────────────────────────────────────────
echo "  Adding PostgreSQL client + pgvector..."
uv add "psycopg[binary]"
uv add asyncpg
uv add pgvector
uv add sqlalchemy

# ── Content hashing ───────────────────────────────────────────────────────────
echo "  Adding BLAKE3 for D⁴ governance hashing..."
uv add blake3

# ── Semantic versioning ───────────────────────────────────────────────────────
echo "  Adding semver for template version validation..."
uv add semver

# ── Verify ────────────────────────────────────────────────────────────────────
echo ""
echo "  Verifying installation..."
uv run python -c "
import langgraph, langchain_ollama, langsmith
import tavily, asyncpg, pgvector
import blake3, semver
print('  ✓ All ACES stack dependencies installed')
print(f'  LangGraph:  {langgraph.__version__}')
"

echo ""
echo "═══ Installation complete ═══"
echo ""
echo "Next steps:"
echo "  1. Set up PostgreSQL: createdb aces"
echo "  2. Run schema:        psql -d aces -f MetaArchitecture/registry/001_aces_schema.sql"
echo "  3. Register template: uv run python template_registry.py --register gap_analysis_v1.yaml"
echo "  4. Set env vars:"
echo "     export LANGSMITH_API_KEY=your_key"
echo "     export TAVILY_API_KEY=your_key"
echo "     export ANTHROPIC_API_KEY=your_key"
echo "     export ACES_DB_URL=postgresql://localhost/aces"
