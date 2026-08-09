# Turning evidence into a fix

@Metadata {
    @TitleHeading("How-To Guide")
    @Available(macOS, introduced: "14.0")
}

Record real sessions, let the tool group what went wrong into categories, and draft a minimal edit to the skill from what it found — with a human landing every change.

## Overview

This picks up where measuring leaves off: the score is not good enough, and you want to know *why*
and what to change. It assumes you have a skill in a project and have used the agent on real work.

Three stages, only the last of which spends anything: record what happened, group the failures, draft
an edit. Nothing here edits your skill — the last stage writes a proposal for you to read.

## 1. Record a session as evidence

```sh
skillet capture --skill <skill> --slug <short-name>
```

This takes your most recent Claude session and writes it into the skill's folder as a stored record,
scored on the way in. Add `--session <ref>` to pick a specific one rather than the newest.

**Secrets are removed before anything is written, always.** There is no flag to turn that off, and if
the secret scanner cannot run, the capture fails rather than writing an unscrubbed file. Add
`--fail-on-secret` in an automated pipeline to also fail the build when something was found — the
scrubbed record is still written either way.

Record several. One session is an anecdote; the grouping in the next step needs a corpus to work
with, and the thresholds that decide when a change is justified are counted in sessions and distinct
problem areas.

## 2. Group the failures

```sh
skillet triage <skill>              # writes one file per group
skillet triage <skill> --dry-run    # show the grouping, write nothing
```

This is free. It reads the scored records you captured, clusters what went wrong into categories, and
writes one evidence file per category under `skills/<skill>/evaluations/findings/`.
Use `--since <YYYY-MM-DD>` to narrow the window.

It never overwrites. If a file is already at the name it wants, it says so and leaves both alone, so
re-running is safe and a hand-edited file is never clobbered.

You can also write evidence by hand — when you had to fix output yourself and no recording captures
it, a short note under `skills/<skill>/evaluations/friction/` is read exactly the same way.
<doc:TryingItForFree> shows the shape.

## 3. Draft an edit

```sh
skillet suggest <skill> --from <evidence-id> --dry-run    # free: the request and its size
skillet suggest <skill> --from <evidence-id>              # PAID: one model call
```

Name one or more evidence ids. The request carries those records, any hand-written notes from the
same sessions, and the skill file — and asks for the smallest edit that addresses what was observed,
preferring to delete or tighten rather than add.

The result is written to `.skillet/proposals/<id>.json`. **Nothing is applied.** Each proposed edit
quotes the exact text it would replace, which must appear in the file exactly once, so you can see
precisely what would change.

Free checks run before any spending: the static gate, then a read-only check that Claude is usable,
then the folder is prepared — only then is the one call made.

### What it tells you afterwards

- **A draft was written** — the file is named; go read it.
- **An identical draft already exists** — the same request was made before, so nothing was rewritten
  and you are pointed at the existing file. If you have since written a test and linked it to that
  evidence, the stored list of tests is refreshed and it says so.
- **A different file holds that name** — nothing was overwritten, and it exits with a usage error so
  an automated pipeline cannot mistake it for success. Re-run with `--out <name>.json`.

## 4. Apply the draft you agreed with

Read the proposal first — that is the whole point of it being a file. When you agree with it:

```sh
skillet suggest <skill> --proposals <name>.json --apply --dry-run   # what would land, nothing written
skillet suggest <skill> --proposals <name>.json --apply             # writes your working tree
```

This calls no model and costs nothing. The drafting run prints the exact command, so there is nothing
to retype.

Three things it insists on:

- **Your repository must be clean.** Reverting the change is how you undo it, and that only works if
  everything uncommitted afterwards is the tool's work. Commit or stash first.
- **Every edit must still match.** Each one replaces text that has to appear in the file exactly once.
  If the file has moved on since the draft was written, it is refused rather than guessed at.
- **All of it or none of it.** One stale edit stops the whole draft, so you are never left with a file
  matching neither the original nor the proposal. To take part of a draft, say so: `--edits 0 2`.

**Nothing is committed and nothing is staged.** The change sits in your working tree for you to read
with your normal tools, and the commit is yours.

## 5. Prove it

Measure again with <doc:MeasuringASkill>: the edit is justified when a test that was failing now
passes, repeatedly.

If nothing tests the behaviour the evidence describes, the drafting step says so explicitly rather
than implying the fix is proven. Write the test first — then the same line names it, and the loop
closes.

> Note: Proving an edit automatically, by measuring both versions side by side, is planned but not
> shipped. Today the judging is yours.

## Next

- <doc:MeasuringASkill> — re-measure and confirm the fix held.
