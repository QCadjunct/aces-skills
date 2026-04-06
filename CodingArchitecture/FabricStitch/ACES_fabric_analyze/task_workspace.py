"""
task_workspace.py — ACES TaskWorkspace
FQSN: CodingArchitecture/FabricStitch/ACES_fabric_analyze/task_workspace.py
VERSION: 1.0.0-ACES

Shared filesystem coordination substrate for ACES TaskInstances.
Replaces asyncio.gather() join point with a true $AND barrier
using atomic flag files as the coordination primitive.

Architecture:
  Local Event Flags  → workspace/flags/*.flag   (per-agent, set on complete)
  Global Event Flags → cross-task RabbitMQ/Tailscale (future)
  Common Event Flag  → TaskWorkspace instance    (TeamAgent owns this)

Enqueue: agent writes output → sets flag (atomic on POSIX)
Dequeue: TeamAgent polls all_flags_set() → True → reads context_map

Author: Peter Heller / Mind Over Metadata LLC
Repo:   QCadjunct/aces-skills
"""

from __future__ import annotations

import asyncio
import datetime
import pathlib
import shutil
from dataclasses import dataclass, field


# ═══════════════════════════════════════════════════════════════════════════════
# TASK WORKSPACE
# ═══════════════════════════════════════════════════════════════════════════════

class TaskWorkspace:
    """
    Shared filesystem workspace for one TaskInstance.

    Directory layout:
      {root}/
        task_manifest.yaml     WORM — written at dispatch, never modified
        flags/
          {pattern}.flag       Atomic touch — agent sets on complete
        outputs/
          {pattern}.md         Agent writes output here before setting flag
        synthesis/
          input.md             Assembled by TeamAgent after barrier releases
          output.md            Synthesis result
          {slug}.docx          pandoc output
        cost/
          cost_actual.yaml     Written by TeamAgent after barrier releases

    The flags/ directory IS the event flag cluster.
    Each .flag file IS a local event flag.
    all_flags_set() IS the $AND barrier condition.
    wait_all() IS SYS$WFLAND — wait for ALL flags in cluster.
    """

    POLL_INTERVAL_MS: int = 500    # barrier poll interval

    def __init__(self, task_id: str, outdir: pathlib.Path):
        self.task_id  = task_id
        self.root     = outdir / task_id
        self.flags    = self.root / "flags"
        self.outputs  = self.root / "outputs"
        self.synthesis = self.root / "synthesis"
        self.cost     = self.root / "cost"
        self._init_dirs()

    def _init_dirs(self) -> None:
        for d in [self.flags, self.outputs, self.synthesis, self.cost]:
            d.mkdir(parents=True, exist_ok=True)

    # ── Agent interface (called by each SubAgent/TeamMate) ────────────────────

    def set_flag(self, pattern: str, output: str) -> None:
        """
        Agent calls this when complete.
        Two-step: write output THEN set flag (atomic ordering).
        The flag is the signal — output must be readable before flag is set.

        Maps to VMS: SYS$SETEF (set event flag)
        """
        output_path = self.outputs / f"{pattern}.md"
        output_path.write_text(output, encoding="utf-8")
        # Touch flag AFTER writing output — atomic on POSIX
        flag_path = self.flags / f"{pattern}.flag"
        flag_path.touch()

    def clear_flag(self, pattern: str) -> None:
        """
        Clear a specific flag — used on retry.
        Maps to VMS: SYS$CLREF (clear event flag)
        """
        flag_path = self.flags / f"{pattern}.flag"
        if flag_path.exists():
            flag_path.unlink()

    # ── TeamAgent interface (barrier owner) ───────────────────────────────────

    def all_flags_set(self, patterns: list[str]) -> bool:
        """
        True when ALL flags are present.
        Maps to VMS: $AND condition on event flag cluster.
        """
        return all(
            (self.flags / f"{p}.flag").exists()
            for p in patterns
        )

    def status(self, patterns: list[str]) -> dict[str, bool]:
        """
        Query which flags are currently set.
        Maps to VMS: SYS$READEF (read event flags).
        """
        return {
            p: (self.flags / f"{p}.flag").exists()
            for p in patterns
        }

    def get_context_map(self) -> dict[str, str]:
        """
        Read all agent outputs after barrier releases.
        TeamAgent calls this after wait_all() returns.
        """
        return {
            f.stem: (self.outputs / f"{f.stem}.md").read_text(encoding="utf-8")
            for f in sorted(self.flags.iterdir())
            if f.suffix == ".flag"
        }

    async def wait_all(
        self,
        patterns:   list[str],
        timeout_s:  int = 900,
    ) -> dict[str, str]:
        """
        True $AND barrier — polls until ALL flags set or timeout.
        TeamAgent blocks here during resource wait state.

        Maps to VMS: SYS$WFLAND (wait for ALL event flags in cluster).

        Returns: context_map {pattern: output} when all flags set.
        Raises:  TimeoutError if not all flags set within timeout_s.
        """
        deadline = datetime.datetime.now().timestamp() + timeout_s
        while not self.all_flags_set(patterns):
            if datetime.datetime.now().timestamp() > deadline:
                missing = [
                    p for p in patterns
                    if not (self.flags / f"{p}.flag").exists()
                ]
                raise TimeoutError(
                    f"$AND barrier timeout after {timeout_s}s. "
                    f"Missing flags: {missing}"
                )
            await asyncio.sleep(self.POLL_INTERVAL_MS / 1000)
        return self.get_context_map()

    # ── Workspace lifecycle ───────────────────────────────────────────────────

    def write_manifest(self, manifest: dict) -> None:
        """Write WORM task manifest — called once at dispatch."""
        import yaml
        manifest_path = self.root / "task_manifest.yaml"
        manifest_path.write_text(
            yaml.dump(manifest, default_flow_style=False),
            encoding="utf-8"
        )

    def archive(self, archive_root: pathlib.Path) -> pathlib.Path:
        """Move completed workspace to archive location."""
        dest = archive_root / self.task_id
        shutil.move(str(self.root), str(dest))
        return dest

    def __repr__(self) -> str:
        return f"TaskWorkspace(task_id={self.task_id}, root={self.root})"


# ═══════════════════════════════════════════════════════════════════════════════
# TASK INSTANCE
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass
class TaskInstance:
    """
    One unit of work dispatched to the ACES pipeline.
    Owns the TaskWorkspace. TeamAgent receives this.

    task_id:      ACESID-32 / UUIDv7 — unique per run
    template_ref: FQSN of skill_chain.yaml
    source:       URL being analyzed
    theme:        analysis theme (default: analytical-brief)
    session_id:   session identifier for cost grouping
    workspace:    shared coordination substrate
    """
    task_id:      str
    template_ref: str
    source:       str
    theme:        str        = "analytical-brief"
    session_id:   str        = ""
    workspace:    TaskWorkspace | None = field(default=None, repr=False)
    status:       str        = "pending"
    created_at:   datetime.datetime = field(
                      default_factory=datetime.datetime.now
                  )

    @classmethod
    def create(
        cls,
        template_ref: str,
        source:       str,
        outdir:       pathlib.Path,
        theme:        str = "analytical-brief",
        session_id:   str = "",
    ) -> "TaskInstance":
        """Factory — generates task_id and initializes workspace."""
        import uuid
        task_id   = str(uuid.uuid4())
        workspace = TaskWorkspace(task_id, outdir)
        return cls(
            task_id      = task_id,
            template_ref = template_ref,
            source       = source,
            theme        = theme,
            session_id   = session_id,
            workspace    = workspace,
        )
