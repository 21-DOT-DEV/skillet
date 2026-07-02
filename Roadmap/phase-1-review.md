# Phase 1 — Completed-Items Cross-Artifact Audit

**Date:** 2026-07-01
**Scope:** every completed-item claim in [phase-1-walking-skeleton.md](phase-1-walking-skeleton.md), cross-verified three ways — phase doc ↔ `Specs/001–007` plans ↔ shipped code/tests — plus the cross-artifacts they cite (ROADMAP.md, AGENTS.md, README.md, `skillet-design.md` §5/§6.1/§7/§9–§11/§13–§14, the constitution).
**Verification tier:** evidence-based, free-only. Full build + suite run (2026-07-01: **235 tests / 40 suites, all green**, clean 2.77 s build), spend-free CLI exercising in a throwaway fixture repo (`init` ×2, `lint`, `run --dry-run`/`--json`, `harness list/info`, exit-code probes), and claim-by-claim source verification with `file:line` evidence. **The paid env-gated live smoke was not run** (design P9 — spend needs consent); live-path claims are marked accordingly. Live behavior cited here rests on the consented 2026-06-28 smoke recorded in design v0.13.
**Verdict: Phase 1 COMPLETE stands.** All seven features' roadmap success metrics verify against shipped code with test evidence. The drift found is overwhelmingly *documentary* — current-state doc lines that lagged the nine post-merge review rounds (v1.9.1–v1.9.8) — plus four substantive items that need decisions, not doc edits (§5 Major findings). Documentary drift is reconciled in this pass (§6).

---

## 1. Verdict summary

| Feature | Roadmap metrics | Plan (Specs) | Notable findings |
|---|---|---|---|
| F1 discovery & output contract | ✅ all verified | 001 · minor as-built deltas | `-q`/`-v` parsed but inert (A15) |
| F2 `skillet init` | ✅ verified (1 wording fix) | 002 · minor as-built deltas | "three next commands" → honest filter prints two today (A4, fixed) |
| F4 free static lint | ✅ all verified | 005 · current | L001 counts Unicode scalars exactly as claimed; LintKit provably pure |
| F5 trace & harness seam | ✅ all verified | 003 · naming drift | `HarnessReplay` shipped as `ReplayAdapter` (plan never updated) |
| F6 claude-code adapter | ✅ all verified | 004 · fallback wording stale | gaps C/D confirmed still open; **gap #3 is closed** (A3, fixed) |
| F7 neutral runner + judge | ✅ all verified | 007 · current through round 8 | provenance gaps M2/M3; recompute wording stale (A1, fixed) |
| F8 boundary codecs | ✅ all verified | 006 · 3 deviations unrecorded | `session-meta.json` codec never shipped (A5); §7.2 was half-reconciled |

Cross-cutting: package DAG exactly matches §11's Phase-1 subset (no violating edge); `.Cxx` confined to `ConfigYAML` + executable (+ `ConfigYAMLTests`, viral to the direct-importer test target); pins match Package.resolved (`swift-yaml` rev `e8d1769…`, argument-parser 1.6.2, subprocess 0.2.1, system 1.5.0); zero `Foundation.Process`/`posix_spawn`/`NSTask` hits — the launcher monopoly holds; 9 kits ↔ 9 unit-test targets + `IntegrationTests` driving the built binary; fixtures verified synthetic, zero credential/real-log hits (constitution VI upheld); `swiftLanguageModes: [.v6]`.

## 2. Method

1. **Ground truth first:** `swift build && swift test` (235/40 green), then hands-on CLI smoke in a temp git repo — `init` idempotency (run 2: `created 0 · skipped 10`), `lint` L009 error path (exit 1, `skillet.lint/1`, fix-hint), clean lint after a 3-case `evals.json` (exit 0), `run --dry-run` plan (`3 × k=3 = 9 trials`, exit 0) and `--json` (`skillet.run-plan/1` with `will_spend`), `--runs 0` → exit 2, unknown command → exit 2, missing evals → exit 2 with what/why/fix, `harness list/info` capability matrix + P6-style not-found detail.
2. **Seven parallel read-only audit passes** (one per feature cluster + cross-cutting), each returning per-claim verdicts with `file:line` evidence; load-bearing findings independently re-verified before any edit.
3. **Doc-lineage tracing:** each stale line attributed to the review round that superseded it (ROADMAP v1.9.x ↔ design v0.12–v0.20 revision log), distinguishing *current-state* text (reconciled) from *historical* change-log entries (never rewritten).

