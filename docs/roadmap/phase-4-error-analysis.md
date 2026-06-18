# Phase 4 — Error Analysis (Northstar gap #1)

**Status:** PLANNED
**Horizon:** Next
**Last Updated:** 2026-06-17

## Goal

Mine the captured corpus into a routed failure taxonomy — *what is actually going
wrong, and how often* — surfacing calibration alarms first. This is the
Northstar's #1 value gap and, per the error-analysis-first principle, it comes
*before* codifying evals or editing the skill: you analyze real failures, then
decide what's worth a test. This phase is sequenced ahead of the harness matrix
(Phase 7) precisely because it is a value gap, not a differentiator.

## Key Features

1. Corpus triage — Track A (CLI: `skillet triage`) — PLANNED · Ported
   - Purpose & user value: Run deterministic scorers across every bundle and
     cluster the signal into a failure taxonomy — error analysis, not a pass-rate
     — so the maintainer sees the patterns that actually recur.
   - Northstar: gap #1 made executable (the headline activity).
   - Success metrics:
     - `triage` clusters scorer output across the corpus into named findings, each routed to its cheapest lever with the "hypothesis, not verdict" caveat.
     - Findings auto-link to friction events that share sessions.
     - Output ends by pointing at `skillet next`.
   - Dependencies: scorers (Phase 2), corpus (Phase 3).
   - Confidence: Medium — design §6.1 `triage` (Track A).

2. Scorer↔judge contradiction detection (surfaces in `triage`/`report`, gated in `next --strict`) — PLANNED · Net-new
   - Purpose & user value: When a deterministic scorer and the judge disagree on
     the same expectation, that calibration alarm outranks the pass rate — it
     silently inflates or deflates every number. Surfaced first, above the taxonomy.
   - Northstar: calibration safety (the gate the whole pass-rate trust is conditioned on).
   - Success metrics:
     - Contradictions print first in `triage`/`report` with a count and a "triage before trusting the verdict" banner.
     - A pure join over verdicts + SARIF for the same expectation (unit-tested, no model).
   - Dependencies: scorers + verdicts (Phase 2).
   - Confidence: Medium — design §8, §6.1 `triage`.

3. Baseline drift between captures (CLI: `skillet baseline compare`) — PLANNED · Ported
   - Purpose & user value: For skills that *emit* findings, diff two captures —
     resolution-to-discovery ratio, severity drift, rule-ID entropy — emitted
     un-gated so the audit surfaces qualitative shifts instead of calcifying.
   - Northstar: gap #1 (drift is the producer-skill error-analysis channel).
   - Success metrics:
     - `baseline compare --from <s> --to <s>` reports the three order parameters as a clear diff.
     - Emitted un-gated (no `--fail-on-drift` threshold).
   - Dependencies: SARIF reader (Phase 2), corpus (Phase 3).
   - Confidence: Medium — design §6.2, §8.

4. Cross-corpus drift matrix (CLI: `skillet baseline matrix`) — PLANNED · Ported
   - Purpose & user value: Surface per-rule trajectories across packages —
     *generalizing rules* (firing in ≥3 packages) and *stuck rules* (zero variance
     across ≥3) — as producer-skill friction candidates.
   - Northstar: gap #1 (pattern discovery at corpus scale).
   - Success metrics:
     - `baseline matrix <skill>` classifies rules as generalizing/stuck with the package evidence behind each.
   - Dependencies: baseline compare (F3).
   - Confidence: Medium — design §6.2, §8.

## Dependencies & Sequencing

- Local ordering: triage (F1) and contradiction detection (F2) first (consumer-skill
  error analysis); baseline compare (F3) → matrix (F4) (producer-skill error analysis).
- Cross-phase: findings here become evidence the Phase 5 gates engine consumes;
  contradictions condition the Phase 5 proof gate and Phase 6 `iterate` verdicts.

## Phase Metrics & Success Criteria

- This phase is successful when: a maintainer can point `triage` at a real corpus
  and get a ranked, lever-routed failure taxonomy with calibration alarms first —
  and can decide what's worth codifying *from observed failures*, not imagined ones.

## Risks & Assumptions

- Track A only here; the paid Track B axial coding of corrective turns is Phase 8.
- Lever routing is a hypothesis; the gates engine (Phase 5), not triage, decides
  what clears.

## Phase Change Log

- 2026-06-17: Phase created and spotlighted as its own phase (Northstar gap #1),
  sequenced before codification per the error-analysis-first cross-reference.
