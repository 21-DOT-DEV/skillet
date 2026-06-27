# Plan — Phase 1 · F4: free static lint — error-tier core (`skillet lint`)

| | |
|---|---|
| **Feature** | F4 — free static `SKILL.md` lint, error-tier core (CLI: `skillet lint`) |
| **Phase** | 1 — Walking Skeleton ([Roadmap/phase-1-walking-skeleton.md](../../Roadmap/phase-1-walking-skeleton.md), F4) |
| **Status** | ✅ IMPLEMENTED (2026-06-25) |
| **Last updated** | 2026-06-26 |
| **Builds on** | F1 (project discovery, output contract, exit codes); F2 (`evaluations/` scaffolding); F6 (the `ConfigYAML`→pure-model config-link + interop-containment pattern); **F8 (the `evals.json` codec — [Specs/006](../006-frozen-boundary-codecs/plan.md), re-sequenced ahead of F4)** |
| **Authoritative refs** | design §6.1 `lint` (catalog + tiers + `--format`), §7.1 (repo layout), §7.2 (frozen `evals.json`), §5.2 (`[lint]` knobs + per-skill overlay), §5.4 (exit codes), §11 (`LintKit`, `EDDCore` codecs); constitution I (TDD), III (deterministic core), IV (frozen formats) |
| **Scope** | **Error-tier core**: `L001` + `L003` + `L009` (full warn+error behavior). `L010`/`L011` (warn-only) + SARIF → Phase 2. |
| **Workflow** | Standalone plan (spec-kit workflow intentionally skipped) |

---

## 1. Goal

Ship `skillet lint` — free, instant, model-free static analysis of skill *source*, the cheapest lever
that gates the expensive ones. It **exits `1` on any error-tier finding**, prints stable diagnostic
ids + fix-hints, and reads exemptions from the `[lint]` config (never inline pragmas). It also lands
the first **`evals.json`** reader (§11) — a frozen boundary format, golden-tested.

**Success criteria (roadmap F4):**
- Flags an over-long description (`SKILL-L001`) and a missing/short `evals.json` (`SKILL-L009`) on fixtures, exiting `1` on any error-tier finding.
- `SKILL-L003` flags an over-long body (warn >500, error >1000 lines, excluding frontmatter + code).
- Stable diagnostic ids + fix-hints in TTY and `--json` (`skillet.lint/1`); exemptions via `[lint].disable`, not inline pragmas.
- `LintKit` is pure + interop-free (the rules engine has no I/O and no YAML); `swift build` + `swift test` green.

---

## 2. Scope

### In scope (the three error-emitting rules, full tiers)
| ID | Check | Tiers |
|---|---|---|
| `SKILL-L001` frontmatter-shape | `description` > 1024 chars **after YAML folding** | error |
| `SKILL-L003` body-token-budget | body line count (excl. frontmatter + fenced code): >500 warn, >1000 error | warn / error |
| `SKILL-L009` has-evals | `evals.json` **missing → error**; present but **< 3 cases → warn** | error / warn |

