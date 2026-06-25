# `skillet` — the SKILL.md Evaluation Toolkit
## Design Document — eval-driven development (EDD) for agent skills

| | |
|---|---|
| **Status** | Draft v0.11 — for review |
| **Name** | `skillet` (settled — SKILL · E · T, the *SKILL.md Evaluation Toolkit*); EDD remains the methodology's name |
| **Deliverable** | Public, open-source, multi-harness Swift CLI |
| **Supersedes** | The repo-private `swift-skill-eval` tool + the Python trigger harness |
| **Decision provenance** | §2 — every load-bearing choice here was settled in the design Q&A |
| **Revision log** | v0.11 (2026-06-24): §13 v1.x adds **skill-bundle integrity lint rules** (`scripts/`/asset/reference checks) — a second cross-reference lint group beside skill-security (F12), from Skill-Lab's Structure/Content bundle checks + AWS `skill-eval`'s skill-standard-directory scan; no settled-decision touch. Mirrored as ROADMAP Phase 8 F13. v0.10 (2026-06-24): **adopted §14-8 (held-out proof, R2)** — a `skill_md` edit is `proven` only when a held-out sibling eval (same failure class, not its drafting eval) also passes, guarding against overfit proof: new **Held-out proof** gate (§8), `gates.proof.require_holdout` knob (§5.2, default on; advisory per D6, enforced under `--strict`), and the `iterate --mark` step (§6.1). No schema change. Graduated from Candidate Enhancements into ROADMAP Phase 6 (F5); §14-9/§14-10 (process-assertions, ablation) remain open. v0.9 (2026-06-24): staged three competitive-cross-reference enhancements as **open questions** (recommendation given, no decision yet) — §14-8 held-out proof for edits (R2 — a sibling/held-out proving eval to close the circular-proof gap in corroboration integrity), §14-9 deterministic process-assertions over the `Trace` (R3, incl. the R7 metrics/events-split sub-question), §14-10 ablation arms (R5 — partial-skill A/B); all **pending sign-off** and mirrored in ROADMAP's *Candidate Enhancements*. §13 v1.x adds skill-security lint rules (R1 — the one cross-reference item with no settled-decision touch). Proposals only — no gate, contract, or scope change until decided. v0.8 (2026-06-24): competitive landscape refresh from a GitHub cross-reference — Appendix C.1 adds `skill-eval-harness` (closest architectural sibling: paired/ablation arms + normalized-trace process assertions + runner adapters), `alibaba/skill-up`, `SkillOpt` (~9k★), `EvoSkill` (~1k★), and `Skill-Lab`; the C-note now records that the space heats up yet none owns the production loop, that deterministic pre-judge static checks are table-stakes (a principle, not a differentiator), and that no eval-space `skillet` name collision exists. §1 tightens the harness-matrix claim (others now run multi-harness; none prints a per-harness pass^k table off a normalized-trace seam) and adds a positioning row contrasting skillet's human-lands stance with the autonomous optimizers (SkillOpt/EvoSkill). Landscape/positioning only — no decision, scope, or schedule change. v0.7 (2026-06-23): vendored-copy finder (§6.2 `harness which --search`, §9.1 resolution chain) fixed — it now selects the **highest non-denylisted `--version`** (newest-mtime only as a tiebreaker), not raw newest-mtime. Surfaced while validating F6 against 16 cached claude copies in an editor's npx tree (incl. the denylisted `2.1.143`), where newest-mtime could have returned a banned or older-versioned binary. v0.6 (2026-06-21): swift-yaml interop-containment validated during F6 implementation — wired isolated in the new `.Cxx` `ConfigYAML` target (decodes config → `EDDCore.SkilletConfig`); C++ interop proved **viral to direct importers**, so the `skillet` executable is a `.Cxx` leaf while `EDDCore` + all kits stay interop-free (§11 implementation notes 1–2 updated). v0.5 (2026-06-20): clig.dev conformance reconciliation — re-verified against the live guidelines and closed gaps: §5.2 environment-variable conventions; §5.3 `--version`, `--no-input`, `-n`, and color completeness (`TERM=dumb`, `--no-color`); §5.5 responsiveness/progress and pager; §6.3 + §11 support/bug-report path and bounded Ctrl-C cleanup; §12 uninstall. Appendix B rebuilt from prose into a complete, sectioned checklist; Appendix D citation broadened. Two reconciliations that touch settled choices were decided in review: `--plain` (P7) **deferred** (Open Question 6); the user-level XDG **preferences** tier **adopted** — a user-config tier added to §5.2 precedence (§7.1, §7.5), with D3 scoped to workflow state and the gitignored cache kept repo-local. v0.4 (2026-06-18): added `capture` secret-sanitization — redact-in-place before write, bundled `betterleaks` (MIT) run offline via `swift-subprocess`, fail-closed when unavailable; extended §12 privacy to secrets-in-evidence (touches §6.1, §7.2, §11, §12). v0.3 (2026-06-18): config format moved TOML→YAML (adopt `swift-yaml`, drop the TOML dependency); standardized all process execution on `swift-subprocess`; added §7.5 artifact & file-format reference and the §7.6 YAML usage policy. v0.2: renamed to `skillet`; applied the cross-implementation review (findings 1.1–4.7 + appendices); P5 amended; proposal format changed to content-anchored edits. v0.1: initial design |

---

## 1. Purpose & positioning

`skillet` is a command-line tool that turns the **production-as-eval methodology** into software: every real run of a skill can be captured, every hand-fix becomes structured evidence, and a SKILL.md edit ships only after it is corroborated and proven by a previously-failing eval. The runbook stops being prose you must remember and becomes state the tool computes.

**Northstar.** *Close the feedback loop into actionable SKILL.md iterations as fast as reasonably possible, without cutting corners.* Its two highest-value gaps, in order: (1) error-analysis / pattern discovery, and (2) AI-assisted fix suggestion. Every design choice below should be traceable to one of these or to loop integrity.

**What it is for.** Anyone maintaining `SKILL.md` skills — for Claude Code, Codex, OpenCode, or any agentskills.io-style harness — who wants their skills to improve from real usage without calcifying around one bad run.

**What it is not.** Not a skill *authoring* assistant (skill-creator owns creation), not a generic LLM eval framework (promptfoo et al. own that), and not a CI gatekeeper by default (gates advise; `--strict` is opt-in).

**Position in the ecosystem.**

| Tool | Occupies | `skillet`'s relation |
|---|---|---|
| `agent-skills-eval` | Neutral with/without-skill test runner | `skillet run` matches that capability on day one, with zero setup — then the workflow layer goes beyond it |
| Anthropic `skill-creator` | In-agent creation + eval + description optimizer | `skillet` reads/writes its file formats unchanged; complementary, not competing |
| OpenAI eval-skills guidance | Methodology prose | `skillet` is that methodology, executable |
| `SkillOpt` / `EvoSkill` | Autonomous skill *optimizers* — auto-accept on a held-out score / auto-commit edits | `skillet` drafts and proves, but **a human lands every write**; the human-owns-writes stance is the deliberate opposite |

The fuller June-2026 landscape — including general-purpose eval CLIs and two newly discovered `skill-eval` name collisions — is Appendix C.

**The two features that justify a new tool.**

1. **The computable runbook.** Friction events and triage findings carry machine-readable gate fields; a deterministic rules engine derives corroboration counts, distinct-domain de-dupe, and HELD/WATCH state from repo files alone. `skillet next` is EDD's `git status`: it tells you, with reasons, the single highest-value action and the exact command to run it.
2. **The harness matrix.** `skillet run --harness claude-code,opencode` executes the same suite through multiple agents and prints a per-harness pass^k portability table — “passes on Claude Code, flakes on OpenCode.” Other tools now *run* a skill across harnesses (SkillOpt’s results grid; `alibaba/skill-up`’s engine flag), but none reports a **per-harness pass^k table off a normalized-trace adapter seam** — and only a design that is multi-harness from day one can.

---

## 2. Decisions already made

These were settled explicitly during design elicitation and are **not** open for casual relitigating inside this doc; changing one means revisiting its dependents.

| # | Decision | Consequence |
|---|---|---|
| D1 | **Public open-source tool** | `init` scaffolding, config story, schemas assume nothing about any one repo, single-binary distribution, stability promises |
| D2 | **Layered: opinionated workflow is the identity, neutral runner is the entry point** | Porcelain/plumbing split; `run` works statelessly in any skills repo; workflow commands light up as artifacts accumulate |
| D3 | **Repo files are the only state** | No database, no daemon; all workflow state derived from committed artifacts; a gitignored cache may accelerate, never originate. User-level *preferences* (XDG config, §5.2) are configuration inputs — like flags and env — not state: they tune defaults and never originate evidence, gate, or run state |
| D4 | **Multi-harness from day one** | `HarnessAdapter` protocol with capability flags; normalized trace schema designed now; judge decoupled from task harness |
| D5 | **Wire-compatible at the boundaries, greenfield at the core** | `evals.json`, `trigger-eval.json`, `benchmark.json`, SARIF 2.1.0, session bundles: frozen contracts with golden-file tests. Friction/gate state: new structured format. `migrate` exists for the friction log only |
| D6 | **Gates advise, never silently enforce** | Human-only judgment and git commits; `--strict` exists for CI opt-in |
| D7 | **Name: `skillet`** (the SKILL.md Evaluation Toolkit); EDD stays the methodology term | Binary/config/env are `skillet`-branded; the spine, gates, principles, and `EDDCore` keep their EDD names |

---

## 3. Design principles

**P1 — Porcelain over plumbing, like git.** Workflow verbs (`run`, `capture`, `triage`, `next`, `iterate`) are thin compositions of stable plumbing (`grade`, `score`, `bundle`, `gate eval`). Anything porcelain can do, a script can do with plumbing and `--json`.

**P2 — Stateful feel, stateless substance.** Every piece of workflow knowledge is recomputable from files in `evaluations/`. Delete `.skillet/` (the cache) at any time; nothing is lost. This is what makes the workflow layer trustworthy: state is greppable, diffable, reviewable in a PR.

**P3 — Progressive disclosure.** A newcomer types `skillet run` in a repo with one `evals.json` and gets value in thirty seconds, never having heard of gates. The friction → triage → next → iterate loop reveals itself as artifacts accumulate, and every command's output ends by suggesting the next sensible command.

**P4 — Fast on capture, slow on write.** Capturing evidence is one command and never blocks. Changing a SKILL.md is deliberately gated: corroborated, codified as a failing eval, proven by the eval passing with no pass^k regression. The tool makes the slow path *convenient*, not optional-feeling.

**P5 — Human-only writes to the skill** *(amended in v0.2)*. `skillet` never commits — absolute, no exceptions. "Never edits a live SKILL.md" relaxes to "never **by default**": `suggest --apply` is the explicit opt-in that materializes a reviewed proposal into the working tree through content-anchored application (§7.3), refusing a dirty tree and stopping short of the commit. The net is safer, not looser — the default path still only emits a proposal, and `--apply` merely automates the apply step the human previously ran by hand. `iterate` continues to work only in throwaway worktrees.

**P6 — Errors teach.** Every failure message states what went wrong, why, and the command that fixes it. The `--skill-path` class of silent false-negatives is extinct by construction: skill visibility is the adapter's job and `doctor` verifies it before any paid run.

**P7 — Human-first output, machine-stable contract.** TTY output is for people and carries no compatibility promise. `--json` exists on every command, every JSON payload carries a `schema` field, and exit codes are stable API.

**P8 — Determinism where determinism is possible.** The gates engine, scorers, aggregation, and trace parsing are pure functions with unit tests. Only task execution and judging touch a model — and both are recordable/replayable.

**P9 — Spend is visible and consented.** Paid trials are estimated up front; large runs confirm before spending (TTY) or require `--yes` (scripts).

**P10 — The methodology ships as defaults, not dogma.** Gate thresholds (3–5 evidence, ≥3 sessions, ≥2 domains, k=3 *requested* trials) are the shipped defaults in config, tunable per repo — and there is no universal k floor; choose k by the variance you need to detect. Opinionated ≠ unconfigurable.

---

## 4. Vocabulary

Precise names are half the "intuitive" battle. These terms are used consistently across commands, flags, file formats, JSON output, and source code.

