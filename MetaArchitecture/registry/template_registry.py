"""
template_registry.py — ACES Template Registry v1.0.0
FQSN: MetaArchitecture/Registry/template_registry

Manages WORM template registration, semantic search, and morph() instantiation.
Backed by PostgreSQL + pg_vector + pgduckdb.

Architecture:
  TemplateRegistry  — catalog of registered templates
  SkillChainTemplate — WORM template definition (frozen after registration)
  MorphContract      — declares what is fixed vs overridable
  TemplateMorph      — one instantiation of a template with bound parameters
  RAGRetriever       — semantic search over past phase outputs

Author: Peter Heller / Mind Over Metadata LLC
Repo:   QCadjunct/aces-skills
FQSN:   MetaArchitecture/Registry/template_registry
"""

from __future__ import annotations

import hashlib
import json
import re
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

import yaml


# ═══════════════════════════════════════════════════════════════════════════════
# BLAKE3 content hashing (D⁴ governance key)
# Falls back to SHA3-256 if blake3 not installed
# ═══════════════════════════════════════════════════════════════════════════════

def _hash(content: str) -> str:
    """BLAKE3-256 hash of content — D⁴ governance key."""
    try:
        import blake3
        return blake3.blake3(content.encode()).hexdigest()
    except ImportError:
        # Fallback: SHA3-256 (same output length, cryptographically sound)
        return hashlib.sha3_256(content.encode()).hexdigest()


def _pair_hash(fqsn: str, version: str, content_hash: str) -> str:
    """D⁴ PAIR_HASH — BLAKE3(fqsn + version + content_hash)."""
    return _hash(f"{fqsn}|{version}|{content_hash}")


# ═══════════════════════════════════════════════════════════════════════════════
# MORPH CONTRACT
# Declares what is WORM (fixed) vs overridable at instantiation time
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass
class MorphConstraint:
    """Constraint on an overridable parameter."""
    param:          str
    allowed_types:  list[str] = field(default_factory=list)   # e.g. ["url", "github_url"]
    vendor_whitelist: list[str] = field(default_factory=list) # e.g. ["Ollama", "Anthropic"]
    must_match_role: bool = False                              # pattern must match phase role
    required:       bool = False                               # must be set at instantiation


@dataclass
class MorphContract:
    """
    Declares the morph semantics of a template.

    fixed:        topology, pattern_names, barrier_type — WORM, never change
    overridable:  source_url, models, phases, patterns — can bind at instantiation
    constrained:  overridable but within declared bounds
    """
    fixed:       list[str]          = field(default_factory=list)
    overridable: list[str]          = field(default_factory=list)
    constrained: list[MorphConstraint] = field(default_factory=list)

    @classmethod
    def default(cls) -> "MorphContract":
        """Standard morph contract for skill chain templates."""
        return cls(
            fixed=[
                "topology",
                "phase_count",
                "barrier_type",
                "pattern_names",
            ],
            overridable=[
                "source_url",
                "model_per_phase",
                "phase_enabled",
                "pattern_per_phase",
                "synthesis_model",
                "word_minimum",
                "word_target",
                "word_limit",
            ],
            constrained=[
                MorphConstraint(
                    param="source_url",
                    allowed_types=["url", "github_url", "file_path"],
                    required=True,
                ),
                MorphConstraint(
                    param="model_per_phase",
                    vendor_whitelist=["Ollama", "Anthropic", "OpenAI", "Google"],
                ),
                MorphConstraint(
                    param="pattern_per_phase",
                    must_match_role=True,
                ),
            ],
        )

    def to_dict(self) -> dict:
        return {
            "fixed": self.fixed,
            "overridable": self.overridable,
            "constrained": [
                {
                    "param": c.param,
                    "allowed_types": c.allowed_types,
                    "vendor_whitelist": c.vendor_whitelist,
                    "must_match_role": c.must_match_role,
                    "required": c.required,
                }
                for c in self.constrained
            ],
        }

    @classmethod
    def from_dict(cls, d: dict) -> "MorphContract":
        return cls(
            fixed=d.get("fixed", []),
            overridable=d.get("overridable", []),
            constrained=[
                MorphConstraint(**c) for c in d.get("constrained", [])
            ],
        )


