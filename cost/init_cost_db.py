#!/usr/bin/env python3
"""
init_cost_db.py — Initialize cost_audit.duckdb
Run once: uv run python init_cost_db.py

Creates the four tables:
  runs     — one row per pipeline run
  agents   — one row per agent per run
  rates    — current vendor rates (refreshed daily)
  patterns — aggregate stats per pattern

Also creates a view: cost_summary (joins runs + agents + rates)
"""

import duckdb
import pathlib
import datetime

DB_PATH = pathlib.Path.home() / ".config/fabric/cost_audit.duckdb"
DB_PATH.parent.mkdir(parents=True, exist_ok=True)

con = duckdb.connect(str(DB_PATH))

con.execute("""
CREATE TABLE IF NOT EXISTS runs (
    run_id          VARCHAR PRIMARY KEY,
    timestamp       TIMESTAMP,
    source          VARCHAR,
    vendor          VARCHAR,
    model           VARCHAR,
    chain_type      VARCHAR,   -- skill_chain | cached_rag | sequential
    agents_total    INTEGER,
    agents_complete INTEGER,
    agents_failed   INTEGER,
    wall_ms         INTEGER,
    sequential_est_ms INTEGER,
    speedup         DOUBLE,
    tokens_in_total  INTEGER,
    tokens_out_total INTEGER,
    cost_usd_total  DOUBLE,
    synthesis_pattern VARCHAR,
    output_path     VARCHAR,
    created_at      TIMESTAMP DEFAULT current_timestamp
)
""")

con.execute("CREATE SEQUENCE IF NOT EXISTS agents_seq START 1")

con.execute("""
CREATE TABLE IF NOT EXISTS agents (
    id              INTEGER PRIMARY KEY DEFAULT nextval('agents_seq'),
    run_id          VARCHAR REFERENCES runs(run_id),
    pattern         VARCHAR,
    vendor          VARCHAR,
    model           VARCHAR,
    status          VARCHAR,   -- complete | failed | cancelled
    elapsed_ms      INTEGER,
    attempts        INTEGER,
    tokens_in       INTEGER,
    tokens_out      INTEGER,
    cost_usd        DOUBLE,
    created_at      TIMESTAMP DEFAULT current_timestamp
)
""")

con.execute("CREATE SEQUENCE IF NOT EXISTS rates_seq START 1")

con.execute("""
CREATE TABLE IF NOT EXISTS rates (
    id              INTEGER PRIMARY KEY DEFAULT nextval('rates_seq'),
    provider        VARCHAR,
    model           VARCHAR,
    input_per_1m    DOUBLE,
    output_per_1m   DOUBLE,
    fetched_at      DATE,
    source          VARCHAR DEFAULT 'pricepertoken.com',
    created_at      TIMESTAMP DEFAULT current_timestamp
)
""")

con.execute("""
CREATE TABLE IF NOT EXISTS patterns (
    pattern_name    VARCHAR PRIMARY KEY,
    runs_total      INTEGER DEFAULT 0,
    tokens_in_avg   DOUBLE,
    tokens_out_avg  DOUBLE,
    elapsed_ms_avg  DOUBLE,
    cost_per_run_avg DOUBLE,
    cost_total_usd  DOUBLE DEFAULT 0.0,
    last_run        TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT current_timestamp
)
""")

con.execute("""
CREATE OR REPLACE VIEW cost_summary AS
SELECT
    r.run_id,
    r.timestamp,
    r.source,
    r.vendor,
    r.model,
    r.chain_type,
    r.wall_ms,
    r.speedup,
    r.cost_usd_total,
    a.pattern,
    a.elapsed_ms,
    a.tokens_in,
    a.tokens_out,
    a.cost_usd        AS agent_cost_usd,
    rt.input_per_1m,
    rt.output_per_1m,
    rt.fetched_at     AS rate_date
FROM runs r
JOIN agents a ON r.run_id = a.run_id
LEFT JOIN rates rt
    ON  rt.provider = a.vendor
    AND rt.model    = a.model
    AND rt.fetched_at = (
        SELECT MAX(fetched_at) FROM rates
        WHERE provider = a.vendor AND model = a.model
    )
""")

print(f"✓ cost_audit.duckdb initialized: {DB_PATH}")
print(f"  Tables: runs, agents, rates, patterns")
print(f"  View:   cost_summary")

# Load any existing JSONL from rates history
import pathlib, json
rates_dir = pathlib.Path.home() / ".config/fabric/rates_history"
if rates_dir.exists():
    jsonl_files = sorted(rates_dir.glob("rates_*.jsonl"))
    if jsonl_files:
        print(f"\n  Loading {len(jsonl_files)} existing JSONL rate files...")
        for jf in jsonl_files:
            con.execute(f"""
                INSERT INTO rates (provider, model, input_per_1m, output_per_1m, fetched_at, source)
                SELECT provider, model, input_per_1m, output_per_1m, CAST(date AS DATE), 'pricepertoken.com'
                FROM read_ndjson_auto('{jf}')
                WHERE event = 'rate_refresh'
                  AND NOT EXISTS (
                    SELECT 1 FROM rates r2
                    WHERE r2.provider = provider
                      AND r2.model = model
                      AND r2.fetched_at = CAST(date AS DATE)
                  )
            """)
        print(f"  ✓ Historical rates loaded")

con.close()
print("\n✓ Done.")
