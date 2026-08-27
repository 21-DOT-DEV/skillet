# Phase 8 — Beyond v1: Deeper Analysis, Broader Reach

**Status:** FUTURE
**Horizon:** Later
**Last Updated:** 2026-08-16

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

9. **[F60]** Real spend numbers — token counting in the claude-code adapter — **PARTLY DONE** 2026-08-21
   - Purpose & user value: read the token counts the session reports, so estimates and the spend
     column show real numbers instead of standing in for them with a count of attempts.
     Confidence: Medium — design §9.3.
   - **Done 2026-08-21 — the counting half.** Every reply a session reports carries what it read and
     wrote; those lines were already being read and the counts thrown away. They are now read per kind
     and totalled: `total_tokens` plus `input_uncached_tokens`, `input_cache_read_tokens`,
     `input_cache_write_tokens` and `output_tokens`, written per run in the saved results file, with a
     `total_tokens` difference between the two runs of a comparison when both counted. Absent
     everywhere nothing counted, which replaced a made-up zero.
     - **No field is named `input_tokens`, deliberately.** Anthropic's API uses that name for the input
       that was *not* served from its cache; the OpenTelemetry telemetry convention uses the same name
       for the whole input. Adding cache counts on top of a figure that already includes them roughly
       doubles the answer — filed as Langfuse issue 12306, closed as the consumer's fault because both
       producers were behaving as documented. Every field here says what it holds.
     - **Only the roll-up gets a difference.** How much a model read is stable whether or not the
       provider's cache was warm, so a difference in it is attributable to the skill. The
       cached-versus-fresh split is not, so it is reported per run and never differenced.
   - **Left to do — the spend half.** No money figure is published. Turning these counts into a bill
     needs per-token-type prices: a cache read costs a fraction of fresh input and an Anthropic cache
     write costs 1.25× or 2× it, so a single price per token would be wrong in both directions. The
     counts are published in the shape that makes that computable by whoever has the prices.

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

12. **[F72]** Domain-specific output scorers — the bring-your-own-check layer (`SKILL-S2xx`) — FUTURE · Net-new
    - Purpose & user value: Let a repo add its **own** deterministic checks over a skill's
      *produced output*, so domain rules that only make sense for one skill can run without
      being baked into the tool. F17 shipped only the general writing-quality checks
      (`SKILL-S001`–`S006`; `SKILL-S000` file-unreadable and `SKILL-S007` findings-file validity
      also ship, but are coverage/infrastructure rules rather than writing-quality ones, so all
      eight ids are taken) and deliberately deferred the predecessor's domain-specific ones —
      citation freshness, article-shape and symbol-shape diffs, catalog-scaffold repeatability,
      reader-test-performed, single-purpose-gate-respected. **This entry is that deferral's
      owner**; without it those six capabilities are an orphaned regression against the
      predecessor CLI. The output-side sibling of **F11** (user-authored rules over SKILL.md
      *source*): F11 checks what the skill *says*, this checks what the skill *produced*.
    - Northstar: deterministic-first (more free signal before any paid judging).
    - Success metrics:
      - A repo-local check emits `SKILL-S2xx` findings through the **same** SARIF emit,
        severity banding, and `scorers.disable`/`enable` machinery as the built-in checks — no
        second output path, no schema bump.
      - Each ported domain check has a calibration fixture (clean input → no findings, bad
        input → located findings), matching the evidence bar F17 held itself to.
      - A check that needs a change-diff or skill metadata (rather than a bare folder) can
        declare that need and is skipped — not silently wrong — when the input lacks it.
    - Dependencies: scorers (**F17**), the evidence/corpus model (Phase 3); shares the
      declarative-rule decisions of **F11** if that lands first.
    - Confidence: Medium — the six predecessor scorers are working reference implementations;
      open question is declarative-data vs. compiled-plugin (see Notes).
    - Notes: Two candidate shapes — data-declared checks (like F11, safest: no code execution)
      or a compiled extension point (most expressive, biggest security surface). Prefer the
      data shape and let the compiled path stay a non-goal unless demand proves otherwise;
      repo-local scorer IDs use a reserved `S2xx` range so they can never collide with built-ins.

