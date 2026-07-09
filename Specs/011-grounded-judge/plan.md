# Plan — Phase 2 · F16: the grounded judge (file-contents grading)

| | |
|---|---|
| **Feature** | F16 — grounded judge: grade whether a file-writing skill wrote the *right* contents, not just that it claimed to (CLI: `skillet run --judge grounded-judge`) |
| **Phase** | 2 — Trustworthy Measurement & Static Gates ([Roadmap/phase-2-measurement-static-gates.md](../../Roadmap/phase-2-measurement-static-gates.md), F16) |
| **Status** | IMPLEMENTED (2026-07-08) — `--judge text-judge\|grounded-judge` on `RunCommand` (validated, unknown → exit 2; grounded prints a P9 cost note; sets the evidence policy + stamps `judge_id` into provenance); `GroundedJudge` (JudgeKit — reuses `ClaudeCLIJudgeRunner` + required-explicit model + the v2 untrusted-JSON injection defense over `producedFiles`, strict-to-criterion, own `promptVersion` v1, reuses `TextJudge.parse`); `JudgeEvidence` gains optional `fileContents` + `FileContent` + `EvidencePolicy` (protocol unchanged); `Runner` hashes staged inputs pre-run and captures the produced/changed set post-run under the with-contents policy (text path → no read); `WorkspaceManager.snapshotStaged` + `readProducedContents` (before/after snapshot diff — created+modified captured, deleted disclosed, untouched skipped; **symlink-confined** via `noSymlink`; 32 KiB/file · 128 KiB total; cut/binary/omit all disclosed); `EDDCore` — `RunProvenance` gains `judgeId`, committed `judge` block (benchmark `metadata.judge` + grading) gains additive `id`, carried on trigger-only merges. Capture hardened over two post-ship review rounds: non-regular files (FIFO/socket/device) disclosed **never opened** (a hang past the harness timeout), non-UTF-8 withheld as binary (no lossy U+FFFD), withheld sizes disclosed (`sizeBytes`), lstat deletion (no dangling-symlink double-record); **unreadable** regular files (chmod 000) disclosed not dropped; captured contents **persisted** to the run cache (`file_contents.json`) on **every** exit path (pollution/process/parse failure) and even for an **empty** produced set (`[]`, distinct from not-captured), for replay/re-grade/audit; symlinked-dir children skipped (not phantom-disclosed); `decodeText` trims only a genuine incomplete trailing scalar so an invalid byte (`0xFF`) at the cap stays binary (not stripped to text); a hard-linked produced file (link count > 1) is disclosed, never read. **356 tests green (+35**: 6 JudgeKit, 21 RunKit incl. P1 symlink-leak + FIFO-DoS + non-UTF-8 + invalid-byte-at-cap + hard-link + unreadable + every-exit-path persistence + timeout, 4 EDDCore provenance, 5 integration**)**; both roadmap F16 metrics verified against the built binary; end-to-end smoke confirmed (note + committed `judge.id` + exit-2 validation). All 8 decisions + two plan-review rounds + five code-hardening rounds applied. |
| **Last updated** | 2026-07-08 |
| **Builds on** | F7 (Runner/WorkspaceManager, `JudgeEvidence`, `Judge`/`JudgeRunner` seam, `ClaudeCLIJudgeRunner`, replay seam); F6 (claude-code adapter); F8 (frozen record provenance — `judge_id`/`model`/`judge_prompt_version`) |
| **Authoritative refs** | design §9.4 (the Judge — text vs grounded split; "grounded reads file *contents* from the trial sandbox… without changing the `Judge` protocol"); §11 (RunKit is the effectful/IO layer, JudgeKit stays subprocess-free behind `JudgeRunner`; constitution VI); P2/D3 (offline recompute/replay); §14-4 (judge model required-explicit) |
| **Decisions (2026-07-07, in-session Q&A, cold-reader protocol, evidence-recorded)** | **D-1 Content acquisition = bounded eager capture by the runner** (industry cross-ref: the "compact snapshot" pattern — Finch, arXiv:2512.13168; agent-as-a-judge is ascendant but raises variance/hurts reproducibility — AJ-Bench arXiv:2604.18240, "When AIs Judge AIs" arXiv:2508.02994, stochasticity-in-agentic-evals arXiv:2512.06710; the field's own reproducibility fix is replay-recording, which is skillet's P2/D3). RunKit reads output-file **contents** into `JudgeEvidence` at the same pre-teardown point it lists the sandbox, **touched-files-first**; the judge still never touches disk (constitution VI intact); contents ride the captured evidence so `--record`/re-grade (F19/F25) reproduce for free. **Symlink confinement (plan-review P1):** `readContents` **never follows symlinks** — it `lstat`s each entry (reusing `WorkspaceManager.isSymlink`/`noSymlink(at:under:)`), reads only real files whose resolved path stays under the workspace root, and **elides a symlinked output** as a disclosed marker (`[symlink → skipped, not followed]`, D-3 rule) rather than reading it. This closes the host-file-leak class: a trial that writes `out.txt → /etc/passwd` must never funnel host contents into the judge prompt or the cache records (the same no-follow discipline staging/fixtures already enforce). `readContents` walks + filters independently — it does **not** consume `listing()`'s paths, which may include a symlink entry. The on-demand **agent-reader** path stays open behind the same evidence contract — a later slice, recorded-for-replay when it lands. **D-2 Selection = an explicit whole-run flag taking a stable judge id** `--judge <id>`, values `text-judge` (default) | `grounded-judge` (plan-review P2): the value you pass **equals the recorded `judge_id`** — one naming surface, no friendly-alias mapping table to keep stable, matching the roadmap's `--judge <grounded-id>` and F25's `--judge <id>` re-grade selector. **Per-criterion auto-routing is deferred** — the design §9.4 "default for any criterion asserting a file-contents outcome" wording will be reconciled to "selected explicitly; auto-routing staged" and authored as **design §14-21** *in this feature's implementation docs ripple* (the design currently reaches §14-20; the plan does not claim it exists yet — plan-review P2). A fallible "is this criterion about a file?" classifier is exactly the kind of silent verdict-changing surface skillet refuses. **D-3 Capture bounds = fixed limits, cut-but-disclose** (no config knobs yet): a per-file byte cap (a file over it is included up to the cut with an explicit `[cut, N more bytes]` marker), a total-bytes cap filled touched-files-first (files left out are named to the judge), and non-text files listed with size but contents elided (`[binary, N bytes]`). The **load-bearing rule**: any cut/skipped/elided content is *disclosed to the judge and recorded*, never silent — an omission can never masquerade as an empty/wrong file. Exposing the caps as config (`judge.grounded.*`, parallel to the existing `runs.max_output_bytes`) is a **noted follow-up** if real skills hit the ceiling. **D-4 Grounded is a distinct judge whose evidence is a superset** (text + bounded contents), grading **strictly against each criterion** — an existence-only criterion passes on existence alone regardless of any content opinion, so flipping the flag can never silently convert an existence check into a content critique; its own `judge_id: "grounded-judge"` + `promptVersion` (start `v1`), stamped per verdict **and additively into the committed provenance** (plan-review P1): `RunProvenance` gains `judgeId`, and the committed `judge` block in **both** `benchmark.json` `metadata.judge` and `grading.json` gains an optional `id` — because those blocks carry only `{provider, model, prompt_version}` today, so grounded vs text would otherwise be distinguishable only by a coincidental `v1`-vs-`v2` string, and the per-trial `Verdict.judgeId` alone lives in the deletable `.skillet/` cache and would not survive a wipe. With `id` recorded, `prompt_version` regains its correct meaning (versioning *within* a judge lineage) and cross-judge deltas stay attributable in the committed record. **D-5 Flag-only selection now, config default staged** (no `judge.kind` concept invented until usage asks; consistent with D-3). **D-6 File set = the produced/changed delta via a before/after snapshot diff** (pre-implementation protocol; industry cross-ref: state-diff-based artifact grading — Agent-Diff arXiv:2602.11224, SWE-bench-style "extract the changes, grade those, not the workspace" — BeyondSWE arXiv:2603.03194, Finch's compact input↔output diff arXiv:2512.13168). The runner hashes each file it stages (skill bundle + input fixtures), then after the run classifies the post-run listing: **created** (path absent from the staged set) and **modified** (staged path whose content hash changed) get their contents captured (touched-first ordering is now this whole set); **deleted** staged files are disclosed as a fact (`[deleted]`), no content; **genuinely-untouched inputs are listed-not-read** — their existence is already carried and grading their unchanged bytes as skill output would be wrong. Deliberately does **not** trust `Trace.workspaceDiff` (degraded/empty on the live `stream-json` path) — the runner's own stage-time knowledge is exact and works identically live and replayed. **D-7 Caps = 32 KiB per file / 128 KiB total** (pre-implementation protocol; industry cross-ref: long context *degrades judge reliability* — LongJudgeBench arXiv:2606.01629, "lost in the middle" positional bias, task-specific byte budgets — AcademiClaw arXiv:2605.02661; so a bigger cap is worse on *both* cost and accuracy, not a tradeoff). Holds this project's typical whole outputs (a machine-readable report, a handful of doc files) intact while keeping a grading prompt ≈ a sixth of the model's window, far from overflow/drift; large files cut-and-disclosed, an over-budget many-file skill drops lowest-priority files (disclosed). Config knobs stay the D-3 follow-up. **D-8 Cost visibility = a one-line note when grounded is selected** (pre-implementation protocol; P9 spend-honesty): the run/plan prints "grounded judge includes file contents — larger grading requests, higher per-call cost (up to ~128 KiB of file text each)". Trial and call *counts* are unchanged (grounded doesn't add calls), and real token costs await F60 — so the note is the honest signal, matching the trigger/`--ab` note style; the gate stays trial-denominated. |
| **Assumptions** | A1: grounded reuses the same `ClaudeCLIJudgeRunner` + required-explicit `judge.model` (§14-4) as text — the split is prompt+evidence, not backend. A2: file contents are **untrusted** (the skill wrote them) → JSON-encoded under the same v2 untrusted-data framing as the text judge, with the criterion the trusted rubric; grounded's own `promptVersion` (start `v1`). A3: TDD per the roadmap metric — planted correct/wrong/empty fixtures; a fake `JudgeRunner` that decides from the contents section proves the contents actually reach the judge (a criterion-keyed canned verdict couldn't). A4: the `EvidencePolicy` (listing-only vs with-contents+caps) is set by the `--judge` selection and applies even under `--replay`, so the capture path is exercised end-to-end offline while grading stays deterministic via `ReplayJudge`. A5: additive only — `JudgeEvidence` gains an optional contents field (nil on the text path, no cost), `skillet.run/1` unchanged (grounded changes verdict *provenance*, not the report shape); the committed `judge` provenance block gains an **optional additive `id`** (tolerant-reader, additive-within-major — the mechanism F14's `estimated_calls` and F15's arm rows used), so no *breaking* frozen-format change while cross-judge attribution survives a cache wipe. A6: out of scope for grounded — deterministic parse/schema/existence checks that a **scorer** (F17) owns; grounded is the qualitative "is the content right" a code check can't express (mirrors SWE Atlas: execution-based where possible, LLM rubric only for what tests can't verify). |
| **Workflow** | Standalone plan (spec-kit workflow intentionally skipped) |

