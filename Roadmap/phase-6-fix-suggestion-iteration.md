# Phase 6 — Fix Suggestion & Safe Iteration (Northstar gap #2)

**Status:** IN PROGRESS
**Horizon:** Next
**Last Updated:** 2026-08-16

## Goal

Close the loop: draft minimal, surgical `SKILL.md` edits from *observed* evidence,
prove them by A/B in a throwaway worktree, and let a human land them — skillet
never commits. This is the Northstar's #2 value gap (AI-assisted fix suggestion)
and the *Suggest → Apply → Re-measure* arc. Drafting is constrained to discovered
failures, never imagined ones.

## Key Features

1. **[F41]** Draft edit proposals (CLI: `skillet suggest`) — IMPLEMENTED (2026-08-01) · Ported
   - Purpose & user value: From the failure taxonomy, the cited `SKILL.md`
     passages, and corrective-turn excerpts, the judge drafts *minimal surgical*
     content-anchored `EditProposal`s — generalize from feedback, prefer deleting
     dead prose and extracting to `references/`, explain the why. Nothing is
     applied.
   - Northstar: gap #2 made executable.
   - Success metrics:
     - `suggest <skill> --from <evidence-id>` emits `EditProposal`s (`current_excerpt` → `proposed_text`, `rationale`, `addresses`) to `.skillet/proposals/`.
     - Proposals draft only against observed evidence; each records its `motivation` evidence ids.
   - Dependencies: findings (Phase 4), evidence (Phase 3), judge (Phase 2).
   - Confidence: Medium — design §6.1 `suggest`, §7.3.

2. **[F42]** Safe apply to the working tree (CLI: `skillet suggest --proposals <name>.json --apply [--edits <n>...]`) — SHIPPED 2026-08-04 · Net-new
   - Purpose & user value: Materialize a reviewed proposal into your working tree
     via content-anchored application (exact-once match, refuse-on-ambiguity,
     fail-loud on drift) — refusing a dirty tree and stopping short of the commit.
     The deliberate, safer P5 amendment.
   - Northstar: gap #2 (automates the apply step the human used to do by hand).
   - Success metrics:
     - `suggest --apply` writes the draft's edits to the working tree (`--edits <n>...` narrows it), refuses a dirty tree, and never commits.
     - An anchor that matches zero or >1 times aborts loudly with a remedy.
   - Dependencies: proposals (F41), content-anchored `EditApply` engine.
   - Confidence: Medium — design §6.1 `suggest`, §7.3.

3. **[F43]** Prove a proposal by A/B (CLI: `skillet iterate <skill> --proposals <name>.json [--edits <n>...]`) — SHIPPED 2026-08-19 · Ported
   - Purpose & user value: Apply a proposal subset into a *throwaway git worktree*
     (the live skill untouched), run the pinned suite at k, and print the per-eval
     `pass^k` delta against the baseline — proving the fix before any human lands
     it.
   - Northstar: gap #2 (the "prove it" half) + loop integrity.
   - Success metrics:
     - `iterate` reports before/after `pass^k` at observed k with no regressions to call a proposal proven.
     - Any regression discards the worktree and exits `1`, emitting nothing unless `--keep-worktree`.
   - Dependencies: runner (Phase 1), proposals (F41), worktree lifecycle.
   - Confidence: Medium — design §6.1 `iterate`, §10.
   - **Revised and shipped (2026-08-19):** the command line and the source of the "before" number
     changed — `--edits` replaces `--apply <indices>`, and both measurements are taken in the same
     invocation rather than one being read from a recorded run. Both were approved as design §14
     items 22 and 23 and applied; see [Specs/020](../Specs/020-prove-by-ab/plan.md) D6 and D2.

4. **[F44]** Mark evidence proven (CLI: `skillet iterate --mark`) — PLANNED · Net-new
   - Purpose & user value: On a clean, regression-free A/B, advance the linked
     friction event to `proven` — an explicit, auditable state write, provisional
     until judge calibration clears.
   - Northstar: loop integrity (closes the evidence lifecycle honestly).
   - Success metrics:
     - `iterate --mark` sets `proven` only with zero pass^k regression *and* no unresolved contradiction on the affected evals.
   - Dependencies: iterate (F43), evidence lifecycle (Phase 3), contradiction join (Phase 4).
   - Confidence: Medium — design §6.1 `iterate`, §8.

5. **[F45]** Held-out proof discipline (gate: `gates.proof.require_holdout`) — PLANNED · Net-new
   - Purpose & user value: Close the *circular-proof* gap — a `skill_md` edit is `proven`
     only when a **held-out sibling eval** (same failure class, *not* the one the edit was
     drafted from) also passes, so a proof reflects a fix that generalizes rather than an
     overfit to its own eval. When the failure class has no sibling, `next` advises authoring
     one; the proof is recorded `single-eval` until then.
   - Northstar: loop integrity; hardens the *corroboration integrity* outcome.
   - Success metrics:
     - `iterate --mark proven` on a `skill_md` lever requires a held-out sibling eval to pass; with none, it records `single-eval, un-corroborated` and `next` surfaces the gap.
     - Under `--strict`, a missing held-out blocks promotion (exit `5`); advisory otherwise (D6).
   - Dependencies: iterate (F43), the Proof gate + evidence `root_cause`/`cluster` keys (design §8, §7.3).
   - Confidence: Medium — design §8 (Held-out proof), §5.2 `gates.proof`, §6.1 `iterate`; adopted from §14-8.
   - Notes (2026-07-06): a **synthetic sibling** — generated under F63/F64 from a seed in the
     same failure class — is proof-eligible; such marks are recorded `synthetic-backed`
     (visible in `next`/`report`). Evidence-side gates remain observed-only. Design §14-16.

## Dependencies & Sequencing

- Local ordering: `suggest` (F41) → `iterate` proves (F43) → `--mark` (F44); safe
  apply (F42) is the human's landing step after a proven A/B.
- Cross-phase: depends on Phase 5 (`eval new` produced the failing eval and the
  proposal's motivation), Phase 4 (the contradiction gate), and Phase 1 (the runner
  `iterate` re-measures through).

## Phase Metrics & Success Criteria

- This phase is successful when: a maintainer goes from a corroborated finding to a
  drafted, A/B-proven, regression-free proposal — and lands it with a single
  explicit `--apply` while skillet never touches the commit.

## Risks & Assumptions

- The `suggest`/`iterate` engines and content-anchored apply are ported; the
  `--apply` convention is the net-new P5 amendment.
- Suggestion quality depends on the judge; calibration is bounded by the
  contradiction gate until a human-label set exists (Phase 8).

## Phase Change Log

- 2026-06-17: Phase created and spotlighted as its own phase (Northstar gap #2),
  sequenced ahead of the harness matrix within Next.
- 2026-06-24: Added F5 [now F45] (held-out proof discipline), adopting design §14-8 (R2) from the v0.8
  competitive cross-reference; graduated from ROADMAP *Candidate Enhancements*. Roadmap MINOR → v1.6.0.
- 2026-06-26: PATCH — adopted the global stable Fn ids (F41–F45; roadmap v1.8.0 scheme reconciliation). Mechanical renumber; no scope change.
- 2026-07-06: PATCH — F45 gains the `synthetic-backed` held-out note (design §14-16, decided:
  synthetic siblings are proof-eligible within their seed's failure class; evidence-side gates
  stay observed-only). Roadmap → v1.13.0.
