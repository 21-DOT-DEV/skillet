# Phase 7 — Multi-Harness Portability (differentiator #2)

**Status:** PLANNED
**Horizon:** Next
**Last Updated:** 2026-06-17

## Goal

Run the same suite through multiple agents and print a per-harness `pass^k`
portability table — "passes on Claude Code, flakes on OpenCode." This is the
second feature that justifies a new tool, and only a design that is multi-harness
from day one (Phase 1's adapter seam) can deliver it. It sits last in the Next
horizon because it is a differentiator, not a Northstar value gap — but it is
still v1.

## Key Features

1. opencode adapter (CLI: `--harness opencode`) — PLANNED · Net-new
   - Purpose & user value: The second real agent — the one that makes the matrix
     meaningful and proves the adapter seam by a second implementation rather than
     assertion.
   - Northstar: differentiator #2 (portability needs ≥2 agents).
   - Success metrics:
     - Runs a task and parses its native logs into a `Trace` (golden-file tested).
     - Supports the load+visible injection contract for behavioral and trigger axes.
   - Dependencies: adapter seam (Phase 1).
   - Confidence: Low — second-adapter choice is design Open Question 1 (doc assumes opencode). `needs-research`

2. direct-api adapter (CLI: `--harness direct-api`) — PLANNED · Net-new
   - Purpose & user value: A harness that inlines `SKILL.md` + references into the
     system context (siblings listed, bodies withheld) — and doubles as the
     cheapest CI text judge.
   - Northstar: differentiator #2 + spend honesty (cheap CI path).
   - Success metrics:
     - Executes a task with inline injection and trivial trace parsing.
     - Refuses `capture` loudly (no native session store) rather than failing silently.
   - Dependencies: adapter seam (Phase 1).
   - Confidence: Medium — design §9.5, §13.

3. Replay adapter (test/replay double) — PLANNED · Ported
   - Purpose & user value: Serve recorded traces/verdicts back so skillet's own
     suite and matrix tests run free and deterministic.
   - Northstar: loop integrity (cheap, reproducible CI).
   - Success metrics:
     - A recorded run replays identically with no harness or network.
   - Dependencies: record/replay (Phase 2).
   - Confidence: Medium — design §9.5, §10.

4. The portability table (CLI: `skillet run --matrix`) — PLANNED · Net-new
   - Purpose & user value: Fan the suite across harnesses and add per-harness
     `pass^k` columns — the headline output no existing tool offers.
   - Northstar: differentiator #2 surface.
   - Success metrics:
     - `run --matrix` prints per-harness `pass^k` columns and flags evals that pass on one harness and fail/flake on another.
     - Spend estimate accounts for the harness multiplier before running.
   - Dependencies: ≥2 adapters (F1/F2), runner (Phase 1).
   - Confidence: Medium — design §6.1 `run`, §9.5.

5. Binary resolution chain & ban policy (CLI: `skillet harness list|info`, `harness which --search`) — PLANNED · Ported
   - Purpose & user value: A fixed, printable resolution chain and a provenance-backed
     denylist so dev↔CI runs are reproducible — never a silent swap of an
     explicitly-pinned banned binary.
   - Northstar: loop integrity (reproducibility, provenance).
   - Success metrics:
     - `harness info <id>` shows which link of the chain won; an explicitly-pinned banned version is a hard `3`, an auto-discovered one falls back with a notice.
     - `harness which --search` prints an `export`-able pin (never auto-probes other apps' private caches).
   - Dependencies: adapters.
   - Confidence: Medium — design §9.1.

6. Per-adapter environment-hygiene contracts — PLANNED · Net-new
   - Purpose & user value: Each adapter declares which env vars are stripped /
     required / passed through (e.g. strip `CLAUDECODE` so a nested skillet doesn't
     confuse the child harness) — clean nesting, not ad-hoc.
   - Northstar: loop integrity (reproducible, non-interfering runs).
   - Success metrics:
     - An agent-launched skillet runs a child harness without env bleed (tested).
   - Dependencies: adapters.
   - Confidence: Medium — design §10.

## Dependencies & Sequencing

- Local ordering: adapters (F1/F2/F3) → matrix (F4); resolution/ban (F5) and env
  hygiene (F6) underpin all adapters.
- Cross-phase: all build on Phase 1's `HarnessAdapter` seam; `--matrix` reuses the
  Phase 1/2 runner and judge.

## Phase Metrics & Success Criteria

- This phase is successful when: a maintainer runs `run --matrix` across two real
  agents plus direct-api and gets an honest per-harness `pass^k` table that names
  the binaries it resolved.

## Risks & Assumptions

- The specific second agent (opencode vs codex vs gemini-cli) is design Open
  Question 1; opencode is assumed. `codex` is Phase 8.

## Phase Change Log

- 2026-06-17: Phase created. Sequenced last within Next — a differentiator, not a
  Northstar value gap — per the Northstar-forward tie-break.
