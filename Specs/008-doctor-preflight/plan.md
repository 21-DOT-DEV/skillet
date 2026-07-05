# Plan — Phase 2 · F3: $0 preflight & skill-visibility check (`skillet doctor`)

| | |
|---|---|
| **Feature** | F3 — $0 preflight & skill-visibility check (CLI: `skillet doctor [<skill>...]`) |
| **Phase** | 2 — Trustworthy Measurement & Static Gates ([Roadmap/phase-2-measurement-static-gates.md](../../Roadmap/phase-2-measurement-static-gates.md), F3) — **first Phase-2 feature** (unblocked: depends only on shipped Phase-1 seams) |
| **Status** | IMPLEMENTED (2026-07-04) — `DoctorCommand` + pure `EDDCore.DoctorReport` (frozen `skillet.doctor/1`, golden-tested) + `HarnessKit.SkillBundleAudit` (staging-parity, guarded by `RunKitTests/StagingParityTests`) + additive `HarnessInfo.binaryPath`/`source`/`bannedVersion`; `verifySkillVisibility` deepened to audit-backed; skill selection factored into the shared `selectSkillDirectories` (lint + doctor, no drift); auth = warning row. **258 tests green (+21**: 5 report unit/golden, 7 audit, 1 parity, 8 binary-integration incl. shim-probed healthy/unauth paths**)**. Both roadmap F3 metrics verified against the built binary. **Post-review hardening (2026-07-04, 5-finding slate):** staging rules now **code-shared** via `SkillBundleRules` (HarnessKit), consumed by both the audit and RunKit's stager — §3 is literal, with `StagingParityTests` kept as the walk-structure guard; remedies interpolate real names (`EDDError.harnessNotFound`/`harnessBanned` + doctor's generic probe path print `SKILLET_CLAUDE_CODE_BIN`, not `<ID>` placeholders — P6 copy-pasteable); `DoctorReport.remedy` doc broadened (warnings may carry one, e.g. auth); the project is located once per invocation (`loadConfigWithOrigin(context:)`, threaded through `doctor`/`lint`/`run`); the visibility failure row joins a SKILL.md issue + dropped symlinks in one pass (real-reason remedy; audit hoisted to once per skill); healthy-but-zero-skills suggests authoring a skill, not re-`init`. 260 tests green (+2: both-issues audit unit + one-pass integration). **Round 2 (2026-07-04):** `skillet.doctor/1` rows are **presence-guaranteed** (decided in-session — every check that runs emits ≥1 row per subject; an absent check id means *not run*, never silent-pass; lint emits a clean pass row, closing the passed-vs-not-run ambiguity); `Row.pass/.warning/.failure` factories make the failure remedy **required by construction**, verified end-to-end by a JSON invariant test over a multi-failure run (missing binary + dropped symlink + lint error → every failure row carries a remedy); the zero-skills next-step honors the configured `skills_root` (+ the first zero-skills integration test, custom root); redundant post-select sort dropped (`SkillScanner.scan` pre-sorts); README shows `doctor [<skill>...]`; current-state docs synced (262) and `doctor` removed from AGENTS' still-planned list. 262 tests green (+2). |
| **Last updated** | 2026-07-04 |
| **Builds on** | F1 (`ProjectLocator`, `GlobalOptions`/`--json`, exit codes, `SkilletJSON`); F4 (name-only skill selection, `SkillReader`, LintKit catalog); F5 (`HarnessAdapter` seam — `verifySkillVisibility` + `InjectionStrategy` signatures shipped); F6 (`ClaudeCodeAdapter` `probe`, `BinaryResolver` + winning-link `Source`, `Denylist`); F7 (strict config loader, bundle-staging filter rules, `probe(strict:)` auth); F8 (`SchemaIdentified` + golden discipline) |
| **Authoritative refs** | design §6.1 `doctor` (checklist — F3 ships the phase-metric subset), §9.2 (positive-load condition; discovery-only half **deferred** per phase Notes), §9.1 (resolution & ban policy), P6 (errors teach), P3 (suggested next step); constitution I (TDD), III (frozen contracts — new `skillet.doctor/1`), IV (CLI conventions), V (free-before-paid — doctor is the $0 gate) |
| **Scope decision** | **Option 2 — contract-complete, checks-subset** (decided 2026-07-03 in-session, after a doctor-pattern survey: brew/npm/wp-cli/gh/flutter). Ship doctor's end-state *contract* now — check-registry rows, frozen `--json` schema, warn-never-fails exit semantics — and light up only the phase-metric rows. Two deliberate above-metrics additions: the frozen **`skillet.doctor/1`** schema (+ golden) and the **registry row shape** (later doctor features land as additive rows, never contract changes). Auth is a **warning** row (the $0 spend-gate stays `run`'s shipped strict preflight, per the F3 phase Notes). |
| **Workflow** | Standalone plan (spec-kit workflow intentionally skipped) |

---

## 1. Goal

