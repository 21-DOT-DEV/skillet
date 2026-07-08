# `ROADMAP.md` — changelog

The roadmap's versioned change log, extracted from `ROADMAP.md` on 2026-07-04 (v1.11.1) so the plan document
stays lean. Latest first; every version is a linkable heading; historical entries are never rewritten.
Companion: [`skillet-design-changelog.md`](skillet-design-changelog.md).

## v1.15.0 — 2026-07-07

MINOR — **F15 SHIPPED: the A/B baseline arm** ([Specs/010](Specs/010-ab-baseline/plan.md); design →
v0.39). `skillet run --ab` runs every behavioral eval through a with-skill arm and a **provably
skill-free** baseline arm and reports the **paired** Δ ("is the skill earning its tokens?").
Isolation is prevent + verify + preflight (decided in-session after a Claude-Code-flags +
promptfoo/Anthropic-error-bars cross-reference): baseline trials launch with the session-level
no-skills switch (`--disable-slash-commands`), a $0 `--help` preflight refuses unsupported binaries
(exit 3 — §9.2's declare-cannot), and every baseline trial's trace must show zero skill invocations
or the trial is `polluted` — never judged, excluded from counts, loud in the report. Reporting:
per-eval paired Δ, mean ± Bessel SE (honest "too few" below n = 2), flip tally, time Δ (new
per-trial durations); additive `ab` block in `skillet.run/1` + `ab_baseline_trials` in the plan
payload. `benchmark.json` gains the canonical `with_skill`/`without_skill` rows (reserved by
Specs/009), arm-marked `per_eval` entries, per-arm stats + signed `delta` strings; single-arm runs
keep `"default"`; trigger-only runs carry the AB record (latest-run-per-axis); the offline
recompute rebuilds the block (P2/D3). Behavioral-axis only — trigger-only + `--ab` refuses (exit 2),
mixed runs print the single-arm note. Both roadmap F15 metrics verified against the built binary.
+25 tests at implementation and +4 across two post-review rounds (**321 green final**, verified
full-suite run). Phase 2 remains IN PROGRESS.

## v1.14.1 — 2026-07-07

PATCH — **review-round consistency fixes** (three reviewed findings; no scope or priority change;
design → v0.38): (1) the Global-Risks *judge-reliability* bullet now cites the **specified F10
agreement check** (report-only Cohen's kappa, design §14-14) instead of the pre-v1.13.0
"`needs-research` calibration harness" framing — the `needs-research` tag is reserved for the Apple
provider (F68); (2) design §13's v1 scope line reconciled with the F61–F68 rounds (F61/F62/F63 into
*Ships in v1*; F10/F64–F68 + the declined public Swift-library surface into *Later / explicitly
out*), ending the two-scope-stories drift; (3) Phase 8's risks text now names all cross-reference
additions (F10–F13 from the v0.8 competitive round; F64–F68 from the July-2026 Apple Evaluations
rounds) instead of "one cross-reference addition."

## v1.14.0 — 2026-07-07

MINOR — **Diagnostic model tier + Apple Foundation Models provider** (design → v0.37; §14-19/§14-20
decided — full record in [skillet-design-changelog.md](skillet-design-changelog.md) v0.37): **F67**
the provider-neutral cheap-model slot (Phase 8, pulls forward with F62) — the two-tier contract in
design §9.6: the diagnostic tier generates/scores/clusters/smokes and **never gates**, may float
with provenance stamped, calibrate-before-trust (F10 κ ≥ 0.6 before any judging use); platform
defaults only for $0/offline/entitlement-free providers, always announced (plan note + `doctor`
row); deliberately not Apple-only (Ollama-class cross-platform local runners are the research
alternative). **F68** the Apple FM/PCC provider (Phase 8, `needs-research`) — macOS zero-config
default = the on-device model behind `#if canImport(FoundationModels)` (compiles out on Linux and
older SDKs; zero new dependencies); PCC **never defaults** (managed entitlement, per-user iCloud
quota, network) — an explicit build-from-source lane; research exit-conditions: entitlement-for-CLI
viability, Apple Intelligence in CI VMs, SDK/OS timeline, skill context-fit rates vs 4–8K,
provenance identifiers. Diagnostic-tier lane notes added to F62 (Phase 4), F63 (Phase 5),
F64/F10/F52 (Phase 8), and the F14 smoke arm (Phase 2); `skillet.yaml` gains the `models.diagnostic`
slot (design §5.2). Docs-only; no shipped-code change.

## v1.13.0 — 2026-07-06

MINOR — **Apple Evaluations (WWDC26) cross-reference adopted** (design → v0.36; §14-9 decided + new
§14-13…§14-18 — the full decision record is [skillet-design-changelog.md](skillet-design-changelog.md)
v0.36): **F61** deterministic process assertions over the trace (Phase 2 — graduated from Candidate
Enhancements; required/forbidden tools, ordered/unordered groups, seven deterministic argument
matchers, strict + partial-credit dual results, judge-free; Apple's model-assisted matcher deferred),
**F62** scored diagnostic dimensions (Phase 4; anchored scales + rationales beside the binary
verdict — diagnostics-only, never gates), **F63** trigger-corpus paraphrase expansion (Phase 5;
observed seeds only, `synthetic` provenance, deterministic validators), **F10** re-specified
(Phase 8; report-only judge↔human Cohen's-kappa agreement check, ≥ 0.6 target, `needs-research`
dropped), **F64** general observed-seed synthetic generator (Phase 8), **F65** named aggregation
catalog (Phase 8; config-invoked, no formula language), **F66** test-framework integration recipe
(Phase 8, docs; the Swift-library surface declined and recorded as a Phase 8 non-goal). **F45**
gains the `synthetic-backed` held-out proof note (§14-16: synthetic siblings proof-eligible within
their seed's failure class; evidence-side gates stay observed-only). Candidate Enhancements: §14-9
graduated; §14-10 (ablation arms) remains staged. Docs-only; no shipped-code change; Phase 2
remains IN PROGRESS.

## v1.12.0 — 2026-07-04

MINOR — **F14 SHIPPED: the trigger axis** ([Specs/009](Specs/009-trigger-axis/plan.md); design → v0.30).
`skillet run --axis behavior|trigger|all` (default: each axis where its file exists; the spend gate covers
the combined estimate — trigger trials are judge-free single calls). Fired/not-fired judged
**deterministically** from `skillInvocations` over **whole-corpus frontmatter stubs** (§9.2's `visible:`
tier, now live); `should_trigger:false` near-misses verify correct non-firing with routing forensics.
`benchmark.json` carries both axes — `configuration:"trigger"` rows + axis-marked `consistency` entries,
**latest-run-per-axis merge** so no axis can blank the other; both recompute offline (P2/D3);
`skillet.run/1` gains the additive `trigger` block. Both roadmap F14 metrics verified by replay-seam
integration tests. Doctor's discovery-only visibility check: **unblocked by F14, deferred** (D-4 —
tracking texts updated). +17 tests (279 green). No other scope or priority change.

## v1.11.1 — 2026-07-04

PATCH — **Change Log extracted to this file** (it had grown to 56% of ROADMAP.md). One linkable heading per
version, latest first, historical entries **verbatim** (never rewritten); ROADMAP.md keeps the latest summary +
a link here. Entry discipline going forward: **detail lives nearest the artifact** (a feature's `Specs/NNN` plan
status; design-only changes in `skillet-design-changelog.md`) — logs like this one carry a short summary + link.
Companion: [`skillet-design-changelog.md`](skillet-design-changelog.md) (design v0.28). No plan, scope, or
priority change.

## v1.11.0 — 2026-07-04

MINOR — **F3 SHIPPED: `skillet doctor`, the $0 preflight**
([Specs/008](Specs/008-doctor-preflight/plan.md); design → v0.27; **Phase 2 → IN PROGRESS**).
Option-2 contract (decided in-session 2026-07-03 after a brew/npm/wp-cli/gh doctor-pattern
survey): the end-state *contract* ships now — check-registry rows in a frozen **`skillet.doctor/1`**
`--json` payload (golden-tested), **warnings never fail** (exit `0`), any failure row exits `3`
with a remedy line, shared `2`/`4` classes — with the phase-metric checks lit: config parse + file
origin, harness binary/version/denylist + winning resolution link (additive
`HarnessInfo.binaryPath`/`source`/`bannedVersion`), per skill×harness **positive-load visibility**
via the new staging-parity `SkillBundleAudit` (a symlink staging would silently drop is a loud
failure naming the path — the `--skill-path` false-negative class killed statically; parity with
the F7 stager is test-guarded), and all error-tier lint findings (recolored exit `3`). **Auth =
warning row** per the F3 Notes (`run`'s strict preflight owns the refusal), so doctor stays green
in authless CI. Deferred rows land with their owners: frontmatter → F20, `--paid` → F21,
per-value origins → F24; artifact sweep / `git` / betterleaks / discovery-only half with their
features. +21 tests (258 green). No scope or priority change beyond F3 → IMPLEMENTED.

## v1.10.1 — 2026-07-03

PATCH — **dependency review: direct `swift-system` declaration KEPT;
removal deferred behind SE-0529** (design **§14-12**, R-dep; design → v0.26). Removing it now is
blocked and worthless: Ubuntu day-one has no SDK `System` module (the `SystemPackage` product
needs the top-level declaration), `swift-subprocess` (pinned 0.2.1 and upstream 0.5 alike)
declares `swift-system` `from: 1.5.0` and links it unconditionally (identical fetch/build graph
either way), and `exact: 1.5.0` is the manifest-level guard against floating to an untested
1.7.x (known-good-pins policy; upstream is at 1.7.2). Removal triggers tracked in Global Risks &
Assumptions: **T1** minimum toolchain ships SE-0529 stdlib `FilePath` + **T2** the pinned
`swift-subprocess` release consumes it. Docs-only — no dependency, scope, or priority change.

## v1.10.0 — 2026-07-01

MINOR — **audit remediation slate landed** (M1–M3 + §14-11 adopted; M4
drafted, pending maintainer ratification — [phase-1-review §5/§8](Roadmap/phase-1-review.md)).
(1) **M1:** `.github/workflows/ci.yml` — the constitution-V free-suite gate (macOS + Ubuntu via the
official `swift:6.3` container; zero secrets, zero paid calls; the live smoke self-skips) —
authored and logically verified; the first live run (and any Linux-first-build fallout) lands with
the next push. (2) **M2 / design §14-4 DECIDED — required-explicit judge model:** the config decode
carries no model fallback and `run` refuses an absent `judge.model` (exit 2, what/why/fix; the
replay/test seam exempt; `init` writes one). **Migration (pre-1.0 breaking):** hand-rolled configs
without `judge.model` must add it — or re-run `skillet init`. A deliberate divergence from the
surveyed silent-default convention (promptfoo's ambient-credential grader). (3) **M3:** committed
records gain additive provenance — `benchmark.json` `metadata.executor_binary_version` +
`metadata.judge.prompt_version`, and a `grading.json` `judge` block — via the new pure
`EDDCore.RunProvenance`; `run` now probes the replay seam too (canned, free) so every record names
its executor. (4) **§14-11 DECIDED — adopted:** additive `pass_1` in `skillet.run/1` +
`suite_pass_1` in the `consistency` block (mean per-eval trial pass rate — τ-bench's headline
metric, meaningful even at k = 1); strict all-trials `pass^k` stays the reliability gate
(graduated out of *Candidate Enhancements*). Design doc → v0.24/v0.25. 237 tests green. No phase
or priority change.

## v1.9.10 — 2026-07-01

PATCH — **external cross-reference addendum** added to the Phase-1 audit
([phase-1-review §8](Roadmap/phase-1-review.md)) after three adversarially-verified deep-research
passes (~29 primary sources): **nothing contradicts shipped Phase-1 behavior**. Verified supported:
pass^k ≡ τ-bench's metric (Chen et al. the correct ANY-pass contrast), FLAKY/hygiene-before-deltas
= the Google flaky-test canon, the existence-check-via-workspace-listing rule (Anthropic's canonical
final-state example; τ-bench/SWE-bench concur), **M1's free-suite-as-PR-gate** (lm-evaluation-harness
+ Inspect AI run model-free zero-credential CI on every PR; walking-skeleton canon puts build/test
automation before the first feature), the held-out proof gate (DSPy/GEPA), and audit-citation
practice itself (IIA 14.1 / ISO 19011 / ADR). **M2 reframed**: required-explicit judge is a
deliberate reproducibility divergence (promptfoo silently defaults its grader from ambient
credentials — verified in docs + source). Two corrections applied: design v0.22 (the infra-only-retry
rule re-stated as skillet's own discipline — no primary source states it) and **§14-11 staged**
(additive `pass_1` reporting; τ-bench's unbiased estimator makes skillet's strict rule a deliberate
conservative special case) → Candidate Enhancements. F16 (grounded judge) framed as closure of
τ-bench's named "necessary but not sufficient" gap. §7-minors deferral confirmed (no urgency
evidence; clig.dev silent on inert flags). Design doc → v0.23. No scope, feature, or priority change.

## v1.9.9 — 2026-07-01

PATCH — **Phase-1 completed-items cross-artifact audit** →
[Roadmap/phase-1-review.md](Roadmap/phase-1-review.md). Every F1–F8 metric verified against
`Specs/001–007` + shipped code (235 tests green; free-only — the paid smoke not re-run):
**Phase-1-COMPLETE stands**; F6 gaps C/D confirmed open, gap **#3 closed** (typed `harnessNotFound`
what/why/fix at probe/preflight). Documentary drift reconciled: phase-doc F2/F6/F7 current-state
lines; AGENTS (`Roadmap/` paths, LintKit in the banner, `.Cxx` test-target note, dump-help claim
scoped to names); README (+F8); design → **v0.21** (§7.2 evals-2.0 row + run-record family +
`scorecard.json` exclusion, §9.1 F50 annotations, §9.3 synthetic-goldens wording, §10
consistency-block recompute, §14-4 shipped-state note, §14-8 F5→F45); docc walkthrough (no
`--harness-path` yet; CI "when wired"); post-audit notes on all seven plans. **Staged, not
applied** (audit §5): the CI workflow (constitution V — `.github/workflows/` is empty),
judge-model required-explicit (§14-4 / constitution II), committed-record provenance
(`judge_prompt_version`/`executor_binary_version`), and the constitution's stale swift-system
note. No scope, feature, or priority change.

## v1.9.8 — 2026-07-01

PATCH — **F7 review round 9** (judge trace-evidence conformance + reason tolerance +
config test coverage). The text judge's prompt now carries the plan-specified compact trace summary —
skill invocations + **tool-call names + files touched** (was skills only) — as **best-effort supporting
context** (may be empty on live runs), with the workspace listing the sole authoritative existence oracle;
`workspaceDiff` modification-detection stays with the F16 grounded judge so a live-degraded diff can't
cause a false FAIL. The strict verdict parser tolerates a **missing `reason` key** (optional/defaulted) —
a bare `{"verdict":"PASS"}` is a valid PASS, never flipped to FAIL over cosmetics. Added tests for the
init template's F7 defaults and a config decode of `runs`/`judge` knobs. 235 tests green. No scope change.

## v1.9.7 — 2026-06-30

PATCH — **F7 review round 8** (free-before-paid lint gate + judge/`-C`/forensics
correctness). `run` now **enforces the shipped free error-tier lint** (`L001`/`L003`) before any spend —
making the README's "free lint gates every paid run" real: after the eval loader (corrupt→4/missing→2
preserved) and before dry-run/confirm/probe/cache, an error-tier finding refuses with **exit 2** and
`skillet.lint/1` (command-contextual — `skillet lint`'s own finding stays exit 1); `doctor` still owns
the broader Phase-2 preflight. The judge's **trusted criterion moved out of the untrusted evidence JSON**;
`-C` is now validated by `harness list/info` (exit 3, was silently ignored); a symlinked `SKILL.md` is
rejected before any read (exit 4); trial **forensics keep the raw output + partial verdicts on a
parse/judge failure**; `grading.json` is documented in the frozen run-record family and the init template
gains `runs.max_output_bytes`. 232 tests green. No scope/feature change.

## v1.9.6 — 2026-06-30

PATCH — **F7 review round 7** (judge injection defense + capture/cache hardening).
The text judge is hardened against prompt injection from the model under test: the untrusted output is
presented as one JSON object (it can't spoof fake prompt sections), framed as untrusted data whose
embedded instructions must be ignored, and the verdict must be strict JSON `{"verdict","reason"}` — a
prose "PASS: …" no longer counts (fail-safe FAIL; prompt version v1→v2). The subprocess output-capture
limit is now configurable (`runs.max_output_bytes`, default 64 MiB) so a large-but-valid `stream-json`
session is no longer misread as a behavioral failure (a true infra class + retry stay F18). The
`.skillet` cache path is symlink-confined before any write (exit 4), matching the round-5 skill guard.
227 tests green. No scope/feature change.

## v1.9.5 — 2026-06-30

PATCH — **F7 review round 6** (benchmark.json boundary honesty + cache hygiene).
A compatibility audit against the **real** skill-creator eval-viewer + artifacts found the producer was
retyping/overloading the frozen contract. `benchmark.json` `runs[].configuration` is now the **string**
`"default"` (the viewer groups/color-codes on that exact value) instead of an object; `runs[]` is **one
row per trial** (`run_number` + that trial's `expectations[]` + a `result` that counts *expectations*, not
trials); and skillet's `pass^k` moved to the **additive `consistency` block** (the shape real artifacts
established), which is also the offline recompute source (with numeric-`eval_id` coercion so real records
aren't silently dropped). `run` now writes the self-owned `.skillet/.gitignore` before touching the cache
(no accidental forensics commit even without a prior `init`), and the cache run path gains a uuid suffix
(no same-second collision). 218 tests green. No scope/feature change.

## v1.9.4 — 2026-06-30

PATCH — **F7 review round 5** (config strictness + path confinement). The
config-consuming commands (`lint`, `harness info`, `run`) now load `skillet.yaml` through a shared
**strict** loader — a present-but-undecodable repo config, or a missing/undecodable `--config`, fails
loud (exit 2/4) instead of silently falling back to defaults. The skill dir + its `evaluations/` are
**symlink-confined** before any read or write (a symlinked path → exit 4), so a committed symlink can't
redirect a paid run's reads/writes outside the repo. The non-spending `claude auth status` preflight
**fails closed** on malformed output (an unverifiable auth state never spends). `--json --dry-run` now
emits the schema-tagged **`skillet.run-plan/1`** spend-free plan, and `benchmark.json` `runs[]` carry an
additive `pass_rate`. 214 tests green. No scope/feature change.

## v1.9.3 — 2026-06-29

PATCH — **F7 review round 4** (fixture / staging isolation). `files[]` now
allowlists the fixture namespace: `fixtures/**` and `evaluations/fixtures/**` are model-visible, while
everything else under `evaluations/**` (the eval definition, the run-record family, `sessions/`,
`findings/`, `friction/`) is rejected (exit 4) — so an eval can't hand the model under test its own
answers. Bundle + fixture staging switched to a recursive filtered copy that drops hidden files and
symlinks at **any** depth (not just top-level), closing nested `.env`/`.git` leaks. Aligns with the
inputs-vs-targets split in Inspect/lm-eval/promptfoo. 205 tests green. No scope/feature change.

## v1.9.2 — 2026-06-28

PATCH — **F7 review round 3** (security hardening). Eval ids no longer
path-traverse the `.skillet/runs` cache (index-based cache path; the real id stays in records);
**symlinks are rejected** in eval `files[]` fixtures *and* the skill bundle (recursive — no symlink
staged or followed, the escape/leak guard for a paid harness; the only symlinks in real skills are
`.build` build-cruft, so zero migration cost); zero-expectation evals are rejected before spend
(can't measure → exit 4) and a verdict-less trial never passes vacuously; the spend prompt requires
**both** stdin and stdout to be a TTY (else fails like `--no-input`). Added the plan's
evidence-asserting RunKit judge test. 201 tests green. No scope/feature change.

## v1.9.1 — 2026-06-28

PATCH — **F7 review-round hardening** (post-merge code review). Confined eval
`files[]` fixtures to the skill directory (reject absolute / `..` traversal — the standard path-traversal
guard, since a paid harness reads committed evals); coerced **numeric** eval ids into records (were
dropped to positional ids); rejected `--runs < 1` as a usage error; made a **judge-subprocess failure
an ungraded trial**, not a false criterion FAIL; switched skill staging to a **denylist** (exclude
`evaluations/` + hidden `.skillet`/`.git`/`.env`) — keeps real skills' non-standard bundle dirs
(`agents/`, `fixtures/`, `eval-viewer/`) a fixed allowlist would have dropped; refreshed stale test
counts. 195 tests green. No scope/feature change.

## v1.9.0 — 2026-06-28

MINOR — **Phase 1 COMPLETE: F7 (`skillet run`) implemented**, closing the
walking skeleton. The neutral runner runs a skill's evals k×/eval in fresh sandboxes, grades each
expectation with a `claude-code`-backed text judge (existence/claim-mismatch via the post-run
workspace listing + trace), and reports aggregate `pass^k` at observed k = `min` recorded — pure in
`EDDCore` and **recomputable offline from the committed `evaluations/benchmark.json`** (P2/D3). New
targets `RunKit` + `JudgeKit`; spend is estimated up front and gated (`confirm_above_trials`/`--yes`/
`--no-input`/`-n`,`--dry-run`, design P9); exit codes `0/1/2/3/4`; the live claude-code path is one
opt-in env-gated smoke (free CI uses a replay seam). `Specs/007`; 179 tests green. Phase 1 → **Foundation/COMPLETE**,
Phase 2 → **Now**. (Per-feature impl was historically PATCH; bumped MINOR for the horizon shift.)

## v1.8.0 — 2026-06-26

MINOR — **moved `doctor` (F3) from Phase 1 to Phase 2** and **reconciled the
`Fn` identifier scheme across all phases**. `doctor` is off the walking-skeleton critical path (F7
`run` doesn't depend on it) and its companions — the `--paid` canary, the full lint catalog, and
`config list --origins` — are all Phase 2; so F7 becomes Phase 1's only remaining feature. The
scheme reconciliation adopts one global, stable, never-reused, position-independent `Fn` counter (new
*Feature identifiers* section), grounded in stable-ID best practice (Sparx EA, RTEMS req-for-req, Jira
— assign-once / never-renumber / don't-encode-position; links in that section). Minimal-churn: Phase 1's `F1–F8` and
Phase 8's `F10–F13` were already global and were **preserved** (so design/AGENTS/Specs/back-changelog
references stay valid); the local-ordinal Phases 2–7 and Phase 8 items 1–9 received global ids
`F14–F60`; `doctor` keeps `F3`; `F9` is a retired gap. Also **re-deferred the three frontmatter
spec-conformance rules** (name kebab/length, allowed-keys, duplicate-key rejection) from `doctor` to
Phase 2's full lint catalog (F20) — they still surface in `doctor` once they're lint rules. No v1
scope change; no `plan.md` yet (authored at implementation time).

## v1.7.1 — 2026-06-25

PATCH — Phase 1 **F4 (`skillet lint`) implemented**: the free static gate —
`SKILL-L001` (description >1024 Unicode code points, matching Anthropic's `quick_validate.py`),
`SKILL-L003` (body-line budget), `SKILL-L009` (has-evals, ≥3) — as a pure `LintKit` over a
`SkillSource` the executable assembles; `skillet lint` exits 1 on any error-tier finding
(`skillet.lint/1`). Also corrected the stale Global Risks line (F8 was already done; 122 tests;
`Specs/001`–`006`). Phase 1 stays IN PROGRESS (F3 `doctor`, F7 `run` open). Plan:
[Specs/005](Specs/005-free-static-lint/plan.md).

## v1.7.0 — 2026-06-24

MINOR — added **Phase 8 F13 — skill-bundle integrity lint group** (static
checks that bundled `scripts/` are self-contained / non-interactive / `--help`-capable, that
referenced script/asset paths resolve, and that no files are orphaned or outside the spec dirs) —
the second cross-reference lint group beside F12, from Skill-Lab's Structure/Content bundle checks
+ AWS `skill-eval`'s skill-standard-directory scan; no settled-decision touch. Also synced the
stale **Phase 8 overview bullet** to name the security + bundle-integrity groups (design→roadmap
drift surfaced by the F12/F13 adds). Design doc → v0.11 (§13 v1.x). No v1 scope change.

## v1.6.0 — 2026-06-24

MINOR — **adopted held-out proof (R2 / design §14-8)** and graduated it from
*Candidate Enhancements* into **Phase 6 (new F5 [now F45])**: a `skill_md` edit is `proven` only when a
held-out sibling eval (same failure class, not the one it was drafted from) also passes — guarding
against overfit proof and hardening the *corroboration integrity* outcome. Encoded in design §8
(Held-out proof gate), §5.2 (`gates.proof.require_holdout`, default on; advisory per D6, enforced
under `--strict`), §6.1 `iterate --mark`; design doc → v0.10. §14-9/§14-10 stay parked.

## v1.5.0 — 2026-06-24

MINOR — acted on the v0.8 competitive cross-reference under a **strict
evidence bar**. Added **Phase 8 F12 — skill-security lint rules** (security tier in the
`SKILL-Lxxx` catalog: prompt-injection, evaluator-manipulation, unicode-obfuscation,
YAML-anomaly, suspicious-size; from Skill-Lab + AWS `skill-eval` + SkillTester) — the one finding
with no settled-decision touch. **Staged three more as design open questions** (not in the phase
plan until decided), mirrored in the new *Candidate Enhancements* section: §14-8 held-out proof
(R2), §14-9 process-assertions over the `Trace` (R3 + R7 sub-question), §14-10 ablation arms (R5).
Evaluated and **deferred** three: failure-clustering in triage (single, uncertain source —
revisit when Phase 4 is built), a microsoft/skills fixture corpus (a testing asset, not a
research-revealed gap), and reinforcing the autonomous-optimizer non-goal (already covered by the
v0.8 §1 / Appendix C edits). Design doc → v0.9. No v1 scope change.

## v1.4.2 — 2026-06-24

PATCH — **trademark risk narrowed** from the v0.8 design-doc
competitive cross-reference: a June-2026 GitHub sweep found no `skillet` name collision *inside
the eval space* (only PAN's non-eval product family conflicts), so the Global Risks trademark
bullet is updated. Risk register only — the pre-launch trademark check still stands; no phase,
feature, or priority change.

## v1.4.1 — 2026-06-21

PATCH — Phase 1 **F6 (claude-code adapter) implemented** (validatable core):
`ClaudeCodeAdapter` (native-JSONL→`Trace` parser, golden vs a synthetic fixture), `BinaryResolver`,
`Denylist`, and `probe`/`verifySkillVisibility` behind a fakeable launcher; live `run` stays F7.
`swift-yaml` wired isolated in a new `.Cxx` `ConfigYAML` target (kits + pure core stay interop-free;
the executable is a `.Cxx` leaf, per the interop spike). Phase 1 stays IN PROGRESS (F4/F3/F8/F7 open).

## v1.4.0 — 2026-06-21

MINOR — Phase 1 F6/F7 scope re-attributed: claude-code's **live `run`
execution + skill-injection** moved from F6 to F7 (where the opt-in env-gated smoke and a real
claude-code can validate it), because claude-code isn't runnable in this dev/CI environment and the
predecessor port is absent. F6 keeps the validatable core (native-JSONL→`Trace` parser, binary
resolution, denylist, and the `probe`/`verifySkillVisibility` seam). Build order and **Fn** ids
unchanged. Detail in `Roadmap/phase-1-walking-skeleton.md`.

## v1.3.0 — 2026-06-21

MINOR — Phase 1 re-sequenced to a dependency-honest build order:
`skillet doctor` (F3) moved after the HarnessAdapter seam (F5) + claude-code adapter (F6),
because `doctor`'s `probe()`/`verifySkillVisibility` are adapter methods (design §9.1) and it
also needs `swift-yaml` + error-tier lint (F4). New build order: F1, F2, F5, F6, F4, F3, F8, F7
(feature **Fn** ids unchanged — stable across specs and Package targets). Also marked Phase 1
IN PROGRESS and corrected the now-stale "no implementation" assumption (F1/F2 shipped:
`Specs/001`, `Specs/002`). No scope change.

## v1.2.0 — 2026-06-18

MINOR — added **capture secret-sanitization** to Phase 3 (F7 [now F32]):
redact-in-place before write, bundled `betterleaks` (MIT) run offline, fail-closed
when unavailable. Closes the commit-secrets footgun; extends design §12 privacy
(§6.1/§7.2/§11/§12 updated, doc → v0.4).

## v1.1.0 — 2026-06-18

MINOR — added **user-authored declarative YAML lint rules**
to Phase 8 (F11) — a bounded, ReDoS-guarded extensibility capability — governed by
the new design §7.6 "YAML usage policy" (litmus test + verdict table). No existing
phases or priorities changed.

## v1.0.1 — 2026-06-18

PATCH — config file is now `skillet.yaml` (was
`skillet.toml`) in Phase 1 references, matching the design decision to adopt YAML
via the `swift-yaml` package and drop the TOML dependency. No phases, features,
or priorities changed.

## v1.0.0 — 2026-06-17

Initial roadmap created from `skillet-design.md`
(Northstar §1, command surface §6, v1 scope line §13, architecture §11) plus an
external best-practice cross-reference — EDD / error-analysis (Hamel Husain &
Shreya Shankar), AI-agent eval guidance (Anthropic, *Demystifying evals for AI
agents*), the Now/Next/Later framework (ProdPad), and walking-skeleton MVP
sequencing. Horizons are dependency-honest with the Northstar as tie-breaker;
items are capability-centric, anchored to testable CLI increments, and tagged
Ported/Net-new; full arc (v1 → v1.x → Later, plus explicit Non-Goals).
