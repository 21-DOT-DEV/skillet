# AGENTS.md (skillet)

`skillet` — the **SKILL.md Evaluation Toolkit** — is a public, open-source, multi-harness Swift
CLI for eval-driven development (EDD) of agent skills: capture real runs, turn hand-fixes into
structured evidence, and ship a `SKILL.md` edit only after a previously-failing eval proves it.

> **Status — nine commands ship today:** `init`, `doctor`, `lint`, `score`, `harness`, `run`, `capture`,
> `triage`, `suggest` (drafting *and* `--apply`). **Phases are not worked in order**, so a later phase
> can be finished while an earlier one still has open features — which is why "Phase 2 IN PROGRESS"
> appears below alongside shipped Phase 6 work, rather than contradicting it.
>
> **Phase 1 COMPLETE — F1, F2, F4–F8 landed** ([completed-items audit](Roadmap/phase-1-review.md));
> **Phase 2 IN PROGRESS — F3 (`skillet doctor`, the $0 preflight) and F14 (`skillet run --axis
> trigger`, the deterministic description axis) shipped 2026-07-04; F15 (`skillet run --ab`, the
> provably skill-free baseline arm with paired Δ) shipped 2026-07-07; F16 (`skillet run --judge
> grounded-judge`, the file-contents grader) shipped 2026-07-08; F17 (`skillet score`, free
> deterministic scorers over produced text → SARIF 2.1.0) shipped 2026-07-09**
> ([Specs/008](Specs/008-doctor-preflight/plan.md), [Specs/009](Specs/009-trigger-axis/plan.md),
> [Specs/010](Specs/010-ab-baseline/plan.md), [Specs/011](Specs/011-grounded-judge/plan.md),
> [Specs/012](Specs/012-deterministic-scorers/plan.md)).
> **Phase 3 — F26+F32 (`skillet capture`, scrubbed + scored session bundles) shipped; Phase 4 — F33
> (`skillet triage`, the free corpus failure taxonomy) shipped; Phase 6 — F41 (`skillet suggest`,
> drafted `SKILL.md` edits from observed evidence) and F42 (`suggest --apply`, safe apply to the
> working tree — all-or-nothing, clean-repo required, never commits) shipped** ([Specs/013](Specs/013-capture-session-evidence/plan.md)–[Specs/019](Specs/019-safe-apply/plan.md)).
> `Package.swift` plus `EDDCore`, `TraceKit`,
> `ProjectKit`, `RenderKit`, `HarnessKit`, `LintKit`, `ScoreKit`, `JudgeKit`, `RunKit`, `CorpusKit`, `SanitizerKit`, `AnalysisKit`, `IterateKit`, `ConfigYAML`, and the
> `skillet` executable exist — the executable owns the full ArgumentParser command tree (no
> `skilletCLI` library; `ProjectKit` is the discovery/config-IO home) — with the full suite green
> (`swift build && swift test`). For what exists right now, `skillet --help` is authoritative — this
> file does not keep a second copy of that list; see *Commands* below for what each one does. **Per-feature records live nearest the artifact**: each
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

## Commands (true now — verified against the binary by the test suite)

- `swift build` — build the package (resolves `swift-argument-parser`, `swift-subprocess`, `swift-system`, `swift-yaml`; also `swift-clocks` and the two it brings with it, which are fetched but built into the tests only, never into `skillet`).
- `swift test` — run the unit + integration suites (all green in CI; the count lives in the run output, not here). The integration suite drives
  the built binary, which `swift test` builds first; filter with tags, e.g. `swift test --skip slow`.
