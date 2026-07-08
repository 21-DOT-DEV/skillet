# Phase 5 — The Computable Runbook (differentiator #1)

**Status:** PLANNED
**Horizon:** Next
**Last Updated:** 2026-07-07

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

5. **[F63]** Trigger-corpus paraphrase expansion (CLI: `skillet eval new --expand <seed>`, name provisional) — PLANNED · Net-new
   - Purpose & user value: Grow the trigger axis's query corpus from *observed*
     seeds — paraphrase variants and near-misses of real trigger phrasings (from
     captured sessions, friction, or existing trigger evals) — because activation
     is wording-sensitive and thin coverage bites hardest there. Every generated
     case records its seed, carries a `synthetic` provenance marker, and passes a
     deterministic validator before entering the corpus (rejects reported, never
     silently dropped).
   - Northstar: loop integrity — coverage where the description axis needs volume,
     without breaking codify-what-you-discover: seeds are always observed reality.
   - Success metrics:
     - Expansion refuses to run without a real seed; each generated case records seed + `synthetic` provenance and passes the validator.
     - Generated near-misses land as `should_trigger:false` cases with routing expectations.
   - Dependencies: trigger axis (F14, Phase 2), evidence formats (Phase 3), codify scaffolding (F40).
   - Confidence: Medium — design §14-15 (decided 2026-07-06); precedent: Apple `SampleGenerator` (validator-gated), the retired Python harness's paraphrase technique.
   - Notes: First slice of the general generator (F64, Phase 8); proof standing of synthetic cases is §14-16 / F45.
   - Diagnostic-tier lane (F67, design §9.6): on macOS the unconfigured model slot defaults to
     Apple's on-device model — $0, offline, announced in the plan, validator-gated (§14-20); on
     Linux the slot stays unset until configured.

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
- 2026-07-06: MINOR — added **F63** (trigger-corpus paraphrase expansion; first slice of design
  §14-15's observed-seed synthetic generation, Apple Evaluations cross-reference).
  Roadmap → v1.13.0.
- 2026-07-07: PATCH — F63 gains the diagnostic-tier lane note (F67/§14-20: macOS defaults to the
  on-device model, announced + validator-gated). Roadmap → v1.14.0.
