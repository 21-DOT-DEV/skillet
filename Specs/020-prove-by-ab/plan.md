# F43 — Prove a proposal by measuring it twice (`skillet iterate`)

| | |
|---|---|
| **Feature** | F43 — Prove a proposal by A/B (Phase 6 · [phase-6-fix-suggestion-iteration.md](../../Roadmap/phase-6-fix-suggestion-iteration.md)) |
| **Command** | `skillet iterate <skill> --proposals <name>.json [--edits <n>...] [--runs <k>] [-n\|--dry-run] [--yes] [--no-input] [--keep-worktree] [--json]` |
| **Status** | **PLANNED** — 2026-08-16. Five unknowns resolved by Q&A before any code. |
| **Adapted from** (concepts, **not** a type port) | `~/Developer/skills/Sources/SkillEvalCLI/IterateCommand.swift` and `SkillEvalKit/IterateOutcome.swift` — the predecessor's working implementation, read closely and departed from in three recorded places (D3, D4, D6); D1 and D2 follow it deliberately, against my own first recommendation in each case — see §10. |
| **Decisions** | **D1 — Strict verdict, disclosed noise, labelled provisional.** · **D2 — Both measurements taken fresh, in one invocation.** · **D3 — A clean repository is required.** · **D4 — The throwaway copy is removed either way; `--keep-worktree` retains it.** · **D5 — Both measurements write outside the copy.** · **D6 — The command line matches its shipped sibling, not the design sketch.** · **D7 — One record, with the paired comparison as an additive block.** · **D8 — A declined cost confirmation leaves `5`, following the published table.** · **D9 — The cost confirmation is extracted so both paid commands share one.** |
| **Assumptions** | **A1 — One increment.** · **A2 — Writes no project state, ever.** · **A3 — Composition, not new machinery.** · **A4 — Every external program through the one sanctioned launcher.** · **A5 — Every test free.** |

## 1. Outcome

You have a saved draft of proposed edits to a skill and you want to know whether they actually help
before putting them in your files. One command measures the skill as it is, applies the edits to a
throwaway copy, measures it again, and prints the per-test difference with a verdict. Nothing you own is
touched. If it passes, you land it with the command that already exists for landing things.

## 2. Scope

**In:** making a disposable copy of the repository; applying a chosen subset of a saved draft into that
copy; measuring both the unedited skill and the edited copy in the same invocation; reporting the
per-test before/after difference with an honest error bar; a verdict; removing the copy.

**Out:** committing anything (forbidden outright); changing any file you own; advancing a piece of
evidence to "proven" (that is **F44**, the next feature, via an opt-in `--mark`); holding back part of
the test set as an unseen check (**F45**); measuring whether the automatic grader agrees with a human
(**F10**, Phase 8 — but see D1, which depends on its absence).

## 3. CLI contract

```
skillet iterate <skill> --proposals <name>.json [--edits <n>...] [--runs <k>]
                        [-n|--dry-run] [--yes] [--no-input] [--keep-worktree] [--json]
```

- `--proposals <name>.json` names a saved draft — a **bare filename**, looked up in the drafts folder,
  never a path. Same rule, same folder, same wording as the command that applies drafts today.
- `--edits 0 2` narrows which of the draft's edits are applied; omitted means all of them.
- `--runs <k>` sets how many times each test is repeated. Same name and meaning as in `skillet run`.
- `-n`/`--dry-run` shows what would be measured and what it would cost, and stops without spending.
- `--yes` proceeds past the cost confirmation without prompting, as it does in `skillet run`. **The
  number left behind on a decline differs from that command** — see D8.
- `--no-input` never prompts; a confirmation that would have been asked is refused instead, so a script
  or scheduled run cannot hang waiting for an answer nobody will type. **This command adds it** —
  `skillet run` is the only shipped command that has it today (`Sources/skillet/RunCommand.swift:59`),
  and every command that can prompt should offer a way to turn prompting off.
- `--keep-worktree` retains the disposable copy instead of removing it, for inspecting what happened.
- **There is no `--apply`.** Applying the edits into the copy is the whole job of this command; a switch
  for it would carry no information, and the word already means *"write into my real files"* on the
  sibling command. See D6.

