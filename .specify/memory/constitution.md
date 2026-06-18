<!--
Sync Impact Report:
- Version: N/A → 1.0.0 (Initial constitution)
- Change Type: Initial creation
- Scope: skillet repository (/Users/csjones/Developer/skillet) — the SKILL.md Evaluation Toolkit, a public, open-source, multi-harness Swift CLI for eval-driven development (EDD) of agent skills
- Orientation: This constitution governs HOW WE DEVELOP skillet (engineering process and
  non-negotiable development standards). It is orthogonal to — and deliberately distinct from —
  the design doc's product principles (P1–P10) and settled decisions (D1–D7), which capture the
  CLI's intended behavior. The two overlap but serve different masters: skillet-design.md is the
  product spec; this constitution is the development charter. Appendix A cross-maps the two.
- Core Principles (7, refactored from an initial 7-candidate set after best-practice research):
  I. Spec-First & Test-Driven Development
  II. Evidence-Driven & Trustworthy Measurement
  III. Deterministic Core & Stable Contracts
  IV. Human- and Agent-First, Composable CLI
  V. Cross-Platform CI & Quality Gates
  VI. Security, Privacy & Dependency Hygiene
  VII. Open Source Excellence
- Enforcement: Three-tier model (MUST / SHOULD / MAY) with explicit MUST NOT
- Governance: 21-DOT-DEV maintainer (BDFL) model; security/contract-relevant change protocols
- Best-practice sources folded in: clig.dev (CLI design); Husain & Shankar, "A Field Guide to
  Rapidly Improving AI Products" / AI Evals (error-analysis-first, trustworthy measurement,
  criteria drift); LLM-as-a-judge calibration literature (judge overconfidence, judge-prompt
  versioning, human-label alignment)