Ship `skillet doctor` — the free, fast self-check that catches the silent killers before any paid
run: config parses (and says which file loaded), each harness resolves (binary, version, denylist,
winning resolution link), the skill is actually *visible* to the harness (the positive-load half of
the §9.2 contract — the `--skill-path` false-negative class, killed by construction, P6), and the
free error-tier lint gate is green. Exit `3` with a remedy line on any failure; warnings never fail.

**Success criteria (roadmap F3 metrics, verbatim):**
- `doctor` reports config origin (which file loaded), harness version/resolution, and per-skill
  visibility, exiting `3` with a remedy line on any failure.
- Verifies the positive-load condition (target `SKILL.md` **+ `references/`** resolve under the
  injection strategy); error-tier `lint` findings surface here and also fail (exit `3`), warnings
  shown but non-failing.

**Contract additions (Option 2, recorded above):**
- `--json` emits frozen **`skillet.doctor/1`** (registry rows: `check` / `subject` / `status` /
  `message` / `remedy`), golden-tested per the F8 discipline.
- Exit contract: `0` = no failure rows (warnings OK — the brew-doctor lesson), `3` = any failure
  row, `2`/`4` unchanged shared strict-loader classes (bad `--config` path / undecodable YAML).

## 2. Scope

### In scope
- **`EDDCore`**: pure `DoctorReport` (`SchemaIdentified`, `skillet.doctor/1`) — rows + pure
  healthy/exit derivation. No I/O.
- **`HarnessKit`**: `SkillBundleAudit` — the positive-load dry-run sharing the F7 staging filter
  semantics (symlink/hidden rules); `ClaudeCodeAdapter.verifySkillVisibility` deepened from
  "`SKILL.md` exists" to audit-backed; `HarnessInfo` gains additive optional `binaryPath`/`source`
  (the winning resolution link — already captured by `BinaryResolver`, now surfaced).
- **executable**: `DoctorCommand` (slots into the reserved subcommand list) composing shipped
  seams — `ProjectLocator`, strict config load **+ origin** (extends `ConfigSupport`; its comment
  already reserves origins for doctor), skill selection (named subset or all discovered, the lint
  path), per-harness `probe(strict: false)`, per skill×harness visibility audit, LintKit catalog
  (error tier ⇒ failure rows, warn tier ⇒ warning rows). **RenderKit**: `renderDoctor` (TTY
  `✓/!/✗` rows + P3 next step; JSON via `SkilletJSON`).
- **Tests**: EDDCore report unit + codec golden; HarnessKit audit unit tests; IntegrationTests
  driving the built binary (healthy → `0`; missing binary → `3` + remedy; lint-error skill → `3`;
  corrupt config → `4`; `--json` shape) with a shim harness binary for the healthy probe.

### Out of scope (with where it lands)
- `--paid` canary → **F21**. Frontmatter spec-conformance rows → **F20** (surface here once they
  are lint rules). Discovery-only visibility half (siblings listable-not-injected) → deferred by
  the F3 phase Notes (refined when the `visible:` set is exercised live). Auth as *failure* →
  stays `run`'s strict preflight ($0, pre-spend, shipped F7). `evaluations/` artifact-schema
  sweep → with F19/F22-era features (loaders already fail loud at point of use). `git` presence →
  with `iterate` (Phase 6). betterleaks resolution → with `capture` (Phase 3; not vendored yet).
  Per-value config origins (`config list --origins`) → **F24** (doctor reports the *file* origin
  only). User-defined check config (wp-doctor style `doctor.yml`) → not planned; the registry is
  a report shape, not a config surface. Implicit doctor-before-paid-commands → already shipped in
  subset form as `run`'s F7 preflight.

## 3. Architecture (targets touched)

```
skillet (exe)  ──▶  DoctorCommand: wiring only (ArgumentParser, row assembly, renderer, exit)
  ├─ EDDCore        DoctorReport (pure rows + exit derivation; skillet.doctor/1)
  ├─ HarnessKit     SkillBundleAudit + deepened verifySkillVisibility + HarnessInfo.source
  ├─ LintKit        (unchanged) full shipped catalog, reused via LintSupport
  ├─ ProjectKit     (unchanged) ProjectLocator
  ├─ ConfigYAML     (unchanged) strict loader, now reporting origin via ConfigSupport
  └─ RenderKit      renderDoctor (TTY + JSON)
```

Dependency directions are unchanged (strictly downward). The staging-filter *predicate* lives in
`HarnessKit` so both the audit (doctor) and RunKit's stager can share it without a new edge —
RunKit already depends on HarnessKit.

## 4. Detailed design

### 4.1 EDDCore (pure)
`DoctorReport`: `rows: [Row]`; `Row = {check, subject?, status, message, remedy?}` with
`status ∈ {pass, warning, failure}` and frozen dotted check ids: `config`, `harness.binary`,
`harness.version`, `harness.auth`, `skill.visibility`, `skill.lint` (additive-only list).
`healthy = no failure rows`; `exitCode = healthy ? .success : .environment`. Failure rows carry a
non-nil `remedy` (tested). Encoded via `SkilletJSON` (snake_case), schema-tagged.

