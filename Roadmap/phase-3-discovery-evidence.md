# Phase 3 — Discovery & Evidence Capture

**Status:** IN PROGRESS (F26 + F32 shipped 2026-07-11)
**Horizon:** Next
**Last Updated:** 2026-06-18

## Goal

Record what actually happens in production — real sessions and the hand-fixes a
human made — as structured, greppable evidence. This is the *Discover* step and
the raw material for error analysis: without a captured corpus and logged
friction, there is nothing to analyze, codify, or prove. Capture is one command
and never blocks (design P4).

## Key Features

1. **[F26]** Capture a session as evidence (CLI: `skillet capture`) — IMPLEMENTED (2026-07-11) · Ported
   - Purpose & user value: Turn the run you just finished into a normalized,
     scored session bundle in one command — the habit only sticks if it's cheaper
     than skipping it.
   - Northstar: gap #1 input (the corpus error analysis reads).
   - Success metrics:
     - `capture --skill <s> --slug <x>` (newest session by default) writes a frozen bundle + additive `*.trace.json` and runs the deterministic scorers into the bundle's SARIF.
     - When corrective turns are detected, the closing line suggests `skillet friction add`.
   - Dependencies: Trace seam + claude-code adapter (Phase 1), scorers (Phase 2).
   - Confidence: Medium — design §6.1 `capture`.

2. **[F27]** Checkpoint & feedback-preserving capture (CLI: `skillet capture --from-checkpoint`, `--preserve-feedback`) — PLANNED · Ported
   - Purpose & user value: Slice a transcript at a checkpoint before the session
     ends, and keep every corrective turn rather than trimming to the final state
     — the open-coding signal that Track B error analysis later depends on.
   - Northstar: gap #1 input (preserves the corrections to be coded).
   - Success metrics:
     - `--from-checkpoint last` produces an in-progress capture plus a `-completed` sibling of the same work.
     - `--preserve-feedback` retains all corrective turns from the first checkpoint to EOF.
   - Dependencies: capture (F26).
   - Confidence: Medium — design §6.1 `capture`, §9.3.

3. **[F28]** Session bundles & corpus management (CLI: `skillet bundle inspect|verify|list|stats|backfill`) — PLANNED · Ported
   - Purpose & user value: Read, schema-check, inventory, and repair the session
     corpus — including SARIF role directionality and additive backfill of missing
     `*.trace.json` / `session-meta.json` — so an accreted corpus stays valid.
   - Northstar: loop integrity (the corpus is the database).
   - Success metrics:
     - `bundle verify` enforces append-only policy and SARIF role directionality.
     - `bundle backfill` writes missing trace + meta using documented proxies (`captured_at` ← date@00:00Z; unknowns ← `"unknown"` sentinel).
   - Dependencies: capture (F26).
   - Confidence: Medium — design §6.2, §7.4.

4. **[F29]** Structured friction & finding evidence + lifecycle (file format `skillet.friction/1`) — PLANNED · Net-new
   - Purpose & user value: One markdown+frontmatter file per event — gate fields
     machine-readable, body human-readable, merge-conflict-free — so evidence is
     greppable, diffable, and reviewable in a PR. Files are the API.
   - Northstar: gap #1 input + differentiator #1 substrate (gates read these).
   - Success metrics:
     - A friction event and a finding validate on read against their schema; hand-edited frontmatter is accepted.
     - The lifecycle `logged → candidate → codified → proven → closed` (with `watch`/`held` side states) is representable and never transitions implicitly.
   - Dependencies: none (EDDCore evidence graph).
   - Confidence: Medium — design §7.3.

5. **[F30]** Friction suite — log & inspect human evidence (CLI: `skillet friction add|list|show|set-state|render`) — PLANNED · Net-new
   - Purpose & user value: Capture "I had to hand-fix this" in ~30 seconds, and
     let a human record judgment — `set-state held|watch` — that the engine reads
     but never infers. The benevolent dictator's interface (design D6).
   - Northstar: gap #1 (human error analysis) + benevolent-dictator principle.
   - Success metrics:
     - `friction add` writes one structured event (TTY prompts / flags / `$EDITOR`) in under a minute.
     - `list` shows the gate dashboard (evidence count, domains, state); `render` regenerates `friction-log.md` as a do-not-edit view.
     - `set-state` records human HELD/WATCH with a required reason; the engine never sets them.
   - Dependencies: evidence format (F29).
   - Confidence: Medium — design §6.1 `friction`.