## 3. Per-feature verification

Claims are the phase doc's success metrics (abbreviated); evidence is indicative, not exhaustive.

### F1 — Project discovery & output contract
| Claim | Verdict | Evidence |
|---|---|---|
| Root resolution walks to `skillet.yaml`/`.git`; `-C` parity test | ✅ | `Sources/ProjectKit/ProjectLocator.swift:29-44`; `Tests/IntegrationTests/DiscoveryParityTests.swift:6-23` |
| Exit codes typed; usage 2 / environment 3 | ✅ | `Sources/EDDCore/ExitCode.swift:3-16`; `Tests/IntegrationTests/ExitCodeTests.swift` (5 = `gate` defined, deliberately unreachable until `--strict`) |
| Every `--json` payload carries its declared `schema` | ✅ | `Envelope` injects at encode (`Sources/EDDCore/JSON.swift:21-31`); 8 schemas shipped: `skillet.{root,error,init,lint,run,run-plan,harness-info,trace}/1` (`trace/1` is model-only until Phase-3 capture) |
| `--color` / `NO_COLOR` | ✅ | `Sources/skillet/GlobalOptions.swift:18-19`; `Sources/RenderKit/Color.swift:16-22` |

### F2 — `skillet init`
| Claim | Verdict | Evidence |
|---|---|---|
| Valid `skillet.yaml` + `evaluations/` skeleton + next commands | ✅ | `Sources/ProjectKit/InitPlanner.swift`; smoke run. Next-command line prints the **registered** subset (`lint · run` — the honest filter, `Sources/skillet/InitCommand.swift:65-70`); the metric's "three" was reconciled (A4) |
| Idempotent re-run (fills gaps, overwrites nothing) | ✅ | `Tests/IntegrationTests/InitIntegrationTests.swift:31-47` (created==[], yaml byte-identical); smoke run 2: `created 0 · skipped 10` |
| Self-owned `.skillet/.gitignore` | ✅ | `InitPlanner.swift:52-54`; root `.gitignore` untouched |
| Template carries the F7 knobs | ✅ | `Sources/ProjectKit/SkilletConfigTemplate.swift:15-29` (`runs.*` incl. `max_output_bytes`, `judge.provider/model`) — round-9 test `InitIntegrationTests.swift:17-20` |

### F4 — Free static lint
| Claim | Verdict | Evidence |
|---|---|---|
| `SKILL-L001` counts **Unicode code points** (`quick_validate.py` `len()` parity; not NFC, not graphemes) | ✅ | `description.trimmingCharacters(…).unicodeScalars.count > 1024` — `Sources/LintKit/Linter.swift:40-43`; combining-mark boundary test `Tests/LintKitTests/LinterTests.swift:40-47` |
| `SKILL-L003` warn >500 / error >1000; frontmatter + fences excluded; tunable | ✅ | `Linter.swift:55-100`; boundary tests at 500/501/1000/1001 `LinterTests.swift:77-84` |
| `SKILL-L009` missing → error, <3 → warn; consumes F8 `caseCount` | ✅ | `Linter.swift:113-133`; `EvalsFile.swift:56-57` |
| Exit 1 error-tier / 2 unknown skill; stable IDs + fix-hints; `skillet.lint/1` | ✅ | `Sources/skillet/LintCommand.swift:55-79`; `Tests/IntegrationTests/LintIntegrationTests.swift:14-59`; smoke-verified |
| Knob-table exemptions (no pragmas); LintKit pure | ✅ | `SkilletConfig.swift:53-80`; zero pragma hits; LintKit imports = EDDCore (+Foundation for `CharacterSet`) only, `Package.swift:54` |
| Frontmatter conformance rules absent (re-homed F20) | ✅ | no kebab/allowed-keys/dup-key logic anywhere in LintKit |

