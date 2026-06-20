# Phase 2 — Trustworthy Measurement & Static Gates

**Status:** PLANNED
**Horizon:** Next
**Last Updated:** 2026-06-17

## Goal

Turn the thin runner into measurement you can trust *deltas* on, and complete the
free static gate. This adds the second eval axis, the A/B baseline, a grounded
judge for file-outcome criteria, deterministic scorers, flaky hygiene,
record/replay, the full lint catalog, and human + HTML reporting — everything
that makes a `pass^k` number believable before the workflow layer starts acting
on it.

## Key Features

1. Trigger axis (CLI: `skillet run --axis trigger`) — PLANNED · Net-new
   - Purpose & user value: Test whether a skill's *description* actually fires it
     — the question behavioral evals can't answer — retiring the separate Python
     trigger harness into one binary, two axes.
   - Northstar: loop integrity (closes the "did it even trigger?" half of quality).
   - Success metrics:
     - Each `trigger-eval.json` query is judged fired/not-fired deterministically from `skillInvocations`; `should_trigger:false` near-misses verify correct *non*-firing.
     - Reported separately from the behavioral axis in the run table.
   - Dependencies: Trace seam, runner (Phase 1).
   - Confidence: Medium — design §6.1 `run`, §9.3.

2. A/B baseline arm (CLI: `skillet run --ab`) — PLANNED · Ported
   - Purpose & user value: Run with-skill and without-skill arms and report Δ —
     "is the skill earning its tokens?" — matching `agent-skills-eval` on day one.
   - Northstar: loop integrity (value attribution).
   - Success metrics:
     - `--ab` adds a provably skill-free baseline arm and prints per-eval Δ.
     - On a harness that cannot isolate ambient skills, `--ab` is refused with an explanation rather than producing a polluted baseline.
   - Dependencies: runner (Phase 1).
   - Confidence: Medium — design §6.1 `run`, §9.2.

