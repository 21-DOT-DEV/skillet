# Phase 1 — Walking Skeleton: Prove the Loop End-to-End

**Status:** IN PROGRESS — F1, F2, F5, F6 complete
**Horizon:** Now
**Last Updated:** 2026-06-23
**Review:** completed-items cross-artifact audit → [phase-1-review.md](phase-1-review.md)

## Goal

Stand up the thinnest possible end-to-end thread of the EDD loop: in any skills
repo, run a single eval through Claude Code, have it judged, and print a `pass^k`
result — backed by just enough `init`/`doctor`/`lint` to make that one command
trustworthy. This proves the architecture (the seams every later phase reuses)
and delivers the "value in 30 seconds" entry point (design D2) that earns the
tool its first user.

## Key Features

Listed in **build order**; the bracketed **[Fn]** is the feature's *stable identifier* (referenced in
Dependencies, Package targets, the specs, and the change log) and does **not** change when the build
sequence is re-ordered.

1. **[F1]** Project discovery & output contract (CLI: `skillet`, `-C <dir>`, `--json`, exit codes) — DONE · Net-new
   - Purpose & user value: Run from anywhere — skillet finds its project by
     walking up to `skillet.yaml`/`.git`, like git — and every command speaks to
     both humans (TTY) and scripts (`--json` + stable exit codes).
   - Northstar: loop integrity (the substrate every other command stands on).
   - Success metrics:
     - From any subdirectory, a command resolves the correct project root (`-C` parity test).
     - Exit codes follow the documented table: usage error `2`, environment error `3`.
     - Every `--json` payload validates against its declared `schema` field.
   - Dependencies: none.
   - Confidence: Medium — design §5 (invocation model, exit codes, output contract).
   - Plan: [Specs/001-project-discovery-output-contract/plan.md](../Specs/001-project-discovery-output-contract/plan.md)

2. **[F2]** Adopt skillet in a repo (CLI: `skillet init`) — DONE · Net-new
   - Purpose & user value: One idempotent command turns a skills repo into a
     skillet project — detected config, discovered skills, scaffolded
     `evaluations/` — so a newcomer is productive without hand-authoring config.
   - Northstar: loop integrity (onboarding).
   - Success metrics:
     - `init` writes a valid `skillet.yaml` + `evaluations/` skeleton, then prints the three next commands.
     - Re-running fills gaps and overwrites nothing (idempotency test passes).
   - Dependencies: Project discovery (F1).
   - Confidence: Medium — design §6.1 `init`.
   - Plan: [Specs/002-adopt-skillet-repo/plan.md](../Specs/002-adopt-skillet-repo/plan.md)

3. **[F5]** Normalized trace & harness-adapter seam (surfaces via `skillet harness info`) — DONE · Net-new
   - Purpose & user value: The one harness-independent record (`skillet.trace/1`)
     and the `HarnessAdapter` protocol that every later capability — capture,
     triage, judging, the matrix — consumes. Designing it now (D4) is what lets
     the tool be multi-harness later without a retrofit.
   - Northstar: differentiator #2 foundation + loop integrity.
   - Success metrics:
     - The `Trace` model round-trips through `--json` with its `schema` field intact (golden test).
     - `skillet harness info` lists registered adapters and their capability matrix; `--json` carries its `schema`.
     - `ReplayAdapter` produces a canned `Trace` through the protocol — the seam is implementable end-to-end with no live harness.
   - Dependencies: none (pure model + protocol). Per §9.3, per-harness parsers live beside their adapters, so claude-code trace parsing is F6.
   - Confidence: Medium — design §9.1, §9.3, §11.
   - Plan: [Specs/003-normalized-trace-harness-seam/plan.md](../Specs/003-normalized-trace-harness-seam/plan.md)