### F5 — Trace & harness-adapter seam
| Claim | Verdict | Evidence |
|---|---|---|
| `Trace` = `skillet.trace/1`, schema-intact round-trip | ✅ | `Sources/TraceKit/Trace.swift:12`; `Tests/TraceKitTests/TraceTests.swift:29-58` |
| `harness info` lists adapters + capability matrix; `--json` schema | ✅ | `Sources/skillet/HarnessCommand.swift:34-79`; `skillet.harness-info/1`; smoke-verified |
| Replay double produces canned `Trace` through the protocol | ✅ | shipped as **`ReplayAdapter`** (`Sources/HarnessKit/ReplayAdapter.swift:6,23-45`) — plan 003's `HarnessReplay` name never updated (A6) |
| Protocol matches design §9.1 | ✅ | `HarnessAdapter.swift:97-135` incl. `probe(strict:)` (grew with F7, design v0.13 — code and design agree today) |

### F6 — claude-code adapter
| Claim | Verdict | Evidence |
|---|---|---|
| Native-JSONL → `Trace`, golden vs **synthetic** fixture | ✅ | inline, plainly synthetic fixture (`Tests/HarnessKitTests/ParseTraceTests.swift:13-23`; fake ids/round timestamps); constitution VI clean repo-wide |
| 06-23 correctness items (A: tool-result turns · B: `toolUseResult` diff · E: newline join) | ✅ | `ClaudeCodeAdapter.swift:214-216, 199-208, 239`; tests `ParseTraceTests.swift:29-70` |
| Resolution chain flag > env > config > PATH, source recorded | ✅ | `BinaryResolver.swift:62-69`, `ResolvedBinary.source` (captured; *printing* it is F50's `harness which`) |
| Denylist seed `2.1.143`; pinned-banned exit 3; auto-discovered → loud `HarnessInfo.warnings`, no auto-fallback (F50) | ✅ | `Denylist.swift:9`; `ClaudeCodeAdapter.swift:64-75`; `ProbeTests.swift:37-65` |
| `probe`/`verifySkillVisibility` behind fakeable `ProcessLauncher` | ✅ | `ProcessLauncher.swift:31-40`; all ProbeTests fake-driven |
| Tracked gaps C/D/#3 | ⚠️ **C, D still open — #3 closed** | C: `deleted: []` hardwired (`ClaudeCodeAdapter.swift:252`) · D: no `is_error` handling (grep: comments only) · #3: typed `EDDError.harnessNotFound` what/why/fix ships at probe/preflight (`EDDError.swift:57-80`; smoke: "could not find the claude-code binary (checked the flag, env, config, and PATH)"); raw-error residual only on `run()`'s direct-launch race — phase doc reconciled (A3) |
| `run()` + `.only(load:)` injection (landed with F7); live path env-gated | ✅ | `ClaudeCodeAdapter.swift:117-150`; sole gate `SKILLET_LIVE_SMOKE` (`RunIntegrationTests.swift:313-322`); global `~/.claude/skills` isolation = documented limitation |

### F7 — Neutral runner, judge, pass^k
| Claim | Verdict | Evidence |
|---|---|---|
| k trials/eval in fresh `Workspace`; PASS/FAIL/FLAKY table + aggregate; exit 1 on any non-PASS | ✅ | `Runner.swift:38-91`; `WorkspaceManager.swift:133-160`; `Renderer.swift:164-178`; `RunCommand.swift:128-131` |
| All-criteria pass rule; claimed-but-not-created FAILs via listing + trace facts; content-grounding deferred F16 | ✅ | `RunModels.swift:45`; `JudgeKitTests.swift:161-173` (listing drives verdict); evidence-asserting judge `RunnerTests.swift:337-344`; `workspaceDiff` deliberately excluded from the prompt |
| pass^k pure in EDDCore; observed k = min recorded; per-eval status on own recorded set; **offline recompute from committed `benchmark.json`** | ✅ | `RunModels.swift:66-124`; recompute reads **`consistency.per_eval`** (`RunRecordMapping.swift:93-123`) — the phase doc's "(per-eval `passed`/`total`)" was pre-v1.9.5 wording, reconciled (A1); cache-deleted recompute test `RunIntegrationTests.swift:123-146` |
| Spend gate (P9): estimate, `confirm_above_trials`, `--yes`/`--no-input`/`-n`; TTY-both prompt rule; probe-before-spend; auth fail-closed | ✅ | `RunCommand.swift:93-115, 302-314`; `ClaudeCodeAdapter.swift:78-102`; smoke: dry-run spends nothing, `skillet.run-plan/1` |
| Free lint preflight (L001/L003) after eval loader, before spend → exit 2 + `skillet.lint/1`; corrupt 4 / missing 2 preserved | ✅ | `RunCommand.swift:85-89, 261-266`; `RunIntegrationTests.swift:194-208` (lint-2 preempts probe-3) |
| Security/confinement rounds 3–7 (traversal, symlinks at any depth, fixture-namespace allowlist, denylist staging, `.skillet` confinement, zero-expectation, uuid cache path, index-based cache ids, `max_output_bytes`) | ✅ | `WorkspaceManager.swift:10-160`; `RunCommand.swift:215-291`; nine integration tests cited in the run |
| Injection-hardened judge v2: one JSON evidence object, untrusted framing, strict-JSON verdict, criterion held out, `reason` optional, trace summary best-effort | ✅ | `TextJudge.swift:16, 40-134`; `JudgeKitTests.swift:53-159` |
| Judge failure = ungraded trial, never a fabricated FAIL; forensics keep raw + partial verdicts | ✅ | `Judge.swift:41-47`; `Runner.swift:72-96`; `RunnerTests.swift:241-251, 306-323` |
| Live path: one opt-in env-gated smoke; free CI replay seam | ✅ (not exercised here) | `RunIntegrationTests.swift:313-322`; consented live validation recorded in design v0.13 |

### F8 — Frozen boundary codecs
| Claim | Verdict | Evidence |
|---|---|---|
| `evals.json` decodes 2.0 object **and** legacy array; correct `caseCount`; faithful both-shape round-trip | ✅ | `EvalsFile.swift:15-79`; `EvalsFileTests.swift:32-79` |
| Run-record family + `trigger-eval.json` + SARIF subset; unknown keys preserved | ✅ | `RunRecords.swift` (incl. `eval_metadata.json`), `TriggerEvalFile.swift`, `Sarif.swift`; raw-hold + verbatim re-emit (the `extra`-catch-all wording in the 06-24 log entry is historical — the 06-25 review replaced that idiom) |
| Semantic golden compare, synthetic fixtures | ✅ | `jsonSemanticEqual` (`JSONValue.swift:74-84`); byte test pins `3` not `3.0` |
| `scorecard.json` not adopted; bundle assembly deferred | ✅ | zero hits; no bundle assembly anywhere |
| v1.9.5 shape: `configuration:"default"` string, per-trial `runs[]`, expectation-counting `result` + `pass_rate`, `consistency` block as recompute source, numeric-id coercion | ✅ | `RunRecordMapping.swift:23-123`; `RunRecordMappingTests.swift:24-86` (writer lives in `RunCommand.swift:321-334`; RunKit writes cache forensics only) |
| §7.2 prose reconciled | ⚠️ **was half-done** | benchmark/SARIF rows current (v0.17); `evals.json` row was still legacy-only, family + `scorecard` exclusion unnamed, `Tests/Golden/boundary/` fictional → **completed this pass** (design v0.21) |

## 4. Cross-cutting verification

| Area | Verdict | Evidence |
|---|---|---|
| §11 target DAG (Phase-1 subset), no `skilletCLI` | ✅ exact | `Package.swift:27-102`; JudgeKit ↛ HarnessKit; LintKit ↛ ConfigYAML |
| `.Cxx` confinement + dependency pins | ✅ | 3 targets (`ConfigYAML`, executable, `ConfigYAMLTests`); pins = Package.resolved |
| Sanctioned deps only; launcher monopoly | ✅ | 4 declared packages; zero forbidden process APIs (see M4 for the swift-system charter note) |
| Test topology; tags; binary discovery + `SKILLET_TEST_BINARY` | ✅ | `Package.swift:105-124`; `TestHarness.swift:18-68`; `Tags.swift` |
| 300-line test-file soft cap | ⚠️ 2 over | `RunnerTests.swift` 345, `RunIntegrationTests.swift` 323 (rest ≤184) |
| Constitution VI (no real logs/secrets) | ✅ clean | synthetic-only fixtures; credential greps clean |
| Verified-docs harness | ⚠️ narrow | dump-help = subcommand **names** only; link checker covers `README/AGENTS/ROADMAP.md` only, markdown links only — precisely why every drift item below survived it (A28) |
| CI | ❌ **absent** | `.github/workflows/` empty since 2026-06-20 → M1 |

## 5. Major findings (decisions needed — **not** applied)

*External evidence per finding: [§8](#8-external-cross-reference-addendum-2026-07-01).*

**Dispositions (2026-07-01):** M1 implemented — `.github/workflows/ci.yml` authored (first verified
run lands with the next push) · M2 implemented — §14-4 decided, required-explicit (`run` exit 2 on an
absent `judge.model`) · M3 implemented — additive provenance in `benchmark.json`/`grading.json` via
`RunProvenance` · M4 drafted, pending maintainer ratification. §8's R1 (`pass_1`) was adopted and
shipped the same day (§14-11 → Decided). ROADMAP v1.10.0 carries the consolidated entry.

- **M1 · No CI workflow exists.** Constitution V MUSTs (macOS 14+ & Ubuntu LTS build/test, merge gates, free-suite-always) have no workflow behind them; every "free CI" statement across the docs describes a suite that today runs only locally. *Recommend:* commit the free-suite workflow (macOS + Ubuntu, `swift test --skip slow`) before the next feature lands, or record an explicit CI deferral in the constitution.
- **M2 · `judge.model` is not required-explicit.** Constitution II: "MUST … require an explicit judge model"; design §14-4 assumes required-explicit. Shipped: `init` writes it explicitly (half satisfied) but the decode silently defaults to `claude-sonnet-4-6` when absent (`SkilletConfig.swift:128-144`). *Recommend:* decide §14-4 — either enforce (absent key → error naming the fix) or amend the assumption; until decided this is a standing constitution-II deviation.
- **M3 · Committed-record provenance gap.** Design §7.2/§9.1 say `benchmark.json` carries `executor_binary_version` and `judge_prompt_version`; shipped committed records carry judge provider+model only — `judge_prompt_version` survives only in the deletable cache (`verdicts.json`), and `executor_binary_version` appears nowhere in the codebase. Cross-run deltas can't yet be attributed harness-vs-skill from committed files, and v1- vs v2-graded runs are indistinguishable after a cache wipe. *Recommend:* additive metadata fields in the F7 writer (small, frozen-format-safe) — natural home: early Phase 2 (F19 record/replay or with F16).
- **M4 · Constitution's swift-system note is false.** Charter says swift-system is a "test-only transitive dep … no shipped runtime dependency" (constitution Technology Stack), but `SystemPackage` is a declared **production** dependency of HarnessKit (`Package.swift:62`; `ProcessLauncher.swift` imports). AGENTS was updated; the authoritative charter was not. *Recommend:* PATCH amendment updating that note (and, same pass: add `RenderKit` to the charter's §11 layer diagram; drop the out-of-domain "onion/control credentials" phrase in Principle VI — copy-in artifact).

## 6. Reconciliation applied in this pass (docs only)

| Artifact | Fix |
|---|---|
| `Roadmap/phase-1-walking-skeleton.md` | F2 metric: "three next commands" → the honest registered subset (A4) · F6 gap #3 → closed-with-residual (A3) · F7 recompute → `consistency` block (A1) · dated audit change-log entry; history entries untouched |
| `AGENTS.md` | `docs/roadmap/` → `Roadmap/` ×2 (A30) · `LintKit` added to the banner kit list (A39) · `run` flag list gains `--no-input`/`--keep-workspace` · `.Cxx` note gains `ConfigYAMLTests` (A38) · dump-help claim scoped to names-today (A42) |
| `README.md` | F8 added to the landed-features status line (A29) |
| `skillet-design.md` → **v0.21** | §7.2 `evals.json` row → 2.0-canonical + legacy-on-read; family + `scorecard` exclusion named; goldens described as synthetic/inline (A8, A14) · §9.3 goldens wording → synthetic-mirroring (constitution VI) (A9) · §10 recompute parenthetical → `consistency` block (A2) · §9.1 two phase-boundary annotations (winning-link printing, auto-fallback = F50; F7 refuses) (A11) · §14-4 shipped-state note (M2 pointer) · §14-8 stale `(F5)` → `(F45)` (A10) |
| `Sources/skillet/skillet.docc/TestingEndToEnd.md` | resolution chain drops the nonexistent `--harness-path` flag (A41) · CI note now says "when wired" (M1 pointer) |
| `Specs/001–007/plan.md` | dated post-audit deviation rows: 001 (flat `EDDError`, inline goldens, inert `-q`/`-v`) · 002 (honest next-filter, ToolInfo substitution, template growth, 06-23 fix) · 003 (`ReplayAdapter` naming, `probe(strict:)`) · 004 (fallback → F50, refusal semantics, inline fixture) · 005 (run preflight + strict loader reuse) · 006 (session-meta not shipped → Phase 3; v1.9.5 supersedes the `configuration` enum; producer mapping placement; §7.2 completed) · 007 (round 9; as-built cache layout; `JudgeRunner` seam; `--permission-mode acceptEdits`) |
| `ROADMAP.md` → v1.9.9 | audit change-log entry linking this review |

## 7. Minor findings — recorded, no doc edit required

| ID | Finding | Suggested home |
|---|---|---|
| A15 | `-q`/`-v` parsed but wired to nothing (`GlobalOptions.swift:21-25`) | wire or drop (Phase 2 F24) |
| A17 | `RunCommand.swift` = 342 lines of real logic vs the "~≤50-line wiring" §11 claim (`InitCommand` 71 · `HarnessCommand` 86 · `LintCommand` 96 are mildly over) | extract into kits at next F7-adjacent touch |
| A18 | judge subprocess uses a fixed 120 s timeout — `runs.timeout` governs trials only (`ClaudeCLIJudgeRunner.swift:15`) | F18 |
| A19 | `.sessionCapture` capability bit declared while `locateSessions`/`exportSession` throw `notImplemented` ("Phase 3") | flip the bit with Phase 3, or accept convention |
| A20 | no `judging` capability bit on the claude-code adapter (judge wired via RunKit runner) — design §9.5 matrix targets ✓ | F16 |
| A25 | `Denylist.Decision.warnedFallback` name + doc comments still say "falls back"; no fallback exists | rename with F50 |
| A26 | stale code comments cite F3 for frontmatter rules re-homed to F20 (`FrontmatterParser.swift:7`, `SkillFrontmatter.swift:3-4`) | trivial comment fix |
| A21 | `lint` suggests `→ next: skillet run` even when its own error-tier finding guarantees `run` will refuse | UX polish (TTY prose, non-API) |
| A22 | missing-evals remedy says "see `skillet init`", but `init` scaffolds directories, not an `evals.json` | wording polish |
| A16 | init's empty-repo "add a SKILL.md" guidance is dead code (`available` never empty since lint/run registered) | remove or revive with `doctor` |
| A28 | link checker: extend to `Roadmap/`, `Specs/`, docc (with dir-relative resolution) — the blind spot that hid every doc-drift item here | Phase 2 (verified-docs) |
| A47 | `--replay` is a hidden test-only flag per plan 007, yet the docc walkthrough documents it for users | formalize as public F19 |
| A32 | `skillet.trace/1` has no CLI emitter yet (model-only) | arrives with capture (Phase 3) |
| A37 | test-file cap: split `RunnerTests` (345) / `RunIntegrationTests` (323) at next touch | hygiene |
| A34 | trial sandboxes live under `.skillet/runs/…` (repo-local, not `$TMPDIR`) — consistent with P2/D3 + forensics; noted because design §5.2 lists `TMPDIR` for workspace scratch | doc nuance only |

**Historical entries deliberately not rewritten:** the 06-24 "`extra` catch-all" wording (mechanism replaced 06-25), the 06-24 "§7.2 prose reconciliation still pending" note (completed by this audit — see the new change-log entry), `HarnessReplay` in the 06-21 entries (shipped as `ReplayAdapter`), and every per-round test count. Change logs record what was true when written; only current-state text was reconciled.

## 8. External cross-reference addendum (2026-07-01)

The findings above were cross-referenced against published EDD / LLM-evaluation best practice in
three deep-research passes (~29 primary sources; claims verified by 3-vote adversarial passes where
budget allowed, single-pass verbatim primary-source checks otherwise — confidence noted per row).
**Nothing contradicts shipped Phase-1 behavior.** Verdicts:

| Audit position | Verdict | Primary evidence |
|---|---|---|
| pass^k semantics (per-eval PASS iff **all** recorded trials pass; aggregate = fraction of evals; observed k = `min`) | **Supported** (3-0, twice) | Definitionally identical to τ-bench's pass^k — Yao et al. 2024, [arXiv:2406.12045](https://arxiv.org/abs/2406.12045); Chen et al. 2021 ([arXiv:2107.03374](https://arxiv.org/abs/2107.03374)) is the correct ANY-pass contrast (τ-bench's own ref [5]) |
| FLAKY (`0 < passes < recorded`) + hygiene-before-deltas | **Supported** (3-0) | Google's canonical definition verbatim ([Micco 2016](https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html); [Listfield 2017](https://testing.googleblog.com/2017/04/where-do-our-flaky-tests-come-from.html)); ~84% of pass→fail transitions in Google's CI involve a known-flaky test — deltas untrustworthy without flake triage; alarm-fatigue rationale for surfacing over retry-to-green |
| "Variance unmeasurable" below k = 2 | **Supported** | Single-trial outcomes are inconclusive (Listfield 2017); nondeterminism *in the system under test* is explicitly in scope — in skillet's case it is the thing being measured |
| Existence check via the post-run workspace listing (claimed-but-not-created FAILs) | **Supported** (verbatim primaries) | Anthropic, ["Demystifying evals for AI agents"](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents) (2026): the outcome is the *final environment state* — the flight-"booked"-claim vs reservation-in-DB example is exactly this rule; τ-bench final-DB-state comparison; SWE-bench ([arXiv:2310.06770](https://arxiv.org/abs/2310.06770)) fail-to-pass tests — the model's claims play no role |
| M1 — CI (free suite as the PR gate) | **Supported** | lm-evaluation-harness ([unit_tests.yml](https://github.com/EleutherAI/lm-evaluation-harness/blob/main/.github/workflows/unit_tests.yml)) and Inspect AI ([build.yml](https://github.com/UKGovernmentBEIS/inspect_ai/blob/main/.github/workflows/build.yml)) run model-free, zero-LLM-credential suites on every PR (3-0, live workflows 2026-07-01; paid-API tests self-skip); promptfoo/openai-evals consistent with scoped nuances; walking-skeleton canon (Freeman & Pryce, *GOOS* ch. 4 — build/deploy/test automation **before** the first feature) supports "CI before the next feature lands" |
| M2 — judge required-explicit | **Nuanced → keep, reframed** | *Stricter than surveyed convention, deliberately:* promptfoo silently defaults its grader from ambient credentials (3-0 — [docs](https://www.promptfoo.dev/docs/configuration/expected-outputs/model-graded/) + `src/providers/defaults.ts`), so the identical config can be judged by different models on different machines — exactly the hazard M2 targets. Frame as a reproducibility stance, not an industry norm |
| M3 — committed-record provenance | **Directionally supported** (leads unverified) | MLflow tracking norms, the NeurIPS reproducibility checklist (Pineau et al., [arXiv:2003.12206](https://arxiv.org/abs/2003.12206)), and EvalGen's criteria drift (Shankar et al., [arXiv:2404.12272](https://arxiv.org/abs/2404.12272)) all align but did not complete adversarial verification; the irreversibility argument (provenance not captured at run time is unrecoverable) stands on its own |
| Judge injection-hardening | **Directionally supported** (leads unverified) | OWASP [LLM01](https://genai.owasp.org/llmrisk/llm01-prompt-injection/) segregate-untrusted-content + validate-output-format; null-model judge attack ([arXiv:2410.07137](https://arxiv.org/abs/2410.07137)); JudgeDeceiver ([arXiv:2403.17710](https://arxiv.org/abs/2403.17710)). Treat the hardening as **mitigation, not immunity** |
| Held-out proof gate (F45) | **Supported** (verbatim primaries) | DSPy docs recommend a 20/80 train/validation split *because* "prompt-based optimizers often overfit to small training sets"; GEPA ([arXiv:2507.19457](https://arxiv.org/abs/2507.19457)) selects on held-out Pareto performance. (Negative note: Anthropic's evals post does **not** discuss holdout — don't cite it for this) |
| §7 minors deferral | **No urgency evidence** | [clig.dev](https://clig.dev/) defines `-q`/`-v` semantics but is silent on parsed-but-inert flags (soft pressure only: wire them or remove them); nothing treats line caps or command-file size as more than style |

**Corrections the cross-reference forced** (both applied, design v0.22): the §10 infra-only-retry
rule was framed as received "flaky-test best practice" and Appendix C.2 credited it to pytest/jest —
no primary source states that rule (full-text verification of both Google posts; pytest-rerunfailures/
jest re-run *any* failure by default). It is now stated as **skillet's own discipline**. And one **new
evidence-driven finding**:

- **R1 — report `pass^1` alongside strict pass^k (staged as design §14-11).** τ-bench estimates
  pass^k with the unbiased estimator `E[C(c,k)/C(n,k)]` over n recorded trials and **headline-reports
  pass^1** (= average reward), with pass^k curves as the reliability trend (verified 2-0 against the
  paper *and* `sierra-research/tau-bench` `run.py`). skillet's binary all-recorded-trials rule equals
  that estimator only at k = n; under mixed recorded counts it is **strictly conservative
  (downward-biased)** — a legitimate reliability stance, but the report should carry `pass_1` for
  comparability and document the conservatism. *(Adopted + shipped 2026-07-01: `pass_1` in
  `skillet.run/1`, `suite_pass_1` in `consistency`, conservatism documented in design §10 —
  §14-11 → Decided.)*

**On existence-now / content-later (F16):** a defensible **one-phase** staging — but every mature
exemplar verifies *content* from inception (τ-bench record values; SWE-bench executing tests;
WebArena backend-state checks), and τ-bench itself concedes state-match is "necessary but not
sufficient." F16 is therefore closure of a real, named gap — priority, not polish — and per
Anthropic's "deterministic graders where possible," its content checks should lean deterministic
(substring/structured/executable assertions) before expanding LLM-judge scope.

**Citation policy (why this addendum exists):** IIA Global Internal Audit Standards 14.1 (findings
rest on relevant, reliable, **sufficient** information — sufficiency defined so a competent person
could repeat the work and reach the same conclusions), ISO 19011's evidence-based-approach principle
(verifiable evidence as "the rational method for reaching reliable and reproducible audit
conclusions"), and ADR practice ([Nygard 2011](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions))
all endorse embedding verifiable evidence in findings and decision records — and risk-based
remediation (not fix-everything) is the corresponding norm for acting on them, matching this audit's
§5/§7 triage. Empirically, the cross-reference confirmed three positions verbatim and corrected two
(the retry-rule attribution; the estimator nuance) — the value citations lock in.