# ═══════════════════════════════════════════════════════════════════════════════
# SKILL CHAIN TEMPLATE (WORM)
# Frozen at authoring time — never modified after registration
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass
class SkillChainTemplate:
    """
    WORM template definition.
    Frozen at authoring time.
    Registered in the TemplateRegistry under FQSN@version.

    Identity:
      fqsn         — Fully Qualified Skill Name
      version      — semantic version (1.0.0)
      content_hash — BLAKE3(canonical_yaml) — detects tampering
      pair_hash    — BLAKE3(fqsn+version+content_hash) — D⁴ governance key
    """
    fqsn:           str
    version:        str
    title:          str
    description:    str
    template_yaml:  str             # canonical YAML (frozen)
    morph_contract: MorphContract
    author:         str = "Peter Heller / Mind Over Metadata LLC"

    # Computed at registration
    content_hash:   str = field(default="", init=False)
    pair_hash:      str = field(default="", init=False)

    def __post_init__(self):
        self.content_hash = _hash(self.template_yaml)
        self.pair_hash    = _pair_hash(self.fqsn, self.version, self.content_hash)

    @classmethod
    def from_yaml_file(cls, path: Path) -> "SkillChainTemplate":
        """
        Load a template from a YAML file.
        The file IS the canonical form — content_hash is derived from it.
        """
        raw = path.read_text()
        data = yaml.safe_load(raw)

        morph_contract = MorphContract.from_dict(
            data.get("morph_contract", MorphContract.default().to_dict())
        )

        return cls(
            fqsn          = data["fqsn"],
            version       = data["version"],
            title         = data["title"],
            description   = data.get("description", ""),
            template_yaml = raw,
            morph_contract= morph_contract,
            author        = data.get("author", "Peter Heller / Mind Over Metadata LLC"),
        )

    def verify_integrity(self, stored_content_hash: str) -> bool:
        """
        Verify template has not been tampered with.
        Compare stored hash against recomputed hash of current YAML.
        """
        return self.content_hash == stored_content_hash

    @property
    def identity(self) -> str:
        return f"{self.fqsn}@{self.version}"

    def phases(self) -> list[dict]:
        """Parse phases from template_yaml."""
        data = yaml.safe_load(self.template_yaml)
        return data.get("phases", [])

    def pattern_names(self) -> list[str]:
        """All patterns referenced across all phases."""
        names = []
        for ph in self.phases():
            for agent in ph.get("agents", []):
                names.append(agent["pattern"])
        return list(set(names))


# ═══════════════════════════════════════════════════════════════════════════════
# TEMPLATE MORPH — one instantiation of a template
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass
class TemplateMorph:
    """
    One instantiation of a SkillChainTemplate with bound parameters.

    The template topology is WORM.
    The morph parameters are the concrete bindings for this run.

    task_id: ACESID-32 / UUIDv7 — unique per instantiation
    """
    template:       SkillChainTemplate
    source_url:     str
    morph_params:   dict[str, Any] = field(default_factory=dict)
    task_id:        str = field(default_factory=lambda: str(uuid.uuid4()))
    session_id:     str = ""
    created_at:     datetime = field(default_factory=lambda: datetime.now(timezone.utc))

    # Validation result
    is_valid:       bool = field(default=True, init=False)
    errors:         list[str] = field(default_factory=list, init=False)

    def __post_init__(self):
        self._validate()

    def _validate(self):
        """Validate morph parameters against the template's morph contract."""
        contract = self.template.morph_contract
        errors   = []

        # source_url is always required
        if not self.source_url:
            errors.append("source_url is required")

        # Check fixed params are not being overridden
        for fixed in contract.fixed:
            if fixed in self.morph_params:
                errors.append(f"'{fixed}' is fixed — cannot be overridden at instantiation")

        # Check constrained params
        for constraint in contract.constrained:
            val = self.morph_params.get(constraint.param)
            if constraint.required and val is None and constraint.param != "source_url":
                errors.append(f"'{constraint.param}' is required")
            if val and constraint.vendor_whitelist:
                vendor = val.get("vendor") if isinstance(val, dict) else None
                if vendor and vendor not in constraint.vendor_whitelist:
                    errors.append(
                        f"'{constraint.param}' vendor '{vendor}' not in whitelist "
                        f"{constraint.vendor_whitelist}"
                    )

        self.is_valid = len(errors) == 0
        self.errors   = errors

    def to_skill_chain_yaml(self) -> str:
        """
        Produce a concrete skill_chain.yaml from the template + morph params.
        This is what the orchestrator actually runs.
        """
        data = yaml.safe_load(self.template.template_yaml)

        # Apply source_url
        data["source"] = self.source_url

        # Apply model overrides per phase
        model_overrides = self.morph_params.get("model_per_phase", {})
        phase_enabled   = self.morph_params.get("phase_enabled", {})
        pattern_overrides = self.morph_params.get("pattern_per_phase", {})

        for phase in data.get("phases", []):
            ph_num = str(phase["phase"])
            for agent in phase.get("agents", []):
                if ph_num in model_overrides:
                    agent["model"] = model_overrides[ph_num].get("model", agent["model"])
                    agent["vendor"] = model_overrides[ph_num].get("vendor", agent["vendor"])
                if ph_num in pattern_overrides:
                    agent["pattern"] = pattern_overrides[ph_num]
            if ph_num in phase_enabled:
                phase["enabled"] = phase_enabled[ph_num]

        # Apply word budget overrides
        if "synthesis_model" in self.morph_params:
            data["synthesis"]["model"]  = self.morph_params["synthesis_model"].get("model")
            data["synthesis"]["vendor"] = self.morph_params["synthesis_model"].get("vendor")
        if "word_minimum" in self.morph_params:
            data["synthesis"]["word_minimum"] = self.morph_params["word_minimum"]
        if "word_target" in self.morph_params:
            data["synthesis"]["word_target"]  = self.morph_params["word_target"]
        if "word_limit" in self.morph_params:
            data["synthesis"]["word_limit"]   = self.morph_params["word_limit"]

        return yaml.dump(data, default_flow_style=False, sort_keys=False)

    @property
    def morph_delta(self) -> dict:
        """Only the parameters that differ from template defaults."""
        return {k: v for k, v in self.morph_params.items() if v is not None}


