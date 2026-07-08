# Plan — Phase 2 · F15: the A/B baseline arm (`skillet run --ab`)

| | |
|---|---|
| **Feature** | F15 — A/B baseline arm: run with-skill and provably-without-skill arms and report the paired Δ (CLI: `skillet run --ab`) |
| **Phase** | 2 — Trustworthy Measurement & Static Gates ([Roadmap/phase-2-measurement-static-gates.md](../../Roadmap/phase-2-measurement-static-gates.md), F15) |
| **Status** | IMPLEMENTED (2026-07-07) — `--ab` on `RunCommand` (behavioral-only; trigger-only + `--ab` refuses at exit 2 pre-spend; mixed runs note the single-arm trigger on stderr; spend gate + `estimated_calls` + plan preview cover both arms, additive `ab_baseline_trials`); `Runner.runBaseline` (`SkillSet.none`, `stageSkill: false`, per-trial **pollution tripwire** — any `skillInvocations` on a baseline trial ⇒ new `polluted` exit class, never judged, excluded from counts) + per-trial `durationSeconds` on both arms; `ClaudeCodeAdapter` — `.none` appends **`--disable-slash-commands`** and `verifyBaselineIsolation()` greps the resolved binary's `--help` for it pre-spend (new `EDDError.baselineNotIsolable`, exit 3; default adapters refuse via the loud-degrade protocol extension; new `HarnessCapabilities.baselineIsolation`); `ReplayAdapter` arm-aware (`.none` serves a skill-free canned trace; hidden `--replay-baseline-map` wires arm-distinct verdicts, fail-all default → deterministic positive Δ); `EDDCore` — `ABComparison` (paired per-eval Δ + Bessel SE at n ≥ 2 else nil, flips, time Δ, polluted, flaky-untrusted ids) additive in `skillet.run/1`, benchmark producer writes canonical `with_skill`/`without_skill` rows + arm-marked `per_eval` (+`polluted`) + per-arm `pass_rate`/`time_seconds`/`tokens` stats + signed `delta` strings (`+0.50`/`+13.0`/`+0`), single-arm keeps `"default"`, trigger-only runs carry the whole AB record (latest-run-per-axis), offline recompute rebuilds `ab` with live math; RenderKit WITH/BASELINE/Δ table + paired footer (± SE or "too few", flip tally, pollution warning). **+25 tests at initial implementation** (8 EDDCore, 5 RunKit, 6 HarnessKit, 6 integration; 317 green at that point — the post-review rounds below carry the running totals, and the **final count is the last status-log entry**); both roadmap F15 metrics verified against the built binary. **Bench check done (2026-07-07):** the Zed-bundled claude **2.1.198** (resolved via the TestingEndToEnd editor-bundle chain) advertises `--disable-slash-commands  Disable all skills` in `--help` — the preflight's exact match target, confirmed against a real current binary for $0. Remaining live item (rides the env-gated smoke, paid): full `--ab` semantics on a real session — in particular whether the switch also removes skill *descriptions* from context, not just loading; the per-trial tripwire covers the loading half regardless. |
| **Last updated** | 2026-07-07 |
| **Builds on** | F7 (Runner/WorkspaceManager, spend gate, run records, replay seam); F14 (axis wiring, per-axis benchmark merge, `estimated_calls`); F6 (claude-code adapter + arg contract); F8 (frozen codecs) |
| **Authoritative refs** | design §6.1 `run` (`--ab` adds the without-skill baseline arm, reporting Δ), §9.2 (`SkillSet.none`: "provably no skill present"; the adapter isolates ambient skills **or declares it cannot** — `--ab` refused, never a polluted baseline), §10 (arms in the plan expansion), §4 (Arm vocabulary); the frozen `benchmark.json` viewer contract (canonical `configuration` strings `with_skill`/`without_skill`, per-arm `{mean,stddev}` stats + signed delta strings — reserved for F15 by Specs/009) |
| **Decisions (2026-07-05→07, in-session Q&A, evidence-recorded)** | **D-1 Isolation = prevent + verify + preflight** (industry cross-ref: Claude Code CLI reference `--disable-slash-commands` / `--safe-mode` / `--bare`; promptfoo's transcript-based `skill-used` assertion): baseline trials launch claude-code with **`--disable-slash-commands`** (surgical: skills+commands only — `--bare`/`--safe-mode` would also strip CLAUDE.md/hooks and make the arms differ by more than the skill; auth untouched, no config-dir relocation); every baseline trial's parsed `Trace` must show **zero `skillInvocations`** — any hit reclassifies the trial `polluted` (never a graded result, never judged; excluded from the arm's counts; surfaced in report + JSON); a `verifyBaselineIsolation()` preflight greps the resolved binary's `--help` for the flag **before spend** and refuses (exit 3, what/why/fix) when absent — adapters without the capability refuse `--ab` by default (loud-degrade house pattern). **D-2 Reporting = paired difference** (Anthropic *Adding Error Bars to Evals*: report per-item paired deltas + SE, not marginal-score subtraction; agent-skills-eval parity: pass/latency/tokens visibility): per-eval paired Δ of trial pass rates; suite footer = mean paired Δ **± SE** (Bessel; SE only at n ≥ 2 — otherwise "too few evals/repeats", never fake certainty), flip tally (baseline→with), time Δ; tokens print "—" until `Trace.usage` lands (F60) — never fabricated. **D-3 Records = canonical two-arm block**: `--ab` runs write `runs[]` rows under `configuration: "with_skill"` / `"without_skill"` (single-arm runs keep F7's `"default"`; readers treat `default` as the with-arm); baseline `consistency.per_eval` entries carry an additive `"arm": "baseline"` marker so the behavioral recompute never mixes arms; `run_summary` gains `with_skill`/`without_skill` (`pass_rate`/`time_seconds` stats; `tokens` zeros until F60) + a `delta` block with signed fixed-precision strings (`+0.50`/`+13.0`/`+1700` — predecessor `Benchmark.swift` parity); Δ re-derives offline from the committed record (P2/D3). **D-4 Scope = behavior axis only**: universal practice (activation is tested *with* the skill; over-triggering via near-misses); mixed runs print a stderr note (shipped F14 pattern); a trigger-only invocation with `--ab` refuses before spend (usage, exit 2). |
| **Assumptions** | A1: both arms graded by the **same judge + rubric** (that is the comparison); grading.json stays with-arm-only (it is the skill's judged record). A2: spend gate stays trial-denominated; `--ab` doubles behavioral trials and the call estimate (baseline trials are judged too: behavioral × 2 arms × 2 calls + trigger × 1); `skillet.run-plan/1` gains additive `ab_baseline_trials`. A3: exit code semantics unchanged — exit 1 derives from the with-arm (+ trigger); a failing *baseline* is not a failure (it is the point). A4: `skillet.run/1` gains one additive optional `ab` block; goldens extend additively. A5: the replay seam must be arm-aware (the canned trace fires `demo`, which would trip the tripwire) — `.none` serves a skill-free canned trace; a hidden `--replay-baseline-map` wires arm-distinct canned verdicts (baseline defaults fail-all, so replay `--ab` shows a positive Δ deterministically). A6: `durationSeconds` is measured per trial (additive on `TrialResult`) — `time_seconds` stats are real from day one. |
| **Workflow** | Standalone plan (spec-kit workflow intentionally skipped) |

---

## 1. Goal

Ship the value-attribution arm: `skillet run --ab` runs every behavioral eval through both a
with-skill arm and a **provably skill-free** baseline arm and reports the paired per-eval Δ —
"is the skill earning its tokens?" — matching `agent-skills-eval` on day one, with isolation that
is checked, never assumed.

**Success criteria (roadmap F15 metrics, verbatim):**
- `--ab` adds a provably skill-free baseline arm and prints per-eval Δ.
- On a harness that cannot isolate ambient skills, `--ab` is refused with an explanation rather
  than producing a polluted baseline.

## 2. Scope

### In scope
- **EDDCore**: `TrialExit.polluted` (additive); `TrialResult.durationSeconds` (additive, default
  nil); `RunReport.ab` block (baseline axis + per-eval paired rows + paired mean Δ ± SE + flips +
  time Δ + polluted count); paired-difference math (pure, Bessel-corrected SE); benchmark producer
  two-arm rows/summary/delta + `arm` marker + baseline recompute (`baselineCounts`, `ab`
  re-derivation); `RunPlan.abBaselineTrials`.
- **HarnessKit**: `HarnessCapabilities.baselineIsolation`; `verifyBaselineIsolation()` protocol
  extension (default: loud refusal); `ClaudeCodeAdapter` — `--disable-slash-commands` on `.none`
  runs, `--help` flag-support preflight, `.none` skips skill-staging enforcement; `ReplayAdapter`
  arm-aware canned traces.
- **RunKit**: `WorkspaceManager.prepare(stageSkill:)` (baseline sandboxes stage fixtures only);
  `Runner.runBaseline` (`.none` injection, pollution tripwire after parse — polluted trials are
  never judged); per-trial duration capture on both arms.
- **executable**: `--ab` flag; trigger-only refusal + mixed-run stderr note; doubled spend math +
  plan preview; baseline isolation preflight before spend; AB table + paired footer (RenderKit);
  additive JSON; records writing with the baseline arm.
- **Tests**: EDDCore unit (paired math edge cases; two-arm producer; carry; recompute; polluted
  exclusion); RunKit (skill-free staging, tripwire, duration); HarnessKit (arg shape, help-grep
  preflight, arm-aware replay); integration via the replay seam (`--ab` end-to-end: table, JSON,
  benchmark, exit codes; refusal + note paths; dry-run doubling).

### Out of scope (with where it lands)
- Ambient-skill isolation for `.only` (with-arm) runs — the global-skills leak on the with-arm is
  pre-existing and orthogonal (tracked in the F6 adapter comment); F15 fixes the *baseline* arm,
  where the §9.2 "provably" contract bites.
- `Trace.usage` token stats → F60 (tokens render "—" / write 0 until then).
- Ablation arms (partial-skill) → design §14-10 (pending). `--matrix` interplay → Phase 7.
- The `infra` exit class + retry → F18 (`polluted` is F15's one addition; F18 subsumes nothing here).

## 3. Architecture (targets touched)

`EDDCore` (models/math/codecs, pure) ← `RunKit` (baseline loop + staging) ← `skillet`
(flag/preflight/records/rendering); `HarnessKit` (isolation contract + adapter). No new targets,
no new dependencies, `.Cxx` containment preserved.

## 4. Status log

- 2026-07-07: Plan authored from the in-session decision Q&A (D-1…D-4); implementation started.
- 2026-07-07: IMPLEMENTED — full status in the header row. 317 tests green (+25). Design → v0.39,
  ROADMAP → v1.15.0. Bench check: `--disable-slash-commands` confirmed in the Zed-bundled claude
  2.1.198's `--help` ($0). Open follow-ups: paid live `--ab` smoke (incl. whether the switch hides
  skill *descriptions* from context, not just loading — the tripwire covers loading either way);
  with-arm ambient-skill isolation stays out of scope (pre-existing, documented in the adapter).
- 2026-07-07: **Post-review round 1 (3-finding slate).** (1) **Unmeasured pairs can no longer
  manufacture a skill effect**: a pair with zero measured trials in either arm (e.g. every baseline
  trial polluted, or a baseline eval that never ran) now yields `delta: nil`, joins the new
  `unmeasured_eval_ids`, and is excluded from the paired mean/SE and the flip tally (the old code
  treated an all-polluted baseline as rate-0 FAIL → a fabricated `+1.00 / 1↑`; one shipped test had
  codified it). The renderer prints `— 0/0` / `n/a` for such rows, "unmeasured" for an
  effect with zero measured pairs, the flip denominator over measured pairs, and a dedicated
  unmeasured line; the pollution warning is unchanged. (2) **One paired estimator everywhere**:
  `benchmark.json`'s `delta.pass_rate` was a pooled trial-mean difference (diverges from
  `ab.paired_mean_delta` when pollution removes baseline trials unevenly — pinned by a new
  uneven-counts test); the producer now derives it from the same `ABComparison`, and the paired
  math itself moved into one shared `init(pairs:...)` used by the live report AND the offline
  recompute — divergence is now impossible by construction (`time_seconds` delta deliberately stays
  the pooled-mean difference, matching the per-arm stats beside it). (3) **AGENTS.md synced** per
  its own maintenance contract: F15/Specs/010/317-tests banner, `--ab` in the run synopsis, hidden
  replay seams (`--replay`/`--replay-map`/`--replay-baseline-map`) documented. 319 tests green
  (+2 new: all-polluted-no-effect, uneven-counts-paired-delta; the unmeasured-pair test is the
  missing-baseline test rewritten in place; 2 extended).
- 2026-07-07: **Post-review round 2 (2-finding slate).** (1) **Committed/offline time delta keeps
  the live optionality**: `armSummary` writes `time_seconds` only when the arm measured durations,
  and the `delta` block gains `time_seconds` only when both arms did (and `pass_rate` only when a
  measured pair exists; an entirely-unmeasured comparison writes no `delta` block at all) — the old
  producer averaged empty arrays (`mean([]) = 0`), fabricating `"+N.0"` off an all-polluted arm,
  and the offline recompute then rebuilt a non-nil delta the live report honestly withheld.
  `abTimeDelta`'s absent-key guard now means "unmeasured" by construction. (2) **`durationSeconds`
  is harness-only on every path**: the post-`adapter.run` stamp is hoisted and reused by the
  parse/judge error exits (previously those measured elapsed-at-catch, leaking slow grader/parser
  time into the arms' time Δ, contradicting the stated contract); when `adapter.run` itself threw,
  elapsed-at-catch is the run attempt and stays. 321 tests green (+2: unmeasured-arm-omits-keys
  incl. offline round-trip, slow-throwing-judge duration; 1 extended with time-Δ parity).
- 2026-07-07: **Post-review round 3 (count reconciliation) + full-suite verification.** The
  authoritative run: **321 tests in 52 suites, zero failures, exit 0**. Earlier round entries had
  recorded *predicted* counts (320/322) before their verification runs completed — a hung
  round-1 test process held the SwiftPM build lock for ~90 minutes and silently queued every
  later run; counts here and in AGENTS.md / ROADMAP / the design changelog are now corrected to
  the verified numbers (initial 317 → round 1 319 → round 2 321; F15 total +29 test annotations,
  25 initial + 4 across rounds, 1 rewritten in place).