### Exit codes

| Code | When |
|---|---|
| `0` | measured, and no test scored lower — the edits are proven at the observed repeat count. **This does not mean every test passed**: a skill with a failing test, edited so that nothing gets worse, exits `0`. See the note below the table |
| `1` | at least one test scored lower. This is a **measured** outcome, not a malfunction — the same meaning the code already carries for a skill failing its tests |
| `2` | usage — no draft named, an edit number the draft does not have, a skill that does not match the draft |
| `3` | environment — `git` missing, not inside a repository, the model program unusable |
| `4` | the draft file is unreadable or malformed |
| `5` | a safety check refused and nothing was done — the repository is not clean, the cost confirmation was declined, or a quoted passage has moved, appears more than once, or overlaps another so the edits were not applied. The last of those is what the command that lands edits already answers with `5` (`Sources/skillet/SuggestCommand.swift:548`) |

**Why `0` here does not mean "everything passed".** The published meaning of `0` is *"Success;
everything measured passed"* (`Sources/EDDCore/ExitCode.swift:4`, repeated in the design document's
table at `skillet-design.md:231`). This command answers a narrower question — *is this edit safe to
land* — so it leaves `0` whenever nothing got worse, including when tests were already failing and
still are. That is the same shape as the existing carve-out for the scoring command, which
*"exits 0 even when scorers fire"* (`skillet-design.md:246`), and it needs the same written note beside
it rather than being left to collide with the table. Landing this feature therefore adds a sentence in
both places (§9). The per-test rows show what still fails, so nothing is hidden — only the summary
number is narrower than the table's wording implies.

## 4. What runs, in order

Everything free happens before anything paid, and the cheapest refusals come first.

1. **Resolve the skill** named on the command line ⇒ `2` if there is no such skill.
2. **Read the draft** through the confining reader every untrusted file goes through ⇒ `4` if malformed.
   Then **cross-check the skill** against the draft ⇒ `2` on mismatch.
3. **Resolve the selection.** No `--edits` means every edit; a number outside the draft ⇒ `2`. This sits
   here because the draft is what defines the valid range, so it is the first moment it can be checked —
   and a mistake in what you typed must answer before anything about the state of your machine.
4. **Require a clean repository** (D3) ⇒ `5` when anything is modified, staged, or untracked.
5. **Plan the cost and confirm it, then check the model program is usable.** Two separate checks, not
   one: the cost confirmation asks before spending roughly double a single measurement, and the shared
   readiness check (`SpendGate.swift`) refuses a missing or signed-out setup. **That order matches both
   commands that already spend** — the measured run confirms at `RunCommand.swift:228` and checks
   readiness at `:241`; drafting refuses over its ceiling at `SuggestCommand.swift:240` and checks
   readiness at `:249`. An earlier draft of this plan had them the other way round, which would have made
   this the only paid command of three to ask in a different order. The confirmation is not shared today
   and this feature extracts it — see D9. `--dry-run` stops here and reports.
6. **Make the disposable copy** — `git worktree add --detach <path> HEAD`, outside your repository:
   the last committed state, attached to no branch (D4). Spelled out because the default does the
   opposite, and a copy on a branch can collide with one already checked out.
7. **Apply the selected edits into the copy**, through the same engine the landing command uses — every
   quoted passage must still match exactly once, or nothing is applied and the copy is removed.
8. **Measure the unedited skill** — reading the skill files in your own folder and changing none of
   them. Its trial records are written, like the other measurement's, to a folder of their own under
   the project's scratch area (D5); what is never written to is your skill.
9. **Measure the edited copy.** Both measurements write their trials and grades into *your* project's
   scratch folder, never the copy's — and each into its own folder beneath the run, so the second
   cannot overwrite the first (D5).
10. **Compare, verdict, report** (D1, D7).
11. **Remove the copy** — `git worktree remove --force <path>`, either outcome, unless
    `--keep-worktree`. The force is not optional: applying the edit is what makes the copy differ
    from what was committed, and git refuses to remove a copy in that state (D4).

## 5. The decisions, and why