| Term | Definition |
|---|---|
| **Skill** | A directory containing `SKILL.md` (+ optional `references/`, `scripts/`), per the agentskills.io convention |
| **Eval** | One test case. **Behavioral** evals (`evals.json`) assert how the skill behaves once fired; **trigger** evals (`trigger-eval.json`) assert whether the description fires it at all. Together: the two **axes** |
| **Trial** | One execution of one eval through one harness. `--runs k` ⇒ k trials per eval |
| **Run** | One invocation of `skillet run`: a set of evals × harnesses × k trials, recorded as a unit |
| **Arm** | With-skill vs. without-skill execution of the same trial (`--ab`) |
| **Requested k** | Trials per eval asked for (`--runs`/config) — the trial *budget* |
| **Observed k** | `min(runs)` actually recorded across evals — the *basis* for pass^k; differs from requested k whenever trials are lost, aborted, or retried (the common case) |
| **pass^k** | An eval passes at observed k iff *all recorded trials* pass — reliability, not pass@1. Aggregate pass^k = fraction of evals that pass. Consistency is only meaningful at observed k ≥ 2 |
| **Flaky** | An eval with 0 < passes < observed k. Flaky evals are hygiene items: stabilize before trusting deltas |
| **Contradiction** | A deterministic scorer and the judge disagreeing on the same expectation — the calibration alarm that outranks the pass rate (§8) |
| **Harness** | An agent runtime that executes tasks: `claude-code`, `opencode`, `codex`, `direct-api`. Implemented as a `HarnessAdapter` |
| **Trace** | The normalized, harness-independent record of one execution: turns, tool calls, file changes, usage |
| **Session bundle** | The frozen on-disk capture of one production run (transcript, diff, SARIF, bodies, meta) |
| **Evidence** | Anything that counts toward a gate: a **friction event** (human-logged) or a **finding** (machine-mined by triage) |
| **Friction event** | One structured record of "I had to hand-fix the skill's output," with gate fields in frontmatter |
| **Finding** | One structured record emitted by `triage` from scorers or corrective-turn mining |
| **Lever** | Where a fix belongs: `eval` \| `benchmark` \| `lint` \| `skill_md` \| `reference` \| `config`. Routing is a hypothesis, not a verdict |
| **Gate** | A deterministic rule evidence must clear before a lever may be pulled (e.g., prose edits need ≥3 sessions across ≥2 domains) |
| **Proposal** | A candidate edit to a skill as content-anchored `EditProposal`s (per-edit `current_excerpt` → `proposed_text`, exact-once anchors) — drafted by `skillet suggest` or by hand — the output of `suggest`, the input of `iterate` |
| **Judge** | The grader of rubric criteria. Pluggable; independent of the task harness; split by capability into text and grounded judges (§9.4) |
| **Scorer** | A deterministic, free check that runs over outputs/bundles and emits SARIF |
| **Lint rule** | A deterministic, free `SKILL-Lxxx` check over the SKILL.md *source*; the implementer of the `lint` lever |
| **Drift** | Cross-run/cross-package SARIF order parameters (resolution-to-discovery ratio, severity drift, rule-ID entropy) plus generalizing-rule and stuck-rule classifications — the *machine* source of friction candidates for producer skills |

---

## 5. Invocation model

### 5.1 Run from anywhere

`skillet` discovers its project the way git does: walk upward from `$PWD` until a config file (`skillet.yaml`) or a `.git` boundary is found. Inside a skill directory, that skill is the implicit subject; at the repo root, all skills are. `-C <dir>` runs as-if from another directory. The `swift run`-from-repo-root era is over: `skillet` is an installed binary that works wherever you are.

### 5.2 Configuration precedence

`flags > environment > per-skill overlay > repo skillet.yaml > user config (XDG) > built-in defaults` — strictly, with `skillet config list --origins` showing where every effective value came from. The per-skill overlay (`evaluations/skillet.yaml`, optional, knobs only) exists because the highest-frequency configuration — scorer exemptions, vocab allowlists, lint disables — is skill-local. It is the landing spot for the `config` lever, and the operational reason most evidence never needs to become prose. The **user config** (`$XDG_CONFIG_HOME/skillet/config.yaml`, else `~/.config/skillet/config.yaml`) holds cross-repo personal *preferences* — a default harness, color, judge model, editor — and sits just above built-in defaults so any repo, overlay, env, or flag value wins over it; it may set defaults but **never** originates evidence, gate, or run state (D3). The gitignored cache stays repo-local (`.skillet/`).

```yaml
# skillet.yaml — created by `skillet init`, committed to the repo
project:
  skills_root: skills              # glob roots for SKILL.md discovery

runs:
  k: 3                             # trials per eval
  concurrency: 1                   # >1 is a choice, not a default: two parallel agents OOM'd a 16GB box
  confirm_above_trials: 25         # estimate + confirm beyond this (TTY)
  timeout: "10m"                   # per-trial watchdog: SIGTERM, 10s grace, SIGKILL
  infra_retries: 1                 # retry harness crashes/network only — never judged failures

harness:
  default: claude-code
  matrix: [claude-code, opencode]  # what --matrix means here
  claude-code:
    path: ""                       # resolution: flag > SKILLET_CLAUDE_CODE_BIN > this > PATH > vendored (opt-in)
    banned_versions: ["2.1.143"]   # shipped denylist seed: Skill-tool regression (is_error on every
                                   # invocation) — cost 3 sessions misdiagnosed as "prose insufficient"

judge:
  provider: anthropic-api          # or any adapter id with the judging capability
  model: claude-sonnet-4-6

# The methodology's numbers, shipped as defaults, tunable per repo (P10)
gates:
  codify:
    min_evidence: 3                # …or the same root cause twice:
    same_root_cause: 2
  prose_edit:
    min_sessions: 3
    min_domains: 2
  judge_only:
    min_sessions: 3
    min_domains: 2
  proof:
    # a skill_md edit is `proven` only if a held-out sibling eval (same failure class, not the
    # one it was drafted from) also passes — overfit guard; advisory per D6, blocks under --strict
    require_holdout: true

# Scorer/lint knobs — the `config` lever's destination, repo-wide here,
# overridable per skill in evaluations/skillet.yaml. Most signals land here, not in prose.
# (Supersedes the predecessor's .skill-eval/vendored-prefixes.txt and vocab-exemptions.txt;
# one-time import via `skillet migrate knobs`.)
scorers:
  vendored_prefixes: ["Vendored/", "Generated/"]
  vocab:
    exempt: ["secp256k1", "Schnorr"]
lint:
  disable: []                      # stable rule ids, e.g. ["SKILL-L011"]
  body_warn_lines: 500             # SKILL-L003: warn above this …
  body_error_lines: 1000           # … error above this
```

> **Config writes stay surgical.** `swift-yaml` (§11) parses this file but does not
> preserve comments on re-emit, so `skillet config set` rewrites the targeted lines
> in place rather than parse→mutate→serialize — the documented defaults above
> survive a programmatic change.

**Environment variables.** skillet's own variables are uppercase, underscore-delimited, and
`SKILLET_`-prefixed (`SKILLET_<ID>_BIN`, `SKILLET_ALLOW_BANNED_<ID>`), single-line, and none ever
carries a secret — provider credentials stay in the provider SDK's own variables and are never read
from a skillet flag (clig.dev: secrets belong in neither flags nor env). skillet also honors the
standard environment: `NO_COLOR`/`TERM` (color), `EDITOR` (`friction add`), `PAGER` (paged output),
`TMPDIR` (workspace/worktree scratch), and `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY` for provider calls.
`skillet config list --origins` reveals any value an environment variable supplied.

### 5.3 Global flags

| Flag | Meaning |
|---|---|
| `--json` | Machine output on stdout; human chatter to stderr |
| `-q` / `-v` | Quieter / more verbose human output |
| `--color auto\|always\|never` | Also honors `NO_COLOR`, `TERM=dumb`, and `--no-color` (≡ `--color never`); auto-off when stdout is not a TTY |
| `-C <dir>` | Operate as if started in `<dir>` |
| `--config <path>` | Explicit config file |
| `--harness <id,...>` | Harness selection (where execution happens) |
| `--runs <k>` | Override trials per eval |
| `--yes` | Assume consent for confirmations (scripts/CI) |
| `-n` / `--dry-run` | Print the plan (trials, spend estimate, writes) and stop |
| `--no-input` | Never prompt; if input is required, fail with the flag that supplies it (≠ `--yes`, which *answers* prompts) |
| `--version` | Print version and exit |

### 5.4 Exit codes (stable API)

| Code | Meaning |
|---|---|
| `0` | Success; everything measured passed |
| `1` | Measured failure: eval failures, trigger misfires, `iterate` regression |
| `2` | Usage error (bad flags/arguments) |
| `3` | Environment error: harness missing, auth failure, `doctor` failure |
| `4` | Artifact error: corrupt/invalid file against its schema |
| `5` | Gate violation under `--strict` |

### 5.5 Output contract

Human output is conversational, table-oriented, and ends with a suggested next command. It is **not** an API. `--json` payloads each carry `"schema": "skillet.<thing>/1"` and are versioned independently of the binary. Timestamps in artifacts are ISO-8601 UTC. Prompts appear only on a TTY and every prompt has a flag equivalent.

**Responsive over fast.** Long operations (`run`, `capture`, `iterate`) print something before any
paid or network call and show live progress on a TTY — a trial counter with an animated component,
plus an ETA where one is derivable — so a multi-minute run never looks hung; animation and color
stay suppressed when stdout is not a TTY or `--json` is set (the "no spinners when piped" rule,
stated positively). Large human output (`report`, `friction list`, `bundle list|stats`) pages
through `$PAGER` (default `less -FIRX`) only on a TTY.

---

## 6. Command surface

### 6.1 Porcelain — the loop

The ten loop verbs map one-to-one onto the methodology spine (Discover → Codify → Measure → Interpret → Suggest → Apply → Re-measure) plus its free static gate, named for what the *user* is doing, not for the spine's internals.

```
skillet init        # adopt skillet in a repo
skillet lint        # free static analysis of SKILL.md source — the cheapest lever
skillet run         # measure: execute evals, both axes, any harnesses
skillet capture     # discover: record a production session as evidence
skillet friction    # discover: log/inspect human-observed friction
skillet triage      # interpret: mine the corpus into routed findings
skillet suggest     # suggest: draft edit proposals from evidence — machine drafts, human reviews
skillet next        # the prioritized, gate-aware worklist
skillet iterate     # apply (safely): A/B a proposal in a throwaway worktree
skillet report      # render results for humans (TTY or HTML)
```

---

#### `skillet init`

```
skillet init [--skill <path>...]
```

Detects installed harnesses (via adapter probes), discovers skills under `skills_root` (or the given paths), writes `skillet.yaml` with detected defaults, and scaffolds per-skill `evaluations/` directories (`evals.json` and `trigger-eval.json` skeletons if absent; `friction/`, `findings/`, `sessions/` directories). Idempotent: re-running fills gaps and never overwrites. Ends by printing the three commands a newcomer should try (`doctor`, `run`, `next`).

---

#### `skillet doctor`

```
skillet doctor [<skill>...] [--paid]
```

Free, fast self-check, run implicitly (in relevant-subset form) before any paid command so failures cost $0:

- config parses; effective values printed with origins on `-v`
- each configured harness probes: binary resolved (with the link of the resolution chain that won), version not on the known-bad denylist (§9.1), auth present
- **skill visibility per harness**: for every skill × harness pair, the adapter statically verifies *both* conditions of the §9.2 contract — the positive-load condition (target `SKILL.md` *and* `references/` resolve under its injection strategy) and the discovery-only condition (declared siblings are listable but not injected). The `--skill-path` failure class, eliminated as a category (P6)
- each skill's `SKILL.md` frontmatter conforms to the agent-skills spec: `name` kebab-case ≤64 chars; `description` non-empty, ≤1024 chars, no angle brackets; top-level keys within the allowed set; duplicate keys rejected — spec-conformance, not JSON-schema, since `SKILL.md` lives outside `evaluations/`
- error-tier `lint` findings (§6.1 `skillet lint`) surface here too — the free gate runs before any paid one
- every artifact in `evaluations/` validates against its schema; boundary formats checked against golden expectations; unexpected `fixtures/**` diffs warned (A/B integrity, §9.2)
- `git` present (needed by `iterate`)
- the bundled secret scanner (`betterleaks`, §6.1) resolves and runs **detection-only** — skillet never passes `--validation`, so `capture` sanitization stays offline

`--paid` adds one canary trial per harness: a trivial prompt that asserts a known `references/` file is readable from inside the harness. Exit `3` on any failure, each with a remedy line.

---

#### `skillet lint`

```
skillet lint [<skill>...] [--format tty|json|sarif]
```

Free, instant, no model: static analysis of the skill *source* — `SKILL.md`, frontmatter, `references/` wiring — treated the way SwiftLint/clippy/shellcheck treat code. Stable diagnostic ids (`SKILL-Lxxx`, continuing the existing catalog) with tiers and fix-hints; SARIF output for editors and CI; **exit `1` on any error-tier finding**. Exemptions live in the `[lint]` knob tables — config, never inline pragmas — so suppressions are reviewable in one place.

The shipped catalog (ported; 5 of a planned 12):

| ID | Checks | Tier |
|---|---|---|
| `SKILL-L001` frontmatter-shape | description >1024 chars after YAML folding | error |
| `SKILL-L003` body-token-budget | body line count (ex-frontmatter/code): warn >500, error >1000 | warn/error |
| `SKILL-L009` has-evals | `evals.json` exists with ≥3 cases | error/warn |
| `SKILL-L010` has-trigger-evals | `trigger-eval.json` with ≥3 should-trigger **and** ≥3 should-not | warn |
| `SKILL-L011` cross-skill-refusal-contract | required headings present (silent unless siblings exist) | warn |

Roadmap rules, framed as *additions* (not existing behavior): name↔directory match, reserved `anthropic-*`/`claude-*` prefixes, third-person what+when description voice, all-caps ALWAYS/NEVER density, reference-extraction candidates, dead reference links.

This command is the implementer of the `lint` lever, the free pre-API gate (`skillet lint && skillet fixtures verify` is the intended pre-commit pair), its error-tier findings surface in `doctor` and `next`, and it's where "fix it without touching prose" usually lands.

---

#### `skillet run`

```
skillet run [<skill>...] [--axis behavior|trigger|all] [--eval <id|tag>...]
        [--runs <k>] [--ab] [--harness <id,...> | --matrix]
        [--judge <id>] [--concurrency <n>] [--fail-fast]
        [--record <dir> | --replay <dir>]
```

The day-one neutral runner (D2) and the Measure step. Defaults: the skill of the cwd (else all skills), both axes where files exist, `k` from config, the default harness, with-skill arm only.

