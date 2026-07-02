# Testing skillet end-to-end

@Metadata {
    @TitleHeading("How-To Guide")
    @Available(macOS, introduced: "14.0")
}

Run skillet's `init` → `lint` → `run` loop on a throwaway repo — through a real `claude-code` run that reports a `pass^k` score — to confirm every Phase-1 command works end to end.

## Overview

This guide takes you from a fresh checkout to a measured `pass^k` result, exercising each command in order. The free stages come first — `lint`, and a `--replay` run that calls no model — then the one paid stage: a live `run` that shells the [`claude` CLI](https://code.claude.com/docs/en/cli-reference), always estimated and confirmed before it spends.

It stays on *running* the commands. It doesn't teach how to author an effective `SKILL.md` (your skill-authoring tool owns that) or explain the `pass^k` methodology itself (the reliability score and why it's read at the minimum trial count is a separate topic) — here, `pass^k` is just the number a run reports.

You supply Claude one of two ways: a normal Claude Code install on your `PATH`, or — if you don't have one — the binary an editor's coding agent bundles (Xcode or Zed). Step 5 covers both.

> Note: In CI (when wired) you run only the free stages. The `--replay` path is the pull-request gate; the single paid path is an opt-in, env-gated smoke test (`SKILLET_LIVE_SMOKE=1`).

## Prerequisites

- **Swift 6** on **macOS 14+** — to build the toolkit.
- A terminal and `git`.
- *For the live run only* — **Claude Code installed and authenticated**, either on your `PATH` or bundled by Xcode's or Zed's coding agent (step 5). The free stages need none of this.

## 1. Build skillet

```sh
cd ~/Developer/skillet
swift build
alias skillet="$PWD/.build/debug/skillet"   # this shell session only
```

## 2. Adopt skillet in a repo

`skillet init` is idempotent and writes a committed `skillet.yaml`, a self-owned gitignored `.skillet/`, and a `skills/` root.

```sh
mkdir -p ~/tmp/skillet-demo && cd ~/tmp/skillet-demo
git init -q          # gives skillet a project boundary
skillet init
```

```
Initialized skillet
  created 4 · skipped 0 · skills 0
  + .skillet
  + .skillet/.gitignore
  + skillet.yaml
  + skills
→ next: skillet lint · skillet run
```

## 3. Add a skill and its evals

A skill is a `SKILL.md` plus an `evaluations/evals.json`:

```sh
mkdir -p skills/greeter/evaluations
cat > skills/greeter/SKILL.md <<'EOF'
---
name: greeter
description: replies concisely with exactly what is asked
---
When asked, reply with exactly what the user requested and nothing else.
EOF
cat > skills/greeter/evaluations/evals.json <<'EOF'
{"skill_name":"greeter","evals":[
  {"id":0,"prompt":"Reply with exactly the word: DONE","expectations":["The response contains the word DONE"]},
  {"id":1,"prompt":"Reply with exactly: 42","expectations":["The response contains 42"]},
  {"id":2,"prompt":"Say only: ready","expectations":["The response contains the word ready"]}
]}
EOF
```

Each eval needs at least one `expectations` entry — an eval with none can't measure behavior and is rejected before any spend. Input `files` (if an eval declares them) go under `fixtures/` (or `evaluations/fixtures/`) and are referenced relatively; absolute paths, `..`, symlinks, hidden files, and any other `evaluations/` path are refused — the model never sees the eval's own answers or records.

## 4. Run the free gates (no spend)

`lint` is the cheapest gate — free, model-free static analysis meant to run before any paid command:

```sh
skillet lint            # → "✓ lint: no findings", exit 0
```

`--dry-run` (alias `-n`) estimates the trial count and spends nothing:

```sh
skillet run greeter --dry-run
# plan: 3 eval(s) × k=3 = 9 trial(s) for greeter (nothing spent)
```

The `--replay` path proves the whole run → judge → `pass^k` → records pipeline with no model calls — this is exactly what CI uses:

```sh
skillet run greeter --replay
```

```
✓ run: greeter — pass^k 1.00 (k=3)
EVAL  STATUS  PASSES
0     pass    3/3
1     pass    3/3
2     pass    3/3
3 passed · 0 flaky · 0 failed · observed k=3
```

This writes `skills/greeter/evaluations/benchmark.json` and `grading.json`.

## 5. Provide a Claude binary

