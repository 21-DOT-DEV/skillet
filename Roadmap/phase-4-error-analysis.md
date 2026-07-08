# Phase 4 — Error Analysis (Northstar gap #1)

**Status:** PLANNED
**Horizon:** Next
**Last Updated:** 2026-07-07

## Goal

Mine the captured corpus into a routed failure taxonomy — *what is actually going
wrong, and how often* — surfacing calibration alarms first. This is the
Northstar's #1 value gap and, per the error-analysis-first principle, it comes
*before* codifying evals or editing the skill: you analyze real failures, then
decide what's worth a test. This phase is sequenced ahead of the harness matrix
(Phase 7) precisely because it is a value gap, not a differentiator.

## Key Features

1. **[F33]** Corpus triage — Track A (CLI: `skillet triage`) — PLANNED · Ported
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

2. **[F34]** Scorer↔judge contradiction detection (surfaces in `triage`/`report`, gated in `next --strict`) — PLANNED · Net-new
   - Purpose & user value: When a deterministic scorer and the judge disagree on
     the same expectation, that calibration alarm outranks the pass rate — it
     silently inflates or deflates every number. Surfaced first, above the taxonomy.
   - Northstar: calibration safety (the gate the whole pass-rate trust is conditioned on).
   - Success metrics:
     - Contradictions print first in `triage`/`report` with a count and a "triage before trusting the verdict" banner.
     - A pure join over verdicts + SARIF for the same expectation (unit-tested, no model).
   - Dependencies: scorers + verdicts (Phase 2).
   - Confidence: Medium — design §8, §6.1 `triage`.

3. **[F35]** Baseline drift between captures (CLI: `skillet baseline compare`) — PLANNED · Ported
   - Purpose & user value: For skills that *emit* findings, diff two captures —
     resolution-to-discovery ratio, severity drift, rule-ID entropy — emitted
     un-gated so the audit surfaces qualitative shifts instead of calcifying.
   - Northstar: gap #1 (drift is the producer-skill error-analysis channel).
   - Success metrics:
     - `baseline compare --from <s> --to <s>` reports the three order parameters as a clear diff.
     - Emitted un-gated (no `--fail-on-drift` threshold).
   - Dependencies: SARIF reader (Phase 2), corpus (Phase 3).
   - Confidence: Medium — design §6.2, §8.

4. **[F36]** Cross-corpus drift matrix (CLI: `skillet baseline matrix`) — PLANNED · Ported
   - Purpose & user value: Surface per-rule trajectories across packages —
     *generalizing rules* (firing in ≥3 packages) and *stuck rules* (zero variance
     across ≥3) — as producer-skill friction candidates.
   - Northstar: gap #1 (pattern discovery at corpus scale).
   - Success metrics:
     - `baseline matrix <skill>` classifies rules as generalizing/stuck with the package evidence behind each.
   - Dependencies: baseline compare (F35).
   - Confidence: Medium — design §6.2, §8.

5. **[F62]** Scored diagnostic dimensions (judge; surfaces in `triage`/`report`) — PLANNED · Net-new
   - Purpose & user value: A rubric criterion may declare named quality dimensions
     with anchored numeric scales (every score value carries a written description);
     the judge returns per-dimension score + rationale *alongside* the binary
     verdict. Scores never gate — they make failure analysis denser: rationales and
     low dimensions point triage at *what* to fix, not just that something failed.
   - Northstar: gap #1 (diagnosis density per failure).
   - Success metrics:
     - A criterion with dimensions yields per-dimension scores + rationales in run records and `triage`/`report`; verdicts, gates, and pass^k are provably unchanged by any score.
     - Anchored scales are required (no bare 1–5); an all-samples-same-score dimension is surfaced with a "split this dimension" hint (Apple's guidance).
   - Dependencies: judge (Phase 2), triage (F33).
   - Confidence: Medium — design §14-13 (decided 2026-07-06, diagnostics-only; the binary-preferred counter-guidance is recorded in Appendix D).
   - Diagnostic-tier lane (F67, design §9.6): Apple's Private Cloud Compute model is the candidate
     scoring judge — explicit opt-in, never a default, and only after the F10 agreement check
     clears κ ≥ 0.6 (§14-20).

## Dependencies & Sequencing

- Local ordering: triage (F33) and contradiction detection (F34) first (consumer-skill
  error analysis); baseline compare (F35) → matrix (F36) (producer-skill error analysis).
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
- 2026-06-26: PATCH — adopted the global stable Fn ids (F33–F36; roadmap v1.8.0 scheme reconciliation). Mechanical renumber; no scope change.
- 2026-07-06: MINOR — added **F62** (scored diagnostic dimensions, design §14-13 via the Apple
  Evaluations cross-reference; diagnostics-only — binary verdicts remain the sole gate).
  Roadmap → v1.13.0.
- 2026-07-07: PATCH — F62 gains the diagnostic-tier lane note (F67/§14-20: PCC scoring judge,
  opt-in behind F10 calibration). Roadmap → v1.14.0.
