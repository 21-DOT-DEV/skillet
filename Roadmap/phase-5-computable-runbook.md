# Phase 5 — The Computable Runbook (differentiator #1)

**Status:** PLANNED
**Horizon:** Next
**Last Updated:** 2026-06-17

## Goal

Turn the EDD runbook from prose you must remember into state the tool computes.
A deterministic gates engine derives corroboration, de-dupe, and HELD/WATCH state
from repo files alone, and `skillet next` renders the single highest-value action
— with its reason and the exact command. This is the first of the two features
that justify a new tool, and it encodes the expert's cost-benefit discipline:
*most evidence should not become a `SKILL.md` edit.*

## Key Features

1. **[F37]** The gates engine (CLI: `skillet gate eval`) — PLANNED · Net-new
   - Purpose & user value: A pure, instant, exhaustively-tested function over
     evidence + eval results + thresholds that decides what may be pulled and why
     — so the worklist is trustworthy the way `git status` is. It is the encoded
     cost-benefit/corroboration call: counts unique domains, respects human HELD,
     puts hygiene first, and flags single-version/single-model evidence.
   - Northstar: differentiator #1 core; encodes "evidence-to-edit ratio" discipline.
   - Success metrics:
     - Codify needs ≥3 evidence (or same root cause twice); prose edits need ≥3 sessions across ≥2 distinct domains (defaults, tunable per repo).
     - Corroboration counts unique `domain` values, not raw sessions; cross-version evidence is flagged, not counted; `"unknown"` counts separately.
     - A human `held` state suppresses ACT-NOW promotion even when counts clear.
     - Every assessment carries the evidence set, the rule, the gap, and a ready-to-run command (property-tested).
   - Dependencies: evidence format (Phase 3), eval results (Phase 1/2), contradiction join (Phase 4).
   - Confidence: Medium — design §8.

2. **[F38]** The prioritized worklist (CLI: `skillet next`) — PLANNED · Net-new
   - Purpose & user value: "git status for EDD" — the flagship. A pure derivation
     that tells you, with reasons, the single highest-value next action and the
     exact command, grouped ACT NOW / NEEDS CORROBORATION / HELD / WATCH.
   - Northstar: differentiator #1 surface; routes work to both value gaps.
   - Success metrics:
     - `next` renders the gate engine's output with a reason and a runnable command on every line.
     - Flaky evals and contradictions outrank everything; HELD items show their reason and are not nagged.
   - Dependencies: gates engine (F37).
   - Confidence: Medium — design §6.1 `next`.

3. **[F39]** CI invariant enforcement (CLI: `skillet next --strict`) — PLANNED · Net-new
   - Purpose & user value: Let CI enforce the runbook — exit `5` on a violated
     invariant (a codified eval with no proof run, a skill_md edit landed without
     cleared gates) — without skillet ever blocking a human interactively (D6).
   - Northstar: loop integrity (gates advise by default, enforce only on opt-in).
   - Success metrics:
     - `next --strict` exits `5` on an uncleared invariant and `0` otherwise.
     - An uncleared scorer↔judge contradiction on affected evals blocks under `--strict`.
   - Dependencies: `next` (F38).
   - Confidence: Medium — design §6.1 `next`, §8.

4. **[F40]** Codify scaffolding (CLI: `skillet eval new`, `--from-friction <id>`) — PLANNED · Net-new
   - Purpose & user value: Turn a corroborated finding into a behavioral eval that
     cites the suspected `SKILL.md` clause and links the evidence — the *Codify*
     step, reached only after error analysis says it's worth it.
   - Northstar: loop integrity (codify what you discovered).
   - Success metrics:
     - `eval new <skill> --from-friction <id>` scaffolds assertions citing the clause, links the evidence, and sets state `candidate → codified` on save.
     - The new eval is confirmed to *fail today* before any fix is drafted.
   - Dependencies: evidence (Phase 3), gates engine (F37), boundary codecs (Phase 1).
   - Confidence: Medium — design §6.2 `eval new`, §7.3.

## Dependencies & Sequencing

- Local ordering: gates engine (F37) → `next` (F38) → `--strict` (F39); `eval new`
  (F40) is the action `next` proposes once a codify gate clears.
- Cross-phase: consumes Phase 3 evidence and Phase 4 findings/contradictions;
  `eval new` outputs the failing eval that Phase 6's `suggest`/`iterate` prove against.

## Phase Metrics & Success Criteria

- This phase is successful when: a maintainer runs `skillet next` and trusts it —
  every recommendation names the gate it cleared (or the gap it's missing) and
  ships a command — and most evidence is correctly routed *away* from prose edits.

## Risks & Assumptions

- Net-new and load-bearing; correctness rests on exhaustive unit/property tests of
  the pure gates function (design §8, §11 EDDCore).

## Phase Change Log

- 2026-06-17: Phase created. Sequenced after Error Analysis (Phase 4) so
  codification follows discovered failures, per the error-analysis-first ordering.
- 2026-06-26: PATCH — adopted the global stable Fn ids (F37–F40; roadmap v1.8.0 scheme reconciliation). Mechanical renumber; no scope change.