`run` shells the `claude` CLI. skillet resolves it in order: `SKILLET_CLAUDE_CODE_BIN` env → `harness.claude-code.path` in `skillet.yaml` → `PATH` (a `--harness-path` flag is reserved as the chain's first link but is not wired yet — Phase 7).

**Default — Claude Code on `PATH`.** If you installed Claude Code the usual way (`npm i -g @anthropic-ai/claude-code`, or the [native installer](https://code.claude.com/docs/en/setup)), skillet finds it automatically — nothing to configure. Confirm it's present and authenticated (neither call spends):

```sh
claude --version            # e.g. 2.1.191 (Claude Code)
claude auth status --json   # must show "loggedIn": true
```

If that works, **skip to step 6** — there's nothing to set.

**Optional — an editor-bundled (ACP) binary.** If `claude` isn't on your `PATH` but you use an editor whose coding agent ships one — **Xcode** or **Zed** — point skillet at it with `SKILLET_CLAUDE_CODE_BIN`. They live under:

- Xcode coding agent: `~/Library/Developer/Xcode/CodingAssistant/Agents/claude/<version>/claude`
- Zed: `~/Library/Application Support/Zed/node/cache/_npx/<hash>/node_modules/@anthropic-ai/claude-agent-sdk-darwin-arm64/claude`

Resolve the newest across both roots and verify it (non-spending):

```sh
export SKILLET_CLAUDE_CODE_BIN="$(find \
  ~/Library/Developer/Xcode/CodingAssistant/Agents \
  ~/Library/Application\ Support/Zed/node/cache/_npx \
  -name claude -type f -perm +111 2>/dev/null \
  | xargs -I{} stat -f '%m %N' {} 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
echo "$SKILLET_CLAUDE_CODE_BIN"
"$SKILLET_CLAUDE_CODE_BIN" --version            # e.g. 2.1.154 (Xcode) / 2.1.191 (Zed)
"$SKILLET_CLAUDE_CODE_BIN" auth status --json   # "loggedIn": true
```

> Warning: These editor paths are ephemeral — the Xcode version directory and Zed's npm-cache hash change and get garbage-collected — so resolve fresh each session and never commit the path. skillet's probe refuses a denylisted (known-bad) version, so a stale pick fails loud rather than running.

## 6. Run for real (paid)

Sanity-check the probe, then run. Start with `--runs 1` to keep the first real run cheap — about two Claude calls per eval (one trial, one judge):

```sh
skillet harness info                 # claude-code → available (<version>), authenticated
skillet run greeter --dry-run        # confirm the plan/estimate
skillet run greeter --runs 1 --yes   # PAID: shells `claude -p` per trial + the judge
```

> Important: `--yes` confirms the spend. Omit it and skillet prompts only when both stdin and stdout are a terminal, and otherwise refuses (like `--no-input`) — so CI never blocks or spends by surprise. Before any trial, `run` probes the harness: a missing, unauthenticated, or denylisted binary fails fast with exit 3, spending nothing.

## 7. Read the results

`pass^k` re-derives from the committed `benchmark.json` — delete `.skillet/` and nothing is lost.

```sh
cat skills/greeter/evaluations/benchmark.json   # metadata, per-eval results, run_summary (pass_k)
cat skills/greeter/evaluations/grading.json     # per-expectation {text, passed, evidence}
ls .skillet/runs/*/                              # gitignored forensics (trace.json, verdicts.json, …)
skillet run greeter --replay --json             # machine-readable (schema: skillet.run/1)
```

Commit the two `evaluations/*.json` files. **Don't** commit `.skillet/` — `init` already gitignores it, and it's a deletable cache (nothing there is authoritative).

## Exit codes

For scripting and CI:

| Code | Meaning |
|---|---|
| `0` | all evals PASS |
| `1` | any FAIL or FLAKY (`pass^k` demands all *k* trials pass) |
| `2` | usage error: bad flags, unknown skill, no evals, `--runs < 1` |
| `3` | harness probe failed: missing, unauthenticated, or denylisted binary |
| `4` | corrupt `evals.json`, or an out-of-skill / symlinked / private / zero-expectation eval |

## Troubleshooting

**`run` exits 3 with "could not find the claude-code binary."** `claude` isn't on `PATH` and no override is set. Install Claude Code, or follow step 5 to point `SKILLET_CLAUDE_CODE_BIN` at an editor-bundled binary.

**`run` exits 3 with "not authenticated."** The resolved binary has no usable credential. Run `claude auth login`, or set `ANTHROPIC_API_KEY` / `CLAUDE_CODE_OAUTH_TOKEN` (see [generating a long-lived token](https://code.claude.com/docs/en/authentication)), then re-run.

**`run` exits 2 with "spend requires confirmation."** You're over `runs.confirm_above_trials` on a non-interactive shell. Pass `--yes` to proceed, or `--dry-run` to preview without spending.

**`run` exits 4 on a fixture or eval.** An eval referenced a `files[]` entry that's missing, out-of-skill, symlinked, hidden, or private (anything under `evaluations/` other than `evaluations/fixtures/`), or it declared zero `expectations`. Keep fixtures under `fixtures/` (or `evaluations/fixtures/`) as real (non-symlink) files, and give every eval at least one expectation.

> Note: A flaky result (`pass^k` below 1.0 with mixed PASSES) isn't an error — it's the measurement working. It means the skill behaved inconsistently across trials; raise `--runs` to see the rate more precisely.

## Cleanup and next steps

```sh
unset SKILLET_CLAUDE_CODE_BIN
rm -rf ~/tmp/skillet-demo
```

For a real skill, commit `evaluations/benchmark.json` + `grading.json` after a run — they're the eval-viewer's contract and the source `pass^k` re-derives from. A *file-writing* skill's live run may need a more permissive permission mode (an env-gated tuning point, not yet exposed).
