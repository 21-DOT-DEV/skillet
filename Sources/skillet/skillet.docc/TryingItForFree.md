# Trying skillet without spending anything

@Metadata {
    @TitleHeading("Tutorial")
    @Available(macOS, introduced: "14.0")
}

Walk the whole loop on a throwaway project — static checks, a cost preview, a real measurement of produced text, and a drafted-fix preview — without an account, a network call, or a cent.

## Overview

This is a practice run. You will create a disposable project, add a small skill, and use every stage
of skillet that costs nothing, ending with a preview of a proposed edit. Then you delete the folder.

Nothing here calls a model. You do not need Claude installed, a subscription, or an API key. The two
stages that *do* spend money are pointed at, not performed — each has its own guide.

Every command below runs exactly as written, in order, from an empty folder.

> Note: This is a lesson, not a template. When you come back with a real skill of your own, follow
> <doc:MeasuringASkill> and <doc:TurningEvidenceIntoAFix> instead — they start from where you actually are.

## Before you start

You need **Swift 6 on macOS 14+** and nothing else. Build the tool with `swift build` from a checkout,
then put the build folder on your `PATH` so `skillet` resolves — on a debug build that folder is
`.build/debug`.

## 1. Create a project

```sh
mkdir skillet-tour && cd skillet-tour
skillet init
```

```text
Initialized skillet
  created 4 · skipped 0 · skills 0
  + .skillet
  + .skillet/.gitignore
  + skillet.yaml
  + skills

→ next: skillet lint · skillet doctor · skillet run
```

`init` is safe to re-run — it reports what it skipped rather than overwriting. It writes a committed
`skillet.yaml`, a `skills/` folder, and a self-ignoring `.skillet/` scratch folder you never commit.

## 2. Add a skill and its tests

A skill is a `SKILL.md` plus a set of behavioural tests. Each test gives a prompt and states what a
good answer contains.

```sh
mkdir -p skills/greeter/evaluations
cat > skills/greeter/SKILL.md <<'EOF'
---
name: greeter
description: replies with exactly what was asked for and nothing else
---
When asked for something specific, reply with exactly that and stop. No preamble, no summary.
EOF
cat > skills/greeter/evaluations/evals.json <<'EOF'
{"skill_name":"greeter","evals":[
  {"id":0,"prompt":"Reply with exactly the word: DONE","expectations":["The response contains the word DONE"]},
  {"id":1,"prompt":"Reply with exactly: 42","expectations":["The response contains 42"]},
  {"id":2,"prompt":"Say only: ready","expectations":["The response contains the word ready"]}
]}
EOF
```

Every test needs at least one expectation — one with none cannot measure anything and is refused
before any spending.

## 3. Check the skill statically

`lint` is the cheapest gate: no model, no network, and it runs before every paid command anyway.

```sh
skillet lint
```

```text
✓ lint: no findings
→ next: skillet run
```

## 4. See what a measured run would cost

`--dry-run` plans the work and stops. This is how you find out what you would be spending before you
spend it.

```sh
skillet run greeter --dry-run
```

```text
note: no usable trigger-eval.json — trigger axis skipped (add {query, should_trigger} cases to run it)
plan: 3 eval(s) × k=3 = 9 trial(s) ≈ 18 model call(s) for greeter (nothing spent)
```

Three tests, run three times each, is nine trials — and roughly two model calls per trial, because
each answer is also graded. Running each test repeatedly is the point: a skill that works once and
fails twice has not been fixed.

## 5. Measure produced text for free

`score` runs deterministic checks over text an agent produced. No model grades it, so it costs
nothing and gives the same answer every time. Write something with the habits it looks for:

```sh
cat > produced.txt <<'EOF'
Additionally, this meticulously crafted summary delves into the intricate tapestry
of the request. It stands as a testament to the vibrant interplay of ideas.
EOF
skillet score produced.txt
```