4. **[F6]** claude-code adapter — trace parser, resolution & probe (live `run` in F7) — DONE · Ported
   - Purpose & user value: The first real harness adapter: parse claude-code's native session into a
     `Trace`, resolve and vet its binary (denylist), and provide the `probe` + static skill-visibility
     check that `doctor` needs. The live task execution (`run` + §9.2 skill-injection) lands in F7, where
     a real claude-code validates it.
   - Northstar: loop integrity.
   - Success metrics:
     - A recorded Claude Code session (native JSONL) parses into a `Trace` — turns, tool calls, file changes, skill invocations — golden-tested vs a **synthetic** fixture mirroring the native format (real logs are not committed — constitution VI; the parser is re-derived from the live format, the predecessor port being absent).
     - The binary resolution chain (flag > env > config > PATH; vendored deferred) selects the right link and records which one won (the source is captured + printable; `harness which` surfaces it later).
     - A seed-denylist version is refused when pinned (exit `3`); when auto-discovered it surfaces a **loud notice** (carried as `HarnessInfo.warnings`, shown by `harness info` on the TTY and in `--json`) but is not fatal. *Automatic fallback to a non-banned binary is a documented seam — the resolver returns a single candidate today; F7.*
     - `probe()` and `verifySkillVisibility` are implemented behind a fakeable process-launcher seam (logic unit-tested); `probe`'s live version/auth call is validated only by F7's opt-in env-gated smoke (claude-code isn't runnable in CI).
   - Known F6 gaps (tracked, by design): (C) `Trace.workspaceDiff.deleted` is always empty — deletions aren't modeled yet; (D) failed/`is_error` tool results are not captured, so a `Skill` invocation is recorded even when it errored; (#3) a missing/unresolved binary surfaces a raw launcher error rather than a P6 what/why/fix message — the live path is F7-gated. C/D/#3 land with their consumers (Phase 2+/F7).
   - Dependencies: Trace & adapter seam (F5). Needs a synthetic claude-code-format fixture; live paths are env-gated (claude-code unavailable in CI).
   - Confidence: Medium — design §9, §13.
   - Plan: [Specs/004-claude-code-adapter/plan.md](../Specs/004-claude-code-adapter/plan.md)

5. **[F4]** Free static lint — error-tier core (CLI: `skillet lint`) — PLANNED · Ported
   - Purpose & user value: Instant, model-free analysis of the `SKILL.md` source
     so the cheapest lever runs first and gates the expensive ones; error-tier
     findings surface in `doctor` too.
   - Northstar: loop integrity + deterministic-first.
   - Success metrics:
     - Flags an over-long description (`SKILL-L001`) and a missing/short `evals.json` (`SKILL-L009`) on fixtures, exiting `1` on any error-tier finding.
     - Stable diagnostic IDs + fix-hints in TTY; exemptions read from the `[lint]` knob table, not inline pragmas.
   - Dependencies: Project discovery (F1).
   - Confidence: Medium — design §6.1 `lint`.
   - Notes: Phase 1 ships the error-tier subset `doctor` depends on; the full
     5-rule catalog + SARIF lands in Phase 2. Error-tier core = `L001` + `L003` + `L009` (full tiers).
   - Plan: [Specs/005-free-static-lint/plan.md](../Specs/005-free-static-lint/plan.md)

6. **[F3]** $0 preflight & skill-visibility check (CLI: `skillet doctor`) — PLANNED · Net-new
   - Purpose & user value: A free, fast self-check that catches the silent
     killers before any paid run — config parses, the harness is found and
     authed, and the skill is actually *visible* to the harness. Kills the
     `--skill-path` false-negative class by construction (design P6).
   - Northstar: loop integrity (errors teach; never pay to discover a misconfig).
   - Success metrics:
     - `doctor` reports config origin, harness version, and auth, exiting `3` with a remedy line on any failure.
     - Verifies both the positive-load condition (target `SKILL.md` + `references/`) and the discovery-only condition (siblings listable, not injected).
   - Dependencies: HarnessAdapter seam (F5), claude-code adapter (F6); also `swift-yaml` (config parsing) and error-tier `lint` (F4, surfaced in `doctor`).
   - Confidence: Medium — design §6.1 `doctor`, §9.2.

7. **[F8]** Frozen boundary codecs + golden tests (`evals.json`, `benchmark.json`) — PLANNED · Ported
   - Purpose & user value: Read/write the de-facto-standard eval and benchmark
     formats byte-compatibly so existing skill-creator tooling and the eval-viewer
     keep working unchanged — the promise that adopting skillet costs nothing
     downstream (D5).
   - Northstar: loop integrity (ecosystem compatibility).
   - Success metrics:
     - `evals.json` and `benchmark.json` round-trip with unknown keys preserved (`Tests/Golden/boundary/` passes).
     - A `run` updates `benchmark.json` in a form the legacy Python viewer renders unmodified.
   - Dependencies: none (EDDCore codecs).
   - Confidence: Medium — design §7.2, §13.

8. **[F7]** The neutral runner — behavioral axis + pass^k (CLI: `skillet run`) — PLANNED · Ported
   - Purpose & user value: The entry point (D2) — execute a skill's behavioral
     evals in an isolated sandbox, grade each `expected_behavior` line with the
     (text) judge, and report `pass^k` reliability. Answers "does this skill
     work?" in one command, zero workflow required.
   - Northstar: loop integrity (the thread the whole loop hangs on); exposes the
     failures that feed gap #1.
   - Success metrics:
     - `run <skill>` runs every eval k times in a fresh `Workspace`, prints a per-eval PASS/FAIL/FLAKY table + aggregate `pass^k`, and exits `1` on any failure.
     - An eval passes a trial only if *all* criteria pass; a planted "surface compliance without substance" case FAILs.
     - `pass^k` is computed at observed k and recomputes identically offline from the on-disk run record.
     - Executes a trivial task end-to-end through the **live** claude-code adapter (`probe` version+auth, `run` + §9.2 skill-injection), returning a parseable `RawTrace` — covered by one **opt-in, env-gated live smoke** (the only paid test; free CI skips it). *(The live half of F6, validated here against a real claude-code.)*
   - Dependencies: claude-code adapter (F6), boundary codecs (F8), text judge (in this feature).
   - Confidence: Medium — design §6.1 `run`, §10.
   - Notes: Phase 1 ships the with-skill behavioral arm via `claude-code` with the
     text judge. Trigger axis, A/B arm, grounded judge, and matrix arrive in
     Phases 2 and 7. F7 also implements claude-code's live `run` execution + §9.2
     skill-injection (the body F6 leaves as a seam) and owns the env-gated live smoke
     that validates the real adapter path (probe/run/injection).

## Dependencies & Sequencing

- **Build order (dependency-honest):** F1 → F2 *(done)* → F5 (adapter seam) → F6 (claude-code
  adapter) → F4 (lint) → F3 (`doctor`) → F8 (boundary codecs) → F7 (`run`). The Key Features list is
  in this order; **Fn** ids are stable and independent of position.
- Local dependencies: `doctor` (F3) needs the adapter seam (F5) + claude-code adapter (F6) +
  `swift-yaml` (config parsing) + error-tier `lint` (F4, which it surfaces); the runner (F7) needs the
  claude-code adapter (F6) + boundary codecs (F8) + the text judge; `lint` (F4) and `init` (F2) need
  only discovery (F1).
- Cross-phase: F5/F6 are reused by Phases 3, 4, 6, 7; F8 by Phase 2's reporting.
- F6 ships the validatable core (parser, resolution, denylist, `probe`/`verifySkillVisibility` behind a
  fakeable launcher); F7 implements the **live** claude-code `run` execution + §9.2 skill-injection.
  Because claude-code isn't runnable in CI, every live adapter path is validated by **one opt-in,
  env-gated smoke (in F7)** — never by free CI.

## Package targets (Phase 1)

The walking skeleton stands up the §11 architecture as a **Phase-1 subset** of targets, with the
strict downward DAG enforced from the first commit (later phases add kits, not re-layering):

- **`EDDCore`** (pure) — exit codes, `--json` schema envelope, `EDDError`, pass^k aggregation,
  `evals.json`/`benchmark.json` boundary codecs (F1, F4, F7, F8).
- **`TraceKit`** — normalized `Trace`/`Turn` model behind the `HarnessAdapter` seam (F5).
- **`HarnessKit`** — `HarnessAdapter`, `Workspace`, `ClaudeCodeAdapter` (parser + resolution + probe),
  `BinaryResolver`, `Denylist`, `ProcessLauncher`, `ReplayAdapter` (F5, F6);
  **`JudgeKit`** — `Judge`, text judge, `ReplayJudge` (F7).
- **`ConfigYAML`** — the isolated `.Cxx` YAML-codec seam (swift-yaml → `EDDCore.SkilletConfig`); F6.
- **`RunKit`** — trial planner, run records, pass^k (F7).
- **`LintKit`** — error-tier `SKILL-Lxxx` subset (F4); **`RenderKit`** — TTY tables + versioned JSON
  encoders (F1); **`ProjectKit`** — project discovery, config I/O, `init` scaffolding (F1–F3).
- **`skillet`** (executable) — the full ArgumentParser command tree + wiring for
  `init`/`doctor`/`lint`/`run`. No `skilletCLI` library.

**Deferred:** `ScoreKit` (Phase 2), `CorpusKit`/capture (Phase 3), `AnalysisKit` (Phase 4),
`IterateKit` (Phase 6). `swift-yaml` is wired only when `EDDCore`'s config codec body lands (no
tagged release + C++-interop; see AGENTS.md › Dependency notes).

