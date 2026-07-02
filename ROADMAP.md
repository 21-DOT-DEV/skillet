# Product Roadmap — skillet

**Version:** v1.10.0
**Last Updated:** 2026-07-01

`skillet` is the SKILL.md Evaluation Toolkit — eval-driven development (EDD)
for agent skills, as a public, multi-harness Swift CLI. This roadmap is
derived from `skillet-design.md` and an external best-practice cross-reference
(see Change Log). Horizons express priority and sequence, not delivery dates.

## Vision & Goals

- **Vision (Northstar):** Close the feedback loop into actionable `SKILL.md`
  iterations as fast as reasonably possible, without cutting corners.
- **Target users:** Maintainers of `SKILL.md` skills for any agentskills.io-style
  harness (Claude Code, Codex, OpenCode, …) who want their skills to improve
  from real usage without calcifying around one bad run.
- **Top outcomes:**
  1. Skills improve from real production usage — every hand-fix becomes
     structured evidence instead of a lost lesson.
  2. Every `SKILL.md` edit ships only after it is corroborated and *proven* by
     a previously-failing eval that now passes.
  3. Skill behavior is portable, and that portability is *visible* — "passes on
     Claude Code, flakes on OpenCode" is a table, not a surprise.

**Guiding principles** (from the design doc, reinforced by the cross-reference):

- **Error analysis first.** The highest-value activity is discovering real
  failure patterns; codify what you *discover*, never what you *imagine*.
- **Deterministic-first.** Free, instant static checks (lint, scorers) run
  before any paid model judging.
- **The human is the benevolent dictator.** The tool drafts, measures, and
  proves; a human makes every judgment and owns every commit — skillet never
  commits.
- **Gates advise, they don't block.** Corroboration gates guide the worklist;
  CI enforcement is opt-in (`--strict`).
- **Spend is visible and consented.** Paid runs are estimated up front; the
  cheap path is always offered first.

## Phases Overview

| Horizon | Phase | Name / Goal | Status | Detail |
|---|---|---|---|---|
| Foundation | 1 | Walking Skeleton — prove the loop end-to-end | COMPLETE | [phase-1](Roadmap/phase-1-walking-skeleton.md) |
| Now | 2 | Trustworthy Measurement & Static Gates | PLANNED | [phase-2](Roadmap/phase-2-measurement-static-gates.md) |
| Next | 3 | Discovery & Evidence Capture | PLANNED | [phase-3](Roadmap/phase-3-discovery-evidence.md) |
| Next | 4 | Error Analysis — *Northstar gap #1* | PLANNED | [phase-4](Roadmap/phase-4-error-analysis.md) |
| Next | 5 | The Computable Runbook — *differentiator #1* | PLANNED | [phase-5](Roadmap/phase-5-computable-runbook.md) |
| Next | 6 | Fix Suggestion & Safe Iteration — *Northstar gap #2* | PLANNED | [phase-6](Roadmap/phase-6-fix-suggestion-iteration.md) |
| Next | 7 | Multi-Harness Portability — *differentiator #2* | PLANNED | [phase-7](Roadmap/phase-7-multi-harness.md) |
| Later | 8 | Beyond v1 — deeper analysis, broader reach | FUTURE | [phase-8](Roadmap/phase-8-beyond-v1.md) |

- **Phase 1 (Foundation, COMPLETE):** The thinnest end-to-end thread — `skillet run` one eval
  through `claude-code`, judged, with a `pass^k` result — plus just-enough
  `init`/`lint`. Proves the architecture and delivers 30-second value. (All features
  shipped; the `doctor` preflight moved to Phase 2.)
- **Phase 2 (Now):** Make deltas trustworthy — trigger axis, A/B baseline,
  grounded judge, scorers, flaky hygiene, record/replay, the `doctor` preflight
  gate, the full free static-gate catalog, and TTY/HTML reporting.
- **Phase 3 (Next):** Record production sessions and human friction as
  structured, greppable evidence (secret-sanitized on capture) — the raw material
  for error analysis.
