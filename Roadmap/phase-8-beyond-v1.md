# Phase 8 — Beyond v1: Deeper Analysis, Broader Reach

**Status:** FUTURE
**Horizon:** Later
**Last Updated:** 2026-07-07

## Goal

Once the v1 loop is proven end-to-end, deepen the analysis (paid axial coding,
real spend numbers, judge calibration) and broaden reach (more adapters, more lint
rules). Deliberately fuzzy: each item carries a name and a purpose, not five
metrics that would be fiction before the item is promoted. This phase also records
the explicit non-goals so scope stays honest.

## Key Features (name + purpose; detail backfilled on promotion)

1. **[F52]** Track B — axial coding of corrective turns (CLI: `skillet triage --code-feedback`) — FUTURE · Net-new
   - Purpose & user value: Paid, judge-driven open→axial coding of the corrective
     turns captured with `--preserve-feedback` — grouping *observed* corrections by
     root cause (it never invents failures). Deepens Northstar gap #1.
   - Confidence: Medium — design §6.1 `triage`, §9.3.
   - Diagnostic-tier lane (F67, design §9.6): Apple's Private Cloud Compute model is a candidate
     coder — explicit opt-in, never a default; the session corpus stays inside Apple's privacy
     envelope and corpus-scale coding becomes $0 (§14-20).

2. **[F53]** Diff-revert corrective-turn detector — FUTURE · Net-new
   - Purpose & user value: The second half of corrective-turn detection — flag user
     turns whose subsequent diff reverts assistant-written hunks — beyond today's
     text-pattern heuristic. Confidence: Medium — design §9.3.

3. **[F54]** codex adapter (CLI: `--harness codex`) — FUTURE · Net-new
   - Purpose & user value: A third agent for a bigger audience and a stronger matrix.
     Confidence: Low — depends on Open Question 1. `needs-research`

4. **[F55]** opencode session capture — FUTURE · Net-new
   - Purpose & user value: Extend `capture` to a second harness's native session
     store. Confidence: Medium — design §9.5.

5. **[F56]** Fixtures scaffolding (CLI: `skillet eval new --fixture`) — FUTURE · Net-new
   - Purpose & user value: Generate the synthetic-package fixtures that evals run
     against. Confidence: Medium — design §13.

6. **[F57]** The 7 roadmap lint rules — FUTURE · Net-new
   - Purpose & user value: Extend the catalog (name↔directory match, reserved
     `anthropic-*`/`claude-*` prefixes, third-person what+when voice, ALWAYS/NEVER
     density, reference-extraction candidates, dead reference links). Several
     collapse into **data rules** once F11 lands; the semantic ones (voice,
     extraction) stay Swift. Confidence: Medium — design §6.1 `lint`.

7. **[F58]** Variance dashboards — FUTURE · Net-new
   - Purpose & user value: Visualize `pass^k` variance across historical runs so
     "did it really improve?" has a richer answer than one number. Confidence:
     Medium — design §13.

8. **[F59]** `lint --fix` — FUTURE · Net-new
   - Purpose & user value: Auto-apply mechanical lint fixes. Confidence: Medium —
     design §13.

9. **[F60]** Real spend numbers — `Trace.usage` parsing in the claude-code adapter — FUTURE · Net-new
   - Purpose & user value: Parse the stream's per-message usage / `total_cost_usd`
     (discarded today) into `Trace.usage` so estimates and the spend column show
     real numbers instead of trial-count fallbacks. Confidence: Medium — design §9.3.

10. **[F10]** Judge↔human agreement check (CLI: `skillet calibrate`, name provisional) — FUTURE · Net-new
    - Purpose & user value: Validate the LLM judge against human judgment with a concrete,
      report-only workflow: a human labels a sample of already-graded outputs (one greenfield
      labels file, design §7.3 conventions); skillet computes chance-corrected agreement
      (**Cohen's kappa**, the F65 catalog's `agreement` entry) per criterion/dimension and
      prints it — documented target **≥ 0.6**. Advisory only; wiring into the §8 trust gates
      is a later, separate decision. Replaces the prior `needs-research` framing with the
      recipe Apple shipped (WWDC26 335: labeled extraction → kappa → few, small worked
      examples as the low-agreement fix) — the judge-overconfidence and criteria-drift risks
      it addresses are unchanged.
    - Confidence: Medium — design §14-14 (decided 2026-07-06, report-only); Appendix D sources.
    - Also the diagnostic tier's gatekeeper (F67, design §9.6): no free-judge lane (F62/F68 judging
      uses) turns on below κ ≥ 0.6 agreement (§14-19).

