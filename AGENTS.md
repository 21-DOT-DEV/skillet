# AGENTS.md (skillet)

`skillet` — the **SKILL.md Evaluation Toolkit** — is a public, open-source, multi-harness Swift
CLI for eval-driven development (EDD) of agent skills: capture real runs, turn hand-fixes into
structured evidence, and ship a `SKILL.md` edit only after a previously-failing eval proves it.

> **Status: Phase 1 in progress — F1 landed.** The walking skeleton has begun. `Package.swift` plus
> `EDDCore`, `ProjectKit`, `RenderKit`, and the `skillet` executable exist, with unit + integration
> tests green (`swift build && swift test`). **F1 (project discovery & output contract) is
> implemented**: `skillet` explains the loop, `-C <dir>`, `--json` (schema-tagged), `--color`/`NO_COLOR`,
> and the typed §5.4 exit codes (0 ok · 2 usage · 3 environment reachable today). The `skillet`
> executable owns the full ArgumentParser command tree (no `skilletCLI` library); `ProjectKit` is the
> discovery/config-IO home. The rest of the command surface under "Planned" is still agreed *intent*,
> not shipped fact — don't assume a command/module exists until its feature lands. Update this file as
> each feature/phase completes.

## Source-of-truth documents (read these first)

- **`skillet-design.md`** — the product spec. Authoritative for *what skillet does*: product
  principles P1–P10, settled decisions D1–D7, command surface (§6), file formats (§7), gates
  engine (§8), harness abstraction (§9), package architecture (§11), distribution (§12), v1 scope
  (§13), open questions (§14).
- **`ROADMAP.md`** (+ `docs/roadmap/phase-*.md`) — the phase plan. Authoritative for *sequence and
  priority*. Phase 1 is the walking skeleton; do the earliest incomplete phase unless told
  otherwise.
- **`.specify/memory/constitution.md`** — the development charter. **Authoritative for *how we
  build* skillet** (7 principles, MUST/SHOULD/MAY, governance). When in doubt about a development
  practice, the constitution governs — do not duplicate its principles here; read it.

Contributing, security disclosure, and code of conduct are handled at the org level:
[`21-DOT-DEV/.github`](https://github.com/21-DOT-DEV/.github) (`CONTRIBUTING.md`, `SECURITY.md`,
`CODE_OF_CONDUCT.md`). There are intentionally no repo-local copies.

## Commands (true now — Phase 1 / F1)

- `swift build` — build the package (resolves `swift-argument-parser`, `swift-subprocess`, `swift-system`).
- `swift test` — run the unit + integration suites (32 tests, all green). The integration suite drives
  the built binary, which `swift test` builds first; filter with tags, e.g. `swift test --skip slow`.
- `.build/debug/skillet` — the CLI: try `skillet`, `skillet --json`, `skillet -C <dir>`, `skillet --help`,
  `skillet --version`.
- `SKILLET_TEST_BINARY=<path> swift test` — point the integration harness at a specific binary.

Subcommands (`init`/`doctor`/`lint`/`run`/…) are not built yet — see Planned.

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
- **Dependency notes (implementation reality):** `swift-yaml` has **no tagged release** and its
  `YAML` product needs **C++ interop** in the consumer, so it is pinned by revision and isolated to a
  YAML-codec seam (the pure core stays interop-free), wired in only when that codec lands — not up
  front. `swift-system` (`FilePath`) is a **test-only** transitive dep of `swift-subprocess` (the
  integration-test binary harness), adding no shipped runtime dep and needing no amendment. Known-good
  pins: `swift-argument-parser` 1.6.2, `swift-subprocess` 0.2.1, `swift-system` 1.5.0.
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
- **Frozen boundary formats are contracts**: `evals.json`, `trigger-eval.json`, `benchmark.json`,
  SARIF 2.1.0, and session bundles never break — enforced by golden fixtures. Enumerate *all*
  decoded fields in goldens and round-trip unknown keys. `--json` payloads carry a `schema` field
  and are additive within a major. Exit codes are a stable API. Human TTY output is *not* an API.
- **Every command** offers `--json`, supports `-h`/`--help`, ends by suggesting the next sensible
  command, and fails with a message stating what/why/the fixing command.
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
**except** the F1 substrate already shipped (`EDDCore`, `ProjectKit`, `RenderKit`, the `skillet`
executable; see Commands above).

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
`EDDCore`/`TraceKit`; golden files for boundary codecs; `HarnessReplay` fixtures for pipelines; one
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
matrix) → 8 (beyond v1). See `ROADMAP.md` and `docs/roadmap/`.

## Maintenance (sync contract)

- This file describes **current reality**. When a roadmap phase lands, move the now-true parts from
  *Planned* into *Binding conventions* / a new *Commands* section, and update the status banner.
- Keep this file in sync with `.specify/memory/constitution.md`: when a constitutional principle,
  the sanctioned-dependency list, a boundary contract, or a command/flag changes, update the
  relevant section here. **Do not duplicate the constitution's principle text** — reference it; the
  constitution remains authoritative for development principles, this file for operational
  onboarding.
- Add real `Commands` (e.g. `swift build`, `swift test`) only once they actually work.