### D1 — Strict verdict, disclosed noise, labelled provisional

A test scoring lower after the edit than before is a regression, full stop. No statistical allowance is
made for a drop being small.

That is deliberately conservative, and it matches the predecessor, whose own source records the reason
(`SkillEvalKit/IterateOutcome.swift:4-8`): an edit that fixes its target but breaks a sibling test is
blocked, because the point of the gate is that landing after it is safe.

The cost either way is not symmetric. Wrongly blocking a good edit costs you a re-run. Wrongly calling a
bad edit proven puts a regression into a file you then commit, at the exact moment you have decided to
trust the tool. So the gate leans toward blocking.

**But the noise is real and gets shown, not hidden.** A model grading answers disagrees with itself
often enough that a test moving from three-out-of-three to two-out-of-three is frequently run-to-run
variation rather than damage. Every row therefore carries the paired error bar the codebase already
computes, and a drop that sits inside that band is annotated as such. It still blocks. It is never
silently excluded — the predecessor made the same call, annotating rather than discarding.

**Why not threshold on the error bar instead?** Because thresholding presumes you know how noisy your
grader is, and this project has not measured that: the check that compares the automatic grader against
a human is `F10`, Phase 8, unshipped. A statistical band built on an unmeasured error rate looks
rigorous and is not, and its failure mode is passing real regressions. So the verdict prints as
**provisional** until `F10` lands — the same caveat the predecessor prints — and the statistical band
becomes a follow-up then, recorded in §8.

### D2 — Both measurements taken fresh, in one invocation

The "before" number is measured now, not read from a stored earlier run. The two halves of a comparison
are only comparable when one thing differs between them, and a stored measurement was taken on a
different day, with different sampling, possibly against a different version of the model. Folding that
into a number you will read as *"my edit did this"* is a confidently wrong answer, which is the failure
this tool exists to prevent.

The predecessor does the same and says so — its measuring routine's own description
(`IterateCommand.swift:175-177`) states that the tests and fixtures come from whichever skill folder is
being measured, *"so before/after differ only by the SKILL.md edit"*. The call site that measures both
in one pass is `IterateCommand.swift:132-149`.

Honest cost: roughly double a normal run — about 36 model calls for a three-test skill at three repeats
each, stated the way the tool already states estimates elsewhere. The sanctioned lever for making that
cheaper is narrowing *which tests run*, not reusing a stale half; that lever is deferred to §8 because
narrowing also narrows what the regression check can see.

**This departs from the design document, and the departure was missed when this decision was written.**
`skillet-design.md:558` says the command prints deltas *"against the most recent recorded baseline
(running one first if none exists)"* — that is, reuse a stored measurement and only measure fresh when
none exists. D2 does the opposite. The sentence appears exactly once and gives no reasoning, in a
paragraph sketching the command, and §10 (execution and scoring) says nothing about it, so this is a
sketch rather than a considered position — but it is still a settled document saying something else, and
the decision above was reached without noticing that. **Staged** as `skillet-design.md` §14 item 23,
separately from the command-line deviation (item 22) so the two can be signed off independently: one is
what the flags are called, the other is what the numbers mean and what a run costs.

### D3 — A clean repository is required

The disposable copy is built from the last committed state. If your skill file has uncommitted edits,
the copy does not contain them, but the "before" measurement reads your live folder, which does — so the
two halves would differ by your uncommitted work *as well as* the proposed edit, and the verdict would
attribute both to the edit.

The predecessor has no such check; this is a departure, and the reason is D2. The check itself already
exists — the landing command uses it (`Sources/skillet/CleanRepository.swift`) — so this is reuse.

### D4 — The copy is removed either way

It lives outside your repository, so running this never makes your own tree look modified. It is removed
on both outcomes, through git's own removal command rather than by deleting the folder, because deleting
the folder leaves git's bookkeeping behind and those entries accumulate until the branches they hold
cannot be checked out elsewhere. `--keep-worktree` retains it.

