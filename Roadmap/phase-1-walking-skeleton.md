# Phase 1 — Walking Skeleton: Prove the Loop End-to-End

**Status:** PLANNED
**Horizon:** Now
**Last Updated:** 2026-06-18

## Goal

Stand up the thinnest possible end-to-end thread of the EDD loop: in any skills
repo, run a single eval through Claude Code, have it judged, and print a `pass^k`
result — backed by just enough `init`/`doctor`/`lint` to make that one command
trustworthy. This proves the architecture (the seams every later phase reuses)
and delivers the "value in 30 seconds" entry point (design D2) that earns the
tool its first user.

## Key Features

1. Project discovery & output contract (CLI: `skillet`, `-C <dir>`, `--json`, exit codes) — PLANNED · Net-new
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

2. Adopt skillet in a repo (CLI: `skillet init`) — PLANNED · Net-new
   - Purpose & user value: One idempotent command turns a skills repo into a
     skillet project — detected config, discovered skills, scaffolded
     `evaluations/` — so a newcomer is productive without hand-authoring config.
   - Northstar: loop integrity (onboarding).
   - Success metrics:
     - `init` writes a valid `skillet.yaml` + `evaluations/` skeleton, then prints the three next commands.
     - Re-running fills gaps and overwrites nothing (idempotency test passes).
   - Dependencies: Project discovery (F1).
   - Confidence: Medium — design §6.1 `init`.

3. $0 preflight & skill-visibility check (CLI: `skillet doctor`) — PLANNED · Net-new
   - Purpose & user value: A free, fast self-check that catches the silent
     killers before any paid run — config parses, the harness is found and
     authed, and the skill is actually *visible* to the harness. Kills the
     `--skill-path` false-negative class by construction (design P6).
   - Northstar: loop integrity (errors teach; never pay to discover a misconfig).
   - Success metrics:
     - `doctor` reports config origin, harness version, and auth, exiting `3` with a remedy line on any failure.
     - Verifies both the positive-load condition (target `SKILL.md` + `references/`) and the discovery-only condition (siblings listable, not injected).
   - Dependencies: HarnessAdapter seam (F5), claude-code adapter (F6).
   - Confidence: Medium — design §6.1 `doctor`, §9.2.

4. Free static lint — error-tier core (CLI: `skillet lint`) — PLANNED · Ported
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
     5-rule catalog + SARIF lands in Phase 2.

5. Normalized trace & harness-adapter seam (surfaces via `skillet harness info`) — PLANNED · Net-new
   - Purpose & user value: The one harness-independent record (`skillet.trace/1`)
     and the `HarnessAdapter` protocol that every later capability — capture,
     triage, judging, the matrix — consumes. Designing it now (D4) is what lets
     the tool be multi-harness later without a retrofit.
   - Northstar: differentiator #2 foundation + loop integrity.
   - Success metrics:
     - A Claude Code session parses into a `Trace` with turns, tool calls, file changes, and skill invocations (golden-file test vs a recorded native log).
     - The `Trace` round-trips through `--json` with its `schema` field intact.
   - Dependencies: none (pure model + protocol).
   - Confidence: Medium — design §9.1, §9.3, §11.

6. claude-code adapter — run & trace parse (CLI: `--harness claude-code`) — PLANNED · Ported
   - Purpose & user value: The first real harness — execute a task and parse its
     native session — so the runner has something to run against on day one.
   - Northstar: loop integrity.
   - Success metrics:
     - Probes (version + auth) and executes a trivial task end-to-end, returning a parseable `RawTrace`.
     - A seed-denylist version is refused when pinned, or warned + fallen-back-from when auto-discovered.
   - Dependencies: Trace & adapter seam (F5).
   - Confidence: Medium — design §9, §13 (ported from the Claude-only predecessor).

7. The neutral runner — behavioral axis + pass^k (CLI: `skillet run`) — PLANNED · Ported
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
   - Dependencies: claude-code adapter (F6), boundary codecs (F8), text judge (in this feature).
   - Confidence: Medium — design §6.1 `run`, §10.
   - Notes: Phase 1 ships the with-skill behavioral arm via `claude-code` with the
     text judge. Trigger axis, A/B arm, grounded judge, and matrix arrive in
     Phases 2 and 7.

8. Frozen boundary codecs + golden tests (`evals.json`, `benchmark.json`) — PLANNED · Ported
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

## Dependencies & Sequencing

- Local ordering: Trace & adapter seam (F5) → claude-code adapter (F6) → runner
  (F7). Boundary codecs (F8) and the output contract (F1) are prerequisites of
  the runner. `doctor` (F3) depends on the adapter; `lint` (F4) and `init` (F2)
  need only discovery.
- Cross-phase: F5/F6 are reused by Phases 3, 4, 6, 7; F8 by Phase 2's reporting.

## Package targets (Phase 1)

The walking skeleton stands up the §11 architecture as a **Phase-1 subset** of targets, with the
strict downward DAG enforced from the first commit (later phases add kits, not re-layering):

- **`EDDCore`** (pure) — exit codes, `--json` schema envelope, `EDDError`, pass^k aggregation,
  `evals.json`/`benchmark.json` boundary codecs (F1, F4, F7, F8).
- **`TraceKit`** — normalized `Trace`/`Turn` model behind the `HarnessAdapter` seam (F5).
- **`HarnessKit`** — `HarnessAdapter`, `Workspace`, `HarnessClaudeCode`, `HarnessReplay` (F5, F6);
  **`JudgeKit`** — `Judge`, text judge, `ReplayJudge` (F7).
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

- Assumes the predecessor runner/codecs port faithfully behind the new seams.
- Token/cost fields may be structurally zero until usage parsing lands (Phase 8);
  spend falls back to trial-count estimates.

## Phase Change Log

- 2026-06-17: Phase created. Scoped deliberately thin as the walking-skeleton
  "Now" per the dependency-honest + walking-skeleton-MVP decision.
- 2026-06-18: PATCH — config referenced as `skillet.yaml` (was `skillet.toml`);
  reflects the YAML-via-`swift-yaml` decision (TOML dependency dropped). No
  feature or priority change.
