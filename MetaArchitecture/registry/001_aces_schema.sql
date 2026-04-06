-- ═══════════════════════════════════════════════════════════════════════════════
-- ACES Template Registry — PostgreSQL Schema v1.0.0
-- D⁴ governed — three-key physical model
-- Author: Peter Heller / Mind Over Metadata LLC
--
-- Extensions required:
--   CREATE EXTENSION vector;          -- pg_vector for embeddings + RAG
--   CREATE EXTENSION pg_trgm;         -- trigram text search
--   CREATE EXTENSION pgcrypto;        -- uuid generation
--
-- Run: psql -U postgres -d aces -f 001_aces_schema.sql
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS aces;

-- ── Surrogate sequences ───────────────────────────────────────────────────────
CREATE SEQUENCE IF NOT EXISTS aces.template_id_seq     START 1;
CREATE SEQUENCE IF NOT EXISTS aces.instance_id_seq     START 1;
CREATE SEQUENCE IF NOT EXISTS aces.phase_result_id_seq START 1;
CREATE SEQUENCE IF NOT EXISTS aces.rag_chunk_id_seq    START 1;
CREATE SEQUENCE IF NOT EXISTS aces.morph_log_id_seq    START 1;
CREATE SEQUENCE IF NOT EXISTS aces.rate_id_seq         START 1;

-- ═══════════════════════════════════════════════════════════════════════════════
-- TABLE: aces.templates
-- WORM after registration — never UPDATE, only INSERT new versions
-- Three-key D⁴ physical model
-- ═══════════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS aces.templates (

    -- Key 1: Sequential BIGINT surrogate (internal, never exposed)
    id              BIGINT          PRIMARY KEY
                                    DEFAULT nextval('aces.template_id_seq'),

    -- Key 2: Business identity (human-facing, Navigator-searchable)
    fqsn            VARCHAR(255)    NOT NULL,
    version         VARCHAR(50)     NOT NULL,

    -- Key 3: Content-addressed identity (D⁴ governance + ACESID-32 compatible)
    content_hash    CHAR(64)        NOT NULL,   -- BLAKE3-256 of template_yaml
    pair_hash       CHAR(64)        NOT NULL UNIQUE, -- BLAKE3(fqsn+version+content_hash)

    -- Identity
    title           VARCHAR(255)    NOT NULL,
    description     TEXT            NOT NULL,
    author          VARCHAR(255)    NOT NULL DEFAULT 'Peter Heller / Mind Over Metadata LLC',

    -- Template definition (WORM — never modified after insert)
    template_yaml   TEXT            NOT NULL,   -- canonical YAML (frozen)
    morph_contract  JSONB           NOT NULL,   -- fixed vs overridable params

    -- Phase topology (denormalized for query performance)
    phase_count     INTEGER         NOT NULL,
    barrier_type    VARCHAR(50)     NOT NULL DEFAULT 'sequential',
    pattern_names   TEXT[]          NOT NULL,   -- all patterns referenced
    tool_names      TEXT[]          NOT NULL DEFAULT '{}', -- Tavily, etc.

    -- pg_vector: semantic embedding for template discovery
    -- Navigator searches by intent → pg_vector finds matching template
    template_embedding  vector(768),            -- nomic-embed-text (local Ollama)

    -- D⁴ temporal referential integrity
    -- Allen Interval: valid_from to valid_to
    valid_from      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    valid_to        TIMESTAMPTZ     NOT NULL DEFAULT '9999-12-31 00:00:00+00',
    is_current      BOOLEAN         NOT NULL DEFAULT TRUE,

    -- Audit
    registered_at   TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    registered_by   VARCHAR(255)    NOT NULL DEFAULT 'Navigator',

    -- Constraints
    CONSTRAINT uq_template_fqsn_version UNIQUE (fqsn, version),
    CONSTRAINT chk_version_semver CHECK (version ~ '^\d+\.\d+\.\d+(-[a-zA-Z0-9]+)?$')
);

-- ── Indexes: templates ────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_templates_fqsn
    ON aces.templates (fqsn);

CREATE INDEX IF NOT EXISTS idx_templates_pair_hash
    ON aces.templates (pair_hash);