- **Phase 4 (Next):** Mine the corpus into a routed failure taxonomy,
  contradictions first — error analysis *before* codification.
- **Phase 5 (Next):** The gates engine + `skillet next` — "git status for EDD":
  the single highest-value action, with its reason and the exact command.
- **Phase 6 (Next):** Draft minimal `SKILL.md` edits from observed evidence and
  prove them by A/B in a throwaway worktree before a human lands them.
- **Phase 7 (Next):** Run the same suite across multiple agents and print a
  per-harness `pass^k` portability table.
- **Phase 8 (Later):** Track B axial coding, more adapters, the remaining lint
  rules — incl. the **skill-security** (F12) and **skill-bundle-integrity** (F13) groups from the
  competitive cross-reference — **user-authored (YAML) lint rules**, real spend numbers, a
  judge↔human-label calibration harness — plus the explicit non-goals.

## Feature identifiers

Every feature carries a stable **`Fn`** id (e.g. `F6`, `F23`): a single global counter across the
whole roadmap, **assigned once at creation and never changed, reused, or renumbered** when a feature
moves between phases or is re-sequenced. Ids deliberately **do not encode phase or position** — a
feature keeps its id wherever it lands — so every cross-reference (specs, design, change log) survives
reprioritization. This is the standard stable-identifier discipline for requirements and issue
trackers: assign-once, unique, position-independent, never-renumber
([Sparx EA](https://sparxsystems.com/enterprise_architect_user_guide/14.0/model_domains/requirements_naming_and_numbering.html),
[RTEMS](https://docs.rtems.org/docs/main/eng/req/req-for-req.html),
[Jira](https://support.atlassian.com/jira/kb/how-to-get-issue-id-from-the-jira-user-interface/)).

Consequences, by design: ids are **not** contiguous within a phase, and the per-phase Key-Features
lists are ordered by build sequence/theme, **not** by id. `F9` is a retired gap (never assigned). The
v1.8.0 reconciliation assigned global ids to the phases that had been using local per-phase numbering;
Phase 1's `F1–F8` and Phase 8's `F10–F13` were already global and were preserved.

## Product-Level Metrics & Success Criteria

- **Time-to-first-signal** — a fresh skills repo gets a with-skill `pass^k` from
  a single `skillet run`, with zero manual skill-path configuration.
- **Loop cycle time** — median elapsed time from a captured friction event to a
  proven, ready-to-land proposal.
- **Corroboration integrity** — 100% of `SKILL.md` edits shipped via skillet are
  backed by a previously-failing eval that now passes, **corroborated by a held-out sibling
  eval** (same failure class, distinct from the drafting eval) so the proof reflects a
  generalizing fix, not an overfit.
- **Evidence-to-edit ratio** — share of evidence correctly routed to a cheaper
  lever (config/lint/reference) instead of a prose edit; the tool should resist
  over-editing the skill.
- **Portability visibility** — % of evals reporting a per-harness `pass^k` across
  ≥2 harnesses.
- **Spend honesty** — every paid run prints an up-front estimate; every $0 gate
  runs before any paid command; zero unestimated paid runs.
- **Calibration safety** — % of trusted result-deltas with zero unresolved
  scorer↔judge contradictions.

## High-Level Dependencies & Sequencing

- **Phase 1 underpins everything:** the normalized `Trace`, the `HarnessAdapter`
  protocol, and the frozen boundary codecs it establishes are reused by every
  later phase.
- **Phase 3 → 4 → 5 (analyze before codify):** capture evidence, then mine
  failures, *then* let the gates engine prioritize and scaffold evals. This
  ordering follows the error-analysis-first principle.
- **Phases 4 and 6 are the two Northstar value gaps** and are sequenced ahead of
  Phase 7 within the Next horizon — even though all three are v1 — because the
  harness matrix is a differentiator, not a value gap.
- **Phase 6 depends on Phase 5** (evidence/proposal lifecycle) and **Phase 1**
  (`iterate` re-measures through the runner).
- **Phase 7 depends on Phase 1's adapter protocol;** `run --matrix` needs ≥2
  adapters to be meaningful.

## Global Risks & Assumptions

- **Phase 1 COMPLETE; later phases greenfield.** All Phase 1 features ship — F1 (project discovery
  & output contract), F2 (`skillet init`), F4 (`skillet lint`), F5 (trace & harness seam), F6
  (claude-code adapter), F8 (frozen boundary codecs), and now F7 (`skillet run` — the neutral runner,
  `pass^k`, `RunKit`+`JudgeKit`) — `Specs/001`–`007`, 235 tests green. Phases 2–8 — now including
  `doctor` (F3, moved into Phase 2) — are PLANNED/FUTURE: those statuses reflect design intent
  verified against the design doc (Medium confidence), not running code.
- **"Ported" assumption.** The design doc says much of v1 is faithfully
  translated from a predecessor (`swift-skill-eval` + a Python trigger harness).
  That predecessor is not in this repo, so `Ported` tags are a scheduling hint,
  not a verified status; per design §13 the schedule risk concentrates in the
  `Net-new` column.
- **Open questions resolved to doc defaults.** Design §14 choices are assumed at
  their stated defaults (`opencode` as the second adapter; Apache-2.0; static
  `concurrency` knob — the judge-model question is now **decided**: required-explicit,
  §14-4 / v1.10.0). Items resting on the remaining assumptions carry `needs-research`.
- **Trademark risk.** Palo Alto Networks ships a "Skillet" product family (design
  Appendix C / Open Q1); a public launch needs a trademark sanity check first. A
  June-2026 GitHub sweep found **no collision *inside the eval space*** — the PAN
  family is the only conflict, so the risk is narrowed, not removed (the check still
  precedes any public launch).
- **Judge-reliability risk.** External research shows LLM judges are
  systematically over-confident and that evaluation criteria drift as outputs are
  reviewed. Mitigation: the scorer↔judge contradiction gate, `judge_prompt_version`,
  and offline re-grade; a judge↔human-label calibration harness is tracked as a
  `needs-research` item in Phase 8.
- **Cost risk.** Paid trials and judging spend money. Mitigation: deterministic-first
  gates, up-front estimates, confirm-above-threshold.
- **Deliberate phase count.** This roadmap uses 8 phases (above the usual 3–6) on
  purpose: to keep "Now" a thin walking skeleton and to give each Northstar value
  gap its own spotlighted phase, per the dependency-honest + Northstar-forward
  decisions and the walking-skeleton / error-analysis-first cross-reference.

## Candidate Enhancements (pending design §14 sign-off)

From the v0.8 design competitive cross-reference, **staged as design open questions and not yet in
the phase plan**. Each graduates into a phase once its §14 question is decided; until then the
phases and the v1 scope line are unchanged.

- **Deterministic process-assertions over the Trace** → design **§14-9** (with a metrics/events
  schema-split sub-question). Free, judge-free assertions (skill loaded? tool-calls in order? within
  budget?) before the paid judge, extending the Phase 2 trigger axis.
- **Ablation arms** → design **§14-10**. Partial-skill A/B (drop a section / reference / rule) to
  isolate which part of a skill earns its tokens — feeds *evidence-to-edit ratio*. Touches the
  Phase 6 `run --ab` / `SkillSet`.

## Change Log

- v1.10.0 (2026-07-01): MINOR — **audit remediation slate landed** (M1–M3 + §14-11 adopted; M4
  drafted, pending maintainer ratification — [phase-1-review §5/§8](Roadmap/phase-1-review.md)).
  (1) **M1:** `.github/workflows/ci.yml` — the constitution-V free-suite gate (macOS + Ubuntu via the
  official `swift:6.3` container; zero secrets, zero paid calls; the live smoke self-skips) —
  authored and logically verified; the first live run (and any Linux-first-build fallout) lands with
  the next push. (2) **M2 / design §14-4 DECIDED — required-explicit judge model:** the config decode
  carries no model fallback and `run` refuses an absent `judge.model` (exit 2, what/why/fix; the
  replay/test seam exempt; `init` writes one). **Migration (pre-1.0 breaking):** hand-rolled configs
  without `judge.model` must add it — or re-run `skillet init`. A deliberate divergence from the
  surveyed silent-default convention (promptfoo's ambient-credential grader). (3) **M3:** committed
  records gain additive provenance — `benchmark.json` `metadata.executor_binary_version` +
  `metadata.judge.prompt_version`, and a `grading.json` `judge` block — via the new pure
  `EDDCore.RunProvenance`; `run` now probes the replay seam too (canned, free) so every record names
  its executor. (4) **§14-11 DECIDED — adopted:** additive `pass_1` in `skillet.run/1` +
  `suite_pass_1` in the `consistency` block (mean per-eval trial pass rate — τ-bench's headline
  metric, meaningful even at k = 1); strict all-trials `pass^k` stays the reliability gate
  (graduated out of *Candidate Enhancements*). Design doc → v0.24/v0.25. 237 tests green. No phase
  or priority change.
- v1.9.10 (2026-07-01): PATCH — **external cross-reference addendum** added to the Phase-1 audit
  ([phase-1-review §8](Roadmap/phase-1-review.md)) after three adversarially-verified deep-research
  passes (~29 primary sources): **nothing contradicts shipped Phase-1 behavior**. Verified supported:
  pass^k ≡ τ-bench's metric (Chen et al. the correct ANY-pass contrast), FLAKY/hygiene-before-deltas
  = the Google flaky-test canon, the existence-check-via-workspace-listing rule (Anthropic's canonical
  final-state example; τ-bench/SWE-bench concur), **M1's free-suite-as-PR-gate** (lm-evaluation-harness
  + Inspect AI run model-free zero-credential CI on every PR; walking-skeleton canon puts build/test
  automation before the first feature), the held-out proof gate (DSPy/GEPA), and audit-citation
  practice itself (IIA 14.1 / ISO 19011 / ADR). **M2 reframed**: required-explicit judge is a
  deliberate reproducibility divergence (promptfoo silently defaults its grader from ambient
  credentials — verified in docs + source). Two corrections applied: design v0.22 (the infra-only-retry
  rule re-stated as skillet's own discipline — no primary source states it) and **§14-11 staged**
  (additive `pass_1` reporting; τ-bench's unbiased estimator makes skillet's strict rule a deliberate
  conservative special case) → Candidate Enhancements. F16 (grounded judge) framed as closure of
  τ-bench's named "necessary but not sufficient" gap. §7-minors deferral confirmed (no urgency
  evidence; clig.dev silent on inert flags). Design doc → v0.23. No scope, feature, or priority change.
- v1.9.9 (2026-07-01): PATCH — **Phase-1 completed-items cross-artifact audit** →
  [Roadmap/phase-1-review.md](Roadmap/phase-1-review.md). Every F1–F8 metric verified against
  `Specs/001–007` + shipped code (235 tests green; free-only — the paid smoke not re-run):
  **Phase-1-COMPLETE stands**; F6 gaps C/D confirmed open, gap **#3 closed** (typed `harnessNotFound`
  what/why/fix at probe/preflight). Documentary drift reconciled: phase-doc F2/F6/F7 current-state
  lines; AGENTS (`Roadmap/` paths, LintKit in the banner, `.Cxx` test-target note, dump-help claim
  scoped to names); README (+F8); design → **v0.21** (§7.2 evals-2.0 row + run-record family +
  `scorecard.json` exclusion, §9.1 F50 annotations, §9.3 synthetic-goldens wording, §10
  consistency-block recompute, §14-4 shipped-state note, §14-8 F5→F45); docc walkthrough (no
  `--harness-path` yet; CI "when wired"); post-audit notes on all seven plans. **Staged, not
  applied** (audit §5): the CI workflow (constitution V — `.github/workflows/` is empty),
  judge-model required-explicit (§14-4 / constitution II), committed-record provenance
  (`judge_prompt_version`/`executor_binary_version`), and the constitution's stale swift-system
  note. No scope, feature, or priority change.
- v1.9.8 (2026-07-01): PATCH — **F7 review round 9** (judge trace-evidence conformance + reason tolerance +
  config test coverage). The text judge's prompt now carries the plan-specified compact trace summary —
  skill invocations + **tool-call names + files touched** (was skills only) — as **best-effort supporting
  context** (may be empty on live runs), with the workspace listing the sole authoritative existence oracle;
  `workspaceDiff` modification-detection stays with the F16 grounded judge so a live-degraded diff can't
  cause a false FAIL. The strict verdict parser tolerates a **missing `reason` key** (optional/defaulted) —
  a bare `{"verdict":"PASS"}` is a valid PASS, never flipped to FAIL over cosmetics. Added tests for the
  init template's F7 defaults and a config decode of `runs`/`judge` knobs. 235 tests green. No scope change.
- v1.9.7 (2026-06-30): PATCH — **F7 review round 8** (free-before-paid lint gate + judge/`-C`/forensics
  correctness). `run` now **enforces the shipped free error-tier lint** (`L001`/`L003`) before any spend —
  making the README's "free lint gates every paid run" real: after the eval loader (corrupt→4/missing→2
  preserved) and before dry-run/confirm/probe/cache, an error-tier finding refuses with **exit 2** and
  `skillet.lint/1` (command-contextual — `skillet lint`'s own finding stays exit 1); `doctor` still owns
  the broader Phase-2 preflight. The judge's **trusted criterion moved out of the untrusted evidence JSON**;
  `-C` is now validated by `harness list/info` (exit 3, was silently ignored); a symlinked `SKILL.md` is
  rejected before any read (exit 4); trial **forensics keep the raw output + partial verdicts on a
  parse/judge failure**; `grading.json` is documented in the frozen run-record family and the init template
  gains `runs.max_output_bytes`. 232 tests green. No scope/feature change.
- v1.9.6 (2026-06-30): PATCH — **F7 review round 7** (judge injection defense + capture/cache hardening).
  The text judge is hardened against prompt injection from the model under test: the untrusted output is
  presented as one JSON object (it can't spoof fake prompt sections), framed as untrusted data whose
  embedded instructions must be ignored, and the verdict must be strict JSON `{"verdict","reason"}` — a
  prose "PASS: …" no longer counts (fail-safe FAIL; prompt version v1→v2). The subprocess output-capture
  limit is now configurable (`runs.max_output_bytes`, default 64 MiB) so a large-but-valid `stream-json`
  session is no longer misread as a behavioral failure (a true infra class + retry stay F18). The
  `.skillet` cache path is symlink-confined before any write (exit 4), matching the round-5 skill guard.
  227 tests green. No scope/feature change.
- v1.9.5 (2026-06-30): PATCH — **F7 review round 6** (benchmark.json boundary honesty + cache hygiene).
  A compatibility audit against the **real** skill-creator eval-viewer + artifacts found the producer was
  retyping/overloading the frozen contract. `benchmark.json` `runs[].configuration` is now the **string**
  `"default"` (the viewer groups/color-codes on that exact value) instead of an object; `runs[]` is **one
  row per trial** (`run_number` + that trial's `expectations[]` + a `result` that counts *expectations*, not
  trials); and skillet's `pass^k` moved to the **additive `consistency` block** (the shape real artifacts
  established), which is also the offline recompute source (with numeric-`eval_id` coercion so real records
  aren't silently dropped). `run` now writes the self-owned `.skillet/.gitignore` before touching the cache
  (no accidental forensics commit even without a prior `init`), and the cache run path gains a uuid suffix
  (no same-second collision). 218 tests green. No scope/feature change.
- v1.9.4 (2026-06-30): PATCH — **F7 review round 5** (config strictness + path confinement). The
  config-consuming commands (`lint`, `harness info`, `run`) now load `skillet.yaml` through a shared
  **strict** loader — a present-but-undecodable repo config, or a missing/undecodable `--config`, fails
  loud (exit 2/4) instead of silently falling back to defaults. The skill dir + its `evaluations/` are
  **symlink-confined** before any read or write (a symlinked path → exit 4), so a committed symlink can't
  redirect a paid run's reads/writes outside the repo. The non-spending `claude auth status` preflight
  **fails closed** on malformed output (an unverifiable auth state never spends). `--json --dry-run` now
  emits the schema-tagged **`skillet.run-plan/1`** spend-free plan, and `benchmark.json` `runs[]` carry an
  additive `pass_rate`. 214 tests green. No scope/feature change.
- v1.9.3 (2026-06-29): PATCH — **F7 review round 4** (fixture / staging isolation). `files[]` now
  allowlists the fixture namespace: `fixtures/**` and `evaluations/fixtures/**` are model-visible, while
  everything else under `evaluations/**` (the eval definition, the run-record family, `sessions/`,
  `findings/`, `friction/`) is rejected (exit 4) — so an eval can't hand the model under test its own
  answers. Bundle + fixture staging switched to a recursive filtered copy that drops hidden files and
  symlinks at **any** depth (not just top-level), closing nested `.env`/`.git` leaks. Aligns with the
  inputs-vs-targets split in Inspect/lm-eval/promptfoo. 205 tests green. No scope/feature change.
- v1.9.2 (2026-06-28): PATCH — **F7 review round 3** (security hardening). Eval ids no longer
  path-traverse the `.skillet/runs` cache (index-based cache path; the real id stays in records);
  **symlinks are rejected** in eval `files[]` fixtures *and* the skill bundle (recursive — no symlink
  staged or followed, the escape/leak guard for a paid harness; the only symlinks in real skills are
  `.build` build-cruft, so zero migration cost); zero-expectation evals are rejected before spend
  (can't measure → exit 4) and a verdict-less trial never passes vacuously; the spend prompt requires
  **both** stdin and stdout to be a TTY (else fails like `--no-input`). Added the plan's
  evidence-asserting RunKit judge test. 201 tests green. No scope/feature change.
- v1.9.1 (2026-06-28): PATCH — **F7 review-round hardening** (post-merge code review). Confined eval
  `files[]` fixtures to the skill directory (reject absolute / `..` traversal — the standard path-traversal
  guard, since a paid harness reads committed evals); coerced **numeric** eval ids into records (were
  dropped to positional ids); rejected `--runs < 1` as a usage error; made a **judge-subprocess failure
  an ungraded trial**, not a false criterion FAIL; switched skill staging to a **denylist** (exclude
  `evaluations/` + hidden `.skillet`/`.git`/`.env`) — keeps real skills' non-standard bundle dirs
  (`agents/`, `fixtures/`, `eval-viewer/`) a fixed allowlist would have dropped; refreshed stale test
  counts. 195 tests green. No scope/feature change.
- v1.9.0 (2026-06-28): MINOR — **Phase 1 COMPLETE: F7 (`skillet run`) implemented**, closing the
  walking skeleton. The neutral runner runs a skill's evals k×/eval in fresh sandboxes, grades each
  expectation with a `claude-code`-backed text judge (existence/claim-mismatch via the post-run
  workspace listing + trace), and reports aggregate `pass^k` at observed k = `min` recorded — pure in
  `EDDCore` and **recomputable offline from the committed `evaluations/benchmark.json`** (P2/D3). New
  targets `RunKit` + `JudgeKit`; spend is estimated up front and gated (`confirm_above_trials`/`--yes`/
  `--no-input`/`-n`,`--dry-run`, design P9); exit codes `0/1/2/3/4`; the live claude-code path is one
  opt-in env-gated smoke (free CI uses a replay seam). `Specs/007`; 179 tests green. Phase 1 → **Foundation/COMPLETE**,
  Phase 2 → **Now**. (Per-feature impl was historically PATCH; bumped MINOR for the horizon shift.)
- v1.8.0 (2026-06-26): MINOR — **moved `doctor` (F3) from Phase 1 to Phase 2** and **reconciled the
  `Fn` identifier scheme across all phases**. `doctor` is off the walking-skeleton critical path (F7
  `run` doesn't depend on it) and its companions — the `--paid` canary, the full lint catalog, and
  `config list --origins` — are all Phase 2; so F7 becomes Phase 1's only remaining feature. The
  scheme reconciliation adopts one global, stable, never-reused, position-independent `Fn` counter (new
  *Feature identifiers* section), grounded in stable-ID best practice (Sparx EA, RTEMS req-for-req, Jira
  — assign-once / never-renumber / don't-encode-position; links in that section). Minimal-churn: Phase 1's `F1–F8` and
  Phase 8's `F10–F13` were already global and were **preserved** (so design/AGENTS/Specs/back-changelog
  references stay valid); the local-ordinal Phases 2–7 and Phase 8 items 1–9 received global ids
  `F14–F60`; `doctor` keeps `F3`; `F9` is a retired gap. Also **re-deferred the three frontmatter
  spec-conformance rules** (name kebab/length, allowed-keys, duplicate-key rejection) from `doctor` to
  Phase 2's full lint catalog (F20) — they still surface in `doctor` once they're lint rules. No v1
  scope change; no `plan.md` yet (authored at implementation time).
- v1.7.1 (2026-06-25): PATCH — Phase 1 **F4 (`skillet lint`) implemented**: the free static gate —
  `SKILL-L001` (description >1024 Unicode code points, matching Anthropic's `quick_validate.py`),
  `SKILL-L003` (body-line budget), `SKILL-L009` (has-evals, ≥3) — as a pure `LintKit` over a
  `SkillSource` the executable assembles; `skillet lint` exits 1 on any error-tier finding
  (`skillet.lint/1`). Also corrected the stale Global Risks line (F8 was already done; 122 tests;
  `Specs/001`–`006`). Phase 1 stays IN PROGRESS (F3 `doctor`, F7 `run` open). Plan:
  [Specs/005](Specs/005-free-static-lint/plan.md).
- v1.7.0 (2026-06-24): MINOR — added **Phase 8 F13 — skill-bundle integrity lint group** (static
  checks that bundled `scripts/` are self-contained / non-interactive / `--help`-capable, that
  referenced script/asset paths resolve, and that no files are orphaned or outside the spec dirs) —
  the second cross-reference lint group beside F12, from Skill-Lab's Structure/Content bundle checks
  + AWS `skill-eval`'s skill-standard-directory scan; no settled-decision touch. Also synced the
  stale **Phase 8 overview bullet** to name the security + bundle-integrity groups (design→roadmap
  drift surfaced by the F12/F13 adds). Design doc → v0.11 (§13 v1.x). No v1 scope change.
- v1.6.0 (2026-06-24): MINOR — **adopted held-out proof (R2 / design §14-8)** and graduated it from
  *Candidate Enhancements* into **Phase 6 (new F5 [now F45])**: a `skill_md` edit is `proven` only when a
  held-out sibling eval (same failure class, not the one it was drafted from) also passes — guarding
  against overfit proof and hardening the *corroboration integrity* outcome. Encoded in design §8
  (Held-out proof gate), §5.2 (`gates.proof.require_holdout`, default on; advisory per D6, enforced
  under `--strict`), §6.1 `iterate --mark`; design doc → v0.10. §14-9/§14-10 stay parked.
- v1.5.0 (2026-06-24): MINOR — acted on the v0.8 competitive cross-reference under a **strict
  evidence bar**. Added **Phase 8 F12 — skill-security lint rules** (security tier in the
  `SKILL-Lxxx` catalog: prompt-injection, evaluator-manipulation, unicode-obfuscation,
  YAML-anomaly, suspicious-size; from Skill-Lab + AWS `skill-eval` + SkillTester) — the one finding
  with no settled-decision touch. **Staged three more as design open questions** (not in the phase
  plan until decided), mirrored in the new *Candidate Enhancements* section: §14-8 held-out proof
  (R2), §14-9 process-assertions over the `Trace` (R3 + R7 sub-question), §14-10 ablation arms (R5).
  Evaluated and **deferred** three: failure-clustering in triage (single, uncertain source —
  revisit when Phase 4 is built), a microsoft/skills fixture corpus (a testing asset, not a
  research-revealed gap), and reinforcing the autonomous-optimizer non-goal (already covered by the
  v0.8 §1 / Appendix C edits). Design doc → v0.9. No v1 scope change.
- v1.4.2 (2026-06-24): PATCH — **trademark risk narrowed** from the v0.8 design-doc
  competitive cross-reference: a June-2026 GitHub sweep found no `skillet` name collision *inside
  the eval space* (only PAN's non-eval product family conflicts), so the Global Risks trademark
  bullet is updated. Risk register only — the pre-launch trademark check still stands; no phase,
  feature, or priority change.
- v1.4.1 (2026-06-21): PATCH — Phase 1 **F6 (claude-code adapter) implemented** (validatable core):
  `ClaudeCodeAdapter` (native-JSONL→`Trace` parser, golden vs a synthetic fixture), `BinaryResolver`,
  `Denylist`, and `probe`/`verifySkillVisibility` behind a fakeable launcher; live `run` stays F7.
  `swift-yaml` wired isolated in a new `.Cxx` `ConfigYAML` target (kits + pure core stay interop-free;
  the executable is a `.Cxx` leaf, per the interop spike). Phase 1 stays IN PROGRESS (F4/F3/F8/F7 open).
- v1.4.0 (2026-06-21): MINOR — Phase 1 F6/F7 scope re-attributed: claude-code's **live `run`
  execution + skill-injection** moved from F6 to F7 (where the opt-in env-gated smoke and a real
  claude-code can validate it), because claude-code isn't runnable in this dev/CI environment and the
  predecessor port is absent. F6 keeps the validatable core (native-JSONL→`Trace` parser, binary
  resolution, denylist, and the `probe`/`verifySkillVisibility` seam). Build order and **Fn** ids
  unchanged. Detail in `Roadmap/phase-1-walking-skeleton.md`.
- v1.3.0 (2026-06-21): MINOR — Phase 1 re-sequenced to a dependency-honest build order:
  `skillet doctor` (F3) moved after the HarnessAdapter seam (F5) + claude-code adapter (F6),
  because `doctor`'s `probe()`/`verifySkillVisibility` are adapter methods (design §9.1) and it
  also needs `swift-yaml` + error-tier lint (F4). New build order: F1, F2, F5, F6, F4, F3, F8, F7
  (feature **Fn** ids unchanged — stable across specs and Package targets). Also marked Phase 1
  IN PROGRESS and corrected the now-stale "no implementation" assumption (F1/F2 shipped:
  `Specs/001`, `Specs/002`). No scope change.
- v1.2.0 (2026-06-18): MINOR — added **capture secret-sanitization** to Phase 3 (F7 [now F32]):
  redact-in-place before write, bundled `betterleaks` (MIT) run offline, fail-closed
  when unavailable. Closes the commit-secrets footgun; extends design §12 privacy
  (§6.1/§7.2/§11/§12 updated, doc → v0.4).
- v1.1.0 (2026-06-18): MINOR — added **user-authored declarative YAML lint rules**
  to Phase 8 (F11) — a bounded, ReDoS-guarded extensibility capability — governed by
  the new design §7.6 "YAML usage policy" (litmus test + verdict table). No existing
  phases or priorities changed.
- v1.0.1 (2026-06-18): PATCH — config file is now `skillet.yaml` (was
  `skillet.toml`) in Phase 1 references, matching the design decision to adopt YAML
  via the `swift-yaml` package and drop the TOML dependency. No phases, features,
  or priorities changed.
- v1.0.0 (2026-06-17): Initial roadmap created from `skillet-design.md`
  (Northstar §1, command surface §6, v1 scope line §13, architecture §11) plus an
  external best-practice cross-reference — EDD / error-analysis (Hamel Husain &
  Shreya Shankar), AI-agent eval guidance (Anthropic, *Demystifying evals for AI
  agents*), the Now/Next/Later framework (ProdPad), and walking-skeleton MVP
  sequencing. Horizons are dependency-honest with the Northstar as tie-breaker;
  items are capability-centric, anchored to testable CLI increments, and tagged
  Ported/Net-new; full arc (v1 → v1.x → Later, plus explicit Non-Goals).
