# Product Roadmap — skillet

**Version:** v1.12.0
**Last Updated:** 2026-07-04

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
| Now | 2 | Trustworthy Measurement & Static Gates | IN PROGRESS | [phase-2](Roadmap/phase-2-measurement-static-gates.md) |
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
  `pass^k`, `RunKit`+`JudgeKit`) — `Specs/001`–`007`, 235 tests green. **Phase 2 is IN PROGRESS —
  F3 (`skillet doctor`) + F14 (the trigger axis) shipped 2026-07-04 (`Specs/008`–`009`, 292 tests green)**; the remaining Phase 2–8
  features are PLANNED/FUTURE: those statuses reflect design intent verified against the design doc
  (Medium confidence), not running code.
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
- **Upstream dependency watch — `swift-system` / SE-0529 (design §14-12).** The direct
  `swift-system` declaration (`exact: 1.5.0` + the `SystemPackage` product on
  `HarnessKit`/`IntegrationTests`) is **deliberate**: Ubuntu (day-one platform) has no SDK
  `System` module, `swift-subprocess` links `SystemPackage` unconditionally either way (zero
  savings from removal), and the exact pin keeps `swift package update` from floating the
  transitive to an untested 1.7.x. Removal is a **decided deferral** (2026-07-03): it fires when
  **T1** the minimum toolchain ships SE-0529's stdlib `FilePath` (accepted 2026-06) **and**
  **T2** the pinned `swift-subprocess` release consumes it — then the `.package` line, both
  product entries, and the two `#if canImport(System)` imports all go.
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

Full history: [ROADMAP-changelog.md](ROADMAP-changelog.md) — v1.0.0 → v1.12.0, latest first, one
linkable heading per version (extracted 2026-07-04; historical entries are never rewritten).

- **Latest — v1.12.0 (2026-07-04): MINOR** — **F14 `skillet run --axis trigger` SHIPPED**: the
  deterministic description axis over whole-corpus frontmatter stubs; per-axis `benchmark.json`
  merge; additive `skillet.run/1` `trigger` block. (Prior: v1.11.1 — changelog extraction;
  v1.11.0 — F3 `skillet doctor` shipped, Phase 2 → IN PROGRESS.)