- `--ab` adds the without-skill baseline arm to every trial, reporting Δ — this is "is the skill earning its tokens," not routine regression
- `--matrix` (or a multi-id `--harness`) fans the suite across harnesses and adds per-harness columns — the portability table
- `--axis trigger` runs the description axis: each `trigger-eval.json` query is executed against the harness's *selection* step and judged fired/not-fired against `should_trigger`. The Python trigger harness retires; one binary, two axes
- behavioral grading: every `expected_behavior` line is an independent rubric criterion sent to the Judge; an eval passes a trial only if **all** criteria pass; "surface compliance without substance is a FAIL" is part of the standing judge contract (§9.5)
- before spending: a plan line (`12 evals × 3 runs × 2 harnesses = 72 trials, ~$X est.`); above `confirm_above_trials`, confirm on TTY or require `--yes`

Writes a run record under `.skillet/runs/<timestamp>/` and updates the skill's `benchmark.json` **in the frozen format** so the existing eval-viewer keeps working untouched. Exit `1` if anything failed.

```
docc-articles  behavior  k=3        claude-code   opencode
  snippets-compile.................... PASS         FAIL (2/3)
  rule-of-three-density............... PASS         PASS
  cross-skill-refusal................. FLAKY (1/3)  FAIL (0/3)

pass^k: claude-code 14/16 (0.88) · opencode 11/16 (0.69)
1 flaky eval on claude-code — stabilize before trusting deltas.
→ next: skillet next docc-articles
```

---

#### `skillet capture`

```
skillet capture --skill <skill> --slug <slug>
            [--harness <id>] [--last | --session <native-ref>]
            [--from-checkpoint [last|<match>]] [--preserve-feedback]
            [--target-dir <path>]
```

The Discover step's recorder. The adapter (capability: `sessionCapture`) locates the native session — `--last` means "the one I just finished" — exports it, normalizes it to a Trace, and writes a session bundle to `evaluations/<skill>/sessions/<date>-<slug>.*` in the frozen bundle layout, **plus** an additive `*.trace.json` (the normalized form; additive files are permitted by the bundle's append-only policy, §7.2). Runs the deterministic scorers to produce the bundle's SARIF — renamed by role at capture time: producer skills' emitted findings become `*.audit-baseline.sarif`, consumer-side scans become `*.audit-input.sarif` (§7.2), with directionality enforced by `bundle verify`.

The pipeline normalizes the native session and **sanitizes before writing**, failing closed if the scanner cannot run:

```mermaid
flowchart LR
    L["locate native session<br/>adapter sessionCapture (--last)"]
    E["export → normalize to Trace"]
    SCAN{"secret scan<br/>betterleaks, offline"}
    RED["redact in place<br/>+ redaction report"]
    FC["fail closed<br/>no bundle written"]
    W["write session bundle<br/>frozen layout + trace.json + SARIF"]
    D["corrective-turn detect<br/>→ suggest: skillet friction add"]

    L --> E --> SCAN
    SCAN -- scanner ran --> RED --> W --> D
    SCAN -- scanner unavailable --> FC
```

**Secret sanitization (before write).** Production sessions leak credentials — `.env` contents, tokens, auth headers, keys echoed in command output — and capture commits the bundle, so the pipeline scans the transcript, diff, and bodies *before writing* and **redacts in place** with typed markers (`[REDACTED:aws-key]`). The raw secret never enters the repo; it remains only in the harness's native session store, which capture reads but does not commit. The default scanner is **bundled `betterleaks`** (MIT — vendored per platform/arch and run via `swift-subprocess`, §11; version-pinned, behind a swappable seam), run **detection-only and fully offline** (local BPE tokenization); `betterleaks`'s optional validation — its only network step — is off by default, irrelevant to redaction, and never enabled by skillet (§12, P8). Capture stays non-blocking (P4) — it redacts and prints a **redaction report** for the human to review before committing (P5); `--fail-on-secret` makes it fail-closed for CI (exit `1`). False positives are silenced via `betterleaks`'s own allowlist plus a skillet path exemption (`sanitize.exempt_paths`), and every redaction appears in the report, so an exemption is a one-line fix. If the scanner cannot run, capture **fails closed** with a remedy rather than writing an unsanitized bundle. Redaction provenance (scanner, version, count) is recorded in the bundle's `session-meta.json` (§7.2).

Two capture modes matter for the loop. `--from-checkpoint [last|<match>]` slices the transcript at a saved checkpoint *before* the session finishes — the real corpus carries two-stage lineages (an in-progress capture plus a `-completed` sibling of the same work). `--preserve-feedback` keeps every corrective turn from the first checkpoint to EOF instead of trimming to the final state — this is the open-coding signal `triage --code-feedback` (§9.3) depends on; without it Track B starves.

If the corrective-turn detector (§9.3) sees you correcting the agent mid-session, the closing line says so:

```
captured sessions/2026-06-07-secp-schnorr-article.* (trace: 41 turns, 2 corrective)
→ looks like you hand-fixed something: skillet friction add --skill docc-articles --sessions 2026-06-07-secp-schnorr-article
```

---

#### `skillet friction`

```
skillet friction add  [--skill <s>] [--domain <d>] [--lever <l>]
                  [--root-cause <text>] [--sessions <slug,...>] [--no-edit]
skillet friction list [<skill>] [--state <s>]
skillet friction show <id>
skillet friction set-state <id> held|watch|closed --reason <text>
skillet friction render [<skill>]
```

`add` writes one structured event file (§7.3) — interactive prompts on a TTY, flags for scripts, `$EDITOR` for the prose body unless `--no-edit`. Thirty seconds, by design: the habit only sticks if it is cheaper than skipping it (P4).

`set-state` records *human* judgment — HELD and WATCH are decisions, never inferences; the engine reads them and explains them but will not set them (D6). `render` regenerates `friction-log.md` as a generated, do-not-edit view, preserving the journal everyone is used to reading. `list` is the gate dashboard:

```
ID                                   DOMAIN      LEVER     EVIDENCE  STATE
2026-06-07-snippets-dont-compile     secp256k1   eval      3 (1 dom) HELD: single-domain
2026-06-02-rule-of-three-density     networking  skill_md  2 (2 dom) logged
```

---

#### `skillet triage`

```
skillet triage [<skill>] [--code-feedback] [--since <date>] [--write|--dry-run]
```

The Interpret step: error analysis across the whole session corpus, not a pass-rate.

- **Track A** (free, deterministic): scorers over every bundle, clustered by signal; baseline drift (§6.1 `baseline`) feeds producer-skill candidates in here
- **Track B** (`--code-feedback`, paid): the Judge axially codes corrective turns from normalized traces — *what did the human have to fix?* (it groups observed corrections; it never invents failures)

Scorer↔judge **contradictions print first**, above the taxonomy — "⚠ contradictions (N): triage before trusting the verdict" — because a disagreement between a deterministic scorer and the judge on the same expectation is the calibration alarm that silently inflates or deflates every pass rate (§8).

Output is a failure taxonomy; each cluster becomes a **finding** file (§7.3) routed to its cheapest lever, auto-linked to friction events that share sessions. Routing prints with its standing caveat — *a hypothesis, not a verdict* — and the table ends with `skillet next`, where findings and friction jointly feed the gates.

The two tracks run over the corpus and merge into routed findings — contradictions surfaced first:

```mermaid
flowchart LR
    C["session corpus<br/>normalized traces + bundles"]
    A["Track A — free<br/>deterministic scorers, clustered"]
    B["Track B — paid (--code-feedback)<br/>judge axial-codes corrective turns"]
    M["failure taxonomy<br/>contradictions first"]
    F["finding files<br/>routed to cheapest lever"]
    N["→ skillet next"]

    C --> A --> M
    C --> B --> M
    M --> F --> N
```

---

#### `skillet suggest`

```
skillet suggest <skill> [--from <evidence-id>... | --from-run <ts> | --from-triage]
                [--out <proposals.json>] [--proposals <file>] [--apply[=<indices>]]
```

The Suggest step — northstar gap #2 made executable. In: the failure taxonomy, the SKILL.md passages cited by failing `expected_behavior` lines, and corrective-turn excerpts from the linked sessions. The Judge is asked for *minimal surgical* edits and emits `EditProposal` objects — `skill_md_lines`, `rationale`, `current_excerpt`, `proposed_text`, `addresses` — to `.skillet/proposals/` (or `--out`). The Proposal (§7.3) is the **output of `suggest`** and the **input of `iterate`**. Nothing is applied by default.

**The `--apply` convention (safe by default).** One verb across `suggest` and `iterate` — *"materialize the proposal(s) into a tree"* — with the target set by the command and the default always off: `suggest --apply[=<indices>]` writes the selected proposals into your **working tree** through the content-anchored `EditApply` engine (exact-once anchor match, refuse-on-ambiguity, fail-loud on drift), refusing a dirty tree and **never committing**; `iterate --apply <indices>` materializes them into the **throwaway worktree** for measurement. One concept, different tree — a `plan`/`apply`-style safety default. This is the deliberate P5 amendment (v0.2), not a silent port: the default path still only emits proposals, and `--apply` automates exactly the apply step Appendix A previously told the human to run by hand, still stopping short of the commit.

Drafting carries the improvement principles as standing judge instructions — generalize from feedback rather than adding fiddly MUSTs, prefer deleting prose that isn't pulling weight, prefer extraction to `references/` over inline growth, explain the why — under the codify-what-you-discover constraint: `suggest` only drafts against *observed* evidence, never imagined failures. Each proposal records its `motivation` evidence ids, so a proven iterate can advance exactly the evidence that motivated it.

---

#### `skillet next`

```
skillet next [<skill>] [--json] [--strict]
```

The flagship. A pure derivation (no model, no writes, instant) over evidence files, eval results, and config thresholds — `git status` for EDD:

```
docc-articles — next actions

ACT NOW
  ◆ codify: rule-of-three-density            evidence 3/3 across 3 domains ✓
      → skillet eval new docc-articles --from-friction 2026-06-02-rule-of-three-density
  ◆ stabilize: cross-skill-refusal is flaky  (1/3 on claude-code)
      → skillet run docc-articles --eval cross-skill-refusal --runs 5

NEEDS CORROBORATION
  ◇ snippets-dont-compile                    evidence 3, domains 1/2
      → capture one session from a non-secp256k1 package

HELD (human decision — skillet will not nag)
  ▣ compile-eval infra                        "only strong lever is expensive infra"

WATCH
  ▢ recommendations-not-grounded             1 finding, low confidence
```

