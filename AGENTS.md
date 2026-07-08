# AGENTS.md (skillet)

`skillet` — the **SKILL.md Evaluation Toolkit** — is a public, open-source, multi-harness Swift
CLI for eval-driven development (EDD) of agent skills: capture real runs, turn hand-fixes into
structured evidence, and ship a `SKILL.md` edit only after a previously-failing eval proves it.

> **Status: Phase 1 COMPLETE — F1, F2, F4–F8 landed** ([completed-items audit](Roadmap/phase-1-review.md));
> **Phase 2 IN PROGRESS — F3 (`skillet doctor`, the $0 preflight) and F14 (`skillet run --axis
> trigger`, the deterministic description axis) shipped 2026-07-04; F15 (`skillet run --ab`, the
> provably skill-free baseline arm with paired Δ) shipped 2026-07-07**
> ([Specs/008](Specs/008-doctor-preflight/plan.md), [Specs/009](Specs/009-trigger-axis/plan.md),
> [Specs/010](Specs/010-ab-baseline/plan.md)).
> `Package.swift` plus `EDDCore`, `TraceKit`,
> `ProjectKit`, `RenderKit`, `HarnessKit`, `LintKit`, `JudgeKit`, `RunKit`, `ConfigYAML`, and the
> `skillet` executable exist — the executable owns the full ArgumentParser command tree (no
> `skilletCLI` library; `ProjectKit` is the discovery/config-IO home) — with 321 tests green
> (`swift build && swift test`). Shipped commands: `init` · `doctor` · `lint` · `run` · `harness
> list`/`info` — see *Commands* below. **Per-feature records live nearest the artifact**: each
> feature's detailed capsule is its [`Specs/NNN` plan](Specs/README.md) status, with design-only
> changes in [`skillet-design-changelog.md`](skillet-design-changelog.md); this banner stays a
> current-state summary — one clause per feature, no history. Everything under *Planned* is still
> agreed **intent, not shipped fact** — don't assume a command/module exists until its feature
> lands. Update this file as each feature/phase completes.

## Source-of-truth documents (read these first)

- **`skillet-design.md`** — the product spec. Authoritative for *what skillet does*: product
  principles P1–P10, settled decisions D1–D7, command surface (§6), file formats (§7), gates
  engine (§8), harness abstraction (§9), package architecture (§11), distribution (§12), v1 scope
  (§13), open questions (§14). Its revision history lives in
  [`skillet-design-changelog.md`](skillet-design-changelog.md).
- **`ROADMAP.md`** (+ `Roadmap/phase-*.md`) — the phase plan. Authoritative for *sequence and
  priority*. Phase 1 is the walking skeleton; do the earliest incomplete phase unless told
  otherwise. Its versioned history lives in [`ROADMAP-changelog.md`](ROADMAP-changelog.md).
- **`.specify/memory/constitution.md`** — the development charter. **Authoritative for *how we
  build* skillet** (7 principles, MUST/SHOULD/MAY, governance). When in doubt about a development
  practice, the constitution governs — do not duplicate its principles here; read it.

Contributing, security disclosure, and code of conduct are handled at the org level:
[`21-DOT-DEV/.github`](https://github.com/21-DOT-DEV/.github) (`CONTRIBUTING.md`, `SECURITY.md`,
`CODE_OF_CONDUCT.md`). There are intentionally no repo-local copies.

## Commands (true now — Phase 1 / F1, F2, F4–F8)

- `swift build` — build the package (resolves `swift-argument-parser`, `swift-subprocess`, `swift-system`, `swift-yaml`).
- `swift test` — run the unit + integration suites (321 tests, all green). The integration suite drives
  the built binary, which `swift test` builds first; filter with tags, e.g. `swift test --skip slow`.
