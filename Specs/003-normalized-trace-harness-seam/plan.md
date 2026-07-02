# Plan — Phase 1 · F5: Normalized trace & harness-adapter seam

| | |
|---|---|
| **Feature** | F5 — Normalized trace & harness-adapter seam |
| **Phase** | 1 — Walking Skeleton ([Roadmap/phase-1-walking-skeleton.md](../../Roadmap/phase-1-walking-skeleton.md), F5) |
| **Status** | IMPLEMENTED (2026-06-21) — 58 tests green; docs verified |
| **Post-audit (2026-07-01)** | Verified by the [Phase-1 audit](../../Roadmap/phase-1-review.md). Naming delta: the replay double shipped as **`ReplayAdapter`** (house `<X>Adapter` convention), not the `HarnessReplay` written throughout this plan. The protocol later grew `probe(strict:)` + `HarnessInfo.warnings` (F6 correctness pass / F7); design §9.1 and code agree today. |
| **Last updated** | 2026-06-21 |
| **Builds on** | F1/F2 — `EDDCore` (`SchemaIdentified`/`SkilletJSON`/`ExitCode`/`EDDError`), `RenderKit`, the `skillet` executable + subcommand pattern ([spec 001](../001-project-discovery-output-contract/plan.md), [spec 002](../002-adopt-skillet-repo/plan.md)) |
| **Authoritative refs** | design §9.1 (adapter protocol), §9.2 (injection/visibility A/B contract), §9.3 (normalized trace), §9.5 (adapter matrix), §11 (architecture); constitution I/III/IV |
| **Workflow** | Standalone plan (spec-kit workflow intentionally skipped) |

---

## 1. Goal

Establish the two foundations every later capability (capture, triage, judging, `run`, the matrix)
stands on: the **harness-independent `Trace`** (`skillet.trace/1`) and the **`HarnessAdapter`
protocol** seam. Designed-now-not-retrofitted (D4). **Harness-agnostic by construction** — per §9.3,
per-harness parsers live *beside their adapters*, so the claude-code parser + live probe/run land in
**F6**; F5 ships the model, the protocol, a `HarnessReplay` test double, and `skillet harness info`.

**Success criteria (revised — claude-code parse golden test moved to F6):**
- The `Trace` model round-trips through `--json` with its `schema` field intact (golden test).
- `skillet harness info` lists registered adapters + their capability matrix; `--json` carries its `schema`.
- `HarnessReplay` produces a canned `Trace` through the protocol — proving the seam is implementable
  end-to-end with **no live harness**.
- `swift build` + `swift test` green; no new package dependencies.

---

## 2. Scope

### In scope
- **`TraceKit`**: `Trace` (`skillet.trace/1`) + `Turn`, `ToolCall`, `SkillInvocation`, `WorkspaceDiff`, `Usage?`, `HarnessID` — deterministic JSON, golden round-trip.
- **`HarnessKit`**: the **full §9.1 `HarnessAdapter` protocol** + `HarnessCapabilities` + supporting types; `HarnessReplay` (functional test double); a declared `claude-code` **stub**; a small adapter registry; a `HarnessInfoReport` (`skillet.harness-info/1`).
- **`skillet`**: `harness list` + `harness info [<id>]` (human table + `--json`).
- Tests (unit + integration), a `harness info` doc-claim, and README/AGENTS Commands updates.

### Out of scope (deferred, with where it lands)
- **claude-code trace parser + live `probe()`/`run()` + binary resolution/ban policy** → **F6** (per §9.3, parsers live beside their adapter).
- **`swift-subprocess` / `swift-yaml`** — not needed (F5 launches nothing, parses no config) → F6/later.
- **Corrective-turn heuristics** (ported text-pattern detector, §9.3) → **Phase 3** (capture/triage), where first consumed; will live in `TraceKit` then.
- **`verifySkillVisibility` real logic** → F6/`doctor`; **`run`/`Workspace`/`TaskSpec` bodies** → F6/F7. Protocol *signatures* exist now; param types are minimal placeholders.
- **`Usage` token/cost population** → Phase 8 (the field exists, optional, `nil` for now).

---

## 3. Architecture (targets)

Two new targets; **no new package dependencies**.

```
skillet (executable)   harness list/info command + wiring
  → HarnessKit         HarnessAdapter protocol · HarnessCapabilities · HarnessReplay · claude-code stub · registry · HarnessInfoReport
      → TraceKit       Trace (skillet.trace/1) + Turn/ToolCall/SkillInvocation/WorkspaceDiff/Usage/HarnessID
          → EDDCore    SchemaIdentified · SkilletJSON · EDDError
  → RenderKit          (generic table rendering for `harness info`)
```

Unit-test targets: `TraceKitTests`, `HarnessKitTests`. `IntegrationTests` gains harness cases.

---

## 4. Detailed design

### 4.1 TraceKit — the normalized trace (§9.3)
`Trace: SchemaIdentified` (`skillet.trace/1`), fields per §9.3: `harness: HarnessID`, `harnessVersion`,
`startedAt`/`endedAt: Date`, `turns: [Turn]`, `skillInvocations: [SkillInvocation]`,
`workspaceDiff: WorkspaceDiff`, `usage: Usage?`. Sub-types:
- `Turn { role: Role, text: String, toolCalls: [ToolCall], filesTouched: [String], at: Date }` (`Role` = user/assistant/tool/system).
- `ToolCall { name: String, input: String? }` (minimal; richer shape when a parser needs it).
- `SkillInvocation { skill: String, turnIndex: Int }`.
- `WorkspaceDiff { added: [String], modified: [String], deleted: [String] }`.
- `Usage { inputTokens: Int?, outputTokens: Int?, costUSD: Double? }` (all optional; structurally `nil` until Phase 8).
- `HarnessID` (a `RawRepresentable`/string wrapper) lives here so both `Trace` and the adapter can use it without a cycle.