Every line carries the *reason* (which gate, what's missing) and the *exact command*. `--strict` exits `5` if methodology invariants are violated — a codified eval with no proof run, a skill_md edit landed without cleared gates — which is how CI enforces the runbook without `skillet` ever blocking a human interactively.

---

#### `skillet iterate`

```
skillet iterate <skill> --proposals <file|->
            [--apply <indices>...] [--runs <k>] [--eval <id>...] [--keep-worktree]
```

The safe Apply + Re-measure. Reads a *batch* of reviewed proposals (§7.3), materializes the selected subset (`--apply 0 2`; default all) into a **throwaway git worktree** via the content-anchored `EditApply` — the live skill untouched — runs the pinned suite at k, and prints the per-eval pass^k delta (at *observed* k) against the most recent recorded baseline (running one first if none exists):

```
proposals: fix-density.json — applying [0] of 1  (extract refusal prose to references/, -86 lines)

                               before   after    Δ
  snippets-compile             3/3      3/3      —
  cross-skill-refusal          3/3      3/3      —
  rule-of-three-density        2/3      3/3      ▲ fixed
  …
aggregate pass^k               0.88     0.94     ▲   (observed k=3, no contradictions)

no regressions · proposal set proven
→ land it:  skillet suggest --proposals fix-density.json --apply=0   (writes your working tree; you commit)
```

Any regression ⇒ worktree discarded, exit `1`, nothing emitted unless `--keep-worktree` for forensics. `skillet` never applies to the live tree from `iterate` and never commits (P5). On success it can, with `--mark`, advance the linked friction event to `proven` — an explicit, auditable state write whose verdict is **provisional until judge calibration clears** (no unresolved scorer↔judge contradiction on the affected evals, §8). For a `skill_md` edit this also honors the **held-out proof** gate (§8): a sibling eval in the same failure class — *not* the one the edit was drafted from — must pass too, so the proof reflects a generalizing fix rather than an overfit; with no sibling available the mark records `single-eval` and `next` advises authoring one.

The fix-and-prove loop ties `suggest` and `iterate` together — the machine drafts and proves, you review and commit; a regression sends you back to redraft, never to the live tree:

```mermaid
flowchart LR
    S["skillet suggest<br/>draft EditProposals from evidence"]
    R["you review the proposals"]
    I["skillet iterate --apply<br/>A/B in a throwaway worktree, at k"]
    Q{"pass^k delta:<br/>no regression?"}
    L["skillet suggest --apply<br/>writes working tree — you commit"]

    S --> R --> I --> Q
    Q -- proven --> L
    Q -- regression --> S
```

---

#### `skillet report`

```
skillet report [<skill>] [--run <timestamp>] [--html [--open]]
```

TTY summary across runs (trends, flaky list, per-harness matrix); `--html` renders the interactive viewer from the frozen `benchmark.json` — full compatibility with the existing Python viewer's data, whichever renderer you prefer. Both paths re-aggregate offline from recorded run artifacts — Core + Score + Judge, no harness in the loop — so `report` and `grade --run` work on yesterday's corpus from a plane.

---

#### `skillet migrate`

```
skillet migrate friction [--from <path>] [--dry-run]
skillet migrate knobs    [--dry-run]
```

`friction` is the one prose→structure migration (D5): a judge-assisted pass that parses the freeform `friction-log.md` into structured event files, shows the full plan, and writes nothing without confirmation; the original is preserved and thereafter regenerated by `friction render`. `knobs` is a trivial one-time import of the predecessor's `.skill-eval/vendored-prefixes.txt` / `vocab-exemptions.txt` into the `[scorers]` tables. Boundary *formats* never migrate; bundle *meta* is backfilled additively instead (§6.2 `bundle backfill`, §7.4).

---

### 6.2 Plumbing — stable primitives

Everything porcelain does decomposes into these; all support `--json`; their contracts are the scripting API.

| Command | Does |
|---|---|
| `skillet harness list` / `skillet harness info <id>` | Adapters, probe results, capability matrix, and which link of the resolution chain won |
| `skillet harness which <id> [--search <root>]` | Print the resolved binary as an `export`-able pin; `--search` is the *opt-in* recursive vendored-copy finder — it probes each candidate's `--version` and picks the **highest non-denylisted version** (newest-mtime only as a tiebreaker), so it never returns a stale or banned copy. Adapters never auto-probe other apps' private caches (§9.1) |
| `skillet grade --rubric <file> --against <trace\|file\|->` | One Judge pass over criteria; the grading primitive |
| `skillet grade --run <ts> [--judge <id>]` | Offline re-grade of a recorded run under a new judge/prompt version — no harness, no re-execution |
| `skillet score <bundle\|path>` | Deterministic scorers → SARIF on stdout |
| `skillet baseline compare --from <session> --to <session>` | SARIF drift between two captures: resolution-to-discovery ratio, severity drift (pp), rule-ID Shannon entropy — emitted **un-gated** (§8) |
| `skillet baseline matrix <skill>` | Cross-corpus drift: per-rule trajectories across packages, surfacing **generalizing rules** (firing in ≥3 packages) and **stuck rules** (zero variance across ≥3) as producer-skill friction candidates |
| `skillet fixtures verify [<skill>]` | The producer-output contract: every finding in a fixture's `expected.audit-baseline.sarif` must appear in `actual` (recall), and any extra `ruleId` must be in `fixture.json`'s `allowedExtraRuleIds`. For SARIF-emitting skills this is the *only* positive-output correctness assertion — judges grade prose, not emitted-finding recall |
| `skillet bundle inspect\|verify\|list\|stats\|backfill <skill\|slug>` | Corpus management: read/schema-check one bundle (incl. SARIF role directionality); inventory and provenance stats; `backfill` additively writes missing `*.trace.json` *and* `session-meta.json` (proxies: `captured_at` ← date@00:00Z; unresolved fields ← `"unknown"`) |
| `skillet hooks install` | Git pre-commit guard refusing commits that mutate `evaluations/fixtures/**` (bypass: `--no-verify`) — fixture pollution silently invalidates future A/B measurements (§9.2) |
| `skillet gate eval [--json]` | Raw gates-engine output (what `next` renders) |
| `skillet eval new <skill> [--from-friction <id>]` | Scaffold a behavioral eval case; with `--from-friction`, prefill assertions citing the suspected SKILL.md clause, link the evidence, and set its state to `candidate→codified` on save |
| `skillet config get\|set\|list [--origins]` | Effective configuration |
| `skillet completions <shell>` | Shell completions (bash/zsh/fish) |

### 6.3 Help & discoverability conventions

`skillet` with no arguments prints the loop, not a flag dump. Every `--help` leads with two real examples before flags. Unknown commands get "did you mean." Every command's human output ends with a suggested next step (P3). First paid action in a fresh repo triggers a one-time pointer to `skillet doctor`. Top-level `--help` and `--version` carry a support line (the issues URL), so the path to report a problem is always one screen away.

---

## 7. State & artifact model

### 7.1 Repository layout

```
repo/
├── skillet.yaml                          # committed config
├── .skillet/                             # gitignored: cache + run records (rebuildable views; raw records re-gradable)
│   ├── runs/<ts>/
│   │   ├── plan.json                 # the fan-out: evals × k × harnesses × arms
│   │   └── trials/<n>/
│   │       ├── raw.jsonl             # harness-native stream, verbatim (the replay source)
│   │       ├── trace.json            # normalized (skillet.trace/1)
│   │       ├── verdicts.json         # judge output + judge_id + judge_prompt_version
│   │       ├── output.sarif          # deterministic scorers
│   │       └── metadata.json         # timing, usage, retries, exit class (passed|failed|infra|timeout)
│   ├── proposals/*.json              # suggest drafts: content-anchored EditProposal sets
│   └── index.sqlite                  # derived accelerator only — delete freely
└── skills/<skill>/
    ├── SKILL.md
    ├── references/…
    └── evaluations/
        ├── skillet.yaml                  # optional knob overlay (§5.2) — the `config` lever lands here
        ├── evals.json                # FROZEN  (behavioral axis)
        ├── trigger-eval.json         # FROZEN  (trigger axis)
        ├── benchmark.json            # FROZEN  (viewer contract)
        ├── sessions/<date>-<slug>.*  # FROZEN bundle + additive *.trace.json
        ├── fixtures/<name>/…         # synthetic packages evals run against
        ├── friction/<date>-<slug>.md # NEW     (human evidence)
        ├── findings/<date>-<slug>.md # NEW     (mined evidence)
        └── friction-log.md           # generated view (skillet friction render)
```

The committed `evaluations/` tree is the database (P2). `.skillet/` is an accelerator and scratch space; `skillet` rebuilds it on demand and never treats it as truth. The one configuration that lives *outside* the repo is the user-preferences file at `$XDG_CONFIG_HOME/skillet/config.yaml` (§5.2): cross-repo defaults only, never workflow state.

### 7.2 Frozen boundary formats (D5)

| Format | External reader | Policy |
|---|---|---|
| `evals.json` — cases of `{skills, query, files[], expected_behavior[], timeout_seconds?}` | skill-creator's Python tooling; de-facto standard | Read/write as-is. New optional fields only ever *additive* |
| `trigger-eval.json` — `{query, should_trigger}` pairs | skill-creator's optimizer | Same |
| `benchmark.json` | The Python eval-viewer reads exact field names | Opaque contract: `skillet` writes byte-level-compatible structure, verified by golden files. Additive: `executor_binary_version` joins `model`/`judge_prompt_version`, so a cross-run pass-rate delta is attributable to a harness change vs a skill change |
| `*.audit-baseline.sarif` (producer) **and** `*.audit-input.sarif` (consumer) | SARIF 2.1.0 consumers; the audit→articles handoff; the `baseline` drift engine reads the producer side | Real standard; scorers emit valid 2.1.0. Capture renames by role (§6.1); `bundle verify` enforces directionality. The `fixtures verify` invariant (`expected ⊆ actual` + `allowedExtraRuleIds`) is defined over these |
| Session bundles + `session-meta.json` — `{id, skill, skill_version, model, harness, captured_at, schema_version, sanitization?}` | Existing corpus | **Append-only**: never rename/remove/retype anything; new *files* in the bundle (e.g. `*.trace.json`) are permitted; field additions bump `schema_version`. `"unknown"` is a defined sentinel (counted separately, never poisons diversity readings) |

Enforcement is mechanical, not aspirational: `Tests/Golden/boundary/` holds canonical fixture files; CI fails if `skillet`'s codecs produce or reject anything the goldens don't. Two corollaries the predecessor learned the hard way: the goldens must enumerate **all** decoded fields (an omitted field — like `timeout_seconds` — is an unenforced freeze), and codecs must **round-trip unknown keys** rather than dropping them on re-encode, or "additive-only" is a policy the tool itself violates.

### 7.3 Greenfield formats

All three are markdown + YAML frontmatter: machine-parseable, human-readable, merge-conflict-free because every event is its own file. **Files are the API** — hand-editing frontmatter is legitimate; `skillet` validates on read. The frontmatter is parsed and emitted through `swift-yaml`'s `Codable` API (§11).

**Friction event** — `friction/2026-06-07-snippets-dont-compile.md`

```markdown
---
schema: skillet.friction/1
id: 2026-06-07-snippets-dont-compile
skill: docc-articles
domain: secp256k1                  # distinct-domain de-dupe key
lever: eval                        # eval|benchmark|lint|skill_md|reference|config
state: held                        # logged|watch|candidate|held|codified|proven|closed
held_reason: "single-domain; only strong lever is compile-eval infra"
root_cause: "SKILL.md:214 — snippets must compile"
sessions: [2026-06-01-secp-sign-article, 2026-06-04-secp-verify-article]
skill_version: "1.3.0"             # sourced from the linked sessions' meta; "unknown" sentinel allowed
model: claude-opus-4-8             # likewise — version/model-aware corroboration, §8
eval: null                         # filled at codify: evals.json#snippets-compile
---
Invocation: asked for a signing walkthrough article for P256K…
Manual fix: replaced pseudo-API calls with the real secp256k1 API surface…
Notes: a third occurrence outside secp would justify the fixture investment.
```

**Finding** — `findings/2026-06-05-rule-of-three-density.md`: same shape plus `source: scorer|code_feedback|judge`, `confidence: high|medium|low`, `cluster`, and `signal` (the scorer/judge detail). Findings and friction events are both **evidence**; the gates engine consumes them uniformly, de-duplicating on shared sessions.

**Proposal** *(format changed in v0.2)* — the output of `suggest`, the input of `iterate`: a JSON set with `id`, `skill`, `motivation: <evidence ids>`, `expected: <eval ids that should flip>`, and per-edit `EditProposal`s carrying `skill_md_lines`, `rationale`, `current_excerpt`, `proposed_text`, `addresses`. Application is **content-anchored**: each `current_excerpt` must match exactly once (refuse-on-ambiguity, fail-loud on drift). This deliberately replaces the v0.1 unified-diff body — line-anchored hunk offsets rot the moment a human applies any earlier edit by hand, while content anchors survive reordering; strictly safer than `git apply`. Drafted by `skillet suggest` or by hand — the format doesn't care.

**Evidence lifecycle.** `logged → candidate → codified → proven → closed`, with `watch`/`held` as human-set side states. Engine-readable, command-written: `friction add` creates `logged`; gate clearance makes `next` *propose* candidacy; `eval new --from-friction` sets `codified`; `iterate --mark` sets `proven`; the human closes. No transition ever happens implicitly (D6).

### 7.4 Migration & backfill

Boundary **formats** never migrate — they're frozen. Bundle **meta** is *backfilled* additively instead: the corpus accreted `session-meta.json` and `bodies` over time, so `skillet bundle backfill` writes missing meta with documented proxies (`captured_at` ← the bundle's `<date>` prefix @00:00Z; unresolvable fields ← the `"unknown"` sentinel). The friction log is the one prose→structure **migration** (§6.1 `migrate friction`); the knob `.txt` files are a trivial one-time import (`migrate knobs`).

### 7.5 Artifact & file formats (at a glance)

A consolidated map of §7.1–§7.4. Two axes govern every artifact: **committed**
(`evaluations/` — the database) vs **gitignored** (`.skillet/` — rebuildable
cache), and **frozen** boundary contract (D5) vs **greenfield** (hand-editable,
validated on read).

| Role | File(s) | Format | Lifecycle |
|---|---|---|---|
| Config | `skillet.yaml`, `evaluations/skillet.yaml` (overlay) | YAML — `swift-yaml` | committed |
| User preferences | `$XDG_CONFIG_HOME/skillet/config.yaml` | YAML — `swift-yaml` | user-global (not committed) |
| Skill source | `SKILL.md`, `references/`, `scripts/` | Markdown + YAML frontmatter | external |
| Eval & benchmark contracts | `evals.json`, `trigger-eval.json`, `benchmark.json` | JSON — Foundation `Codable` · **frozen** | committed |
| Fixtures | `fixtures/<name>/…` + `fixture.json` | source packages + JSON | committed (commit-guarded) |
| Diagnostics | `*.audit-baseline.sarif`, `*.audit-input.sarif` | SARIF 2.1.0 (JSON) · **frozen** | committed |
| Session corpus | bundle + `session-meta.json`, `*.trace.json` | JSON · **frozen, append-only** | committed |
| Evidence | `friction/*.md`, `findings/*.md`, `friction-log.md` | Markdown + YAML frontmatter · **greenfield** | committed |
| Proposals | `.skillet/proposals/*.json` | JSON | cache |
| Run records | `runs/<ts>/{plan,trace,verdicts,metadata}.json`, `raw.jsonl` | JSON · JSONL | cache |
| Index | `.skillet/index.sqlite` | SQLite | cache (deletable) |
| Report | `report --html` | HTML | produced |

**Serialization stack.** Human-editable inputs are **YAML** (config + frontmatter,
via `swift-yaml`); machine artifacts are **JSON / JSONL / SARIF** via Foundation
`Codable` (no extra dependency); the cache index is **SQLite**. Only JSON crosses a
frozen boundary (D5) — YAML never does. Proposals stay JSON deliberately:
content-anchored `EditApply` needs exact-once, whitespace-stable excerpt matching
that YAML block scalars would make ambiguous. Process execution (harnesses, judge,
`git`) is not a file format but is likewise centralized — on `swift-subprocess`
(§11).

### 7.6 YAML usage policy

YAML earns its place for human-editable **policy**, never **behavior**. The
governing risk is the *configuration-complexity clock*: data that grows
conditionals becomes a poorly-tooled DSL (the Inner-Platform Effect). A surface
may be expressed as YAML only when **all four** hold — if any fails, it stays
Swift:

1. **Value, not behavior** — a list, scalar, or threshold; no conditionals, loops, or cross-references.
2. **Changes independently of the binary** — tuned per-repo/per-skill, or more often than `skillet` ships.
3. **A non-compiling user can author and review it** — *files are the API* (§7.3).
4. **Schema-validatable and safe** — bounded shape, validated on read, no ReDoS or code-exec surface.

