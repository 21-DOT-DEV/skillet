# Plan — Phase 1 · F2: Adopt skillet in a repo (`skillet init`)

| | |
|---|---|
| **Feature** | 002 — Adopt skillet in a repo (`skillet init`) |
| **Phase** | 1 — Walking Skeleton ([Roadmap/phase-1-walking-skeleton.md](../../Roadmap/phase-1-walking-skeleton.md), F2) |
| **Status** | IMPLEMENTED (2026-06-20) — 45 tests green; docs verified. **Addendum (2026-07-05, F14 review round 5):** `init` now writes the two per-skill skeletons design §6.1 always promised — `evals.json` (`{"skill_name":"<name>","evals":[]}`) and `trigger-eval.json` (`[]`) — idempotently (existing files never touched, proven by test). Skeletons are deliberately empty: an empty axis file *skips* its axis with a note (`run` round-5 symmetry fix) and shows as a "no cases yet" doctor warning, so scaffolding can never block or spend. **Round 6:** the skeleton's `skill_name` is JSON-encoded, not interpolated — a folder legally named `we"ird\name` previously scaffolded *corrupt* JSON (an injection into a frozen artifact); planner test proves the weird name round-trips intact. |
| **Post-audit (2026-07-01)** | Verified by the [Phase-1 audit](../../Roadmap/phase-1-review.md). As-built deltas: the next-step line prints the honest **registered** subset (`lint · run` today; `doctor`/`next` join when they exist); dump-help is decoded with a local minimal type (no `ArgumentParserToolInfo` dependency); the 2026-06-23 `InitReport` fix lists the auto-created `evaluations/` parent; the template later gained the F7 knobs (`runs.max_output_bytes`, `judge.*` — F7 rounds 8–9). |
| **Last updated** | 2026-06-20 |
| **Builds on** | F1 (project discovery, output contract, `RenderKit`) — [spec 001](../001-project-discovery-output-contract/plan.md) |
| **Authoritative refs** | design §6.1 `init`, §5.2 (config template + surgical writes), §7.1 (per-skill `evaluations/` layout), §4 (skill = dir with `SKILL.md`); constitution I/III/IV/VI/VII; clig.dev; swift-argument-parser doc tooling (`generate-manual`, `generate-docc-reference`, `--experimental-dump-help`) |
| **Workflow** | Standalone plan (spec-kit workflow intentionally skipped) |

---

## 1. Goal

