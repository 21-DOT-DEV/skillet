# Plan — Phase 2 · F17: deterministic scorers → SARIF (`skillet score`)

| | |
|---|---|
| **Feature** | F17 — free, model-free checks over a skill's produced text that emit standard findings JSON (SARIF 2.1.0) — the deterministic-first signal (CLI: `skillet score <path>`) |
| **Phase** | 2 — Trustworthy Measurement & Static Gates ([Roadmap/phase-2-measurement-static-gates.md](../../Roadmap/phase-2-measurement-static-gates.md), F17) |
| **Status** | IMPLEMENTED (2026-07-09) — plan converged over 11 review rounds; **shipped + green (390 tests)**: ProjectKit `SafeFile`, EDDCore `SarifDocument`/`ScoreReport`, ScoreKit (S001–S007/S000), `skillet score --format tty\|json\|sarif`, RenderKit table, docs ripple |
| **Last updated** | 2026-07-09 |
| **Builds on** | EDDCore (`SarifLog` tolerant *reader*; `SchemaIdentified`/`LintReport`; `JSONValue`; `SkilletConfig`; `Diagnostic`/`SKILL-Lxxx`; `ExitCode`; §5.1 discovery; `EDDCore/JSON.swift:40` snake_case encoder — the **house `--json` convention**, §4.5); **ProjectKit** (EDDCore-only filesystem home — the confinement + safe-read helpers **move** here, §3.2); RenderKit (`Renderer` `.human`/`.json`); F8 golden discipline; the F16 confinement + `decodeText`/`boundedRead` discipline |
| **Adapted from** (concepts, **not** a type port) | `~/Developer/skills/Sources/SkillEvalKit/Scoring/`: **measurement concepts + word-lists** — `Code/AIVocabulary.swift` (incl. `knowledgeCutoffPhrases:127`), `Code/AISlopScorers.swift` counting/regex (incl. `RuleOfThreeMatcher` + `isReferentialItem`/`isTechnicalItem` :449-475), each check's `ScorerScale(min,max,good)`. The **`Scorer` protocol / `ScorerContext` / result model / `ScorerRegistry` are redesigned** for per-occurrence SARIF over a folder (the predecessor is single-value, docc-locked, session+diff-built). **Every generalized check (S001–S006) needs its own calibration fixture.** NOT carried over: `.judge`, `Scorecard`/pass-fail, taxonomy/routing/suggest, the two markdown/tone checks, citations. |
| **Authoritative refs** | design §4, §5.1 (discovery), §5.2 (`scorers.*` config + wordlists), §5.4 (exit codes), §5.5 (`--json`/no-auto-switch/progress/next-step), §6.2 (`skillet score`), §7.2 (SARIF frozen format), §8 (contradiction — the F34 *consumer*), §11 (ScoreKit); constitution I–VI, §constitution:381; P8, D5, D6 |
| **Decisions** | **D-1 Input** = a folder path (dir recursive, or a single file), with a **file-selection policy** (§3.2). **D-2 Checks** = five word/punctuation logics generalized + re-calibrated (S001–S005), **plus** experimental **default-off** S006 "not X, but Y" (§4.7), **plus** S007 sarif-validity + S000 file-unreadable; two markdown/tone checks defer (Option C, §4.7). **D-3 Output** = per-occurrence findings, dual **`level`+`rank`** (§4.2), `level` grounded on the predecessor's universal cuts (`ScorecardFeedback:116-118`: ≥0.5 clean, 0.4–0.5 `warning`, <0.4 `error`). **D-4 Data** = word-lists in-code; a new `SkilletConfig.Scorers` (`vendored_prefixes`, `vocab.exempt`, `disable`, `enable` — §3.1) from repo `skillet.yaml` + defaults (no user layer until F24). **D-5 Surface** = one `--format tty\|json\|sarif`; `--json` = shorthand for `--format json` yielding to explicit `--format`; **no TTY auto-switch — human default** (§3.3). |
| **Assumptions** | A1: new **`ScoreKit`** — deps **`EDDCore` + `ProjectKit`** — + **`ScoreKitTests`**. A2: SARIF emitter **emit-only**, **dedicated camelCase encoder**; `ScoreReport`/`--format json` follows the **house snake_case** convention (§4.5). A3: **`score` is a reporter, not a gate (R8 · C1)** — exit **0 even when scorers fire** (the signal feeds triage F33 /
next / contradiction F34; deliberately unlike `lint`'s exit-1 error-tier gate, so `skillet score` won't fail a
build); **2** usage / **3** environment (bad `<path>`) / **4** corrupt *config* artifact (§3.3). A4: **no new dependency** ("valid SARIF" = structural golden checks). A5: additive/greenfield. |
| **Workflow** | Standalone plan (spec-kit workflow intentionally skipped) |

---

## 1. Goal & success criteria

Ship the **deterministic-first signal**: `skillet score <path>` runs free, model-free, no-network checks
over a skill's produced text and emits standard findings JSON (SARIF 2.1.0) — the cheap, reproducible
layer beneath the paid judge.

**F17 deliverable:** `skillet score <path> --format sarif` emits **valid SARIF 2.1.0** on stdout (structural
conformance pinned by golden fixtures — no external validator, §4.6); **no model, no network**; also
`--format tty` (human table, default) and `--format json` (`ScoreReport`/`skillet.score/1`, §4.5).