**Tests:** one unit-test target per kit + an `IntegrationTests` target driving the built binary via
`swift-subprocess` (isolated temp dirs, Swift Testing tags); 300-line soft cap on test files.

## Phase Metrics & Success Criteria

- This phase is successful when: in a fresh checkout of a real skills repo, a new
  user runs `skillet init && skillet doctor && skillet run <skill>` and gets a
  trustworthy `pass^k` table in under a minute — no manual skill-path wiring, no
  paid surprise.

## Risks & Assumptions

- **The predecessor (`swift-skill-eval`) is not in this repo**, so "Ported" tags are scheduling hints,
  not a copy path: the claude-code parser/runner are re-derived from the live native-session format +
  design §9, validated against real `~/.claude` logs (read, never committed — constitution VI).
- **claude-code is not available in the dev/CI environment**, so every live adapter path (F6 `probe`'s
  call, F7 `run`) is validated only by an opt-in env-gated smoke (F7), not by free CI.
- Token/cost fields may be structurally zero until usage parsing lands (Phase 8);
  spend falls back to trial-count estimates.

## Phase Change Log

- 2026-06-17: Phase created. Scoped deliberately thin as the walking-skeleton
  "Now" per the dependency-honest + walking-skeleton-MVP decision.
- 2026-06-18: PATCH — config referenced as `skillet.yaml` (was `skillet.toml`);
  reflects the YAML-via-`swift-yaml` decision (TOML dependency dropped). No
  feature or priority change.
