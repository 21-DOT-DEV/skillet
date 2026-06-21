# Product Roadmap — skillet

**Version:** v1.2.0
**Last Updated:** 2026-06-18

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
| Now | 1 | Walking Skeleton — prove the loop end-to-end | PLANNED | [phase-1](Roadmap/phase-1-walking-skeleton.md) |
| Next | 2 | Trustworthy Measurement & Static Gates | PLANNED | [phase-2](Roadmap/phase-2-measurement-static-gates.md) |
| Next | 3 | Discovery & Evidence Capture | PLANNED | [phase-3](Roadmap/phase-3-discovery-evidence.md) |
| Next | 4 | Error Analysis — *Northstar gap #1* | PLANNED | [phase-4](Roadmap/phase-4-error-analysis.md) |
| Next | 5 | The Computable Runbook — *differentiator #1* | PLANNED | [phase-5](Roadmap/phase-5-computable-runbook.md) |
| Next | 6 | Fix Suggestion & Safe Iteration — *Northstar gap #2* | PLANNED | [phase-6](Roadmap/phase-6-fix-suggestion-iteration.md) |
| Next | 7 | Multi-Harness Portability — *differentiator #2* | PLANNED | [phase-7](Roadmap/phase-7-multi-harness.md) |
| Later | 8 | Beyond v1 — deeper analysis, broader reach | FUTURE | [phase-8](Roadmap/phase-8-beyond-v1.md) |

- **Phase 1 (Now):** The thinnest end-to-end thread — `skillet run` one eval
  through `claude-code`, judged, with a `pass^k` result — plus just-enough
  `init`/`doctor`/`lint`. Proves the architecture and delivers 30-second value.
- **Phase 2 (Next):** Make deltas trustworthy — trigger axis, A/B baseline,
  grounded judge, scorers, flaky hygiene, record/replay, the full free
  static-gate catalog, and TTY/HTML reporting.
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
  rules, **user-authored (YAML) lint rules**, real spend numbers, a judge↔human-label
  calibration harness — plus the explicit non-goals.

## Product-Level Metrics & Success Criteria

- **Time-to-first-signal** — a fresh skills repo gets a with-skill `pass^k` from
  a single `skillet run`, with zero manual skill-path configuration.
- **Loop cycle time** — median elapsed time from a captured friction event to a
  proven, ready-to-land proposal.
- **Corroboration integrity** — 100% of `SKILL.md` edits shipped via skillet are
  backed by a previously-failing eval that now passes.
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

- **Greenfield repo.** Only `skillet-design.md` and stub `README`/`LICENSE` exist
  today; no implementation. All phases are therefore PLANNED/FUTURE — there is no
  COMPLETE Foundation phase. Statuses reflect design intent verified against the
  design doc (Medium confidence), not running code.
- **"Ported" assumption.** The design doc says much of v1 is faithfully
  translated from a predecessor (`swift-skill-eval` + a Python trigger harness).
  That predecessor is not in this repo, so `Ported` tags are a scheduling hint,
  not a verified status; per design §13 the schedule risk concentrates in the
  `Net-new` column.
- **Open questions resolved to doc defaults.** Design §14 choices are assumed at
  their stated defaults (`opencode` as the second adapter; Apache-2.0;
  required-explicit judge model; static `concurrency` knob). Items resting on
  these carry `needs-research`.
- **Trademark risk.** Palo Alto Networks ships a "Skillet" product family (design
  Appendix C / Open Q1); a public launch needs a trademark sanity check first.
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

## Change Log

- v1.2.0 (2026-06-18): MINOR — added **capture secret-sanitization** to Phase 3 (F7):
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