- Templates status:
  ⚠ .specify/templates/* — none present in this repo yet; create + align when speckit templates
    are introduced (plan/spec/tasks/checklist)
- Companion artifact: AGENTS.md (repo root) — operational onboarding for AI agents and humans;
  references this constitution as authoritative for principles (reference-not-duplicate). Kept in
  sync via the reciprocal note in both files (Governance › AGENTS.md Maintenance below).
- Contributing / Security / Code of Conduct: handled at the org level
  (https://github.com/21-DOT-DEV/.github) — no repo-local copies needed.
- Follow-up TODOs:
  • Resolve license question: repo LICENSE ships MIT; design §14 Q2 recommends Apache-2.0 —
    decide before public launch (Governance › Deferred Decisions)
  • Trademark sanity check against Palo Alto Networks "Skillet" family before public launch
    (design D7 / Appendix C)
-->

# Constitution for skillet

## Preamble

This constitution governs the development of **skillet** — the SKILL.md Evaluation Toolkit — a
public, open-source, multi-harness Swift CLI that turns eval-driven development (EDD) for agent
skills into software.

**Scope**: This repository only. It covers the Swift package (`EDDCore` and the effectful layers
above it), the `skillet` CLI, the boundary file formats, the harness adapters, and all supporting
documentation and CI.

**Orientation**: This document defines **how we build skillet**. It is intentionally orthogonal
to `skillet-design.md`, which defines **what skillet does** (product principles P1–P10, settled
decisions D1–D7). When this constitution and the design doc overlap, they reinforce each other;
when they appear to conflict, the design doc governs *product behavior* and this constitution
governs *development practice*. Appendix A maps the two so neither drifts from the other.

**Philosophy**: skillet is a deterministic-core CLI with frozen boundary contracts, multi-harness
adapters, and a never-auto-commit safety rule. Correctness of the loop, trustworthiness of
measurement, and simplicity take precedence over breadth of features.

---

## Core Principles

### I. Spec-First & Test-Driven Development

**Statement**: Every feature MUST begin with a specification and proceed by test-driven
development: tests written first, verified to fail, then implementation makes them pass.

**Rationale**: Specs align work with user-facing value and provide measurable success criteria.
TDD prevents regressions, enables confident refactoring of the net-new surface (gates engine,
evidence lifecycle, `next`), and documents expected behavior as executable assertions.

**Practices**:
- **MUST** create a spec for every feature before implementation; the spec describes user-facing
  behavior and acceptance criteria, not implementation details.
- **MUST** scope each spec to a single feature or small, independently testable increment.
- **MUST** write tests before implementation (red → green → refactor) and verify they fail first.
- **MUST** validate boundary codecs against golden fixtures and pipelines against recorded
  `HarnessReplay` fixtures (see Principle III).
- **MUST NOT** combine multiple unrelated features in one spec.
- **MUST NOT** mark a task complete while its tests fail, are missing, or pass without ever
  having failed.
- **SHOULD** develop outside-in, from the user's (or operating agent's) perspective first.
- **MAY** add property-based tests for pure functions (gates engine, scorers, aggregation).

**Compliance**: PRs MUST include tests written first. Specs that bundle unrelated features MUST be
rejected in review.

---

### II. Evidence-Driven & Trustworthy Measurement

**Statement**: Behavior changes MUST be driven by discovered evidence, never imagined failure
modes; and any delta the tool reports MUST rest on measurement that is demonstrably sound.

**Rationale**: Error analysis — looking at real traces and categorizing real failures — is the
highest-ROI activity in improving any LLM system (Husain & Shankar). The corresponding hazards are
equally well documented: LLM judges are systematically overconfident, and evaluation criteria
*drift* as more outputs are reviewed. skillet exists to make the trustworthy path the default; its
own development MUST hold to the same standard it sells.

**Practices**:
- **MUST** ground new evals, lint rules, and fix logic in captured evidence (the corpus, friction
  events, triage findings), not in speculation — "codify what you discover, not what you imagine."
- **MUST** treat a previously-failing eval that now passes as the proof obligation for any change
  that claims to fix a behavior; corroboration precedes codification.
- **MUST** keep the scorer↔judge contradiction join correct and surfaced first: a deterministic
  scorer and the judge disagreeing on the same expectation outranks the raw pass rate.
- **MUST** version judge prompts (`judge_prompt_version`) and require an explicit judge model so
  results are reproducible and re-gradable offline.
- **MUST** distinguish measurement from noise: infrastructure (no-terminal-event) failures are
  retried and stamped; judged FAILs are never retried; trial exit class is first-class in records.
- **MUST NOT** let TTY presentation or a favorable-looking number substitute for a sound estimate.
- **SHOULD** prefer free, deterministic gates (lint, scorers) before any paid model judging.
- **SHOULD** guard against criteria drift by recording the critique alongside binary verdicts and
  preserving corrective-turn signal where the loop depends on it.
- **MAY** add a judge↔human-label calibration harness as the rigorous extension of this principle.

**Compliance**: PRs that change graded behavior MUST cite the evidence and the proving eval.
Changes to judging or contradiction logic require explicit review.

---

### III. Deterministic Core & Stable Contracts

**Statement**: The core (`EDDCore`) MUST be pure, synchronous, and unit-tested, with everything
probabilistic or effectful isolated behind protocols above it; and skillet's external contracts
(boundary file formats, `--json` payloads, exit codes) MUST be stable and enforced by tests.

**Rationale**: Determinism is what makes the gates engine, scorers, aggregation, and trace parsing
testable rather than aspirational. Frozen contracts are what let a corpus, a downstream script, or
an operating agent depend on skillet across versions. Both are load-bearing for the whole tool.

**Practices**:
- **MUST** keep `EDDCore` pure and synchronous; it spawns no processes and performs no I/O beyond
  reading the inputs handed to it.
- **MUST** place all model calls, process execution, network, and filesystem effects behind
  protocols in the effectful layers (HarnessKit, JudgeKit, etc.), each record/replayable.
- **MUST** treat frozen boundary formats (`evals.json`, `trigger-eval.json`, `benchmark.json`,
  SARIF 2.1.0, session bundles) as never-break contracts, enforced by golden fixtures in CI.
- **MUST** enumerate *all* decoded fields in golden fixtures and round-trip unknown keys rather
  than dropping them on re-encode (an omitted field is an unenforced freeze).
- **MUST** carry a `schema` field on every `--json` payload; JSON changes are additive within a
  major version.
- **MUST** treat exit codes as a stable API.
- **MUST NOT** break a frozen format, rename/remove/retype a bundle field, or change an exit code
  without a major version bump and migration notes.
- **SHOULD** add new bundle *files* (additive) rather than mutating existing ones.
- **MAY** accelerate with a gitignored cache, but the cache MUST never originate state —
  everything MUST remain recomputable from committed repo files.

**Compliance**: CI fails if codecs produce or reject anything the goldens do not. PRs touching
`EDDCore` MUST include or update unit/property tests.

---

### IV. Human- and Agent-First, Composable CLI

**Statement**: skillet MUST be usable by humans *and* by AI agents without memorizing every
command: human-readable TTY output paired with machine-stable contracts, discoverable affordances,
errors that teach, composable plumbing, and onboarding documentation agents can act on.

**Rationale**: skillet is a tool for maintaining agent skills, so it should itself be operable by
an agent (and by a newcomer who has not read the manual). The CLI-design canon (clig.dev) and the
agent ecosystem agree: ease of discovery, consistency, robustness, and a machine-stable surface are
what let both a person and a program drive a tool confidently.

**Practices**:
- **MUST** offer human-first TTY output for people AND `--json` (with `schema`) for programs and
  agents on every command (P7).
- **MUST** support `-h`/`--help` on every command, lead help with examples, and surface the most
  common flags first.
- **MUST** end command output by suggesting the next sensible command, so the workflow is
  self-revealing (progressive disclosure).
- **MUST** make every failure message state what went wrong, why, and the exact command that fixes
  it; never fail silently (the `--skill-path` false-negative class is extinct by construction).
- **MUST** keep porcelain verbs thin compositions of stable, independently usable plumbing — any
  porcelain action MUST be reproducible with plumbing + `--json`.
- **MUST** maintain a root `AGENTS.md` (plus scoped `AGENTS.md` files where a directory needs
  deltas) so an operating agent can discover commands, contracts, and boundaries without reading
  source — kept in sync when commands, flags, or contracts change.
- **MUST NOT** treat human TTY output as an API or require interactive prompts on a path an agent
  or script must take (`--yes` MUST exist for confirmations; `--dry-run` MUST exist to preview).
- **SHOULD** follow established CLI conventions for naming, exit-on-error, and signal handling.
- **MAY** ship shell/command completion to further lower the discovery cost.

**Compliance**: Reviews verify `--json`, `-h/--help`, teaching errors, and AGENTS.md updates for
every new or changed command.

---

### V. Cross-Platform CI & Quality Gates

**Statement**: skillet MUST build and pass its free test suite on every supported platform in CI,
behave deterministically across environments, and gate merges on automated quality checks — with
free, deterministic checks running before any paid one.

**Rationale**: "CI in this repo *is* the Linux user." Cross-platform reliability and determinism
are core to a tool whose entire value proposition is trustworthy, reproducible measurement; spend
discipline (free-before-paid) is both an economic and a correctness safeguard.

**Practices**:
- **MUST** build and test on macOS 14+ and current Ubuntu LTS in CI.
- **MUST** keep the default CI path free: pure unit/property tests, golden codecs, and
  `HarnessReplay` fixtures — no paid model calls on every PR.
- **MUST** gate merges on build, the free test suite, and lint/format checks all passing.
- **MUST** ensure deterministic behavior: identical inputs produce identical outputs across
  platforms for all pure components.
- **MUST NOT** merge code that breaks any supported platform or that makes the default CI path
  spend money.
- **SHOULD** run at most one opt-in, env-gated live smoke job per adapter; everything else runs
  free.
- **SHOULD** keep boundary goldens authoritative — a CI failure there is a real contract breach,
  not flakiness to be silenced.
- **MAY** add scheduled (non-PR) jobs for heavier or paid validation.

**Compliance**: The CI pipeline enforces all MUST-level gates; platform or golden failures block
merge.

---

### VI. Security, Privacy & Dependency Hygiene

**Statement**: skillet MUST protect secrets, preserve user privacy, never write to a user's skill
or git history without explicit human action, and keep its dependency and process-execution surface
minimal and sanctioned.

**Rationale**: skillet captures real production sessions (which leak credentials) and commits a
corpus; a single unsanitized bundle is a real breach. A tiny, audited dependency surface and a
single sanctioned way to launch processes keep the supply-chain and execution risk legible.

**Practices**:
- **MUST** sanitize secrets before writing any captured bundle — redact in place with typed
  markers; the raw secret never enters the repo.
- **MUST** fail closed: if the secret scanner cannot run, capture refuses to write rather than
  emitting an unsanitized bundle, and offers a remedy.
- **MUST** run the bundled secret scanner detection-only and fully offline; its network validation
  step MUST stay disabled.
- **MUST NOT** emit, log, or commit secrets, private keys, tokens, or onion/control credentials —
  not in output, error messages, or the corpus.
- **MUST NOT** auto-commit, ever, and MUST NOT edit a live `SKILL.md` except via the explicit,
  opt-in `suggest --apply` content-anchored path (which refuses a dirty tree and stops short of the
  commit). `iterate` operates only in throwaway worktrees.
- **MUST NOT** add telemetry or make network calls except to providers the user configured.
- **MUST** launch every subprocess through `swift-subprocess` — the single sanctioned launcher; no
  `Foundation.Process`, no raw `posix_spawn`.
- **MUST** confine all process execution and effects to the effectful layers; `EDDCore` spawns
  nothing.
- **MUST NOT** auto-probe other applications' private caches or binaries (the harness ban policy).
- **MUST NOT** add a new runtime or development dependency without a constitutional amendment and
  explicit justification. The sanctioned runtime/build deps are `swift-argument-parser`,
  `swift-yaml`, `swift-subprocess`, the standard library, and the per-platform vendored
  `betterleaks` companion; the cache MAY use the system SQLite library.
- **SHOULD** estimate paid trials up front and confirm before spending (TTY) or require `--yes`
  (scripts) — spend is visible and consented.
- **SHOULD** record redaction provenance (scanner, version, count) in bundle metadata.

**Compliance**: Code review MUST verify secret handling, the no-auto-commit rule, and the launcher
discipline. CI scans for obvious violations (logging patterns, forbidden process APIs).

---

### VII. Open Source Excellence

**Statement**: skillet MUST follow open-source best practices: clear documentation, welcoming
contribution and disclosure paths, explicit licensing, and simplicity over cleverness.

**Rationale**: skillet is a public tool whose adoption depends on legibility. Good docs and simple,
readable code lower friction for both human contributors and the agents that will operate it.

**Practices**:
- **MUST** maintain a clear README with install (GitHub Releases, Homebrew tap, Mint,
  `swift build`), setup, and usage examples.
- **MUST** maintain `AGENTS.md` (root + scoped) as first-class onboarding for AI agents and humans
  (cross-referenced with Principle IV).
- **MUST** rely on the org-level contribution, security-disclosure, and code-of-conduct documents
  at [`21-DOT-DEV/.github`](https://github.com/21-DOT-DEV/.github); add repo-local copies only if a
  skillet-specific deviation is needed.
- **MUST** include a `LICENSE` file (currently MIT — see Governance › Deferred Decisions).
- **MUST** document every public type and command and keep documentation in sync with behavior.
- **MUST** apply KISS and DRY; readability over cleverness.
- **MUST NOT** let documentation drift from shipped behavior (stale docs are a defect).
- **SHOULD** provide issue/PR templates and respond to contributions promptly and respectfully.
- **SHOULD** document the stability tiers (frozen formats, exit codes, `--json`, command/flag
  semver, no-promise TTY) prominently.
- **MAY** count experiments rather than features when planning the roadmap.

**Compliance**: PRs MUST include documentation and `AGENTS.md` updates for new or changed
behavior. Reviews enforce readability and KISS/DRY.

---

## Implementation Guidance

### Security Disclosure Process

- **MUST** point reporters to the org-level `SECURITY.md` at
  [`21-DOT-DEV/.github`](https://github.com/21-DOT-DEV/.github) for reporting instructions and
  contact method; add a repo-local `SECURITY.md` only for a skillet-specific deviation.
- **MUST** honor the org's acknowledgment timeline and coordinated-disclosure commitment.
- **SHOULD** acknowledge reporters in release notes (with permission).

**Contract- and security-relevant changes** (secret handling/sanitization, boundary-format
edits, exit-code or `--json` schema changes, the no-auto-commit/`--apply` path, the harness ban
policy, dependency or launcher changes):
- **MUST** document the implications in the PR description (audit trail).
- **SHOULD** allow a brief community-review window before merge for non-trivial cases.

### Repository State Discipline (P2/P3)

- All workflow state **MUST** be derived from committed files under `evaluations/`; the `.skillet/`
  cache **MAY** accelerate but **MUST NOT** originate state. Deleting the cache MUST lose nothing.

### swift-yaml Usage Policy (design §7.6)

- YAML is for human-editable **policy**, never **behavior**. A surface may be expressed as YAML
  only when the design §7.6 litmus test holds; otherwise it stays Swift. `skillet config set`
  rewrites targeted lines in place (swift-yaml does not preserve comments on re-emit).

---

## Technology Stack (Current Implementation)

**Note**: This constitution defines technology-agnostic development principles. This section
records current choices, which may change without a constitutional amendment unless a principle
binds them (e.g., the sanctioned-dependency list in Principle VI).

### Supported Platforms (design §12)

- **macOS** 14+
- **Linux** (current Ubuntu LTS)

### Current Stack

- **Language**: Swift 6 (strict concurrency)
- **Build**: Swift Package Manager
- **CLI framework**: `swift-argument-parser`
- **Config / evidence frontmatter**: `swift-yaml` (YAML 1.2; replaces Yams; no TOML dependency)
- **Process execution**: `swift-subprocess` (sole sanctioned launcher)
- **JSON / SARIF / frozen formats**: Foundation `Codable` (no added dependency)
- **Secret scanning**: vendored `betterleaks` (MIT), per platform/arch, offline detection-only
- **Cache**: system SQLite (cache only)
- **Testing**: Swift Testing / unit + property tests; golden fixtures; `HarnessReplay` fixtures

### Package Architecture (design §11)

`EDDCore` (pure) → TraceKit → { HarnessKit, JudgeKit, ScoreKit, LintKit, CorpusKit } →
AnalysisKit / RunKit / IterateKit → `skilletCLI` (wiring only, ~≤50 lines per command).

### Adapters (v1)

`claude-code`, `opencode`, `direct-api`, `replay`.

---

## Governance

### Authority

This constitution supersedes ad-hoc development practices. Deviations MUST be explicitly justified
and approved. The design doc (`skillet-design.md`) remains authoritative for product behavior;
this constitution is authoritative for development practice.

**Model**: 21-DOT-DEV maintainer (BDFL). The maintainer may amend this constitution directly;
the community proposes changes via GitHub issues.

### Amendment Process

1. Propose the amendment with rationale and impact analysis.
2. Update the version per semantic versioning:
   - **MAJOR**: Backward-incompatible governance changes or principle removals/redefinitions.
   - **MINOR**: A new principle or materially expanded guidance.
   - **PATCH**: Clarifications, wording, or non-semantic refinements.
3. Update dependent artifacts (`.specify/templates/*` once they exist, `AGENTS.md`, README).
4. Record the change in the Sync Impact Report and Version History.
5. Commit with a descriptive message.

### Compliance Review Triggers

| Trigger | Action |
|---|---|
| Adding/removing a runtime or dev dependency | Full Principle VI review + amendment |
| Adding or changing a harness adapter | Capability-flag + ban-policy + visibility-contract review |
| Editing a frozen boundary format / exit code / `--json` schema | Principle III contract review; semver impact |
| Changing secret handling, sanitization, or the `--apply`/no-commit path | Security review (Principle VI) |
| Changing judging, contradiction join, or gate thresholds | Principle II review |
| New or changed command/flag | Principle IV review + AGENTS.md/README sync |

### Stability Tiers (design §12)

| Tier | Contract |
|---|---|
| Frozen boundary formats | Never break (golden-tested) |
| Exit codes | Stable API |
| `--json` payloads | Versioned via `schema`; additive within a major |
| Command names & documented flags | Semver: breaking ⇒ major (pre-1.0: minor + CHANGELOG notes) |
| Human TTY output | No promise — explicitly not an API |

### Versioning & Stability (product, pre-1.0)

- **Pre-1.0**: breaking command/flag changes land as minor bumps with CHANGELOG migration notes.
- **Post-1.0**: strict semver; breaking changes require a major bump.

### AGENTS.md Maintenance (sync contract)

The repo-root `AGENTS.md` is the operational onboarding layer for AI agents and humans; this
constitution is the development-principle layer. They are kept in sync, not duplicated:

- `AGENTS.md` **MUST** reference this constitution as authoritative for principles and **MUST NOT**
  duplicate principle text (duplication causes drift); it carries only a distilled, action-time
  Boundaries list and current/Planned operational guidance.
- When a principle, the sanctioned-dependency list (Principle VI), a boundary contract
  (Principle III), or a command/flag (Principle IV) changes, the **same PR MUST update `AGENTS.md`**.
- `AGENTS.md` describes **current reality**; as each roadmap phase lands, its "Planned" content is
  promoted to verified guidance and its status banner updated.

### Deferred Decisions

- **License**: the repo `LICENSE` currently ships **MIT**; design §14 Q2 recommends **Apache-2.0**
  (patent grant; Swift-ecosystem norm). Resolve before public launch and update Principle VII.
- **Trademark**: a sanity check against Palo Alto Networks' "Skillet" family is required before a
  public launch (design D7 / Appendix C).

### Enforcement

- PR reviewers verify constitutional alignment.
- CI enforces MUST-level gates (blocking) and surfaces SHOULD-level items (warnings).
- Three-tier enforcement: **MUST** blocks merge · **SHOULD** warns and requires override
  justification · **MAY** is informational.

---

## Version History

**Version**: 1.0.0
**Ratified**: 2026-06-18
**Last Amended**: 2026-06-18

**Changelog**:
- **1.0.0** (2026-06-18): Initial constitution. Seven development-governance principles with
  three-tier enforcement, 21-DOT-DEV (BDFL) governance, contract/security-relevant change
  protocols, and a stability-tier table. Principles refactored after best-practice research to
  give Evidence-Driven Measurement and Human-/Agent-First CLI first-class billing. Contributing /
  security / code-of-conduct delegated to the org `.github`; companion repo-root `AGENTS.md`
  authored with a reciprocal sync contract (reference-not-duplicate).

---

## Appendix A — Mapping to the Design Doc & Best-Practice Sources

This constitution (development practice) is orthogonal to but reinforces `skillet-design.md`
(product behavior). The table shows where each development principle draws on the design doc's
product principles (P) / decisions (D) and external best practice.

| Constitution principle | Design doc (product) | External best practice |
|---|---|---|
| I. Spec-First & TDD | (process; complements all) | Speckit / spec-driven dev |
| II. Evidence-Driven & Trustworthy Measurement | P4, P10; §8 contradiction join; §9.3 | Husain & Shankar (error-analysis-first, criteria drift); LLM-judge calibration literature |
| III. Deterministic Core & Stable Contracts | P2, P8; D3, D5; §7.2, §11 | Frozen-contract / golden-file testing |
| IV. Human- & Agent-First, Composable CLI | P1, P3, P6, P7; D2 | clig.dev (human-first, discovery, robustness); AGENTS.md convention |
| V. Cross-Platform CI & Quality Gates | P8, P9; §10, §11, §12 | Flaky-test hygiene; free-before-paid spend discipline |
| VI. Security, Privacy & Dependency Hygiene | P5, P9; D6; §6.1, §11, §12 | Supply-chain minimalism; secret-scanning fail-closed |
| VII. Open Source Excellence | D1; §12 | Open-source norms; roadmap-as-experiments |

**Settled decisions (D1–D7)** remain product invariants owned by the design doc; this constitution
assumes them and does not relitigate them.