**Tripwire.** The moment a rule wants conditionals, ordering-dependent
composition, rule-to-rule references, or a `script:` escape hatch — stop and
promote it to a Swift rule. `skillet`'s escape hatch is its own language, never an
embedded one.

| Surface | Home | Note |
|---|---|---|
| `gates.*` thresholds | **YAML** | values only; the gate *engine* (§8) stays a pure, tested function |
| Harness denylist (versions + provenance) | **YAML** | a list with metadata (§9.1) — versioned, audited |
| Scorer wordlists · vendored-prefix / vocab allowlists | **plain list / YAML** | prefer newline-delimited `.txt` for large wordlists |
| Lint rules — pattern / threshold / presence tier | **YAML** | fixed, code-backed *kinds* only; ReDoS-guarded |
| Lint rules — YAML-folded length, eval-count, voice, extraction | **Swift** | needs parsing or semantics |
| Judge / suggest prompt contracts | **versioned `.md` assets** | versioned by `judge_prompt_version` (§9.4) — assets, not knobs |
| Gate-engine flow · adapter capabilities · boundary codecs · exit codes | **Swift** | trust, determinism, typed contracts — never data |

**Operational hygiene** (config, frontmatter, and any rule files are all YAML):
every YAML file is JSON-Schema-validated on read with duplicate keys rejected;
`swift-yaml`'s YAML 1.2 base sidesteps the `yes/no/on/off` and octal traps;
version strings are quoted; and `skillet lint` lints its own rule files.

---

## 8. The gates engine — the computable runbook

A pure function:

```
(evidence files, eval results, config thresholds) → [GateAssessment]
```

Deterministic, instant, no model calls, exhaustively unit-tested — because users must be able to *trust the worklist* the way they trust `git status`.

The engine sits in a loop — evidence in, a ranked worklist out, and your action changes the evidence:

```mermaid
flowchart LR
    EV["evidence<br/>friction + findings + eval results"]
    GE["gates engine<br/>pure derivation, no model"]
    NX["skillet next<br/>ranked worklist: ACT NOW · corroborate · HELD · WATCH<br/>each with a reason + exact command"]
    DO["you run the suggested command<br/>→ evidence changes"]

    EV --> GE --> NX --> DO --> EV
```

**Rules are data.** The shipped defaults are the methodology's published numbers; the `gates.*` keys in `skillet.yaml` tune them per repo (P10):

| Gate | Default rule |
|---|---|
| **Codify** | ≥3 evidence items, *or* the same `root_cause` twice |
| **Prose edit** (`lever: skill_md`) | Same signal across ≥3 sessions **and** ≥2 distinct domains |
| **Judge-only signals** | ≥3 sessions across ≥2 domains before codifying |
| **Distinct-domain de-dupe** | Corroboration counts unique `domain` values, never raw session count |
| **Version-aware corroboration** | By default, count only evidence whose `skill_version` is ≥ the version the candidate fix targets; cross-version evidence is *flagged, not counted* (a v1.0 friction event may describe a problem a later edit already closed). `model` is recorded and single-model corroboration is flagged. `next`'s gap line says so: "2 of 3 sessions predate v1.3." `"unknown"` counts separately and never poisons the diversity reading |
| **Contradicted verdict** | A deterministic scorer and the judge disagreeing on the same expectation outranks the pass rate itself — pass-rate trust is *conditioned* on zero unresolved contradictions. Surfaced first in `triage`/`report`; under `--strict`, an uncleared contradiction blocks (exit `5`) |
| **HELD respect** | A human `held` state suppresses ACT-NOW promotion even when counts clear; `next` shows it with its reason |
| **Proof** | A `codified` item becomes `proven` only when its eval failed before the change, passes after, with **zero pass^k regression** (at *observed* k) across the pinned suite — and the verdict is provisional until judge calibration clears: no unresolved contradiction on the affected evals |
| **Held-out proof** (`lever: skill_md`) | A prose edit is `proven` only if a **held-out sibling eval** — same failure class (`root_cause`/`cluster`), *not* in the proposal's `expected`/`motivation` set — also passes, so the fix is shown to generalize rather than overfit the one eval it was drafted from (`gates.proof.require_holdout`, default on). When the failure class has no sibling, `next` advises authoring one and the mark is recorded `proven (single-eval, un-corroborated)`; under `--strict` the missing held-out blocks promotion (exit `5`). Advisory by default (D6) |
| **Hygiene first** | Flaky evals (0 < passes < observed k) outrank everything except contradictions: deltas measured on a flaky suite are noise, and consistency is only meaningful at observed k ≥ 2 |

Each `GateAssessment` carries: the evidence set, which rule fired or is unmet, the *gap* ("domains 1/2"), and a ready-to-run command — which is all `next` is: this engine plus a renderer. `--strict` (exit `5`) turns unmet invariants into CI failures.

**Contradiction detection lives here too** — a pure `EDDCore` function joining Verdicts and SARIF results for the same expectation (both are core domain types, so no new module is needed; the review proposed a `ReconcileKit`, but a deterministic join belongs with the gates engine). `run`, `triage`, and `report` all surface its output, contradictions first.

**Drift is the producer-skill discovery channel.** For skills that *emit* findings rather than prose, `baseline matrix`'s generalizing-rule (≥3 packages) and stuck-rule (zero variance, ≥3 packages) classifications are the machine source of friction candidates — the structural twin of corrective-turn mining for consumer skills. The order parameters are emitted **un-gated by design**: an eval at 100% tracks regressions but gives no improvement signal, and a `--fail-on-drift` threshold would calcify the audit against exactly the qualitative shifts it exists to surface.

A deliberate non-goal, stated because it is the trap: **most evidence does not lead to SKILL.md edits.** The engine's lever routing exists precisely to keep config knobs, wrong assertions, and reference-file fixes from masquerading as prose gaps — the knob overlay (§5.2) and `references/` are where those land.

---

## 9. Harness abstraction

### 9.1 The adapter protocol

```swift
public struct HarnessCapabilities: OptionSet, Sendable {
    public static let runTask        = Self(rawValue: 1 << 0)  // mandatory
    public static let skillInjection = Self(rawValue: 1 << 1)
    public static let traceParsing   = Self(rawValue: 1 << 2)
    public static let sessionCapture = Self(rawValue: 1 << 3)
    public static let judging        = Self(rawValue: 1 << 4)
}

public protocol HarnessAdapter: Sendable {
    var id: HarnessID { get }
    var capabilities: HarnessCapabilities { get }

    func probe() async throws -> HarnessInfo                 // version, auth, availability
    func verifySkillVisibility(_ skill: SkillRef,
                               strategy: InjectionStrategy) throws  // doctor's $0 check

    func run(_ task: TaskSpec,
             in workspace: Workspace,
             skills: SkillSet) async throws -> RawTrace

    func parseTrace(_ raw: RawTrace) throws -> Trace          // if .traceParsing
    func locateSessions(_ q: SessionQuery) async throws -> [NativeSessionRef] // if .sessionCapture
    func exportSession(_ ref: NativeSessionRef) async throws -> RawTrace
}
```

Commands degrade by capability, loudly: `skillet capture --harness direct-api` fails immediately with "direct-api cannot capture sessions (no native session store); harnesses that can: claude-code" — never silently.

**Resolution & ban policy.** Binary resolution is a fixed, printable chain — `--harness-path` flag > `SKILLET_<ID>_BIN` env > `[harness.<id>].path` > `PATH` > vendored search (opt-in via `harness which --search`, which selects the **highest non-denylisted `--version`** with newest-mtime only as a tiebreaker) — and `skillet harness info <id>` shows which link won, toolchain-resolution discipline in the volta/Bazel tradition. Adapters **must not auto-probe other applications' private caches** (editor-embedded npx/pnpm trees and the like): their layouts rotate without notice and silently produce non-reproducible dev↔CI runs; vendored discovery is therefore always explicit, printing an `export`-able pin rather than deciding for you.

The denylist is *data with provenance*, not a version floor: a shipped seed list (first entry: claude-code `2.1.143`, whose Skill-tool regression returned `is_error` on every invocation and cost three eval sessions misdiagnosed as "prose insufficient" before bisection), a committed per-repo override file (rules-are-data, mirroring §8), and an audited bypass (`SKILLET_ALLOW_BANNED_<ID>`) for deliberately reproducing a regression. The anti-footgun rule: an **auto-discovered** banned binary may fall back to a non-banned one with a loud notice; an **explicitly pinned** banned binary (flag/env/config) is a hard error at exit `3` — never a silent swap. The resolved id and version are stamped into every trial's `metadata.json`, every bundle's `session-meta.json`, and `benchmark.json`'s `executor_binary_version` — provenance is how a ban list gets discovered in the first place, and how a cross-run delta gets attributed to a harness change rather than a skill change.

### 9.2 Skill injection & withholding — the A/B contract

```swift
public enum SkillSet: Sendable {
    case none                                   // baseline arm: provably no skill present
    case only(load: [SkillRef],                 // injected & loadable: exactly these, references/ included
              visible: [SkillRef] = [])         // discoverable-but-unloadable: the sibling corpus
    case ambient                                // whatever the user's environment provides (capture side)
}
```

**Loadable ≠ visible, and the distinction is load-bearing.** Refusal-routing evals require the sibling skill to be **visible but not loaded**: the skill-under-test must be able to *detect* that a sibling exists in order to correctly decline and hand off. The scar behind this: when the model could not even see the sibling, it didn't refuse out-of-scope work — it did the work itself ("the skill failed to load… so I wrote the comments directly"). Strict hermeticism makes the "should I hand off?" branch unreachable, and the cross-skill-refusal eval (§6.1's own sample output) passes vacuously or can't run. `doctor`'s visibility check verifies both halves: the positive-load condition *and* the discovery-only condition (§6.1).

Each trial runs in a fresh, core-owned `Workspace` sandbox (create → stage `files[]` → run → diff → destroy) over **pristine fixtures** — which is why `hooks install` guards `fixtures/**` against commits (§6.2): a polluted fixture silently invalidates every later A/B. *How* `.only` materializes is the adapter's private business — staging into the harness's skill-discovery path (with siblings present-but-stubbed for the `visible` set), a flag, or (for `direct-api`) inlining `SKILL.md` + references into the system context with sibling names listed but bodies withheld. The old `--skill-path` footgun was the user doing the adapter's job; under this contract the failure class cannot recur, and `doctor` proves it per harness before money moves (P6).

`.none` is equally rigorous: the adapter must isolate the trial from ambient user skills, or declare it cannot — in which case `--ab` on that harness is refused with an explanation rather than producing a polluted baseline.

### 9.3 The normalized trace

The one schema everything downstream consumes — capture bundles, corrective-turn mining, judge evidence, the viewer:

```swift
public struct Trace: Codable, Sendable {       // "skillet.trace/1"
    var harness: HarnessID, harnessVersion: String
    var startedAt: Date, endedAt: Date
    var turns: [Turn]                           // role, text, toolCalls, filesTouched, at
    var skillInvocations: [SkillInvocation]     // which skills fired, at which turn
    var workspaceDiff: WorkspaceDiff
    var usage: Usage?                           // tokens / cost where the harness reports them
}
```

Per-harness parsers (Claude Code session JSONL, OpenCode logs, raw API message lists) live beside their adapters and are golden-file tested against recorded native logs. **Corrective-turn detection** runs on `Trace` alone — harness-independent by construction. What ships (ported): text-pattern matching on user turns following assistant work. Roadmap, flagged as not-yet-built (v1.x): the diff-based half, flagging user turns whose subsequent diff reverts assistant-written hunks. Track A flags heuristically for free; Track B (`triage --code-feedback`) sends flagged windows to the Judge for **axial coding** — grouping observed corrections by root cause. It never invents failures: only turns the human actually made enter the taxonomy.

One usage caveat, stated so the port is honest: the existing claude-code pipeline *discards* the stream's `total_cost_usd` and per-message usage — `benchmark.json`'s token fields are structurally zero today. The new `ClaudeCodeAdapter` parsing them into `Trace.usage` is **net-new work, not a port**; until adapters emit usage, spend estimates fall back to trial counts (× a configured per-trial price if set), and the spend column shows "—" rather than fabricated numbers.

This schema is designed now, not retrofitted (D4): every field above is required to express what the *existing* Claude-only pipeline already records, which is the test of sufficiency.

**The trigger axis runs on `skillInvocations`.** A trigger trial executes the bare query with the repo's skills discoverable (`.only(load: [], visible: allSkills)` — §9.2's visibility tier exists for exactly this); grading is then deterministic, no judge needed — did the target skill fire, and for `should_trigger: false` near-misses, did it correctly *not* fire (routing to a sibling instead)? Adapters surface activation events natively where the harness logs them (Claude Code does); `direct-api` approximates with the selection-prompt technique the retired Python harness used. This is where the unified two-axis `run` (§6.1) actually lives in the architecture.

### 9.4 The Judge

```swift
public protocol Judge: Sendable {
    func verdict(for criterion: RubricCriterion,
                 evidence: JudgeEvidence) async throws -> Verdict   // pass/fail + rationale
}
```

Decoupled from the task harness (D4): grading via the same model that did the work conflates the two and breaks the matrix. `JudgeEvidence` is specified, not implied: the response text, the normalized `Trace`, **and the post-run workspace** — a file-listing snapshot of the trial sandbox plus on-demand file reads (the sandbox outlives the trial just long enough to be graded).