# ═══════════════════════════════════════════════════════════════════════════════
# TEMPLATE REGISTRY
# In-memory catalog backed by PostgreSQL
# ═══════════════════════════════════════════════════════════════════════════════

class TemplateRegistry:
    """
    Catalog of registered WORM templates.
    Backed by PostgreSQL + pg_vector for semantic search.

    Usage:
        registry = TemplateRegistry(db_url="postgresql://...")
        await registry.connect()

        # Register a template
        template = SkillChainTemplate.from_yaml_file(Path("gap_analysis_v1.yaml"))
        await registry.register(template)

        # Find template by semantic search
        results = await registry.find("analyze framework promise vs delivery")

        # Morph a template into an instance
        morph = registry.morph(
            fqsn="CodingArchitecture/FabricStitch/gap_analysis",
            version="1.0.0",
            source_url="https://github.com/QCadjunct/UOR-Framework",
        )
    """

    def __init__(self, db_url: str = "", templates_dir: Path = None):
        self.db_url       = db_url
        self.templates_dir = templates_dir or Path.home() / "projects/aces-skills/MetaArchitecture/registry/templates"
        self._cache: dict[str, SkillChainTemplate] = {}
        self._conn = None

    async def connect(self):
        """Connect to PostgreSQL."""
        if self.db_url:
            try:
                import asyncpg
                self._conn = await asyncpg.connect(self.db_url)
            except Exception as e:
                print(f"⚠  DB connection failed: {e} — using file-only mode")

    async def close(self):
        if self._conn:
            await self._conn.close()

    # ── Registration ──────────────────────────────────────────────────────────

    async def register(self, template: SkillChainTemplate) -> bool:
        """
        Register a template in the catalog.
        WORM — if pair_hash already exists, registration is rejected.
        Returns True if registered, False if already exists.
        """
        # Check cache first
        if template.identity in self._cache:
            existing = self._cache[template.identity]
            if existing.pair_hash == template.pair_hash:
                print(f"  ✓ Already registered: {template.identity}")
                return False
            else:
                raise ValueError(
                    f"Template {template.identity} exists with different content. "
                    f"Increment version to register a new template."
                )

        self._cache[template.identity] = template

        if self._conn:
            await self._conn.execute("""
                INSERT INTO aces.templates (
                    fqsn, version, content_hash, pair_hash,
                    title, description, author,
                    template_yaml, morph_contract,
                    phase_count, barrier_type, pattern_names
                ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
                ON CONFLICT (pair_hash) DO NOTHING
            """,
                template.fqsn,
                template.version,
                template.content_hash,
                template.pair_hash,
                template.title,
                template.description,
                template.author,
                template.template_yaml,
                json.dumps(template.morph_contract.to_dict()),
                len(template.phases()),
                "sequential",
                template.pattern_names(),
            )

        print(f"  ✓ Registered: {template.identity} [{template.pair_hash[:8]}...]")
        return True

    async def load_all(self):
        """Load all templates from the templates directory."""
        if not self.templates_dir.exists():
            return
        for yaml_file in self.templates_dir.glob("*.yaml"):
            try:
                template = SkillChainTemplate.from_yaml_file(yaml_file)
                await self.register(template)
            except Exception as e:
                print(f"  ⚠  Failed to load {yaml_file.name}: {e}")

    # ── Lookup ────────────────────────────────────────────────────────────────

    def get(self, fqsn: str, version: str) -> Optional[SkillChainTemplate]:
        """Get template by FQSN and version."""
        return self._cache.get(f"{fqsn}@{version}")

    def list_all(self) -> list[SkillChainTemplate]:
        """List all registered templates."""
        return list(self._cache.values())

    async def find(
        self,
        query: str,
        top_k: int = 3,
        embedding_model: str = "nomic-embed-text",
    ) -> list[tuple[SkillChainTemplate, float]]:
        """
        Semantic search over registered templates using pg_vector.
        Returns list of (template, similarity_score) tuples.

        Falls back to keyword search if pg_vector unavailable.
        """
        if self._conn:
            try:
                from langchain_ollama import OllamaEmbeddings
                embedder = OllamaEmbeddings(model=embedding_model)
                query_vec = await embedder.aembed_query(query)

                rows = await self._conn.fetch("""
                    SELECT fqsn, version,
                           1 - (template_embedding <=> $1::vector) AS similarity
                    FROM aces.templates
                    WHERE is_current = TRUE
                    ORDER BY template_embedding <=> $1::vector
                    LIMIT $2
                """, query_vec, top_k)

                results = []
                for row in rows:
                    template = self.get(row["fqsn"], row["version"])
                    if template:
                        results.append((template, float(row["similarity"])))
                return results
            except Exception:
                pass

        # Fallback: keyword search in cache
        query_lower = query.lower()
        results = []
        for template in self._cache.values():
            score = 0.0
            if any(w in template.title.lower() for w in query_lower.split()):
                score += 0.5
            if any(w in template.description.lower() for w in query_lower.split()):
                score += 0.3
            if score > 0:
                results.append((template, score))
        return sorted(results, key=lambda x: x[1], reverse=True)[:top_k]

    # ── Morphing ──────────────────────────────────────────────────────────────

    def morph(
        self,
        fqsn:        str,
        version:     str,
        source_url:  str,
        morph_params: dict[str, Any] = None,
        session_id:  str = "",
    ) -> TemplateMorph:
        """
        Instantiate a template with concrete parameters.
        Returns a TemplateMorph — validated, ready to run.
        Raises ValueError if template not found or morph is invalid.
        """
        template = self.get(fqsn, version)
        if not template:
            raise ValueError(f"Template not found: {fqsn}@{version}")

        morph = TemplateMorph(
            template     = template,
            source_url   = source_url,
            morph_params = morph_params or {},
            session_id   = session_id,
        )

        if not morph.is_valid:
            raise ValueError(
                f"Morph validation failed for {fqsn}@{version}:\n"
                + "\n".join(f"  - {e}" for e in morph.errors)
            )

        return morph

    # ── RAG ───────────────────────────────────────────────────────────────────

    async def rag_search(
        self,
        query:           str,
        top_k:           int = 5,
        pattern_filter:  str = None,
        template_filter: str = None,
        embedding_model: str = "nomic-embed-text",
    ) -> list[dict]:
        """
        RAG retrieval over past phase outputs.
        Returns top-K most relevant chunks with metadata.

        Use this to answer Navigator questions like:
        "What patterns of failure appear across all frameworks we've analyzed?"
        """
        if not self._conn:
            return []

        try:
            from langchain_ollama import OllamaEmbeddings
            embedder  = OllamaEmbeddings(model=embedding_model)
            query_vec = await embedder.aembed_query(query)

            rows = await self._conn.fetch("""
                SELECT * FROM aces.rag_search($1, $2, $3, $4)
            """, query_vec, top_k, pattern_filter, template_filter)

            return [dict(row) for row in rows]
        except Exception as e:
            print(f"⚠  RAG search failed: {e}")
            return []