6. **[F31]** Friction-log migration & knob import (CLI: `skillet migrate friction|knobs`) — PLANNED · Net-new
   - Purpose & user value: The one prose→structure migration — parse a freeform
     `friction-log.md` into structured events with confirmation — plus a trivial
     one-time import of predecessor knob `.txt` files.
   - Northstar: loop integrity (adoption without losing history).
   - Success metrics:
     - `migrate friction --dry-run` shows the full parse plan and writes nothing without confirmation; the original is preserved.
     - `migrate knobs` imports vendored-prefix / vocab-exemption lists into the `[scorers]` tables.
   - Dependencies: evidence format (F29).
   - Confidence: Low — design §6.1 `migrate`; depends on a predecessor log this repo can't verify. `needs-research`

7. **[F32]** Capture secret-sanitization (CLI: `skillet capture` redact-by-default, `--fail-on-secret`) — IMPLEMENTED (2026-07-11) · Net-new
   - Purpose & user value: Stop captured evidence from leaking credentials into the
     committed corpus — capture scans the transcript/diff/bodies and **redacts secrets
     in place** before writing, so the raw secret never enters the repo. Closes a real
     footgun (committing `.env`/tokens/keys) the prior privacy note didn't cover.
   - Northstar: loop integrity (a trustworthy, safely-shareable corpus).
   - Success metrics:
     - A planted AWS key / GitHub token / private key in a session is redacted to a typed marker (`[REDACTED:…]`) in the committed bundle; the raw value appears nowhere in the repo.
     - Default redacts and emits a review report without blocking (P4); `--fail-on-secret` exits non-zero for CI; if the scanner can't run, capture fails closed (never writes an unsanitized bundle).
     - A false positive is silenced with a one-line allowlist/path exemption; redaction provenance is recorded in `session-meta.json`.
   - Dependencies: capture (F26); `betterleaks` **resolved** (config/env/`PATH`) and run via `swift-subprocess` (Phase 1 process seam). **Release-coupled with F26** — capture is exposure-gated on this scanner (no un-scrubbed write path ships).
   - Confidence: Medium — design §6.1 `capture`, §12; engine choice (betterleaks, MIT) per the secrets-scanner cross-reference.
   - Notes: betterleaks is **resolved from config/env/`PATH`** behind a swappable seam (constitution v1.3.0). Per-platform `.artifactbundle` vendoring is deferred (**F69**) and a gitleaks fallback engine is a separate item (**F70**); TruffleHog stays BYO-only (AGPL + network). Runs offline (validation off); the resolved version is recorded in bundle provenance.

8. **[F69]** Secret-scanner `.artifactbundle` vendoring (bundle `betterleaks` per platform/arch) — PLANNED · Net-new
   - Purpose & user value: ship a version-pinned `betterleaks` **inside** the tool so `capture` works
     out-of-the-box and offline on every install — no manual scanner install, reproducible redaction.
   - Northstar: loop integrity (a trustworthy corpus that any install can produce).
   - Success metrics: a SwiftPM `.artifactbundle` binary target ships `betterleaks` for macOS + Linux
     (arm64/x64), checksum-pinned; `capture` uses the vendored copy by default, override chain unchanged.
   - Dependencies: F32 (the resolved-scanner seam). Restores the constitution's original *vendored* intent
     (v1.3.0 deferred delivery, not behavior).
   - Confidence: Medium — blocked only on `.artifactbundle` packaging infrastructure.