Judges split by capability, because most rubric criteria in a skills corpus assert *file* outcomes ("wrote SARIF to X", "scaffolded the catalog") and a stateless message-API judge cannot inspect a sandbox — it can only grade what's pre-serialized into its prompt, which truncates for multi-file audit skills:

- **Text judge** (`AnthropicAPIJudge`): criteria decidable from response text alone; the cheap CI default *for those criteria only*. Used as a grounded judge's fallback, it must receive the workspace snapshot in-context.
- **Grounded judge** (an agentic adapter with read access to the trial sandbox, instructed to use it): the default for any criterion asserting a file/dir/contents outcome, and for file-writing skills generally. Grading a file-write from prose alone is precisely the "surface compliance" failure the contract forbids.

The standing rubric contract — each `expected_behavior` line is an independent criterion, all must pass, *consult the post-run workspace, do not rely solely on response text, surface compliance without substance is a FAIL* — is versioned by `judge_prompt_version`. Every verdict records `judge_id`, `model`, and `judge_prompt_version`, so results remain comparable across time and re-gradable via `--replay`.

### 9.5 v1 adapter matrix

| Capability | `claude-code` | `opencode` | `direct-api` | `codex` (v1.1) |
|---|---|---|---|---|
| runTask | ✓ | ✓ | ✓ | ✓ |
| skillInjection | ✓ (load+visible) | ✓ (load+visible) | ✓ (inline; visible = names listed) | ✓ |
| traceParsing | ✓ | ✓ | ✓ (trivial) | ✓ |
| sessionCapture | ✓ | v1.1 | — | ? |
| judging | ✓ grounded | ✓ grounded | ✓ text (snapshot in-context) | ✓ grounded |

Two real agents plus `direct-api` ship in v1 because the matrix is a launch feature, the seam must be proven by a second implementation rather than asserted, and `direct-api` doubles as the cheapest CI judge. Which second *agent* ships first is Open Question 2.

---

## 10. Execution & scoring semantics

One trial of `skillet run` flows through the harness seam (§9.1) as shown below; the paragraphs that follow detail each stage. Free deterministic gates (`doctor`/`lint`) run *before* any paid trial, and both the judge and the scorers feed `EDDCore`'s aggregation (§8).

```mermaid
sequenceDiagram
    actor U as You or CI
    participant S as skillet (RunKit)
    participant A as HarnessAdapter
    participant H as Harness CLI (subprocess)
    participant J as Judge
    participant C as Score + EDDCore

    U->>S: skillet run SKILL --eval E --runs k
    S->>S: load config, discover skill, plan trials
    Note over S: free pre-gates first (doctor / lint)
    loop each trial (to observed k)
        S->>A: probe() — resolve binary, denylist, version
        S->>A: stage skill in a fresh Workspace (§9.2)
        S->>A: run(task, workspace, skills)
        A->>H: launch via swift-subprocess (env contract, §10)
        H-->>A: native session (JSONL)
        A-->>S: RawTrace
        S->>A: parseTrace(raw)
        A-->>S: normalized Trace (§9.3)
        S->>J: grade Trace against the rubric
        J-->>S: per-criterion verdict
        S->>C: deterministic scorers, SARIF
    end
    S->>C: aggregate pass^k, gates, scorer/judge contradiction (§8)
    C-->>S: result
    S-->>U: TTY + --json (schema-tagged), stable exit code
```

**Trial isolation.** Every trial gets a fresh `Workspace`: fixtures and `files[]` staged in, harness runs, diff captured, sandbox destroyed. No trial sees another's residue; `--keep-worktree`/`--keep-workspace` exist for forensics.

**pass^k, precisely.** Per eval per harness: pass ⇔ all recorded trials pass every criterion, computed at **observed k** — `min(runs)` actually recorded — which diverges from requested k (`--runs`) whenever trials are lost, aborted, or infra-retried (the common case). Consistency is only *meaningful* at observed k ≥ 2; below that, the aggregator reports "variance unmeasurable" rather than a number, and it always re-derives from the on-disk run records (so the pass^k baseline survives process restarts and is recomputable offline). Anything with 0 < passes < observed k is *flaky* and is reported as a hygiene item before any delta is trusted (§8); pass-rate trust is additionally conditioned on zero unresolved scorer↔judge contradictions. `report` shows variance across historical runs so "did it really improve" has an answer beyond one number.

**Concurrency & cost.** Shipped `concurrency = 1` because the binding constraint is **host memory, not rate limits**: each harness subprocess is memory-heavy (hundreds of MB resident), the *judge* subprocess competes for the same budget, and a second in-flight task can OOM-kill the judge (exit 137 = SIGKILL by the OOM killer), holing the run with ungradeable trials. Concurrency is bounded by available memory rather than a magic integer — the scheduler should be memory-aware, the judge counts against the executor budget, and `--matrix` multiplies all of it. Rate limits and workspace I/O are secondary. Plans always print trial counts; estimates use adapter-reported usage when available and fall back to trial counts otherwise (§9.3). `confirm_above_trials` guards the wallet on TTY; `--yes` is the script contract (P9).

**The scheduler (RunKit).** Between pure `EDDCore` and one-process `HarnessKit` sits the orchestrator: it expands the plan (evals × k × harnesses × arms), executes it under the concurrency cap, and owns the watchdog — per-trial `timeout` (overridable per eval via `timeout_seconds`, §7.2), SIGTERM with a 10-second grace, then SIGKILL, workspace destroyed either way. Retry policy follows flaky-test best practice: only *infrastructure* failures are retried — defined as **no-terminal-event** failures (the stream died without a result event: harness crash, auth/network drop, OOM) as distinct from contract failures — up to `infra_retries`, with every retry stamped into trial metadata; a judged FAIL is never retried, because retrying assertions manufactures green. The flip side holds too: an *un*-retried socket drop manufactures false flakiness, polluting the §8 hygiene gate. Trial **exit class** (`passed | failed | infra | timeout`) is first-class in run records, so aggregation can always tell measurement from noise.