# ═══════════════════════════════════════════════════════════════════════════════
# EXAMPLE TEMPLATE YAML
# ═══════════════════════════════════════════════════════════════════════════════

EXAMPLE_TEMPLATE = """
# ── gap_analysis_v1.yaml ──────────────────────────────────────────────────────
# WORM template — never edit after registration
# To update: create gap_analysis_v2.yaml with version: 2.0.0
# ─────────────────────────────────────────────────────────────────────────────

fqsn:    CodingArchitecture/FabricStitch/gap_analysis
version: 1.0.0
title:   Promise vs Delivery Gap Analysis
description: >
  Three-phase sequential pipeline that compares what a framework promised
  against what it delivered. Phase 1 extracts the original vision,
  Phase 2 extracts current state, Phase 3 performs Allen Interval gap analysis.
  Produces an ACES analytical brief with temporal verdicts.
author:  Peter Heller / Mind Over Metadata LLC

morph_contract:
  fixed:
    - topology
    - phase_count
    - barrier_type
    - pattern_names
  overridable:
    - source_url
    - model_per_phase
    - phase_enabled
    - pattern_per_phase
    - synthesis_model
    - word_minimum
    - word_target
    - word_limit
  constrained:
    - param: source_url
      allowed_types: [url, github_url]
      required: true
    - param: model_per_phase
      vendor_whitelist: [Ollama, Anthropic, OpenAI, Google]
    - param: pattern_per_phase
      must_match_role: true

phases:
  - phase: 1
    label: "PROMISE — what was claimed"
    depends_on: []
    agents:
      - pattern: extract_article_wisdom
        label:   "Extract all claims and promises from original source"
        vendor:  Ollama
        model:   qwen3.5:397b-cloud
        source:  ""
        retry:   2
        timeout: 600
        enabled: true

  - phase: 2
    label: "DELIVERY — what exists today"
    depends_on: [1]
    agents:
      - pattern: extract_wisdom
        label:   "Extract current state from delivery source"
        vendor:  Ollama
        model:   qwen3-next:80b-cloud
        source:  ""
        retry:   2
        timeout: 600
        enabled: true

  - phase: 3
    label: "GAP — promise vs delivery"
    depends_on: [1, 2]
    agents:
      - pattern: ACES_gap_analysis
        label:   "Allen Interval gap analysis"
        vendor:  Ollama
        model:   qwen3.5:397b-cloud
        source:  ""
        retry:   2
        timeout: 600
        enabled: true

synthesis:
  pattern:        synthesize_analysis_brief_from_wisdom
  vendor:         Anthropic
  model:          claude-opus-4-5
  word_minimum:   5000
  word_target:    6500
  word_limit:     8000
  document_limit: 15000
  directive:      ""
"""