- `.build/debug/skillet` — the CLI: try `skillet`, `skillet --json`, `skillet -C <dir>`, `skillet init`,
  `skillet init --json`, `skillet doctor [<skill>...] [--json]` (free $0 preflight; exit 3 + remedy on failure),
  `skillet lint [--json]`, `skillet harness list`, `skillet harness info [--json]`,
  `skillet run [<skill>] [--axis behavior|trigger|all] [--ab] [--runs <k>] [--dry-run] [--yes] [--no-input] [--keep-workspace]` (paid: shells `claude` — behavioral trials add the judge; trigger trials are judge-free single calls; `--ab` doubles behavioral trials with a provably skill-free baseline arm, both arms judged — gated by the combined spend estimate),
  `skillet --help`, `skillet --version`. Hidden test seams on `run`: `--replay` (offline adapter+judge),
  `--replay-map <json>` (with-arm canned verdicts), `--replay-baseline-map <json>` (baseline-arm canned
  verdicts; defaults to fail-all so a replayed `--ab` shows a deterministic positive Δ).
- `swift package generate-manual` / `generate-docc-reference` — regenerate the command reference from the parser.
- `SKILLET_TEST_BINARY=<path> swift test` — point the integration harness at a specific binary.
- CI: `.github/workflows/ci.yml` runs the free suite on macOS (`macos-26`, `DEVELOPER_DIR` pinned to
  Xcode 26.5 for determinism) + Ubuntu (official `swift:6.3` container) on every push/PR — zero
  secrets, zero paid calls; the live smoke self-skips (opt-in locally via `SKILLET_LIVE_SMOKE=1`).
  Historical note: the 2026-06 macOS-only CI failures were an upstream Swift C++-interop bug, fixed
  in swift-yaml (diagnosis + repro live in its `Projects/`); no Swift-version floor beyond Swift 6.

`init`, `doctor`, `lint`, `run`, `harness list`/`info`, and the claude-code adapter (parse + resolution + probe + live `run`) are built; `capture`/`next`/… are not yet — see Planned.

## Binding conventions

These are real rules from the constitution + design decisions. Follow them in any code you write,
from the first commit.

- **Language**: Swift 6 with strict concurrency (`swiftLanguageModes: [.v6]`), Swift Package
  Manager.
- **Sanctioned dependencies only** (adding any other requires a constitutional amendment):
  `swift-argument-parser`, `swift-yaml` (YAML 1.2 — config + evidence frontmatter; *not* Yams, and
  there is **no TOML dependency**), `swift-subprocess`, plus the standard library. JSON/SARIF/frozen
  formats use Foundation `Codable` (no added dependency). Secret scanning uses a vendored
  `betterleaks` (MIT) companion. The cache MAY use system SQLite.