```text
RULE        LEVEL  RANK  FILE:LINE       MESSAGE
SKILL-S001  error  100   produced.txt:1  AI-slop vocabulary: `Additionally`
SKILL-S001  error  100   produced.txt:1  AI-slop vocabulary: `meticulously`
SKILL-S001  error  100   produced.txt:1  AI-slop vocabulary: `intricate`
SKILL-S001  error  100   produced.txt:1  AI-slop vocabulary: `tapestry`
SKILL-S002  error  100   produced.txt:2  Marketing puffery: `stands as`
SKILL-S001  error  100   produced.txt:2  AI-slop vocabulary: `testament`
SKILL-S001  error  100   produced.txt:2  AI-slop vocabulary: `vibrant`
SKILL-S002  error  100   produced.txt:2  Marketing puffery: `vibrant`
SKILL-S001  error  100   produced.txt:2  AI-slop vocabulary: `interplay`

9 findings (9 error · 0 warning) across 1 file
→ next: skillet lint · skillet run · skillet triage
```

Note the exit status is success even with nine findings. `score` reports; it does not gate. What
gates is a behavioural test failing.

## 6. Write down a problem you hit

Not every failure shows up in a test. When you have to fix an agent's output by hand, that is worth
recording — a short note, in the skill's folder, in a shape the tool can read later.

```sh
mkdir -p skills/greeter/evaluations/friction
cat > skills/greeter/evaluations/friction/2026-06-10-vague-reply.md <<'EOF'
---
schema: skillet.friction/1
id: 2026-06-10-vague-reply
skill: greeter
domain: greeter
lever: skill_md
state: logged
sessions: [2026-06-10-demo]
---
Asked for one word and got three sentences of preamble. Trimmed it by hand.
EOF
```

The file name must match the `id` inside it, and the `id` is a date followed by a short dashed name.

## 7. Preview a drafted fix

`suggest` reads the notes you name, plus the skill file, and asks a model to draft a minimal edit.
With `--dry-run` it assembles the request, tells you what it would cost, and sends nothing.

```sh
skillet suggest greeter --from 2026-06-10-vague-reply --dry-run
```

```text
suggest — greeter
  model            claude-sonnet-4-6
  instructions     v1
  evidence         2026-06-10-vague-reply
  proves           (none — no eval is linked to this evidence yet; write one so a fix can be proven)
  prompt size      1130 bytes
  dry run          nothing sent, nothing written
→ next: re-run without --dry-run to draft
```

The `proves` line is the tool refusing to pretend. Nothing yet tests the behaviour that note
describes, so no drafted edit could be proven to fix anything — write a test first, and the same line
will name it.

## 8. See where evidence would come from

The notes in step 6 are hand-written. The other source is recorded sessions, mined automatically:

```sh
skillet triage greeter
```

```text
triage — greeter
  no recordings yet — capture a session to give triage a corpus
→ next: record a session — skillet capture --skill greeter --slug <name>
```

Empty, correctly — you have not recorded any real sessions in a throwaway project.
<doc:TurningEvidenceIntoAFix> picks up from there.

## 9. Clean up

```sh
cd .. && rm -rf skillet-tour
```

## What costs money, and what does not

Everything above was free and stays free. Two things spend:

| Stage | Cost |
|---|---|
| `init`, `lint`, `doctor`, `score`, `capture`, `triage` | free — no model calls |
| `run --dry-run`, `suggest --dry-run` | free — plans and stops |
| `suggest --proposals <name>.json --apply` | free — writes a reviewed draft into your files; no model call |
| `run` | paid — trials plus grading, roughly two calls per trial |
| `suggest` without `--dry-run` | paid — one call per draft |

`doctor` is free too, and it is the right first move once you have Claude installed: it checks your
configuration, whether the tool can find and sign in to Claude, whether your skill is visible to it,
and the static gate — all at once. It is left out of this tour only because it needs Claude present
to tell you anything useful.

## Next

- <doc:MeasuringASkill> — measure a real skill of your own, with the paid run.
- <doc:TurningEvidenceIntoAFix> — record real sessions, cluster the failures, draft a fix.
