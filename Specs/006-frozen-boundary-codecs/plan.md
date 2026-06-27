# Plan — Phase 1 · F8: frozen boundary-format codecs + golden tests

| | |
|---|---|
| **Feature** | F8 — frozen boundary-format codecs + golden tests (EDDCore; no new command) |
| **Phase** | 1 — Walking Skeleton ([Roadmap/phase-1-walking-skeleton.md](../../Roadmap/phase-1-walking-skeleton.md), F8) |
| **Status** | ✅ IMPLEMENTED (2026-06-24) — codecs + goldens green (95 tests); §7.2 *prose* reconciliation pending |
| **Last updated** | 2026-06-24 |
| **Re-sequence** | **F8 moves before F4** (build order → F1, F2, F5, F6, **F8**, F4, F7; doctor/F3 has since moved to Phase 2 — roadmap v1.8.0). F4 consumes F8's `evals.json` codec; F7 consumes the run-record family. |
| **Builds on** | F1 (`SkilletJSON` envelope, golden-test harness); F6 (the `Trace`/`*.trace.json` codec already shipped; the synthetic-fixture discipline) |
| **Authoritative refs** | **Anthropic skill-creator 2.0** [`references/schemas.md`](https://github.com/anthropics/skills/blob/main/skills/skill-creator/references/schemas.md) (Group 1); design §7.2/§7.5 (frozen formats), §9.3 (Trace), §9.4 (SARIF roles); SARIF 2.1.0 (OASIS); constitution IV (frozen formats), VI (no committed real artifacts/secrets) |
| **Scope** | Land the EDDCore **models + decode/encode codecs + golden fixtures** for the boundary formats, grounded in reality; **reconcile §7.2** to match. Consumers (`run`/`report`/`capture`) stay in their phases. |
| **Workflow** | Standalone plan (spec-kit workflow intentionally skipped) |

---

> **✅ Implemented 2026-06-24**, grounded by the deep-research pass. **As built (single idiom):** every
> codec **holds its raw document** (`JSONValue` for `EvalsFile`, `[String: JSONValue]` for the
> `RawJSONObject` family) and re-emits it **verbatim** — so unknown keys round-trip by construction, with
> no key rename and no injected fields (synthesized `Codable` would silently drop unknowns). Golden
> comparison is **semantic** (`jsonSemanticEqual` — order-independent, `1 == 1.0`), *not* `sortedKeys`
> bytes (non-portable across Darwin/Linux, research-confirmed); the raw-object codecs make SARIF's
> "tolerant `level`" automatic — no closed enum to reject an unknown value. `EvalsFile` reads 2.0 +
> legacy + local aliases and round-trips both container shapes; `caseCount` unblocks F4.
>
> **Review pass (2026-06-25):** `EvalsFile`'s reconstruct-on-encode was replaced by verbatim re-emit —
> fixing a silent `cases`→`evals` rename (and `cases` is dropped: ungrounded, not in 2.0) and an injected
> empty `evals` key; the unused `decodeExtra`/`encodeExtra`/`AnyKey` idiom was removed (one idiom only);
> and an explicit byte test locks integral numbers re-encoding as `3`, not `3.0` (`jsonSemanticEqual`
> would otherwise mask it). 96 tests green.
>
> **One item remains:** the §7.2 *design-doc text* reconciliation (the code is built to the 2.0 shapes;
> the prose lags) — deferred while the design doc is being actively edited.

## 1. Goal

Re-establish the frozen-boundary-format discipline — **wire-compatible · golden-tested · additive** — as a real, shipped foundation rather than a §7.2 promise. Land the EDDCore codecs + golden fixtures for every boundary format skillet reads or writes, **grounded against ground-truth** (Anthropic skill-creator 2.0 for the eval/benchmark family; skillet design for the trigger/trace/SARIF family), and reconcile §7.2 — which had drifted from the current Anthropic shapes.

**Success criteria:**
- Each in-scope format **round-trips with unknown keys preserved** (a `benchmark.json` skillet rewrites still renders in the skill-creator viewer; verified by golden).
- `evals.json` decodes the **skill-creator 2.0** object `{skill_name, evals:[…]}` *and* the legacy bare array, into one normalized model; `caseCount` is correct for both (F4's `L009`).
- Golden fixtures are **synthetic** (modeled on real shapes, not committed real artifacts — constitution VI), one per format, both shapes where two exist.
- §7.2 reconciled to the grounded shapes (revision-logged); `swift build` + `swift test` green.

---

## 2. Grounding (how the shapes were established)

Cross-referenced Anthropic's published `references/schemas.md` and **verified against real artifacts in `~/Developer/skills`** (read-only). The frozen-format universe splits three ways:

| Group | Formats | Ground-truth | Action |
|---|---|---|---|
| **1 · Anthropic-canonical** (local artifacts verified to align ✓) | `evals.json` (2.0), `benchmark.json`, `grading.json`, `timing.json`, `metrics.json`, `metadata.json` | `schemas.md` + real samples | model + codec + golden |
| **2 · skillet-design** (Anthropic doesn't define) | `trigger-eval.json`, SARIF 2.1.0 (+ `audit-baseline`/`audit-input` roles); **Trace `*.trace.json` shipped in F6** | design §7.2/§9.3/§9.4 + OASIS | model + codec + golden |
| **3 · local-only** (ignore) | `scorecard.json` `{rows, schema_version, …}` | the local impl's own | **not adopted** |

The local `SkillEvalKit`/`SkillEvalCLI` outputs proved to be **skill-creator-2.0-compatible** (benchmark/grading/evals align; additive extras like `analyzer_model`, `tool_calls`, `run_number`), so they corroborate the spec — but goldens are authored synthetic, not copied from them.

---

## 3. Scope

### In scope — codecs + goldens (all in `EDDCore`, pure, Foundation `Codable`; **no new dependency**)
**Group 1 (Anthropic 2.0):**
- **`EvalsFile`** — canonical = `{skill_name, evals:[{id:Int, prompt, expected_output, files?:[String], expectations:[String]}]}`; **also decodes** the legacy bare array `[{skills, query, files?, expected_behavior, timeout_seconds?}]` and the local `{assertions, name}` case fields, normalizing to one model (decode aliases: `query`→`prompt`, `expected_behavior`/`assertions`→`expectations`). `caseCount` for F4.
- **`BenchmarkFile`** — `{metadata:{skill_name, skill_path, executor_model, timestamp, evals_run, runs_per_configuration, …}, runs:[{configuration:"with_skill"|"without_skill", result:{pass_rate, passed, failed, total, time_seconds, tokens, errors, …}, …}], run_summary, notes?}`. Round-trips unknown keys (viewer compatibility).
- **`GradingFile`** — `{expectations:[{text, passed, evidence}], summary:{passed, failed, total, pass_rate}, execution_metrics, timing, claims?, user_notes_summary?, eval_feedback?}`.
- **`TimingFile`** — `{total_tokens, duration_ms, total_duration_seconds, executor_*?, grader_*?}`.
- **`MetricsFile`** — `{tool_calls:{String:Int}, total_tool_calls, total_steps, files_created:[String], errors_encountered, output_chars, transcript_chars}`.
- **`EvalMetadataFile`** — per-test `{eval name, assertions[]}` (the `eval_metadata.json` sibling).

**Group 2 (skillet-design):**
- **`TriggerEvalFile`** — bare array `[{query, should_trigger}]` (design §7.2).
- **SARIF 2.1.0** — the subset skillet emits/reads (`{version, runs:[{tool, results:[{ruleId, level, message, locations}]}]}`) + the `audit-baseline.sarif` / `audit-input.sarif` **role** convention (§9.4); `bundle verify`'s directionality check is Phase 3, but the model + role naming land here.

### Out of scope (deferred, with where it lands)
- **Consumers** — `run` writing `benchmark.json`/`grading.json`, `report` rendering, the trigger axis executing, the scorers emitting SARIF → **F7 / Phase 2**. F8 lands *codecs + goldens*, not the logic that produces them from a live run.
- **Full session-*bundle* assembly + `bundle verify`** (the multi-file directory contract) → **Phase 3**. F8 lands the per-file `session-meta.json` codec + reuses the F6 `Trace`; the bundle *layout* contract is Phase 3.
- **`history.json`, `comparison.json`, `analysis.json`** (optimizer artifacts) → **Phase 6/8**.
- **`scorecard.json`** — **not adopted** (Group 3, local-only).
- **Encode-from-run** for benchmark/grading (skillet *produces* these) — the models support encoding + round-trip here, but populating them from a real run is F7.

---

## 4. Architecture

```
EDDCore (pure, Foundation Codable — no new dependency)
  Boundary/  EvalsFile · BenchmarkFile · GradingFile · TimingFile · MetricsFile · EvalMetadataFile
             TriggerEvalFile · Sarif (2.1.0 subset + audit role enum)
  (Trace already lives in TraceKit from F6)
```

Each codec: a `Codable` model + `SkilletJSON.decode/encode`, with **unknown-key round-trip** (an `extra` catch-all or a raw re-emit path) so rewrites preserve viewer/tooling fields (frozen-format discipline, D5/§7.2). Models are pure and isolated-testable; no I/O (callers pass `Data`/`String`).

---

## 5. §7.2 reconciliation (a task, design edit)
Update the §7.2 frozen-format table to: the **2.0** `evals.json` (object, `prompt`/`expectations`) as canonical with the legacy array accepted-on-read; `benchmark.json` to the `{metadata, runs, run_summary}` shape + name the **run-record family** (`grading.json`, `timing.json`, `metrics.json`, `eval_metadata.json`); keep `trigger-eval.json`/Trace/SARIF as skillet-design; **explicitly exclude `scorecard.json`**. Revision-log bump. (Done as part of this feature, coordinated against the design doc's current revision.)

---

## 6. Golden + test plan (TDD)
- **`EDDCoreTests`** (or a `Tests/Golden/boundary/` set): per format, decode a synthetic golden → assert fields; **round-trip** (decode → encode → byte/semantic-equal) with an **unknown key** present → preserved.
- `EvalsFile`: 2.0 object **and** legacy array **and** local-alias fixtures → same normalized model + correct `caseCount` (incl. `<3`, `0`).
- `BenchmarkFile`: viewer-critical nesting (`pass_rate` under `result`, `configuration` enum) locked; unknown key (`analyzer_model`) survives round-trip.
- `GradingFile`: `expectations[].{text,passed,evidence}` exact names locked.
- `Sarif`: minimal 2.1.0 doc round-trips; the role enum maps `audit-baseline`/`audit-input`.
- `TriggerEvalFile`/`TimingFile`/`MetricsFile`/`EvalMetadataFile`: decode + round-trip goldens.

---

## 7. Task breakdown (ordered)
1. **§7.2 reconciliation** (design edit + revision-log) — pin the canonical shapes before coding to them.
2. `EDDCore`: `EvalsFile` (2.0 + legacy + alias normalization, `caseCount`) + goldens. *(F4 unblocks here.)*
3. `EDDCore`: `BenchmarkFile` + `GradingFile` + `TimingFile` + `MetricsFile` + `EvalMetadataFile` + goldens (round-trip-unknown-keys).
4. `EDDCore`: `TriggerEvalFile` + `Sarif` (subset + role enum) + goldens.
5. Verify `swift build` + `swift test`; docs sync: AGENTS (formats + EDDCore `Boundary/`), roadmap F8 → DONE + re-sequence recorded, this plan → IMPLEMENTED, `Specs/README`.

---

## 8. Risks & assumptions
- **Anthropic keeps moving the case fields** (`query`→`prompt`→…). Mitigation: canonical = current 2.0, *decode* aliases for legacy/local, additive-only; goldens lock all known shapes. The *count* (F4's need) is invariant across shapes.
- **Viewer compatibility is field-exact** (the web warns: `pass_rate` must nest under `result`, grading uses `{text,passed,evidence}`). Mitigation: round-trip-unknown-keys + golden fixtures captured from the verified real shapes.
- **No committed real artifacts** (constitution VI) — goldens are synthetic, corroborated against `~/Developer/skills` during dev only.
- **Scope creep** — F8 lands *codecs*, not consumers; the temptation to build `run`/`report` here is deferred to F7/Phase 2.

## 9. Definition of done
All in-scope formats round-trip (unknown keys preserved) against synthetic goldens; `EvalsFile` normalizes 2.0 + legacy + local with correct `caseCount`; §7.2 reconciled + revision-logged; `EDDCore` stays pure + dependency-free; `swift build` + `swift test` green; F4 can consume the `evals.json` codec.
