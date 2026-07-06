# Plan — Phase 2 · F14: the trigger axis (`skillet run --axis trigger`)

| | |
|---|---|
| **Feature** | F14 — trigger axis: does the *description* fire the skill? (CLI: `skillet run [--axis behavior\|trigger\|all]`) |
| **Phase** | 2 — Trustworthy Measurement & Static Gates ([Roadmap/phase-2-measurement-static-gates.md](../../Roadmap/phase-2-measurement-static-gates.md), F14) |
| **Status** | IMPLEMENTED (2026-07-04) — `--axis behavior\|trigger\|all` on `RunCommand` (default: each axis where its file exists; combined spend estimate; trigger-only runs build **no judge** and are exempt from §14-4's required-explicit rule — nothing is judged); `Runner.runTrigger` (deterministic loop, index-based cache paths, `trigger.json` forensics with routing + skipped-stub records); `WorkspaceManager.prepareTrigger` + public `frontmatterStub` (textual `---` fence extraction — RunKit stays `.Cxx`-free); `ClaudeCodeAdapter` enforces the staged `visible:` tier; `EDDCore`: `TriggerTrialResult`/`TriggerEvalResult`, `RunReport.Axis` + additive `trigger` block, `BenchmarkFile` master producer with **latest-run-per-axis merge** (axis-marked `consistency` entries; behavioral recompute filters trigger entries; judge provenance carried on judge-free runs — caught by TDD), `RunPlan` additive trigger fields. **279 tests green (+17**: 5 EDDCore, 3 RunKit, 2 live-shape parse, 7 replay-seam integration incl. per-axis merge + grading.json preservation**)**. Both roadmap F14 metrics verified against the built binary. Live stream-json `Skill` shape golden-tested (A1); real-harness validation rides the existing opt-in smoke. **Post-review round 1 (2026-07-05, 3-finding slate):** the lint gate is **axis-aware** (`SKILL-L009` no longer blocks runs without behavioral evals; L001/L003 still gate every axis — the description is what trigger tests) and `doctor` downgrades L009 to a warning when `trigger-eval.json` exists (decided in-session: doctor predicts the runner); `BenchmarkFile`'s master producer takes `skill:` explicitly (no more `"unknown"` on trigger-only first runs — asserted at unit + integration + recompute); unstageable-target net: CRLF normalize in `frontmatterStub` (the `\r\n`-is-one-grapheme Swift gotcha, caught by the new test), pre-spend stub check (exit 4), runner guard recording infra-failed trials (a skipped target can never mint a false near-miss PASS). First trigger-only fixture coverage (no `evals.json`) at run + doctor level. 283 tests green (+4). **Post-review round 2 (2026-07-05, 4-finding slate):** spend gate stays **trial-denominated** (decided in-session — `confirm_above_trials` never silently changes unit) with the call estimate now *visible*: `skillet.run-plan/1` gains additive `estimated_calls` (behavioral × 2 + trigger × 1), shown in the plan line and the confirmation prompt; doctor's L009 downgrade requires a **usable** trigger file (≥1 valid case, the runner's rule — broken/empty keeps the failure with a remedy naming the real problem); behavioral-owned benchmark metadata (`k`/`runs_per_configuration`/`harness`) follows the same carry rule as `evals_run`/judge (a k=1 trigger-only run no longer relabels a k=3 behavioral record); skipped axes print a stderr note (A4 honored). 284 tests green (+1, 3 extended). **Post-review round 3 (2026-07-05, 3-finding slate — decided: share, don't patch):** the trigger-file usability judgment moved into **one shared checker** (`TriggerEvalSupport.loadTriggerEvals`: absent/empty/invalid/usable, with `run`'s symlink refusal built in) called by both `run`'s loader and `doctor`'s downgrade — ending the copy-drift class two rounds in a row exposed; the downgrade now also requires `evals.json` genuinely absent (present-but-corrupt keeps the failure — default `run` would exit 4); the closing commit suggestion names only files actually written (`benchmark.json` alone on trigger-only runs). False-green integration coverage: corrupt-evals-with-usable-trigger and symlinked-trigger both keep doctor red. 286 tests green (+2, 2 extended). **Post-review round 4 (2026-07-05, 4-finding slate, assumptions confirmed):** the shared checker validates the **raw** array (non-object elements → artifact error by position; positional ids can no longer shift — codec round-trip tolerance untouched); doctor gains the additive **`skill.trigger-evals`** row (absent/usable pass · empty warn · invalid/symlinked fail — severities mirror the runner via the same shared checker), closing the valid-evals-plus-rotten-trigger false green; `prepareTrigger` refuses **symlinked sibling folders** (skipped + recorded — discovery doesn't filter them); `run --help` rewritten for both axes. 288 tests green (+2, 2 extended). **Post-review round 5 (2026-07-05, assumptions confirmed):** present-but-**empty** `evals.json` skips the behavioral axis under default mode (stderr note; symmetric with the trigger side's round-3 rule) — doctor's zero-case warning-with-green verdict is now a *true* prediction, closing the last runner↔doctor disagreement; explicit `--axis behavior` still errors, corrupt still artifact-4; the "nothing to run" message covers absent-or-empty; docc sample updated to the axis-labeled headline. (`init` skeletons recorded on [Specs/002](../002-adopt-skillet-repo/plan.md).) 290 tests green (+2, 3 extended). **Post-review round 6 (2026-07-05):** symlink checks moved **before** exists checks everywhere the two interact — the follow-the-link exists check calls a *dangling* symlink "absent", which classified a dangling `trigger-eval.json` as not-configured (pass) and a dangling `evals.json` as genuinely-absent (leniency-eligible) while `run` refuses both at exit 4. Fixed in the shared checker (lstat-first) and doctor's absence test; both dangling variants pinned red by one integration test. No design-text change — code-honesty only. 292 tests green (+2 with Specs/002's escaping test). |
| **Last updated** | 2026-07-04 |
| **Builds on** | F5/F6 (`Trace.skillInvocations`, `SkillSet.only(load:visible:)` signature, claude-code parser); F7 (Runner/WorkspaceManager, spend gate, run records, replay seam); F8 (`TriggerEvalFile` frozen codec — `{query, should_trigger}`, held raw); F3 (presence-guaranteed reporting discipline) |
| **Authoritative refs** | design §6.1 `run` (`--axis`, both-axes default), §9.3 ("the trigger axis runs on `skillInvocations`" — bare query, `.only(load: [], visible: allSkills)`, deterministic, no judge), §9.2 (visible = present-but-stubbed, bodies withheld), §4 (axis-generic eval/pass^k/FLAKY vocabulary), §7.2 (`benchmark.json` frozen viewer contract + additive `consistency` block), §10 (observed-k semantics); P2/D3 (offline recompute from committed records) |
| **Decisions (2026-07-04, in-session, evidence-recorded)** | **D-1 Results persistence:** trigger trials ride `benchmark.json` as viewer-shaped `runs[]` rows under **`configuration: "trigger"`** (the viewer's native discriminator — predecessor `Benchmark.swift` aggregates per-configuration with deltas; its `Runner.swift:13` planned trigger evals into this same record), with authoritative aggregation in the additive **`consistency` block** (`per_eval[].axis` marker + `trigger_*` suite metrics). Survey (promptfoo componentResults, lm-eval-harness results.json, SARIF runs[]): result kinds are keyed inside one artifact; per-kind files appear only at the run-log layer (Inspect), which skillet's `.skillet/runs` cache already is. **D-2 Stubs:** visible-tier staging = **frontmatter-only stub** (real `name`+`description`, body replaced by a stub marker) — §9.2's "bodies withheld", pure description-driven selection, near-zero post-fire spend. **D-3 Scope:** **whole-corpus stubs** per trigger trial (design-literal `visible: allSkills`) so near-misses measure real routing; attribution: `should_trigger:true` passes only on *target* fire; a sibling fire on a near-miss is correct non-firing. **D-4 Doctor:** discovery-only visibility check stays **deferred** — but every doc gating it on "until `visible:` is exercised live" is updated to "unblocked by F14, deferred, tracked". |
| **Assumptions** | A1: live `stream-json` skill-invocation parsing is in F14 scope (design v0.13 assigns it; predecessor `StreamEvent` confirms live assistant events carry the same `message.content[].tool_use` block grammar, but it never parsed `Skill` blocks — F14 adds synthetic live-shape goldens + validates via the opt-in env-gated smoke). A2: `--axis behavior\|trigger\|all`, default `all`-where-files-exist (§6.1); the spend estimate + confirm gate covers the added default cost. A3: `k`/`pass^k`/FLAKY apply to trigger evals unchanged; a trigger trial = **one** paid call (no judge). A4: absent/empty `trigger-eval.json` ⇒ axis skipped with a note; explicit `--axis trigger` with no file = usage error (exit 2, what/why/fix). A5: RunKit stays `.Cxx`-free — stub frontmatter is extracted **textually** (`---` fence split), never via `ConfigYAML`. |
| **Workflow** | Standalone plan (spec-kit workflow intentionally skipped) |

---

## 1. Goal

Ship the second axis: `skillet run --axis trigger` executes each `trigger-eval.json` query as a bare
prompt with the repo's skills *discoverable but stubbed*, and grades fired/not-fired
**deterministically from `Trace.skillInvocations`** — closing the "did it even trigger?" half of
quality and retiring the never-shipped Python trigger harness. One binary, two axes, reported
separately.

**Success criteria (roadmap F14 metrics, verbatim):**
- Each `trigger-eval.json` query is judged fired/not-fired deterministically from
  `skillInvocations`; `should_trigger:false` near-misses verify correct *non*-firing.
- Reported separately from the behavioral axis in the run table.

**Contract additions (decisions above):**
- `benchmark.json`: trigger `runs[]` rows (`configuration:"trigger"`, `eval_id` `trigger-<i>`, one
  expectation whose text states the criterion) + `consistency.per_eval[].axis` (additive; absent =
  `behavior`) + `trigger_suite_pass_power_k`/`trigger_suite_pass_1` — behavioral suite metrics keep
  their exact meaning. Offline recompute handles both axes from the one committed file (P2/D3).
- `skillet.run/1`: additive optional `trigger` block (per-eval rows + `pass_k`/`pass_1`/`observed_k`/
  `measurable` + counts), mirroring the behavioral fields. Goldens extended additively.

## 2. Scope

### In scope
- **EDDCore**: `TriggerOutcome`/report evolution (additive `trigger` block in `RunReport`);
  `PassK` reuse over trigger evals; benchmark producer + `consistency` evolution (axis marker,
  `trigger_*` suite metrics); recompute reads both axes.
- **RunKit**: `WorkspaceManager.prepareTrigger(...)` — whole-corpus **frontmatter-stub** staging
  (textual `---` fence extraction; symlink/hidden rules via `SkillBundleRules`); Runner trigger
  loop (`cases × k` trials, one call each, deterministic verdicts, forensics under
  `.skillet/runs/<ts>/trigger-<i>/trial-<t>/`).
- **HarnessKit**: honor `visible:` in `ClaudeCodeAdapter.run` staging enforcement (stub present =
  visible); live `stream-json` `Skill` tool_use parsing hardened + synthetic live-shape goldens.
- **executable**: `--axis behavior|trigger|all` (default `all`-where-files-exist), the
  **trial-denominated spend gate** (the unit `confirm_above_trials` has always meant — decided
  review round 2) with a previewed **call estimate** (behavioral × 2 + trigger × 1, shown in the
  plan line, `skillet.run-plan/1` `estimated_calls`, and the confirmation prompt), trigger table in
  TTY output (separate section, §6.1 sample style), `--json` additive block.
- **Tests**: EDDCore unit + golden (report/benchmark/consistency additive shapes, recompute both
  axes); RunKit stub-staging tests (fence extraction, corpus staging, exclusion rules) + trigger
  loop via `ReplayAdapter` (canned trace fires `demo`); HarnessKit live-shape parser goldens;
  integration via the replay seam (fired/not-fired/near-miss pass & fail, `--axis` selection,
  missing-file classes, `--json` shape); the env-gated live smoke gains a trigger validation note.

### Out of scope (with where it lands)
- `--ab` arms → **F15** (the `with_skill`/`without_skill` configuration strings stay reserved).
- Doctor's discovery-only visibility row → deferred (**D-4**; unblocked by F14, tracked in the F3
  notes + §6.1/§9.2 annotations — docs updated by this feature to say so).
- `--eval <id|tag>` selection, `--matrix`/multi-harness, `--record`/`--replay` flags → their owning
  features (F19, Phase 7). Process-assertions generalization → §14-9 (pending).
- `direct-api`'s selection-prompt approximation → with the `direct-api` adapter.

## 3. Architecture (targets touched)

`EDDCore` (pure models/aggregation/codecs) ← `RunKit` (stub staging + trigger loop) ←
`skillet` (axis wiring/estimate/rendering); `HarnessKit` (visible enforcement + parser hardening).
No new targets, no new dependencies, `.Cxx` containment preserved (A5).

## 4. Test plan (TDD) — free-first
All trigger-loop logic tested via `ReplayAdapter`/fakes ($0); the only paid validation is the
existing opt-in smoke. 300-line test-file cap honored.

## 5. Task breakdown (ordered)
1. EDDCore models + goldens (report `trigger` block; benchmark trigger rows; consistency axis).
2. RunKit stub staging + tests; Runner trigger loop + tests (replay).
3. HarnessKit visible enforcement + live-shape parser goldens.
4. RunCommand `--axis` + estimate + renderer; integration tests.
5. Docs ripple incl. **D-4 obligation**: design §6.1/§9.2/§9.3 annotations (visible tier real;
   doctor half unblocked-deferred), F3 phase-note + adapter comment updates, phase-2 F14 →
   IMPLEMENTED, ROADMAP MINOR + changelog, README/AGENTS/docc, design changelog entry, this header.

## 6. Risks & assumptions
- **Live invocation shape** (A1): structure-compatible per predecessor fixtures, but `Skill`
  blocks were never parsed by anyone — synthetic goldens could diverge from reality until the
  smoke runs. Mitigation: goldens mirror the predecessor's captured shapes; smoke validates; the
  deterministic grader fails *loud* (not-fired) rather than mis-attributing.
- **Trigger flakiness is signal, not noise**: firing is sampling-dependent; FLAKY trichotomy
  applies unchanged and surfaces description weakness — that's the feature working.
- **Stub fidelity**: a frontmatter fence with no closing `---` or empty description stages a
  degenerate stub; the fence extractor falls back to skipping that sibling with a warning row in
  forensics (never a crash).

## 7. Definition of done
- Both roadmap metrics verified by replay-seam integration tests against the built binary.
- All goldens additive (existing byte-stable outputs unchanged); full suite green.
- Docs ripple landed incl. every D-4 tracking-text update; no settled-decision change.
