# Phase 2 — Trustworthy Measurement & Static Gates

**Status:** IN PROGRESS (F3 + F14 shipped 2026-07-04; F15 shipped 2026-07-07; F16 shipped 2026-07-08)
**Horizon:** Now
**Last Updated:** 2026-07-08

## Goal

Turn the thin runner into measurement you can trust *deltas* on, add the `doctor`
preflight gate, and complete the free static gate. This adds the second eval axis,
the A/B baseline, a grounded judge for file-outcome criteria, deterministic
scorers, flaky hygiene, record/replay, the `$0` `doctor` preflight, the full lint
catalog, and human + HTML reporting — everything that makes a `pass^k` number
believable before the workflow layer starts acting on it.

## Key Features

1. **[F3]** $0 preflight & skill-visibility check (CLI: `skillet doctor`) — IMPLEMENTED (2026-07-04) · Net-new
   - Purpose & user value: A free, fast self-check that catches the silent killers
     before any paid run — config parses, each configured harness is found and the
     right binary/version resolves, and the skill is actually *visible* to the
     harness. Kills the `--skill-path` false-negative class by construction (P6).
   - Northstar: loop integrity (errors teach; never pay to discover a misconfig).
   - Success metrics:
     - `doctor` reports config origin (which file loaded), harness version/resolution, and per-skill visibility, exiting `3` with a remedy line on any failure.
     - Verifies the positive-load condition (target `SKILL.md` **+ `references/`** resolve under the injection strategy); error-tier `lint` findings surface here and also fail (exit `3`), warnings shown but non-failing.
   - Dependencies: HarnessAdapter seam (F5), claude-code adapter (F6); also `swift-yaml` (config parsing) and error-tier `lint` (F4, surfaced here) — all Phase 1.
   - Confidence: Medium — design §6.1 `doctor`, §9.2.
   - Notes: Moved from Phase 1 — off the walking-skeleton critical path (`run`/F7 doesn't depend on it) and its companions live here. Live auth + the discovery-only visibility half are validated with the runner (F7); the `--paid` canary is F21; the frontmatter spec-conformance rules it surfaces come from the full lint catalog (F20).
   - Shipped (2026-07-04, [Specs/008](../Specs/008-doctor-preflight/plan.md)): both success metrics, under the Option-2 contract — frozen `skillet.doctor/1` check rows (`--json`, golden-tested), warnings-never-fail exits (`0` healthy / `3` any failure + remedy), config file-origin, harness binary/version/denylist + winning resolution link, positive-load visibility via the staging-parity `SkillBundleAudit` (dropped symlinks fail loudly, by path), all error-tier lint findings failing at exit 3; auth = warning row (`run`'s strict preflight owns the refusal). Suite green — two post-review hardening rounds; see the [Specs/008](../Specs/008-doctor-preflight/plan.md) status row.

2. **[F14]** Trigger axis (CLI: `skillet run --axis trigger`) — IMPLEMENTED (2026-07-04) · Net-new
   - Purpose & user value: Test whether a skill's *description* actually fires it
     — the question behavioral evals can't answer — retiring the separate Python
     trigger harness into one binary, two axes.
   - Northstar: loop integrity (closes the "did it even trigger?" half of quality).
   - Success metrics:
     - Each `trigger-eval.json` query is judged fired/not-fired deterministically from `skillInvocations`; `should_trigger:false` near-misses verify correct *non*-firing.
     - Reported separately from the behavioral axis in the run table.
   - Dependencies: Trace seam, runner (Phase 1).
   - Confidence: Medium — design §6.1 `run`, §9.3.
   - Shipped (2026-07-04, [Specs/009](../Specs/009-trigger-axis/plan.md)): both success metrics, via
     `--axis behavior|trigger|all` (default: each axis where its file exists) — deterministic
     fired/not-fired from `skillInvocations` over whole-corpus frontmatter stubs (the §9.2 `visible:`
     tier, now live), near-misses verified with routing forensics, separate axis reporting, and
     per-axis `benchmark.json` merge (`configuration:"trigger"` + axis-marked consistency; offline
     recompute covers both axes). Suite green — see the Specs/009 status row.
   - Diagnostic-tier smoke arm planned (F67/F68, design §9.6): a $0 on-device pre-screen lane for
     trigger evals — the lane stays an explicit flag, its provider defaults on macOS, and smoke
     results never merge with real-harness results.

3. **[F15]** A/B baseline arm (CLI: `skillet run --ab`) — IMPLEMENTED (2026-07-07) · Ported
   - Purpose & user value: Run with-skill and without-skill arms and report Δ —
     "is the skill earning its tokens?" — matching `agent-skills-eval` on day one.
   - Northstar: loop integrity (value attribution).
   - Success metrics:
     - `--ab` adds a provably skill-free baseline arm and prints per-eval Δ.
     - On a harness that cannot isolate ambient skills, `--ab` is refused with an explanation rather than producing a polluted baseline.
   - Dependencies: runner (Phase 1).
   - Confidence: Medium — design §6.1 `run`, §9.2.
   - Shipped (2026-07-07, [Specs/010](../Specs/010-ab-baseline/plan.md)): both success metrics —
     isolation is prevent + verify + preflight (session-level `--disable-slash-commands`; a $0
     `--help` preflight refuses unsupported binaries at exit 3; a per-trial trace tripwire
     reclassifies any skill-fire as `polluted`, never graded); reporting is paired (per-eval Δ,
     mean ± SE or an honest "too few", flips, time Δ) in the table, `skillet.run/1` (`ab` block),
     and `benchmark.json` (canonical `with_skill`/`without_skill` rows + per-arm stats + signed
     delta; offline recompute rebuilds the block). Behavioral-only: trigger-only + `--ab` refuses
     (exit 2); mixed runs note the single-arm trigger. Suite green — see the Specs/010 status row.

4. **[F16]** Grounded judge — file-outcome grading (CLI: `--judge grounded-judge`) — IMPLEMENTED (2026-07-08) · Net-new
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
   - Shipped (2026-07-08, [Specs/011](../Specs/011-grounded-judge/plan.md)): both success metrics —
     `--judge grounded-judge` reads the **produced/changed set** (before/after snapshot diff,
     symlink-confined, cut/binary/deleted disclosed, 32 KiB/file · 128 KiB total), grades strictly
     to the criterion, and stamps `judge_id`/`model`/`judge_prompt_version` per verdict **and**
     additively into the committed `judge` block (so grounded vs text survive a cache wipe). Selected
     explicitly (default `text-judge`); auto-routing staged (design §14-21); a P9 cost note prints.
     Suite green — see the Specs/011 status row.

5. **[F17]** Deterministic scorers → SARIF (CLI: `skillet score <path>`) — IMPLEMENTED
   - Purpose & user value: Free, model-free checks over produced text emitting
     standard SARIF 2.1.0 — the deterministic-first signal that feeds triage and
     editors/CI. A reporter, not a gate (exit 0 even with findings).
   - Northstar: deterministic-first; gap #1 input.
   - Success metrics:
     - `score <path>` emits valid SARIF 2.1.0 on stdout (`--format sarif`; structural
       goldens). *(`<path>` input ships now; the saved-run `<bundle>` mode arrives with
       capture, Phase 3.)*
     - Runs with no model and no network.
   - Checks: `SKILL-S001`–`S005` (slop-vocabulary, puffery, em-dash, rule-of-three,
     knowledge-cutoff), `S006` not-x-but-y (experimental, default-off), `S007`
     sarif-validity, `S000` file-unreadable. Also `--format tty|json`.
   - Dependencies: ProjectKit `SafeFile`; EDDCore `SarifDocument`/`ScoreReport`.
   - Known limitation: reads repo `skillet.yaml` + built-in defaults only; the
     user/`$XDG_CONFIG_HOME` config layer for `scorers` is deferred to **F24** (config
     precedence), a known gap vs. design §5.2.
   - Confidence: High — shipped; Specs/012-deterministic-scorers/plan.md, design §6.2, §11 (ScoreKit).

6. **[F18]** Flaky-eval hygiene, watchdog & infra-only retry — PLANNED · Net-new
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

7. **[F19]** Record / replay (CLI: `skillet run --record <dir>` / `--replay <dir>`) — PLANNED · Net-new
   - Purpose & user value: Persist every raw trace and verdict and serve them
     back — free deterministic tests, reproducible bug reports, and re-grading old
     runs without re-execution.
   - Northstar: loop integrity (reproducibility); enables criteria-drift re-grade (F25).
   - Success metrics:
     - A `--record`ed run replays identically through the replay adapter + replay judge with no harness or network.
   - Dependencies: runner, judge.
   - Confidence: Medium — design §10.

8. **[F20]** Full lint catalog + SARIF (CLI: `skillet lint --format sarif`) — PLANNED · Ported
   - Purpose & user value: Complete the shipped 5-rule `SKILL-Lxxx` catalog, add the
     frontmatter spec-conformance rules, and emit SARIF for editors/CI — the free
     pre-API gate in full.
   - Northstar: deterministic-first; cheapest lever.
   - Success metrics:
     - All five shipped rules (`L001`, `L003`, `L009`, `L010`, `L011`) fire on fixtures with correct tiers.
     - **Frontmatter spec-conformance** rules flag a non-kebab / over-long `name` (>64), disallowed top-level keys, and **duplicate keys** (raw-YAML anomaly detection) — re-homed here from `doctor` (F3), and surfacing in `doctor` because it shows error-tier lint.
     - `--format sarif` emits valid 2.1.0; `skillet lint && skillet fixtures verify` is a clean pre-commit pair.
   - Dependencies: lint core (Phase 1).
   - Confidence: Medium — design §6.1 `lint`, `doctor`.

9. **[F21]** Paid preflight canary (CLI: `skillet doctor --paid`) — PLANNED · Net-new
   - Purpose & user value: One trivial paid trial per harness that proves a known
     `references/` file is readable from inside the harness — the last $1 check
     before a real paid run.
   - Northstar: loop integrity + spend honesty.
   - Success metrics:
     - `doctor --paid` asserts reference readability per harness and reports cost.
   - Dependencies: `doctor` (F3), adapter.
   - Confidence: Medium — design §6.1 `doctor`.

10. **[F22]** Fixture-integrity guard (CLI: `skillet fixtures verify`, `skillet hooks install`) — PLANNED · Ported
    - Purpose & user value: For SARIF-emitting skills, assert producer-output recall
      (`expected ⊆ actual` + `allowedExtraRuleIds`) and block commits that mutate
      fixtures — because a polluted fixture silently invalidates every later A/B.
    - Northstar: loop integrity (A/B integrity, design §9.2).
    - Success metrics:
      - `fixtures verify` fails when an expected finding is missing or an un-allowed `ruleId` appears.
      - `hooks install` refuses a commit touching `evaluations/fixtures/**` (bypass: `--no-verify`).
    - Dependencies: scorers (F17).
    - Confidence: Medium — design §6.2.

11. **[F23]** Reporting — TTY & HTML (CLI: `skillet report`, `--html`) — PLANNED · Ported
    - Purpose & user value: Render results for humans — cross-run trends, the
      flaky list, the per-harness matrix — and the interactive HTML viewer from
      the frozen `benchmark.json`, all re-aggregated offline.
    - Northstar: loop integrity (make results legible).
    - Success metrics:
      - `report` summarizes runs in TTY and `--html` renders from `benchmark.json` with no harness in the loop.
      - Re-aggregation matches the live run's numbers exactly.
    - Dependencies: boundary codecs (Phase 1), runs.
    - Confidence: Medium — design §6.1 `report`.

12. **[F24]** Configuration & CLI ergonomics (CLI: `skillet config get|set|list --origins`, `skillet completions`) — PLANNED · Net-new
    - Purpose & user value: Make the precedence chain inspectable and the CLI
      pleasant — see where every effective value came from, and get shell
      completions.
    - Northstar: loop integrity (transparency, clig.dev conformance).
    - Success metrics:
      - `config list --origins` shows the winning source for every effective value.
      - `completions {bash,zsh,fish}` emit working completion scripts.
    - Dependencies: config substrate (Phase 1).
    - Confidence: Medium — design §5.2, §6.2.

13. **[F25]** Offline re-grade & judge-prompt versioning (CLI: `skillet grade --run <ts>`) — PLANNED · Net-new
    - Purpose & user value: Manage *criteria drift* — re-grade a recorded run under
      a new judge model or prompt version without re-executing tasks, so results
      stay comparable as the rubric evolves.
    - Northstar: calibration safety (directly addresses the criteria-drift risk).
    - Success metrics:
      - `grade --run <ts> --judge <id>` re-grades from recorded traces with no harness; verdicts carry the new `judge_prompt_version`.
      - Old and new verdicts are diffable for the same run.
    - Dependencies: record/replay (F19), judge.
    - Confidence: Medium — design §6.2, §9.4.

14. **[F61]** Deterministic process assertions over the trace (eval-declared; graded in `skillet run` before the judge) — PLANNED · Net-new
    - Purpose & user value: A free, judge-free assertion pass over the normalized
      `Trace` before any paid grading — required/forbidden tools, ordered and
      unordered groups, argument matchers (exact / key-present / substring /
      prefix-suffix / regex / numeric-range / one-of-set) — the trigger axis
      generalized: "did it fire" becomes "did it do it the right way," for $0.
    - Northstar: deterministic-first (free signal before the paid judge).
    - Success metrics:
      - An eval can declare a trajectory expectation; a violation names the exact step/matcher that failed, deterministically (no model, no network).
      - One pass emits both a strict all-pass verdict (the only result that gates or feeds pass^k) and a partial-credit percentage (diagnostic-only).
      - Apple's model-assisted semantic matcher is explicitly out (deferred, §14-9).
    - Dependencies: Trace (Phase 1), trigger axis (F14); the grammar joins the frozen eval contract when it ships.
    - Confidence: Medium — design §14-9 (decided 2026-07-06); precedent: Apple `TrajectoryExpectation`, LangChain `agentevals`, `skill-eval-harness` process assertions.
    - Notes: Graduated from ROADMAP Candidate Enhancements via the July-2026 Apple Evaluations cross-reference (design v0.36).

## Dependencies & Sequencing

- Local ordering: `doctor` (F3) is the $0 preflight gate; the grounded judge (F16)
  and scorers (F17) precede flaky/hygiene (F18) and reporting (F23). Record/replay
  (F19) precedes offline re-grade (F25). The paid canary (F21) follows `doctor` (F3).
- Cross-phase: scorers (F17) feed Phase 4 (Error Analysis); the grounded judge (F16)
  is reused by `iterate` in Phase 6. `doctor` (F3) depends only on shipped Phase 1
  seams (F4/F5/F6 + `swift-yaml`), so it is unblocked from the start of the phase.

## Phase Metrics & Success Criteria

- This phase is successful when: a maintainer can trust a `pass^k` delta — `doctor`
  catches misconfigs for $0 first, flaky evals are surfaced, file-outcomes are
  graded against the real sandbox, both axes and the A/B arm report cleanly, and
  any run can be replayed and re-graded offline.

## Risks & Assumptions

- The grounded judge is net-new surface; its calibration is validated only by the
  scorer↔judge contradiction gate until a human-label set exists (Phase 8).

## Phase Change Log

- 2026-07-09: **F17 IMPLEMENTED** — deterministic scorers → SARIF ([Specs/012](../Specs/012-deterministic-scorers/plan.md)):
  `skillet score <path> [--format tty|json|sarif]`, free model-free checks over produced text,
  `ScoreKit` (S001–S007 + S000), `scorers:` config block, EDDCore `SarifDocument`/`ScoreReport`
  frozen boundaries, RenderKit human table. A reporter, not a gate. Fifth Phase-2 feature.
  Roadmap → v1.17.0. Design → v0.49.
- 2026-07-08: PATCH — F16 capture-hardening rounds 1–5 (17 reviewed points, incl. one correctness
  bug): grounded capture never opens special files (FIFO/socket/device — a hang past the harness
  timeout) or hard-linked/symlinked files (host-content leak), withholds non-UTF-8/unreadable files
  with disclosed sizes (no lossy decode, no silent drop, invalid byte at the cap stays binary), uses
  lstat for deletion + symlink-child confinement, and persists evidence to the run cache on **every**
  exit path (incl. empty `[]`). Deferred with rationale: workspace-level isolation (robust
  hard-link/sandbox fix) + bounded fixture reads. 356 tests green. Roadmap → v1.16.5.
- 2026-07-08: **F16 IMPLEMENTED** — the grounded judge ([Specs/011](../Specs/011-grounded-judge/plan.md)):
  `run --judge grounded-judge` reads produced-file contents (snapshot-diff produced set,
  symlink-confined, bounded+disclosed) to catch created-but-wrong; additive committed `judge_id`;
  auto-routing staged (design §14-21). Fourth Phase-2 feature; no scope change to the rest.
  Roadmap → v1.16.0. (Design header pointer reconciled v0.39→v0.42; F15 review rounds had advanced
  the changelog to v0.41.)
- 2026-07-07: **F15 IMPLEMENTED** — the A/B baseline arm ([Specs/010](../Specs/010-ab-baseline/plan.md)):
  `run --ab` with prevent+verify+preflight isolation (`--disable-slash-commands`, $0 flag preflight,
  per-trial `polluted` tripwire), paired Δ ± SE reporting, canonical `with_skill`/`without_skill`
  benchmark rows + signed delta, offline `ab` recompute. Third Phase-2 feature; no scope change to
  the rest. Roadmap → v1.15.0.
- 2026-07-07: PATCH — F14 gains the diagnostic-tier smoke-arm note (design §9.6/§14-20, decided;
  F67/F68). Roadmap → v1.14.0; no change to shipped behavior.
- 2026-07-06: MINOR — added **F61** (deterministic process assertions over the trace; design
  §14-9 decided via the Apple Evaluations cross-reference, graduated from ROADMAP Candidate
  Enhancements — strict + partial-credit dual results, judge-free). Roadmap → v1.13.0; no
  change to shipped features.
- 2026-07-04: **F14 IMPLEMENTED** — the trigger axis ([Specs/009](../Specs/009-trigger-axis/plan.md)):
  `run --axis behavior|trigger|all`, deterministic `skillInvocations` grading over whole-corpus
  frontmatter stubs (§9.2 `visible:` tier live), per-axis `benchmark.json` merge, additive
  `skillet.run/1` `trigger` block. Doctor's discovery-only half: unblocked, still deferred (D-4).
  Second Phase-2 feature; no scope change to the rest.
- 2026-07-04: **F3 IMPLEMENTED — phase → IN PROGRESS.** `skillet doctor` ships the Option-2
  contract ([Specs/008](../Specs/008-doctor-preflight/plan.md)): frozen `skillet.doctor/1`
  check-registry rows; exit `0`-with-warnings / `3`-on-failure (+ shared `2`/`4` classes); config
  origin, harness binary/version/denylist + winning link, positive-load staging-parity visibility,
  error-tier lint surfacing; auth reported as a warning (`run` owns the refusal, per the F3 Notes).
  Deferred rows land with their owners (F20 frontmatter, F21 `--paid`, F24 origins; artifact sweep /
  `git` / betterleaks / discovery-only half with their features) — additive rows, never a schema
  bump. No scope change to the remaining features.
- 2026-06-17: Phase created. Holds the runner-hardening + full static-gate work
  split out of the thin "Now" walking skeleton.
- 2026-06-26: MINOR — **`doctor` (F3) moved in from Phase 1** as the phase's first
  feature (the $0 preflight belongs with its companions — the `--paid` canary F21,
  the full lint catalog F20, config ergonomics F24); **frontmatter spec-conformance
  rules re-homed into the full lint catalog (F20)** from `doctor` (they surface in
  `doctor` once they're lint rules; duplicate-key rejection needs raw-YAML anomaly
  detection); and the phase **adopted the global stable `Fn` ids** — the 12 native
  features renumbered to F14–F25 (roadmap v1.8.0 scheme reconciliation; see
  ROADMAP.md › Feature identifiers). No scope change beyond the `doctor` move and
  the frontmatter re-home.