CREATE INDEX IF NOT EXISTS idx_templates_is_current
    ON aces.templates (is_current) WHERE is_current = TRUE;

CREATE INDEX IF NOT EXISTS idx_templates_embedding
    ON aces.templates USING ivfflat (template_embedding vector_cosine_ops)
    WITH (lists = 10);    -- tune to sqrt(row_count)

CREATE INDEX IF NOT EXISTS idx_templates_description_trgm
    ON aces.templates USING gin (description gin_trgm_ops);

-- ═══════════════════════════════════════════════════════════════════════════════
-- TABLE: aces.instances
-- Every TaskInstance ever created — one row per pipeline run
-- ═══════════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS aces.instances (

    id              BIGINT          PRIMARY KEY
                                    DEFAULT nextval('aces.instance_id_seq'),

    -- ACESID-32 task identifier (UUIDv7 structured)
    task_id         UUID            NOT NULL DEFAULT gen_random_uuid() UNIQUE,

    -- Template reference (FK to registered template)
    template_id     BIGINT          NOT NULL REFERENCES aces.templates(id),
    template_fqsn   VARCHAR(255)    NOT NULL,
    template_version VARCHAR(50)    NOT NULL,

    -- Morphed parameters (what changed from template defaults)
    source_url      TEXT            NOT NULL,
    morph_params    JSONB           NOT NULL DEFAULT '{}',

    -- pg_vector: semantic embedding of source content
    -- Used for: dedup check before running, RAG retrieval context
    source_embedding    vector(768),

    -- Execution state
    status          VARCHAR(50)     NOT NULL DEFAULT 'pending',
                    -- pending | running | complete | failed | cancelled
    phase_count     INTEGER         NOT NULL,
    phases_complete INTEGER         NOT NULL DEFAULT 0,
    phases_failed   INTEGER         NOT NULL DEFAULT 0,

    -- Timing
    wall_ms         INTEGER,
    started_at      TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,

    -- Cost
    cost_usd_total  NUMERIC(10,6)   NOT NULL DEFAULT 0.0,

    -- Output paths
    markdown_path   TEXT,
    docx_path       TEXT,
    workspace_path  TEXT,           -- TaskWorkspace root directory

    -- Session context
    session_id      VARCHAR(255),
    navigator_id    VARCHAR(255)    NOT NULL DEFAULT 'pheller',

    -- Audit
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- ── Indexes: instances ────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_instances_template_id
    ON aces.instances (template_id);

CREATE INDEX IF NOT EXISTS idx_instances_status
    ON aces.instances (status);

CREATE INDEX IF NOT EXISTS idx_instances_created_at
    ON aces.instances (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_instances_source_embedding
    ON aces.instances USING ivfflat (source_embedding vector_cosine_ops)
    WITH (lists = 10);

-- ═══════════════════════════════════════════════════════════════════════════════
-- TABLE: aces.phase_results
-- One row per phase per instance
-- ═══════════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS aces.phase_results (

    id              BIGINT          PRIMARY KEY
                                    DEFAULT nextval('aces.phase_result_id_seq'),

    instance_id     BIGINT          NOT NULL REFERENCES aces.instances(id),
    phase           INTEGER         NOT NULL,
    phase_label     VARCHAR(255),
    pattern         VARCHAR(255)    NOT NULL,
    vendor          VARCHAR(100)    NOT NULL,
    model           VARCHAR(100)    NOT NULL,
    source_url      TEXT,           -- effective source (may differ from instance)

    -- Execution
    status          VARCHAR(50)     NOT NULL,
    elapsed_ms      INTEGER,
    attempts        INTEGER         NOT NULL DEFAULT 1,

    -- Output
    output_text     TEXT,
    word_count      INTEGER,

    -- pg_vector: embedding of phase output
    -- Primary RAG retrieval target — "find relevant phase outputs"
    output_embedding    vector(768),

    -- Cost
    tokens_in       INTEGER,
    tokens_out      INTEGER,
    cost_usd        NUMERIC(10,6)   NOT NULL DEFAULT 0.0,

    -- Audit
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_instance_phase UNIQUE (instance_id, phase)
);

-- ── Indexes: phase_results ────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_phase_results_instance_id
    ON aces.phase_results (instance_id);

CREATE INDEX IF NOT EXISTS idx_phase_results_pattern
    ON aces.phase_results (pattern);

CREATE INDEX IF NOT EXISTS idx_phase_results_output_embedding
    ON aces.phase_results USING ivfflat (output_embedding vector_cosine_ops)
    WITH (lists = 10);

-- ═══════════════════════════════════════════════════════════════════════════════
-- TABLE: aces.rag_chunks
-- Chunked phase outputs for RAG retrieval
-- Each phase output is split into ~500-word chunks
-- This is the primary RAG knowledge base
-- ═══════════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS aces.rag_chunks (

    id              BIGINT          PRIMARY KEY
                                    DEFAULT nextval('aces.rag_chunk_id_seq'),

    instance_id     BIGINT          NOT NULL REFERENCES aces.instances(id),
    phase_result_id BIGINT          NOT NULL REFERENCES aces.phase_results(id),

    phase           INTEGER         NOT NULL,
    pattern         VARCHAR(255)    NOT NULL,
    chunk_index     INTEGER         NOT NULL,  -- 0-based chunk sequence
    chunk_text      TEXT            NOT NULL,  -- ~500 words
    word_count      INTEGER         NOT NULL,

    -- Source metadata for RAG context assembly
    source_url      TEXT,
    template_fqsn   VARCHAR(255)    NOT NULL,
    instance_task_id UUID           NOT NULL,
    run_date        DATE            NOT NULL,

    -- pg_vector: per-chunk embedding (primary RAG index)
    chunk_embedding     vector(768) NOT NULL,

    -- Audit
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_chunk UNIQUE (phase_result_id, chunk_index)
);

-- ── Indexes: rag_chunks ───────────────────────────────────────────────────────
-- Primary RAG retrieval index — this is the hot path
CREATE INDEX IF NOT EXISTS idx_rag_chunks_embedding
    ON aces.rag_chunks USING ivfflat (chunk_embedding vector_cosine_ops)
    WITH (lists = 50);    -- larger lists for larger table

CREATE INDEX IF NOT EXISTS idx_rag_chunks_pattern
    ON aces.rag_chunks (pattern);

CREATE INDEX IF NOT EXISTS idx_rag_chunks_run_date
    ON aces.rag_chunks (run_date DESC);

CREATE INDEX IF NOT EXISTS idx_rag_chunks_template
    ON aces.rag_chunks (template_fqsn);

-- Full text search on chunk content
CREATE INDEX IF NOT EXISTS idx_rag_chunks_text_trgm
    ON aces.rag_chunks USING gin (chunk_text gin_trgm_ops);

-- ═══════════════════════════════════════════════════════════════════════════════
-- TABLE: aces.morph_log
-- Audit trail of every morph() call
-- WORM — append only
-- ═══════════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS aces.morph_log (

    id              BIGINT          PRIMARY KEY
                                    DEFAULT nextval('aces.morph_log_id_seq'),

    instance_id     BIGINT          NOT NULL REFERENCES aces.instances(id),
    template_id     BIGINT          NOT NULL REFERENCES aces.templates(id),

    -- What was morphed
    morph_params    JSONB           NOT NULL,   -- full morph parameters
    morph_delta     JSONB           NOT NULL,   -- only what changed from defaults

    -- Validation result
    morph_valid     BOOLEAN         NOT NULL,
    morph_errors    TEXT[],         -- constraint violations if invalid

    morphed_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    morphed_by      VARCHAR(255)    NOT NULL DEFAULT 'Navigator'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- TABLE: aces.rates
-- Vendor rates (refreshed daily from pricepertoken.com)
-- ═══════════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS aces.rates (

    id              BIGINT          PRIMARY KEY
                                    DEFAULT nextval('aces.rate_id_seq'),

    provider        VARCHAR(100)    NOT NULL,
    model           VARCHAR(100)    NOT NULL,
    input_per_1m    NUMERIC(10,6)   NOT NULL DEFAULT 0.0,
    output_per_1m   NUMERIC(10,6)   NOT NULL DEFAULT 0.0,
    fetched_at      DATE            NOT NULL,
    source          VARCHAR(255)    NOT NULL DEFAULT 'pricepertoken.com',
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rates_provider_model
    ON aces.rates (provider, model, fetched_at DESC);

-- ═══════════════════════════════════════════════════════════════════════════════
-- VIEWS
-- ═══════════════════════════════════════════════════════════════════════════════

-- Cost summary — joins instances + phase_results + rates
CREATE OR REPLACE VIEW aces.cost_summary AS
SELECT
    i.task_id,
    i.created_at::DATE          AS run_date,
    t.fqsn                      AS template_fqsn,
    t.version                   AS template_version,
    i.source_url,
    i.status,
    i.wall_ms,
    i.cost_usd_total,
    pr.phase,
    pr.pattern,
    pr.vendor,
    pr.model,
    pr.elapsed_ms,
    pr.tokens_in,
    pr.tokens_out,
    pr.cost_usd                 AS phase_cost_usd,
    r.input_per_1m,
    r.output_per_1m
FROM aces.instances i
JOIN aces.templates t       ON i.template_id = t.id
JOIN aces.phase_results pr  ON pr.instance_id = i.id
LEFT JOIN aces.rates r      ON  r.provider  = pr.vendor
                            AND r.model     = pr.model
                            AND r.fetched_at = (
                                SELECT MAX(fetched_at) FROM aces.rates
                                WHERE provider = pr.vendor AND model = pr.model
                            );

-- Template performance — avg wall time, failure rate per template
CREATE OR REPLACE VIEW aces.template_performance AS
SELECT
    t.fqsn,
    t.version,
    t.title,
    COUNT(i.id)                             AS total_runs,
    COUNT(i.id) FILTER (WHERE i.status = 'complete') AS successful_runs,
    ROUND(AVG(i.wall_ms)::NUMERIC / 1000, 1)         AS avg_wall_seconds,
    ROUND(SUM(i.cost_usd_total)::NUMERIC, 4)          AS total_cost_usd,
    MAX(i.created_at)                       AS last_run
FROM aces.templates t
LEFT JOIN aces.instances i ON i.template_id = t.id
GROUP BY t.id, t.fqsn, t.version, t.title;

-- RAG retrieval function — find top-K chunks similar to query embedding
CREATE OR REPLACE FUNCTION aces.rag_search(
    query_embedding vector(768),
    top_k           INTEGER DEFAULT 5,
    pattern_filter  VARCHAR DEFAULT NULL,
    template_filter VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    chunk_text      TEXT,
    pattern         VARCHAR,
    template_fqsn   VARCHAR,
    source_url      TEXT,
    run_date        DATE,
    similarity      FLOAT
) AS $$
    SELECT
        rc.chunk_text,
        rc.pattern,
        rc.template_fqsn,
        rc.source_url,
        rc.run_date,
        1 - (rc.chunk_embedding <=> query_embedding) AS similarity
    FROM aces.rag_chunks rc
    WHERE (pattern_filter IS NULL OR rc.pattern = pattern_filter)
      AND (template_filter IS NULL OR rc.template_fqsn ILIKE '%' || template_filter || '%')
    ORDER BY rc.chunk_embedding <=> query_embedding
    LIMIT top_k;
$$ LANGUAGE sql STABLE;

-- Template semantic search function
CREATE OR REPLACE FUNCTION aces.find_template(
    query_embedding vector(768),
    top_k           INTEGER DEFAULT 3
)
RETURNS TABLE (
    id          BIGINT,
    fqsn        VARCHAR,
    version     VARCHAR,
    title       VARCHAR,
    description TEXT,
    similarity  FLOAT
) AS $$
    SELECT
        t.id,
        t.fqsn,
        t.version,
        t.title,
        t.description,
        1 - (t.template_embedding <=> query_embedding) AS similarity
    FROM aces.templates t
    WHERE t.is_current = TRUE
    ORDER BY t.template_embedding <=> query_embedding
    LIMIT top_k;
$$ LANGUAGE sql STABLE;