- `.build/debug/skillet` — the CLI: try `skillet`, `skillet --json`, `skillet -C <dir>`, `skillet init`,
  `skillet init --json`, `skillet doctor [<skill>...] [--json]` (free $0 preflight; exit 3 + remedy on failure),
  `skillet lint [--json]`, `skillet score <path> [--format tty|json|sarif]` (free, model-free deterministic scorers over produced text → SARIF 2.1.0; a reporter, not a gate — exit 0 even with findings, exit 4 on a corrupt config), `skillet harness list`, `skillet harness info [--json]`,
  `skillet run [<skill>] [--axis behavior|trigger|all] [--ab] [--judge text-judge|grounded-judge] [--runs <k>] [--dry-run] [--yes] [--no-input] [--keep-workspace]` (paid: shells `claude`, resolved via `SKILLET_CLAUDE_CODE_BIN` env → `harness.claude-code.path` in `skillet.yaml` → `PATH` — behavioral trials add the judge; trigger trials are judge-free single calls; `--ab` doubles behavioral trials with a provably skill-free baseline arm, both arms judged; `--judge grounded-judge` reads produced-file contents to catch created-but-wrong, larger grading requests — gated by the combined spend estimate),
  `skillet triage [<skill>] [--since <YYYY-MM-DD>] [--dry-run] [--json]` (free: reads the recorded session bundles under a skill's `evaluations/sessions/`, groups their findings into a failure taxonomy, and writes one evidence file per cluster under `evaluations/findings/` — never overwrites an existing file, reports what it skipped, and exits 0 even when it finds problems: it is a reporter, not a gate),
  `skillet suggest <skill> --from <evidence-id>... [--out <name>.json] [-n|--dry-run] [--yes] [--json]` (paid: one model call that **drafts** minimal `SKILL.md` edits from the evidence records you name plus the human notes sharing their sessions, and writes them to `.skillet/proposals/<id>.json`; **applying is a separate, opt-in step** (`--proposals <name>.json --apply`, free — no model call — which writes your working tree all-or-nothing, refuses a dirty repository, and never commits or stages); free static gates and a read-only check that the model program is usable run first, `-n` previews the request and its size without spending, an over-ceiling request refuses unless `--yes`, and a name already held by a different draft exits 2 without overwriting),
  `skillet iterate <skill> --proposals <name>.json [--edits <n>...] [--runs <k>] [--judge <id>] [-n|--dry-run] [--yes] [--no-input] [--keep-worktree] [--json]` (paid: two measurements, so roughly double a run — measures the skill, applies the edits to a throwaway copy, measures again, and reports the difference with a strict, provisional verdict; never commits, never changes your files).
  `skillet capture --skill <s> --slug <x> [--session <ref>] [--target-dir <path>] [--date <YYYY-MM-DD>] [--force] [--fail-on-secret] [--secret-scanner-path <p>]` (records the newest claude-code session — or `--session` — as a **secret-scrubbed**, scored evidence bundle under `<skills_root>/<skill>/evaluations/sessions/`; **always redacts** — there is no `--no-sanitize` — and **fails closed** if `betterleaks` can't run; `--fail-on-secret` exits 1 for CI, the bundle still written scrubbed),
  `skillet --help`, `skillet --version`. Hidden test seams, per command: `run` and `iterate` both take
  `--replay` (offline adapter+judge) and `--replay-map <json>` (canned verdicts, keyed
  `<criterion>` or `<criterion> @ <marker>`); **`--replay-baseline-map <json>` is `run`-only** (baseline-arm
  canned verdicts; defaults to fail-all so a replayed `--ab` shows a deterministic positive Δ). `iterate`
  has no baseline-arm map because one grader serves both of its measurements — they are told apart by the
  skill's `replay-marker:` line, not by a second recording.
- **The hidden test options ship in the released binary, deliberately.** `--replay`, `--replay-map`,
  `--replay-baseline-map` and `--reply-file` are hidden from help and refused unless `SKILLET_TEST_SEAMS`
  is set, but they are compiled in — because the suite exercises the *built* binary rather than a
  test-only build, which is what makes those tests worth having. Using one requires both an environment
  variable and a command line, and every file they read goes through the same confined reader as any
  other untrusted path. If a stricter posture is ever wanted, the shape is a build-time switch around the
  option declarations plus a test-flavoured build target — recorded so the trade-off is a decision rather
  than an accident.
- `SKILLET_LIVE_SMOKE=1 SKILLET_CLAUDE_CODE_BIN=<claude> swift test --filter liveSmoke` — the **paid**
  opt-in checks (~4 model calls each), skipped by every ordinary run. One per paid command: the measuring
  command's proves a real run end-to-end; the proving command's checks that both measurements really ran
  and that the skill actually reached the model. It does **not** require the edit to improve anything: an
  earlier version did, went red against a real model, and was removed — whether a model follows an edited
  instruction is a fact about the model, not about this program, and asserting it makes the suite fail for
  something it does not control. Run before a release, or after changing how a model is launched or an
  answer is graded.
- `swift package generate-manual` / `generate-docc-reference` — regenerate the command reference from the parser.
- `SKILLET_TEST_BINARY=<path> swift test` — point the integration harness at a specific binary.
- CI: `.github/workflows/ci.yml` runs the free suite on macOS (`macos-26`, `DEVELOPER_DIR` pinned to
  Xcode 26.5 for determinism) + Ubuntu (official `swift:6.3` container) on every push/PR — zero
  secrets, zero paid calls; the live smoke self-skips (opt-in locally via `SKILLET_LIVE_SMOKE=1`).
  Historical note: the 2026-06 macOS-only CI failures were an upstream Swift C++-interop bug, fixed
  in swift-yaml (diagnosis + repro live in its `Projects/`); no Swift-version floor beyond Swift 6.

`init`, `doctor`, `lint`, `score`, `run`, `harness list`/`info`, `capture` (scrubbed, scored session bundles — F26/F32), `triage` (free corpus failure taxonomy — F33), and the claude-code adapter (parse + resolution + probe + live `run` + session capture) are built; `friction`/`next`/… are not yet — see Planned.

## Binding conventions

These are real rules from the constitution + design decisions. Follow them in any code you write,
from the first commit.

- **Language**: Swift 6 with strict concurrency (`swiftLanguageModes: [.v6]`), Swift Package
  Manager.
- **Sanctioned dependencies only** (adding any other requires a constitutional amendment):
  `swift-argument-parser`, `swift-yaml` (YAML 1.2 — config + evidence frontmatter; *not* Yams, and
  there is **no TOML dependency**), `swift-subprocess`, plus the standard library. JSON/SARIF/frozen
  formats use Foundation `Codable` (no added dependency). Secret scanning uses `betterleaks` (MIT),
  **resolved** from the `sanitize` config / `SKILLET_BETTERLEAKS_BIN` / `PATH` (per-platform
  `.artifactbundle` vendoring deferred — constitution v1.3.0). The cache MAY use system SQLite.
  **Test-only** (constitution v1.4.0): `swift-clocks` and the two packages it pulls in with it,
  `swift-concurrency-extras` and `xctest-dynamic-overlay` — three packages, all MIT. `swift-clocks` is pinned
  exactly in the manifest; the other two are pinned by the committed lockfile (`Package.resolved`), because
  pinning `swift-clocks` alone leaves them asked for as "this version or newer" and a resolve then takes
  whatever was published most recently. Naming them in the manifest instead makes the build tool warn on
  every build that they are unused, so the lockfile carries it. They supply a clock
  whose time a test moves by hand, so a wait can be checked without waiting. Attached to the
  `HarnessKitTests` and `RunKitTests` targets only and to no shipped target: building `skillet` on its own
  fetches them while working out the package graph and then compiles and links none of them. Shipped code
  takes the standard library's `Clock` and defaults to the real one, so behaviour is unchanged.
- **Dependency notes (implementation reality):** `swift-yaml` has **no tagged release**, so it is
  **pinned by revision** (`473252b…`). Its `YAML` product needs **C++ interop**, which is **viral to
  direct importers** — so it is confined to the isolated **`ConfigYAML`** target
  (`.interoperabilityMode(.Cxx)`), which exposes a pure-Swift API (decoding into `EDDCore.SkilletConfig`).
  Consequence (validated by the F6 spike): the `skillet` executable, as a direct importer, is a **`.Cxx`
  leaf** too (as is `ConfigYAMLTests`, the codec's own test target — the third and last `.Cxx` island) —
  but every kit and the pure core stay interop-free (they take a decoded `SkilletConfig` as
  input and never import `ConfigYAML`). `swift-subprocess` is now used by **`HarnessKit`** (the
  `ProcessLauncher` seam) as well as the integration-test harness; `swift-system` (`FilePath`) rides in
  with it. Known-good pins: `swift-argument-parser` 1.6.2, `swift-subprocess` 0.2.1, `swift-system`
  1.5.0, `swift-yaml` rev `473252b…`.
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
  the corpus. `capture` **always** redacts before writing (there is **no `--no-sanitize`** opt-out —
  silence a false-positive *file* with `sanitize.exempt_paths` (a glob/whole-segment list; drops findings
  whose path matches), or a false-positive *value* that recurs across artifacts (the diff, trace) with
  betterleaks' own allowlist in `.betterleaks.toml`) and **fails closed** if the scanner can't run. Resolve the scanner via `--secret-scanner-path` /
  `SKILLET_BETTERLEAKS_BIN` / `sanitize.scanner_path` / `PATH`; `--fail-on-secret` exits 1 for CI
  (the bundle is still written scrubbed). Run the scanner offline/detection-only; never enable its
  network validation.
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
is Phase 2's first shipped feature). Phase 2 also shipped `ScoreKit` + `score`; Phase 3 has shipped
`CorpusKit` + `SanitizerKit` + `capture` (F26/F32); Phase 4 has shipped `AnalysisKit` + `triage` (F33);
Phase 6 has shipped `suggest` (F41).

**What is still planned is not listed here.** It used to be, and the list went stale the moment a
command shipped without someone remembering to edit this sentence. Two sources answer it and neither
can drift: `skillet --help` is authoritative for what exists in the binary right now, and the
[ROADMAP phase table](ROADMAP.md) is authoritative for what is planned and when.

### Package architecture (design §11)

```
skillet (Package.swift, Swift 6, strict concurrency)
EDDCore (pure)
  → TraceKit
  → { HarnessKit, JudgeKit, ScoreKit, LintKit, CorpusKit, ProjectKit }
  → AnalysisKit / RunKit / IterateKit / RenderKit / SanitizerKit  (SanitizerKit → CorpusKit + HarnessKit)
  → skillet (executable)   (swift-argument-parser; ALL commands + wiring — thin adapters
                            that delegate to the kits; NO separate skilletCLI library target)
```

`EDDCore` (domain types · gates engine · scorer↔judge contradiction join · pass^k aggregation ·
golden-tested boundary codecs) is pure/synchronous; effectful kits sit above it. The `skillet`
executable is the top wiring layer (no `skilletCLI` library); `ProjectKit` is the filesystem-effect
home for discovery / config I/O / `init` scaffolding, kept out of the executable so it stays
unit-testable. Business logic lives in the kits (one unit-test target each); the CLI surface is
tested via an `IntegrationTests` target that runs the built binary. Commands are wiring, not a fixed
line budget — orchestration-heavy ones (`run`, `capture`, `doctor`) are the largest, and the reusable
logic they call is extracted into kits (e.g. `GitDiffProvider`, `BodyExtractor`) so it's unit-tested there. `CorpusKit` (bundle assembly +
frozen writer) and `SanitizerKit` (betterleaks-backed secret redaction) are the Phase-3 evidence kits.

### Command surface (design §6) — lights up across phases

**Answers today:** `init`, `doctor`, `lint`, `run` (behavior + trigger axes, `--ab`, `--matrix†`),
`capture` (`--from-checkpoint†`, `--preserve-feedback†`), `triage`, `suggest` (`--apply`), `iterate`
(`--edits`), `score`, `harness info`.

**Planned, not yet accepted:** `friction` (planned), `next` (planned, `--strict`), `baseline
compare|matrix` (planned), `report` (planned, TTY + HTML), `migrate` (planned), `grade` (planned),
`bundle` (planned), `hooks install` (planned), `harness which --search` (planned).

A `†` marks a switch that is planned but not yet accepted, and `(planned)` marks a whole command that
is. Nine commands here were listed as available while the tool refused them — a reader learning from
this page was sent to verbs that do not exist. A test now checks every name in this section against what
the binary actually registers, so the two cannot drift apart again. The list mixed the two without saying which, and said the proving command takes `--apply` when it
takes `--edits` — so a reader learning the tool from this page was sent to a switch the parser refuses.
A test now compares every switch named here against what the parser actually accepts, skipping the
marked ones, so this cannot drift again unnoticed.

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
