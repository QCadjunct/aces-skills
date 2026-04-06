---
id: ADR-015
title: TaskWorkspace as True $AND Barrier Substrate
status: Accepted
date: 2026-04-05
author: Peter Heller / Mind Over Metadata LLC
tags:
  - architecture
  - and-barrier
  - task-workspace
  - synchronization
  - teamagent
supersedes: []
related:
  - ADR-008 (stdlib hook pattern)
  - ADR-009 (D4 MDLC Governance)
---

# ADR-015 — TaskWorkspace as True $AND Barrier Substrate

## Context

The current `skill_chain_orchestrator.py` uses `asyncio.gather()` as
the $AND barrier. This is a join point — not a true barrier.

It works under current conditions because:
1. All agents have high latency (20–500 seconds each)
2. All agents are independent SubAgents with no inter-agent communication
3. All agents run in the same Python process on the same node

It will fail when:
1. TeamMates need to signal each other mid-execution
2. Agents run on different cluster nodes (FreedomTower, TheBeast, etc.)
3. An agent crashes — the coroutine dies silently with no flag evidence
4. The barrier needs to query partial progress during execution
5. Cost accounting needs per-agent timestamps at completion

## Decision

Replace `asyncio.gather()` with a `TaskWorkspace` — a shared filesystem
coordination substrate — as the $AND barrier primitive.

The workspace directory IS the event flag cluster.
Each `.flag` file IS a local event flag.
`all_flags_set()` IS the $AND barrier condition.
`wait_all()` IS `SYS$WFLAND` — wait for ALL flags in cluster.

## VMS Mapping

| VMS Primitive | ACES Equivalent |
|---|---|
| Event flag cluster | `TaskWorkspace` instance |
| Local event flag (1-23) | `flags/{pattern}.flag` file |
| Global event flag (64-127) | Cross-task RabbitMQ / Tailscale (future) |
| `SYS$SETEF` (set flag) | `workspace.set_flag(pattern, output)` |
| `SYS$CLREF` (clear flag) | `workspace.clear_flag(pattern)` |
| `SYS$READEF` (read flags) | `workspace.status(patterns)` |
| `SYS$WFLAND` (wait for ALL) | `await workspace.wait_all(patterns)` |
| `SYS$WFLOR` (wait for ANY) | `asyncio.gather()` — retained for SubAgent launch |

## Enqueue / Dequeue Semantics

```
Enqueue (agent side):
  1. Agent completes execution
  2. Agent writes output to workspace/outputs/{pattern}.md
  3. Agent touches workspace/flags/{pattern}.flag  ← atomic on POSIX
  Flag set IS the enqueue signal

Dequeue (TeamAgent side):
  1. TeamAgent polls workspace.all_flags_set(patterns) every 500ms
  2. When True → dequeue condition met
  3. TeamAgent calls workspace.get_context_map()
  4. Reads all outputs atomically — all guaranteed written before flags set
  5. Proceeds to synthesis
```

## TaskWorkspace Directory Layout

```
~/fabric-analysis/{task_id}/
  task_manifest.yaml     WORM — written at dispatch, never modified
  flags/
    extract_article_wisdom.flag
    extract_wisdom.flag
    extract_ideas.flag
    extract_questions.flag
    analyze_claims.flag
    summarize.flag
    ACES_temporal_gap_analysis.flag
  outputs/
    extract_article_wisdom.md
    extract_wisdom.md
    extract_ideas.md
    extract_questions.md
    analyze_claims.md
    summarize.md
    ACES_temporal_gap_analysis.md
  synthesis/
    input.md              Compressed context assembled by TeamAgent
    output.md             Synthesis result
    {slug}.docx           pandoc output
  cost/
    cost_actual.yaml      Per-agent cost written at flag-set time
```

## Cross-Node Architecture

When agents run on different cluster nodes:

```
FreedomTower (TeamAgent)
  │
  ├── Agent 1 → local subprocess → writes to ~/fabric-analysis/{task_id}/
  ├── Agent 2 → SSH to TheBeast  → writes to Tailscale-mounted path
  ├── Agent 7 → SSH to Teacher   → writes to Tailscale-mounted path
  │
  └── $AND barrier polls flags/ on shared Tailscale mount
      When all 7 flags present → barrier releases on FreedomTower
```

The shared path can be:
- NFS mount over Tailscale mesh
- Synology DS920+ at 192.168.1.242 mounted on all nodes
- RustFS S3-compatible object store (future)

## TeamMate Communication Path

Once the workspace exists, TeamMate communication is trivial:

```
Analyst TeamMate writes: workspace/synthesis/analyst_brief.md
Writer TeamMate reads:   workspace/synthesis/analyst_brief.md
Writer TeamMate writes:  workspace/synthesis/writer_draft.md
TeamAgent assembles:     workspace/synthesis/output.md
```

No message queues needed for intra-task communication.
The filesystem is the message bus at this level.

## Two-Phase Synthesis (companion to this ADR)

The workspace also solves the synthesis truncation problem:

```
Phase 1 — Compress (in-process after barrier releases):
  Each agent output → first 500 words
  Passed to synthesis model as context

Phase 2 — Archive (after synthesis completes):
  Full verbatim outputs written to Tier 2 WORM archive
  Never passed to synthesis model — prevents context overflow

Result:
  Synthesis input: 7 × 500 words = ~3,500 words
  Previously:      7 × 3,000 words = ~21,000 words
  Reduction: 6× fewer input tokens → synthesis completes within output limits
```

## Consequences

**Positive:**
- True $AND barrier — flag ownership is explicit and auditable
- Cross-node agent execution — any node with workspace mount can participate
- Agent crash detection — missing flag after timeout = explicit failure
- Partial progress visibility — query status() at any time
- WORM audit trail — workspace persists as run artifact
- TeamMate communication — shared workspace enables bidirectional signals
- Cost accounting — per-agent cost written at flag-set time with precise timestamp

**Negative:**
- Filesystem I/O overhead — negligible for current agent latencies (20-500s)
- Workspace cleanup required — must archive or delete after run
- Shared mount required for cross-node — Tailscale path configuration needed

## Implementation Status

- `task_workspace.py` — written, not yet wired into orchestrator
- `TaskInstance` dataclass — written alongside TaskWorkspace
- `skill_chain_orchestrator.py` — still uses `asyncio.gather()`
- Wiring into orchestrator — P1 next sprint

## Migration Path

```
Sprint N (current): asyncio.gather() + two-phase compression (DONE)
Sprint N+1:         TaskWorkspace wired alongside gather() (parallel)
Sprint N+2:         gather() replaced by workspace.wait_all()
Sprint N+3:         Cross-node agents via Tailscale mount
Sprint N+4:         TeamMate communication via workspace/synthesis/
```

