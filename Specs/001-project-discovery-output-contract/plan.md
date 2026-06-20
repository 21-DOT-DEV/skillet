# Plan — Phase 1 · F1: Project discovery & output contract

| | |
|---|---|
| **Feature** | 001 — Project discovery & output contract |
| **Phase** | 1 — Walking Skeleton ([Roadmap/phase-1-walking-skeleton.md](../../Roadmap/phase-1-walking-skeleton.md), F1) |
| **Status** | IMPLEMENTED (2026-06-20) — all success criteria met; 32 unit + integration tests green |
| **Last updated** | 2026-06-20 |
| **Authoritative refs** | design §5.1–5.5 (invocation, exit codes, output contract), §6.3 (help/discoverability), Appendix B (clig.dev checklist), §11 (architecture); constitution I/III/IV/V |
| **Workflow** | Standalone plan (spec-kit workflow intentionally skipped) |

---

## 1. Goal

Stand up the thinnest CLI substrate every later command stands on: a `skillet` binary that
(a) finds its project the way git does, (b) speaks to both humans (TTY) and scripts (`--json` with
a `schema` field), and (c) returns the documented, typed exit codes. No real subcommands yet — F1 is
the *output contract + discovery engine*, not a feature verb.

**Success criteria (from roadmap F1):**
- From any subdirectory, a command resolves the correct project root (`-C` parity test).
- Exit codes follow the table: usage error `2`, environment error `3` (both demonstrated).
- Every `--json` payload validates against its declared `schema` field.
- `swift build` and `swift test` pass on the Swift 6.3.2 toolchain (macOS; Linux is CI's job later).

---

## 2. Scope

### In scope
- **Root command** (`skillet`, no args) → prints the EDD loop overview (Appendix B: "command-less
  invocation explains the loop"); `--help` is examples-first; `skillet --json` → a `skillet.root/1`
  payload.
- **Global flag plumbing** (shared `@OptionGroup`): `-C <dir>`, `--json`, `--color auto|always|never`
  (+ `NO_COLOR`), `-q`/`-v`, `--config <path>`.
- **git-style discovery engine** (`ProjectKit`): walk up from `$PWD`/`-C` to the first `skillet.yaml`
  (project root) or `.git` (boundary).
- **Typed exit codes** (`EDDCore`): the full §5.4 table as a stable enum; `0`/`2`/`3` are *reachable*
  in F1, `1`/`4`/`5` are defined for later features.
- **Shared `--json` envelope** (`EDDCore`): schema-tagged, deterministically encoded.
- **Output routing** (`RenderKit`): machine/JSON → stdout, human chatter → stderr; color resolution;
  verbosity; "suggested next step" line.
- **Package scaffold** for the F1 targets only + their tests.

### Out of scope (deferred, with where they land)
- Subcommand bodies `init`/`doctor`/`lint`/`run` — F2–F7 (not even registered as stubs in F1;
  unknown commands → exit `2`).
- **Config *parsing*** — `skillet.yaml` is treated as an opaque discovery *marker* in F1; YAML
  decoding waits for `swift-yaml` (deferred; see AGENTS.md › Dependency notes). `--config <path>` is
  recorded into the project context but not parsed yet.
- Spend/action flags (`--yes`, `--dry-run`, `--harness`, `--runs`) — land with the commands that use
  them.
- `HarnessKit`/`JudgeKit`/`RunKit`/`LintKit`/`ScoreKit`/etc., shell completions, man pages, HTML report.
- Actual triggers for exit `1`/`4`/`5` (defined as types now; fired by later features).

---

## 3. Architecture (F1 target subset)

Per design §11, the strict downward DAG — only the targets F1 needs:

```
skillet (executableTarget)         ← root command + global flags + wiring + exit-code mapping
  → ProjectKit → EDDCore           ← discovery, -C resolution, project context
  → RenderKit  → EDDCore           ← TTY/JSON output, color, verbosity, envelope encoding
  → EDDCore (pure, Foundation)     ← ExitCode, EDDError, JSONEnvelope, payload types
```

**Dependencies (Package.swift):**
- `swift-argument-parser` 1.6.2 → `skillet` executable.
- `swift-subprocess` 0.2.1 + `swift-system` 1.5.0 → **`IntegrationTests` only** (the binary harness).
- **No `swift-yaml`** (no YAML parsing in F1).

**Test targets:** `EDDCoreTests`, `ProjectKitTests`, `RenderKitTests` (one per kit) + `IntegrationTests`
(drives the built binary). Other kits/test targets are added by their own features.

---

## 4. Detailed design

### 4.1 EDDCore (pure)
- `enum ExitCode: Int32` — `success 0`, `measuredFailure 1`, `usage 2`, `environment 3`,
  `artifact 4`, `gate 5`. The single source of truth for §5.4.
- `EDDError` — typed error carrying `exitCode: ExitCode`, `message: String`, `remedy: String`
  (Appendix B "what/why/fix"). F1 cases: `.usage(...)`, `.environment(.directoryNotFound(path:))`,
  `.environment(.projectNotFound(...))` (mechanism; root command treats no-project as benign).
  Designed as an extensible enum so later features add `.artifact`/`.gate`/measured-failure cases.
- `JSONEnvelope` — every machine payload is schema-first. Approach: a `SchemaIdentified` protocol
  (`static var schema: String { "skillet.<thing>/1" }`) + a single shared `JSONEncoder` factory
  (`.sortedKeys`, `.iso8601` UTC, no escaping slashes) so output is byte-stable and golden-testable.
- Payload types:
  - `RootInfo` (`skillet.root/1`): `skilletVersion`, `project: ProjectContext`, `loop: [LoopVerb]`
    (static informational list of the methodology verbs).
  - `ErrorPayload` (`skillet.error/1`): `code: Int32`, `kind: String`, `message`, `remedy`.
  - `ProjectContext`: `root: String?`, `discoveredVia: enum { skilletYAML, gitBoundary, none }`,
    `cwd: String`, `configPath: String?`.

### 4.2 ProjectKit (effectful — filesystem)
- `DirectoryProbe` protocol (`exists`, `isDirectory`, `contains(filename:)`) with a real
  `FileManager` impl **and** an in-memory fake — so the walk algorithm is unit-tested deterministically
  (record/replayable effects, design §11 / constitution III) and not only via temp dirs.
- `discoverProject(from start: URL, probe: DirectoryProbe) -> ProjectContext` — ascend to filesystem
  root; first dir with `skillet.yaml` ⇒ root (`discoveredVia: .skilletYAML`); else first dir with
  `.git` ⇒ root (`.gitBoundary`); else `.none` with `root: nil`.
- `resolveStartDirectory(_ dashC: String?, cwd: URL) throws -> URL` — apply `-C`; if the dir is
  missing/unreadable, throw `EDDError.environment(.directoryNotFound)` (**exit 3**).

### 4.3 RenderKit (effectful — stdout/stderr/tty)
- `OutputMode` = `.human` | `.json`; chosen from `--json`.
- Routing: JSON/primary data → **stdout**; logs/errors/next-step hints → **stderr** (clig.dev + §5.5).
- `ColorPolicy` from `--color` + `NO_COLOR` + isatty(stdout); `auto` = colored only on a TTY.
- `Verbosity` from `-q`/`-v`.
- `renderRoot(_:)` (human overview ending in suggested next steps **or** the `skillet.root/1` JSON),
  `renderError(_:)` (human what/why/fix on stderr **or** `skillet.error/1` JSON on **stderr**).

### 4.4 skillet executable
- `GlobalOptions: ParsableArguments` — the shared flags above, attached via `@OptionGroup`.
- `SkilletCommand: AsyncParsableCommand` (root). `run()` → resolve start dir → discover → render
  root (human/JSON) → exit 0.
- **Exit-code reconciliation (key F1 task):** ArgumentParser defaults (validation → `EX_USAGE` 64)
  do **not** match §5.4. A custom `@main` maps them:
  ```
  do { var cmd = try SkilletCommand.parseAsRoot(args); try await cmd.run() }   // → 0
  catch let e as EDDError { RenderKit.renderError(e); exit(e.exitCode.rawValue) }
  catch {                                                                        // ArgumentParser
      if help/cleanExit → print to stdout, exit 0
      else → render usage message to stderr, exit 2
  }
  ```
  Uses `SkilletCommand.exitCode(for:)`/`fullMessage(for:)` to detect help vs validation.
- Wiring stays ≤ ~50 lines (design §11).

---

## 5. Test plan (TDD — red → green → refactor)

**Unit (per kit, Swift Testing):**
- `EDDCoreTests`: ExitCode raw values; EDDError `exitCode`/`message`/`remedy`; envelope is
  schema-first + deterministic (golden files for `skillet.root/1`, `skillet.error/1`); ISO-8601 UTC.
- `ProjectKitTests` (fake `DirectoryProbe`): finds `skillet.yaml` from a deep subdir; stops at `.git`
  boundary; nested resolves to the right root; no-project ⇒ `.none`; `-C` resolution; `-C` missing ⇒
  environment error.
- `RenderKitTests`: color `auto/always/never` + `NO_COLOR`; stdout-vs-stderr routing; JSON-vs-human
  selection; byte-stable JSON.

**Integration (`IntegrationTests`, drives the built binary):**
- Improved `TestHarness` (per research): test-bundle-relative binary discovery + `SKILLET_TEST_BINARY`
  override + `#require` exists; per-test UUID temp dir via `final class` `init`/`deinit`; `swift-subprocess`;
  central `Tag` extension (`.integration`/`.slow`).
- Cases: `skillet` → exit 0 + prints loop; `skillet --json` → valid JSON, `schema == skillet.root/1`;
  `skillet -C <subdir> --json` → resolves the correct root (**`-C` parity**); `skillet -C <nonexistent>`
  → **exit 3** + `skillet.error/1` on stderr; `skillet bogus` → **exit 2**; `skillet --bad-flag` → exit 2;
  `--color never`/`NO_COLOR` → no ANSI.
- **"validates against its schema":** golden-file structure check + asserting the `schema` field per
  payload (no runtime JSON-Schema dependency in F1).
- Test files honor the **300-line soft cap** (split suites; extract `TestHarness` + project fixture).

---

## 6. Task breakdown (ordered)

1. `Package.swift` — F1 targets + test targets + deps (argument-parser; subprocess/system test-only).
2. `EDDCore` — ExitCode, EDDError, JSONEnvelope, payload types (**tests first**).
3. `ProjectKit` — DirectoryProbe (+ fake), discovery, `-C` resolution (**tests first**).
4. `RenderKit` — output mode, routing, color, verbosity, encoders (**tests first**).
5. `skillet` — GlobalOptions, root command, exit-code-mapping `@main`, wiring.
6. `IntegrationTests` — TestHarness + project fixture + the contract cases above.
7. Verify — `swift build` + `swift test` green; `-C` parity, exit `2`/`3`, schema fields confirmed.
8. Docs sync — promote F1 in `AGENTS.md` (banner + real `swift build`/`swift test` commands + "skillet
   / -C / --json / exit codes exist now"); mark roadmap F1 status.

---

## 7. Risks & assumptions
- **ArgumentParser exit codes** differ from §5.4 → handled by the custom `@main` mapping (task 5).
- **`swift-subprocess` 0.2.1 / `swift-system` `FilePath`** harness API — proven by the `subtree`
  reference repo; mirror its usage (`#if canImport(System)`).
- **No `swift-yaml`** — discovery treats `skillet.yaml` as an opaque marker; safe for F1.
- **"No project found" is benign for the root command** (works anywhere, like `git` outside a repo);
  the `requireProject → exit 3` mechanism exists but is exercised by project-requiring commands in F2+.
- Linux parity is asserted by CI in a later phase; F1 verifies locally on macOS.

---

## 8. Definition of done
All success criteria (§1) met; unit + integration suites green; no `Foundation.Process` (launcher
discipline); `EDDCore` pure (no I/O); docs synced. Ready to hand F2 (`init`) a working substrate.