- 2026-06-20: F1 (project discovery & output contract) implemented — `Package.swift`
  + `EDDCore`/`ProjectKit`/`RenderKit` + the `skillet` executable; 32 unit + integration
  tests green. Plan: [Specs/001-…/plan.md](../Specs/001-project-discovery-output-contract/plan.md).
- 2026-06-20: F2 (`skillet init`) implemented — templated `skillet.yaml` + per-skill `evaluations/`
  scaffolding + self-owned `.skillet/.gitignore`; verified-docs harness (dump-help surface +
  behavioral + link checks); `README.md` brought current. 45 tests green. Plan:
  [Specs/002-adopt-skillet-repo/plan.md](../Specs/002-adopt-skillet-repo/plan.md).
- 2026-06-21: MINOR re-sequence — Phase-1 build order made dependency-honest: `skillet doctor` (F3)
  moved to after the HarnessAdapter seam (F5) and claude-code adapter (F6), since `doctor`'s
  `probe()`/`verifySkillVisibility` are adapter methods (design §9.1) and it also needs `swift-yaml`
  (config parsing) + error-tier `lint` (F4). New build order: F1, F2, F5, F6, F4, F3, F8, F7. Feature
  identifiers (**Fn**) are unchanged — stable across the specs, Package targets, and prior log entries;
  only the build sequence changed. No scope or feature-content change.