- **Dependency notes (implementation reality):** `swift-yaml` has **no tagged release**, so it is
  **pinned by revision** (`048f714f…`). Its `YAML` product needs **C++ interop**, which is **viral to
  direct importers** — so it is confined to the isolated **`ConfigYAML`** target
  (`.interoperabilityMode(.Cxx)`), which exposes a pure-Swift API (decoding into `EDDCore.SkilletConfig`).
  Consequence (validated by the F6 spike): the `skillet` executable, as a direct importer, is a **`.Cxx`
  leaf** too (as is `ConfigYAMLTests`, the codec's own test target — the third and last `.Cxx` island) —
  but every kit and the pure core stay interop-free (they take a decoded `SkilletConfig` as
  input and never import `ConfigYAML`). `swift-subprocess` is now used by **`HarnessKit`** (the
  `ProcessLauncher` seam) as well as the integration-test harness; `swift-system` (`FilePath`) rides in
  with it. Known-good pins: `swift-argument-parser` 1.6.2, `swift-subprocess` 0.2.1, `swift-system`
  1.5.0, `swift-yaml` rev `048f714f…`.
- **`swift-subprocess` is the only sanctioned way to launch a process** — no `Foundation.Process`,
  no raw `posix_spawn`. All process execution lives in the effectful layers.
- **`EDDCore` is pure and synchronous** — it spawns nothing and performs no I/O beyond its inputs.
  Everything probabilistic or effectful (model calls, processes, network, filesystem) lives behind
  a protocol *above* `EDDCore`, and is record/replayable.
- **Repo files are the only state.** All workflow state is recomputable from committed files under
  `evaluations/`. A `.skillet/` cache MAY accelerate but MUST NOT originate state (deleting it
  loses nothing).
- **Config is YAML** (`skillet.yaml`). `config set` rewrites targeted lines in place
  (swift-yaml does not preserve comments on re-emit). YAML is for human-editable *policy*, never
  *behavior* (design §7.6).
- **Frozen boundary formats are contracts**: `evals.json`, `trigger-eval.json`, `benchmark.json` +
  the run-record family (`grading.json`, `timing.json`, `metrics.json`, `eval_metadata.json`),
  SARIF 2.1.0, and session bundles never break — enforced by golden fixtures (F8 lands the EDDCore
  `Boundary/` codecs for these). Enumerate *all* decoded fields in goldens and round-trip unknown keys. `--json` payloads carry a `schema` field
  and are additive within a major. Exit codes are a stable API. Human TTY output is *not* an API.
- **Every command** offers `--json`, supports `-h`/`--help`, ends by suggesting the next sensible
  command (only ones that actually exist), and fails with a message stating what/why/the fixing command.
- **CLI help lives in ArgumentParser metadata, not `///`.** User-facing help is the `abstract`/
  `discussion` + per-flag `help:` — the single source of truth that `--help`, `--experimental-dump-help`,
  and the `generate-manual`/`generate-docc-reference` plugins all read. `///` doc comments are
  contributor/implementation notes and **MUST NOT** duplicate the help (only the ArgumentParser copy is
  verified). DocC symbol docs (`///`) apply to *public library* symbols; the executable has none.
- **License**: repo ships **MIT** (`LICENSE`); design §14 recommends Apache-2.0 — unresolved, see
  constitution › Deferred Decisions.

## Boundaries (distilled from the constitution's MUST-NOTs — act on these)

- **Never auto-commit. Ever.** skillet never runs `git commit`. The only way a live `SKILL.md` is
  modified is the explicit, opt-in `suggest --apply` content-anchored path, which refuses a dirty
  tree and stops short of the commit. `iterate` operates only in throwaway worktrees.
- **Never emit, log, or commit secrets** (credentials, tokens, keys) — not in output, errors, or
  the corpus. `capture` redacts before writing and **fails closed** if the scanner can't run. Run
  the scanner offline/detection-only; never enable its network validation.
- **No telemetry; no network calls** except to providers the user explicitly configured.
- **Do not add a dependency** (runtime or dev) without a constitutional amendment.
- **Do not break a frozen format, bundle field, exit code, or `--json` schema** without a major
  version bump and migration notes.
- **Do not auto-probe other applications' private caches/binaries** (the harness ban policy).
- **Tests before implementation** (TDD); changes to graded behavior must cite evidence and a
  proving (previously-failing) eval.

## Planned (per `ROADMAP.md` — agreed intent, NOT yet built)

Treat everything in this section as a target to build toward, not as existing functionality —
**except** what Phase 1 already shipped (now COMPLETE): the `EDDCore`, `TraceKit`, `HarnessKit`,
`LintKit`, `JudgeKit`, `RunKit`, `ProjectKit`, `RenderKit`, and `ConfigYAML` kits + the `skillet`
executable with `init`/`doctor`/`lint`/`run`/`harness` (see the status banner + Commands above; `doctor`
is Phase 2's first shipped feature). The kits and commands still *planned* are the remaining Phase 2+
ones — `ScoreKit`/`CorpusKit`/`AnalysisKit`/`IterateKit`
and `capture`/`friction`/`triage`/`next`/`suggest`/`iterate`/`baseline`/`report`/… .

### Package architecture (design §11)

```
skillet (Package.swift, Swift 6, strict concurrency)
EDDCore (pure)
  → TraceKit
  → { HarnessKit, JudgeKit, ScoreKit, LintKit, CorpusKit, ProjectKit }
  → AnalysisKit / RunKit / IterateKit / RenderKit
  → skillet (executable)   (swift-argument-parser; ALL commands + wiring, ~≤50 lines
                            each; NO separate skilletCLI library target)
```

`EDDCore` (domain types · gates engine · scorer↔judge contradiction join · pass^k aggregation ·
golden-tested boundary codecs) is pure/synchronous; effectful kits sit above it. The `skillet`
executable is the top wiring layer (no `skilletCLI` library); `ProjectKit` is the filesystem-effect
home for discovery / config I/O / `init` scaffolding, kept out of the executable so it stays
unit-testable. Business logic lives in the kits (one unit-test target each); the CLI surface is
tested via an `IntegrationTests` target that runs the built binary. CorpusKit is a Phase-3 kit.

### Command surface (design §6) — lights up across phases

`init`, `doctor`, `lint`, `run` (behavior + trigger axes, `--ab`, `--matrix`), `capture`
(`--from-checkpoint`, `--preserve-feedback`), `friction`, `triage`, `next` (`--strict`), `suggest`
(`--apply`), `iterate` (`--apply`), `baseline compare|matrix`, `report` (TTY + HTML), `migrate`,
`grade`, `score`, `bundle`, `hooks install`, `harness` (`info`, `which --search`).

### Adapters (v1)

`claude-code`, `opencode`, `direct-api`, `replay`.

### Platforms & testing (design §11–§12)

macOS 14+ and current Ubuntu LTS. Testing strategy: pure unit + property tests for
`EDDCore`/`TraceKit`; golden files for boundary codecs; `ReplayAdapter` fixtures for pipelines; one
opt-in, env-gated live smoke job per adapter in CI — everything else runs free, and free
deterministic gates run before any paid one. **One unit-test target per kit** (each kit provably
importable/testable in isolation). Because all ArgumentParser logic lives in the `skillet`
executable, the CLI surface is exercised by an **`IntegrationTests`** target that runs the **built
binary** via `swift-subprocess`: test-bundle-relative binary discovery (+ `SKILLET_TEST_BINARY`
override), per-test temp-dir isolation for parallel safety, and Swift Testing tags separating the
free suite from env-gated live runs. **Test files: 300-line soft cap** (split suites; extract
`TestHarness`/fixture helpers).

### Roadmap phases

Phase 1 (walking skeleton) → 2 (measurement & static gates) → 3 (discovery/evidence) → 4 (error
analysis) → 5 (computable runbook / `next`) → 6 (fix suggestion & iteration) → 7 (multi-harness
matrix) → 8 (beyond v1). See `ROADMAP.md` and `Roadmap/`.

## Maintenance (sync contract)

- This file describes **current reality**. When a roadmap phase lands, move the now-true parts from
  *Planned* into *Binding conventions* / a new *Commands* section, and update the status banner.
- Keep this file in sync with `.specify/memory/constitution.md`: when a constitutional principle,
  the sanctioned-dependency list, a boundary contract, or a command/flag changes, update the
  relevant section here. **Do not duplicate the constitution's principle text** — reference it; the
  constitution remains authoritative for development principles, this file for operational
  onboarding.
- Add real `Commands` (e.g. `swift build`, `swift test`) only once they actually work.
- **Doc changelogs live beside their documents** (extracted 2026-07-04):
  [`skillet-design-changelog.md`](skillet-design-changelog.md) (design doc keeps `Status: Draft v0.x`
  + a one-line latest pointer) and [`ROADMAP-changelog.md`](ROADMAP-changelog.md) (ROADMAP keeps
  semver header + latest summary). One linkable `## vX.Y — date` heading per version, latest first;
  **historical entries are never rewritten**. Entry discipline — *detail lives nearest the artifact*:
  a feature's detailed record is its `Specs/NNN` plan status; design-only/decision changes are
  recorded in full in the design changelog; every other log (ROADMAP changelog, phase change logs)
  writes a 2–4-line summary + link. The bare `CHANGELOG.md` name stays **reserved for the future
  software changelog** ([Keep a Changelog](https://keepachangelog.com) format, design §12).
- **Documentation is verified, not just written** (Principle VII). Each new/changed command updates
  `README.md` usage + the *Commands* list, and the free test suite checks three layers: (1) the
  documented command surface against `skillet --experimental-dump-help` (subcommand names today —
  flag-level assertions are a tracked gap; decoded with a local minimal type, not an
  `ArgumentParserToolInfo` dependency);
  (2) behavioral claims (exit codes, `--json` `schema`) by running the binary; (3) internal doc links
  resolve. The command *reference* can be regenerated from the parser via `swift package generate-manual`
  / `generate-docc-reference`. Checks assert **facts only — never the human/TTY prose** a command prints (P7).