3. Grounded judge — file-outcome grading (CLI: `--judge <grounded-id>`) — PLANNED · Net-new
   - Purpose & user value: Most skill criteria assert *file* outcomes ("wrote
     SARIF to X", "scaffolded the catalog"); a grounded judge reads the post-run
     sandbox instead of grading from prose, killing the "surface compliance"
     failure for file-writing skills.
   - Northstar: loop integrity (correct grading is the foundation of every delta).
   - Success metrics:
     - A criterion asserting a written file passes only when the file exists with expected contents in the sandbox (planted pass/fail fixtures).
     - Every verdict records `judge_id`, `model`, `judge_prompt_version`.
   - Dependencies: text judge (Phase 1), Workspace sandbox (Phase 1).
   - Confidence: Medium — design §9.4.

4. Deterministic scorers → SARIF (CLI: `skillet score`) — PLANNED · Ported
   - Purpose & user value: Free, model-free checks over outputs/bundles emitting
     standard SARIF 2.1.0 — the deterministic-first signal that feeds triage and
     editors/CI.
   - Northstar: deterministic-first; gap #1 input.
   - Success metrics:
     - `score <bundle>` emits valid SARIF 2.1.0 on stdout (schema-validated).
     - Runs with no model and no network.
   - Dependencies: Trace/bundle model.
   - Confidence: Medium — design §6.2, §11 (ScoreKit).

5. Flaky-eval hygiene, watchdog & infra-only retry — PLANNED · Net-new
   - Purpose & user value: Make reliability honest — flag flaky evals as hygiene
     items before any delta is trusted, retry only infrastructure failures (never
     judged FAILs), and bound every trial with a watchdog so a hung harness can't
     hole a run.
   - Northstar: loop integrity (deltas on a flaky suite are noise).
   - Success metrics:
     - An eval with `0 < passes < observed k` is reported FLAKY and excluded from trusted deltas.
     - A no-terminal-event failure is retried up to `infra_retries`; a judged FAIL is never retried (both stamped in trial metadata).
     - A per-trial timeout escalates SIGTERM → 10s grace → SIGKILL, destroying the workspace either way.
   - Dependencies: runner (Phase 1).
   - Confidence: Medium — design §8, §10.

6. Record / replay (CLI: `skillet run --record <dir>` / `--replay <dir>`) — PLANNED · Net-new
   - Purpose & user value: Persist every raw trace and verdict and serve them
     back — free deterministic tests, reproducible bug reports, and re-grading old
     runs without re-execution.
   - Northstar: loop integrity (reproducibility); enables criteria-drift re-grade (F12).
   - Success metrics:
     - A `--record`ed run replays identically through the replay adapter + replay judge with no harness or network.
   - Dependencies: runner, judge.
   - Confidence: Medium — design §10.

7. Full lint catalog + SARIF (CLI: `skillet lint --format sarif`) — PLANNED · Ported
   - Purpose & user value: Complete the shipped 5-rule `SKILL-Lxxx` catalog and
     emit SARIF for editors/CI — the free pre-API gate in full.
   - Northstar: deterministic-first; cheapest lever.
   - Success metrics:
     - All five shipped rules (`L001`, `L003`, `L009`, `L010`, `L011`) fire on fixtures with correct tiers.
     - `--format sarif` emits valid 2.1.0; `skillet lint && skillet fixtures verify` is a clean pre-commit pair.
   - Dependencies: lint core (Phase 1).
   - Confidence: Medium — design §6.1 `lint`.

8. Paid preflight canary (CLI: `skillet doctor --paid`) — PLANNED · Net-new
   - Purpose & user value: One trivial paid trial per harness that proves a known
     `references/` file is readable from inside the harness — the last $1 check
     before a real paid run.
   - Northstar: loop integrity + spend honesty.
   - Success metrics:
     - `doctor --paid` asserts reference readability per harness and reports cost.
   - Dependencies: `doctor` (Phase 1), adapter.
   - Confidence: Medium — design §6.1 `doctor`.

9. Fixture-integrity guard (CLI: `skillet fixtures verify`, `skillet hooks install`) — PLANNED · Ported
   - Purpose & user value: For SARIF-emitting skills, assert producer-output recall
     (`expected ⊆ actual` + `allowedExtraRuleIds`) and block commits that mutate
     fixtures — because a polluted fixture silently invalidates every later A/B.
   - Northstar: loop integrity (A/B integrity, design §9.2).
   - Success metrics:
     - `fixtures verify` fails when an expected finding is missing or an un-allowed `ruleId` appears.
     - `hooks install` refuses a commit touching `evaluations/fixtures/**` (bypass: `--no-verify`).
   - Dependencies: scorers (F4).
   - Confidence: Medium — design §6.2.

10. Reporting — TTY & HTML (CLI: `skillet report`, `--html`) — PLANNED · Ported
    - Purpose & user value: Render results for humans — cross-run trends, the
      flaky list, the per-harness matrix — and the interactive HTML viewer from
      the frozen `benchmark.json`, all re-aggregated offline.
    - Northstar: loop integrity (make results legible).
    - Success metrics:
      - `report` summarizes runs in TTY and `--html` renders from `benchmark.json` with no harness in the loop.
      - Re-aggregation matches the live run's numbers exactly.
    - Dependencies: boundary codecs (Phase 1), runs.
    - Confidence: Medium — design §6.1 `report`.

11. Configuration & CLI ergonomics (CLI: `skillet config get|set|list --origins`, `skillet completions`) — PLANNED · Net-new
    - Purpose & user value: Make the precedence chain inspectable and the CLI
      pleasant — see where every effective value came from, and get shell
      completions.
    - Northstar: loop integrity (transparency, clig.dev conformance).
    - Success metrics:
      - `config list --origins` shows the winning source for every effective value.
      - `completions {bash,zsh,fish}` emit working completion scripts.
    - Dependencies: config substrate (Phase 1).
    - Confidence: Medium — design §5.2, §6.2.

12. Offline re-grade & judge-prompt versioning (CLI: `skillet grade --run <ts>`) — PLANNED · Net-new
    - Purpose & user value: Manage *criteria drift* — re-grade a recorded run under
      a new judge model or prompt version without re-executing tasks, so results
      stay comparable as the rubric evolves.
    - Northstar: calibration safety (directly addresses the criteria-drift risk).
    - Success metrics:
      - `grade --run <ts> --judge <id>` re-grades from recorded traces with no harness; verdicts carry the new `judge_prompt_version`.
      - Old and new verdicts are diffable for the same run.
    - Dependencies: record/replay (F6), judge.
    - Confidence: Medium — design §6.2, §9.4.

## Dependencies & Sequencing

- Local ordering: the grounded judge (F3) and scorers (F4) precede flaky/hygiene
  reporting (F5) and reporting (F10). Record/replay (F6) precedes offline re-grade
  (F12).
- Cross-phase: scorers (F4) feed Phase 4 (Error Analysis); the grounded judge (F3)
  is reused by `iterate` in Phase 6.

## Phase Metrics & Success Criteria

- This phase is successful when: a maintainer can trust a `pass^k` delta — flaky
  evals are surfaced first, file-outcomes are graded against the real sandbox,
  both axes and the A/B arm report cleanly, and any run can be replayed and
  re-graded offline.

## Risks & Assumptions

- The grounded judge is net-new surface; its calibration is validated only by the
  scorer↔judge contradiction gate until a human-label set exists (Phase 8).

## Phase Change Log

- 2026-06-17: Phase created. Holds the runner-hardening + full static-gate work
  split out of the thin "Now" walking skeleton.