### 4.2 HarnessKit
`SkillBundleAudit.audit(skillPath:)` walks the bundle exactly as F7 staging sees it (skip the
private `evaluations/` namespace; flag **symlinks at any depth** as offenders — staging drops
them, so the model-visible bundle would be silently incomplete, the false-negative class; collect
**hidden files** as `droppedHidden` warnings — policy-dropped, usually benign). Missing/symlinked
`SKILL.md` = offender. `ClaudeCodeAdapter.verifySkillVisibility` = audit + throw
`EDDError.skillNotVisible` naming offending paths (protocol signature unchanged); `ReplayAdapter`
stays trivially visible. `HarnessInfo` gains `binaryPath: String?` + `source: String?` (additive,
defaulted `nil`) filled from `ResolvedBinary` in `probe`.

### 4.3 executable + RenderKit
`DoctorCommand` flow: locate project → strict config + origin (`explicit --config` | repo
`skillet.yaml` | built-in defaults; undecodable → exit `4`, missing `--config` → `2` — shared
classes) → select skills (args or discover; unknown name = same error class as `lint`) → for each
paid-capable harness (claude-code; replay is a test seam, exercised in unit/integration tests):
`probe(strict: false)` → rows: binary (available + path + winning link; failure w/ pin remedy),
version (denylisted ⇒ **failure** — `run` will refuse; remedy: pin a non-banned build), auth
(**warning** w/ `claude auth login` remedy) → per skill: visibility row from the audit
(offenders ⇒ failure listing paths; `droppedHidden` ⇒ warning), lint rows from the shipped
catalog (error tier ⇒ failure w/ fix-hint remedy, warn tier ⇒ warning). Render: TTY rows
`✓/!/✗` grouped project → harness → skills, summary + next step (`skillet run <skill>` when
healthy); `--json` = the report. Exit via `SilentExit(report.exitCode)`.

### 4.4 Config
No new knobs. (`doctor` honors existing `-C`, `--config`, `--json`, color/verbosity globals.)

## 5. Test plan (TDD)
- **EDDCoreTests/DoctorReportTests**: exit derivation (all-pass → 0; warnings-only → 0; any
  failure → 3); failure-rows-carry-remedy invariant; codec golden (exact frozen JSON, schema tag,
  snake_case, stable row order).
- **HarnessKitTests/SkillBundleAuditTests**: ok bundle; missing `SKILL.md`; symlinked `SKILL.md`;
  symlink inside `references/` (offender named with relative path); hidden file → warning not
  offender; `evaluations/` contents ignored; deepened `verifySkillVisibility` throws with paths.
- **IntegrationTests/DoctorIntegrationTests** (built binary + shim claude): healthy fixture →
  exit 0 + origin line + ✓ rows; `--json` → `skillet.doctor/1` + `healthy` derivable (no failure
  rows); missing binary (`SKILLET_CLAUDE_CODE_BIN=/nonexistent`) → 3 + remedy; lint-error skill
  (>1024 description) → 3; corrupt `skillet.yaml` → 4; unauthenticated shim → 0 with `!` auth row.
  300-line test-file cap: split audit vs command suites if needed.

## 6. Task breakdown (ordered)
1. `EDDCore.DoctorReport` + unit/golden tests → green.
2. `HarnessKit.SkillBundleAudit` + `HarnessInfo` additive fields + deepened
   `verifySkillVisibility` + unit tests → green.
3. `RenderKit.renderDoctor` + `ConfigSupport` origin + `DoctorCommand` + wiring.
4. `IntegrationTests` (shim harness) → full suite green.
5. Docs ripple (doc-sync contract): design §6.1 shipped-subset annotation + §7.5/§12
   `skillet.doctor/1` rows + revision log; phase-2 F3 → IMPLEMENTED + change log; ROADMAP MINOR +
   change log; README command table; AGENTS surface line; `Specs/README.md` + this header → IMPLEMENTED.

## 7. Risks & assumptions
- **Staging-parity drift**: the audit re-states the F7 staging filter; if the stager's rules
  evolve, the audit could lie. Mitigation: shared predicate in HarnessKit + a test asserting the
  audit flags exactly what staging drops.
- **Probe cost**: doctor shells `--version` + `auth status` once per harness — free and fast; no
  network beyond the local CLI's own behavior.
- **Registry growth**: later rows (F20/F21/…) must stay additive in `skillet.doctor/1` — enforced
  by the golden + the frozen check-id list note.

## 8. Definition of done
- All §5 tests green in the full suite (`swift test`), no regressions.
- `skillet doctor` on the repo's own fixture project: healthy → `0`; each planted failure class →
  `3` with a remedy line; `--json` golden-stable.
- Docs ripple landed (task 6.5); constitution untouched.
