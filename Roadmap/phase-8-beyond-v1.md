# Phase 8 — Beyond v1: Deeper Analysis, Broader Reach

**Status:** FUTURE
**Horizon:** Later
**Last Updated:** 2026-06-18

## Goal

Once the v1 loop is proven end-to-end, deepen the analysis (paid axial coding,
real spend numbers, judge calibration) and broaden reach (more adapters, more lint
rules). Deliberately fuzzy: each item carries a name and a purpose, not five
metrics that would be fiction before the item is promoted. This phase also records
the explicit non-goals so scope stays honest.

## Key Features (name + purpose; detail backfilled on promotion)

1. Track B — axial coding of corrective turns (CLI: `skillet triage --code-feedback`) — FUTURE · Net-new
   - Purpose & user value: Paid, judge-driven open→axial coding of the corrective
     turns captured with `--preserve-feedback` — grouping *observed* corrections by
     root cause (it never invents failures). Deepens Northstar gap #1.
   - Confidence: Medium — design §6.1 `triage`, §9.3.

2. Diff-revert corrective-turn detector — FUTURE · Net-new
   - Purpose & user value: The second half of corrective-turn detection — flag user
     turns whose subsequent diff reverts assistant-written hunks — beyond today's
     text-pattern heuristic. Confidence: Medium — design §9.3.

3. codex adapter (CLI: `--harness codex`) — FUTURE · Net-new
   - Purpose & user value: A third agent for a bigger audience and a stronger matrix.
     Confidence: Low — depends on Open Question 1. `needs-research`

4. opencode session capture — FUTURE · Net-new
   - Purpose & user value: Extend `capture` to a second harness's native session
     store. Confidence: Medium — design §9.5.

5. Fixtures scaffolding (CLI: `skillet eval new --fixture`) — FUTURE · Net-new
   - Purpose & user value: Generate the synthetic-package fixtures that evals run
     against. Confidence: Medium — design §13.

6. The 7 roadmap lint rules — FUTURE · Net-new
   - Purpose & user value: Extend the catalog (name↔directory match, reserved
     `anthropic-*`/`claude-*` prefixes, third-person what+when voice, ALWAYS/NEVER
     density, reference-extraction candidates, dead reference links). Several
     collapse into **data rules** once F11 lands; the semantic ones (voice,
     extraction) stay Swift. Confidence: Medium — design §6.1 `lint`.

7. Variance dashboards — FUTURE · Net-new
   - Purpose & user value: Visualize `pass^k` variance across historical runs so
     "did it really improve?" has a richer answer than one number. Confidence:
     Medium — design §13.

8. `lint --fix` — FUTURE · Net-new
   - Purpose & user value: Auto-apply mechanical lint fixes. Confidence: Medium —
     design §13.

9. Real spend numbers — `Trace.usage` parsing in the claude-code adapter — FUTURE · Net-new
   - Purpose & user value: Parse the stream's per-message usage / `total_cost_usd`
     (discarded today) into `Trace.usage` so estimates and the spend column show
     real numbers instead of trial-count fallbacks. Confidence: Medium — design §9.3.

10. Judge↔human-label calibration harness — FUTURE · Net-new
    - Purpose & user value: Validate the LLM judge against a human-labeled golden
      set (agreement / sensitivity / specificity), beyond today's scorer↔judge
      contradiction alarm — addressing the documented judge-overconfidence and
      criteria-drift risks. Confidence: Low — net-new, not in the v1 design; added
      from the best-practice cross-reference. `needs-research`

11. User-authored declarative lint rules (YAML) — FUTURE · Net-new
    - Purpose & user value: Let maintainers add repo-local `SKILL-Lxxx` rules as
      data — a regex / threshold / presence matcher in YAML — without recompiling,
      so teams encode and share house style the way Vale and Semgrep do.
    - Success metrics:
      - A rule is a fixed, code-backed *kind* (`match` / `absence` / `occurrence` / `length` / `file-exists`) + pattern + scope + tier + message, riding the same SARIF emit + `lint.disable` exemption machinery as built-in rules.
      - Patterns run on a linear-time engine (or a per-match timeout) and rule files are schema-validated on read — no ReDoS, and no `script:` escape hatch (that's a Swift rule).
    - Confidence: Medium — precedent (Vale, Semgrep) + the design's §7.6 YAML usage policy; bounded by its litmus test and tripwire.
    - Notes: Governed by design §7.6; repo-local rule IDs use a reserved range (e.g. `L2xx`). Subsumes the data-expressible subset of F6.

## Non-Goals (explicitly out of scope)

- **Description-optimizer loop** — owned by skill-creator; revisit only if that changes.
- **Watch mode** — continuous background re-runs.
- **GitHub Action wrapper** — CI integration via `--strict` exit codes is enough for v1.
- **TUI** — the CLI + HTML report cover the surface.
- **Any auto-commit, ever** — the human owns every commit (design P5, absolute).

## Phase Metrics & Success Criteria

- This phase is intentionally not metric'd in detail. Each item gets full
  success metrics when it is promoted into a Now/Next horizon.

## Risks & Assumptions

- Items here are named from the design doc's v1.x / Later columns plus one
  cross-reference addition (F10); priorities will shift as v1 usage data arrives —
  the first real source of `High`-confidence prioritization this roadmap will have.

## Phase Change Log

- 2026-06-17: Phase created from the design §13 v1.x + Later columns and the
  explicit non-goals; added the judge↔human-label calibration harness (F10) from
  the best-practice cross-reference as a `needs-research` item.
- 2026-06-18: Added F11 (user-authored declarative YAML lint rules), governed by
  the new design §7.6 YAML usage policy; noted the F6 overlap. Roadmap MINOR → v1.1.0.