> **Roadmap reconciliation (R1 #5).** The metric "`score <bundle>`" becomes `score <path>` with a
> `<bundle>` (Phase 3) note; design §6.2's `skillet score <bundle|path>` → `<path>` too (§6).

## 2. Scope

### In scope
- **EDDCore**: the typed **SARIF 2.1.0 emitter** (emit-only, camelCase, **incl. `tool.driver.{name,version,
  rules}`** — §4.6) + a **`ScoreReport`** type (`SchemaIdentified`, `skillet.score/1`, snake_case — §4.5),
  both frozen + golden-tested; the tolerant `SarifLog` reader untouched. A new **`SkilletConfig.Scorers`** (§3.1).
- **ProjectKit**: the **moved** shared confinement predicates + safe bounded UTF-8 read (§3.2) — the single
  home for this boundary; RunKit/HarnessKit re-import from here (no cycle — §3.2).
- **ScoreKit** (new, `EDDCore` + `ProjectKit`): the redesigned `Scorer` protocol, a general folder-scoped
  `ScorerContext`, the finding model, `ScorerRegistry`, generalized + re-calibrated logic, in-code
  word-lists, exemption/enable/disable, the ported `ScorerScale`.
- **Checks** (§4.1): S001–S005 generalized, S006 (experimental, **default-off**), S007, S000.
- **executable**: `skillet score <path> [--format tty|json|sarif]` (§3.3); exits 0/2/3/4.
- **RenderKit**: a `score` table + a next-step + a progress note (§3.3). **Tests** (§5). **Docs/Package** (§6).

### Out of scope (→ owner)
- Two markdown/tone checks + citations → bring-your-own-check (Option C, §4.7). `.judge` → later.
  Scorecard/rollup → triage F33 / report F23. Contradiction → F34. External word-list files + `migrate
  knobs` → later. User-config precedence → F24. Bundle input + role-rename + corrupt-manifest exit → capture.
  drift/fixtures-verify → F35/F36/F22. **lint's `--format` surface → a separate follow-up (R3 #13).**

## 3. Architecture

`EDDCore` (emitter + `ScoreReport` + config — pure) ; `ProjectKit` (confinement + safe-read — effectful,
EDDCore-only) ← `ScoreKit` ← `skillet` ; `RenderKit`. One **new kit** (`ScoreKit` = `EDDCore` + `ProjectKit`)
+ `ScoreKitTests`; **no new dependency**. EDDCore owns the pure emission inputs; ScoreKit maps onto them.

### 3.1 Config + the `scorers` section (R2 #7; R3 #7; R4 nb)

Discovery via the existing `loadConfigWithOrigin` (upward walk → `--config` / repo `skillet.yaml` /
defaults; **no user layer until F24** — a known gap vs design §5.2, not a new design change, R5 nb; a
**corrupt** explicit/repo config → exit 4, §3.3). Outside a repo → defaults. The per-skill overlay is not
consulted (directory-scoped). Single layer → repo **replaces** defaults. **`SkilletConfig` currently *ignores*
a `scorers:` block on decode (the template already writes one) — F17 adds the model so it is read.**
**Init ripple (R11 · B3):** adding `public var scorers: Scorers?` requires updating `SkilletConfig`'s explicit
memberwise `init(project:harness:lint:runs:judge:)` → `…judge:scorers:)` (a new stored property isn't
auto-added to an explicit init). The param is defaulted (`scorers: Scorers? = nil`) so it's additive — and a
repo grep finds **no direct `SkilletConfig(...)` call sites** (construction is via `Codable` decode), so the
ripple is the initializer alone; tracked so it isn't missed.
```
scorers:                       # SkilletConfig.Scorers (optional; snake_case keys; absent = defaults)
  vendored_prefixes: [String]  # folder names to skip (gitignore-style, R8/B1 — see below). BUILT-IN DEFAULT
                               #   [] (score everything); `skillet init`'s template pre-writes
                               #   ["Vendored/","Generated/"] as a suggestion.
  vocab: { exempt: [String] }  # domain terms to NOT flag; default []. See the vocab.exempt note below.
  disable: [String]            # rule-ids OFF among default-on scorers (mirrors [lint].disable)
  enable:  [String]            # rule-ids ON among experimental/default-off scorers (S006)
```
**`disable` overrides `enable`** if a rule-id appears in both (safe default: an explicit off wins).
**Partial-block decode (R6 nb):** `Scorers` decodes like `Lint`/`Runs` — **each key defaults individually**,
so a repo file with only `scorers.disable:` keeps the built-in `vocab`/`vendored_prefixes`/`enable` defaults
rather than zeroing them (via optional properties / an `init(from:)` that fills missing keys).

**`vendored_prefixes` matching (R8 · B1 · decided — gitignore-style):** a candidate file is skipped iff **any
whole path segment** of its path *relative to `<path>`* equals an entry (trailing slash stripped) — the
[gitignore](https://git-scm.com/docs/gitignore) folder-name-at-any-depth model that ESLint and most tools
follow, and the mental model developers already have. So `Vendored/` skips `Vendored/x.md` **and**
`sub/Vendored/x.md`, but **never** `VendoredFoo.swift` (a different segment — the trailing slash is
conventional, *not* the guard, because whole-segment matching already prevents partial-word hits).
**Case-sensitive** (gitignore default; Linux paths). **No wildcards/negation/leading-slash anchoring in F17**
(a documented future extension). The setting's "prefix" name is legacy (the predecessor's ignore file);
entries match folder segments — noted so the name doesn't mislead.

**`vocab.exempt` semantics (R8 · R3):** an exempt phrase **removes matching entries from the configured slop
word-list *before* scoring** (case-insensitive, whole-phrase — mirrors the predecessor, AISlopScorers.swift:54-55:
the exempt set is built at :54, the word-list `.filter` that drops exempt entries is :55; applied to **both**
S001 `combined` and S002 `puffery` — :54/:79, R10 #8);
it does **not** mask or rewrite occurrences in the source text. So exempting "delve" means the scorer never
counts "delve"; it does not alter what the file says. **Matching is whole-list-entry, exact (lowercased), not
substring (R11 · B1):** `exempt.contains($0.lowercased())` compares against each *word-list phrase*, so
`exempt: ["tapestry"]` removes the list entry `"tapestry"` but does **not** suppress a list entry
`"rich tapestry"` — to exempt that, write the exact entry `["rich tapestry"]`.

### 3.2 Filesystem: selection, safe read, confinement, char unit (R1 #3; R3 #4/#11/#12; R4 #4/#11 · Principle VI)

**File-selection policy (R4 #4).** Recurse `<path>` (or take the one file). A path is a **candidate** iff it
is a **regular file** (symlinks/FIFOs/sockets/devices excluded — confinement), is **not** a dot-entry
(`.git`, `.build`, hidden), and does **not** match a `vendored_prefixes` prefix (checked **before read**).
**No extension filter** — the caller points at a produced-text directory; non-text bytes are handled by the read.

**Confinement + safe read (ProjectKit — the moved home; R3 #4, R6 B2).** `lstat` + never follow symlinks +
never traverse above `<path>`. A new `SafeFile` enum in ProjectKit gathers the boundary. **Moved vs stays:**

| helper (signature) | today | action | callers after |
|---|---|---|---|
| `isSymlink(_: URL) -> Bool` | **one impl** `SkillBundleRules:17`, **re-exported** by `WorkspaceManager:78` | move impl → ProjectKit; both keep thin re-exports | SkillBundleRules, WorkspaceManager, **SkillBundleAudit, TriggerEvalSupport, RunCommand:462, DoctorCommand:241**, ScoreKit (R10 #2 — more callers than first listed; all keep working via the wrappers) |
| `isHidden(_ name: String) -> Bool` | `SkillBundleRules:22` | move | SkillBundleRules, **SkillBundleAudit**, WorkspaceManager, ScoreKit |
| `noSymlink(at: URL, under: URL) -> Bool` | `WorkspaceManager:67` | move | WorkspaceManager, ScoreKit |
| `firstSymlink(in:)` / `firstSymlinkOnPath(from:to:) -> URL?` | `WorkspaceManager:84/:95` | move | WorkspaceManager, ScoreKit |
| `decodeText(_ data: Data, truncated: Bool) -> String?` | `WorkspaceManager:382` | move | WorkspaceManager, ScoreKit |
| `boundedRead(_ url: URL, cap: Int) -> (data: Data, fullSize: Int)?` | `WorkspaceManager:422` (`private`→`public static`) | move | WorkspaceManager, ScoreKit |
| bundle-staging policy (`resolveFixture`, audit) | `SkillBundleRules`/`SkillBundleAudit` | **stays** (calls the moved predicates) | HarnessKit |

**Package.swift:** ProjectKit still imports only Foundation + EDDCore, so adding `ProjectKit` to `HarnessKit`
and `RunKit` (and `ScoreKit`) is **downward — no cycle**. `isHidden` is confirmed shared by all three current
sites (SkillBundleRules/SkillBundleAudit/WorkspaceManager), so it moves rather than duplicates. **Move ripple
(R8 · R1; corrected R10 #1):** `SkillBundleRules` becomes a thin policy wrapper calling ProjectKit. The only
test that names moved helpers directly is **`Tests/RunKitTests/RunnerTests.swift`** (`firstSymlink`/
`firstSymlinkOnPath`, :124/:128/:204) — it re-points at ProjectKit. `StagingParityTests` exercises
`WorkspaceManager.prepare`/`.destroy` + `SkillBundleAudit.audit` (which **stay**), so it needs no change
beyond staying green. The moved helpers use only `FileManager`/`FileHandle`, so
**ProjectKit stays Foundation+EDDCore-only — re-verify no new import creeps in after the move.**

**Build order (R9 · B3 — the move is a *prerequisite*, sequenced explicitly):**
1. **Move** `isSymlink`/`isHidden`/`noSymlink`/`firstSymlink*`/`decodeText`/`boundedRead` into ProjectKit;
   turn `SkillBundleRules` into a thin wrapper; update `Package.swift` (`HarnessKit`/`RunKit` → `ProjectKit`).
2. **HARD GATE (R11 · B4): the full existing suite must be green on CI before any scorer code lands** —
   `RunnerTests` re-points at ProjectKit's helpers; `StagingParityTests`/`HarnessKitTests` pass **unchanged**
   (they use the staying `prepare`/`destroy`/`audit` APIs, not the moved helpers, R10 #1). This is a separate,
   reviewable refactor commit with **no `score` code**.
3. **Only then build `ScoreKit`** (emitter + `ScoreReport` + scorers + `score`) on the now-shared helpers.
   Landing 1–2 first keeps the DAG refactor reviewable in isolation and de-risks it.

**Per-candidate read + disposition (R4 #11; R7 #3):** safe bounded UTF-8 read, **1 MiB cap**. **A `.sarif`/
`.sarif.json` name is dispositive** — detected by **exact suffix** (`path.hasSuffix(".sarif") ||
path.hasSuffix(".sarif.json")`, R9 risk — not substring) — such a file is a findings artifact, so a
read/parse failure is a *validity finding*, not a silent skip:

| candidate | within 1 MiB cap? | disposition |
|---|---|---|
| `.sarif`/`.sarif.json` | yes | route to **S007** only (excluded from S001–S006): valid JSON **and** `version=="2.1.0"` **and** `runs` present ⇒ no finding; **invalid JSON, non-UTF-8, missing `version`/`runs`, or `version`≠"2.1.0"** ⇒ `S007` `error` (R7 #3 — for a `.sarif`, non-UTF-8 *is* malformed, **not** a skip) |
| `.sarif`/`.sarif.json` | **no (> cap)** | `S000` note — oversized, **not decoded**, so not validated (R6 B3) |
| other file | yes, UTF-8 text | scored by S001–S006 (§4.8) |
| other file | yes, binary / non-UTF-8 | **silently skipped** (counted in `summary.files_skipped`; **no** finding — surfacing every non-text file in a mixed dir would be noise) |
| any file | unreadable (permissions) | `S000` note |
| any file | oversized (> cap) | `S000` note — **no `decodeText` on the truncated prefix** (R6 B3) |

**Never crashes.**

**Character unit (R3 #12):** all region offsets/columns count **Unicode scalars** (`String.unicodeScalars`),
per the SARIF spec's "a character = a Unicode code point"; documented, multi-byte golden-locked (UTF-16
caveat noted, not adopted).

### 3.3 CLI, precedence, default, exit codes (R1 #4; R3 #3/#13; R4 #7)

`skillet score <path> [--format tty|json|sarif]` — plumbing. **One selector**; global `--json` = shorthand
for `--format json` yielding to an explicit `--format`:

| invocation | result | via |
|---|---|---|
| *(none)* — TTY **or piped** | `tty` — human table (**default; no auto-switch**) | `Renderer(.human)` |
| `--json` | `json` — `ScoreReport`/`skillet.score/1` | `Renderer(.json)` |
| `--format sarif` | SARIF 2.1.0 | **direct emitter — bypasses `Renderer`** |
| `--json --format sarif` | **sarif** (explicit wins) | — |

No TTY auto-switch (house §5.5 + clig.dev + Docker's auto-switch-is-annoying report; two machine formats →
auto-pick is arbitrary). Because piped runs still default to the table, the command's **`--help` discussion
shows a piped machine example** — e.g. `skillet score . --format sarif > out.sarif` (R11 · risk) — so script
users know to opt in. `score` lands `--format` first; `lint` follows separately (R3 #13). **Wiring (R6 nb; R8 C2; R9 · B2 — coexistence proven, not a risk):** the inherited global `--json`
(`@OptionGroup GlobalOptions`) and a **command-local `@Option var format`** parse independently — **already the
established pattern** (`RunCommand` combines `GlobalOptions.--json` with local `--judge`/`--axis`/`--runs`, so
distinct flag names never conflict at parse time). Precedence (`--format` wins) is **resolved in `run()`
against `options.json` in code**, not via ArgumentParser conflict handling. `json` (or `--json`) builds
`Renderer(.json)`; `tty` builds `Renderer(.human)`; **`sarif` bypasses `Renderer` entirely** (the emitter
writes straight to stdout, since `Renderer` only models `.human`/`.json`). **TTY extras
(§5.5, R4 nb):** a one-line `scoring N files…` progress note (stderr; suppressed under `--json`/`--format
sarif`/pipes) and a **next-step suggestion** after the human table, built with the **same registration-filter mechanism as
`LintCommand.nextSteps()`** — suggest the loop steps that exist today, else `skillet --help` (R7 #1 —
**correction:** lint's filter is by *registration*, **not** free-vs-paid, so the earlier "free-only mirror"
framing was a false claim about current code; a next-step *suggestion* is not a spend, and `run` confirms
before spending, so suggesting it stays P9-safe).

**Exit codes** (§5.4): `0` report (even with findings — D6) · `2` usage · `3` environment (`<path>`
non-existent/unreadable) · **`4` a corrupt explicit/repo `skillet.yaml`** (via `loadConfigWithOrigin`,
Principle III — R4 #7). **A malformed scored `.sarif` under `<path>` is a *finding* (S007), not exit 4.**

## 4. Output contract

### 4.1 Rule-ids, levels, triggers (R1 #9; R3 #9; R4 #1)

| ruleId | kebab name | kind | level | trigger |
|---|---|---|---|---|
| `SKILL-S001` | `slop-vocabulary` | density | §4.2 band | per slop-word match |
| `SKILL-S002` | `puffery` | density | §4.2 band | per puffery match |
| `SKILL-S003` | `em-dash` | density | §4.2 band | per em-dash occurrence (severity per-file) |
| `SKILL-S004` | `rule-of-three` | density | §4.2 band | per non-referential/non-technical triple (§4.8) |
| `SKILL-S005` | `knowledge-cutoff` | count | §4.2 band | per cutoff-phrase mention (§4.8) |
| `SKILL-S006` | `not-x-but-y` | density (**experimental, default-off**) | §4.2 band | per contrast construction (§4.7) |
| `SKILL-S007` | `sarif-validity` | categorical | **`error`** | a `.sarif`/`.sarif.json` that is invalid JSON, missing `version`/`runs`, or whose `version` ≠ `"2.1.0"` (R5 nb) |
| `SKILL-S000` | `file-unreadable` | categorical | **`note`** | a regular file that is unreadable (permissions) or exceeds the 1 MiB cap (§3.2) |

### 4.2 Severity: dual `level` + `rank` (R2 #6; R3 #2; R4 #1)

Raw metric → `ScorerScale.normalizedGoodness` → `[0,1]` goodness (1 = ideal). Per occurrence, from the
**file's** goodness: **`rank` = `round((1 − goodness) × 100)`**; **`level`**: `≥0.5` clean (no finding),
`0.4–0.5` `warning`, `<0.4` `error` (`ScorecardFeedback:116-118`, cited; `note` reserved for S000). Scored
per file; clean files emit nothing. Categorical rules fix `level`, no `rank`.

**`normalizedGoodness` formula (R9 · B1 — ported verbatim from `SkillEvalKit/Scoring/Scorer.swift:57-70`;
ScoreKit must reproduce it exactly so calibration matches):**
```swift
let span = max - min
guard span > 0 else { return 1.0 }                       // degenerate scale ⇒ nothing to judge
let t = Swift.max(0, Swift.min(1, (value - min) / span))
switch good {
case .high:   return t
case .low:    return 1.0 - t
case .target(let target):
    let distance = abs(value - target)
    let maxDistance = Swift.max(target - min, max - target)
    guard maxDistance > 0 else { return 1.0 }
    return 1.0 - Swift.min(1.0, distance / maxDistance)   // S003: value 0, target 1.5, max 10 ⇒ 1 − 1.5/8.5 ≈ 0.82
}
```

**Per-scorer metric / denominator / scale — all verified against source (R4 #1); locked by fixtures:**

| ruleId | raw metric | denominator | `ScorerScale(min,max,good)` | source (scale · denominator) |
|---|---|---|---|---|
| S001 | slop-word hits | per **1000 words** | `(0, 20, .low)` | AISlopScorers.swift **:39** · :57 |
| S002 | puffery hits | per **1000 words** | `(0, 20, .low)` | **:67** · :82 |
| S003 | em-dashes | **per 100 words** ✳ | `(0, 10, .target(1.5))` | **:92** · :105 |
| S004 | non-ref/non-tech triples | per **100 sentences** | `(0, 20, .low)` | **:115** · :128 |
| S005 | cutoff-phrase mentions | **raw count** | `(0, 5, .low)` | **:138** · :159 |
| S006 | contrast constructions | per **1000 words** | *provisional `(0, 15, .low)`* (§4.7) | new |

✳ S003 is per **100** words (`* 100.0` at :105, target ~1.5/100w), not per-1000. Citations (R6 B1): the
**scale** is defined at the bold line, the **denominator/multiplier** at the second — both verified.

**S003 target-scale intent (R8 · R4).** `.target(1.5)` with `max 10` penalizes **over-use**, not absence: a
clean article with **0 em-dashes** normalizes to goodness ≈ **0.82** (≥ 0.5 ⇒ **no finding**); S003 only fires
(goodness < 0.5) above ~5.75/100w. This is the intended ported behavior — a required calibration fixture
proves a 0-em-dash file stays silent so the target scale isn't mistaken for penalizing absence.

### 4.3 SARIF `region` (R1 #7; R3 #12)
`startLine`+`startColumn`+`endLine`+`endColumn` (**1-based**) **and** `charOffset`+`charLength` (**0-based**,
per the SARIF spec), all counting **Unicode scalars** (R5 nb — stated to avoid an off-by-one). **`endColumn`
is the 1-based column immediately *after* the region (R6 nb)**, so for a single-line match `endColumn ==
startColumn + charLength`. Categorical results: `artifactLocation`, no region. **Conversion task (R8 · R2):**
the scorers use `NSRegularExpression`, which returns **UTF-16 `NSRange`s** — a dedicated
`SARIFRegion.from(regexMatch:in:)` converts those to **scalar-counted** `charOffset`/`charLength` and 1-based
line/column, and is unit-tested with **emoji (astral), combining marks, CJK, and CRLF** (easy to get wrong;
§5). §5 asserts `startLine`/`startColumn` + the multi-byte case.

### 4.4 `properties`
`skillet.`-namespaced: `skillet.density` (or `count` for S005), `skillet.denominator`, `skillet.goodness`,
`skillet.scale`. **Encoding (R6 nb):** `properties` is a `[String: JSONValue]` **map with literal dotted
keys**, not a struct — so both encoders emit `skillet.density` verbatim (JSON key-encoding strategies,
incl. the shared `.convertToSnakeCase`, do **not** transform dictionary keys), keeping the key stable across
the camelCase SARIF and snake_case `ScoreReport` outputs; goldens lock it. **`skillet.scale` shape:** `{ min:
Double, max: Double, good: "high"|"low"|"target", target: Double? }` (`target` present only when `good ==
"target"`) — the enum's associated value is lifted to a sibling field so it serializes cleanly in both.

### 4.5 `ScoreReport` / `skillet.score/1` — snake_case (R2 #6; R3 #6; R4 #8)
A new **EDDCore** type mirroring `LintReport` (`SchemaIdentified`), golden-tested. **It follows the house
`--json` convention — snake_case via the shared encoder** (like `skillet.lint/1`), **distinct from the SARIF
output's camelCase** (§4.6). The two casings are intentional: SARIF's is spec-mandated, `skillet.score/1`'s
is house-consistent.
```
ScoreReport { schema = "skillet.score/1"
  findings: [ { rule_id, level, rank?, message,
                location{ file, start_line, start_column, end_line, end_column, char_offset, char_length },
                properties } ]                      // B2: density findings (S001–S006) carry ALL location
                                                    //   fields. Categorical S000/S007: location is EXACTLY
                                                    //   { file } — no start/end/char fields at all (R7 #2),
                                                    //   mirroring SARIF artifactLocation with no `region`.
  summary:  { per_rule: { <rule_id>: <Int> },       // B3: a JSON object ([String: Int]), not an array
              files_scored: Int, files_skipped: Int, files_unreadable: Int } }
```
> Illustrative only — `SkilletJSON.encoder()` uses `.sortedKeys`, so `schema` is **not** first in real output;
> golden tests lock the sorted-key bytes, not this layout (R5 nb).
> **Compile-time shape (R9 risk):** `location` is a **sum type** — `.file(String)` for categorical S000/S007
> vs `.region(file, startLine, …, charLength)` for density findings — so a categorical finding **cannot** carry
> region fields (the SARIF "`artifactLocation` with no `region`" rule is enforced by the type, not by convention).
> **Custom `Codable` required (R11 · B2):** a Swift enum does **not** synthesize to the documented *flat* object
> (`location{ file, start_line?, … }`) — the default encoding emits a case-tagged shape. `Location` needs a
> hand-written `Codable` that flattens both cases into one object: `file` always present; `start_line`/…/
> `char_length` present only for `.region`. This is the sole part of the frozen `skillet.score/1` schema whose
> encoding isn't mechanical — a golden locks the exact bytes for both cases.

### 4.6 Emitter: casing, `$schema`, `tool.driver.rules`, "schema-validated" (R1 #8; R2 #3/#7; R4 #6)
- **Distinct type name (R9 risk):** the typed emit-only model is **`SarifDocument`** (+ a `SarifEmitter`
  serializer), **not** reusing `SarifLog` — the existing raw/tolerant *reader* stays under that name to avoid
  confusion between the reader and the writer.
- **Dedicated camelCase encoder** for SARIF — **`SarifDocument` must not use `SkilletJSON.encoder()`**
  (`JSON.swift:35-43`, snake_case), R11 risk; goldens lock `startLine`/`ruleId`/`$schema`/`tool.driver.rules`
  literally.
- **`tool.driver` carries `name` ("skillet"), `version`, and a `rules[]`** — a **static catalog of the full
  rule set S000–S007** (`id`, `name`, `shortDescription`), listed **regardless of whether a rule fired or is
  disabled** (B4 — the SARIF-idiomatic "advertise your catalog" model; S006's default-off state rides in its
  rule `properties`). This keeps golden tests stable when S006 is off; golden-asserted.
- **`$schema`** = `https://json.schemastore.org/sarif-2.1.0.json` (R8 · S1 · decided — the community mirror the
  repo's reader test already uses; the value is advisory since consumers validate *structure*, not by fetching
  the URL). A code comment cites the **OASIS canonical** schema URL as the authoritative provenance. **Emit-only**;
  `SarifLog` stays the reader.
  **"Schema-validated" = structural golden checks**, not an external validator.

### 4.7 S006: matching rule, default-off, Option C (R1 #12; R3 #10; R4 #3 · Principle II)
**Matching rule (designed — R4 #3; EQ-Bench's contrast family, regex-only since a POS-tagger would be a new
dependency).** Case-insensitive; each match is **one intra-sentence span** (no `.?!` sentence-ender inside;
distance-capped ≤ ~60 chars), located at the negator, covering the three families:
1. `not (just|only|merely|simply) … but …`  2. `(it|that|this|they|we|you)'s not …, (it's|but) …`  (the
"it's not X, it's Y" form)  3. `less about … more about …`. Metric = matches per 1000 words; **provisional
scale `(0, 15, .low)`**, both pinned by the calibration fixture. Because it is regex-only (no POS stage) and
uncalibrated, S006 ships **default-OFF**, opted in via `scorers.enable: ["SKILL-S006"]`; its calibration
fixture (legit `not X, but Y` prose must not over-flag; sloppy repetition must) is a **hard completion
gate**; default-on is deferred until evidence. **Option C future revisit:** the deferred markdown/tone checks
can later ship under this same opt-in tier.

### 4.8 Generic matching for S004 / S005 + `.sarif` exclusion (R3 #8; R4 #2/#5)
- **S004 rule-of-three** — port `RuleOfThreeMatcher`, keeping its two skips (a triple `X, Y, and Z` is **not**
  counted when **≥2 items are referential or technical**), with one generalization spelled out (**B1**):
  - *Referential*: the predecessor's `isReferentialItem` checks a **markdown
    link** `](`, a DocC **symbol** `` `` ``, and a DocC **article link** `<doc:` (AISlopScorers.swift **:452**).
    F17 keeps `](` verbatim,
    **drops** `<doc:` (DocC-only, no generic equivalent), and **generalizes** the DocC double-backtick symbol
    marker to a **generic single-backtick inline-code** span `` `…` `` — a *new* generalization (the source
    checks only the literal substring `` `` ``). **Exact predicate (R7 #5):** an item is inline-code iff it
    **contains a backtick-delimited span** — `item.range(of: #"`[^`]+`"#, options: .regularExpression) != nil`
    (this superset also matches the DocC `` ``X`` `` inner span, so DocC symbols stay covered). A calibration
    fixture must prove it skips code triples ("`` `foo`, `bar`, and `baz` ``") **without** suppressing
    legitimate rhetorical triples ("fast, cheap, and reliable" — no backticks, still counts).
  - *Technical*: `isTechnicalItem` (:465-473) is kept **verbatim** (already generic — an **all-caps run**
    `[A-Z]{2,}`, a **digit-bearing token**, or identifier punctuation `_`/`::`/`/`), so "P2WPKH, P2WSH, and
    P2SH" does not over-flag.
  - Denominator = sentences (per 100).
- **S005 knowledge-cutoff** — phrase list **ported verbatim from `AIVocabulary.knowledgeCutoffPhrases`**
  (:127), substring-count case-insensitive, **raw count**, scale `(0,5,.low)`.
- **`.sarif`/`.sarif.json` exclusion (R4 #5; R6 nb):** these files are processed **only by S007** and
  **excluded from S001–S006** density scoring. **Why SARIF is the special case** (and arbitrary `.json`/
  `.yaml`/source is *not* excluded): SARIF is a findings artifact skillet itself defines, so S007 owns it;
  other machine files are left in-scope but score **near-zero naturally** (slop vocabulary, em-dashes, and
  rhetorical triples essentially never occur in code/config), so no extension allowlist is needed — and a
  data file whose *prose* string values are genuinely sloppy is arguably a correct hit, not noise.

## 4.9 Scorer model, mechanics & output determinism (R10 · implementability review)

The prior sections fixed *policy*; this pins the *mechanics* an implementer would otherwise have to guess.

**Scorer model (R10 #1) — the "redesign" made concrete.** Scoring is **per file** (each scorer sees one
decoded file's text — *not* the predecessor's per-corpus join of `articleBodies`; calibration fixtures are
authored against per-file densities, so a short file with one hit can score high — intended):
```swift
struct ScoredFile { let relativePath: String; let text: String }          // one decoded candidate
enum ScorerMeasurement {
    case density(value: Double, occurrences: [Range<String.UnicodeScalarView.Index>])  // S001–S006
    case categorical(level: SarifLevel, message: String)                               // S007
    case notApplicable                                                                 // e.g. 0 words
}
protocol Scorer { var ruleId: String { get }; var scale: ScorerScale { get }
                  func measure(_ file: ScoredFile, config: Scorers) -> ScorerMeasurement }
```
The **runner** maps a measurement → findings: `.notApplicable` → none; `.density` → goodness =
`scale.normalizedGoodness(value)`; **goodness ≥ 0.5 → none (clean)**, else **one located finding per
occurrence** at the file's `level`/`rank` (§4.2). `.categorical` → one file-level finding. **S000 is emitted
by the file reader** during disposition (§3.2), not by a `Scorer`.

**Counting (R10 #5) — ported verbatim; two units, deliberately.** Port `SlopTextStats.wordCount`
(AISlopScorers.swift:341) and `.sentenceCount` (:353) unchanged. **Denominators count `Character`s**
(graphemes, as the predecessor — changing this shifts every calibration number); **regions count Unicode
scalars** (SARIF, §4.3). Different purposes, different units — no conflict.

**Per-rule match + region span (R10 #4).** Each density scorer is refactored from "return a count" to "return
count + the scalar range of each match"; **`SARIFRegion.from(scalarRange:in:)`** (generalized from the
regex-only form so the non-regex scorers work) turns a range into the region:

| rule | match mechanism | region span |
|---|---|---|
| S001/S002 | word-list membership over `\b`-delimited words | the matched word's range |
| S003 | scalar scan for **U+2014 only** (not en-dash/`--`, :104) | the single em-dash scalar (`charLength 1`) |
| S004 | `RuleOfThreeMatcher` regex (:422) | the whole `X, Y, and Z` match (group 0) |
| S005 | case-insensitive phrase search **on the original text** (not a lowercased copy) | the matched phrase range |
| S006 | the three contrast regexes below | the whole contrast-span match |

**Finding ordering (R10 #2) — determinism for goldens.** The walk order is irrelevant: after all files ×
scorers run, **sort findings by `(relativePath, charOffset, ruleId)`** before emitting — the total order the
golden tests require (`FileManager` enumeration is unordered; `.sortedKeys` does not sort arrays).

**Level band operators (R10 #11), exact (`ScorecardFeedback:117-118`):** `goodness ≥ 0.5` clean · `0.4 ≤
goodness < 0.5` `warning` · `goodness < 0.4` `error`.

**Word lists (R10 #8):** S001 = `AIVocabulary.combined` (AIVocabulary.swift:87) **only** (the un-ported
`FormalRegisterDensity` list is not merged in); S002 = `AIVocabulary.puffery` (:90). `vocab.exempt` filters
**both** (:54 for S001, :79 for S002).

**S006 patterns (R10 #9), literal** (case-insensitive; each within one sentence — no `.?!` between; ≤ 60 scalars):
1. `\bnot\s+(just|only|merely|simply)\b[^.?!\n]{0,60}?\bbut\b`
2. `\b(it|that|this|they|we|you)['’]?s\b[^.?!\n]{0,60}?,\s*(it['’]?s|but)\b`
3. `\bless\s+about\b[^.?!\n]{0,60}?\bmore\s+about\b`
Located at the leading negator. The calibration fixture (the hard gate) locks these against false positives.

**Multi-line regions (R10 #7).** Line break = **`\n`** (a `\r` immediately before `\n` is part of the ending;
a lone `\r` is content). `startLine` = 1 + `\n`-count before the range start; `startColumn` = 1 + scalars
since the last `\n`. A match crossing a `\n` sets `endLine > startLine`, `endColumn` = scalars on the final
line + 1. (Reachable via S004/S006 `\s+`; CRLF is in the §5 test matrix.)

**Summary counters (R10 #6).** `files_scored` = readable text files run through ≥1 density scorer **incl.
zero-word files (0 findings) and `.sarif` files (S007 ran)**; `files_skipped` = read but non-scorable
(binary/non-UTF-8); `files_unreadable` = S000 (permission/oversized). Vendored/dot paths are excluded during
the walk and **not counted**.

**Message text (R10 #3)** — `result.message.text` + each `tool.driver.rules[].shortDescription`:

| rule | `message.text` | `shortDescription` |
|---|---|---|
| S001 | `` AI-slop vocabulary: `<word>` `` | Over-used AI vocabulary |
| S002 | `` Marketing puffery: `<word>` `` | Marketing-puffery language |
| S003 | `Over-used em-dash` | Em-dash over-use |
| S004 | `Rule-of-three rhetorical triple` | Rule-of-three over-use |
| S005 | `` Knowledge-cutoff disclaimer: `<phrase>` `` | Knowledge-cutoff mention |
| S006 | `"not X, but Y" contrast construction` | Negative-parallelism over-use |
| S007 | `Invalid SARIF 2.1.0: <reason>` | Emitted findings-file validity |
| S000 | `Not scored: unreadable (permissions)` / `Not scored: exceeds 1 MiB` | File not scored |

**RenderKit `score` table (R10 #10):** columns `RULE · LEVEL · RANK · FILE:LINE · MESSAGE` via
`Renderer.renderTable`; empty state `✓ score: no findings` (mirroring lint's `✓ lint: no findings`,
Renderer.swift:153); summary `N findings (E error · W warning) across M files`.

**Minors (R10).** Em-dash = **U+2014 only**. S007 "`runs` present" = the **key exists** (`SarifLog.runs`
returns `[]` when absent). `tool.driver.version` = `SkilletVersion.current`, **normalized in goldens** (not a
literal, so releases don't churn fixtures). No file-count cap on the walk (bounded per-file at 1 MiB — a
reporter walking everything is acceptable; stated so it isn't mistaken for an oversight). An unreadable or
oversized `.sarif` is **S000** (the read-failure rows in §3.2 precede S007).

## 5. Test plan (TDD) — free-first

1. **EDDCore goldens + region conversion.** SARIF emitter: exact 2.1.0 JSON, **camelCase literal**,
   **`tool.driver.{name,version,rules}`** present (static S000–S007 catalog), a `region` with
   `startLine`+`startColumn` **and** `charOffset`/`charLength`, `rank`+`level`, `skillet.` properties incl.
   the `skillet.scale` shape — **incl. a golden for S003 asserting `skillet.scale.good == "target"` and
   `skillet.scale.target == 1.5` (R9 risk — the sibling-field serialization + dictionary-key preservation)** —
   empty `results: []` for zero findings. **`SARIFRegion.from(regexMatch:in:)` unit-tested (R8 · R2)** with
   **emoji/astral, combining marks, CJK, and CRLF** → correct scalar offsets + 1-based line/column.
   `ScoreReport`/`skillet.score/1` **snake_case** JSON golden (schema, `per_rule` object).
2. **ScoreKitTests** (≤300 lines/file, UUID temp dirs).
   - *Per scorer, re-calibrated (S001–S006)*: clean → none; sloppy → located findings at expected scalar
     line/column with the §4.2 `level`+`rank`; **S003 per-100-words + a 0-em-dash file stays silent (R8/R4)**;
     **S004 both skips** — the
     single-backtick generalization ("`` `foo`, `bar`, and `baz` ``" → **skip**), the technical skip
     ("P2WPKH, P2WSH, and P2SH" → skip), **and a plain rhetorical triple ("fast, cheap, and reliable" →
     count)** to prove the generalization doesn't over-suppress (R6 B1); **S005** phrase list + raw count;
     **S006 matching-rule fixture** (the three families hit; legit contrast prose does not over-flag).
   - *Config*: `vocab.exempt` phrase **removed from the word-list** (not flagged, source unchanged — R3);
     **`vendored_prefixes` gitignore-matching (R8/B1)** — `Vendored/` skips `Vendored/x.md` **and**
     `sub/Vendored/x.md` (any depth) but **scores** `VendoredFoo.swift` (different segment); case-sensitive;
     skipped **before read**; **S006 off by default**, on via `enable`; a default-on scorer off via `disable`;
     `disable` beats `enable`; outside-repo defaults; a **corrupt repo `skillet.yaml` → exit 4**.
   - *File selection / safety*: dot-dirs (`.git`) skipped; symlink not followed; escape rejected; **binary /
     non-UTF-8 → silently skipped (counted), no finding**; **unreadable / >1 MiB → an `S000` note, no crash**;
     `.sarif` excluded from density, routed to S007.
   - *Validity*: a malformed `.sarif`, and a well-formed one with `version: "2.0.0"` → an `S007` `error`
     finding (exit **0**); an **oversized `.sarif` (> 1 MiB)** → an `S000` note and is **not** validated by
     S007 (R5 nb — the read cap precedes validation).
3. **IntegrationTests (built binary).** `--format sarif` → structural 2.1.0 (incl. `tool.driver.rules`) on
   stdout, **exit 0**, no model/net; **`--format json` → asserts top-level `schema == "skillet.score/1"` and
   that `summary.per_rule` is an object keyed by rule-id, not an array (R8 · S2)**; `--json --format sarif` →
   SARIF; `--format tty`/bare-pipe → the human table + next-step; single-file `<path>`; clean folder → empty
   findings; **missing `<path>` argument → exit 2 (R8 · S3)**; **bad `<path>` → exit 3**; **corrupt config →
   exit 4**; unknown flag → 2.

> **Moved-helper parity (R8 · R1; R10 #1):** `RunnerTests` re-points at ProjectKit (it names the moved
> helpers); `StagingParityTests`/`HarnessKitTests` stay green unchanged — together proving the
> confinement/safe-read move preserved behavior (§3.2).

## 6. Docs ripple (§ doc-sync contract)

- **Roadmap** F17: IMPLEMENTED; metric `score <bundle>` → `score <path>` + `<bundle>` (Phase 3) note; **add a
  tracked known-limitation line (R7 #7): the user/`$XDG_CONFIG_HOME` config layer for `scorers` is deferred to
  F24** (repo + built-in defaults only in F17) — captured here so it does not silently drift vs design §5.2.
- **design.md**: **§6.2 `skillet score <bundle|path>` → `<path>`** (`<bundle>` deferred note); §5.2 the
  `scorers` section + **the new `SkilletConfig.Scorers` model + its `CodingKeys`** documented in the config-model
  list (R7 #4 — *not* a §7.2 frozen boundary *format*; it is a config model, now read rather than ignored);
  §5.4/§6.2 **record the reporter-vs-gate reconciliation (R7 #6): `score` is a *reporter* — exit 0 even when
  scorers fire (D6 "gates advise"; the scorer signal feeds later gating in triage F33 / contradiction F34) —
  deliberately unlike `lint`, a *pre-paid gate* that exits 1 on an error-tier finding; a corrupt *config*
  still exits 4**; §5.5 note `score` lands `--format` first + its progress/next-step; §11 `ScoreKit` shipped;
  §7.2 `SKILL-Sxxx` beside `SKILL-Lxxx`. Header + changelog bump.
  - **Design-doc amendment = a tracked deliverable landing *with* the feature commit (R9 · B4), proposed text:**
    - **§6.2** — change the plumbing row to `skillet score <path>` · "Deterministic scorers → SARIF on stdout
      (`--format sarif`); reporter, exit 0. `<bundle>` input lands with capture (Phase 3)."
    - **§5.2** — add: "`scorers:` — `vendored_prefixes` (gitignore-style folder skips), `vocab.exempt` (domain
      terms removed from the slop word-list, whole-entry), `disable`/`enable` (rule-id opt-out/opt-in). Repo +
      built-in defaults only; the user/`$XDG_CONFIG_HOME` layer lands with F24." **And explicitly (R11 · doc):
      the built-in defaults are `[]` for *both* `vendored_prefixes` and `vocab.exempt`; `skillet init` pre-writes
      `["Vendored/","Generated/"]` as a *suggestion*; the example values shown at design.md:174-186 (incl.
      `["secp256k1","Schnorr"]`) are illustrative *template output*, not runtime defaults** — the current §5.2
      example doesn't draw that line and must.
    - **§5.4** — add a note: "`score` is a **reporter**, not a gate: it exits 0 even when scorers fire (the
      SARIF signal feeds triage/contradiction), deliberately unlike `lint`'s error-tier exit 1. A corrupt
      config still exits 4."
    These edits land in the same PR as F17 so the source-of-truth doc stays in sync (not deferred).
- **AGENTS.md** banner + Commands gains `score`; **README.md** command list gains `score`.
- **Package.swift**: `ScoreKit` (`EDDCore` + `ProjectKit`) + `ScoreKitTests`; `RunKit`/`HarnessKit` gain
  `ProjectKit` (the moved helpers); `skillet` gains `ScoreKit`.
- **Specs/README.md** index: add `012`. **ROADMAP.md / ROADMAP-changelog.md**: F17 status + `score` row.

## 7. Status log & review-round changelog

- **2026-07-09 · Authored** + **Review round 1 (12)** + **round 2 (7 + Q&A)** + **round 3 (13, research)** —
  see git history of this file; net: exit codes, config discovery, confinement, dual `level`+`rank`, one
  `--format` selector (no auto-switch), five logics generalized + re-calibrated, ProjectKit home, `ScoreReport`,
  `scorers` config, camelCase emitter, region unit = scalars, S006 default-off.
- **2026-07-09 · Review round 4 (8 blockers + non-blockers), research-cross-referenced.** (1) **S003 = per
  100 words** (verified `*100.0`); all denominators re-pinned against source. (2) **S004 retains
  `isTechnicalItem`** (all-caps/digit/identifier) generalized, not just links/inline-code — prevents technical
  triples over-flagging. (3) **S006 matching rule designed** (EQ-Bench contrast family, regex-only, three
  intra-sentence patterns) + provisional scale. (4) **File-selection policy** added (regular, non-dot,
  non-vendored candidates; no extension filter). (5) **`.sarif` excluded from S001–S006**, routed to S007.
  (6) **`tool.driver.{name,version,rules}`** added to the emitter + goldens. (7) **Exit 4** for a corrupt
  config (via `loadConfigWithOrigin`) added. (8) **`ScoreReport` is snake_case** (house `--json` convention),
  distinct from SARIF camelCase; sample corrected. **Non-blockers:** design ref §7.6→§5.2; §6.2 `<bundle|path>`
  ripple; `vendored_prefixes` default `[]` vs template-suggested values clarified; `disable` beats `enable`;
  `skillet.scale` JSON shape; S003 trigger wording; TTY progress note; next-step suggestion. **Architecture
  risk** addressed: confinement/safe-read **moved** (not duplicated) into ProjectKit; ProjectKit stays
  EDDCore-only, so RunKit/HarnessKit importing it is downward — no cycle.
- **2026-07-09 · Review round 5 (4 blockers + non-blockers), research-cross-referenced.** (B1) S004
  referential-skip corrected: `](` kept, `<doc:` dropped, DocC `` `` `` **generalized to single-backtick
  inline code** (a stated new generalization + fixture); `isTechnicalItem` kept verbatim. (B2) `ScoreReport`
  location carries **full SARIF positional fidelity** (`start/end_line/column` + `char_offset/length`;
  categorical omit end/char). (B3) `per_rule` is a **JSON object** `[String: Int]`. (B4) `tool.driver.rules`
  = a **static S000–S007 catalog** (not the active set), stable when S006 is off. **Non-blockers:**
  `vendored_prefixes` matching semantics (relative, component-prefix, trailing-slash required — **superseded by R8: gitignore whole-segment, slash optional**, R10 #3); `charOffset`
  **0-based** scalars stated; oversized `.sarif` → `S000` (not S007), called out; `S007` also flags `version`
  ≠ `"2.1.0"`; `.sortedKeys` means goldens lock sorted bytes not sample order; `SkilletConfig.Scorers` +
  `CodingKeys` added to the frozen-artifact ripple (config was ignored on decode); the "no user layer until
  F24" gap noted vs §5.2; next-step suggests the **free** `skillet lint`, not paid `run` (**superseded by R7: lint's filter is registration-based, not free-vs-paid — the "free lint" framing was wrong**, R10 #4).
- **2026-07-09 · Review round 6 (3 blockers + non-blockers), research-cross-referenced.** (B1) **Citations
  corrected + made precise**: scale defs at `:39/:67/:92/:115/:138`, denominators at `:57/:82/:105/:128/:159`
  (both cited); `isReferentialItem` `:452`. (B2) **ProjectKit move given an explicit inventory** (moved-vs-
  stays table + signatures; `isHidden` accounted for across its 3 sites; `isSymlink` de-dupes; Package.swift
  downward-only confirmed). (B3) **Oversized → no decode**: `boundedRead fullSize > cap` ⇒ `S000`, never
  `decodeText` on the truncated prefix (so an oversized `.sarif` is never partially validated). **Non-blockers:**
  `properties` is a dotted-key map both encoders emit verbatim (dictionary keys bypass `.convertToSnakeCase`);
  `--format`↔`Renderer` wiring (`.json`/`.human`/`sarif`-bypass) stated; `Scorers` decodes with per-key
  defaults (partial block doesn't zero siblings); `endColumn` = 1-based-after (`startColumn + charLength`);
  S004 fixture made explicit (single-backtick skip, technical skip, rhetorical triple counts); documented why
  SARIF is the special-cased extension (skillet-owned artifact; other machine files score near-zero naturally).
- **2026-07-09 · Review round 7 (4 blockers, 1 editorial + 3 clarifications).** (1) **Next-step claim
  corrected** — `LintCommand.nextSteps()` filters by *registration*, not free-vs-paid; dropped the false
  "free-only mirror" wording (score uses the same registration mechanism; a suggestion isn't a spend).
  (2) **Categorical location shape pinned** — S000/S007 `location` is **exactly `{ file }`** (no start/end/char),
  i.e. SARIF `artifactLocation` with no `region`. (3) **`.sarif` non-UTF-8/parse failure → S007 `error`**
  (not a silent skip) — read-disposition rewritten as a table branching on `.sarif`-ness. (4) Removed the
  **duplicate table header**; "frozen-artifact list" → **config-model list** (not a §7.2 boundary format).
  (5) **S004 single-backtick predicate stated exactly** (`item` contains `` `[^`]+` `` — a superset that also
  covers DocC `` ``X`` ``). (6) **Exit-0-with-findings recorded** as a deliberate reporter-vs-gate choice in
  design §5.4/§6.2. (7) **Deferred user-config layer** tracked as a roadmap known-limitation vs §5.2.
- **2026-07-09 · Review round 8 (1 blocker, 2 clarifications, 4 risks, 4 minors) + decision Q&A.** **Decided:**
  (B1) **`vendored_prefixes` = gitignore-style** folder-name-at-any-depth, whole-segment, case-sensitive, no
  wildcards/anchoring in F17 (research: gitignore spec + ESLint follow it); (S1) **`$schema` = the community
  mirror** (advisory value; OASIS canonical cited in a comment). **Applied:** (C1) reporter-not-gate rationale
  lifted into the Assumptions cell (A3); (C2) `--format` resolved in code against `options.json`, not
  ArgumentParser conflict handling; (R1) move ripple spelled out — `SkillBundleRules` → thin wrapper,
  `StagingParity`/`RunnerTests` re-point at ProjectKit, ProjectKit stays Foundation+EDDCore-only (re-verify);
  (R2) `SARIFRegion.from(regexMatch:in:)` converts UTF-16 `NSRange`→scalars, unit-tested with emoji/combining/
  CJK/CRLF; (R3) `vocab.exempt` **removes word-list entries**, not text-masking; (R4) S003 target-scale intent
  confirmed (0 em-dashes ⇒ goodness ≈0.82 ⇒ silent; fixture proves it); (S2) integration asserts `schema` +
  `per_rule` object; (S3) missing `<path>` → exit 2; (S4) `boundedRead` keeps its `cap:` param (already true).
- **2026-07-09 · Review round 9 (4 blockers + risks; "implementation-ready" verdict).** (B1) **`normalizedGoodness`
  formula added verbatim** to §4.2 (Scorer.swift:57-70) — S003's 0-em-dash⇒0.82 now reproducible. (B2)
  **Global `--json` + local `--format` coexistence confirmed proven**, not a risk (`RunCommand` already does
  `GlobalOptions.--json` + local `--judge`/`--axis`); precedence resolved in `run()`. (B3) **ProjectKit move
  sequenced** as a prerequisite: (1) move + Package.swift, (2) green existing tests, (3) then ScoreKit. (B4)
  **Design-doc amendment made a tracked deliverable with proposed §6.2/§5.2/§5.4 text**, landing in the F17 PR.
  **Risks:** emitter named **`SarifDocument`/`SarifEmitter`** (distinct from the `SarifLog` reader); `.sarif`
  detection by **exact suffix**, not substring; `ScoreReport.location` is a **sum type** enforcing categorical =
  `{file}` at compile time; a golden pins `skillet.scale.good=="target"`/`target==1.5`. **Minors** all confirmed
  (citations, snake_case encoder, untouched reader, TTY default). Implementation-ready.
- **2026-07-09 · Review round 10 (independent dual review — accuracy + implementability).** Accuracy pass
  confirmed **every code citation correct** (rounds 6–9 held); fixed 5 drifts: (#1) `StagingParityTests`
  does **not** call moved helpers — only `RunnerTests` does; (#2) `isSymlink` is **one impl re-exported**, not
  duplicated, with more callers than listed; (#3/#4) two stale round-5 changelog phrases annotated as
  superseded (trailing-slash; free-lint next-step); (#5) `vocab.exempt` cite → :54-55, filters both S001+S002.
  **Implementability pass added §4.9** resolving the "how, not what" gaps the policy rounds missed: (#1) the
  concrete **`Scorer`/`ScoredFile`/`ScorerMeasurement` model** + per-file scoring; (#2) **finding total-order**
  `(path, charOffset, ruleId)`; (#3) **message + shortDescription text** table; (#4) **per-rule region spans**
  + generalized `SARIFRegion.from(scalarRange:in:)`; (#5) **ported `wordCount`/`sentenceCount`** + the
  Character-denominator / scalar-region unit split; (#6) **counter semantics**; (#7) **multi-line/CRLF region**
  rule; (#8) **S001=`combined`/S002=`puffery`** list identity + exempt-filters-both; (#9) **literal S006
  regexes** + bound; (#10) **`score` table columns**; (#11) **exact band operators**. Minors: em-dash U+2014
  only, `runs`-key-exists, version normalized in goldens, no walk cap, S005 locate-on-original. Now specifies
  *what* and *how*.
- **2026-07-09 · Review round 11 (4 blockers + risks + doc/sync).** (B1) **`vocab.exempt` = whole-list-entry
  exact match (lowercased), not substring**, filtering **both** S001 `combined` and S002 `puffery` (verified
  AISlopScorers.swift:51-55/:79-81) — `["tapestry"]` won't suppress a `"rich tapestry"` entry. (B2)
  **`ScoreReport.Location` needs a hand-written `Codable`** to flatten the sum type into the documented flat
  object (Swift won't synthesize it) — the one non-mechanical part of the `--json` schema, golden-locked.
  (B3) **`SkilletConfig` init ripple** tracked: explicit init gains `scorers:` (additive; no direct call sites
  — decode-only). (B4) **ProjectKit move is a hard CI gate** — full existing suite green as a separate refactor
  commit before any scorer code; `StagingParityTests` passes *unchanged* (staying APIs), only `RunnerTests`
  re-points. **Risks:** piped `--format sarif` example in `--help`; `SarifDocument` must not use the snake_case
  encoder (goldens lock literals incl. `tool.driver.rules`). **Doc/sync:** amended §5.2 must state built-in
  defaults are `[]` for both, `skillet init` pre-writes the vendored values as a *suggestion*, and design.md:174-186's
  example values are illustrative template output, not runtime defaults.
