# Plan — Phase 1 · F6: claude-code adapter (trace parser, resolution & probe)

| | |
|---|---|
| **Feature** | F6 — claude-code adapter (trace parser, resolution & probe; live `run` in F7) |
| **Phase** | 1 — Walking Skeleton ([Roadmap/phase-1-walking-skeleton.md](../../Roadmap/phase-1-walking-skeleton.md), F6) |
| **Status** | ✅ IMPLEMENTED (2026-06-21) — 76 tests green |
| **Post-audit (2026-07-01)** | Verified by the [Phase-1 audit](../../Roadmap/phase-1-review.md). Deltas: the automatic denylist fallback was re-deferred **F7 → F50** (2026-06-27) — shipped behavior *refuses* an auto-discovered-banned binary at `run` (exit 3) and warns via `HarnessInfo.warnings` in `harness info`; `Denylist.Decision.warnedFallback` keeps its pre-F50 name; the synthetic fixture shipped inline (no `Fixtures/` dir); `probe` evolved to `probe(strict:)` with the non-spending auth check (F7). Gaps C/D remain open; gap **#3 closed** (typed `harnessNotFound` what/why/fix). |
| **Last updated** | 2026-06-21 |
| **Builds on** | F5 (`HarnessAdapter` seam, `Trace`, `HarnessKit`, registry) — [spec 003](../003-normalized-trace-harness-seam/plan.md); F1/F2 (`EDDCore`, `RenderKit`, executable) |
| **Authoritative refs** | design §9.1 (adapter protocol, resolution + ban policy), §9.2 (injection/visibility), §9.3 (normalized trace + claude-code session JSONL), §9.5 (adapter matrix), §13 (v1 scope; `Trace.usage` is v1.x); constitution III/V/VI |
| **Scope** | **Option B** — the validatable core now; live `run` + §9.2 skill-injection → F7. Also lands `swift-yaml`, **isolated**. |
| **Workflow** | Standalone plan (spec-kit workflow intentionally skipped) |

---

> **✅ Implemented 2026-06-21** (76 tests green). One delta from the design below: the task-1 interop
> spike found C++ interop is **viral to direct importers**, so §3's hope that "the executable stays
> interop-free" does not hold — the `skillet` executable is a **`.Cxx` leaf**. The load-bearing goal
> held: `EDDCore` + every kit stay interop-free (they consume a decoded `SkilletConfig`, never importing
> `ConfigYAML`). Live `run` + §9.2 skill-injection deferred to F7 as planned.

## 1. Goal

Make **claude-code** the first real harness behind the F5 seam: parse its native session into a
`Trace`, resolve and vet its binary, and provide the `probe` + static skill-visibility check that
`doctor` (F3) needs — **all validatable without a live claude-code**. The live task execution
(`run` + §9.2 skill-injection) lands in **F7**, where a real harness validates it. F6 also lands the
long-deferred **`swift-yaml`**, isolated in a `ConfigYAML` target so the pure core stays interop-free.

**Success criteria (roadmap F6, scope B):**
- A claude-code native session (JSONL) parses into a `Trace` (turns, tool calls, file changes, skill invocations), golden-tested vs a **synthetic** fixture mirroring the real format.
- The binary resolution chain (flag > env > config > PATH > vendored) selects the right link and prints which won.
- A seed-denylist version is refused when pinned (exit `3`), or warned + fallen-back-from when auto-discovered.
- `probe()`/`verifySkillVisibility` are implemented behind a fakeable `ProcessLauncher` (logic unit-tested); `probe`'s live call is env-gated (F7).
- `swift-yaml` is wired in an isolated `ConfigYAML` target; **`EDDCore` and every kit stay interop-free** (build-validated). C++ interop is viral to direct importers, so the executable is a `.Cxx` leaf (see note above).
- `swift build` + `swift test` green.

---

## 2. Scope

### In scope
- **`ConfigYAML`** (new, isolated): `swift-yaml` (`YAML` product, `.interoperabilityMode(.Cxx)` *here only*) decoding `skillet.yaml` → a **pure `SkilletConfig`** model in `EDDCore`. Minimal loader.
- **`HarnessKit`**: the real `ClaudeCodeAdapter` (replacing the F5 stub) — `parseTrace`, the resolution chain, the denylist/ban policy, `probe()` (seam), `verifySkillVisibility` (static), and a thin `run()` seam. Adds a fakeable **`ProcessLauncher`** over `swift-subprocess`.
- Register the real adapter; the executable loads config (via `ConfigYAML`) for the resolution config-link.
- A **synthetic** claude-code JSONL fixture + golden parse test; unit tests for resolution/denylist/probe (fakes) and `SkilletConfig` decode.
- Docs: deps-notes + §11 dependency-policy updated ("`swift-yaml` wired, isolated in `ConfigYAML`").