- `LintKit` (new, pure): the rule engine over a pure `SkillSource`, honoring `[lint]` `disable` + thresholds.
- `EDDCore` (F4's additions): `SkillFrontmatter` model; `Diagnostic` + `LintReport` (`skillet.lint/1`); a `lint` section on `SkilletConfig`. *(The `EvalsFile` / `evals.json` codec now ships in **F8** ([Specs/006](../006-frozen-boundary-codecs/plan.md)); F4 consumes its `caseCount` for `L009` rather than building it.)*
- `ConfigYAML`: `parseFrontmatter(_:)` — split the `---` frontmatter, decode its YAML → `SkillFrontmatter` + body (keeps YAML/C++ interop contained here).
- `ProjectKit`: read each skill's `SKILL.md` text + `evals.json` bytes (the I/O).
- executable `LintCommand` + `RenderKit`: discover → assemble → lint → render (TTY table + `--json`); exit `1` on error-tier.

### Out of scope (deferred, with where it lands)
- **`SKILL-L010` / `SKILL-L011`** (warn-only) + the 7 roadmap rules + **SARIF** + the `--format tty|json|sarif` option → **Phase 2**.
- **Per-skill `evaluations/skillet.yaml` overlay precedence + `config list --origins`** → **F24** (Phase 2 config & CLI ergonomics; F4 reads the repo-level `skillet.yaml [lint]` only).
- **Full frontmatter spec-conformance** (name kebab/length, allowed-keys, duplicate-key rejection, §6.1 `doctor` line) → **Phase 2 full lint catalog (F20)** — they land as `SKILL-Lxxx` rules and surface in `doctor` (F3, also Phase 2) automatically; duplicate-key rejection needs raw-YAML anomaly detection. F4 ships only `L001`'s description-length rule.
- **Security-tier rules** (prompt-injection, evaluator-manipulation, unicode-obfuscation, YAML-anomaly, suspicious-size — Skill-Lab parity) → **Phase 8 F12**. Flagged here so the catalog's growth is visible: F4's `Diagnostic`/`LintReport` (`skillet.lint/1`) is **additive within the major**, so the security tier slots in with no schema change; F12 takes a reserved, greppable id block (a `SKILL-Sxxx` prefix or an `Lxxx` band, mirroring the reserved `L2xx` for user-authored rules, design F11).

---

## 3. Architecture (targets touched)

```
skillet (executable, .Cxx)   LintCommand: discover skills → assemble SkillSource → lint → render
  → ProjectKit         reads SKILL.md text + evals.json bytes per skill (I/O)
  → ConfigYAML (.Cxx)  parseFrontmatter(SKILL.md) → (SkillFrontmatter, body) ; loadConfig → SkilletConfig.lint
  → LintKit  (pure)    Linter.lint(SkillSource, LintConfig) → [Diagnostic]      L001 · L003 · L009
      → EDDCore
  → EDDCore  (pure)    SkillFrontmatter · Diagnostic · LintReport · SkilletConfig.lint   (EvalsFile codec consumed from F8)
  → RenderKit          diagnostics table (TTY)
```

**Interop containment (mirrors F6):** YAML stays in `ConfigYAML` (frontmatter parse). `LintKit` is **pure** — its rules take an already-parsed `SkillSource`, so it never imports `ConfigYAML` and stays interop-free + isolated-testable. The executable (already a `.Cxx` leaf) does the thin assembly (read → parse → decode → `SkillSource`), like F6's `ConfigSupport`. **No new package dependency** — `evals.json` uses Foundation `Codable`.

---

## 4. Detailed design

### 4.1 EDDCore (pure)
- **`EvalsFile`** — **provided by F8** ([Specs/006](../006-frozen-boundary-codecs/plan.md)), *not built here*. F4 calls `EvalsFile.caseCount` for `L009`. (F8 reads skill-creator 2.0 `{skill_name, evals:[…]}` *and* the legacy bare array — **not** a `cases` wrapper, which is ungrounded — holding the doc raw for faithful round-trips.)
- **`SkillFrontmatter`** — `name`, `description`, and a forward-compatible bag; pure (`ConfigYAML` produces it).
- **`Diagnostic`** — `id` (`SKILL-Lxxx`), `tier` (`error`/`warn`), `message`, `fixHint`, `skill`, optional `location`. **`LintReport`** (`SchemaIdentified` = `skillet.lint/1`): `diagnostics[]` + `errors`/`warnings` counts.
- **`SkilletConfig.lint`** — `disable: [String]`, `bodyWarnLines: Int = 500`, `bodyErrorLines: Int = 1000` (snake_case CodingKeys to match `skillet.yaml`).

### 4.2 ConfigYAML (`.Cxx`)
- `parseFrontmatter(_ markdown: String) throws -> (frontmatter: SkillFrontmatter, body: String)` — split the leading `---…---` block, decode its YAML (so folded/block scalars are resolved for `L001`'s "after folding"), return the remaining body text. **Malformed input is data, not a crash:** absent frontmatter, an unterminated `---` block, or YAML that fails to decode resolves to a typed `FrontmatterError` (not an uncaught throw); `LintCommand` maps it to an **error-tier `SKILL-L001`** diagnostic ("frontmatter missing or unparseable") and skips the length check, so a hostile or garbled skill still lints to a clean exit `1`, not a stack trace. Full key-level conformance (duplicate keys, allowed-keys) lands in the Phase 2 lint catalog (F20). *(Skill-Lab covers this via its* Valid Frontmatter */* YAML Anomalies *checks; F4 only needs to fail safe.)*

### 4.3 LintKit (pure)
- `SkillSource` (pure input): `name`, `frontmatter: SkillFrontmatter?` (nil = missing/unparseable → L001), `body: String`, `evals: EvalsFile?` + `evalsPresent: Bool` (present-but-nil = unparseable → L009).
- `Linter.lint(_ source: SkillSource, config: SkilletConfig.Lint) -> [Diagnostic]` — runs the three rules, skips any id in `config.disable`:
  - **L001** description length `> 1024` → error — *length* = **Unicode code-point count** (`unicodeScalars.count`) of the YAML-folded value after trimming whitespace, **matching Anthropic's canonical `len(description.strip()) > 1024`** (`skill-creator/scripts/quick_validate.py:82`). Not `String.count` (grapheme clusters), which combining / zero-width padding can slip under 1024; raw code-point counting already defeats that, and NFC would only *lower* the count and diverge from the canonical gate. Locked by a unicode fixture; the unicode-*obfuscation* rule itself is F12.
  - **L003** body lines excluding the frontmatter block and fenced ```` ``` ```` code blocks: `> bodyErrorLines` → error, else `> bodyWarnLines` → warn.
  - **L009** `evals == nil` → error; `evals.caseCount < 3` → warn.
  - Each diagnostic carries a fix-hint (e.g. L001 → "tighten the description to ≤1024 chars or extract detail to references/").

### 4.4 executable + RenderKit
- **`LintCommand`** (`skillet lint [<skill>...]`): discover skills (ProjectKit, honoring `-C`), assemble each `SkillSource`, run `Linter`, collect a `LintReport`. Exit **`1`** if any `error` diagnostic (§5.4 measured-failure); else `0`. Skills are selected **by name** (unique under `skills_root`; not by path, so it's `-C`/cwd-independent and deterministic), de-duplicated + sorted; an unknown name → usage error (exit `2`) listing the available names.
- **Output:** TTY diagnostics table via `RenderKit` (id · tier · skill · message · fix-hint); the **global `--json`** emits `LintReport` (`skillet.lint/1`). `--format` + SARIF arrive in Phase 2.
- Ends (TTY) by suggesting the next command (`skillet run` / `skillet next` once they exist; until then a generic hint).

### 4.5 Config / exemptions
`LintCommand` loads `skillet.yaml` through the existing F6 config-link (`ConfigYAML` → `SkilletConfig.lint`); `disable` suppresses rule ids and the thresholds feed `L003`. Per-skill overlay precedence → F24 (Phase 2 config ergonomics).

---

## 5. Test plan (TDD)
- **EDDCoreTests**: `SkilletConfig.lint` decode; `LintReport` `--json` schema (`skillet.lint/1`). *(The `EvalsFile` golden + round-trip + `caseCount` are already covered by F8's tests.)*
- **ConfigYAMLTests**: `parseFrontmatter` — folded/block-scalar description; frontmatter/body split; no-frontmatter case; **malformed / unterminated frontmatter and undecodable YAML → a typed `FrontmatterError` (no uncaught throw)**.
- **LintKitTests** (fixtures, pure): L001 (over-long vs ok; **a Unicode boundary fixture — combining marks, ≤1024 grapheme clusters but >1024 code points → must flag**, pinning code-point (not grapheme) counting; **absent/unparseable frontmatter → L001 error**), L003 (≤500 ok · >500 warn · >1000 error · code/frontmatter excluded), L009 (missing → error · <3 → warn · ≥3 → ok); `disable` exemption; custom thresholds.
- **ProjectKitTests**: skill-source reader (present/absent `evals.json`).
- **IntegrationTests**: `skillet lint` on a bad-fixture repo → exit `1` + ids present; on a clean repo → exit `0`; `--json` carries `skillet.lint/1`; unknown skill → exit `2`. **DocsTests**: add the `lint` claim.

---

## 6. Task breakdown (ordered)
1. `EDDCore`: `SkillFrontmatter` + `Diagnostic`/`LintReport` + `SkilletConfig.lint`. *(tests first; `EvalsFile` already ships in F8 — F4 only consumes `caseCount`.)*
2. `ConfigYAML`: `parseFrontmatter`. *(tests)*
3. `LintKit` (new target + test target): `SkillSource` + `Linter` + L001/L003/L009 + disable/thresholds. *(tests first)*
4. `ProjectKit`: skill-source reader. *(tests)*
5. executable: `LintCommand` (assembly + exit mapping + `--json`); `RenderKit` diagnostics table; register the subcommand.
6. `IntegrationTests` + `DocsTests`.
7. Verify `swift build` + `swift test`; smoke `skillet lint` on a fixture. Docs sync: AGENTS (commands + LintKit), README (usage + loop note), roadmap F4 → DONE, this plan → IMPLEMENTED, `Specs/README`.

---

## 7. Risks & assumptions
- **`evals.json` shape — owned by F8 (resolved).** F8 reads the skill-creator 2.0 object (`{skill_name, evals:[…]}`) *and* the legacy bare array; **`cases` is *not* a container key** (ungrounded — not in 2.0 nor any sampled file). F4 must **not** re-introduce a `cases` reader or rebuild the codec — it only calls `EvalsFile.caseCount`.
- **"after YAML folding" (L001)** needs a real YAML parse of the frontmatter → `ConfigYAML` (not a regex on the raw `description:` line), **and a pinned counting unit — Unicode code points** (`unicodeScalars.count`, no normalization, after `.strip()`), **matching Anthropic's `len(description.strip())`** (`quick_validate.py:82`) so `skillet lint` faithfully predicts Anthropic's gate. Code-point counting already stops combining-mark / zero-width padding from slipping under 1024 (the gap grapheme-cluster `String.count` leaves); NFC would only lower the count and diverge. Locked by a unicode fixture. The unicode-*obfuscation* security rule is F12; the *count* is frozen-ish behavior to fix now.
- **Malformed / adversarial frontmatter must fail safe** — absent, unterminated, or undecodable YAML frontmatter resolves to a typed error → an error-tier `SKILL-L001` diagnostic, never an uncaught throw. F4 degrades gracefully; full key-level conformance is the Phase 2 lint catalog (F20).
- **L003 body definition** — "excluding frontmatter + code": strip the `---` block and fenced code blocks, count remaining lines. Definition pinned by fixtures; refine if it proves noisy.
- **LintKit purity** — rules take a parsed `SkillSource`; no I/O/YAML keeps it interop-free + isolated-testable (the load-bearing layering choice).

## 8. Definition of done
`L001`/`L003`/`L009` flag fixtures with stable ids + fix-hints; `skillet lint` exits `1` on any error-tier finding (`0` clean, `2` bad usage); `--json` emits `skillet.lint/1`; `[lint].disable` + thresholds honored; `evals.json` golden green; `LintKit` pure/interop-free; `swift build` + `swift test` green; docs synced.

---

## 9. As-built (2026-06-25)

Implemented per plan; **130 tests green** (97 → +25 feature, +8 review-hardening). Notes:
- **L001 counts Unicode code points** (`description.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count > 1024`), **not** NFC-normalized scalars — decided this turn to faithfully predict Anthropic's canonical `len(description.strip()) > 1024` (`skill-creator/scripts/quick_validate.py:82`). Raw code points already defeat the combining / zero-width padding that grapheme counting allows; NFC would only *lower* the count and diverge. §4.3/§5/§7 updated to match.
- New pure target **`LintKit`** (`SkillSource` + `Linter`), depends on `EDDCore` only — interop-free, as planned.
- **`ConfigYAML.parseFrontmatter`** folds scalars and returns a typed `FrontmatterError` (`.missing`/`.unterminated`/`.undecodable`); the command maps any parse failure to a `nil` frontmatter → error-tier L001 (fail-safe, never an uncaught throw).
- **`ProjectKit.SkillReader`** reads `SKILL.md` + `evaluations/evals.json` bytes; the executable assembles the `SkillSource` (parse + `EvalsFile` decode), keeping `LintKit` pure.
- The `skillet.yaml` `[lint]` block already existed in the F2 template; F4 added only the `SkilletConfig.Lint` model (`decodeIfPresent` defaults 500/1000, snake_case keys).
- **L003 line counting** treats a terminal newline as a terminator (so exactly N content lines counts as N, not N+1) and matches fenced blocks per CommonMark — the closer must repeat the opener's marker char at ≥ its run length with nothing trailing — so mixed `~~~`/``` markers and fence-like content lines don't mis-toggle. (Review hardening, 2026-06-25.)
- **L009 distinguishes absent vs. unparseable** `evals.json` (both error-tier) via `SkillSource.evalsPresent`: a present-but-invalid file reports "exists but is not valid JSON", not "no evals.json found". A frontmatter parse failure feeds an **empty** body to L003 (L001 already errors), so a malformed skill doesn't double-fire. Deeper artifact validation (exit 4) is still out of F4 scope.
- **Selection is by name, not path** (review 2026-06-26): `skillet lint <name>…` matches discovered skill-directory names (unique under `skills_root`), de-duplicated + sorted for deterministic output; an unknown name's error lists the available ones. Chosen over fixing path-vs-`-C` resolution because a skill is a named entity (cf. `cargo -p`, `kubectl`, and skillet's own `harness info <id>`), which removes the cwd/`-C` ambiguity by construction and makes `--json` order stable; path support stays addable later (additive) if an out-of-tree use case appears.
- **Frontmatter parse-failure detail** stays a single generic L001 message in F4; the typed `FrontmatterError` (`.missing`/`.unterminated`/`.undecodable`) lives in `ConfigYAML` and can't cross into pure `LintKit` without breaking interop containment, so granular frontmatter diagnostics land in the Phase 2 lint catalog (F20); `doctor` (F3) surfaces them as error-tier lint once F20 ships.
- **CRLF** input is normalized in `FrontmatterParser` so scalars/body don't carry stray `\r`.