---

## 1. Goal

Grade file-writing skills on **what they wrote**, not just that they claimed to. Today's text judge
sees the response text + a filename listing + trace facts — enough to FAIL a *claimed-but-not-created*
file, but blind to a *created-but-wrong/empty* file (the "surface compliance" failure the judge
contract forbids). `skillet run --judge grounded-judge` reads the output files' contents (bounded) into the
evidence and grades the criterion against them.

**Success criteria (roadmap F16 metrics, verbatim):**
- A criterion asserting a written file passes only when the file exists with expected contents in the
  sandbox (planted pass/fail fixtures).
- Every verdict records `judge_id`, `model`, `judge_prompt_version`.

## 2. Scope

### In scope
- **JudgeKit**: `JudgeEvidence` gains an optional bounded `fileContents` ([{path, bytes, text?,
  truncatedBytes?, binary}]); `GroundedJudge: Judge` (shares `JudgeRunner`, v2 untrusted-JSON prompt
  + a `fileContents` section + a content-correctness instruction, own `id`/`promptVersion`, reuses the
  strict-JSON parse); an `EvidencePolicy` enum the runner reads.
- **RunKit**: `WorkspaceManager.readContents(...)` — **produced/changed-set** capture (D-6: created +
  modified vs the runner's stage-time hashes; deleted disclosed; untouched inputs skipped), bounded to
  **32 KiB/file · 128 KiB total** (D-7), touched-first, cut/binary/deleted/omitted all disclosed,
  **no-follow symlink confinement** (`lstat`-based, resolved paths under the workspace root, symlinked
  outputs elided-and-disclosed — plan-review P1). `Runner` hashes staged inputs, captures contents into
  evidence under the with-contents policy (text policy → no read, no cost); the workspace is live at
  judging time.
- **executable**: `--judge <id>` on `RunCommand` (default `text-judge`; accepts `grounded-judge`);
  maps the id to the judge builder; unknown id → usage error (exit 2) listing valid ids; the
  selection sets the evidence policy. Passes the selected `judge_id` into `RunProvenance`. Prints the
  **D-8 cost note** (stderr) when grounded is selected on a paid run.
- **EDDCore**: `RunProvenance` gains `judgeId`; the committed `judge` block (benchmark `metadata.judge`
  + grading `judge`) gains an optional additive `id` (plan-review P1) — carried on judge-free
  trigger-only runs like the rest of the block.
- **Docs**: design §9.4 annotated (shipped grounded), **§14-21 authored** (auto-routing staged —
  authored in this ripple, does not pre-exist); the standard ripple (design → v0.x, ROADMAP →
  v1.16.0, changelogs, this plan, **Specs/README.md 011 row** — plan-review P3).
- **Tests**: JudgeKit unit (contents reach the prompt; planted correct/wrong/empty; strict-to-criterion
  existence-only; provenance incl. `judge_id`); RunKit unit (bounded capture edges: per-file cut, total
  cap ordering, binary elision, disclosure; **output-symlink not followed + disclosed**; policy gating);
  EDDCore unit (committed `judge.id` present + carried on trigger-only); integration via replay (flag
  selects grounded + exercises capture; committed `judge.id` recorded; default `text-judge` unchanged;
  bad id → exit 2).

### Out of scope (with where it lands)
- Per-criterion auto-routing → design §14-21 (authored in this feature's docs ripple, decided later).
- Config default for the judge kind (`judge.kind`) → staged follow-up (D-5).
- Config knobs for the capture caps → staged follow-up (D-3).
- On-demand agent-reader judge → later slice behind the same evidence contract (D-1).
- Deterministic parse/schema/content checks → the scorer, F17 (A6).
- The `direct-api` "snapshot in-context" judging variant → with that adapter.

## 3. Architecture (targets touched)

`EDDCore` (`RunProvenance` gains `judgeId`; committed `judge` block gains optional `id` — additive) ←
`JudgeKit` (evidence field + grounded judge, still IO-free behind `JudgeRunner`) ← `RunKit` (bounded,
symlink-confined content capture + policy) ← `skillet` (`--judge <id>` wiring + provenance). No new
targets, no new dependencies, constitution-VI IO boundary preserved (all file reads stay in RunKit).

## 4. Test plan (TDD) — free-first

1. **JudgeKit unit** — `GroundedJudge.prompt` JSON-encodes `fileContents` under untrusted framing;
   a fake `JudgeRunner` returning PASS only when the contents section holds the expected string proves
   contents reach the judge; planted correct→PASS / wrong→FAIL / empty→FAIL; an existence-only criterion
   PASSes on a present-but-unrelated-content file (strict-to-criterion, D-4); verdict stamps
   `grounded-judge`/model/`v1`.
2. **RunKit unit** — `readContents`: **created + modified captured, deleted disclosed, untouched input
   skipped** (D-6, via stage-time hashes); per-file cut@32KiB+marker, total-cap@128KiB touched-first +
   named omissions (D-7), binary elision+marker; **a symlinked output (`out.txt → /etc/passwd`, and a
   symlinked dir) is never followed and is disclosed — no host contents in the evidence** (plan-review
   P1); `Runner` includes contents under with-contents policy and omits them (no read) under
   listing-only.
3. **EDDCore unit** — the committed `judge` block carries `id` (benchmark + grading), and it is
   carried verbatim on a judge-free trigger-only merge.
4. **Integration (replay seam)** — `--judge grounded-judge` runs green and exercises capture; the
   committed `benchmark.json`/`grading.json` `judge.id` is recorded; the D-8 cost note prints on
   stderr; `--judge text-judge` (default) is byte-unchanged from today; `--judge bogus` → exit 2.

## 5. Status log

- 2026-07-07: Plan authored from the in-session decision Q&A (D-1…D-5, cold-reader protocol);
  awaiting review before implementation.
- 2026-07-07: **Plan-review round 1 (5 findings, all valid, applied to the plan — no code yet).**
  P1 symlink leak: `readContents` gets an explicit no-follow/confine/disclose rule + output-symlink
  tests (D-1, scope, tests). P1 provenance gap: verified the committed `judge` block carries only
  `{provider, model, prompt_version}` — added additive `judge_id` to `RunProvenance` + both committed
  blocks so the "cross-judge attributable" claim is true in committed records, not just the cache
  (D-4, A5, scope, tests). P2 selector: settled on **stable ids** `text-judge`/`grounded-judge`
  (value == recorded `judge_id`; matches roadmap `<grounded-id>` + F25). P2 §14-21: reworded to
  future-tense "authored in this ripple" (design reaches §14-20; no dangling "already recorded").
  P3: Specs/README.md 011 row added.
- 2026-07-08: **Pre-implementation protocol (cold-reader Q&A) — 3 implementation unknowns settled.**
  D-6 file set = the produced/changed delta via a before/after snapshot diff (research: state-diff
  artifact grading, grade-the-change-not-the-workspace); D-7 caps = 32 KiB/file · 128 KiB total
  (research: long context degrades judge reliability, so bigger is worse on cost *and* accuracy);
  D-8 = a one-line cost note when grounded is selected (P9 spend-honesty). Scope/tests threaded.
  Implementation starts.
- 2026-07-08: **IMPLEMENTED** — full status in the header row. 342 tests green (+21, zero failures,
  verified full-suite run). Design → v0.42 (§9.4 annotated, §14-21 authored; header pointer
  reconciled v0.39→v0.42 — F15's review rounds had advanced the changelog to v0.41), ROADMAP →
  v1.16.0; AGENTS/README/Specs-index rippled. Open follow-ups: the config-knob variants for the
  caps (D-3) and the judge kind (D-5), and auto-routing (§14-21) — all staged, none blocking; a
  paid live smoke of grounded grading rides the env-gated smoke like the other adapters.
- 2026-07-08: **Post-ship review round 1 — capture hardening (5 findings, all valid, fixed).**
  (1) HIGH — content capture no longer opens FIFO/socket/device files (a `FileHandle` read on a pipe
  blocks forever — a skill could `mkfifo` in the sandbox and hang capture *past* the harness timeout,
  since the timeout only wraps the harness call, not evidence capture); the regular-file check runs
  before any open, and non-regular files are disclosed (`special: true`) unread. (2) MEDIUM —
  non-UTF-8 bytes are withheld as `binary` via strict UTF-8 validation (with an incomplete trailing
  scalar trimmed on a cap-truncated read) instead of `String(decoding:as:)`'s lossy U+FFFD; only NUL
  was caught before. (3) MEDIUM — `FileContent` gains `sizeBytes` so a withheld binary/special file
  discloses its size. (4) LOW — the deletion pass uses lstat existence, so a staged file replaced by
  a *dangling* symlink is recorded once (modified symlink), not also deleted. (5) LOW — doc date
  drift fixed. +4 regression tests (FIFO-DoS with a `.timeLimit` guard, non-UTF-8-no-NUL,
  truncated-scalar-stays-text, dangling-symlink-not-double-recorded). 346 tests green (+4). Design →
  v0.43, ROADMAP → v1.16.1.
- 2026-07-08: **Post-ship review round 2 — omission-disclosure + evidence persistence (3 findings,
  all valid, fixed).** (1) MEDIUM — an unreadable regular file (`chmod 000`, open fails while its
  metadata is still readable) is disclosed (`FileContent.unreadable`, with `sizeBytes`) instead of
  the silent `continue` on `boundedRead == nil` — the last gap in "every omission disclosed". (2)
  LOW/MEDIUM — the captured `fileContents` is now persisted as `file_contents.json` in the run cache
  (grounded policy, all exit paths), so grounded evidence survives teardown and the plan's
  replay/re-grade "for free" claim is real; text policy writes nothing. (3) Test hardening — the
  symlinked-dir case asserts the link is disclosed and no `linkdir/…` child enters evidence; the
  production code now separates "is a symlink" (disclose) from "under a symlink" (skip the phantom
  child). +3 tests. 349 tests green. Design → v0.44, ROADMAP → v1.16.2.
- 2026-07-08: **Post-ship review round 3 — persistence is now truly "every exit path" (1 finding,
  valid, fixed).** Round 2 captured only after harness+parse+tripwire, so polluted baseline trials,
  process/timeout failures, and parse failures persisted `nil`, and an empty produced set (`[]`) was
  skipped — "wrote nothing" was indistinguishable from "not captured" after teardown (the worst case
  for "wrote file X" criteria). Fix: capture hoisted post-parse (pollution + judge-fail + success all
  persist); catch paths capture from the live workspace (`?? captureEvidence()`); the writer persists
  whenever captured **including `[]`** (`nil` = text policy = no file). +3 tests (empty-set,
  parse-failure, polluted). Reviewer's `unchanged()`-follows-symlink non-finding confirmed
  unreachable (round-2 guards). 352 tests green. Design → v0.45, ROADMAP → v1.16.3.
- 2026-07-08: **Post-ship review round 4 — a real correctness bug + polish (4 findings, all valid,
  fixed).** (1) CORRECTNESS — `decodeText`'s truncation trim removed *any* high-bit trailing byte, so
  a binary file whose cap-boundary prefix ended in an invalid byte (`0xFF`/`0xFE` — JPEG, UTF-16 BOM)
  was stripped and mis-graded as truncated text; it now trims only a genuine incomplete trailing
  scalar (≤3 continuation bytes then a lead byte `0xC2…0xF4`), so invalid bytes fall through to binary
  (regression test: valid UTF-8 + `0xFF` at the cap → binary). (2) `fileType` comment corrected
  (`attributesOfItem` isn't `lstat`; moot behind the guards). (3) timeout/`ProcessError` catch-path
  test added (backs the round-3 claim). (4) `--judge grounded-judge --axis trigger` now prints a
  "no effect (behavioral-only)" note instead of silently ignoring the flag. +3 tests. 355 tests
  green. Design → v0.46, ROADMAP → v1.16.4.
- 2026-07-08: **Post-ship review round 5 — 4 minor concerns; 2 acted, 2 deferred with rationale.**
  ACTED: (1) hard-link guard — a produced file with `st_nlink > 1` (another directory entry, possibly
  a same-fs host file — the content-leak parallel to symlinks) is disclosed (`hardlink: true`) and
  never read (regression test: `link()` to a host secret → disclosed, unread, no leak); (2) `--judge`
  `@Option` renamed `judgeSelection` (flag unchanged) to remove a `judge`/`judgeCfg` shadowing
  subtlety. DEFERRED (tracked): (3) the **robust** hard-link fix = workspace-level isolation (no reader
  fooled) — a future sandbox-hardening pass, broader than grounded (§9.2); (4) bounded `snapshotStaged`
  reads — fixtures are maintainer-controlled + copied (`nlink = 1`, not skill data), so robustness-not-
  boundary; a nice follow-up. Also DOCUMENTED: `decodeText`'s absurd-sub-scalar-cap continuation edge
  as an accepted heuristic limitation (unreachable at 32 KiB). Possible future cleanup noted:
  `FileContent`'s five withheld-reason bools could consolidate to one enum. +1 test. 356 tests green.
  Design → v0.47, ROADMAP → v1.16.5.
- 2026-07-08: **Post-ship review round 6 — optional polish (4 observations; 2 acted, 2 reaffirmed
  tracked).** ACTED: (1) explicit `import TraceKit` in `GroundedJudge` **and** `TextJudge` — the
  sibling had the identical implicit dependency, so both are made explicit (consistent, not one-off);
  (2) a dedicated `FileContent.omitted` flag — a budget-dropped file is `omitted: true` (with
  `sizeBytes`), so `truncatedBytes > 0` now strictly pairs with a shown prefix (sharper judge
  contract; prompt + total-cap test updated). REAFFIRMED tracked (no change): bounded `snapshotStaged`
  reads (fixtures maintainer-controlled/copied — robustness, not a boundary) and a `--judge`
  `ExpressibleByArgument` enum (fine at two values; raw string keeps CLI value == recorded
  `judge_id`). In-code note strengthened: the now-six withheld-reason bools should become one enum on
  the next substantive touch. No grading-behavior change. 356 tests green (count unchanged — the
  total-cap test was updated in place). Design → v0.48, ROADMAP → v1.16.6.