**The removal must be forced, and that is safe here.** Applying the edit is precisely what makes the copy
differ from the committed state, so the plain removal refuses every time it matters — verified:
*"fatal: '…' contains modified or untracked files, use --force to delete it"*. One `--force` suffices; a
second is not needed. The usual caution about forcing a delete — that it overrides a safeguard — does not
leave this exposed, because **git itself bounds what can be forced**: asked to force-remove a path that is
not a registered copy of this repository, it refuses with *"is not a working tree"* and touches nothing.
Verified against a real folder holding a real file, which survived. So the guard is structural, not a
matter of getting the path right.

The predecessor *keeps* the copy when the edit passes, so you can commit from it. This project does not,
for a specific reason: it already has one sanctioned way to put a reviewed edit into your files, and the
charter permits only that one. A kept copy would be a second route to landing a change.

**No branch is created.** The predecessor makes one (`IterateCommand.swift:107`) and must therefore
delete it separately afterwards (`:112`, `:166`), because removing a copy does **not** remove the branch
it was on — leave that step out and branches pile up invisibly, each holding a name nothing else can
check out. This command has no use for one: a branch exists so you can commit from the copy, and the
paragraph above rules that out. So the copy is made detached — `git worktree add --detach <path> HEAD`,
because asking for a copy without naming a starting point creates a branch named after the folder, which
is the default and the opposite of what is wanted. Removing the folder is then the whole of cleanup, and
the failure the predecessor guards against no longer exists to guard against.

Attaching to nothing also avoids a second problem: the same branch cannot be checked out in two places at
once, so a branch-attached copy can collide — with the branch you are already on, or with itself on a
repeat run, since the default name comes from the folder. A copy attached to nothing cannot collide.

**No periodic cleanup is needed.** Repeated use of these copies can leave loose objects in the shared
history store, which is why some workflows add a housekeeping step. This command never commits inside the
copy, so it creates no objects and there is nothing for such a step to collect.

Removing it loses nothing you need. The trials and grades live in your project's scratch folder (D5),
and the edited file itself regenerates exactly from the draft, by an engine that refuses rather than
guesses when the text has moved.

### D5 — Both measurements write outside the copy, **and each into its own folder**


The second measurement is pointed at the copy, so its output would naturally land inside the copy and
vanish with it — leaving a verdict whose supporting data is half gone. Both measurements therefore write
into your project's scratch runs folder. The named failure category this avoids is a job that reports
success while quietly losing its artifacts.

**A second way to lose the same evidence.** The measuring loop writes each trial to
`base/eval-<n>/trial-<m>` (`Sources/RunKit/Runner.swift:52`), so pointing both arms at one `base` makes
the second arm overwrite the first file for file — the comparison would still print, from reports held in
memory, while the raw trials backing half of it were gone. Each arm therefore gets its own folder beneath
the run, named for the arm. The predecessor does exactly this, with `baseline/` and `candidate/`
subfolders (`IterateCommand.swift:139,147`); this plan originally said only "outside the copy", which is
necessary and not sufficient.

### D6 — The command line matches its shipped sibling, not the design sketch

The design document sketches `--proposals <file|-> [--apply <indices>...]` (`skillet-design.md:551-556`).
This plan uses `--proposals <name>.json`, `--edits <n>...`, and no `--apply`, because the sibling command
that shipped already uses those words for exactly those jobs, and `--apply` there means *"write into my
real files"*. The published guidance for command-line tools is a single sentence on this: be consistent
across subcommands, use the same flag names for the same things.

Two things this plan records rather than resolves:

- The design document says omitting the subset switch applies **all** edits. The predecessor's help says
  omitting it means **review only, no changes** (`IterateCommand.swift:53`). The two sources contradict
  each other. This plan follows neither literally: previewing is `--dry-run`, the same word `run` and
  the landing command already use, and omitting `--edits` applies all.
- Departing from the design document's synopsis is a change to a settled decision, so it is **staged**
  as `skillet-design.md` §14 item 22, written 2026-08-16 and awaiting sign-off. Nothing in the four
  places that still show the old spelling is edited until then — see §9.

### D7 — One record, with the paired comparison as an additive block