if __name__ == "__main__":
    # Quick smoke test
    import asyncio
    import tempfile

    async def main():
        # Write example template to temp file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            f.write(EXAMPLE_TEMPLATE)
            tmp = Path(f.name)

        template = SkillChainTemplate.from_yaml_file(tmp)
        print(f"\nTemplate: {template.identity}")
        print(f"  pair_hash:    {template.pair_hash[:16]}...")
        print(f"  content_hash: {template.content_hash[:16]}...")
        print(f"  phases:       {len(template.phases())}")
        print(f"  patterns:     {template.pattern_names()}")

        # Test morph
        registry = TemplateRegistry()
        await registry.register(template)

        morph = registry.morph(
            fqsn       = "CodingArchitecture/FabricStitch/gap_analysis",
            version    = "1.0.0",
            source_url = "https://next.redhat.com/2022/07/13/the-uor-framework/",
            morph_params = {
                "model_per_phase": {
                    "2": {"vendor": "Anthropic", "model": "claude-sonnet-4-5"}
                }
            }
        )
        print(f"\nMorph: task_id={morph.task_id[:8]}...")
        print(f"  valid:  {morph.is_valid}")
        print(f"  delta:  {morph.morph_delta}")

        # Show concrete YAML
        concrete = morph.to_skill_chain_yaml()
        print(f"\nConcrete skill_chain.yaml preview:")
        print("\n".join(concrete.split("\n")[:15]))

        tmp.unlink()

    asyncio.run(main())