**Env hygiene.** Each adapter declares an environment contract for its subprocess — variables stripped for clean nesting (claude-code strips `CLAUDECODE` so an agent-launched `skillet` doesn't confuse the child harness), variables required, variables passed through. Part of the adapter protocol, not ad-hoc — realized as the explicit environment handed to `swift-subprocess` (§11).

**Record / replay.** `--record <dir>` persists every `RawTrace` and `Verdict`; `--replay <dir>` serves them back through a `ReplayAdapter` + `ReplayJudge`. Three payoffs: `skillet`'s own test suite runs free and deterministic; bug reports become reproducible attachments; and old runs can be *re-graded* under a new judge prompt version without re-executing tasks.

---

## 11. Swift package architecture

```
skillet (Package.swift, Swift 6, strict concurrency)
├── EDDCore        domain types · gates engine · scorer↔judge contradiction join ·
│                  pass^k aggregation (observed-k) · boundary codecs (golden-tested) ·
│                  evidence graph
│                  deps: Foundation (swift-yaml only via an isolated codec seam,
│                  see Dependency policy below) — NO subprocess, NO network
├── TraceKit       Trace/Turn/skillInvocations model · corrective-turn heuristics
│                  (text-pattern; diff-revert detector is v1.x)
├── CorpusKit      session bundles: WRITE + read · provenance stamping · SARIF
│                  role-rename + directionality · inventory/stats · trace + meta backfill
├── LintKit        SKILL-Lxxx static rules over SKILL.md source · knob-table
│                  exemptions · SARIF emit — the free pre-API gate
├── ScoreKit       deterministic output scorers · SARIF emit
├── HarnessKit     HarnessAdapter · resolution chain + ban policy · env-hygiene
│                  contracts · per-trial Workspace sandbox
│   ├── ClaudeCodeAdapter   (trace parser + resolution + probe; F6)
│   ├── OpenCodeAdapter     (+ its trace parser)
│   ├── DirectAPIAdapter
│   └── ReplayAdapter       (test/replay double)
├── JudgeKit       Judge protocol · text judge (AnthropicAPIJudge) · grounded
│                  judge (sandbox-reading adapters) · ReplayJudge
├── RunKit         trial planner/scheduler · memory-aware concurrency · watchdog +
│                  transient-retry · run records · offline re-grade & re-aggregate
├── AnalysisKit    failure taxonomy · axial coding (Track B corrective-turn mining) ·
│                  lever routing · baseline drift engine (order parameters;
│                  generalizing/stuck rules) · EditProposal drafting (suggest)
├── IterateKit     git-worktree lifecycle (≠ trial Workspace) · content-anchored
│                  EditApply (exact-once, refuse-on-ambiguity; `suggest --apply`
│                  reuses it via CLI wiring) · pinned-suite re-measure via RunKit ·
│                  regression guard + auto-revert
├── RenderKit      TTY tables/styling (NO_COLOR-aware) · versioned JSON encoders ·
│                  HTML report writer
├── ProjectKit     project discovery (walk to skillet.yaml/.git) · -C resolution ·
│                  config load/save (via EDDCore codec) · `init` scaffolding —
│                  filesystem effects, kept OUT of the executable so they stay unit-testable
└── skillet        executable target — ALL swift-argument-parser commands + wiring
                   (≤ ~50 lines each); renders errors. There is NO separate skilletCLI
                   library: the executable itself is the top wiring layer
```

**Dependency rule:** a strictly downward DAG —

```
skillet (executable) → { IterateKit, AnalysisKit, RunKit, RenderKit }
       → { HarnessKit, JudgeKit, ScoreKit, LintKit, CorpusKit, ProjectKit }
       → TraceKit → EDDCore
```

`EDDCore` is pure and synchronous; everything probabilistic or effectful lives behind a protocol above it. This is what makes P8 testable rather than aspirational.

**The loop is the org chart.** The middle layer is mechanism (how to run one process, grade one criterion, score one output); the top layer is the EDD loop itself. Every spine stage has exactly one owner:

| Spine stage | Owner | Surface |
|---|---|---|
| Discover | CorpusKit (+ TraceKit heuristics) | `capture`, `friction` |
| Codify | EDDCore + eval scaffolding | `eval new` |
| Measure | RunKit over Harness/Judge/Score | `run`, `grade`, `score` |
| Interpret | AnalysisKit (+ EDDCore contradiction join) | `triage`, `baseline compare\|matrix` |
| Suggest | AnalysisKit (drafting) + EDDCore gates (prioritizing); apply wiring via IterateKit's EditApply | `suggest`, `next` |
| Apply | IterateKit | `iterate`, `suggest --apply` |
| Re-measure | IterateKit → RunKit | `iterate` (same invocation) |
| Free static gate | LintKit | `lint`, `fixtures verify`, `doctor`, `hooks` |

**Two lifecycles, two types, on purpose.** `Workspace` (HarnessKit) is the per-trial fixture sandbox — created and destroyed around one harness process. `Worktree` (IterateKit) is the per-proposal copy of the *skill repo* — created around one A/B experiment. They are distinct types with distinct owners precisely so neither can be misused for the other.

**Error model.** One typed `EDDError` hierarchy; every case carries `exitCode`, a human message, and a `remedy` line. The `skillet` executable renders errors; nothing else prints. An unexpected (non-`EDDError`) failure additionally prints a one-line, pre-populated bug-report pointer and stays terse unless `-v` adds the trace.

**Concurrency & cancellation.** `async/await` with a `TaskGroup` per run; Ctrl-C cancels cleanly — in-flight workspaces and worktrees are destroyed, partial run records are marked `aborted`, never half-written. Teardown is itself bounded so it cannot hang; a second Ctrl-C during cleanup is reported and skips the rest, leaning on the crash-only invariant (D3) that the next run always starts from committed files.

**Testing strategy.** `EDDCore`/`TraceKit`: pure unit tests incl. property tests on the gates engine. Boundary codecs: golden files (§7.2). Pipelines end-to-end: `ReplayAdapter` fixtures recorded from real harnesses. One opt-in, env-gated live smoke job per adapter in CI; everything else runs free. Each kit is its own target with its own unit-test target, so every kit is provably importable and testable in isolation. Because *all* argument-parser logic lives in the `skillet` executable (not a library), the command surface is exercised by a separate `IntegrationTests` target that drives the **built binary** through `swift-subprocess` — with test-bundle-relative binary discovery (plus a `SKILLET_TEST_BINARY` override), per-test temp-dir isolation for parallel safety, and Swift Testing tags separating the free suite from env-gated live runs. Test files carry a **300-line soft cap**, honored by splitting suites and extracting harness/fixture helpers (e.g. a `TestHarness` + a project fixture).

**Dependency policy.** `swift-argument-parser`, `swift-yaml` (the 21-DOT-DEV YAML 1.2 parser/emitter for config and evidence frontmatter — it **replaces Yams**, and because config is now YAML there is **no TOML dependency**), `swift-subprocess` (the swiftlang async/await process API; see below), and the standard library; JSON, SARIF, and the frozen boundary formats use Foundation `Codable`, adding no dependency. `swift-yaml` vendors `yaml-cpp` and builds it natively via SwiftPM (no system dependencies, no unsafe flags). All shelling-out is confined to the effectful layers — `EDDCore` spawns nothing — and goes through **`swift-subprocess`**, the *single* sanctioned way to launch a process (no `Foundation.Process`, no raw `posix_spawn`): harness CLIs, the judge, `git` (worktree/status; no libgit2 binding), and the vendored secret scanner (`betterleaks`, §6.1) all run through it, each adapter's environment contract (§10) supplied as the subprocess's explicit environment and the per-trial watchdog (SIGTERM → grace → SIGKILL, §10) mapped onto its graceful→forceful teardown. SQLite via the system library for the cache only.

Two implementation notes refine this policy. (1) `swift-yaml` has **no tagged release** (pinned by revision), and its `YAML` product **requires C++ interop**, which is **viral to direct importers**; it is confined to the isolated **`ConfigYAML`** target (`.interoperabilityMode(.Cxx)`), which exposes a pure-Swift API decoding into `EDDCore.SkilletConfig` — landed in F6. The pure core (`EDDCore`) and every kit stay free of C++-interop mode by consuming a decoded `SkilletConfig` rather than importing `ConfigYAML`; the F6 interop spike confirmed the one unavoidable consequence — the `skillet` executable, a direct importer, is a `.Cxx` leaf (the kits/core are unaffected). (2) `swift-system` (`FilePath`) rides in transitively via `swift-subprocess`, which is now a shipped dependency used by **`HarnessKit`** (the `ProcessLauncher` seam) as well as the `IntegrationTests` harness; both were already sanctioned, so no amendment is needed. Known-good pins at time of writing: `swift-argument-parser` 1.6.2, `swift-subprocess` 0.2.1, `swift-system` 1.5.0, `swift-yaml` rev `e8d1769…`.

---

## 12. Distribution, versioning & stability

**Platforms.** macOS 14+ and Linux (current Ubuntu LTS) from day one — CI in this repo *is* the Linux user.

**Channels.** GitHub Releases (prebuilt binaries per platform/arch), Homebrew tap, Mint, and `swift build` from source. The skillet binary carries no library runtime dependencies; it bundles one vendored companion — `betterleaks` (MIT), per platform/arch, for `capture` secret-sanitization (§6.1) — and requires `git` for `iterate`. Uninstallation is a documented one-liner — remove the binary and the tap/formula; the per-repo `.skillet/` cache is disposable — shown at the foot of the install docs.

**Stability tiers** (documented in the README, enforced by tests):

| Tier | Contract |
|---|---|
| Frozen boundary formats | Never break, ever (golden-tested) |
| Exit codes | Stable API |
| `--json` payloads | Versioned via `schema` field; additive within a major |
| Command names & documented flags | Semver: breaking ⇒ major bump (pre-1.0: minor, with CHANGELOG migration notes) |
| Human TTY output | No promise — explicitly not an API (P7) |

**Privacy.** No telemetry, no network calls except the providers the user configured — and the bundled `betterleaks` runs with validation disabled, so secret-scanning never phones home (§6.1). Privacy also means *secrets never enter the committed corpus*: `capture` redacts credentials in place before writing a bundle (§6.1), so a raw secret stays only in the harness's own session store, never in the repo.

---

## 13. v1 scope line

| Ships in v1 | v1.x | Later / explicitly out |
|---|---|---|
| `init`, `doctor`, `lint` (5-rule SKILL-Lxxx catalog), `run` (both axes, `--ab`, matrix), `capture` (claude-code, incl. `--from-checkpoint`/`--preserve-feedback`), `friction` suite, `triage` Track A + contradictions-first, `baseline compare\|matrix`, `suggest` (+`--apply`), `next` (+`--strict`), `iterate` (batch `--apply`), `report` (TTY + HTML, offline re-aggregate), `migrate friction\|knobs`, `fixtures verify`, `grade --run` re-grade, `bundle list\|stats\|backfill` (trace + meta), `hooks install`, harness ban policy + `which --search`, all §6.2 plumbing | `triage --code-feedback` (Track B axial coding), the diff-revert corrective-turn detector, `codex` adapter, `opencode` sessionCapture, fixtures scaffolding (`eval new --fixture`), the 7 roadmap lint rules, skill-security lint rules, skill-bundle integrity lint rules, variance dashboards, `lint --fix`, `Trace.usage` parsing in `ClaudeCodeAdapter` (until then: trial-count estimates) | Description-optimizer loop (skill-creator owns it; revisit), watch mode, GitHub Action wrapper, TUI, any auto-commit ever |
| Adapters: `claude-code`, `opencode`, `direct-api`, `replay` | | |

**Provenance honesty.** Two columns of work hide in "v1," and they are not the same risk. **Ported** (a working predecessor exists; the job is faithful translation behind the new seams): the runner, scorers, the SARIF reader and `baseline` drift engine, the contradiction join, capture (incl. checkpoint modes), the 5-rule lint catalog, the binary resolver + denylist, fixture-verify, and the suggest/iterate engines (`SuggestSkillMdEdits`, content-anchored `EditApply`, worktree A/B). **Net-new** (no predecessor; the design's largest fresh surface): the gates engine, structured friction/finding files and the evidence lifecycle, `next`, the multi-harness abstraction beyond claude-code, the unified trigger axis, and version-aware corroboration. The line's logic stands — v1 must demonstrate both differentiators (computable runbook, harness matrix) end-to-end on the full loop — but the schedule should weight the net-new column, because that's where the unknowns live.

---

## 14. Open questions

*(The naming question is resolved: D7, title block. Residual diligence noted there: a trademark sanity check against PAN's Skillet family before going public.)*

1. **Second agent adapter at launch:** `opencode` (open-source, easiest to test in CI) vs `codex` (bigger audience) vs `gemini-cli` (now supports Agent Skills with an explicit `activate_skill` step — a clean native trigger-axis signal). Doc assumes `opencode`.
2. **License.** Recommendation: Apache-2.0 (patent grant; Swift-ecosystem norm). MIT acceptable.
3. **HTML viewer.** v1 renders from frozen `benchmark.json` (Python viewer keeps working regardless); full port-and-retire decision deferred to v1.1.
4. **Judge model pinning.** Should `skillet.yaml` *require* an explicit judge model (reproducibility) or float to a provider default (freshness)? Doc assumes required-explicit, set by `init`.
5. **Memory-aware scheduling.** v1 ships the static `concurrency` knob with the OOM rationale documented (§10); whether to add per-process RSS budgeting (auto-derived concurrency) is open — it's the principled fix but adds platform-specific machinery.

6. **A stable `--plain` output mode (clig.dev Output; touches P7).** clig.dev recommends a `--plain`, one-record-per-line columnar surface for `grep`/`awk`, and its Future-proofing section explicitly blesses skillet's stance — *changing human-readable output is fine, point scripters at `--plain`/`--json`*. The tension is contract count: skillet today keeps exactly one machine surface (`--json` + `schema`), and P7 declares TTY output a non-API precisely so it can evolve freely; `--plain` adds a *second* surface to freeze, version, and golden-test (a new row in the §12 / constitution stability tiers), for users who would rather pipe to `awk` than `jq`. Affected if adopted: P7, §5.5, §12 + constitution stability tiers, Appendix B. *Recommendation:* defer — `--json` already serves machine consumers; revisit if real usage shows scripters parsing TTY output (the exact failure `--plain` exists to prevent). **Decided 2026-06-20: deferred** — `--json` remains the single machine surface.

7. **User-level config tier — RESOLVED (2026-06-20): adopted as a preferences-only tier.** A cross-repo *preferences* tier (`$XDG_CONFIG_HOME/skillet/config.yaml`) was added to the §5.2 precedence chain (`… > repo skillet.yaml > user config (XDG) > built-in defaults`), with **D3 scoped to workflow state** so the tier carries defaults only and never originates evidence, gate, or run state (§7.1, §7.5; constitution Repository State Discipline clarified). The gitignored cache stays repo-local (`.skillet/`). clig.dev's category-2 user preferences were the real gap; its category-3 project config skillet already satisfied.

8. **Held-out proof for edits (R2 — staged from the v0.8 cross-reference).** The loop drafts an edit *from* a failing eval and proves it by *that same* eval passing; if the proving eval is the one the edit was tuned to, the proof is circular and the *corroboration-integrity* outcome is hollow. Should `suggest`/`iterate` and the §8 `prose_edit`/`codify` gates require the proving eval to be a **sibling/held-out** case in the same failure class, distinct from the drafting eval? *Cross-ref:* `skill-eval-harness`'s `tune`/`holdout`/`holdback` splits; SkillOpt's held-out-validation accept gate; standard EDD/ML train-test discipline. *Affected:* §8, §5.2 `gates`, §6.1 `iterate`/`suggest`, D6, the integrity metric. *Recommendation:* adopt a held-out/sibling-proof rule. **Decided 2026-06-24: adopted.** Encoded as the **Held-out proof** gate (§8) + the `gates.proof.require_holdout` knob (§5.2, default on) + the `iterate --mark` proof step (§6.1): a `skill_md` edit is `proven` only when a held-out sibling eval (same failure class, *not* its drafting eval) also passes — advisory when the class has no sibling (`next` says so), enforced under `--strict`. No schema change (uses `root_cause`/`cluster` + the proposal's `expected`/`motivation`). Graduated to ROADMAP Phase 6 (F5).

9. **Deterministic process-assertions over the `Trace` (R3).** The trigger axis already asserts *did the skill fire* over `skillInvocations`; should skillet generalize that to a **deterministic, judge-free assertion pass** over the existing `Trace` — skill loaded, a tool-call present or in a given order, within a token budget — as free signal *before* the paid judge? **Sub-question (R7):** can assertions read the existing `Trace` fields (`turns[].toolCalls`, `skillInvocations`, `usage`), or does `Trace` need a separate metrics/events object (cf. `skill-eval-harness`'s `events.json` + `metrics.json`)? *Cross-ref:* `skill-eval-harness` process assertions; `agent-skill-evals` tool-call assertions. *Affected:* §9.3, §10, §6.1 `run`, §4. *Recommendation:* adopt reading existing fields; treat the schema split (R7) as a deferred sub-decision, revisited only if assertions require it. **Pending sign-off** (extends the grading contract); ROADMAP "Candidate Enhancements."

10. **Ablation arms (R5).** `SkillSet` (§9.2) today is whole-skill on/off (`.none`) plus sibling visibility (`.only`); should it gain **partial-skill ablation** variants — drop one section, one `references/` file, or one rule — so `run --ab` can isolate *which part* of a skill earns its tokens, feeding the *evidence-to-edit-ratio* (resist-over-editing) outcome? *Cross-ref:* `skill-eval-harness` ablation arms; SkillOpt's add/delete/replace edit operators. *Affected:* §9.2 `SkillSet`, §6.1 `run --ab`, §10. *Recommendation:* adopt as a v1.x extension. **Pending sign-off** (extends the A/B contract); ROADMAP "Candidate Enhancements."

---

## Appendix A — A worked session

Tuesday. You used `docc-articles` on a real package and hand-fixed the output.

```
$ skillet capture --skill docc-articles --slug urlrouting-middleware --last
captured sessions/2026-06-09-urlrouting-middleware.*   (trace: 38 turns, 1 corrective)
→ looks like you hand-fixed something: skillet friction add --skill docc-articles \
    --sessions 2026-06-09-urlrouting-middleware

$ skillet friction add --skill docc-articles --sessions 2026-06-09-urlrouting-middleware
  domain      › networking
  lever       › skill_md
  root cause  › SKILL.md:142 — rule-of-three density
[$EDITOR opens for the prose body]
logged friction/2026-06-09-rule-of-three-density.md

$ skillet next docc-articles
ACT NOW
  ◆ codify: rule-of-three-density   evidence 3/3 across 3 domains ✓
      → skillet eval new docc-articles --from-friction 2026-06-09-rule-of-three-density

$ skillet eval new docc-articles --from-friction 2026-06-09-rule-of-three-density
added evals.json#rule-of-three-density (3 assertions citing SKILL.md:142)
state: codified · confirm it fails today:
      → skillet run docc-articles --eval rule-of-three-density

$ skillet run docc-articles --eval rule-of-three-density
  rule-of-three-density ............ FAIL (0/3)        ← good: it reproduces
→ draft a fix: skillet suggest docc-articles --from 2026-06-09-rule-of-three-density

$ skillet suggest docc-articles --from 2026-06-09-rule-of-three-density --out fix-density.json
drafted 1 EditProposal (SKILL.md:142, content-anchored) → .skillet/proposals/fix-density.json
nothing applied — review the excerpt → proposed_text, then prove it:
      → skillet iterate docc-articles --proposals .skillet/proposals/fix-density.json --apply 0

$ skillet iterate docc-articles --proposals .skillet/proposals/fix-density.json --apply 0
proposals: fix-density.json — applying [0] of 1 in a throwaway worktree
                               before   after    Δ
  rule-of-three-density        0/3      3/3      ▲ fixed
  (12 other evals)             …        …        —
aggregate pass^k               0.88     0.94     ▲   (observed k=3, no contradictions)
no regressions · proposal set proven  (friction marked proven via --mark)
→ land it: skillet suggest --proposals .skillet/proposals/fix-density.json --apply=0

$ skillet suggest --proposals .skillet/proposals/fix-density.json --apply=0
applied 1 edit to skills/docc-articles/SKILL.md (working tree only — commit is yours)

$ git commit -am "docc-articles: ground rule-of-three in density guidance (proven: rule-of-three-density)"
```

Eight commands, each one suggested by the last. The machine drafted, measured, proved, and — only on your explicit `--apply` — materialized; the human made every judgment, and the commit was yours alone.

## Appendix B — clig.dev conformance checklist

Re-verified against the live guidelines (v0.5). `✓` = conformant; `→` = deliberate divergence
(rationale at the foot, decision staged in §14).

- **The basics** — ArgumentParser; zero/non-zero exit (§5.4); stdout for data, stderr for chatter (P7).
- **Help** — examples-first `--help`; bare invocation explains the loop; `-h`/`--help`/`help`;
  "did you mean"; support/issues line on top-level `--help` and `--version`; man pages from ArgumentParser.
- **Output** — human-readable default; `--json` everywhere with `schema`; `-q`/`-v`; suggested-next-step
  lines; symbols used sparingly; pager (`$PAGER`) for large output; no animation when piped.
  → no `--plain` (Open Q6 — `--json` is the single machine surface, P7).
- **Color** — `--color auto|always|never` (≡ `--no-color`); honors `NO_COLOR` and `TERM=dumb`; off when not a TTY.
- **Errors** — what/why/fix via a `remedy` line; typed exit codes (§5.4); no trace without `-v`;
  pre-populated bug-report pointer on unexpected failures.
- **Arguments & flags** — flags over args; long form for every flag, short only for common ones; standard
  names (`--json`, `-n`/`--dry-run`, `-q`, `--version`, `-h`/`--help`); `--no-input`; `-` for stdin/stdout;
  safe defaults; never reads a secret from a flag.
- **Interactivity** — prompts only on a TTY; every prompt has a flag; `--no-input` and `--yes`;
  confirmation before large spend (P9).
- **Subcommands** — consistent flags/output; `noun verb` plumbing (`harness list`, `bundle verify`).
  → git-style top-level porcelain verbs (`run`, `triage`) over strict `noun verb` — the git precedent (P1).
- **Robustness** — input validated on read; responsive (<100 ms / print before paid calls); progress on
  long ops; per-trial timeouts (§10); crash-only, recomputable state (D3); aborted runs never half-written.
- **Future-proofing** — additive boundary formats (§7.2); stable exit codes; no catch-all; no arbitrary
  abbreviations; TTY output free to change, scripters pointed at `--json`.
- **Signals** — immediate Ctrl-C; bounded cleanup; second Ctrl-C reported.
- **Configuration** — precedence printed via `--origins` (§5.2); project config version-controlled;
  env-var conventions (uppercase, `SKILLET_`-prefixed); no secrets in env; user-level preferences in `$XDG_CONFIG_HOME/skillet/` (§5.2).
- **Naming** — short, lowercase, memorable (trademark check pending, D7).
- **Distribution** — single binary; native installers; shell completions; semver + CHANGELOG; documented uninstall.
- **Analytics** — none: no telemetry, no phone-home (§12, Principle VI) — exceeding the opt-in bar.

**Deliberate divergences** (clig.dev is guidelines, not rules). `--plain` touches a settled choice (P7)
and is deferred (Open Question 6); the user-level XDG **preferences** tier was adopted (D3 scoped to
workflow state, §5.2). Verb-first porcelain follows git (P1). Secrets-in-env is the one provider-dictated
exception — LLM SDKs read their own key variables — and skillet keeps its *own* surface clean: it never
takes a secret from a skillet flag or variable.

## Appendix C — Similar CLI tools (landscape, June 2026)

Context for why this table exists: skills have exploded — SkillsBench counts ~47,000 unique skills across 6,300+ repositories — while testing them remains rare and mostly vibe-checked. Every tool below lives somewhere on the **Measure** stage (sometimes plus Create/Optimize/Audit); none owns the production loop — Discover → Interpret → Suggest → Apply under corroboration gates with proof — which is `skillet`'s reason to exist (§1).

### C.1 Functional landscape

| Tool | Stack / shape | What it does | Spine coverage |
|---|---|---|---|
| `skill-creator` (Anthropic) — github.com/anthropics/skills | Skill/plugin running *inside* the agent | Official path: scaffolds skills, runs evals with grader agents, aggregates benchmarks, optimizes descriptions; agentskills.io docs describe it automating the eval-iterate workflow | Create + Measure + Optimize |
| `agent-skills-eval` — github.com/darkrishabh/agent-skills-eval | TypeScript CLI, YAML config | Same prompt through `with_skill` / `without_skill` arms via model APIs; a judge grades both against shared assertions; `--baseline` enables the comparison | Measure (A/B) |
| `skill-eval-harness` — github.com/adewale/skill-eval-harness | Python CLI (`uv`) | Paired `with_skill`/`without_skill` plus `old_skill`/**ablation** arms; normalized event/metric traces drive **process assertions** (skill loaded? commands in order? within budget?); pluggable **runner adapters** (Pi, Claude Code, Jetty, Codex); leakage/answer-key hygiene + tune/holdout/holdback splits | Measure (A/B + process assertions) — closest architectural sibling to `skillet run` |
| `skill-up` (Alibaba) — github.com/alibaba/skill-up (+ `zpzjzj/skill-up-action`) | Go CLI, declarative YAML | Workspace setup → skill install → **multi-engine** run (`claude_code`/`codex`/`qodercli`) → tiered judging (`rule_based`/`script`/`agent_judge`) → reports; a GitHub Action runs it across engines in CI | Measure, multi-engine — overlaps `skillet run --matrix`, but prints no per-engine pass^k table |
| `SkillOpt` (Microsoft) — github.com/microsoft/SkillOpt | Python, paper-backed (~9k★) | Autonomous text-space **optimizer**: trajectory-driven add/delete/replace edits to one SKILL.md, accepted only when a **held-out validation score** strictly improves; reports best/tied across a (model × benchmark × harness) grid | Optimize (autonomous; auto-accepts — no human-lands gate) |
| `EvoSkill` (Sentient) — github.com/sentient-agi/EvoSkill | Python, Apache-2.0 (~1k★) | Self-improvement loop that **mines failed trajectories** to synthesize/repair reusable skills; supports 6 agents (Claude Code, OpenCode, OpenHands, Goose, Codex, Harbor); git-versions every program it creates | Create + Optimize (failure-driven; auto-commits) |
| `opencode-skill-creator` — antongulin | TypeScript, OpenCode-only | Skill lifecycle: generate → evaluate → optimize description (train/test split) → benchmark → install | Create + Measure + Optimize |
| Promptfoo — promptfoo.dev | Declarative YAML eval CLI | General prompt/RAG/agent evals; now ships a first-class agent-skills guide driving Codex, Claude, and OpenCode, inferring skill-used signals (e.g. SKILL.md reads) and comparing skill versions across providers | Measure, multi-harness — the closest overlap with `skillet run --matrix` |
| Inspect AI — inspect.aisi.org.uk | Python framework + `inspect eval` CLI (UK AISI + Meridian) | Research-grade: datasets/solvers/scorers, Docker/K8s sandboxing, 200+ prebuilt benchmarks, log viewer | Measure (general agent evals; no skill artifact model) |
| DeepEval — deepeval.com | Python, pytest-style `deepeval test run` | LLM-app eval suites and metrics; positions itself as an eval harness *inside* coding agents and ships its own installable Skill | Measure (app-level) |
| `sample-agent-skill-eval` (AWS) — github.com/aws-samples/sample-agent-skill-eval | Python CLI, binary named `skill-eval` | `skill-eval audit <dir>`: static security scan of skill-standard directories with a 0–100 score/grade and allowlist knobs; pitched as “create with skill-creator → evaluate with skill-eval” | Static audit — a security-flavored cousin of `skillet lint` |
| `Skill-Lab` (`sklab`) — github.com/8ddieHu0314/Skill-Lab | Python CLI | `sklab evaluate` scores a SKILL.md against **37 criteria / 5 dimensions** incl. **5 security checks** (prompt-injection, evaluator-manipulation, unicode-obfuscation, YAML anomalies, suspicious size); **static checks run before** the optional LLM review (`--skip-review`) | Static audit/lint — a deterministic-first cousin of `skillet lint` |
| `skill-eval` (mgechev) — github.com/mgechev/skill-eval | TypeScript framework | Define a task, run the agent in a Docker container, grade how well it followed the skill (Gemini-centric) | Measure |
| SkillTester — research (arXiv) | Academic benchmark | Benchmarks utility *and* security of skills across agent ecosystems | Benchmark |
| OpenAI `eval-skills` guide — developers.openai.com/blog/eval-skills | Methodology, not a tool | Systematic skill testing for Codex, including trigger evals: is the name/description strong enough for the agent to select the skill unaided | Methodology |
| agentskills.io "Evaluating skills" | Official docs | Clean-context runs, iteration directories, LLM-proposed improvements with mandatory human review | Methodology |

Four notes the table surfaces. First, **name collisions**: two public tools already ship a `skill-eval` binary (AWS's audit CLI and mgechev's framework), and a follow-up check found `skillet` equally occupied — Palo Alto Networks ships an entire Skillet product family (skilletlib, SLI, skilletcli, IronSkillet) — see Open Question 1; a June-2026 GitHub sweep found **no collision *inside the eval space***, so the PAN family is the only conflict. Second, the **harness surface keeps widening**: Gemini CLI now supports Agent Skills with an explicit `activate_skill` step, making it both a future adapter candidate and an easy trigger-axis signal source. Third, the field is **heating up and consolidating** — `SkillOpt` (~9k★) and `EvoSkill` (~1k★) are paper-backed and growing fast — yet every entry still lives on Measure/Optimize/Audit; **none owns the production loop** (§1). Fourth, **deterministic pre-judge static checks are now table-stakes** (Skill-Lab, `agent-skill-evals`, and `skill-up` all ship them), so `skillet` treats them as a *principle*, not a differentiator — its wedge is the per-harness pass^k matrix, the normalized-trace adapter seam, the computable runbook, and the human-lands proof loop. Those audit cousins are uniformly *security/structure*-flavored (injection, unicode-obfuscation, suspicious size; `scripts/`/asset/reference wiring) — exactly what `skillet` keeps **out** of `lint`'s quality core and defers as the **skill-security** (F12) and **skill-bundle-integrity** (F13) tiers (§13 v1.x / ROADMAP Phase 8).

### C.2 Design precedents — patterns `skillet` borrows

| Precedent | Pattern borrowed |
|---|---|
| git | Porcelain/plumbing split; repo-as-database; `skillet next` as the loop's `git status` |
| `gh` | Workflow porcelain with a raw escape hatch (`gh api` ↔ `skillet grade`/`score`/`gate eval`) |
| cargo | Opinionated lifecycle verbs over a committed manifest (`skillet.yaml`) |
| terraform | `plan`/`apply` gated writes — `iterate` proves, a human applies |
| pytest / jest | Zero-config drop-in runner; flaky-test discipline (infra-only retries, never re-run assertions) |
| ESLint / SwiftLint / clippy | Stable rule ids (`SKILL-Lxxx`), config-table exemptions, SARIF interchange |
| volta / Bazel toolchains | Deterministic binary resolution chain + version pinning/bans with provenance |
| Betterer-style ratchets | Baseline-diff drift (`skillet baseline compare`) instead of absolute thresholds |
| jscodeshift / codemods | Machine drafts the change, a human reviews and lands it (`skillet suggest`) |

## Appendix D — Research references

The predecessor repo grounds its choices in two tiers: roadmap/principles files carry full citations, while in-code comments deliberately shorthand them ("Wang-style", "clig.dev"). For a public tool that's too thin — contributors who can't see *why* a non-obvious choice exists (un-gated drift, no-k-floor, human-only writes) will re-derive or "simplify" it away. This appendix ships in the repo as `docs/RESEARCH.md`; doc-comments cite into it.

**Verified (HTTP 200, content matched, June 2026 — per the v0.2 review):**

| Grounds | Source |
|---|---|
| EDD methodology, error analysis, codify-what-you-discover, human-in-the-loop | Hamel Husain & Shreya Shankar — *AI Evals FAQ* — hamel.dev/blog/posts/evals-faq/ (incl. *Why is error analysis so important?* and *Should I practice eval-driven development?*); Husain — *Your AI Product Needs Evals*; *A Field Guide to Rapidly Improving AI Products* |
| Deterministic-graders-first; grade what was produced; "an eval at 100% provides no improvement signal" | Anthropic — *Demystifying evals for AI agents* — anthropic.com/engineering/demystifying-evals-for-ai-agents |
| pass^k reliability metric (and its pass@k predecessor) | Yao et al., *τ-bench* (arXiv:2406.12045); Chen et al., *Evaluating LLMs Trained on Code* (arXiv:2107.03374) |
| LLM-as-judge baseline; judge validation & criteria drift; independent ground-truth verification | Zheng et al., *MT-Bench* (arXiv:2306.05685); Shankar et al., *Who Validates the Validators?* (UIST 2024, arXiv:2404.12272); Dhuliawala et al., *Chain-of-Verification* (arXiv:2309.11495) |
| Self-evolving evals / drift detection (the `baseline` subsystem) | Lun Wang — *Your Evals Will Break and You Won't See It Coming* — wanglun1996.github.io/blog/your-evals-will-break.html |
| Open → axial coding (Track B's qualitative method) | Grounded theory (Glaser & Strauss 1967; Strauss & Corbin 1990) |
| CLI conventions: config precedence & XDG, human-first output, color, progress/responsiveness, standard flags (`--version`/`--no-input`/`--plain`/`--json`), env-var hygiene, no-telemetry | clig.dev; The Twelve-Factor App §III (12factor.net/config); no-color.org |
| Skill-authoring spec the lint catalog codifies; docs craft; SARIF interchange | Anthropic — Agent Skills best practices (platform.claude.com); Diátaxis (diataxis.fr); SARIF 2.1.0 (OASIS) |

**Repo-cited, not independently verified — resolve before publishing:**

| Grounds | Source |
|---|---|
| Judge calibration (backs the contradiction gate) | NVIDIA — *Judge's Verdict* — arXiv:2510.09738 |
| Suggest→apply loop grounding | *GEPA* — arXiv:2507.19457 (ICLR'26) |
| "Engineers design, agents implement" ownership stance | HollandTech — *Claude Is Not Your Architect* (2026) — no public URL located |
| AI-slop scorer wordlists | Wikipedia editor lists `WP:AIVOCAB`, `WP:AIPUFFERY`, `WP:RO3`, `WP:AIDASH` |