This project has already solved "report two arms and their difference": the A/B feature emits **one**
record whose main fields carry one arm and whose additive block carries the other plus the paired
comparison — per-test differences, their mean, a standard error, and counts of tests that flipped to
passing or failing (`Sources/EDDCore/RunModels.swift:206`). Its own documentation states the rule this
feature depends on: pairing cancels the two arms' shared per-test difficulty, never subtract two
marginal scores, and below two comparable tests the error bar is *absent, not invented*.

This feature emits the same shape under its own name — `skillet.iterate/1`, with the second arm and the
paired rows as an additive block. **Not** the existing block's name: there it means *skill switched on
versus off*, here it means *edit applied versus not*, and a reader must not be told a baseline arm ran.

The flip counts map directly onto the verdict — a regression is a test that flipped down — and the
per-test error bar is what D1 annotates rows with.

### D8 — A declined cost confirmation leaves `5`, following the published table

The exit numbers are a published contract that only changes on a major version. Their own definitions
decide this: `5` means *"a safety gate refused, and nothing was done — not a broken file and not a broken
machine, a deliberate check said no"* (`Sources/EDDCore/ExitCode.swift:19-22`), and `2` means *"usage
error: bad flags or arguments"* (`ExitCode.swift:14`). Declining a confirmation is the first, not the
second — nothing was mistyped.

The drafting command already follows that: its size-ceiling refusal leaves `5`
(`Sources/skillet/SuggestCommand.swift:240`). The measuring command does not — its confirmation leaves
`2` and says so in its own note (`Sources/skillet/RunCommand.swift:586`). The two refusals are the same
event with the same way out: both remedies read *"re-run with --yes"*. So this is one convention with two
spellings, and this feature follows the definition rather than the older spelling.