One idempotent `skillet init` turns a skills repo into a skillet project: write a commented
`skillet.yaml`, scaffold per-skill `evaluations/` evidence directories, make the cache uncommittable,
and point the user at the next real step. Onboarding in one command (design D2's "value in 30s").
F2 also establishes the project's **verified-documentation** discipline (constitution Principle VII):
docs are checked, not just written.

**Success criteria (roadmap F2):**
- `init` writes a valid `skillet.yaml` + `evaluations/` skeleton, then prints the next commands.
- Re-running fills gaps and overwrites nothing (idempotency test passes).
- Plus: `swift build` + `swift test` green; every `--json` payload carries its `schema`; the
  documentation checks (below) pass and `README.md` is current.

---

## 2. Scope

### In scope
- **`skillet init [--skill <path>…] [--json]`** — the executable's first subcommand (F1 root overview preserved).
- Write repo-root **`skillet.yaml`** from the canonical commented template (design §5.2) — **text, Foundation only, no `swift-yaml`**.
- **Discover skills** = directories containing `SKILL.md` under `skills_root` (default `skills`), or explicit `--skill` paths.
- Per skill, scaffold **`<skill>/evaluations/{friction,findings,sessions}/`** (+ a directory-keeping `.gitignore` that ignores nothing — not a `.gitkeep`; see [Adam Johnson, "Don't create `.gitkeep`"](https://adamj.eu/tech/2023/09/18/git-dont-create-gitkeep/)).
- Write **`.skillet/.gitignore`** containing `*` (self-owned cache ignore) — repo-root `.gitignore` **never** touched (clig.dev: don't edit config that isn't ours).
- **Idempotent:** create-missing-only, never overwrite, report created vs. skipped.
- **Empty repo** (no skills): write `skillet.yaml`, create an empty `skills/` root, guide the user to add a `SKILL.md`.
- **Output:** human summary + an accurate next-command suggestion (**only commands that exist**); `--json` → a `skillet.init/1` payload.
- **Documentation (verified):** rich ArgumentParser `abstract`/`discussion`/`help:` on `init`; bring **`README.md`** current (install + F1/F2 usage); add the **doc-verification checks** (§4.6).

### Out of scope (deferred, with where it lands)
- Frozen **`evals.json`/`trigger-eval.json`** skeletons → **F8** (the boundary-codec feature owns their shape + goldens).
- **Harness detection/probing** → F5/F6 (`init` writes a static `harness.default: claude-code`).
- **Config *parsing* / `swift-yaml`** → first feature that must *read* config (`doctor`/`run`/`config`).
- **Custom `skills_root` honoring on re-init** (needs config reading) → ships with config parsing.
- Committing generated reference artifacts / CI regeneration of `generate-docc-reference` → a later docs pass (the plugins are available now; we don't commit their output yet).
- **DocC snippets** (no public Swift API to exercise) and **doc-example execution / "flavor 2"** (Swift has no idiomatic runtime doctest) → not adopted.

---

## 3. Architecture (targets touched)

No new product targets; runtime dependencies unchanged (**no `swift-yaml`**).

```
skillet (executable)   InitCommand subcommand · next-command suggestion · --json · rich help text
  → ProjectKit         skill discovery · init planning/execution · skillet.yaml template · cache ignore
      → EDDCore        InitReport / skillet.init/1 payload
  → RenderKit          init summary (human) / JSON envelope
```

- Unit logic in `ProjectKit` (`ProjectKitTests`). CLI behavior in `IntegrationTests` (built binary).
- **`IntegrationTests` gains** `.product(name: "ArgumentParserToolInfo", package: "swift-argument-parser")` to decode `--experimental-dump-help` for the surface check (test-only).

---

## 4. Detailed design

### 4.1 `skillet.yaml` template (ProjectKit)
A static, commented template string == design §5.2's documented config (`project.skills_root`,
`runs.*`, `harness.default: claude-code` + `matrix`, `judge`, `gates`, `scorers`, `lint`). Emitted
verbatim on first init. Comments survive because it's text, not `swift-yaml` re-emit (design §5.2).

### 4.2 Skill discovery (ProjectKit)
`SkillScanner`: given `skills_root` (or explicit `--skill` paths), return immediate subdirectories
that contain a `SKILL.md` (design §4). Needs directory *listing*, so extend `DirectoryProbe` with
`subdirectories(of:)`; the in-memory fake implements it for unit tests.

### 4.3 Init planning + execution (ProjectKit) — pure plan, effectful apply
- `InitPlanner` (pure; reads via `DirectoryProbe`): repo root + `skills_root` + discovered skills +
  current FS state → an `InitPlan` = ordered `[InitAction]` (`createDirectory` / `writeFile`), **only
  for missing targets** (idempotency by construction). Actions: `skillet.yaml`; `.skillet/.gitignore`
  (`*`); per-skill `evaluations/{friction,findings,sessions}/` + a directory-keeping `.gitignore`; `skills/` root when none exist.
- `InitExecutor` (effectful; `FileSystemWriter` seam): applies the plan → `InitReport`
  `{ created: [String], skipped: [String], skills: [String] }`.
- `FileSystemWriter` protocol (`createDirectory`, `writeFile`) + real impl + in-memory fake (tests).

### 4.4 `skillet init` (executable)
- `InitCommand: AsyncParsableCommand`, `@OptionGroup GlobalOptions`, `@Option var skill: [String]`.
- Resolves the start/root via F1's `ProjectLocator` (honoring `-C`), runs planner → executor, renders the report.
- **First subcommand:** `SkilletCommand.configuration.subcommands = [InitCommand.self]`; the root's
  `run()` (overview) stays the default with no subcommand (verify ArgumentParser behavior in TDD).
- **Next-command suggestion:** an ordered onboarding list (`doctor` → `run` → `next`) **filtered to
  registered subcommands** — never advertises an unimplemented command (clig.dev). F2 → fallback:
  `skillet --help`, plus "add a `SKILL.md` under `skills/` and re-run" when no skills were found.
- **Help text (convention):** the user-facing description lives in `abstract`/`discussion` + per-flag
  `help:` (the source of truth for `--help`, `--experimental-dump-help`, and the generated reference).
  A terse `///` may describe the type's *role* (wiring) but **must not duplicate** the help.
- **Exit:** `0` success; `3` if a `--skill` path or write target is missing/unwritable.

### 4.5 Output (EDDCore + RenderKit)
- EDDCore: `InitReport` → `skillet.init/1` envelope `{ schema, created[], skipped[], skills[] }`.
- RenderKit: human summary ("Initialized skillet — wrote N, skipped M; K skills") + next-step line;
  `--json` emits the envelope on stdout. Errors reuse `skillet.error/1`.

### 4.6 Documentation & verification (three layers)
The Swift-idiomatic "docs stay true" approach — generate-from-source + verify-the-parser, **never
asserting human/TTY prose** (constitution P7/VII):

1. **Reference (generated, available now):** `swift package generate-manual` and
   `swift package generate-docc-reference` produce a man page / DocC reference from the command tree
   (the plugins ship with `swift-argument-parser`). Documented here as available; committing artifacts
   / CI regeneration is a later pass.
2. **Surface verification (built in F2):** a test decodes **`skillet --experimental-dump-help`** via
   `ArgumentParserToolInfo` and asserts the documented commands/flags exist; it cross-checks the
   `README.md`/`AGENTS.md` "Commands (true now)" list so docs can't claim a command the binary lacks.
3. **Behavioral + links (built in F2):** binary-spawning tests assert exit codes + `--json` `schema`
   (which generation/dump-help can't), and an internal-doc-link check confirms relative links resolve.

`README.md` (currently a stub — a Principle VII MUST gap) is brought current: install
(`swift build`/SwiftPM) + `skillet` / `init` / `--json` / `-C` usage.

---

## 5. Test plan (TDD — red → green)

**Unit — `ProjectKitTests`:**
- `SkillScanner`: finds `SKILL.md` dirs under `skills_root` (fake probe); ignores non-skill dirs; honors `--skill`.
- `InitPlanner`: fresh repo → plan has `skillet.yaml` + `.skillet/.gitignore` + per-skill dirs; **re-run → empty plan** (idempotency); partial → fills only gaps; empty repo → `skillet.yaml` + `skills/` only.
- Template contains key anchors (`skills_root`, `harness.default`).

**Integration — `IntegrationTests` (built binary):**
- `init` on a temp repo with a skill → creates `skillet.yaml`, `<skill>/evaluations/{friction,findings,sessions}`, `.skillet/.gitignore`; exit 0; prints summary + next step.
- **Idempotent re-run** → everything "skipped", no content changes, exit 0.
- `.skillet/.gitignore` contains `*`; repo-root `.gitignore` absent/unchanged.
- `--json` → valid `skillet.init/1` with `created`/`skipped`/`skills`.
- Empty repo → `skillet.yaml` + `skills/` created; guidance printed.
- `--skill <path>` scaffolds that skill; nonexistent `--skill` → exit 3.
- **Docs — surface:** decode `--experimental-dump-help`; assert `init` (+ its flags) present; assert each "Commands (true now)" entry exists in the dump.
- **Docs — behavioral + links:** documented commands hold their exit/`--json` `schema`; internal links in `README.md`/`AGENTS.md`/`ROADMAP.md` resolve.

300-line soft cap; extend `Fixture` with skill-directory builders.

---

## 6. Task breakdown (ordered)
1. `ProjectKit`: extend `DirectoryProbe` (listing) + `FileSystemWriter` seam (+ fakes). *(tests first)*
2. `ProjectKit`: `SkillScanner`. *(tests first)*
3. `ProjectKit`: `skillet.yaml` template + `InitPlanner` (pure, idempotent). *(tests first)*
4. `ProjectKit`: `InitExecutor` + `InitReport`.
5. `EDDCore`: `InitReport`/`skillet.init/1` payload; `RenderKit` init rendering. *(tests)*
6. `skillet`: `InitCommand` (+ rich `abstract`/`discussion`/`help:`) + next-command suggestion; register subcommand, preserve root overview.
7. `IntegrationTests`: init cases (extend `Fixture`).
8. Docs verification: add `ArgumentParserToolInfo` dep; dump-help surface check + link-check; **rewrite `README.md`** current.
9. Verify: `swift build` + `swift test` green; smoke-test `init`, re-init, `--json`, `.skillet/.gitignore`; spot-check `generate-docc-reference`.
10. Docs sync: AGENTS.md (F2 command/status/Commands), roadmap F2 → DONE, this plan → IMPLEMENTED, `Specs/README` row.

---

## 7. Risks & assumptions
- **No `swift-yaml`:** template is text; re-init uses the default `skills_root` (custom honoring deferred).
- **Frozen skeletons deferred to F8** — avoids F2 freezing `evals.json`/`trigger-eval.json` shapes.
- **`.skillet/.gitignore` = `*`** reliably keeps the cache out of git (nested `.gitignore`); root file untouched.
- **`--experimental-dump-help` is nominally experimental** but stable in practice (Apple ships `ArgumentParserToolInfo`); acceptable for the surface check.
- **Subcommand structure:** root overview must remain the default with no subcommand — verified in TDD.
- **Next-commands / docs checks** assert facts (existence, exit codes, `--json` schema, link resolution), **never** human/TTY prose (P7).

## 8. Definition of done
All success criteria met; idempotency proven; `.skillet/.gitignore` present and root `.gitignore`
untouched; `--json` carries `schema`; `README.md` current; the doc-verification checks (surface +
behavioral + links) pass; unit + integration suites green; no `Foundation.Process`; `EDDCore` stays
pure; docs synced.