Encoded via `EDDCore.SkilletJSON` (sorted keys, snake_case, ISO-8601). Golden `--json` round-trip test.

### 4.2 HarnessKit — the adapter seam (§9.1)
- `HarnessCapabilities: OptionSet` (`runTask`, `skillInjection`, `traceParsing`, `sessionCapture`, `judging`) — verbatim §9.1.
- `HarnessAdapter` protocol — the **full** §9.1 signature set: `id`, `capabilities`, `probe()`, `verifySkillVisibility(_:strategy:)`, `run(_:in:skills:)`, `parseTrace(_:)`, `locateSessions(_:)`, `exportSession(_:)`.
- Supporting types — fully specified where F5 exercises them (`SkillRef`, `SkillSet` per §9.2 [`none`/`only(load:visible:)`/`ambient`], `InjectionStrategy`, `HarnessInfo` [version/auth/availability]); minimal placeholders for run-path types (`TaskSpec`, `Workspace`, `RawTrace`, `NativeSessionRef`, `SessionQuery`).
- `HarnessError` (e.g. `.notImplemented`, `.notSupported(capability:)`) → mapped to `EDDError.environment` (exit 3) at the CLI; degrade loudly by capability (§9.1).
- **`HarnessReplay`**: implements the whole protocol; `probe()` returns canned `HarnessInfo`; `parseTrace`/canned path yields a fixture `Trace`; capability-absent methods throw `.notSupported`. The proof that the protocol is implementable end-to-end.
- **`ClaudeCodeAdapter` stub**: `id = "claude-code"`, declared `capabilities`; every effectful method throws `.notImplemented` ("arrives in F6"). Enough for `harness info` to list it honestly.
- `HarnessRegistry`: the set of registered adapters for `harness list`/`info`.
- `HarnessInfoReport: SchemaIdentified` (`skillet.harness-info/1`) — adapters with id, capabilities, and probe state — the `--json` payload (lives here since it's harness-domain; conforms to EDDCore's `SchemaIdentified`).

### 4.3 skillet executable — the `harness` command
- `harness list` — registered adapter ids + capabilities.
- `harness info [<id>]` — capability matrix + probe result where implemented (replay: canned; claude-code: "not yet implemented — F6"). Informational ⇒ exit 0; `--json` → `skillet.harness-info/1`.
- Human output via a **generic table helper added to `RenderKit`** (rows in, formatted/color-aware out) — keeps presentation out of the executable and `RenderKit` free of `HarnessKit` types.

### 4.4 Tests
- `TraceKitTests`: `Trace` `--json` round-trip + golden; `schema` present; deterministic; sub-types encode.
- `HarnessKitTests`: capability flags; `HarnessReplay.probe()`/canned `Trace`; `SkillSet` cases; `claude-code` stub throws `.notImplemented`; `HarnessInfoReport` schema.
- `IntegrationTests`: `harness list` shows `replay` + `claude-code`; `harness info` shows capabilities; `harness info --json` → `skillet.harness-info/1`; `harness info claude-code` reports the not-implemented probe state at exit 0. Add a `harness info` claim to `DocsTests`.

---

## 5. Task breakdown (ordered)
1. `TraceKit`: `Trace` + sub-types + `HarnessID`. *(tests first — round-trip/golden)*
2. `HarnessKit`: `HarnessCapabilities` + `HarnessAdapter` protocol + supporting types + `HarnessError`. *(tests first)*
3. `HarnessKit`: `HarnessReplay` + `ClaudeCodeAdapter` stub + `HarnessRegistry` + `HarnessInfoReport`. *(tests)*
4. `RenderKit`: generic table renderer. *(tests)*
5. `skillet`: `harness list`/`info` command + wiring; register `replay` + `claude-code` stub.
6. `Package.swift`: add `TraceKit` + `HarnessKit` (+ test targets); executable → `+HarnessKit`.
7. `IntegrationTests`: harness cases + `DocsTests` claim.
8. Verify: `swift build` + `swift test` green; smoke `harness list`/`info`/`--json`.
9. Docs sync: AGENTS Commands (+ `harness info`), README usage, roadmap F5 → DONE + **move the claude-code-parse metric to F6**, this plan → IMPLEMENTED, `Specs/README` row.

---

## 6. Risks & assumptions
- **Protocol designed ahead of some consumers** (`run`/`Workspace`/`TaskSpec`). Mitigation: §9.1 already specifies the protocol (D4); param types are minimal placeholders fleshed out by F6/F7 — signatures stay stable.
- **Trace sufficiency:** §9.3 asserts the schema expresses what the existing claude-code pipeline records; F6's real parser is the true test — keep `Trace` additive-friendly.
- **Honest capabilities:** `HarnessReplay`/`claude-code` stub must declare only capabilities they truly have; effectful gaps throw loudly (`.notImplemented`/`.notSupported`), never silently no-op.

## 7. Definition of done
`Trace` round-trips via `--json` with `schema` intact (golden); `harness info` lists adapters +
capabilities (`--json` schema); `HarnessReplay` proves the seam end-to-end; `swift build` + `swift test`
green; no new package deps; docs synced (incl. the F5→F6 metric move). `EDDCore` stays pure.