Outside practice points the same way. Tools that fold a declined confirmation into a generic error leave
scripts unable to tell *"the person said no"* from *"something broke"* — the reason Terraform users have
[asked for a dedicated code](https://github.com/hashicorp/terraform/issues/22701). This project already
has one.

**Recorded, not resolved:** the measuring command's `2` disagrees with the table. Correcting it is a
change to a published contract and needs a version bump, so it is a deferred item (§8), not something
this feature does quietly on the side.

### D9 — The cost confirmation is extracted so both paid commands share one

The routine that prints the estimate and asks for approval is private to one command
(`Sources/skillet/RunCommand.swift:587`), so it cannot be called from here. This feature moves it beside
the readiness check that is already shared, and both commands call it.

The rule of thumb says wait for a third occurrence before sharing, because two copies cannot tell you
whether the similarity is real — and duplication is cheaper than a wrong shared shape. That rule governs
*abstractions you might have guessed wrong about*. It does not govern *a control whose failure mode is
being left out*, where the published guidance is the opposite: use a single routine, because several
implementations means most are correct and some are not.

**This repository already lost that bet once, in the same file.** The readiness check lived only in the
measured-run command; when the drafting command arrived it *"simply forgot, so that command could spend
against a blocked or signed-out setup"* (`Sources/skillet/SpendGate.swift:10-15`). That note ends *"a
future paid command inherits this by calling one function"*. This is that command.

The seam is clean because the two callers differ in exactly one way — the number left on a decline (D8).
So the shared routine answers *must we ask, and did they agree*; each caller reports its own refusal.
Extraction must not change what the measuring command does, which §7 pins with a test.

## 6. Module & layering

- **`EDDCore`** — the report shape (`IterateReport` + its paired block), pure. Reuses the existing
  `pass^k` math and the paired-comparison shape rather than restating either.
- **`IterateKit`** — today this module holds exactly one file, the engine that applies a reviewed edit
  (`EditApply.swift`, from F42). **This feature adds** the pure verdict beside it: given two measurements, produce per-test
  differences, the flip counts, and the strict guard. No file or process access. This is where the
  predecessor's `IterateOutcome` concepts land, rewritten against this project's types.
- **New, thin, in the executable** — the disposable-copy lifecycle: create, remove, and the refusal when
  it cannot be created. Every `git` invocation through the one sanctioned launcher (A4).
- **`skillet`** — the command: parse, gate, orchestrate, render. Effects live here, per the same
  boundary the sibling commands keep.

**Moved, not reused** — the cost confirmation is extracted from the measuring command into the shared
pre-spend file so both call one routine (D9). That edits a command that already ships, so its own
behaviour is pinned by a test first.

**The shape matters, because the two callers must keep answering differently.** The shared routine
decides only *must we ask, and what did you answer* — it returns that, and raises nothing. Each command
turns a refusal into its own error and therefore its own number: the measuring command keeps `2`, this
one leaves `5` (D8). Moving the error out with the rest would change the older command silently, which is
exactly what test 18 exists to catch.

Reused unchanged: the applying engine, the exactly-once matching rule, the readiness check
(`SpendGate.swift`), the measuring loop
(`Runner.run(…base:)` already accepts any directory), the spend gate, the clean-repository check, the
confining reader, and the renderer.

## 7. Test plan (red → green; every test free)

Every test runs without a model. The replay adapter answers from recorded fixtures, so both measurements
are deterministic and cost nothing.

**Pure, in `IterateKitTests`:**
1. No test scores lower ⇒ proven.
2. One test scores lower ⇒ blocked, and that test is named.
3. A test present in only one measurement compares against zero, so a test that vanishes cannot hide a
   regression — the predecessor's rule, kept.
4. A drop inside the error band still blocks, and is annotated as sitting inside it.
5. Below two comparable tests the error bar is absent rather than invented.
6. The verdict text says provisional.

**Through the built command, in `IterateIntegrationTests`:**
7. Clean repository, draft that still matches ⇒ measures twice, prints both, exits 0.
8. Uncommitted work anywhere ⇒ refused at `5` before spending, nothing created.
9. A quoted passage that has moved ⇒ refused, copy removed, nothing measured (no spend).
10. Regression ⇒ exit 1, copy removed, both measurements still on disk.
11. `--keep-worktree` ⇒ copy retained, and its location printed.
12. The copy is gone from git's own list of copies afterwards — not merely absent from disk — **and no
    new branch exists**, since none was created. A test asserting only the first would pass while
    branches accumulated. The run that precedes this applies an edit, so the copy is dirty when it is
    removed; a cleanup that forgot to force would fail here rather than in the field.
13. Neither measurement's output is inside the copy (D5) — assert the files exist after removal.
13a. **Each arm's trials survive the other's** — with two tests and two repeats, count the trial
    folders after a run and find both arms' complete sets, not one arm's overwritten by the other.
14. Nothing is committed and nothing is staged; the live skill file is byte-identical afterwards.
15. `--dry-run` reports the doubled estimate and spends nothing.
16. `--json` emits `skillet.iterate/1` with the paired block, and its numbers equal the printed ones.
17. Declining the cost confirmation here leaves `5`, and the message names the way out (D8).
18. **Extraction changes nothing for the measuring command** — declining its confirmation still leaves
    `2`, still prompts on a terminal, and still refuses without prompting when input is not a terminal.
    Written *before* the extraction, so it fails if the move alters behaviour.
18a. **…including which check answers first.** With both a cost over the threshold *and* an unusable
    model program, the measuring command must still refuse on the cost, not the program. Pinning only the
    number would let the extraction reorder the two checks silently, changing which error a person sees.

**Verification discipline** (the standing rule): each fix or guarantee is checked by undoing it and
confirming the matching test fails.

## 8. Open items deliberately deferred

- **A statistical band instead of a strict guard** — the right destination, blocked on `F10` (measuring
  how often the automatic grader agrees with a human). Revisit when it ships; D1 is written to be
  replaced rather than amended.
- **Narrowing which tests run** (`--eval <id>...` in the design sketch) — the sanctioned way to make this
  cheaper, but it narrows what the regression check can see, so it needs its own decision.
- **All three paid commands ask you to approve a cost before checking the tool can spend it** — the cost
  gate runs first and the readiness check second, in both shipped commands and therefore in this one. So
  you can approve spending and only then be told the model program is signed out. Reversing it would be
  better for a person, and is deliberately *not* done here: it would change two commands that already
  ship, for a feature that has nothing to do with either. Recorded so the ordering is a choice on record
  rather than an accident nobody noticed.
- **The measuring command's declined-confirmation number disagrees with the published table** — it
  leaves `2` (*"bad flags or arguments"*) for something nothing was mistyped in, where the table's `5`
  (*"a deliberate check said no"*) fits. Correcting it changes a published contract and needs a major
  version bump, so it is its own decision. Recorded here so the disagreement is visible rather than
  discovered. See D8.
- **Nothing checks the exit-code table against the code, and it has now drifted twice** — the meaning of
  `0` and the meaning of `5` were both found stale by review rather than by a test, in consecutive
  rounds. Two checks already exist that compare this design document against the built tool: one for the
  commands it lists (`Tests/IntegrationTests/DocsTests.swift:272`) and one for the options it spells out
  (`:298`), and neither surface has drifted since. A third of the same shape — every number in the
  table exists in the code, with matching meaning — is what stops the next one. Deferred because it
  belongs to the documentation checks rather than to this feature, and because it should be written
  against the corrected table rather than the current one.
- **Marking evidence proven** — `F44`, deliberately a separate feature and an opt-in switch.
- **Holding back part of the test set** — `F45`.
- **Running the two measurements concurrently** — halves wall-clock, but the predecessor pins
  concurrency to 1 with the note *"to avoid judge OOM"*, so this needs evidence before it is changed.

## 9. Docs ripple on landing (not now)

The command list in the design document gains a shipped marker for this verb, and the two mechanical
checks that compare documented commands against the built ones will start requiring it. The read-me's
loop diagram moves this verb from planned to shipped. The roadmap's phase entry and this phase document
gain a shipped date. The contributor guide's command list gains a row.

**And the meaning of exit `0` gains a command-specific note in two places** — the doc comment on the
success code (`Sources/EDDCore/ExitCode.swift:4`) and the exit-code table in the design document's §5.4
(`skillet-design.md:231`, with the note beside the existing one for the scoring command at `:246`).
Without it the published wording *"everything measured passed"* is false for this command, which leaves
`0` when nothing regressed even if tests still fail. This is a clarification, not a change to the
contract: no number changes meaning for any existing command.

**The same table's row for `5` is stale already, before this command exists.** It publishes
*"Gate violation under `--strict`"* (`skillet-design.md:236`), while the code defines that number as a
refused safety check generally — its own note records that the `--strict` wording *"was already narrower
than its only use"* (`Sources/EDDCore/ExitCode.swift:19-22`). This command uses `5` for a dirty
repository, a declined cost confirmation, and a quoted passage that no longer matches, none of which
involve `--strict`. The row changes to the code's own wording. That is a correction of documentation to
match shipped behaviour, not a change to behaviour.

**Two sentences in the design document change only once their proposals are signed off**, and both are
in §6.1's description of this command: the synopsis line showing `--apply <indices>` (§14 item 22, from
D6), and the sentence saying deltas are printed *"against the most recent recorded baseline (running one
first if none exists)"* at `skillet-design.md:558` (§14 item 23, from D2). Listing them here so a later
update cannot fix the flags and leave the measurement sentence describing behaviour the command does not
have.

**A third place, easy to miss because it is a table rather than prose:** the ships-in-v1 column at
`skillet-design.md:1151` lists this command as `iterate` (batch `--apply`). It changes with the same
sign-off, and is called out separately because a search for the flag in running text does not find it.

## 10. Status log

- **2026-08-16 — planned.** Five unknowns resolved through Q&A, each after reading the predecessor and
  checking outside practice. Three of the five answers depart from the predecessor, and each departure
  has a recorded reason rather than a preference: the clean-repository requirement (D3) exists because
  the predecessor's copy is built from committed state while its "before" reads the live folder, so
  uncommitted work silently contaminates the comparison; the copy is discarded on success (D4) because
  this project has a sanctioned landing path the predecessor lacked; and the command line follows the
  shipped sibling rather than the design sketch (D6). Two answers follow the predecessor deliberately
  against my own first recommendation: the strict guard (D1), because thresholding on an unmeasured
  grader error rate is false rigour, and measuring both arms fresh (D2). The report shape (D7) was found
  already solved inside this codebase by the A/B feature, including the honest-uncertainty rule D1 needs.