9. **[F70]** gitleaks fallback engine (second scanner behind the swappable seam) — PLANNED · Net-new
   - Purpose & user value: a proven, ubiquitous fallback (`gitleaks`, MIT) behind the same `SecretScanner`
     seam, for environments where `betterleaks` isn't available.
   - Northstar: loop integrity (redaction never blocked by one engine's absence).
   - Success metrics: `gitleaks` conforms to the `SecretScanner` seam (findings parsed, same span-merge
     redaction); selected by config; output golden-tested. Additive — no F32 change.
   - Dependencies: F32 (the seam + parser contract).
   - Confidence: Medium — a second parser + resolution entry, no new mechanism.

10. **[F71]** `CapturePipeline` extraction — testable fail-closed ordering — PLANNED · Net-new (architecture)
   - Purpose & user value: extract `capture`'s orchestration (session-resolve → assemble → **scrub** →
     score → write) out of `CaptureCommand` into a `CapturePipeline` in a new top-tier `CaptureKit`, so the
     **fail-closed ordering** — scrub-before-write, refuse-on-scanner-failure, exempt-blanket guard — is
     unit-tested with injected fakes, not only through the capture integration path. (Option C of the
     round-11 review — the Humble Object / ports-and-adapters "testable use-case core".)
   - Northstar: loop integrity (the redact-before-write guarantee proven by fast unit tests, not just e2e).
   - Success metrics: `CaptureKit` hosts the pipeline behind injected seams (adapter/scanner/scorer/writer);
     a `CaptureError` domain enum translates to `EDDError` at the command boundary with **exit codes/remedies
     unchanged**; unit tests assert scrub precedes write and every scanner-failure path fails closed;
     `CaptureCommand` becomes a thin adapter. Best done as a pass that also covers `run`/`doctor` (same shape).
   - Dependencies: F26/F32 (the shipped capture pipeline). Extends round-11 Option B (`GitDiffProvider`,
     `BodyExtractor` already extracted to their kits) — the remaining, orchestration-level slice.
   - Confidence: Medium — mechanical extraction; the risk is the `EDDError`→`CaptureError` inversion
     preserving the exit codes/remedies pinned over 11 review rounds (gated on the integration suite green).

## Dependencies & Sequencing

- Local ordering: capture (F26) **release-couples with** secret-sanitization (F32) — capture is exposure-gated on the real scanner, so the two ship together (no un-scrubbed write path; constitution v1.3.0). Then checkpoint modes (F27) and bundles (F28); evidence
  format (F29) → friction suite (F30) → migration (F31). Scanner `.artifactbundle` vendoring (F69), the gitleaks fallback (F70), and the `CapturePipeline` extraction (F71) are additive follow-ups on the shipped F26/F32 pipeline.
- Cross-phase: this corpus feeds Phase 4 (Error Analysis) and Phase 5 (the gates
  engine reads friction/findings). `--preserve-feedback` (F27) is required for
  Phase 8's Track B axial coding.

## Phase Metrics & Success Criteria

- This phase is successful when: after a real session, a maintainer captures it
  and logs the hand-fix in under two minutes total, and the resulting evidence is
  valid, greppable, and ready for triage and the gates engine.

## Risks & Assumptions

- The migration path assumes a predecessor `friction-log.md` exists; tagged
  `needs-research` until confirmed.

## Phase Change Log

- 2026-07-12: **Post-implementation review round 11 (capture architecture).** Extracted `GitDiffProvider`
  (→ HarnessKit) and `BodyExtractor` (→ CorpusKit) out of `CaptureCommand` and unit-tested them (review
  Option B — the deep, edge-case-heavy leaf logic in existing kits). Added **F71** (`CapturePipeline`
  extraction — the orchestration-level slice / Option C) as a deferred follow-up, scoped to unit-testing
  the fail-closed scrub→write ordering. Corrected the design/AGENTS "~≤50-line command" claim (inaccurate —
  no command is ≤50; commands are thin adapters, orchestration-heavy ones larger). Detail: Specs/013.
- 2026-07-10: **Constitution v1.3.0 ripple** (secret-scanner delivery). F32 `betterleaks` changes from
  *bundled/vendored* to **resolved from config/env/`PATH`** (redact-before-write / fail-closed / offline
  MUSTs unchanged); F32 **release-couples with F26** (capture exposure-gated on the real scanner — no
  un-scrubbed write path ships). Added **F69** (`.artifactbundle` vendoring — the deferred delivery) and
  **F70** (gitleaks fallback engine). Detail: Specs/013–014, `constitution.md` v1.3.0. Roadmap MINOR.
- 2026-06-17: Phase created. Placed before Error Analysis and the Computable
  Runbook to honor the error-analysis-first ordering (capture evidence before
  analyzing or codifying it).
- 2026-06-18: Added F7 [now F32] (capture secret-sanitization — redact-in-place, bundled
  betterleaks, fail-closed). Closes the commit-secrets footgun; design §6.1/§12.
  Roadmap MINOR → v1.2.0.
- 2026-06-26: PATCH — adopted the global stable Fn ids (F26–F32; roadmap v1.8.0 scheme reconciliation). Mechanical renumber; no scope change.