### Out of scope (deferred, with where it lands)
- **Live `run()` execution + §9.2 skill-injection + the env-gated live smoke** → **F7** (its consumer, the `Workspace` lifecycle, and a real claude-code to validate it). F6's `run()` throws `.notImplemented`.
- **`probe()`'s live validation** (a real claude-code present) → F7's smoke. (Logic is fake-tested here.)
- **Full config precedence + `config list --origins` + the per-repo denylist override file** → **F3** (doctor).
- **`Trace.usage` population** → v1.x (§13); `parseTrace` leaves it `nil`.
- **Vendored-binary search** (the `harness which --search` recursive finder) → minimal/stub now; full later.

### Known gaps (post-implementation, tracked)
A follow-up pass corrected the parser against the **real** `~/.claude` native format (tool-result `user`
lines are no longer counted as turns; `workspaceDiff` is derived from each result's `toolUseResult`
rather than the request input) and made the auto-discovered-banned case surface a **loud notice** via
`HarnessInfo.warnings`. These remain open, by design:
- **(C) Deletions not modeled** — `Trace.workspaceDiff.deleted` is always empty (no `delete` `toolUseResult.type` observed in the sampled format). → Phase 2+.
- **(D) Failed/`is_error` tool results not captured** — a `Skill` invocation is recorded even when its result errored, which is exactly the failure mode the `2.1.143` denylist seed exists for. → Phase 2+.
- **(#3) Missing/unresolved binary surfaces a raw launcher error**, not a P6 what/why/fix message; the live launch path is **F7**-gated (env-gated smoke).
- **(Automatic denylist fallback)** — notice-only today; falling back to a non-banned binary needs the resolver to enumerate candidates. → F7.

*(Resolved in the same pass: F — `InitReport.created` now lists the `evaluations/` parent dir, which the planner emits as an explicit, idempotent `createDirectory` action.)*

---

## 3. Architecture (targets touched)

```
skillet (executable)   loads config (ConfigYAML) → passes harness path to resolution; registers the real adapter
  → ConfigYAML (NEW, .Cxx) → swift-yaml (YAML) + EDDCore     decode skillet.yaml → SkilletConfig
  → HarnessKit              ClaudeCodeAdapter · BinaryResolver · Denylist · ProcessLauncher (+ swift-subprocess)
      → TraceKit, EDDCore
  → EDDCore                 SkilletConfig (pure model)
```

**Interop containment (the load-bearing claim):** only `ConfigYAML` enables C++ interop. `HarnessKit`'s
resolution takes config *values* (a pure `SkilletConfig`/`String?`) as **input** — it does **not**
import `ConfigYAML` — so it stays interop-free. The executable imports `ConfigYAML` only to load config;
since `ConfigYAML`'s public API is pure Swift (`SkilletConfig`), the executable should not need interop
either. **Task 1 validates this by building** with interop enabled *only* on `ConfigYAML`.

**New dependencies:** `swift-yaml` (new package, pinned by **revision** — no tagged release) → `ConfigYAML`;
`swift-subprocess` (already a package dep) added to the **`HarnessKit`** target for the real `ProcessLauncher`.

---

## 4. Detailed design

### 4.1 `SkilletConfig` (EDDCore, pure) + `ConfigYAML` (isolated)
- `EDDCore.SkilletConfig`: a pure `Codable`/`Sendable` model of `skillet.yaml` — enough for F6
  (`project.skills_root`, `harness.default`, `harness.<id>.path`) with a forward-compatible shape; no `swift-yaml`.
- `ConfigYAML.ConfigLoader`: `load(yaml: String) throws -> SkilletConfig` and
  `load(from root: URL) throws -> SkilletConfig?` (nil when no `skillet.yaml`), via `swift-yaml`'s decoder.
  Target has `swiftSettings: [.interoperabilityMode(.Cxx)]`; `swift-yaml` pinned by revision.

### 4.2 `ClaudeCodeAdapter` (HarnessKit) — replaces the F5 stub
- **`parseTrace(RawTrace) -> Trace`**: claude-code native JSONL → `Trace`. Skip control lines
  (`ai-title`/`last-prompt`/`queue-operation`); map `user`/`assistant` lines → `Turn` (role from
  `message.role`; text from `text` blocks; `toolCalls` from `tool_use`; `at` from `timestamp`);
  `harness = "claude-code"`, `harnessVersion` from `version`; `usage = nil` (v1.x). `skillInvocations`
  (from the `Skill` tool_use / activation events) and `filesTouched`/`workspaceDiff` (from `Write`/`Edit`
  `tool_use` + `toolUseResult`) — **I'll inspect one richer real session (read-only) to nail these**,
  then author the synthetic golden fixture to match.
- **`BinaryResolver`**: flag > env (`SKILLET_CLAUDE_CODE_BIN`) > config (`harness.claude-code.path`, passed
  in) > `PATH` > vendored (minimal); returns the resolved path + **which link won** (printable). Behind a
  fakeable FS/PATH probe → unit-tested.
- **`Denylist`**: seed list in code (`claude-code 2.1.143`, §9.1) + bypass env
  (`SKILLET_ALLOW_BANNED_CLAUDE_CODE`). Auto-discovered banned → warn + fall back; **explicitly pinned
  banned → `EDDError.environment` (exit 3)**.
- **`probe()`**: resolve → version (via `ProcessLauncher`) → denylist → auth → `HarnessInfo`. Logic
  fake-tested; the live `claude --version`/auth call is env-gated (F7).
- **`verifySkillVisibility(skill, strategy)`**: **static** $0 check (§9.2) — positive-load (target
  `SKILL.md` + `references/` resolve under the injection strategy) and discovery-only (siblings listable,
  not injected). Validatable now; `doctor` (F3) consumes it.
- **`run()`**: `throw HarnessError.notImplemented("live execution lands in F7")` — thin seam.
- **`ProcessLauncher`**: protocol over `swift-subprocess` (real) + an in-memory fake (tests); the *only*
  process-launch surface (constitution VI — no `Foundation.Process`).

### 4.3 Registry + executable
Register the real `ClaudeCodeAdapter` (replacing the F5 stub). The executable loads config via
`ConfigYAML` and passes `harness.claude-code.path` into the resolver. `harness info claude-code` now
reflects the real adapter (here: "not found" via the resolution chain, since claude-code isn't installed).

---

## 5. Test plan (TDD)

- **`EDDCoreTests`**: `SkilletConfig` decodes/round-trips.
- **`ConfigYAMLTests`**: `ConfigLoader` decodes a sample `skillet.yaml` → `SkilletConfig`. (Interop
  containment is verified by the build: `EDDCore`/`HarnessKit`/executable compile interop-free.)
- **`HarnessKitTests`**: `parseTrace` golden vs the synthetic fixture; `BinaryResolver` (fake FS/PATH →
  correct link wins + printable); `Denylist` (fake versions → pinned-banned exit 3, auto-banned warn+fallback);
  `probe()` logic (fake `ProcessLauncher` → version/denylist); `verifySkillVisibility` (fixture skill dir).
- **`IntegrationTests`**: `harness info claude-code` reflects the real adapter (`--json` schema intact).
- **Fixture**: a hand-authored claude-code JSONL under `Tests/HarnessKitTests/Fixtures/` (synthetic; no secrets).

---

## 6. Task breakdown (ordered)
1. **`swift-yaml` interop spike (gate):** add `swift-yaml` (pin a revision); create `ConfigYAML` (`.Cxx`) with a trivial decode; have the executable import it; **build and confirm `EDDCore`/`HarnessKit`/executable stay interop-free**. If interop cascades, **stop and reassess** (e.g., the interop-free `yamlcpp` product + a thin shim) before proceeding.
2. `EDDCore`: `SkilletConfig` pure model. *(tests first)*
3. `ConfigYAML`: `ConfigLoader` (YAML → `SkilletConfig`). *(tests)*
4. `HarnessKit`: add `swift-subprocess`; `ProcessLauncher` seam (real + fake).
5. `HarnessKit`: `BinaryResolver` + `Denylist`. *(tests first, fakes)*
6. `HarnessKit`: `ClaudeCodeAdapter` — inspect a richer real session (read-only) → `parseTrace` (golden vs synthetic fixture); `probe` (seam); `verifySkillVisibility` (static); `run()` thin seam.
7. Register the real adapter; executable loads config for the resolution config-link.
8. `IntegrationTests` + `DocsTests` updates.
9. Verify: `swift build` + `swift test` green; smoke `harness info claude-code` (+ `--json`).
10. Docs sync: AGENTS deps-notes (`swift-yaml` wired/isolated; `swift-subprocess` now in `HarnessKit`) + §11 dependency-policy; roadmap F6 → DONE; this plan → IMPLEMENTED; `Specs/README`.

---

## 7. Risks & assumptions
- **`swift-yaml` C++-interop cascade** — the task-1 spike gates this; if importing `ConfigYAML` forces interop on its consumers, reassess (interop-free `yamlcpp` + shim, or another approach) before building further.
- **No tagged release** → pin `swift-yaml` by revision; record the pinned commit in `Package.resolved`/docs.
- **claude-code native format** — the core is grounded; `filesTouched`/`workspaceDiff`/`skillInvocations` need one richer real session (read-only) to map correctly; the committed fixture is synthetic (constitution VI).
- **claude-code unavailable in CI** — `probe`/`run` live paths are env-gated (validated in F7), not by me here or free CI.
- **`verifySkillVisibility` injection specifics** — best-effort static check of claude-code's skill-discovery staging; refined when validated live (F7/F3).

## 8. Definition of done
`parseTrace` golden green; resolution + denylist + probe/visibility fake-tested; `ConfigYAML` decodes and
**interop is contained** (build proves it); `swift build` + `swift test` green; docs synced; `EDDCore` stays
pure and interop-free; live `run` deferred to F7.