13. **[F12]** Skill-security lint rules (security tier in the `SKILL-Lxxx` catalog) — FUTURE · Net-new
    - Purpose & user value: Static, deterministic-first security checks over the SKILL.md file —
      prompt-injection phrasing, evaluator/judge manipulation, unicode obfuscation, YAML
      front-matter anomalies, and suspicious size — so a skill is screened for adversarial content
      before it is trusted or shipped. Runs free, before any paid judge.
    - Confidence: Medium — competitive cross-reference (Skill-Lab's 5 security checks; AWS
      `skill-eval` static security scan; SkillTester's security benchmark); design §6.1 `lint`, §13.

14. **[F13]** Skill-bundle integrity lint group — FUTURE · Net-new
    - Purpose & user value: Static checks over a skill's *bundle*, beyond its `SKILL.md` prose —
      that bundled `scripts/` are self-contained, non-interactive, and `--help`-capable; that
      referenced script/asset paths resolve; and that no files are orphaned or outside the spec
      dirs — so a skill ships as a coherent, runnable package, not just well-written prose. Free,
      deterministic, before any paid judge.
    - Confidence: Medium — competitive cross-reference (Skill-Lab's Structure/Content bundle checks;
      AWS `skill-eval`'s skill-standard-directory scan); the agentskills.io `scripts/`/`references/`
      structure; design §6.1 `lint`, §7.1, §13.

15. **[F64]** General synthetic eval generator (both axes) — FUTURE · Net-new
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

16. **[F65]** Named aggregation catalog — FUTURE · Net-new
    - Purpose & user value: Fixed, Swift-implemented, config-invoked aggregations over numeric
      metrics — `mean` / `min` / `max` / `stddev` / `median` / `percentile(p)` / `sum` /
      `count` / `agreement` — attachable as thresholds where a gate already exists; grows by
      PR, never a config formula language (the versioned per-trial JSON is the custom-math
      escape hatch). Serves F61's partial-credit percentage, F62's dimension scores, and
      F10's kappa; pulls forward if their reporting demands it.
    - Confidence: Medium — design §14-17 (decided 2026-07-06); mirrors F11's fixed
      code-backed *kinds* stance.

17. **[F66]** Test-framework integration recipe (docs) — FUTURE · Net-new
    - Purpose & user value: A short documented recipe for running skillet inside any test
      framework — Swift Testing, pytest, bare CI — by shelling `skillet run --json` and
      asserting on the payload + exit codes; the `--json` + exit-code contract *is* the
      integration surface. Companion to the declined Swift-library surface (non-goal below).
    - Confidence: High — design §14-18 (decided 2026-07-06); docs-only.

18. **[F67]** Diagnostic model tier — the provider-neutral cheap-model slot (config: `models.diagnostic`) — FUTURE · Net-new
    - Purpose & user value: One slot and one contract (design §9.6) for every model whose output
      informs but never gates: generation (F63/F64), scoring (F62), clustering (F52), the F14
      smoke arm. Cheap/local providers may fill it; a platform default may fill it only with a
      $0/offline/entitlement-free provider and always announces itself (plan note + `doctor` row).
      Deliberately **not Apple-only**: providers are plugs — Apple first (F68), cross-platform
      local runners (Ollama-class) the research alternative.
    - Confidence: Medium — design §14-19 (decided 2026-07-07), §9.6.
    - Notes: Pulls forward to land with its first consumer (F62, Phase 4).

19. **[F68]** Apple Foundation Models provider (on-device + Private Cloud Compute) — FUTURE · Net-new · `needs-research`
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

13. **[F73]** Finish the binary-resolution chain — the missing `--harness-path` switch — FUTURE · Net-new
    - Purpose & user value: point one run at one copy of a program without changing your environment
      or editing a file everyone shares. The resolution order is already specified as a fixed,
      printable chain — the switch, then `SKILLET_<ID>_BIN`, then `[harness.<id>].path`, then what is
      on your `PATH` (`skillet-design.md:895`) — and matches the ordinary convention that an explicit
      switch on the command line beats an environment variable, which beats a file. **Only the top of
      that chain was never built.** The routine that resolves a program already takes the switch as its
      first argument; all four callers pass nothing.
    - Discovered 2026-08-18 by following the tool's own advice: the "could not find it" message named
      the switch first, so the first fix it offered someone already stuck did not exist. The message
      now names only the two routes that work, and a test refuses to let the name come back until the
      switch does (`Tests/EDDCoreTests/RemedyRoutesTests.swift`).
    - Success metrics:
      - Every command that resolves a program accepts the switch, and it beats the environment variable.
      - The message names all three routes again, and the test that forbids the name is retired.
    - Dependencies: none — five call sites in the measuring, checking, drafting, recording and
      version-control paths.
    - Confidence: High — the behaviour is already specified; this is completing it, not designing it.

14. **[F74]** Record a replay file from a live run — FUTURE · Net-new
    - Purpose & user value: every canned-answer file in this project is written by hand, so the offline
      tests are checked against text a person invented rather than text a model produced. A `--record`
      switch on the measuring and proving commands would write the answers and gradings of a real run
      into a file the offline path can replay — the ordinary "record once, replay for ever" practice for
      software that calls a model, which keeps a fast free suite honest about real output without paying
      for it again.
    - Related sighting, 2026-08-22: a throwaway copy left behind by a killed process stays in the shared
      temporary area and in version control's own list of copies, with nothing to surface it. `F76`
      (confine short-lived working directories) covers where the copy lives; a preflight that notices
      leftovers belongs with it.
    - Discovered 2026-08-20, doing the first live run of the proving command. That run produced exactly
      the artifact worth keeping — a real answer that failed a test and a real answer that passed it,
      with the grader's own reasons — and there was no way to turn it into a fixture except by hand, so
      it was recorded as prose in `Specs/020-prove-by-ab/plan.md` instead of as a test.
    - Reinforced 2026-08-21, closing the routing gap in the offline answerer. Which skill a session says
      it reached for is now stated by the skill's own file rather than baked into the answerer, so an
      offline test asserts on something it declared. That removes a test passing on a coincidence, but it
      cannot make the offline answer resemble a real one — the standard remedy is a check run against both
      the stand-in and the real thing, asserting they agree, and this feature is that check's only
      practical route.
    - Success metrics:
      - A live run can write a file the offline path replays, reproducing that run's verdicts exactly.
      - At least one offline test is driven by recorded real output rather than invented text.
      - The recorded file is scrubbed by the same path `capture` uses, so a recording never carries a
        secret (constitution: redact before write).
    - Dependencies: the offline answerer and grader already read exactly this shape of file; what is
      missing is the writer.
    - Confidence: High — the format exists and is exercised by roughly forty tests; this adds a producer
      for it.

15. **[F75]** Bring the integration test files under the 300-line cap — FUTURE · Net-new
    - Purpose & user value: the contributor guide states a 300-line soft cap for test files, and six of
      seven files driving the built binary exceed it — 1113, 668, 544, 537, 459 and 382 lines. A file
      that long is read by nobody in full, so a test that has quietly stopped asserting anything is hard
      to notice, and two tests covering the same ground even harder.
    - Discovered 2026-08-20 while splitting the two files this feature added (D19). Those are now under
      the cap; the rest predate it and are left, because splitting six suites is a mechanical change with
      its own review rather than a line in someone else's feature.
    - Success metrics:
      - Every file under `Tests/` is at or below the cap, or carries a recorded reason for exceeding it.
      - The test count is unchanged by the split, checked before and after.
      - Shared setup lives in one place per command rather than on whichever suite owns it.
    - Dependencies: none.
    - Confidence: High — the pattern is established by D19's split (a `…Fixture` holding shared setup,
      topic suites beside it).

16. **[F76]** Confine and clean up short-lived working directories — FUTURE · Net-new
    - Purpose & user value: two paths stage work in the machine's shared temporary area and tidy up on
      the way out — the recording command's scoring input, and the throwaway copy the proving command
      measures in. Killed part-way, both leave a folder behind, in a place nobody thinks to look. Moving
      short-lived work under the project's own ignored scratch folder makes leftovers discoverable and
      removable, and a check in the free preflight could name any it finds.
    - Discovered 2026-08-21 in review. Neither leaks anything secret — the recording command redacts
      before it writes, and the copy holds only committed content — so this is tidiness and
      discoverability rather than exposure.
    - Success metrics:
      - Short-lived working directories live under the project's ignored scratch folder, not the shared
        temporary area.
      - The free preflight names leftovers from an interrupted run and says how to clear them.
      - A copy that outlives its run is already disclosed (D14); the preflight closes the loop for one
        that outlived the whole process.
    - Dependencies: none.
    - Confidence: High — both call sites are one line each; the preflight check is a new row.

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
  cross-reference additions — F10, F11, F12, F13 (the v0.8 competitive round; listed
  individually because F72 was later inserted between F11 and F12, so the range is no longer
  contiguous) and F64–F68
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
- 2026-08-13: MINOR — added **F72** (domain-specific output scorers — the bring-your-own-check
  layer, `SKILL-S2xx`). Gives an owner to the F17 deferral of the predecessor CLI's six
  domain-specific checks, which until now was a decision no entry claimed. Output-side sibling
  of F11. Roadmap → v1.22.0.
- 2026-08-20: MINOR — added **F74** (record a replay file from a live run). Raised by the first live
  run of `iterate`, which produced real before/after answers worth keeping and no supported way to keep
  them. Roadmap → v1.23.0.
- 2026-08-20: MINOR — added **F75** (bring the integration test files under the stated 300-line cap).
  Raised while splitting the two files F43 added; the other six predate it. Roadmap → v1.24.0.
- 2026-08-21: MINOR — added **F76** (confine and clean up short-lived working directories). Raised in
  review alongside F75; tidiness rather than exposure, since neither path stages anything unredacted.
  Roadmap → v1.25.0.