11. **[F11]** User-authored declarative lint rules (YAML) — FUTURE · Net-new
    - Purpose & user value: Let maintainers add repo-local `SKILL-Lxxx` rules as
      data — a regex / threshold / presence matcher in YAML — without recompiling,
      so teams encode and share house style the way Vale and Semgrep do.
    - Success metrics:
      - A rule is a fixed, code-backed *kind* (`match` / `absence` / `occurrence` / `length` / `file-exists`) + pattern + scope + tier + message, riding the same SARIF emit + `lint.disable` exemption machinery as built-in rules.
      - Patterns run on a linear-time engine (or a per-match timeout) and rule files are schema-validated on read — no ReDoS, and no `script:` escape hatch (that's a Swift rule).
    - Confidence: Medium — precedent (Vale, Semgrep) + the design's §7.6 YAML usage policy; bounded by its litmus test and tripwire.
    - Notes: Governed by design §7.6; repo-local rule IDs use a reserved range (e.g. `L2xx`). Subsumes the data-expressible subset of F57.

12. **[F12]** Skill-security lint rules (security tier in the `SKILL-Lxxx` catalog) — FUTURE · Net-new
    - Purpose & user value: Static, deterministic-first security checks over the SKILL.md file —
      prompt-injection phrasing, evaluator/judge manipulation, unicode obfuscation, YAML
      front-matter anomalies, and suspicious size — so a skill is screened for adversarial content
      before it is trusted or shipped. Runs free, before any paid judge.
    - Confidence: Medium — competitive cross-reference (Skill-Lab's 5 security checks; AWS
      `skill-eval` static security scan; SkillTester's security benchmark); design §6.1 `lint`, §13.

13. **[F13]** Skill-bundle integrity lint group — FUTURE · Net-new
    - Purpose & user value: Static checks over a skill's *bundle*, beyond its `SKILL.md` prose —
      that bundled `scripts/` are self-contained, non-interactive, and `--help`-capable; that
      referenced script/asset paths resolve; and that no files are orphaned or outside the spec
      dirs — so a skill ships as a coherent, runnable package, not just well-written prose. Free,
      deterministic, before any paid judge.
    - Confidence: Medium — competitive cross-reference (Skill-Lab's Structure/Content bundle checks;
      AWS `skill-eval`'s skill-standard-directory scan); the agentskills.io `scripts/`/`references/`
      structure; design §6.1 `lint`, §7.1, §13.

14. **[F64]** General synthetic eval generator (both axes) — FUTURE · Net-new
    - Purpose & user value: Extend F63's observed-seed expansion to behavioral evals: grow
      datasets from real captured seeds under the same rules — a `synthetic` provenance marker
      naming the seed, deterministic per-sample validators with rejects tracked,
      coverage-over-count sizing. Never generates from a blank page (design §14-15's
      load-bearing rule).
    - Confidence: Medium — design §14-15 (decided 2026-07-06); precedent: Apple
      `SampleGenerator`, DeepEval Synthesizer.
    - Diagnostic-tier lane (F67, design §9.6): Apple's Private Cloud Compute model is the candidate
      generator (32K context, structured trajectory output) — explicit opt-in, entitlement lane,
      never a default (§14-20).

15. **[F65]** Named aggregation catalog — FUTURE · Net-new
    - Purpose & user value: Fixed, Swift-implemented, config-invoked aggregations over numeric
      metrics — `mean` / `min` / `max` / `stddev` / `median` / `percentile(p)` / `sum` /
      `count` / `agreement` — attachable as thresholds where a gate already exists; grows by
      PR, never a config formula language (the versioned per-trial JSON is the custom-math
      escape hatch). Serves F61's partial-credit percentage, F62's dimension scores, and
      F10's kappa; pulls forward if their reporting demands it.
    - Confidence: Medium — design §14-17 (decided 2026-07-06); mirrors F11's fixed
      code-backed *kinds* stance.

16. **[F66]** Test-framework integration recipe (docs) — FUTURE · Net-new
    - Purpose & user value: A short documented recipe for running skillet inside any test
      framework — Swift Testing, pytest, bare CI — by shelling `skillet run --json` and
      asserting on the payload + exit codes; the `--json` + exit-code contract *is* the
      integration surface. Companion to the declined Swift-library surface (non-goal below).
    - Confidence: High — design §14-18 (decided 2026-07-06); docs-only.

17. **[F67]** Diagnostic model tier — the provider-neutral cheap-model slot (config: `models.diagnostic`) — FUTURE · Net-new
    - Purpose & user value: One slot and one contract (design §9.6) for every model whose output
      informs but never gates: generation (F63/F64), scoring (F62), clustering (F52), the F14
      smoke arm. Cheap/local providers may fill it; a platform default may fill it only with a
      $0/offline/entitlement-free provider and always announces itself (plan note + `doctor` row).
      Deliberately **not Apple-only**: providers are plugs — Apple first (F68), cross-platform
      local runners (Ollama-class) the research alternative.
    - Confidence: Medium — design §14-19 (decided 2026-07-07), §9.6.
    - Notes: Pulls forward to land with its first consumer (F62, Phase 4).

18. **[F68]** Apple Foundation Models provider (on-device + Private Cloud Compute) — FUTURE · Net-new · `needs-research`
    - Purpose & user value: The first plug for F67. On macOS the unconfigured diagnostic slot
      defaults to the $0/offline on-device model — compiled behind `#if canImport(FoundationModels)`
      (an OS framework: zero new dependencies; Linux and older SDKs compile the lane out), with
      runtime availability checks. The Private Cloud Compute model (32K context, reasoning, $0
      tokens) is an explicit build-from-source lane and **never a default** (managed entitlement,
      per-user iCloud quota, network). Adds `doctor`/plan quota rows via `quotaUsage`.
    - Research exit-conditions (design §14-20): PCC-entitlement viability for CLI tools (and who
      can hold it); Apple Intelligence inside CI VMs; SDK/OS timeline; measured skill context-fit
      rates vs the 4–8K on-device window; available OS/model-build provenance identifiers.
    - Confidence: Low until research clears — design §14-20 (decided 2026-07-07); Appendix D sources.

## Non-Goals (explicitly out of scope)

- **Description-optimizer loop** — owned by skill-creator; revisit only if that changes.
- **Watch mode** — continuous background re-runs.
- **GitHub Action wrapper** — CI integration via `--strict` exit codes is enough for v1.
- **TUI** — the CLI + HTML report cover the surface.
- **A public Swift library / test-trait surface** — declined 2026-07-06 (design §14-18): the
  CLI + `--json` is the contract; the §11 kit layout keeps the option open (a future
  `.library` product is a one-line manifest change) without promising API stability. F66
  documents the supported integration path; revisit only on demonstrated demand.
- **Any auto-commit, ever** — the human owns every commit (design P5, absolute).

## Phase Metrics & Success Criteria

- This phase is intentionally not metric'd in detail. Each item gets full
  success metrics when it is promoted into a Now/Next horizon.

## Risks & Assumptions

- Items here are named from the design doc's v1.x / Later columns plus the
  cross-reference additions — F10–F13 (v0.8 competitive round) and F64–F68
  (July-2026 Apple Evaluations rounds); priorities will shift as v1 usage data
  arrives — the first real source of `High`-confidence prioritization this
  roadmap will have.

## Phase Change Log

- 2026-06-17: Phase created from the design §13 v1.x + Later columns and the
  explicit non-goals; added the judge↔human-label calibration harness (F10) from
  the best-practice cross-reference as a `needs-research` item.
- 2026-06-18: Added F11 (user-authored declarative YAML lint rules), governed by
  the new design §7.6 YAML usage policy; noted the F6 [now F57] overlap. Roadmap MINOR → v1.1.0.
- 2026-06-24: Added F12 (skill-security lint rules) from the v0.8 competitive cross-reference
  (Skill-Lab / AWS `skill-eval` / SkillTester); no settled-decision touch. Roadmap MINOR → v1.5.0.
- 2026-06-24: Added F13 (skill-bundle integrity lint group — `scripts/`/asset/reference checks)
  from the Skill-Lab cross-reference (its Structure/Content bundle checks; AWS `skill-eval`); no
  settled-decision touch. Roadmap MINOR → v1.7.0.
- 2026-06-26: PATCH — adopted the global stable Fn ids (items 1–9 → F52–F60; the already-global F10–F13 preserved; roadmap v1.8.0 scheme reconciliation). Mechanical renumber; no scope change.
- 2026-07-06: MINOR — Apple Evaluations cross-reference: **F10 re-specified** (report-only
  judge↔human kappa agreement check; `needs-research` dropped — design §14-14), added **F64**
  (general observed-seed synthetic generator, §14-15), **F65** (named aggregation catalog,
  §14-17), **F66** (test-framework integration recipe, §14-18); non-goals gain the declined
  Swift-library surface (§14-18). Roadmap → v1.13.0.
- 2026-07-07: MINOR — added **F67** (diagnostic model tier, design §14-19/§9.6: informs-never-gates
  contract, `models.diagnostic` slot, announced platform defaults, provider-neutral) and **F68**
  (Apple Foundation Models provider, §14-20, `needs-research`: macOS on-device zero-config default,
  PCC never defaults, research exit-conditions listed); diagnostic-tier lane notes on F10/F52/F64.
  Roadmap → v1.14.0.
- 2026-07-07: PATCH — risks text now names all cross-reference additions (F10–F13, F64–F68)
  instead of "one" (review finding; `needs-research` is reserved for F68). Roadmap → v1.14.1.
