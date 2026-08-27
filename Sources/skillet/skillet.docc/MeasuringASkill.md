# Measuring a skill

@Metadata {
    @TitleHeading("How-To Guide")
    @Available(macOS, introduced: "14.0")
}

Take a skill you already have, point Claude at it, and get a reliability score you can put in a commit message — with the cost checked before anything is spent.

## Overview

This assumes you have a skill with behavioural tests and want a real number for it. If you have
neither yet, walk <doc:TryingItForFree> first — it builds both on a throwaway project for nothing.

The measurement runs each test *k* times and reports how often the skill got it right every single
time. A skill that passes once and fails twice has not been fixed, and a single run cannot tell you
that.

## Give the tool a Claude binary

The paid stages shell out to the `claude` command-line tool. It is resolved in this order:

1. the `SKILLET_CLAUDE_CODE_BIN` environment variable
2. `harness.claude-code.path` in `skillet.yaml`
3. your `PATH`

**If Claude Code is installed normally, there is nothing to configure.** Confirm it is present and
signed in — neither call spends anything:

```sh
claude --version
claude auth status --json    # expects "loggedIn": true
```

**If it is not on your `PATH`** but your editor bundles one — Xcode's or Zed's coding agent both do —
point the environment variable at that binary instead. Those paths contain a version or a cache hash
that changes and gets cleaned up, so resolve it fresh each session and never commit it.

## Preflight for free

`doctor` checks everything a paid run depends on, and spends nothing doing it:

```sh
skillet doctor <skill>
```

It reports one line per check — configuration, finding and signing in to Claude, whether the skill is
actually visible to the agent, and the static gate — with a fix line under every failure. It exits
with an environment error if something would break a paid run. A missing credential is a warning
here, because the run itself refuses before spending rather than failing halfway.

## Check the cost, then run

```sh
skillet run <skill> --dry-run          # the plan and the call estimate, nothing spent
skillet run <skill> --runs 1 --yes     # PAID
```

Start with `--runs 1`. It is not a real reliability measurement — one trial cannot show
inconsistency — but it proves the whole path works before you pay for the full count.

`--yes` confirms the spend. Without it, the tool prompts only when it is genuinely talking to a
person at a terminal, and otherwise refuses. That is deliberate: an automated pipeline never blocks
waiting for input and never spends by surprise.

Once it works, drop `--runs 1` and take the real measurement at the configured count.

## Read the result

The score re-derives from committed files, so the scratch folder is disposable:

```sh
cat skills/<skill>/evaluations/benchmark.json    # per-test results and the summary
cat skills/<skill>/evaluations/grading.json      # per-expectation verdicts and evidence
skillet run <skill> --json                       # machine-readable, schema skillet.run/1
```

Commit both files under `evaluations/`. Do not commit `.skillet/` — `init` already ignores it, and
nothing in it is authoritative.

A result below perfect with mixed passes is not an error. It means the skill behaved inconsistently
across trials, which is the measurement doing its job. Raise the trial count to see the rate more
precisely.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | success |
| `1` | a measured failure — a test failed, or passed only sometimes |
| `2` | usage — bad flags, unknown skill, no tests, a spend that needs confirming |
| `3` | environment — Claude missing, not signed in, a refused version, or a machine problem |
| `4` | a broken file in your project — unreadable tests, or a fixture outside the skill |
| `5` | a gate refused — for example a request over the size ceiling without `--yes` |
| `75` | nothing could be measured and trying again may work — attempts never got graded, and nothing that did get graded failed |
| `70` | a defect in skillet itself, not in your input or environment |

## When something fails

Run `skillet doctor <skill>` first — it prints a fix line under every failure, and the cases below
map to its rows.

**Environment error, "could not find the claude-code binary."** Claude is not on your `PATH` and no
override is set. Install it, or point `SKILLET_CLAUDE_CODE_BIN` at an editor-bundled binary.

**Environment error naming a failed call.** The tool found Claude and the call itself failed — check
that you are signed in, that you are inside any usage limits, and that the configured model name is
valid. This is a different message from "could not find it", on purpose.

**Usage error about confirming spend.** You are over the configured trial threshold on a
non-interactive shell. Pass `--yes`, or `--dry-run` to preview instead.

**A broken-file error on a fixture or test.** A test referenced an input file that is missing,
outside the skill, a shortcut, hidden, or somewhere private; or a test declared no expectations. Keep
input files under `fixtures/` as real files, and give every test at least one expectation.

## Next

- <doc:TurningEvidenceIntoAFix> — when the number is not good enough, turn the failures into a fix.