- 2026-06-21: PATCH — F5 scoped as the harness-*agnostic* seam (Trace model + HarnessAdapter protocol
  + HarnessReplay + `harness info`); claude-code trace parsing confirmed F6 (per §9.3, per-harness
  parsers live beside their adapters). F5's "parse a Claude Code log" success-metric moved to F6;
  added F5 plan link ([Specs/003](../Specs/003-normalized-trace-harness-seam/plan.md)). Metric
  attribution only — no scope change.
- 2026-06-21: F5 (normalized trace & harness-adapter seam) implemented — `TraceKit` (`Trace` =
  `skillet.trace/1`) + `HarnessKit` (full `HarnessAdapter` protocol + `HarnessReplay` + claude-code
  stub + registry + `harness-info` report) + `skillet harness list`/`info`; harness-agnostic, no new
  package deps; 58 unit + integration tests green. Plan:
  [Specs/003](../Specs/003-normalized-trace-harness-seam/plan.md).
- 2026-06-21: MINOR — F6/F7 scope re-attributed (Option B). claude-code isn't runnable in this dev/CI
  environment and the predecessor port is absent, so F6 now ships only the validatable core — the
  native-JSONL→`Trace` parser (golden vs a synthetic fixture; real logs not committed, constitution VI),
  the binary resolution chain, the denylist/ban policy, and `probe`/`verifySkillVisibility` behind a
  fakeable launcher seam — while the **live `run` execution + §9.2 skill-injection** (and the live
  validation of `probe`/`run`) move to **F7**, which owns the one opt-in env-gated smoke where a real
  claude-code validates the path. `probe`/`verifySkillVisibility` stay in F6 because `doctor` (F3,
  earlier in the build order) needs them. Fn ids stable; build order unchanged.
- 2026-06-21: F6 (claude-code adapter) implemented — `HarnessKit` gains `ClaudeCodeAdapter`
  (native-JSONL → `Trace` parser, golden vs a synthetic fixture covering turns / tool calls / skill
  invocations / workspace diff), `BinaryResolver` (flag > env > config > PATH), `Denylist` (seed
  `2.1.143`; pinned-banned exit 3, auto-discovered warn+fallback), and `probe` / `verifySkillVisibility`
  behind a fakeable `ProcessLauncher`; live `run` stays an F7 seam. `swift-yaml` wired isolated in the
  new `.Cxx` `ConfigYAML` target (decodes `skillet.yaml` → `EDDCore.SkilletConfig`); the interop spike
  confirmed C++ interop is **viral to direct importers**, so the executable is a `.Cxx` leaf while every
  kit + the pure core stay interop-free. 76 unit + integration tests green. Plan:
  [Specs/004](../Specs/004-claude-code-adapter/plan.md).
- 2026-06-23: PATCH — F6 correctness pass against the **real** `~/.claude` native format (read-only,
  not committed — constitution VI). Fixed three parser defects the self-referential synthetic fixture
  had masked: (A) tool-result `user` lines are no longer counted as conversational turns (they
  outnumber real user turns ~5:1 in live sessions); (B) `workspaceDiff` is now derived from each
  result's `toolUseResult` (`create`→added, `update`→modified) instead of the request input; (E)
  multiple text blocks in a turn join with a newline. The denylist auto-discovered-banned case now
  surfaces a **loud notice** via the new additive `HarnessInfo.warnings` (shown by `harness info` on the
  TTY + in `--json`); automatic fallback stays an F7 seam. Synthetic fixture + tests rewritten to assert
  the correct native-format behavior. Also fixed F2's `InitReport` (F): it now lists the auto-created
  `evaluations/` parent dir. Deletions (C), `is_error` results (D), and the raw-error-vs-P6 message (#3)
  are logged as tracked gaps. 79 tests green.
