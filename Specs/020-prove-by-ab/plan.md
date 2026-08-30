# F43 — Prove a proposal by measuring it twice (`skillet iterate`)

| | |
|---|---|
| **Feature** | F43 — Prove a proposal by A/B (Phase 6 · [phase-6-fix-suggestion-iteration.md](../../Roadmap/phase-6-fix-suggestion-iteration.md)) |
| **Command** | `skillet iterate <skill> --proposals <name>.json [--edits <n>...] [--runs <k>] [-n\|--dry-run] [--yes] [--no-input] [--keep-worktree] [--json]` |
| **Status** | **IMPLEMENTED + DOCUMENTED** — 2026-08-21 (877 tests / 111 suites green, zero warnings; staged, no commits — manual review). Planned 2026-08-16 across five unknowns; five more surfaced during implementation, four defects in the first review, four documentation drifts when the ripple in §9 was applied, seven settings defects in the second review, three selection/report defects in the third, three stand-in defects in the fourth, three settings/reporting defects in the fifth, and four in the sixth — all recorded in §10. |
| **Adapted from** (concepts, **not** a type port) | `~/Developer/skills/Sources/SkillEvalCLI/IterateCommand.swift` and `SkillEvalKit/IterateOutcome.swift` — the predecessor's working implementation, read closely and departed from in three recorded places (D3, D4, D6); D1 and D2 follow it deliberately, against my own first recommendation in each case — see §10. |
| **Decisions** | **D1 — Strict verdict, disclosed noise, labelled provisional.** · **D2 — Both measurements taken fresh, in one invocation.** · **D3 — A clean repository is required.** · **D4 — The throwaway copy is removed either way; `--keep-worktree` retains it.** · **D5 — Both measurements write outside the copy.** · **D6 — The command line matches its shipped sibling, not the design sketch.** · **D7 — One record, with the paired comparison as an additive block.** · **D8 — A declined cost confirmation leaves `5`, following the published table.** · **D9 — The cost confirmation is extracted so both paid commands share one.** · **D10 — Every free refusal is shared, and the static check reads the edited copy.** · **D11 — The copy's lifetime belongs to a scope, so a failure cannot leak it.** · **D12 — Every run setting comes from the type that declares it, checked once, and proved by a value the paid path demands.** · **D13 — One routine turns `--edits` into the list every later step uses, and the command offered at the end names exactly what was measured.** · **D14 — The offline stand-ins decide nothing by chance, read nothing unguarded, and leave nothing unsaid.** · **D15 — Every number the gate forwards is checked, and a reported count is one that happened.** · **D16 — A test that cannot run is refused, a comparison that cannot be drawn is not success, and an unreadable file says where.** · **D17 — An option that would be ignored is refused, and the grader choice is offered by both paid commands.** · **D18 — A test's name is the key every comparison joins on, so it is unique by construction and does not move.** · **D19 — The preview answers a machine, both sides of a saved file are checked, and a change too small to print says so.** |
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
5. **Make the disposable copy** — `git worktree add --detach <path> HEAD`, outside your repository:
   the last committed state, attached to no branch (D4). Spelled out because the default does the
   opposite, and a copy on a branch can collide with one already checked out. **From here the copy's
   lifetime belongs to a scope**, so every route out of the steps below removes it (D11). It is made
   this early because it costs nothing and the free static checks must read the *edited* version — see
   step 7 and D10.
6. **Apply the selected edits into the copy**, through the same engine the landing command uses — every
   quoted passage must still match exactly once, or nothing is applied and the copy is removed.
7. **The free refusals, all of them, from the one routine both paid commands call** (D10): a test naming
   a file that is missing or out of bounds ⇒ `4`; a test with nothing to grade ⇒ `4`; a shortcut inside
   the skill folder ⇒ `4`; and the free static catalog ⇒ `2`. The first three read your skill (the copy
   is your last commit, so they agree); the static one reads the **edited copy**, so a repair is never
   blocked and an edit that breaks something else is still refused for free. `--dry-run` stops here and
   reports — which means a preview names a broken edit instead of quoting a cost for a plan that cannot
   run.
8. **Plan the cost and confirm it, then check the model program is usable.** Two separate checks, not
   one: the cost confirmation asks before spending roughly double a single measurement, and the shared
   readiness check (`SpendGate.swift`) refuses a missing or signed-out setup. **That order matches both
   commands that already spend** — the measured run confirms at `RunCommand.swift:228` and checks
   readiness at `:241`; drafting refuses over its ceiling at `SuggestCommand.swift:240` and checks
   readiness at `:249`. An earlier draft of this plan had them the other way round, which would have made
   this the only paid command of three to ask in a different order. The confirmation is not shared today
   and this feature extracts it — see D9.
9. **Prepare the scratch folder through the shared routine**, which refuses a `.skillet` or
   `.skillet/runs` that is a shortcut to somewhere else. Writing straight to the path instead sent six
   raw transcripts outside the project and still reported success — see §10.
10. **Measure the unedited skill** — reading the skill files in your own folder and changing none of
    them. Its trial records are written, like the other measurement's, to a folder of their own under
    the project's scratch area (D5); what is never written to is your skill.
11. **Measure the edited copy.** Both measurements write their trials and grades into *your* project's
    scratch folder, never the copy's — and each into its own folder beneath the run, so the second
    cannot overwrite the first (D5).
12. **Remove the copy** — `git worktree remove --force <path>`, on the way out of *any* of the steps
    above, unless `--keep-worktree` (D11). The force is not optional: applying the edit is what makes
    the copy differ from what was committed, and git refuses to remove a copy in that state (D4).
13. **Compare, verdict, report** (D1, D7) — after the copy is gone, so the report is never the reason a
    copy outlives the run.

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

### D10 — Every free refusal is shared, and the static check reads the **edited copy**

Before spending, the measured run refuses four things: a test naming a file that is missing or out of
bounds, a test with nothing to grade, a shortcut inside the skill folder, and anything the free static
catalog calls an error. All four were private to that command, so this one reached none of them — and a
missing fixture was *skipped silently*, which can surface as a reported regression the edit did not
cause. That is the third time in this feature a check existed in one command and was simply absent from
the other; D9 records the first two. They now live in one routine
(`SpendGate.assertFreeChecksPass`) that both commands call, beside the readiness and cost checks.

**Where the static check points is the substantive part.** Aiming it at your skill as it stands — which
is what the measured run does — would refuse the *repair* you wrote, which is the most valuable edit
this command can prove; that is why the command that applies edits deliberately skips the check
(`Sources/skillet/SuggestCommand.swift:388-390`). Skipping it here instead would let you pay to prove an
edit that leaves the file broken in some other way. The recognised answer is to gate on **what changed**
rather than on pre-existing state ("Clean as You Code" — the stated goal is to allow improvements to
already-problematic code while still preventing new problems). So the caller passes the directory the
static checks read: the measured run passes your skill, and this command passes the edited copy.

**One ordering consequence, which improves things.** The copy costs nothing to make, so it is made
*before* the cost question — which puts every free refusal ahead of anything paid, this project's own
rule (constitution V). `--dry-run` therefore applies the edit and reports a broken one rather than
promising a measurement that would refuse; the copy is removed either way (D11).

Both halves are pinned, and undoing either shows why both are needed: pointing the static check at the
live skill *simultaneously* blocks the repair (exit `2` where `0` is right) and admits the breaking edit
(exit `0` where `2` is right).

### D11 — The copy's lifetime belongs to a scope, so a failure cannot leak it

Cleanup sat in an on-the-way-out block. This project builds with Swift 6.3.3, where such a block cannot
wait for slow work — waiting there only became legal in 6.4 — so the code *started* the removal and
returned, and the process could exit first. Every failure past the point where the copy exists therefore
leaked both the folder and an entry in git's own list of copies.

**A dead entry does not clear itself.** The assumption that the next copy would tidy it was tested and
is false: after deleting a copy's folder and making another, the dead entry was still listed. Git sweeps
records only once they are older than `gc.worktreePruneExpire` — unset here, so git's documented default
of **three months**. Only an explicit `git worktree prune` cleared it. So the leaks accumulate for a
quarter of a year.

The fix is the ordinary scoped-resource shape — the *bracket* pattern: RAII in C++, try-with-resources
in Java, `with` in Python, and the guarantee Swift's own structured concurrency makes in SE-0304, where
an error escaping a task group cancels *and awaits* the remaining tasks before rethrowing. One routine
(`ThrowawayCopy.withCopy`) makes the copy, runs the work, and waits for the removal on the way out of a
success and of a failure alike. `--keep-worktree` still means keep: a failure is exactly when you want
the copy left to inspect.

### D12 — Every run setting comes from the type that declares it, checked once, and **proved by a value the paid path demands**

The settings type already declares every default a measurement runs on: 3 repetitions, a 10-minute limit,
64 MiB of captured output per attempt, and a cost question above 25 trials
(`SkilletConfig.Runs`, `Sources/EDDCore/SkilletConfig.swift:136`). This command re-typed three of them by
hand at the point of use, and two had drifted — it capped output at **4 MiB** (small enough to cut off a
long session and record the attempt as a failure having nothing to do with the skill) and asked above
**20 trials**. It also validated none of them, so a repetition count of zero produced `0/0` on every eval,
*"no test scored lower"*, exit `0`, **and the command to land the edit** — a recommendation to ship
something nothing measured. The measuring command refuses all of it.

**The lower cost threshold was not a deliberate "this command is pricier" policy, and is gone.** The
threshold counts *trials*, and this command's trial count already doubles for its two measurements — so
at the shared number it already asks at half the repetitions. The one other command here that doubles its
work, `run --ab` (which adds a skill-free comparison arm), keeps the shared threshold for exactly that
reason. A lower number counts the same cost twice.

**A refusal names where the value came from.** The message this replaces said *"pass --runs with a value
≥ 1, or omit it to use runs.k"* even when `runs.k` was itself the cause — sending you to the setting that
had just been refused. Flag and file now get their own wording.

**A time limit the tool cannot read is refused, not quietly replaced.** Both commands shared
`?? .seconds(600)`, so `timeout: "10 minutes"` capped every attempt at ten minutes while the file said
otherwise, and an attempt stopped on time is recorded as a failed one. This one predates the feature. It
is refused now, and the free preflight `skillet doctor` reports it through *the same routine*, so the
free check cannot drift from what the paid path enforces. There is no released version for the stricter
reading to break: the repository has no version tags.

**And the enforcement is proved, not remembered.** `SpendGate.approveSettings` returns a
`SpendGate.Approved` whose initializer is private to it, and `MeasurementSetup.forBehaviour` takes nothing
else — so a command cannot reach a paid measurement carrying numbers nothing checked. Deleting the gate
call from this command produces `error: cannot find 'approved' in scope` rather than a review finding.
That is the *witness* pattern: constructing the value is the proof the check ran. Sharing a guard fixes
the commands that exist; requiring its result fixes the one nobody has written.

The type cannot see two commands that both call the gate and feed it different inputs, so it is paired
with `Tests/IntegrationTests/PaidCommandParityTests.swift` — one scenario, every paid command, identical
answers required. Neither half covers the other's gap.

### D13 — One routine resolves `--edits`, and the command offered at the end names exactly what was measured

Three checks turn `--edits 2 0` into a list: the numbers are in range, none is repeated, and the result is
put in a canonical order. The command that writes your files had all three. This one had the first only —
so `--edits 0 0` reached the applying engine, which reported that *"edits 0 and 0 cover overlapping
text"* (an edit cannot overlap itself) and advised applying them *"one at a time with --edits"*, the flag
just used — at exit `5`, the number reserved for a deliberate safety refusal, for something simply
mistyped. Seventh instance of this feature's recurring shape; `EditSelection` is now the one routine both
call, and the parity suite covers it.

**One wording, one word of difference.** The two commands already refused an out-of-range number
differently, each better in a different way: one named the flag and the count, the other said what
dropping the flag would do. Keeping either discarded something. Human text carries no compatibility
promise here (design **P7** — *"TTY output is for people and carries no compatibility promise"*), so
nothing was owed to either; what is owed is **P6** (*"errors teach — what went wrong, why, and the command
that fixes it"*). The merged sentence carries all of it, and the only genuine difference — one command
*applies*, the other *proves* — is a single caller-supplied verb.

**And the offer at the end names only what was proven.** Proving `--edits 0` of a two-edit draft printed
`skillet suggest … --apply`, which applies **both** — recommending an edit nothing measured. That is the
same fault as a verdict drawn from zero trials (D12), reached by a different route, and in a command whose
entire purpose is to not recommend unproven edits. The flag is appended only when the subset is genuinely
narrower, so proving everything still prints the short command.

**Honest scope note.** The review also reported that the raw flag array was passed to the applying engine
where the canonical list should have been. That is true and is fixed, but with repeats now refused up
front it is **defence in depth, not a live defect**: the only remaining way the two lists can differ is
order, and order does not survive — the engine sorts placements by position before writing and compares
overlaps with `min`/`max`. Verified: `--edits 1 0` and `--edits 0 1` produce byte-identical output. So no
test is claimed for that half.

**A grammar defect, and why it was not house style.** The blocked verdict read *"1 test(s) scored lower"*.
`(s)` appears eight times in the renderer, which looked like a convention until checked: the same file
branches on singular and plural properly in seven places (`Renderer.swift:217`, `:300`, `:340`, `:349`,
`:350`, …), rendering *"1 error"* / *"2 errors"*. This line was the outlier, and now reads *"1 test scored
lower"*.

**Fixing it alone left this command inconsistent with itself**, which a sweep of the whole source caught:
the preview line in this same command printed *"1 eval(s) × k=3 × 2 measurements = 6 trial(s) ≈ 12 model
call(s)"* (`Sources/skillet/IterateCommand.swift:220`). Both belong to this feature, so both are fixed;
the preview now reads *"1 eval × k=3 × 2 measurements = 6 trials ≈ 12 model calls"*. Roughly sixteen more
`(s)` sites remain across the measuring, triaging, capturing, preflight and scoring commands — all real
(every one can render at a count of one), all pre-existing, and all belonging to shipped output this
feature does not touch. Deferred as its own item in §8 rather than swept silently.

### D14 — The offline stand-ins decide nothing by chance, read nothing unguarded, and leave nothing unsaid

**A verdict decided by a coin flip.** The stand-in grader looked up a recorded answer by searching the
reply for a marker. A shorter recorded marker fitted inside a longer real one — `v1` inside `v1 release`
— so two recorded answers matched, and which won came from the order a lookup table happened to be in.
Swift randomises that per run *on purpose*, partly to expose code that depends on it. Measured: **twenty
identical runs of one command split ten and ten between opposite verdicts.**

The fix recovers the marker **exactly** — the reply is written `<text> [<marker>]`, so the marker is
everything between the first `" ["` and the closing bracket — and matches by equality. Twenty runs now
agree, and they agree on the *right* entry: the whole marker's, not a fragment's.

**The "refuse if two still fit" half of the decision is not in the code, deliberately.** With an equality
test, one reply carries one marker and recorded answers are unique, so two cannot both fit; there is no
tie left to break. Writing a refusal anyway would be unreachable code that reads as a safety net it does
not provide. An earlier attempt at a check before measuring was written and **withdrawn** for the same
reason: it compared recorded markers against each other, while the clash is between a recorded marker and
the *skill's* marker, which the recording need not contain — so it would have been reassurance without
cover.

**The last unguarded read in the source.** The stand-in read a staged skill file with a call this project
removed everywhere else, following symbolic links and reading without limit — measured at 200 MB in one
gulp, once per attempt. It now goes through the shared guarded reader at the same 1 MiB limit the other
staged-skill reads use, and a refusal is treated exactly as a file with no marker always was. The reason
recorded is **CERT FIO32-C** — *do not perform operations on devices that are only appropriate for files*
— rather than an anecdote, because an anecdote is what went wrong next door (below).

**A copy that could not be deleted said nothing.** With deletion forced to fail, the command printed a
complete successful report, offered the command to land the edit, exited `0`, and left both the folder and
an entry in git's list of copies — which an earlier round measured as not clearing itself for three
months. It is now a **disclosure**: this project already defines one as *"one skipped/refused input, named
with its reason — the 'every omission is disclosed' rule every reporting command follows"*
(`Sources/EDDCore/Disclosure.swift:3-6`), carried by three other payloads. This was the only reporting
command with nowhere to put one. It appears in the printed result and in `skillet.iterate/1` alike, so a
scheduled job that never reads the error stream still learns of it.

**A correction next door.** Four comments record that this class of unguarded read hangs forever on a
named pipe. Probing all four ways this codebase can read a file, against a pipe with a writer attached:
`String(contentsOf:)`, `Data(contentsOf:)` and `FileManager.contents(atPath:)` **all refuse instantly**,
while `FileHandle.readDataToEndOfFile()` **blocks indefinitely**. So the hazard is real and the guard is
right, but `Sources/ConfigYAML/ConfigLoader.swift:16` attributed it to the wrong call; that sentence is
corrected in place, and the two that were right (`WorkspaceManager.swift:296`, `CorpusLoader.swift:38`)
are untouched.

### D15 — Every number the gate forwards is checked, and a reported count is one that happened

**The gate checked three numbers and forwarded a fourth.** `SpendGate.approveSettings` validated the
repeat count, the output limit and the time limit, then passed `runs.confirm_above_trials` through
untouched. The cost check is `trials > limit`, so **any negative value is true for every run**: each
invocation stops to ask, and where it cannot ask — a scheduled job, a pipe, `--no-input` — it refuses
outright. Meanwhile the free preflight printed a tick beside it: `✓ config.runs … confirm_above_trials=-1`.
That is precisely the silently-misapplied setting D12 built this gate to catch, one field short. Zero
stays valid and means *ask about everything*.

**A count called "observed" that was the count requested.** `IterateReport.observedK` is documented *"as
observed rather than as requested"*, and the measuring command computes it that way — the fewest repeats
any test recorded (`RunModels.swift:189`). This command passed the requested number. Reproduced with a
test that has no prompt, so it cannot run and records nothing:

```
iterate:  e2  0/0  0/0  —      average change +0.50 ± 0.50  (observed k=3)
run:      observed_k: 0        recorded per eval: [3, 0]
```

Two reports, one field name, opposite answers about the same skill — with this one printing `k=3` beside a
row that reads `0/0`. It is now computed from the recorded counts, and the two agree.

**An invariant that was being remembered rather than checked.** The stand-in grader recovers a marker as
the text between the first `" ["` and the final `]`. That is exact *only while the canned answer contains
no `[` and does not end with `]`* — true today (`"done"`, `"done (no skill)"`), and nowhere written down.
Rather than move the marker onto a type the real graders share for the sake of a test-only concern, the
rule is stated at the canned answers and **pinned by a test** that fails the moment either gains a bracket.

### D16 — A test that cannot run is refused, a comparison that cannot be drawn is not success, and an unreadable file says where

**The third route to a vacuous "proven".** A behaviour test needs a prompt — the instruction sent to the
model. Without one it recorded nothing, and nothing-against-nothing is no change, so with *every* test
promptless this command printed two `0/0` rows, said *"no test scored lower"*, **offered the command that
lands the edit**, and exited `0` — while the measuring command exited `1` on the identical skill.

It is refused now, for free, from the routine both paid commands share, leaving `4` — the same number and
the same place as a test with nothing to check. That changes the measuring command's answer for this input
from `1` to `4`, deliberately: **a test that cannot run is not a failing test.** The most widely used test
runner keeps the two apart (a file it cannot load is not `EXIT_TESTSFAILED`), and the closest tool of this
kind validates its test files at load time *"to catch typos early"* and keeps test failure on a different
number from every other error. Nothing has been released against the old number.

**A comparison that could not be drawn is not a pass.** `run --ab` adds a measurement with the skill
switched off. When that arm produced no usable pairing at all, the exit number was taken from the
with-skill arm alone, so a script that asked for a comparison got `0` and assumed it had one. The trust
rule in controlled experiments is that a failed guardrail voids the comparison — nothing in it can be
read. It now leaves **`3`**, not `1`: no test failed, and `3` is already the number this design assigns to
the same inability caught earlier — the free pre-spend check for a model program that cannot switch skills
off *"exit 3 otherwise"* (`skillet-design.md:382`). One fault, one answer, whichever check catches it. What
`0` covers is now written beside the number itself.

**Seven places, two answers, none naming your file.** An unreadable file was reported by dumping the
reading library's whole error object in five places and saying nothing beyond "not valid" in two — so the
same broken test file gave the exact character position from one command and no hint from another. The
translation is written once now and says *where in your document* the fault is, which is what JSON
validators publish as a location path and what survives wording changes; the reading library's own type
and domain names stay out, since they describe how this program is built rather than what is wrong with
your file.

**A caveat belongs with the result.** How often the automatic grader agrees with a person has never been
measured, and the report's documentation says that caveat is printed with every verdict. It was printed
only on a proven one. Measurement practice is explicit that a qualifier travels *with* the result rather
than being relegated to a general note — so it now sits on both verdict lines, parenthesised so it
qualifies the grader instead of competing with the conclusion (*"not proven; provisional"* hedges twice).
A blocked verdict is where it matters most: an unchecked grader may be the reason you are being told not
to ship.

**Two consequences worth recording.** Refusing promptless tests made the previous round's end-to-end test
for the repeat count **impossible to construct** — that was the only way to record fewer repeats than were
asked for. Rather than keep a test that could no longer fail, the guarantee moved somewhere stronger: the
report now **derives** its repeat count from what was recorded and cannot be told a different number.
Likewise, the offline stand-ins cannot produce an unusable comparison arm, so "no pairing was drawn" is
defined beside the data as `ABComparison.producedNoPairing` and tested directly, rather than through a
path that cannot reach it.

### D17 — An option that would be ignored is refused, and the grader choice is offered by both paid commands

**A recording named without `--replay` launched a real model.** The switch permitting a test-only option
answers *"is this allowed here"*; nothing answered *"do these options mean anything together"*. So naming
a recorded-answer file on its own passed the gate, was never read, and both paid commands went on to
spend against a real model while the caller believed they were offline. Reproduced without spending: on a
machine with no model program configured it reached `could not find the claude-code binary` — a real
launch attempt. One shared check now refuses it, for both commands and both recording options.

**Refused rather than treated as implying `--replay`.** An option that quietly does nothing and an option
that quietly changes mode are both surprises; of the two, being told costs one retype.

**The grader choice is now offered by both.** The file-reading grader exists for a single failure — the
run created the file and its contents are wrong — and only the measuring command offered it. So the loop
could record that failure, group it, draft an edit for it, and then **never prove the fix**, because the
proving command's comparison only ever read what the reply claimed. Same flag name, same two values, same
validation, same warning about larger and pricier grading requests, with one addition: this command
grades twice, so the note says so.

**No settings key for it, deliberately.** The nearest precedent — requiring the grader *model* to be
written down (§14-4) — does not transfer: a model **floats**, so the same file gets judged differently on
different machines with nobody doing anything, which is the hazard that decision closed. The grader kind
does not float; it defaults to the text grader everywhere, choosing the other is explicit at the point of
use, and every verdict already records which grader produced it. The real argument for a key is that a
project always wanting file-content grading cannot say so once — genuine, but unasked for, and a key
shipped now is a second home for one decision plus a precedence rule between them. Deferred, recorded
here so it is a decision rather than an omission; roughly ten lines whenever someone wants it.

**Two test defects of my own, both the shape being fixed.** The first version of the recording test reused
shared invocations that already carry `--replay`, so it passed while exercising nothing. The first version
of the grader test asserted the flag was *accepted* and warned about — both still true when the selection
is then discarded, so undoing the fix left it green. It now asserts the choice **reached the run**:
selecting the file-reading grader makes each trial record a `file_contents.json`, and the text grader must
not. That difference is visible with no model involved.

**And a readability fix.** The eval column padded to a fixed 24 characters, which silently truncates: two
evals whose names share a long prefix printed as identical rows. It now grows to fit, bounded, and
anything past the bound is shortened *visibly* with an ellipsis.

### D18 — A test's name is the key every comparison joins on, so it is unique by construction and does not move

**Found by measuring coverage, not by reading.** The only uncovered lines in the comparison were two that
build a lookup keyed by test name with a rule that keeps the first entry and discards the rest. They were
uncovered because nothing had ever had two tests with one name. Constructing that case: two tests both
named `same`, the first improving and the second getting worse, produced **one row reading `+1.00`, the
verdict "no test scored lower", exit `0`, and an offer to apply the edit.** The measuring command
meanwhile ran both and reported one failure and one pass, so the two disagreed about one file.

**The name is not a label — it is the key.** Four places lined up two sets of results by it, all with the
same silent rule: before against after (`EditVerdict.swift:71`, `:72`), with-skill against without
(`RunModels.swift:319`), and that same pairing rebuilt from the saved file months later
(`RunRecordMapping.swift:455`). A key that does not identify one thing produces joins that complete,
look valid, and are wrong — which is why databases reject a repeated key rather than choosing a row.

**Parsed, not checked.** Both doors results come in by — the tests file and the saved results file — now
produce a set that *cannot hold* a repeated name (`UniqueByName`), and the comparisons take that type.
Checking at each comparison would have been one rule written four times, re-verifying what a reader of
the file already established; carrying the guarantee in the type means the four discard-the-rest lines
are **deleted** rather than made unreachable. This is the third time this feature has reached for that
shape, after the settings gate's witness value (D12) and the report deriving its own repeat count (D15).

**And a name taken from a position is not a name.** A test's name is optional, and in the corpus this
tool was adapted from **three of four skills name no test at all** — so refusing unnamed tests was
considered and rejected on the evidence. They were numbered by position, which made the key move whenever
the file was edited: insert a test near the top and every test below silently inherits its neighbour's
accumulated history, with nothing printed and nothing left over to notice. An unnamed test is now named
from its own content — `tidy-these-notes-into-action-d9bb` rather than `eval-1` — which survives
reordering, reads in a report, and changes only when the test itself is rewritten.

The hash behind that name is FNV-1a rather than the language's built-in hashing, which is seeded afresh
per process on purpose: a name built from it would differ between two runs of the same command and every
stored result would stop lining up.

**One cost, disclosed rather than hidden:** results stored under the old positional names re-point once
when this lands. Nothing has been released, and the alternative was leaving a key that moves.

### D19 — The preview answers a machine, both sides of a saved file are checked, and a change too small to print says so

**The preview ignored a request for machine-readable output.** Every command here offers one and every
payload carries a schema, but this command's preview hand-assembled prose regardless — so a script asking
for a plan received a table meant for a person. It now emits `skillet.iterate-plan/1`, mirroring the
measuring command's `skillet.run-plan/1`: the tests, the repetitions, the doubled trial count, whether a
real run would put the cost to you, and the estimated calls.

**Only one side of the saved results file was checked.** The comment written in the previous round said
the file was refused if it named a test twice; only the without-skill side actually was. A repeat on the
with-skill side went straight into the score and the pairing — a wrong `pass^k` and a wrong comparison,
from a file nobody would think to suspect. Both sides are checked now, and the comment matches.

**A difference too small to print is not the same as no difference.** Rounding to two places turned a
real change of 0.004 into `+0.00 ▲` — a number reading as nothing beside an arrow saying otherwise — and
a real drop into `-0.00 ▼`. Below what two places can show, the size is now written as a bound (`<+0.01`,
`>-0.01`) and the arrow, which was never in doubt, stays. The same fault was in the average line beneath
the table, which the review had not spotted and which is fixed with it.

**One reported fault is not one.** Naming a test was said to be language-sensitive, because lowercasing
can be — a capital `I` becomes a dotless `ı` under Turkish rules. Measured: `"INCIDENT Işık".lowercased()`
gives `incident işık`, **identical** to the result with an explicit neutral language and **different**
from the Turkish one. The language-aware method is the one that takes a language as an argument; the one
used here does not. The recommended change would have altered nothing, so the property is pinned by a
test instead — if it were ever swapped for the language-aware method, a Turkish machine would name the
same test differently and every stored result would stop lining up.

**The file-size cap, with the context the review lacked.** Both new test files exceeded the 300-line soft
cap and are now split — the proving command's 702 lines into four topic suites plus a shared fixture
(largest 179), the parity file's 392 into two plus a fixture (largest 199), with the test count unchanged
at 867. Worth recording: **six of seven integration files exceeded that cap**, the largest being 1113
lines and predating this work. Splitting only the two added here is the right call for what this feature
owns, and leaves a repo-wide gap that is its own change rather than something to fold in silently.

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

**Added by the post-implementation review round (D10, D11):**
19. A test naming a fixture that is not there ⇒ `4` before spending, not skipped silently.
20. An edit that leaves the skill failing the free static catalog ⇒ `2`, and the rule id is named.
21. **An edit that repairs an already-invalid skill is measured, not blocked** — the half that decides
    where the static check points. Undoing it exposes both failures at once: the repair is blocked and
    the breaking edit in 20 is admitted.
22. `--dry-run` on a broken edit reports the breakage instead of quoting a cost, and leaves no copy.
23. A `.skillet/runs` that is a shortcut elsewhere ⇒ `4`, and the folder it points at stays empty.
24. A failure after the copy exists still removes it — asserted on git's own list of copies, which is
    what accumulates, and which does not clear itself for three months (D11).

**In `HarnessKitTests`:**
25. The offline stand-in answers as the skill it was *handed*: the requested one rather than the first
    alphabetically, a loaded skill before a merely-present one, no marker on a skill-free run, the
    staged folder only when no skill was named, and an unmarked skill answering exactly as it always did.

**Added when the documentation ripple was applied (§9):**
26. Every option the design document spells in a command's **usage line** is one the parser accepts, and
    nothing listed as planned has quietly started working — run for every command with a usage block,
    not just the one it was written for.
27. **No prose under that block spells an option the parser refuses** — the usage line is only the
    headline, and the stale spelling was in running text. Both compare against the parser's structured
    argument list, never `--help`'s text: matching the text passes a flag the command merely *mentions*,
    which is how the first attempt at 27 passed while the drift was still present.

**Added by the second review round (D12):**
28. Zero or negative repetitions refuse rather than proving an edit nothing measured — and the refusal
    names the flag or the setting, whichever supplied the value.
29. A non-positive output cap and an unreadable time limit both refuse; the free preflight `skillet
    doctor` reports the time limit too, through the same routine, so it cannot drift.
30. `--dry-run --keep-worktree` names the copy it kept.
31. Awkward markers reach the grader intact — `]`, `[[[`, a quote, a backslash, non-Latin text — driven
    through the real path, because reading the marker, carrying it, and putting it back is the chain
    that broke. Plus a skill-free answer and unreadable text, which must behave as they always did.
32. **`Tests/IntegrationTests/PaidCommandParityTests.swift`** — one settings file, every paid command,
    identical answers required, each in its own repository so one command's records cannot change what
    the next sees. Its blind spot (a *new* paid command missing from its list) is covered by the
    compiler, per D12.

**Added by the third review round (D13):**
33. Naming the same edit twice is a mistyped command (`2`), not a safety refusal (`5`), in every command
    that narrows a draft — and the refusal never reports an edit overlapping itself, nor advises the flag
    that carried the mistake.
34. An out-of-range number is refused identically by both, naming the flag, the file and the count, with
    a fix line whose verb matches what that command would have done.
35. Proving a subset offers a land command limited to that subset; proving everything offers the short
    command unchanged.
36. A single regressing test reads as "1 test scored lower", **and** the preview in the same command
    reads "1 eval" — pinned together, because fixing one and leaving the other is the inconsistency the
    finding was about.

**Added by the fourth review round (D14):**
37. Overlapping recorded markers grade identically across repeated runs, and by the whole marker's entry
    rather than a fragment's — including a marker containing brackets.
38. A staged skill file that is a symbolic link is not followed, and one over the limit is refused rather
    than read whole; both are treated as a file with no marker.
39. A copy that could not be removed is disclosed in the printed result **and** in `skillet.iterate/1`.
40. Two tests changing by the same amount give a stated spread of zero, not an absent one.
41. Two runs in a row keep separate records and separate copies (deterministic; no concurrency).

**Added by the fifth review round (D15):**
42. A negative ask-before-spending threshold is refused by every paid command; zero is accepted and means
    ask about everything.
43. The repeats reported are the ones that happened, and the two commands agree about the same skill.
44. The canned answers cannot shift the marker boundaries — no `[`, and no trailing `]`.

**Added by the sixth review round (D16):**
45. A test with no prompt — missing or blank — is refused by every paid command before spending, at `4`,
    and no verdict is drawn from it.
46. An unreadable test file is explained the same way by both commands, says where the fault is, and never
    names this program's own internals.
47. The grader caveat appears on a blocked verdict as well as a proven one.
48. "No comparison was drawn" is distinguishable from "the comparison came out flat", tested directly
    because the offline stand-ins cannot reach the state.
49. The reported repeat count is derived from what was recorded and cannot be supplied.

**Paid, opt-in, skipped by every ordinary run** (`SKILLET_LIVE_SMOKE=1`, `.tags(.slow)`):
50. The proving command launches a real model twice in one invocation, records both measurements, has
    the skill **actually invoked** in each, and leaves no copy behind. Asserts nothing about what the
    model writes.
51. Grading distinguishes an expectation the reply meets from one it cannot — asked of the grader
    directly, not inferred from whether an edit moved a score.

**Added by the seventh review round (D17):**
52. A recording named without `--replay` is refused by every paid command, and never reaches a real
    model launch — spelled out rather than reusing invocations that already carry `--replay`.
53. Both paid commands accept the same two graders and refuse the same nonsense, and choosing the
    file-reading one **changes what the run captures**, not merely what it accepts.
54. An eval name too long for its column is shortened visibly; two names sharing a long prefix stay
    distinguishable.

**Added by the coverage round (D18):**
55. Two tests with one name are refused by every paid command before spending, whether the name is
    written down or derived from the test's content.
56. Reordering the tests file does not rename its tests, and no name is a position.
57. A set of results cannot be built with a repeated name, and the repeat is caught wherever it sits.

**Added by the eighth review round (D19):**
58. A preview asked for machine-readable output gets `skillet.iterate-plan/1`, not prose.
59. A change too small to print at two places is shown as a bound with its arrow, never as `+0.00 ▲` —
    in the per-test rows and in the average beneath them.
60. A test's name is unaffected by the machine's language: a capital `I` never becomes a dotless `ı`.

**Added by the ninth review round:**
61. Two hundred tests sharing an opening phrase get two hundred different names, as do two hundred
    varied ones and a thousand at larger scale — the ending must be wide enough to separate them.
62. The readable part of a name equals what a language-neutral lowercasing produces, so the machine's
    language cannot change it.

**Added by the tenth review round:**
63. A record path that is a link is refused and nothing outside the project is written — asserted on the
    outcome, because the mid-measurement window cannot be driven from a test without making it flaky.
64. A run suggests only loop verbs the tool answers to: `iterate` appears, `next` does not, and the test
    says so out loud when that changes.

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
- **`(s)` reads ungrammatically at a count of one, in about sixteen places across five other commands** —
  `TriageEngine.swift:135`/`:140`/`:203`/`:204`/`:211`, `Renderer.swift:394`/`:397`/`:422`/`:430`/`:510`/
  `:513`/`:516`, `CorpusLoader.swift:60`, `RunRecordMapping.swift:492`, `RunCommand.swift:220-222`,
  `DoctorCommand.swift:257`, `CaptureCommand.swift:328`. Every one can render at one. The codebase already
  branches properly in ten places and has no shared helper for it, so the sweep should add one rather than
  repeat the ternary sixteen times — which is why it is a change of its own and not a line in this
  feature. Recorded when the two sites belonging to this feature were fixed (D13).

- **Marking evidence proven** — `F44`, deliberately a separate feature and an opt-in switch.
- **Holding back part of the test set** — `F45`.
- **Running the two measurements concurrently** — halves wall-clock, but the predecessor pins
  concurrency to 1 with the note *"to avoid judge OOM"*, so this needs evidence before it is changed.

## 9. Docs ripple on landing — **applied 2026-08-19**

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

**Applied 2026-08-19, and it found four drifts this list did not anticipate.** Everything above is done:
the read-me's diagram draws this verb solid and its shipped list names it; the two exit-code doc comments
carry the same wording as the table (`0`'s narrowing, and `5` gaining the declined cost confirmation);
the design document, roadmap, phase file, contributor guide and reference page all read as shipped.

What the list missed, all inside the design document's own section for this command:

1. **The synopsis was corrected and the sentence under it was not** — it still said the subset is
   selected with `--apply 0 2`, the spelling D6 removed. Exactly the failure §9 warned about one
   paragraph earlier, in the same section, and it survived a full green suite.
2. **The sample output predated the renderer that shipped** — an `aggregate pass^k` row the command does
   not print, a verdict line with no **provisional** label, which D1 makes mandatory in every rendering,
   and a `→ land it:` line carrying flags the command does not emit. Replaced with the real shape, taken
   from a live invocation.
3. **A false claim about a regression** — *"nothing emitted unless `--keep-worktree`"*. The table is
   printed on a regression; what is withheld is the `→ land it:` line.
4. **`--mark` and the held-out-proof gate read as current behaviour.** Both are deferred (`F44`, `F45`,
   §8), so they are now marked planned and the section says plainly that the command writes no project
   state at all.

**And the check that should have caught the first one did not exist.** The mechanical comparison between
documented options and what the parser accepts covered `suggest` only. It now runs for every command
with a usage block, and a second check reads the *prose* under that block, because the stale spelling sat
in running text rather than in the usage line. See §7 items 26–27 — including the false pass found while
verifying them.

## 10. Status log

- **2026-08-29 — sixtieth round: four more findings from review; two were wrong about what would happen,
  and both had a smaller true version underneath.**

  **"This will not build on the Linux machine" — it does.** Ran it there: builds and passes. The two
  low-level names it flags (asking the system whether a program is still running) are available on Linux
  today only because the general-purpose library re-exports them as a convenience — a convenience that has
  been added, argued over and changed before, and that Apple's own system-APIs package says it will not
  remove the need to work around. Eight files here already declare the dependency explicitly; **three did
  not**, not one — the reported file plus two that predate this work. All three now do. Nothing changes
  today; the build simply stops depending on a courtesy.

  **"A cancelled wait keeps polling for about five seconds" — measured at 0.058 seconds.** A wait that has
  been told to stop returns at once, so the loop drains in milliseconds. The true version is smaller and
  real: the helper ignored being told to stop, kept asking, and then reported *"the thing never happened"* —
  untrue, since it was never waited for. It now passes that on, so a run that was stopped says so instead of
  inventing a failure.

  **"Nothing verifies the child is really ended" — that is what last round added,** and removing the
  mechanism makes it fail rather than pass. Nothing to do.

  **Three unexplained figures in the piece that talks to the model tool** — sixty seconds to ask its
  version, thirty to ask whether the user is signed in, sixty for its help text. Against health-check
  practice, where one to two seconds is normal, sixty looks absurd. It is not: these answer "is this tool
  usable at all", and on a first run the tool may still be setting itself up, where giving up early would
  tell a new user their tool is broken when it is merely starting. The figures survive scrutiny; the reason
  existed nowhere. They are now named and carry it. Deliberately **not** made adjustable — every real case
  for adjustable limits comes from limits that were too *tight*, and nothing here has been too slow.

  **And the suite caught me making the same mistake again, one round after writing the rule against it.**
  The waiting helper added last round gave up after five hundred attempts — about five seconds. That held
  when its check ran on its own and was exceeded the moment the whole suite ran at once and starting a
  program took longer, so the check failed reporting "the program never recorded its number" when the
  program was merely slow to start. A cap like that is a bet on machine speed wearing the clothes of a
  failure bound. The check already carried a one-minute limit, so there were two bounds and the tighter one
  was the wrong one. The inner cap is gone: the time limit is now the only bound. Confirmed both ways —
  the suite passes, and leaving the program running makes the check fail at 60.0 seconds rather than hang.

  **A fourth figure in the same file was a different thing entirely:** ten minutes, which is the published
  default for the per-attempt limit and *is* adjustable. Only the link between the code and the published
  setting was missing, and now it is stated.

- **2026-08-29 — fifty-ninth round: four findings from review, all real, one of them materially narrower
  than reported.**

  **The stopping promise was not broken — two sentences were.** The report said the product description
  promises a polite stop, a pause, then a forceful one, while the program only does the forceful one. The
  second half is true and confirmed at the source: the library that starts programs takes a list of
  stopping steps, always appends the forceful step to whatever it is given, and is given nothing — so an
  empty list *is* an immediate forceful stop. But the description already scopes the polite sequence
  correctly, as a **planned** item (F18) that has not shipped, and lists it under what is deferred. Only two
  sentences described it as though it were current: a comment beside a setting, and a passing clause in the
  section on borrowed code. Both now say plainly what happens today. The planned item stays planned.

  **Deliberately not adding the pause.** A pause before forcing a stop is a length of time, and it happens
  inside the borrowed library, which will not take a clock this project controls — so nothing could check
  it without sitting through it. That is the thing four earlier rounds were spent removing. What is given
  up is the last fragment of the transcript for a run that already failed and is never graded.

  **Four checks were giving a real program a real time limit** — ten seconds twice, thirty once, five once.
  Every one of those was a duration picked so the program would finish first: generous, never yet failed,
  and still a guess about machine speed. Where the limit belongs in what is being checked, it now sits on a
  clock that is never moved, so it is present and can never fire. Where it was beside the point, it is gone.
  Each of the three groups involved now carries a bound, which is what the removed limits were incidentally
  providing.

  **A promise with no coverage at all now has some.** Nothing checked that a program this tool walks away
  from is actually ended — the deleted check that claimed it in its title only ever confirmed the caller was
  told. If that broke, model programs would keep running after being abandoned, and they are billed while
  they run. The new check has the program record the number the system knows it by and then never finish,
  triggers the walking-away directly, and then asks repeatedly whether it is gone. Undo it — never ask it to
  stop — and it fails after 12.8 seconds instead of hanging, because it carries a bound.

  **Two dead ends on the way there, both worth knowing.** Making the limit fire at once killed the program
  *before* it could record anything, so nothing was left to check — the limit fires too early to be the way
  in. And asking repeatedly while only yielding, without pausing, never saw the program start at all: a loop
  that only yields keeps a worker thread to itself and holds up the very work it waits for. That is the same
  fault as the clock-pushing loop from round fifty-seven, in a new place.

  **So the rule was sharpened a second time.** As written it forbade *all* fixed waiting, which also
  forbade the standard replacement for it: waiting **until a condition holds**, re-checking at intervals,
  giving up after a bound. That returns the moment the condition holds, so a slow machine takes longer and
  still gets the right answer, and reaching the bound reports that the thing never happened rather than
  losing a race. It is now written as allowed and preferred.

  **And the sweeping claim from the previous round was false and is now true and specific.** "No real
  waiting anywhere" was wrong — it was written from a search too narrow to match the ways waiting is
  actually spelled here. It now says no check waits a *fixed* length of time, and names the two places
  where real time deliberately passes.

- **2026-08-29 — fifty-eighth round: waiting removed from the checks entirely, and the rule written down.**

  Four rounds were spent trying to make one check reliable while it waited on real time. Each attempt was
  a smaller version of the same mistake, and the last still failed on the shared build machine. This round
  stops fixing it and removes the waiting.

  **The measurement that settled it,** taken on one machine with the same load recipe. The same behaviour,
  checked by starting a real program that idles: **5 failures in 10**. Checked with a clock the check
  controls and no program at all, under **twice** the load: **15 passes out of 15**. That is not a tuning
  difference; the two are different kinds of check.

  **What made the second kind possible.** Giving up on work after a set time used to be welded to starting
  a program, so the only way to reach the giving-up was to start one. Splitting the giving-up into its own
  small piece — same logic, moved — means it can be checked with nothing running and no time passing: the
  work is a wait on a clock nobody ever moves, and the watchdog's clock reports the time up the moment it
  is asked. The outcome is settled by construction rather than by one side being slower.

  **Two checks deleted.** The one that started a real five-second program, whose only subject was a single
  line of wiring, and the one that waited twenty thousandths of a second to confirm the clock used by
  default really moves. The second is now close to unreachable by accident: clocks that do not move come
  from the borrowed clock library, which is attached to checks only and cannot be reached from the shipped
  program at all. **No check anywhere now waits a fixed length of time.** Two places still let real time
  pass, both deliberately and neither a guess: one runs the built program to see it enforce its own limit,
  and one waits *until* an abandoned program has gone, re-checking and giving up after a bound.

  **Written into the binding rules (charter 1.4.0 → 1.5.0)** rather than left as folklore, with the
  measurement attached so the next person does not have to rediscover it: no check may wait on real
  elapsed time, nor start a program that idles, to observe behaviour that depends on time; such code takes
  a clock and defaults to the real one, and checks hand in one they control.

  **One more racing check, found only after the rule was written — and it was the tightest of the lot.**
  A check runs the built program with its time limit set to one second and hands it a stand-in `git` that
  idles for three: a three-to-one margin, tighter than the fifteen-to-one one that had already been
  failing. It was missed because the idling is written inside a line of text that gets saved as a script,
  so searching for the usual spellings did not find it. The behaviour it covers lives in the program's own
  module, which no check can reach directly, so it can only be exercised by running the program from
  outside — where its clock cannot be swapped.

  **Which is a recognised situation with a recognised answer:** test a time limit against something that
  **never answers**, not something that is merely **slow**. Only the second is a race. The stand-in is now
  `tail -f /dev/null`, the usual way to spell "blocks until killed" — no duration, nothing to tune, no
  processor burned, and unlike `sleep infinity` it works on both platforms this project builds for
  (`sleep infinity` fails outright on macOS). The check carries a one-minute bound so that a limit which
  stops firing fails the run instead of hanging it: removing the limit from the program makes it fail after
  60.4 seconds rather than never returning.

  **So the rule was sharpened before it landed.** As first written it banned *real elapsed time*, which
  would have forbidden checking the built program's own limits at all — the program has its own clock and
  the check is outside it. It now bans *a length of time picked so one thing finishes before another*: a
  margin that can be tuned. That is what every failure here had in common, and it is the line the wider
  practice draws too.

  **Still unclaimed:** nothing verifies that a program abandoned by the watchdog is actually stopped. The
  check's old title claimed it; that check is gone, so the claim is gone too, but the promise in the design
  document (stop it gently, then forcibly) remains untested.

- **2026-08-28 — fifty-seventh round: the same check failed again on the shared build machine, with my fix
  for it already in place. Failing to reproduce it was the finding.**

  The check that an overrunning program is stopped by the watchdog lost on the shared build machine again,
  this time with the previous round's fix merged. Then it survived roughly **fifty** local attempts without
  failing once: thirty of the check alone, six with the machine's task scheduling squeezed to a single
  thread, six full runs on one machine and five more on the other with the processor count cut to two. At
  that point the useful conclusion is not "tune it further" — a fault that cannot be provoked in fifty
  tries and still fails in the wild is telling you the shape is wrong.

  **The shape was wrong twice, the same way.** Both earlier versions needed something *outside* the call to
  happen soon enough: the first needed the machine to be quick enough for a two-tenths-of-a-second watchdog
  to beat a three-second program; the second needed this check to push the clock forward *after* the
  waiting had been set up inside the call, and there is no moment it can know that has happened. Whenever
  the push came too early there was nothing to push past, and the program won. Neither version could
  guarantee anything; both merely made losing unlikely, on the machine they were written on.

  **Nothing is raced now.** The clock handed to the watchdog answers every wait the instant it is asked, so
  the watchdog's wait is over before the program under it has managed anything, on any machine, with
  nothing outside having to intervene. The ten-minute watchdog is what keeps the check honest — far longer
  than the program lives, so one waiting on a real clock loses to the program every time and the check
  fails. Confirmed by doing exactly that: put the wait back on a real clock and it fails after 30.0
  seconds, the program winning. The check itself now finishes in **four thousandths of a second**; the run
  that failed on the build machine took 6.9.

  **Neither number in it is a margin, which took a second pass to get right.** The first attempt at this
  left the program under the watchdog running for half a minute and called that "margin" — which is
  precisely the thing being removed, since a machine stalled for longer would still lose. The check is now
  given a minute to finish, and the program under it runs for ten, so the program cannot win by outlasting
  anything: the minute runs out first and says the check timed out, instead of the program quietly
  finishing and the check drawing the wrong conclusion from it. The ten-minute watchdog is a tripwire
  rather than a timing knob — on a real clock it outlives the program, so the program wins and the check
  fails, which is what makes it prove the clock is really being used. Confirmed both ways: passes in four
  thousandths of a second, and fails at 60.3 seconds when the clock is taken back out.

  **Reproduced, then measured — the earlier "cannot reproduce it" no longer holds.** The recipe: start four
  busy processes per processor, **let the load build for about a minute** (this is the part that was
  missed — the first four attempts ran while the load was still climbing and all passed, which is what
  produced the false conclusion that it could not be reproduced), then run the whole suite over and over.
  Under that, the old version failed **five times out of ten**. The new version, run the same way against a
  machine loaded *twice* as heavily, failed **none out of ten**, with the suite taking 19 to 45 seconds
  instead of its usual 17 — so the load was genuinely biting, not just a large number on a display.

  **What was actually going wrong.** The old version kept a loop running that pushed the clock forward and
  yielded, over and over. On a machine with plenty of processors that is harmless. On a small busy one it
  occupies one of the few worker threads shared by all waiting work — including the very wait it existed to
  push past. So it starved what it was serving, while the program it was racing ran outside that pool and
  finished on time regardless. That explains every observation: it needs few processors *and* sustained
  load, it never showed on a sixteen-processor machine, and the failing run took 6.9 seconds for a
  three-second program.

  **Still unclaimed:** the check's own title says the overrunning program "is killed", and nothing in it
  verifies that; it checks only that the caller is told the time ran out.

  **Swept for the same shape elsewhere.** Three other places move a clock by hand, and none is exposed:
  two step a stopwatch along in a straight line with nothing else running, and the third moves the clock
  from *inside* the code being checked, so there is no outside timing to get wrong.

- **2026-08-27 — fifty-sixth round: pinning one borrowed package to an exact version does not pin what
  that package itself borrows.**

  A review flagged that the build had picked up a release of `xctest-dynamic-overlay` published **two days
  earlier**. Checked against the source rather than taken on trust, and it is right: the tag was published
  2026-08-25 and the build resolved to it on 2026-08-27.

  **Why an exact pin did not prevent it.** `swift-clocks` is pinned to exactly 1.1.0. But `swift-clocks`
  asks for the two packages *it* needs as "this version or newer", and nothing in this project overrode
  that — so a resolve takes whatever was published most recently, however recently that was. The exactness
  bought nothing for the two packages standing behind the one that was named. Both are now held at
  `swift-concurrency-extras` 1.4.1 (released 2026-07-24) and `xctest-dynamic-overlay` 1.11.0 (2026-07-09) —
  both, not only the one flagged, since the other floats in exactly the same way and merely happened to
  land on an older release that day. Every borrowed package is now at least a month old: 79, 49 and 34 days.

  **Held by the committed lockfile, not by the manifest, and the difference cost a round to find.** The
  review's suggested fix was to name the two in the manifest with exact versions. That does pin them — and
  it makes the build tool print, on every build on both machines, that a declared dependency is unused,
  because there is no way to say "this version, but I do not use it directly". This project builds clean,
  so two permanent warnings is the wrong trade. The lockfile is what a build actually reads; a version
  hand-written into it survives a resolve, which was checked rather than assumed. So the versions are held
  there, and moving off them takes a deliberate update that shows up as a change to a committed file — the
  same protection model chosen one round earlier for the dependency surface: a person reading a diff.
  One trap found the hard way while proving that: writing a version into the lockfile **by hand** is not a
  way to pin anything. The tool quietly replaced the made-up commit identifier with the real one for that
  version, and the version itself reverted on a later run without saying so. The safe route is to let the
  tool write the entry — name the version in the manifest, resolve, then take the name back out — and then
  read the file to confirm, rather than trusting that a restore did what it looked like it did.

  **A second crash, unrelated, found because these runs were repeated.** One run on Linux died outright —
  not a check failing, the whole run — inside the system library's own way of starting another program,
  while it counted the files the process had open by reading a listing that other threads were changing
  underneath it. The next identical run passed, which is what a race looks like. The cause was the single
  place in this project that started a program the system library's way instead of the one sanctioned way
  everything else uses, which the charter requires; it was a check that runs a real shell to read its own
  quoting back. Moved onto the sanctioned way, that being the only such place left. Seven Linux runs since,
  all clean.

  **And a third, in my own work from the previous round.** The check that the watchdog ends an overrunning
  program was claimed as immune to a busy machine. It is not: it moved the clock forward once, and the wait
  it needed to move past is set up *inside* the call, so if that had not happened yet the clock advanced
  over an empty schedule and the real program won the race. It failed exactly that way once. It now keeps
  the clock moving until the call finishes, which cannot miss. Thirty consecutive runs since, all passing.

  **The rule the review cited does not exist in this project.** It called seven days "the dependency
  vetting window"; nothing in the charter, the contributor notes or the design document sets any minimum
  age. So this was decided on its merits rather than by pointing at a rule. Holding off on a brand-new
  release is genuine current practice — the automated update tools ship it as
  [Renovate's minimum release age](https://docs.renovatebot.com/key-concepts/minimum-release-age/) and as
  Dependabot's cooldown, which became a **three-day default on 14 July 2026** — and three to five days is
  the usual recommendation. Two days is inside even the shortest of those. The seven-day figure appears to
  be the reviewer's own; the concern behind it is mainstream.

  **Kept in proportion.** All three packages are test-only and reach nothing that ships, so nobody running
  the released program was exposed. The exposure was to developer machines and the shared build machine
  while the suite runs — real, but much narrower than the wording suggested.

- **2026-08-27 — fifty-fifth round: loose ends after taking on a testing-only dependency, and a guard
  that was built, reviewed, and taken back out.**

  **Documents that list what this project depends on.** Three do. Two were updated when the dependency was
  taken on; the design document was not, so it still described a set of outside code that no longer matched
  the build description. Its policy section, its list of known-good versions, its version marker and its own
  revision history now agree with the others. The roadmap's "Dependencies" section turned out to be about
  the order phases are built in, not outside code, so it correctly needed nothing — checked, not assumed.

  **One small hazard closed.** Only `.build/` was ignored, so a second build folder made while testing the
  other platform was swept into a commit as four embedded repositories. Folders named alongside it are now
  ignored too.

  **A guard was built for the promise about testing-only code, and then removed on review.** The written
  rule says three packages attach to tests and reach nothing that ships. A step on the shared build machine
  was added to re-check that on every change. On review it did not earn its place: the only thing it
  guards against is somebody deliberately editing the build description to attach a testing-only clock to
  shipped code, which is a single visible line in a small file that a person reads before anything is
  committed, and which nobody has a reason to write. Against that, it cost two new files in a new folder,
  and a hardcoded list of names with nothing tying it to the written rule it claimed to enforce — the same
  "written in one place, silently missing from its twin" fault this effort has spent days removing, freshly
  introduced. It also only ever checked those three names, so a brand-new unapproved package in shipped code
  would have passed it: narrower than the rule, while reading as broader. The sentence claiming the promise
  is "checked on every change" was removed along with it, rather than keeping a script alive to make a
  sentence true. Worth stating plainly, because it is the general lesson: a claim about *behaviour* earns a
  check that fails when the behaviour breaks; a claim about *policy* can be a rule that a person enforces
  when reading a change, and dressing the second up as the first buys confidence rather than safety.

  **Two facts kept from the attempt, both of which cost time to find.** First, the package tool cannot be
  asked anything from inside the test suite: it takes a lock on the package while the suite runs, so a
  check written as a test waits on a lock the test itself is holding, and the run never finishes. Pointing
  it at a different build folder does not help — the lock is on the package. Second, the toolchain image
  the Linux build machine runs in has neither Python nor `jq`, so a check written in either passes on one
  machine and cannot start at all on the other. Both were found by running them, not by reasoning about
  them.

- **2026-08-27 — fifty-fourth round: checks stop waiting for time to pass and start moving it by hand,
  under a charter amendment.**

  Rounds fifty-one and fifty-three each fixed a check that judged how long a real wait took, which is
  really a judgement of how busy the machine is. Both fixes made the judgements *safe against* a busy
  machine. This round removes the waiting instead, which is the stronger thing and the settled Swift
  practice. **Charter 1.3.0 → 1.4.0** sanctions it.

  **The dependency is three packages, not one.** `swift-clocks` brings `swift-concurrency-extras` and
  `xctest-dynamic-overlay` with it; all three are MIT and all three are named in the charter, because
  naming only the one asked for would understate what was actually taken on. They attach to two test
  targets and to nothing that ships. Building the released program on its own into an empty folder
  fetches all three while the package graph is worked out and then compiles and links **none** of them,
  leaving no trace behind — checked, not assumed. Shipped code takes the standard library's own clock and
  falls back to the real one, so no run behaves differently.

  **How a run gets its clock.** A clock held as *some clock or other* cannot be asked for a moment in
  time — the kind has to be known. So the kind is captured once, where it is still known, as "make me a
  stopwatch", and the rest of the file only ever starts stopwatches. The watchdog that ends an overrunning
  program takes a clock the same way.

  **Four checks rewritten, one added, one deletion.**
  - *The watchdog.* It used to start a program that sleeps three seconds and give the watchdog two tenths
    of a second to beat it — a fifteen-fold margin, and so a claim the machine would not be busy. It is
    now given **ten minutes**, far longer than the program lives, which is what makes it honest: on a real
    clock the program would always win and the check would fail, so the only way it can pass is if the
    watchdog truly waits on the clock handed to it. Put the wait back on a real clock and it fails after
    3.0 seconds — the program winning, exactly as predicted. It takes four thousandths of a second now.
  - *The slow grader.* The grader moves the clock on rather than waiting on it. Waiting would hang: the
    run is stopped inside the grader, and a wait that has not been reached yet cannot be pushed past ahead
    of time, so nothing is left to move the clock. Moving it on directly makes the same amount of time
    pass, which is all the code being checked can see. The figure recorded for the attempt must now be
    **exactly nothing**, rather than merely far enough below the whole call.
  - *The two conversion checks.* Both waited and then judged. Both now move the clock a stated amount and
    say what the answer must be.
  - *Added, and the suite needs it.* Everything above drives a clock moved by hand, and all of it would go
    on passing if the clock used when nobody supplies one never moved — at which point every attempt would
    be recorded as taking no time and the very figure this tool publishes would be zero everywhere. One
    check uses the real clock and asserts only that *some* time went by, never how much.
  - *Deleted.* The helper that read the real clock had no caller left in shipped code once the stopwatch
    arrived; only its own checks kept it alive.

  **A mistake of mine, caught by my own check.** I asserted the answer for sixty thousandths of a second
  as an exact figure. A fraction of a second counted in the clock's smallest unit runs past the range the
  number format holds exactly, so it came back a millionth of a millionth of a millionth high. The
  comparisons now allow that much slack, which is still far tighter than any mistake worth catching.

  **Verified.** Each change undone in turn makes its own check fail, including the new one. Twenty
  consecutive runs of the two rewritten checks on a deliberately loaded machine, all passing. Both
  machines: **1125 checks in 177 groups**, nothing from the compiler.

- **2026-08-27 — fifty-third round: the shared branch went red, in a check sitting ten lines from the one
  I had just rewritten for exactly this mistake.**

  A check waited sixty thousandths of a second and then insisted the answer came back under five seconds.
  The build machine took **six seconds** to finish that wait. Round fifty-one fixed a check of precisely
  this shape and wrote the reason out beside it; the one directly above it kept the same ceiling and was
  left alone. Both machines now pass **1124 checks in 177 groups** with nothing to report from the
  compiler.

  **A ceiling on a measured wait is a statement about the machine, not about the code.** The floor is
  different and is sound: waiting sixty thousandths of a second guarantees *at least* that much time
  passed, on any machine, however busy. A delay can only push the answer up, never down. So the floor
  stays and the ceiling goes.

  **The reason a ceiling was reached for at all was a design mistake underneath.** The sum that turns a
  measured span into a number of seconds was written inside the same call that reads the clock, so the
  only way to exercise the sum was to wait and then judge the answer — and judging the answer from above
  means judging the machine. The sum is now its own call. The direction the ceiling was meant to guard,
  a span of a fraction of a second reported as minutes, is covered against spans of exactly known length
  with no waiting anywhere in it, so no machine can influence the result. One of those spans is an hour
  and half a second: whole seconds and the fraction are carried separately, and quietly dropping the
  fraction answers every other case correctly.

  **Sweeping for the same mistake elsewhere turned up one more, not yet failing.** That a slow grader's
  half-second stays out of the time recorded for an attempt was being demonstrated by the recorded time
  coming in under four tenths of a second — again a claim that the machine was quick, waiting to go red
  the first time it wasn't. It now compares the recorded figure against the time the whole call took: the
  grader's half-second is inside one and must be outside the other, so a gap of at least that much has to
  separate them. A delay anywhere lands in both figures and leaves the gap untouched. This was the only
  other one; the shipped program has no comparison of this kind at all, and the rest of the checks have
  no ceiling on any measured span.

  **Verified by reproducing the failure rather than arguing about it.** Loading the machine to sixteen
  stretched a sixty-thousandths wait by only a tenth — nowhere near what the build machine did, so on its
  own that proved little and is recorded here as such. Making the wait itself take 6.1 seconds reproduces
  the failure exactly: the old ceiling fails, the rewritten check passes. Undoing each fix in turn makes
  its own check fail — the scale of the sum, and the grader's time leaking into the recorded figure.

- **2026-08-27 — fifty-second round: both machines now run the same checks and finish silent, and the
  test rig no longer guesses where the program it is testing lives.**

  The Linux machine passes: **1123 checks in 177 groups**, matching the Mac exactly, with no compiler
  complaints from our own files on either.

  **Five compiler complaints, four of which only one machine ever showed.** The file-system library
  shipped on Apple's platforms marks a handful of calls "you may ignore the answer"; the separate
  version used on Linux does not. So this code was quiet on the Mac by accident of how someone else
  annotated a library, not because the ignored answers were unneeded. Three of them asked "does this
  path exist, and is it a folder?" and then threw the first half away. Seeding the folder flag to *true*
  and asking about a path that is not there shows why that matters: the flag comes back still true,
  untouched. The two answers only mean something read together. The rule now appears once instead of
  being written out separately in two places that could drift apart, and it keeps the behaviour that was
  already there — a path that has gone away, or a shortcut aimed at nothing, stays in the list rather
  than quietly disappearing from it. A new check covers exactly that: undo the fix and the dangling
  shortcut vanishes while six real files remain listed, so the check has teeth.

  **A complaint on *both* machines, which corrects an earlier claim of mine that the Mac build was
  silent.** One test marked a call as able-to-fail when it cannot. Removed.

  **A test that created a marker file and never checked that it worked.** It then asked a directory
  listing to show that marker. Had the file never been written, the listing would have come back empty
  and been read as "the working folder was never set" — the wrong diagnosis entirely. It now stops
  immediately and says so.

  **The rig that launches the program under test was pinned to one folder name.** Its own description
  promised it worked whatever folder the build wrote to. That was true on the Mac, which asks the test
  bundle where it is, and false on Linux, which had the default folder name written into it. Point a
  build at a different folder — as anyone comparing two builds does — and it reaches into an unrelated
  one. Here that was loud, because the program it found was built for another kind of processor and
  refused to start, **362 times**. On a machine where both builds are for the same processor it would be
  silent: a leftover copy answers every check with an older version's behaviour and the run still reads
  green. It now asks the test runner where *it* is and looks next door, which is what the description
  always claimed. Measured against the exact command that failed: **362 launch failures before, 0 after**,
  with the other build still present and visible.

  **Two things seen and deliberately left alone,** recorded here so they are not lost. First, the list of
  files a grader is shown and the list of files the run left behind disagree about shortcuts that point at
  a folder: the second keeps every shortcut, the first drops those. There is one caller of the first in
  the shipped program and no demonstration of harm, so this is written down rather than changed. Second,
  the two ways of building a run record disagree about repeated check names — the one taking full results
  rejects them, the one taking per-check totals does not. Only tests use the second; the shipped program
  rebuilds a record by reading it back, and that path does reject them.

- **2026-08-27 — fifty-first round: the build machine running Linux failed five checks, and one of them was
  a fix of mine that never worked there at all.**

  Everything below is the theme this effort has been circling for days — safety or behaviour borrowed from
  the machine it was written on — this time in my own work, found only because a second platform ran it.

  **A fix that worked on one platform and not the other.** A folder that cannot be read must report an
  incomplete list, never "no files, and that is all of them", because the grader is told the list is the
  last word on whether a file exists. That relied on being handed nothing when the folder cannot be opened
  — true on one platform; on the other a working walker is handed back that simply yields no entries. So
  the defect the fix was written for was still live on Linux. It now asks whether the folder exists and can
  be read, which is the same answer everywhere.

  **A test that measured how busy the machine was.** A forty-millisecond wait was asserted to measure under
  a second; on a loaded build machine it took two. The property being checked is that fractions of a second
  survive the conversion, so it now checks that — a measurement carrying a fraction — rather than a
  wall-clock bound that says more about the machine than the code.

  **A test whose guard depended on the order files are listed in.** With a limit of one, which single file
  the walk reaches differs by platform, so the assertion that makes the test mean anything held on one and
  failed on the other. A limit of zero reaches nothing anywhere, which is what the guard was trying to say.

  **A test asserting a capability of the machine rather than a promise of the tool.** An unreadable file's
  message gives the exact line and column on one platform and only "not valid JSON" on the other. That is
  the reading library's doing, not this program's. The position is now asserted where the machine can
  supply it, asked the same way the program itself asks so the two cannot disagree — and the guarantees
  that *are* this tool's, naming the reader's own file and never its own internals, are asserted
  everywhere.

  **Checked that conditioning the assertion had not quietly disabled it here**: breaking the position
  extraction still fails the test on this machine, so the branch is live rather than skipped on both.

  1122 tests / 177 suites green locally, zero warnings; staged, no commits. The Linux result is the one
  that matters and is not yet known.

- **2026-08-25 — fiftieth round: a row said one thing was checked and it failed, while the evidence inside
  that same row said it was never measured.**

  Each routing attempt is written as its own row in the saved file. An attempt that never ran was written
  with one thing checked, one failure, and a score of nothing — beside an evidence line reading "not
  measured". The object contradicted itself. Reproduced for both an attempt that never ran and one that ran
  out of time: each produced one checked item where none should have been.

  Worse than the contradiction: the summary above those rows already left such attempts out, so anything
  working out a rate from the rows got a different answer from the recompute this file exists to support —
  the two halves of one document disagreeing about the same attempts.

  **The recommended fix would have broken the agreement it was trying to create.** It proposed leaving out
  both attempts that never ran *and* attempts that ran out of time. But the summary leaves out only the
  first: running out of time contributes a zero there, and counts as measured. Leaving it out of the rows
  as well would have made them disagree again, in the other direction. What is left out is now exactly what
  the summary leaves out — which is the point, and it also holds to the rule settled earlier in this work
  that running out of time is a real answer: the skill did not fire in the time allowed.

  This is the fourth place the same rule had to be applied, and the third time it was applied to a
  container while something inside it was missed — the comment two lines above the offending code already
  said "third place with the same fault".

  **The contradiction then moved from the figures into the words, and had to be chased there too.** With
  the numbers corrected, an attempt that ran out of time recorded a graded failure while the evidence text
  beside it still read "not measured" — it had shared that wording with attempts that never ran, and only
  the second kind now discards the text. Running out of time has its own wording, phrased to be true in
  both directions a routing check can be written: one can require that the skill is reached for, or that
  it is not, and running out of time fails either — not because the answer was seen to be wrong but
  because it was never seen at all in the time allowed, and an unobserved answer cannot be recorded as a
  pass. A second reviewer caught this; fixing the numbers and leaving the words is the same defect one
  layer along.

  Two undos, failing five and two tests. 1122 tests / 177 suites green, zero warnings; staged, no commits.

- **2026-08-25 — forty-ninth round: the reader I added rebuilt the report's own figures and believed the
  block sitting next to them.**

  Last round the published report was made readable, and made to rebuild every figure from its rows rather
  than take them from the text. The before-and-after comparison beside those figures was handed straight
  to a generated reader. Reproduced: tampering with the tally of checks a skill fixed and reading the file
  back returned **ninety-nine** where the rows supported one. So a published report could state a result
  its own rows contradict. The same reader also accepted a repeated check name, which both other ways of
  building a report refuse — making the published format the most permissive of the three when it exists
  to mirror them. Both were mine, from one round earlier: the rule was applied to the container and not to
  what it contained.

  Fixed by rebuilding the comparison from its paired rows, and by refusing a repeated name in the report
  and in its per-axis twin. Only what cannot be worked out from the counts is still stored: how much longer
  the runs took, what they cost, and how many attempts were thrown out.

  **Five sightings triaged, four settled without code:**

  - A repeated name in a routing or without-skill axis — **real, fixed with the above**, since it is the
    same reader one level down.
  - A symlinked input reported to the grader as newly created output — **not reachable**, and pleasingly
    because of earlier work in this same effort: a named input that is a link is refused when it is
    resolved, and a link inside a folder is skipped when staged, so a link in the workspace was made by the
    run and calling it created is correct.
  - A check with no graded attempts reading as *failed* — **true, and already recorded as open** in design
    §14-23, where the fix was attempted, reverted, and the blocker written down.
  - A generated command carrying both a list of numbers and a name starting with a hyphen — **verified by
    running it**, which is what the sighting said was missing: the list stops at the end-of-options marker
    and the name is read as a name. Now pinned by a test.
  - Replaying with no verdict map defaulting every missing verdict to pass — **confirmed, and by design**:
    it is how the offline seam runs without a map. Worth knowing that a regression cannot be demonstrated
    in that mode; not a fault.

  Two undos, failing three and four tests. 1119 tests / 176 suites green, zero warnings; staged, no commits.

- **2026-08-25 — forty-eighth round: the container obeyed none of the three rules inside it.**

  Each figure in a run's per-arm block is withheld rather than invented when there is nothing behind it —
  no score, no timing, no cost. The block *holding* none of them was written anyway, so a run where every
  attempt failed to be set up produced an arm whose entire value was `{}`. Reproduced: the entry came back
  as an empty object. Reachable in practice, because an attempt whose workspace cannot be prepared records
  no verdicts, no duration and no cost — so a run where that happens throughout has nothing to put in the
  block at all. Now the block answers "nothing" and the arm is left out, which is what the two helpers it
  calls already did.

  **An existing test broke, and it was the test that needed changing rather than the fix.** It pinned the
  case where every attempt was *disqualified* — a skill fired where none may exist — and asserted the arm
  was present with no score in it. Its attempts carry no timing and no cost either, so under the new rule
  the arm disappears entirely. In a real run a disqualified attempt did run and did cost something, so its
  arm would still appear with only the score missing; the fixture is thinner than reality. The assertion
  now states the rule — no score is stated for that arm — which holds whether or not the arm appears, and
  still fails if a score is ever written there.

  **The second finding is false, and was already covered.** A marker containing a closing bracket was said
  to break recovery, on the reasoning that the last bracket would be the one inside it. It is not: recovery
  runs to the last bracket, which is the closing one added *after* the marker. Markers containing `]`, `[`,
  `v[1] release`, `with ] and [` and `trailing ]]]` all round-trip, pinned by tests added earlier in this
  work. The reporter flagged it as unverified, which it was.

  **Distinguishing a real failure from the build artefact worked.** Two failures appeared right after a
  restore; one vanished on the next run — the artefact, now seen four times — and one persisted and named
  itself, which is the one above. Re-running before diagnosing is what separated them.

  One undo, failing its test. 1116 tests / 175 suites green, zero warnings; staged, no commits.

- **2026-08-25 — forty-seventh round: two runs starting in the same second could overwrite each other's
  records, and I had argued in this very log that they could not.**

  Each run names its folder with a timestamp to the second plus the first eight characters of a random
  identifier. Eight hex characters is a birthday bound on thirty-two bits. When two runs collide, asking
  for a folder that already exists **succeeds silently** — measured — so the second run writes its
  transcripts, traces and records into the first run's folder, and preparing a workspace there deletes what
  is already in it.

  **The reasoning that let this stand was mine, and it was wrong in an instructive way.** An earlier entry
  in this log defended the short identifier: a clash needs two runs in the same second, whereas the
  throwaway working copy has no timestamp and therefore needed the full width. That weighed how *likely* a
  clash was and never weighed what one *does*. The working copy refuses a clash outright — it fails safe.
  The records folder accepts one silently — it fails unsafe. The one that fails unsafe needed the width
  more, not less. The old entry is marked corrected rather than rewritten, because it is a record of what
  was thought at the time.

  Both now use the whole identifier, matching what the working copy already did. The comment on a test
  that asserted the opposite is corrected too, and says plainly that it cannot force a clash — that would
  mean winning a one-in-four-billion race — so it covers the outcome that holds either way.

  **Separately: the contributor guide listed nine commands as available that the tool refuses.** The design
  document has always marked the unshipped ones and had a test enforcing it; the guide duplicated the list
  with neither. A duplicated list with only one copy checked is a list that drifts. The guide now separates
  what answers today from what is planned, and a test checks the first half against what the binary
  registers.

  **That test was worthless when first written and the undo caught it.** It scanned line by line for the
  word "planned" — but the heading and the entries share a line, so every entry inherited the word from the
  heading and nothing could ever fail. It now checks the "answers today" list specifically, and undoing it
  fails with the offending name.

  **A third sighting of the build artefact.** Eleven failures appeared on the run immediately after a source
  file was restored from a backup, and vanished on the next run with no change. Same signature as the two
  earlier occurrences: it only ever happens on the first run after a restore. Confidence that this is an
  artefact of how the undo checks are performed, rather than a fault in the tests, is now high.

  Two undos, one of which failed to bite until the test was rewritten. 1114 tests / 174 suites green, zero
  warnings; staged, no commits.

- **2026-08-25 — forty-sixth round: rewriting the saved results deleted everything this version did not
  recognise.**

  The file is documented as keeping what it does not understand, so a field written by a newer version of
  the tool survives being rewritten by an older one. It did the opposite. Reproduced before changing
  anything: a field at the top level and a field inside the settings block were both handed in and both
  discarded. The cause is the named one — the writer built a fresh document out of only the fields it knew
  about, which is precisely how this kind of data is lost.

  **The two industry precedents point opposite ways, and the difference decides it.** Container-orchestration
  schemas *delete* what they do not recognise, because those documents are hand-written input to a shared
  store and deleting enforces a declared description of what is valid. Message formats *keep* it — a
  behaviour removed once and restored, because losing it broke systems where an older component rewrites a
  newer one's data. This file is the second case: nobody hand-writes it, and the only writers are versions
  of this tool. Deleting is also only coherent alongside a description of every valid field, which this
  format deliberately does not have — it permits fields to be added — so deleting would remove legitimate
  ones.

  **The rule adopted is the standard one for combining documents:** sections addressed by name are merged
  into, lists are replaced whole. That also settled a question asked the other way round earlier: the
  recorded attempts are replaced not because "they describe this run", but because a name says what a new
  value corresponds to and a position in a list says nothing. A principled line rather than a judgement,
  which matters here — distinctions of this kind have drifted repeatedly.

  **A carried-forward figure can be seen and corrected; a destroyed one cannot be recovered by anyone.**
  That asymmetry is what makes keeping the lesser risk, and it is written into the code rather than left as
  reasoning that happened once.

  Also: the one place in the comparison path that asserted a value was present, a line after computing it,
  now computes it once and uses it where it is known to exist — the surrounding code avoids such
  assertions, and this was the only one.

  Four items reported as intentional were checked and agreed with: best-effort cleanup that reports when it
  fails, a check that fails closed, a reader that skips one bad line rather than losing a whole session,
  and readiness checks skipped when running offline.

  One undo, failing four assertions. 1113 tests / 174 suites green, zero warnings; staged, no commits.

- **2026-08-25 — forty-fifth round: the machine-readable output could be written but not read.**

  The published run payload carries two names spelling a digit as a word — `pass_1` and `pass_1_evals` —
  because that is how the measure is written in the literature. The standard rule for turning a published
  name back into a program's own name turns those into `pass1` and `pass1Evals`, which match nothing.
  Reproduced: the text written out is correct, and reading it back returns nothing at all.

  Two more faults on top. The report type could not be read back *at all* — it was only ever writable, so
  nothing could consume what this tool publishes and the contract was one-way. And a third name,
  `cost_unreadable`, was given an explicit spelling it did not need; the ordinary rule already produces
  exactly that, and stating it is what stopped it being read. Both my own, from earlier rounds.

  Fixed by teaching the shared reader that a name whose parts include a bare number is published exactly
  as spelled, and by rebuilding the report from its rows on read. The wire format is unchanged to the byte.

  **Replacing a built-in rule means re-implementing it, so it is pinned against the original.** Every
  published name this project uses is compared to what the standard rule produces, except the two that are
  the reason for the replacement — so an accidental difference cannot quietly stop some other field being
  read.

  **Reading rebuilds rather than believes.** Every figure in the report is worked out from its rows, so a
  generated reader would have taken them from the text and let a hand-edited file state a score its own
  rows contradict. It hands the rows back to the same initialiser that built them. Same decision as the
  proving command's report two rounds ago.

  **The intermittent failure has an explanation, though still no name.** It appeared twice, both times on
  the first run immediately after a source file was restored from a backup copy, and never on any run
  after that — twenty-plus clean runs between and after. Restoring a file gives it a fresh modification
  time while reverting its contents, so parts of the build are rebuilt and parts are not; the same shape as
  the link errors seen earlier when a default argument changed a symbol. Almost certainly an artefact of
  how the undo checks are performed, not a fault in the tests. Recorded as probable rather than proven,
  since the failing test was never named.

  One undo, failing three tests. 1110 tests / 173 suites green, zero warnings; staged, no commits.

- **2026-08-25 — forty-fourth round: "nobody reported a cost" and "somebody reported one we could not
  read" stopped looking the same.**

  When a reply reports what it cost in a form that cannot be trusted — a field missing, a figure below
  none — the whole session's counts are discarded, deliberately, so that a part-read total never enters a
  record. But a session that reported nothing at all was recorded identically. Both came out as no
  figures, so nothing anywhere distinguished a run that cost nothing to report from a run whose cost was
  reported and unusable — and only the second is a problem worth looking at. Same shape as the reason an
  attempt was never graded, which had the same fix two rounds earlier.

  Driven by a failing test written first, exactly as suggested in review: it would not compile until the
  state existed, and failed until the parser set it. Three layers, as predicted — the diagnostic record
  states which of the three it was, the attempt record carries it, and the run says so on screen. It is
  deliberately **not** a failure and does not change the exit number: the measurements are unaffected, only
  the cost record is.

  **An existing test caught something worth keeping.** It asserted that a trace with no cost figures
  contains no text matching "usage" — but what it meant was "no cost figures", and the looser spelling
  caught the new field that says *why* they are absent, which is the opposite of what it guarded. Tightened
  to check the thing it meant. The field is stated on every record rather than omitted when uninformative,
  which departs from this project's usual habit of withholding: a diagnostic record is the one place where
  being explicit beats making a reader infer, and stating an observed fact is not the same as inventing a
  verdict.

  **The intermittent failure from last round was hunted and not caught** — twelve further clean runs,
  including six deliberate repeats. One hypothesis is ruled out: tests here already run one at a time, so
  it was not a parallel race. The original output was never captured to a file, so the test cannot be
  named. Left open rather than guessed at.

  One undo, failing its test. 1106 tests / 171 suites green, zero warnings; staged, no commits.

- **2026-08-25 — forty-third round: one real bug, one half-false, three that were decisions needing to be
  written where a reader would find them.**

  **Real: "is this path inside that folder?" answered "no" for every path when the folder was the whole
  filesystem.** The check appended a separator to the folder — right for every ordinary one, and wrong for
  the single case that already ends in a separator, where it produced a prefix nothing can start with. It
  failed safe rather than open, so nothing was ever wrongly allowed through; it simply made a routine
  offered for anyone to call unusable for a folder nobody currently passes. Fixed for any folder.

  **My own fix had a bug and my own test caught it.** Making the root work broke the rule that a folder is
  not inside *itself* — the root came back as inside the root. That rule had been an accident of how the
  text was joined rather than something stated; it is stated now.

  **Half-false: the stand-in reading a sibling skill's declaration instead of the target's.** It reads the
  first staged skill that carries one, and the review asked whether that could be a sibling. It cannot,
  when there is a skill under test: the loaded one is put ahead of the rest. That was a real guarantee with
  nothing checking it and nothing saying so — now both. The genuine residue is routing runs, which stage a
  whole corpus with nothing loaded, so there is no target to prefer and two declaring skills would be
  decided alphabetically; recorded as an unsupported fixture shape rather than papered over.

  **Three were decisions already made, recorded only in the source.** The saved results file has two blocks
  answering different questions — one records what happened on each attempt and stores zeros for an attempt
  that produced no verdicts, the other records what was measured and withholds its figures for the same
  attempt. And its three signed differences are not over one population: the quality difference counts only
  graded attempts, while the time and cost differences count every attempt that reported a value, because
  an attempt that broke down partway still took time and still cost money. All correct, all deliberate, and
  none of it discoverable by someone reading the file. Written where the file's shape is described.

  **One left for later.** When a model's reply reports its token usage incompletely, the whole run's counts
  are discarded — deliberately, so a half-read figure never enters a total — but nothing distinguishes
  "none were reported" from "reported and unusable". Same shape as the discarded reason fixed earlier; it
  needs a flag carried through three layers, so it is recorded rather than half-done.

  **An intermittent failure was seen once and not reproduced** in six subsequent full runs, and the run that
  showed it did not name the test. Recorded because a tool for measuring reliability having an unexplained
  flaky test is worth knowing, even unresolved.

  Three undos, each failing its tests. 1103 tests / 170 suites green, zero warnings; staged, no commits.

- **2026-08-25 — the mutation-testing tool was tried on this project and does not work on it.**

  Recorded because the diagnosis is worth more than the attempt: anyone who reaches for this tool here
  will hit the same wall, and two of the four blockers have workarounds worth writing down.

  1. **The copied project inherits a stale compiler cache.** The tool copies the whole directory,
     including build products, and the copied cache still names the original location — so the copy will
     not compile. *Workaround:* clear the compiler cache directory before running, keeping everything else.
  2. **Clearing the whole build directory instead breaks it differently** — the fetched dependencies live
     there too, and the copy then tries to download them. *Workaround:* build first, then clear only the
     compiler cache.
  3. **The tool's own rewriting corrupts files containing non-ASCII characters.** With the above cleared,
     it produced source that does not compile: `cannot find operator '||&&'` and an identifier with two
     characters eaten off the front — `baseTokens` became `seTokens`. Two characters is exactly the
     difference between the byte length and the character length of one em-dash, and there is an em-dash
     in the lines immediately before. **128 of this project's 132 source files contain non-ASCII**, because
     the house style is prose comments using em-dashes and arrows. There is no workaround: the tool
     miscounts positions in almost every file here.
  4. **Applying debug entitlements to the copied executable failed** for want of a signing tool in this
     environment. Probably specific to where this ran rather than to the project.

  **Conclusion: not adopted, and the earlier recommendation to adopt it is withdrawn.** Blocker 3 is a
  defect in the tool that this codebase will hit everywhere, independent of environment or configuration.
  The generated configuration was correct and is not kept, since a configuration file for a tool that
  cannot run is a stale artifact of the kind this work has been removing.

  What stands instead is the earlier alternative: break the scoring and comparison code by hand in a
  handful of deliberate ways and see which tests notice. Slower, narrower, and it works.

  Working tree verified unchanged afterwards; 1099 tests / 168 suites green; staged, no commits.

- **2026-08-25 — forty-second round: seven tests reported success while checking nothing.**

  Taking the insight from the last round — a check whose silent failure looks exactly like success — and
  applying it to the suite itself. Seven tests needed something from the machine (version control
  installed, a filesystem that supports hard links, not running as the administrator account) and simply
  returned when it was absent. Returning is how a test reports success, so on any machine missing one of
  those, the run said they passed while nothing had been checked.

  Every comparable framework has a first-class "did not run" outcome for exactly this — and so does the
  one used here, spelled as a condition attached to the test. **It was already used correctly in three
  places in this repository**, including one that is the exact situation of two of the seven, so this was
  applying an existing local pattern rather than importing one.

  Verified by forcing each condition false: the run now prints `skipped: "needs version control
  installed"` per test instead of counting them as passes. One reporting caveat worth knowing: the
  single-line summary still counts skipped tests in its total, so only the per-test lines distinguish
  them — which is the same reporting gap the literature describes.

  **One of the four flagged sites turned out to be correct and was left alone.** A loop that stops when one
  list runs out looked like a silent skip, but the line directly above it already asserts the two lists are
  the same length; the guard exists because an assertion here records a failure and *keeps going*, so
  without it a mismatch would index past the end and crash the run after the real failure had already been
  reported. That is what the guidance recommends, not a defect.

  **On the tooling question:** the ecosystem's mutation-testing tool for this language does systematically
  what the by-hand undo does one case at a time, can be pointed at a single file, and drives the package's
  own test command. It is not adopted here — it needs installing, which is the user's call.

  1099 tests / 168 suites green, zero warnings, zero silent early returns remaining; staged, no commits.

- **2026-08-25 — forty-first round: one finding real, one false.**

  **Real: two figures documented as "cannot be supplied, only derived" were taken straight from the
  file.** The proving command's report is written out as machine-readable text, and how many repeats were
  observed, plus each row's "did this test run at all" flag, are worked out from the counts when a report
  is built. Both were stored values with a reader written by the compiler, so reading a report back simply
  took them from the text. Demonstrated: a report built with nothing recorded said the repeats were none,
  and after one edit to the saved text it read back as ninety-nine, with the row's flag flipped to "it
  ran" while its own counts still said nothing had. The report contradicted itself.

  Nothing reads this format back today, which is why it was worth closing rather than leaving: the same
  hole was closed on the token counts earlier in this work for the same reason — the next reader added
  would inherit it silently, and reading a value back is the second place it is made.

  **False: the token-count reader does not require the roll-up it says it never reads.** The report placed
  a line in that reader decoding the total and discarding it. Measured: the only mention of that field in
  the whole file is where it is written, and text carrying the four parts without it decodes fine,
  deriving the total from them. The reader already matches its documented contract exactly; no change.

  **Four attempts to undo the fix went wrong before one worked**, each caught by an assertion rather than
  by a passing test — two anchors matched twice, and one matched the *building* path instead of the
  *reading* path, which broke the build so no test ran at all. An undo that silently does nothing looks
  exactly like a fix that works. Worth the extra passes: the last one bites on both figures.

  1099 tests / 168 suites green, zero warnings; staged, no commits.

- **2026-08-25 — cleanup sweep: the changes shipped, the descriptions of them did not.**

  Six documentation claims were left describing a tool that no longer exists. None of them break anything
  running; all of them mislead the next reader, and two describe things published as a stable promise.

  - **Both exit-number tables omitted `75`** — the one people read and the one the design keeps — while
    the number itself is described as a stable promise in two other places. Added to both, with the reason
    it is deliberately not the "environment is wrong" number.
  - **The list of ways an attempt can end named one that never shipped and omitted two that did.** It
    promised an `infra` class for a later phase and listed `passed | failed | timeout`; the real set is
    those three plus `polluted` and `error`. Corrected, including why the name `error` was chosen over the
    `infra` the paragraph had promised — and that what remains for that later phase is the retry policy,
    not the class.
  - **A folder-listing example** carried the same never-shipped name.
  - **The scope table** still promised that later phase would deliver the class. It shipped early, and
    under a different name.
  - **The two fields added to the run's machine-readable output** — how many attempts produced no result,
    and how many checks the softer average covers — were described only in the proposal entry, not where
    that output's fields are documented.
  - **The rule catalogue was described as having five rules** while four are implemented. Corrected in one
    place a round earlier and missed here — the same shape as the defects this whole feature keeps
    producing, in prose rather than code.

  One check came back clean: the terminal-detection helper the spend prompt stopped using is still used for
  colour decisions, so nothing was orphaned by that change.

  1096 tests / 167 suites green, zero warnings; staged, no commits.

- **2026-08-25 — fortieth round: how long an attempt took was measured on a clock that gets adjusted.**

  Elapsed time was the difference between two readings of the clock that says what time of day it is. That
  clock is corrected by time-sync, daylight-saving changes, and people setting it by hand, and a correction
  landing during a measurement stretches, shrinks or reverses the answer. This tool publishes the
  difference between how long a run takes with a skill and without it, so a distorted reading is a
  distorted *result*, not a cosmetic wobble.

  One thing the report did not mention and that makes it worse: a duration below zero is not refused
  anywhere, so a backwards correction would have flowed into the averages as a negative — the exact defect
  the sibling measurement, the count of tokens, was given a refusal for earlier in this work. Switching
  clocks removes that possibility by construction rather than adding another guard.

  Four call sites, all in one file, now use a clock that only counts forward and keeps counting while the
  machine sleeps — which is what "how long did this take" means for a run someone is waiting on. The
  standing advice is exactly this: a wall-clock reading used to *measure* an interval rather than to
  *record a moment* should be a monotonic one. The one remaining wall-clock reading nearby is left alone
  deliberately: it stamps a folder name, which is recording a moment.

  **The test is about the part that could actually be wrong.** The clock cannot run backwards by
  construction, so there is nothing to assert there; what is hand-written beside it is the conversion into
  seconds, where an exponent a few places out reports a run of milliseconds as one of hours. Undone, it
  reports a forty-millisecond wait as forty-three million seconds, and both tests catch it.

  1096 tests / 167 suites green, zero warnings; staged, no commits.

- **2026-08-25 — thirty-ninth round: three places said "infrastructure failure" in a comment and wrote
  down "the skill failed".**

  **A run that could not be set up counted against the skill.** Before a skill is measured, it and its
  inputs are copied into a scratch folder; when that failed, the attempt was recorded as a measured
  failure — and the comment on that very line read "couldn't stage → infra failure". The routing check had
  the same fault twice more, one of them under a comment saying "record an infrastructure failure
  instead". A test covering it asserted a measured failure while its own name called the attempts
  infrastructure failures. So a permission problem or a full disk lowered a skill's score and, in a
  before-and-after comparison, could make a working skill look broken. All three now record an attempt
  that was never graded; that value is now the only thing the runner writes for these, and a judged
  failure was already recorded differently.

  The classification is not this project's invention: the standard list of build-failure categories puts
  "job setup failed" among those recommended for automatic retry, and names the thing under test failing
  as the one not to retry. An earlier answer here had it returning the "environment is wrong" number
  instead, which asserts the problem is permanent — a claim the tool cannot support, and the same
  over-claiming rejected when this outcome was named.

  **The question before spending money was gated on the wrong stream.** It is written to the error stream
  and answered from the input stream, but whether to ask at all was decided by the results stream. So the
  ordinary habit of saving results to a file while watching the screen made the tool decide nobody was
  there and stop, refusing to ask a question that would have been visible and answerable. A well-known
  project fixed the identical mistake in a change titled "Check stdin rather than stdout for interactive
  terminals". A progress note had the same fault and was fixed with it.

  **A skill folder that is a link was inspected but not run.** Only the folder *holding* the skills was
  refused. So the commands that merely read a skill would follow a link pointing anywhere on the machine
  while the commands that run one refused it. Declining is what `find`, `ripgrep` and `git` all do by
  default — measured, not assumed.

  **Two claims in the report did not survive measurement, and one of my own tests did not either.**
  Creating a folder whose name has been replaced by a link does not create anything outside the project
  here: it either fails outright or creates nothing. The check still moved earlier, because that safety
  is the platform's rather than this code's — but the comment says plainly that it narrows the gap rather
  than closing it, since checking a name and then acting on it can never be made safe by checking harder.
  And my first test for the link-folder fix passed with the fix removed, because this platform's directory
  listing already omits links; it now supplies its own listing that reports them, which is what the other
  platform's behaviour looks like, and it bites.

  **Two of my three undos did not bite, which is the more useful result.** The link-folder test passed
  with its fix removed, because this platform's directory listing already omits links; it now supplies its
  own listing that reports them and does bite. The records-folder test still passes either way, and
  measuring showed why: the run is already refused at start-up by the check that walks the skill's path.
  So the check added before the folder is created is unreachable by any deterministic test — it guards
  only the case where the link appears after that start-up check and before the folder is made. Kept as
  defence in depth and labelled as such, in the code and in the test, rather than left looking covered.
  The test itself still earns its place: the existing one replaces the record *file* with a link, and
  nothing covered replacing the *folder*.

  1093 tests / 166 suites green, zero warnings; staged, no commits.

- **2026-08-25 — thirty-eighth round: three concerns, two real, and the reported symptom was wrong on
  both counts.**

  **A pipe, socket or device named as an input, or found while staging a folder.** The staging code
  checked that a source was not a link and not a folder, then handed it to the file-copying routine —
  so anything else went straight through. The concern said the copy could hang; measured, it does not
  hang here, it fails immediately with "operation not supported". The real symptom is worse in a
  different way: an odd entry *inside* a folder being staged **aborts the whole copy**, so one stray
  pipe kills a run rather than being passed over. And the guarantee that it fails rather than blocks is
  the platform's, not this code's — this project builds for more than one, and the two platforms have
  separate implementations of those routines. The check that removes the borrowing already existed and
  was used by three other readers here, each citing the same rule about opening a file whose kind you
  have not established.

  Fixed in both places, with different answers on purpose: a file someone **named** is refused, because
  a named input silently not arriving is a confusing failure later; a file merely **found inside a
  folder** is passed over, exactly as a link already is there, because one odd entry is not a reason to
  abandon a run.

  **My first attempt at the named-input half was wrong and the existing tests caught it.** I made the
  path-permission check also require the file to exist, which is a different contract — three cases that
  legitimately resolve a path before anything is written broke. It now rules only on what is found *if*
  something is: a folder or an ordinary file passes, anything else does not, and absence still resolves.

  **The cache's ignore file was written by hand rather than through the shared routine.** Asking whether
  the file was there and then writing it are two steps and the name can change between them. It now goes
  through the routine used everywhere else, which makes "create only if absent" a single step the
  operating system settles and reports the lost race as an ordinary "file exists" — which for this file
  means somebody already wrote what we were going to. Low risk either way, but it was the one write here
  not using the shared primitive.

  **A dependency revision cited in the design document had drifted** from what the package actually
  pins. Corrected. Half of that report was wrong: `AGENTS.md` already carried the right revision, and a
  mention in a dated history entry was left as written, being a record of what was true then. My own
  notes carried the stale revision too and now say to read it from the package file, since it moves.

  Two undos, each failing its tests. 1091 tests / 164 suites green, zero warnings; staged, no commits.

- **2026-08-24 — thirty-seventh round: my own half-fix from the round before could crash the results
  writer after the money had been spent.**

  Last round I made the per-attempt scores on the without-skill side count only attempts that were
  actually graded, and left the *count* beside them counting every attempt that had not been disqualified.
  Two different sets of attempts feeding the same row. Reproduced before changing anything:

  - **When every attempt on that side failed to grade**, the count was above zero with no scores to
    average, so the row divided by nothing and writing the results file failed outright —
    `EncodingError.invalidValue: nan … Path: consistency.per_eval[1].mean_pass_rate`. That happens in the
    step that saves results, which runs *after* the model calls. The user pays for the run and then the
    command fails, having written nothing.
  - **Short of that**, the two sets merely disagreed. Measured: a live run reported the without-skill side
    as one attempt and no difference; reading the saved file back reported two attempts and a difference of
    half. A saved file that states a different denominator from the run that produced it cannot be
    re-checked against that run, which is the single promise that file exists to keep.

  **The same fault was in two more places**, both summaries that average every attempt in a run: the
  without-skill side and the routing side each counted an attempt that never produced a result as one that
  scored nothing. Where every routing attempt failed to grade, the summary stated a flat "nothing passed"
  for a check nobody measured — which the comment directly above it says it must never do.

  So the rule has now been applied in three separate rounds and missed a sibling every time. The type
  introduced last round stopped a *score* being built from the wrong count; it did not reach these, because
  they assemble lists of per-attempt figures by hand rather than going through it. That is the same shape
  one level down, and worth naming rather than declaring the class closed again.

  Two undos, each failing its tests with the exact numbers reported. A third finding — a corrupt earlier
  results file being treated as absent — is a documented recoverability choice with the real gate before
  any spending, and was left alone, as its reporter suggested.

  1088 tests / 163 suites green, zero warnings; staged, no commits.

- **2026-08-24 — thirty-sixth round: the rule I added last round had been applied in two places out of
  eight, and I was the one who left the other six.**

  Last round introduced the idea of an attempt that was never graded and stopped it counting toward a
  score. Two places were updated. Six were not. Reproduced before changing anything, for a check with two
  passing attempts and one never graded: the headline said the skill passed outright, while the
  before-and-after comparison in the **same report** said two-thirds, claimed three attempts where two
  were graded, and — the damaging part — **did not register that the skill had fixed the check at all**,
  because two-thirds no longer counts as passing. A tool whose purpose is detecting that an edit helped
  had stopped detecting it, from a single network hiccup.

  **Fixed by consolidation, not by patching six sites.** This is the textbook "one change, many scattered
  edits" problem, whose prescribed remedy is a single canonical definition, with tests as the safety net
  during the change rather than instead of it — patching plus a guard test was my first recommendation and
  is the option the literature explicitly rules out. The cause underneath is a bare number standing in for
  a domain idea; the remedy is to name the idea. Scores are now built from a record through one type whose
  two ordinary constructors derive the count themselves, so the total attempted is not something a caller
  can pass by mistake. One route still takes numbers directly — re-deriving from a saved file, where the
  separation was made when the file was written — and it says so. Nothing outside this repository consumes
  these types (the package builds only the executable), so the compiler enumerated every site rather than
  a reviewer having to; the count of missed sites had gone from two, which I found, to eight, which the
  review found.

  Also folded in: the three separate ways a pass rate was assembled became one; the softer overall average
  no longer scores an unmeasurable check as zero, and now publishes how many checks it covers, so the
  correction cannot quietly shrink the basis instead; and the edit-proving command stopped treating an
  ungraded attempt as a failed one, which could report a good edit as a regression.

  **Two findings resolved by changing nothing, both after checking.** Cost and time figures keep counting
  ungraded attempts: the token figure is a sum, so it *is* the spending record, and money spent on an
  attempt that failed was still spent — the standard efficiency measure divides total spend by successful
  results and keeps the numerator gross. That finding's symptom, an arm looking "measured at zero
  quality", disappears once the quality rate stops counting ungraded attempts, which was the other fix. And
  the stand-in's last-ditch fallback deliberately claims nothing rather than risk claiming something wrong;
  restoring the dropped fields would reintroduce the hand-written-JSON hazard its comment describes.

  Style items: a paragraph I had duplicated while restoring a file during a hung verification run, an odd
  accumulator written plainly, and a comment the denominator fix had made wrong.

  One undo, failing both new tests. 1078 tests / 158 suites green, zero warnings; staged, no commits.

- **2026-08-24 — thirty-sixth round: four reported findings; one real and worse than described, one
  half false, one that led somewhere bigger, one already sound.**

  **A run could stop dead while writing down what it cost.** Measured against a control: ordinary token
  counts finish in under eight seconds and exit cleanly, while counts near the largest whole number the
  program holds make the run park and never return — killed after five minutes, nothing written, nothing
  said. Adding the four counts up overflows, which halts rather than wraps. Reachable from a line in a
  skill's own file, and from the numbers a provider reports.

  **Verifying it found a second, quieter fault at a threshold a thousand times lower.** These counts are
  written into the saved results file as JSON, where a number is held as a double, so above about nine
  thousand million million a whole number silently changes on the way through: `…993` is written and reads
  back as `…992`. The file could state a count that is not the one counted. The JSON standard names that
  exact range as the one where every reader agrees on a value, so it is the honest ceiling — and applying
  it removes the stall as a side effect, since four counts below it cannot come near overflowing. Real use
  has ninety-thousand-fold headroom: a thousand tests, a hundred repeats, a full million-token context
  each.

  **The grader was told an incomplete list of files was the last word on what exists.** The list stops
  after fifty thousand entries, and said nothing when it did — the flag recording the cut was computed and
  thrown away by both callers while a comment claimed it was passed on. A run that installs dependencies
  or builds something passes that easily, and the file it actually produced could be pushed off the end,
  so a check like "the run created report.md" would be marked failed with the file sitting there. That
  records a limitation of this tool as a fault in the skill, which is the one thing a measuring tool must
  never do. Files the run produced are now kept whatever else is dropped, and a cut is disclosed with the
  claim narrowed: a listed file certainly exists, a missing one is no longer proof of absence.

  **Two findings needed no code.** A marker containing brackets already survives — measured, including the
  spelling from the original bug — and only brackets in the surrounding text break it, which two existing
  tests already prevent on the only thing that writes it. Pinned anyway, because the tempting repair
  (reading from the last bracket rather than the first) silently truncates markers that work today; the
  undo proves it. And reading a signed number back is not tied to the machine's regional settings — the
  conversion is always the neutral one — so that is pinned rather than changed.

  **Three of my own mistakes, all caught by measuring rather than reading.** The check guarding against a
  halt could itself halt: written plainly, it was safe only because the ceiling declared elsewhere happened
  to be small enough. It now asks for the overflow instead of risking it. And two tests worked their inputs
  out *from* the ceiling, so undoing the ceiling changed what they tested — one of them overflowing while
  the list of cases was being built, which stopped the test process before anything ran. That is what was
  behind three apparent "hangs" I twice explained without measuring; the actual evidence (no compiler
  processes, no build activity, a ten-minute-old test runner) said the build had long finished. A stack
  sample named the argument list in one call. Explaining a stall from plausibility instead of sampling it
  cost three interrupted runs.

  **Found while checking whether the prompt needed a size limit — it does not.** The worst realistic
  grading prompt is about a hundred and sixty thousand tokens against a million-token window. But every
  grading failure that is not a timeout — a provider error, a rate limit, a network blip — is recorded as
  `failed`, a measured failure of the skill. A skill firing where none may exist gets its own outcome and a
  timeout gets its own; everything else is scored against the skill. Not fixed here: a new outcome touches
  the results file, the pass-rate arithmetic and the renderer. It is already planned as the `infra` class
  (F18) and is worth pulling forward.

  **One more found while deciding what to hand over.** A directory that cannot be read answered "no
  entries, and that is the complete list" — which, now that the grader has been taught to trust a list
  that does not say it was cut, asserts that nothing exists and fails every check of the form "the run
  created X". The same defect as the one above, in the sibling path, made sharper by fixing the first.
  An unreadable directory now reports an incomplete list.

  Four undos, failing 3, 4, 1 and 1 tests. 1070 tests / 155 suites green, zero warnings; staged, no
  commits.

- **2026-08-23 — thirty-fifth round: a skill folder named with a leading hyphen got handed a command
  that could not run.**

  Reproduced end to end before changing anything. A skill in a folder called `-demo` was accepted
  silently, reported as having no problems, and the tool ended by printing `→ next: skillet run -demo`.
  Running that exact line gives *"Unknown option '-demo'"* — the word is read as a switch rather than as a
  name.

  **Quoting is the wrong layer, and could not have fixed it.** `skillet run '-demo'` fails identically,
  because the shell removes the quotes and the program still receives `-demo`. The established
  shell-quoting libraries leave a leading hyphen alone for exactly this reason; the Rust one's
  quoting-hazards page covers nul bytes and control characters and never mentions hyphens. The catalogued
  name for the other layer is argument injection (CWE-88), whose entry describes this case directly and
  lists two mitigations — mark the end of the options, or refuse the name.

  **The name was already illegal, which changed the answer.** The read-only reference implementation this
  project grounds its rules in rejects this name shape and tests `-leading` by name, and its README adds
  that the name must match the folder. So the argument written into the quoting helper — that refusing a
  name would mean declining to work with an ordinary folder — does not apply here; it was written about
  spaces, which are legal. The deeper gap: this project's rule catalog had **no name rule at all**, three
  rules against the reference implementation's four checks, which is why a folder violating the published
  rule was reported as fine.

  **Both defences, because neither alone closes it.** A new rule `SKILL-L012` checks the **folder** name —
  not the declared one, since the reproduction had folder `-demo` declaring `name: demo`, so a rule reading
  the declared name would have passed while the broken command was still printed. A leading hyphen is
  error-tier (it breaks a command you were told to run); wrong case, underscores, a trailing hyphen, a
  doubled hyphen and over-length warn, since they are off-spec without breaking anything a build should
  fail over. Separately the printed commands now carry the end-of-options marker. That is not decorative:
  the rule is suppressible, and with it suppressed the tool prints `skillet run -- -demo`, which was run
  here and is accepted.

  **The marker has to go last, which the obvious fix gets wrong.** Everything after it is read as a value,
  so putting it in front of the name and leaving the switches behind turns those into values too —
  measured, that form fails with *"3 unexpected arguments"*. Switches are moved ahead of the name instead.
  The subset flag in the proving command had to move into that group rather than being appended, or it
  would have been silently dropped from the command it belongs to.

  Two of my own mistakes, both caught by tests rather than by reading. The helper first tested the
  **quoted** name for a leading hyphen, so a name holding a space became `'-my skill'`, no longer looked
  like a hyphen, skipped the marker, and still reached the program as `-my skill`. And the new end-to-end
  test appended the project location after the printed line, where it landed past the marker — the exact
  trap the line exists to avoid.

  Draft filenames are refused rather than repaired: the tool creates those, and the same function already
  refuses spaces on the same grounds. Only the joined `--out=-x.json` form could ever have made one, since
  the spaced form is refused earlier by the argument reader; both routes are now recorded.

  Also found while verifying: the design catalog described five rules as shipped when three were —
  `SKILL-L010` and `SKILL-L011` exist only as comments. Table corrected, `SKILL-L012` added.

  Three undos, failing 7, 14 and 5 tests. 1058 tests / 153 suites green, zero warnings; staged, no commits.

- **2026-08-23 — thirty-fourth round: reading a value back from a file skipped the check that building
  one in code could not.**

  A count of what a model read and wrote cannot be below none, and the constructor refuses one that is —
  a rule settled last round, in the place a value is built, precisely so it would hold everywhere.
  Reading one back from a saved file builds a value too, and that path checked nothing. Reproduced: a
  file stating minus five tokens read and minus three written decoded without complaint into a value
  whose stated roll-up was minus eight, and whose exact equivalent the constructor refuses outright. The
  type could hold, by way of a file, a value nobody could write in code.

  This is a named and long-settled defect class rather than a local slip: reading an object back is a
  second constructor, and the standing guidance is that it must produce a valid instance whatever it is
  handed, guaranteeing every invariant the first constructor does. A reader that skips the check is the
  documented way an otherwise-careful type ends up in a state it forbids.

  **Scope, measured rather than assumed.** Nothing in the shipped sources reads either of the two files
  that carry these counts back in — the diagnostic file a run leaves behind is written and never re-read,
  and the saved results file is read as raw values, not through this path. So the hole was reachable only
  from test code today, not from a file a user could hand over. Fixed anyway: the type's own
  documentation claimed the invariant held everywhere, and it did not. A sweep for the same shape found
  no second instance — this is the only type here with a validating constructor, and no type gets a
  generated reader that would slip past one.

  **One rule, not two.** The reader hands its four numbers to the constructor and reports the refusal,
  rather than repeating "not below none" beside it — repeating it is how this file acquired several of
  the defects already logged above. The numbers are looked at again only to name which one was
  impossible, and the message gives that name in the spelling the file uses rather than the internal one,
  with the value that was actually there.

  Refusing rather than treating the value as absent or rounding it up to none follows two decisions
  already made here: a value that is present but unreadable is not the same as an absent one, and
  rounding would invent a measurement. One undo, confirming all four fields fail. 1045 tests / 150 suites
  green, zero warnings; staged, no commits.

- **2026-08-23 — thirty-third round: seven findings, all seven real, and the file was contradicting
  itself.**

  **A saved results file said two incompatible things at once.** A run's summary already withheld its
  score when nothing was measured; the rows underneath still said the test had failed. Reproduced: a
  routing check that never ran wrote no summary at all, and its own row said it scored zero and was not
  unreliable — "measured, and it failed" for something nobody tried. One of the three kinds of row already
  withheld its conclusions; the other two had not been reached. The counts stay in every row, because they
  are facts; the three conclusions drawn from attempts are withheld when there were none. Seventeenth
  instance of a rule holding in one place and missing from its sibling.

  **An entry with no usable test name was passed over or quietly invented.** A name is the key every
  result is matched up by. An entry with none was dropped and the score computed from what remained; a
  name written as `1.5` was turned into the text `"1.5"` and used as a real test name. The counts in the
  same entry were already refused when they could not be counts, so the more important field was being
  treated the more leniently. Both now refuse the file, naming what was there — the standard reading of a
  required field is that the document fails, not that the record is skipped, and the one guidance that
  endorses skipping attaches a condition (somewhere to put the rejected record) that a command reading one
  file cannot meet.

  **A thrown-out-attempt count that could not be read counted as none.** That turns "attempts were
  disqualified" into "nothing was disqualified", on the number that decides whether a comparison can be
  trusted at all. Present-but-unreadable now refuses; absent still means none, since most entries never
  carry the field.

  **A count of tokens below none was buildable.** These count what a model read and wrote; none can be
  negative, and one arriving from a provider's reply or a test fixture would have flowed into the totals
  written into the file. It is refused where the value is made rather than checked afterwards, so it holds
  everywhere the value appears. That cost almost nothing: both places that build one from outside text
  already had the exact branch a refusal takes — one discards a partial statement, the other marks the
  session's counts unreadable.

  **A helper answered "four zeros" when handed nothing to average.** Unreachable today, and
  indistinguishable from four real measurements that all came out at zero — the confusion this file has
  been corrected for twice. It now reports "nothing to say" and its caller writes no entry, which also
  collapses a rule that had been duplicated between helper and caller. Stopping the program was considered
  and rejected: an empty list is a real state here, not a mistake, and the convention reserves stopping for
  mistakes.

  **And a message about an unusable value printed `0` for a list or an object** — describing nothing that
  was in the file. It now says what was actually there.

  Five undos, each confirming its test fails. 1043 tests / 150 suites green, zero warnings; staged, no
  commits.

- **2026-08-23 — thirty-second round: a failing check could take the whole run down, and one printed line
  contradicted itself.**

  **Seven places turned a failed check into a crashed run.** A requirement that cannot be met is designed
  to fail its own test and let the rest report; forcing it instead ends the process, so one unmet
  requirement takes every other result with it and reports none of them. Demonstrated: with the force
  removed, an unmet requirement now gives *"Test run with 7 tests in 1 suite failed with 1 issue"* — the
  run finishes and says what went wrong. That failure mode is not hypothetical here; a run was lost to a
  trapping check earlier in this work and the cause took three false starts to find. All seven are gone,
  including the fixture setup that would have crashed the suite over a full disk.

  **The repeat count printed beside the average described a different set of tests from the average.** A
  test that ran on neither side records no repeats, and counting it dragged the figure to zero: measured,
  one test that ran three times each side, beside one that never ran, printed a real average of `+1.00`
  next to a claim that the fewest repeats any test recorded was none — the two halves of one line
  disagreeing. The average already leaves those tests out, so the count now does too.

  **This is not a reversal of the earlier decision, and the difference matters.** That decision covered the
  case where *nothing* ran: the count stays zero and the line says "unmeasurable" instead of stating an
  average. That still holds and is pinned. What it never reached was the mixed case, where some tests ran
  and one did not — which is the case that printed a contradiction. Nothing is hidden by leaving those
  tests out of the count: they are named in the run's omissions list.

  **A test named for the old behaviour had to be flipped**, which is recorded at the line rather than
  quietly changed: it asserted that a test recording nothing drags the count to zero, which was the fault
  described in its own title.

  **Four sweeps came back clean and are recorded rather than re-run later**: no forced unwraps or unchecked
  casts in the shipped sources, the sleeping timeout is cancelled with its group, the file reads are
  guarded and closed, the command's switches match both documents, the disposable-copy path validates and
  confines its own name, and the token figures use one vocabulary across the printed and saved forms.

  Two undos, each confirming its test fails. 1033 tests / 148 suites green, zero warnings; staged, no
  commits.

- **2026-08-23 — thirty-first round: two documentation faults, and the check that would have caught them
  found three more.**

  **The contributor guide named a switch the tool refuses.** Its command-surface list said the proving
  command takes `--apply`; that command takes `--edits`, and the design document says so explicitly. The
  same guide spelled it correctly sixty rows earlier, so the page contradicted itself. Anyone reading it
  to learn the tool would have been sent to a switch the parser rejects.

  **The guide also described a paid check that no longer exists.** It said the proving command's live
  check additionally requires the unedited skill to fail and the edit to fix it. That requirement was
  tried, went red against a real model, and was removed — whether a model follows an edited instruction is
  a fact about the model, not about this program, and asserting it makes the suite fail for something it
  does not control. The guide kept describing the version that was abandoned.

  **The design document had a check for exactly this and the guide did not.** Every switch the design
  document spells is already compared against what the parser accepts. The page contributors are pointed
  at first was not, which is how a wrong switch sat there. That comparison now covers the guide too — and
  running it immediately surfaced three more entries naming switches the parser refuses. All three turned
  out to be genuinely planned, listed in roadmap documents, so the list had been mixing shipped and
  planned without saying which. They are marked now, and the check honours the mark, so a forward-looking
  entry reads as one and a wrong one still fails.

  **One unverified candidate was real and is the same fault this feature keeps finding.** The summary of a
  run and the results it is built from are matched up position by position when the file is written, and
  pairing two lists that way silently stops at the shorter one: measured, a summary describing three tests
  handed one result recorded a single row and the other two vanished from the committed file. Refused now.

  **Two candidates confirmed as not faults, one of them measured.** Two prompts sharing their first
  twenty-eight characters were said to collide: they do not, because the fingerprint on the end is taken
  from the whole prompt, not the shortened part — `-b9634f36` against `-4e413942` for the case described.
  And the short identifier in a run's cache folder name sits behind a timestamp, so a clash needs two runs
  in the same second sharing the same thirty-two bits; the working-copy folder that was widened has no
  timestamp, which is why it needed the width and this does not. **— Wrong, corrected 2026-08-25 (see the
  entry at the top of this log). This weighed how *likely* a clash was without weighing what a clash
  *does*: the working copy refuses one outright, while the cache folder accepts it silently and the second
  run then writes over the first run's records. The cache needed the width more, not less.**

  Three undos, each confirming its test fails. 1031 tests / 148 suites green, zero warnings; staged, no
  commits.

- **2026-08-22 — thirtieth round: a limit that was declared, documented, and never applied — by me.**

  **Listing a finished working folder was written twice, and the two drifted.** One version counted its
  entries and stopped at a limit. The other read the whole folder into memory in a single call and never
  looked at the limit — while its own description said it did. The unlimited one was the version the
  grading path actually used, so a run producing tens of thousands of files could exhaust memory during
  the very step meant to record what it produced.

  **Mine, and the way it happened is the useful part.** The limit was added two rounds ago and landed in
  the wrong one of the two. The test written alongside it called that same wrong one — so the test passed,
  the description claimed the limit, and the version that needed it had neither. Both descriptions had
  also drifted from their bodies: one still said it used a call it no longer used.

  **Fixed by removing the second walker rather than fixing it.** There is now one walk, so there is
  nothing left to drift; it stops at the limit, reports that it stopped so a short list is not passed off
  as a complete one, and lists a shortcut without walking into the tree on the other side. The test now
  calls that walk directly, with a small limit, instead of creating fifty thousand files to reach the real
  one.

  **One thing is not test-enforced, and saying so matters.** Undoing the limit fails the test; putting the
  capture path back on the single-call version does not, because every test of that path uses a small
  folder where both behave identically. What protects it now is that there is only one walker to call.

  **Three secondary observations, one changed and two confirmed.** The results file is read once before
  anything is spent and again minutes later when the run writes; anything could replace it in between, and
  that was passed over in silence — it is now said, on the grounds that whoever replaced it has already
  destroyed what it held, so what would otherwise be lost is the person knowing. An unreadable folder
  still reads as an empty one: the folder is created by this tool moments earlier, and making one flag
  mean both "stopped early" and "could not be read" would make it mean neither, so it is recorded rather
  than changed. And counting attempts that failed or ran out of time is deliberate — the clock ran and the
  tokens were spent either way, which is the same reason a failed attempt's cost is recorded at all;
  what is left out is an attempt that was *disqualified*, which measured nothing rather than measuring
  something badly. Now written at the line, since it has been queried.

  1027 tests / 147 suites green, zero warnings; staged, no commits.

- **2026-08-22 — twenty-ninth round: three findings, all three real, and the one that matters made the
  tool recommend a command that cannot run.**

  **A skill whose folder name contains a space got a printed command that fails.** Every proving run ends
  by printing the exact command that applies what it proved. A folder may legally be called `My Skill`,
  and pasted bare that is two arguments: running exactly what was printed gave *"Unexpected argument
  'Skill'"*. Reproduced end to end against a real project. The rule that already refuses spaces in the
  file this tool *generates* says why, in its own words — whitespace "breaks the command this tool prints
  for you" — and it covered the generated name while the user's folder name went in untouched.

  **Quoted rather than forbidden.** Refusing is right for a name this tool chooses for itself; a folder
  name is the user's and already exists on disk, so refusing would mean declining to work with an ordinary
  folder. Every place that pastes a name into a printed command now quotes it — six of them, across the
  proving, drafting, clustering and preflight commands, since one of them being right is worth nothing.
  Checked by handing the result to a real shell and confirming what comes out the other side is exactly
  the name that went in.

  **A canned reply was looked for relative to wherever you were standing.** The switch that supplies a
  recorded model reply resolved a plain name against the current folder, while the check beside it
  requires the file to be inside the project — so running from elsewhere looked in the wrong place and
  then refused what it found. The same fault in the measuring command's equivalent switch was corrected
  earlier and this twin was missed. Both now mean the same thing.

  **The check I added last round was comparing a path against the thing it was built from.** The builder
  fetched the temporary folder itself instead of using the one it was handed, so confirming the finished
  path stayed inside that folder was true by construction. It still caught a name that walks out, because
  that comes from the name rather than the base — but the moment anything passed a different folder, the
  check would have agreed with itself. Mine, from last round, in the very code I described as the part
  that catches what a spelling list misses.

  **Two of the three fixes are checked by undoing them; one is not, and saying so matters.** The printed
  command and the reply-file path both fail their tests when reverted — the second only after the test was
  changed to pass a project-relative name, since it had been passing a full path and exercising none of
  this. The builder's ignored argument has no biting check: it is private, and the routine that calls it
  sits in a module no test target can reach. What is tested is the underlying rule, including that a path
  built under one folder is not judged as being inside a different one, which is the fault the ignored
  argument would have hidden.

  1025 tests / 147 suites green, zero warnings; staged, no commits.

- **2026-08-22 — twenty-eighth round: four findings, two real, one of them worse than filed and one that
  does not happen.**

  **Counts that cannot both be true were accepted and turned into plausible verdicts.** Each entry in a
  saved results file says how many times a test ran and how many of those runs passed. Measured: a pass
  count of `-1` was accepted and read as "this test is unreliable"; an attempt count of `-1` reached the
  printed summary as `observed k=-1`; and five passes out of three attempts also read as "unreliable"
  rather than as a file that cannot be scored. The report named the first of those; the other two are the
  same fault and are fixed with it. The two counts now have to make sense together, not only on their own.

  **A skill's name could send the throwaway working copy outside the folder it belongs in — and the
  report's own testing concluded it could not.** The copy's location is built by pasting the name into a
  folder name, so a name carrying a path separator followed by a step upwards stops being one folder:
  measured, `a/../../b` resolves beside the machine's temporary area rather than inside it. A name of `..`
  on its own stays inside, which is the case the report tested before concluding escape was impossible.

  It is unreachable through the command — names are matched against folders actually on disk first, and no
  real folder name contains a separator — and it is checked anyway, at the point the value is used rather
  than in the one caller that happens to check it. Two checks: the name must be a plain single name, and
  the finished path must still resolve inside the temporary folder. The second is what catches a spelling
  nobody listed, and undoing it proves the point — without resolving the path first, the raw text still
  begins with the right folder while the path itself escapes.

  **The rule moved to where it could be tested.** Neither the command's own module nor the end-to-end
  suite can reach that helper, so the rule now lives beside the other path-safety checks and is tested
  there. A backslash is deliberately *not* refused: on the systems this runs on it is an ordinary
  character in a name, and anything that genuinely escapes is caught by where the path lands.

  **The version-label scheme does not have the reported fault.** Every awkward label recovers exactly —
  `v[1] release`, `]`, `a]b[c`, `[[[`, `x [y`, `with ] and [` — because the framing is the *first* opening
  and the *last* closing, and the text between is pinned by an existing test to contain neither. What was
  true is that the only test covering it checked that the label *appeared* in the answer, not that it came
  back out: presence where effect was meant, the shape that has hidden three faults here. That assertion
  now exists, and moving the framing by one character fails it.

  **The diagnostic cache write stays best-effort.** Nothing reads that file, and it lives in a folder
  documented as safe to delete, so a failure costs a convenience. Two separate reviews have now asked, so
  the reason is written at the line.

  Four undos, each confirming its test fails. 1019 tests / 146 suites green, zero warnings; staged, no
  commits.

- **2026-08-22 — twenty-seventh round: a rounded average made a run disagree with itself, and a silent
  replacement got a voice.**

  **The difference in tokens between the two sides was saved rounded to whole tokens.** It is an average,
  and averages are fractional whenever the two sides recorded different numbers of attempts — which is any
  run where one attempt was thrown out. Measured: a run reporting `90.5` saved `+90` and read back as
  `90`, so the figure the run announced and the figure re-derived from its own file disagreed. This file's
  own rule is that those two cannot disagree. Now saved with two places, matching the finest precision
  already used beside it. No fixed number of digits can make them agree exactly; this puts the
  disagreement below a hundredth of a token. The figure printed on screen stays whole, because that is for
  a person reading a table rather than for a later run to re-derive from.

  **A results file that is not a results file at all was replaced without a word.** Confirmed for three
  shapes — a list, a bare string, and something that is not readable at all: the run finished, exited `0`,
  and the file was overwritten.

  **The suggested remedy was to refuse, and that would be a mistake.** Replacing an unreadable file is
  deliberate and was added for a reason recorded at the time: a planted one previously hung the writer
  after the money was spent, and replacing it is how the tool heals. Refusing instead would let anyone
  stop every future run by dropping a broken file into place.

  **What was actually missing was the telling**, so that is what changed. The run now says, before anything
  is spent, that the file cannot be read, that it will be replaced, and that any earlier results in it —
  including for the half this run does not measure — will be lost, while there is still time to take a
  copy. Two situations that look alike stay handled differently on purpose, and the reason is written
  where they part: a file that reads as a results file but holds something unscorable carries real history
  the person can repair, so it stops the run; one that does not read as a results file carries none.

  Two undos, each confirming its tests fail. 1009 tests / 144 suites green, zero warnings; staged, no
  commits.

- **2026-08-22 — twenty-sixth round: the tool was writing a file its own reader rejects, and I caused it.**

  **What happens.** A run keeps whichever half of the results file it did not measure this time, copying it
  forward unchanged — that is how measuring one thing cannot destroy the record of the other. The half
  being copied was never checked. Reproduced: a committed file whose routing entry said `2.5` runs was
  carried straight through a clean run, which exited `0`, and reading the file it produced throws *"test
  't' gives runs as 2.5, which is not a whole number of runs"*. The tool wrote a record its own canonical
  reader refuses.

  **This is mine, from last round.** Making that reader strict was the right call; leaving the producer
  permissive alongside it created the asymmetry. Sixteenth instance of a rule holding in one place and
  being absent from its sibling — the first one this work introduced rather than found.

  **One part of the report is wrong and worth correcting.** It says a later `skillet score` would throw on
  the record. No command reads this file back today — that one reads produced text, not results — so
  nothing currently fails for a user. What is broken is the promise that the score re-derives from the
  committed file at any time, which is why the reader was made strict in the first place.

  **Refused before anything is spent, not at the moment of writing.** Writing happens after the
  measurement: refusing there would mean the money is gone and the results thrown away. The check now sits
  with the other refusals that cost nothing to reach, and uses the reader itself, so the message already
  names the entry and says what to do. Measured: the same run now stops with exit `4` before any
  measurement, and the existing file is left byte-identical for the person to correct.

  **Refused rather than quietly dropped**, which is what the report suggested. Dropping the unreadable half
  loses the committed record of the axis that did not run this time — the very thing carrying it forward
  exists to protect — and would replace a file the person can still repair with one where that history is
  gone.

  **The two lower-confidence notes need nothing, and one was already settled.** The diagnostic cache write
  is deliberately best-effort. The plain repeated-name error from a freshly finished run is deliberate and
  was decided two rounds ago: the names there come either from a check that already refuses repeats before
  spending or from numbering generated in a loop, so a repeat arriving later is this tool's fault and
  saying so is correct. A test pins both classifications side by side so the difference reads as a
  decision.

  One undo, confirming its tests fail. 1006 tests / 144 suites green, zero warnings; staged, no commits.

- **2026-08-22 — twenty-fifth round: two items filed as minor, one of which loses a whole session.**

  **A session file saved with Windows line endings is read as nothing at all.** Reading it splits on a
  single newline character — but in Swift a carriage return followed by a newline is *one* character, so
  that split never matches and the entire file arrives as one piece which is not valid on its own. It does
  not degrade line by line, as the report supposed; it disappears whole. Measured: a two-reply session read
  this way produced no conversation and no counts, against two replies and a full count for the same
  content saved the other way. The automatic grader reads that empty conversation and fails every
  expectation — a measured failure produced by how a file was saved, with nothing saying so. Filed as low
  priority; the consequence is a wrong verdict.

  **A single-line file survives either way**, because trailing blank space is tolerated around a lone
  value. That is why this needed more than one line to reproduce, and why a test of it must use more than
  one.

  **This project already documents the exact trap, one reader over.** The code that stages a skill file
  normalises line endings first and explains why in a comment. The reader of session files did not. Two
  readers of session files, in fact: the second records which model produced a session, and on the same
  input recorded it as unknown. Both now split on any line ending. Three other places split the same way
  and were measured rather than assumed: the one reading skill files is already normalised further up, and
  the other two read output this tool produced itself, which is always plain.

  **A test whose every attempt was thrown out was recorded as having failed.** An attempt is disqualified
  when a skill was used in a run meant to be without one; it is never graded. When every attempt goes that
  way, the per-test row said the test scored zero — indistinguishable from a test that ran and got
  everything wrong, and the most flattering possible reading of the skill being tested. The run's summary
  block was given this rule two rounds ago and the rows underneath it were missed: the fifteenth time in
  this feature that a rule has held in one place and been absent from its sibling. The counts stay, since
  they are facts — nothing ran, nothing passed, this many attempts were thrown out — and only the two
  derived verdicts are withheld.

  Two undos, each confirming its test fails. 1003 tests / 143 suites green, zero warnings; staged, no
  commits.

- **2026-08-22 — twenty-fourth round: the reported fault does not happen; the guarantee it assumed is now
  stated and tested anyway.**

  **The claim, and the measurement.** Differences between two runs are written into the results file as
  short pieces of text like `+0.50`, and read back with a plain text-to-number conversion that only
  understands a dot. The report was that these are written using the machine's regional conventions, so a
  comma-decimal machine would write `+0,50` — which reads back as nothing — and a four-figure count would
  be written `+1,100`, which reads back as `1`. Forcing the machine's region to a comma-decimal one and
  running the code's own calls produced `+0.50`, `+1000` and `+12345.6`. This way of formatting applies no
  regional conventions unless a setting is handed to it, which is documented rather than lucky. The probes
  in the report all handed one in, so they showed what that form does and never exercised the one in use.

  **The number-writing path had a real bug of this exact kind once, in a different place, and it is
  fixed.** Encoding numbers into a file — not formatting text — once used the machine's decimal mark.
  Tested here under a forced comma-decimal region: clean, both writing and reading.

  **Named explicitly anyway, and this is the part worth keeping.** A mainstream ecosystem ships an
  automated rule requiring the neutral setting to be named even where the default is already correct, on
  the grounds that it makes the guarantee visible to whoever reads the call. Two separate reviews of this
  file have now read that call and concluded the opposite, which is the cost of leaving it implied.

  **The test is the durable part, and the values in it are the point.** Every existing test of that block
  uses figures under a thousand, which look identical whether regional conventions are applied or not — so
  they pass on any machine and would keep passing if this broke, which is exactly why the report could not
  be settled by running the suite. The new one uses a difference of `1100`, because applying regional
  conventions inserts a grouping mark even in English. Undoing the fix reproduces the reported failure
  precisely: `+1,100` written, and the figure no longer readable.

  **Numbers printed to the terminal are pinned too, for a different reason.** That output promises nothing
  and could follow the reader's region — but the one well-known command-line tool that did localise
  numeric output withdrew it after complaints from users in exactly those regions, whose own data used
  dots. This table is also pasted into notes and compared between people, and its columns are aligned by
  character count.

  **Two smaller claims, measured and left alone.** The conversion used to read those figures back is not
  region-aware at all, so there is nothing to pin on that side. And a token count sent as `100.0` or `1e2`
  converts to `100`; only a genuinely fractional one fails, and that makes the whole session report no
  counts rather than a wrong one, which is the existing designed behaviour.

  1000 tests / 143 suites green, zero warnings; staged, no commits.

- **2026-08-22 — twenty-third round: an end-to-end coverage audit, and one real class of gap in it.**

  **Every command is driven through the built program** — 302 invocations across the integration suite,
  each of the ten commands covered. There is no command without end-to-end coverage, and three paid checks
  exist behind an environment switch so a free run never spends.

  **The gap was not a command, it was the seams between them.** This tool works as a loop, and each step
  ends by printing the exact command to run next. Every test checked that the right *text* was printed.
  None ran it. That is the same shape as checking a switch is accepted rather than checking it does
  anything — the fault this review series has caught repeatedly inside single commands, sitting unnoticed
  at the level of the workflow.

  Two instances, both verified by hand first and both found working, so these are test gaps rather than
  defects:

  - **Proving an edit → applying it.** The proving step prints the command that lands what it proved. Run
    verbatim, it works, and the subset form — where only some edits were proven and the command gains a
    list of numbers — lands only those. Both are now tests, and the subset one matters most because that
    command is assembled from parts rather than fixed.
  - **Clustering findings → drafting from one.** The drafting step was only ever given finding files
    written by hand in the tests themselves, so nothing checked that a file the clustering step *actually
    produces* can be used: not its name, not its contents, not the identifier used to ask for it. Run for
    real, the chain works. It is now one test that clusters, takes the command that was printed, and runs
    it. Breaking the printed identifier by one word fails it.

  **What is still not covered end to end, stated rather than left to be discovered.** A run without the
  skill counts no tokens offline, so the token difference between the two runs never appears in a file a
  test generates — its arithmetic is covered by constructed inputs instead. The offline stand-in has never
  been checked against a real session, which is what `F74` (record a replay file from a live run) is for.
  And the checks that run in the instant before a record is written cannot be reached while the check at
  the start of the command is in place; they are verified by removing that one, which is recorded at each
  of them.

  997 tests / 142 suites green, zero warnings; staged, no commits.

- **2026-08-22 — twenty-second round: two findings, both real, both the same shape as work already done
  one place over.**

  **A saved file naming one routing check twice inflated its own score.** The check that asks whether a
  model reaches for the right skill is a third arm alongside the with-skill and without-skill ones. Those
  two are refused when a saved file names one test twice; this one was not. Measured: a file naming one
  routing check twice produced two rows for one check and a score of `0.5` — a half-success invented from a
  single check recorded once as passing and once as failing, with the count underneath the figure being
  two where one test exists. The same rule was given to this arm on the live path two rounds ago and its
  saved-file twin was missed. That is the **thirteenth** time in this feature a rule has held in one place
  and been absent from its sibling.

  **A run writes two record files into one folder, and only one of them was checked in the instant before
  writing.** The check at the start of the command runs before a measurement lasting minutes, which is a
  long and predictable window in which to plant a link that redirects a write outside the project; the
  first record file is re-checked immediately before its write for exactly that reason, and the second was
  not. Both now are.

  **Verifying that second one honestly took an extra step, and the first attempt was not a check at all.**
  A link planted before the command starts is caught by the start-of-command check, so the test passes with
  or without the fix — undoing the fix changed nothing, which the run showed plainly. The guard was
  verified the way its neighbour was in an earlier round: with the start-of-command check removed, the case
  is still refused; with both removed, the run finishes and writes straight through the link. The test
  keeps the outcome that holds either way and now says in its own words what it does not cover, rather
  than looking like proof it is not.

  993 tests / 140 suites green, zero warnings; staged, no commits.

- **2026-08-22 — twenty-first round: six findings, four real, and the two most severe were both wrong.**

  **The one marked most severe was already correct.** The claim was that every turn in a parsed session is
  stamped with the session's end time, contradicting a test that expects each to carry its own. The
  variable holding the stamp is reassigned on every line as the file is walked, and a turn is stamped at
  the moment it is added — so it gets *its own* line's time. The test cited is named "Each turn carries ITS
  OWN line timestamp, not the session's final one" and it passes; I ran it. It reads as a bug because the
  variable is called `endedAt` while doing double duty as "the line I am on". That has now been reported
  twice, so the reason is written at the line rather than left to be re-derived.

  **The second was a format break that never happened.** The claim was that per-attempt elapsed time and
  token counts had been removed from the attempt rows of the saved results file, breaking a frozen format.
  Checked against the last commit: those rows have only pass/fail counts and have never held anything
  else. The fixture cited is an *input* to a round-trip test — it feeds a file produced by the separate
  viewer tool and checks that reading and re-writing preserves every field, including ones this tool does
  not produce. It proves the reader is faithful, not that the writer emits them. No version bump is owed.

  **A count that cannot be a count now stops the file being scored.** Each entry in a saved results file
  says how many times a test ran and how many runs passed. An entry saying `2.5`, or a word, was passed
  over in silence and the score worked out from what remained — a confident figure covering fewer tests
  than the file lists, with nothing marking it. Quietly shrinking what a score covers can only push the
  figure up, which is the practice trustworthy-benchmark guidance names as untrustworthy, and this file is
  the long-lived report-driving case where strict checking is the standard answer. `2.0` and `2` are the
  same number and both still work; an entry with no count at all is still passed over, which is a separate
  question recorded rather than changed quietly.

  **Token counts are now read only from the model's own replies.** Both kinds of line were being read while
  the note beside the code said otherwise. Measured across every session on this machine — 24,598 lines of
  ten kinds — only model replies carry a count block, 11,246 of them. And tokens spent on a result handed
  back from a tool are already inside the *next* reply's input figure, so the replies are the whole of the
  accounting rather than part of it: a count found anywhere else could only be the same tokens counted
  twice.

  **Two smaller ones.** A failed version-control step quoted only the first two words of the command, so
  the command shown was one nobody had run and could not be repeated. And asking to keep the throwaway
  copy, then having the run fail, left the copy behind without saying where — the one case where you most
  want to open it was the one where you could not find it.

  **On testing the quoted command.** It cannot be reached through ordinary use, and no test target can
  reach that code directly. Rather than assert it conditionally — which would pass while checking nothing,
  a trap caught and discarded once already in this work — the test points the setting that names the
  version-control program at a stand-in that behaves normally except for the one operation, which drives
  the real path and fails cleanly.

  Four undos, each confirming its test fails. 990 tests / 140 suites green, zero warnings; staged, no
  commits.

- **2026-08-22 — twentieth round: four findings, all four real, and an hour lost to a self-inflicted
  false trail.**

  **A block of figures carried forward from a saved file could be written back under the other run's
  name.** A results file holds one block per run. When a later run measures only the "does the model reach
  for this skill" check, the earlier figures are carried through. Which block was picked up and which name
  it went back under were decided in two separate places from two different rules, so a file holding both
  names had its single-run figures written back under the comparison name — the label saying one thing and
  the numbers being the other's, and the block that name belonged to dropped. Reproduced by building such
  a file: the comparison block read `0.11`, which was the single-run block's value. Both are now decided
  at the same moment, so they cannot disagree. skillet itself never writes both names, so this needs a
  file merged or edited by hand — pinned because the mismatch is silent and the file is what later runs
  read.

  **A number was written into the saved file and read back by nothing.** The token difference between the
  two runs of a comparison was recorded, while the line that would show it printed a dash whatever had
  happened — a figure the record promised that no reader could obtain. It is now carried on the comparison,
  read back when the file is re-read, and shown. A dash now means neither side counted anything, which is
  what it should have meant all along.

  **The switch that lets a known-bad version of the model program through took any value at all.** The
  message tells you to set it to `1`; setting it to `0` — the natural way to write "no, leave the check
  on" — turned the check off. It now takes exactly the advertised word. Deliberately stricter than the
  switch enabling the hidden test options, which treats any non-empty value as yes because a test harness
  cannot remove a variable, only blank it: turning off a safety check is a different kind of decision.

  **Two parts were deciding which program to run from two different views of the environment.** The part
  that finds the program was built with its own view whatever the rest was given, so a caller naming a
  program through a supplied variable was ignored and the machine's real environment consulted instead.
  They now share one. What is handed to the *program* is deliberately not that map and is documented as
  such: a caller supplying one variable would otherwise leave the program with only that one and no way to
  find anything.

  **The false trail, recorded because it cost more than the findings did.** The full suite appeared to
  hang. It had not: the first run was still holding the build lock in the background, so every check run
  afterwards sat waiting and produced no output. Three "isolations" were run against that, and each was
  worthless for its own separate reason — one corrupted a source file with a careless text edit, one
  failed to compile and reported success anyway, and one used a stash that also cleared the staged state
  for those paths. The lesson is the one already written down about this exact symptom: no output is not
  the same as still working, and the first thing to check is what is already running. Nothing was lost —
  the working tree was verified intact and re-staged — but a check whose result cannot be trusted is worse
  than no check, because it is acted on.

  Five undos, each confirming its test fails. 983 tests / 137 suites green, zero warnings; staged, no
  commits.

- **2026-08-22 — nineteenth round: a security sweep, eight items, four changed and one of them let a
  mistyped filename read as a proven edit.**

  **A file that could not be read made an edit look proven.** The offline switch takes a file of recorded
  answers so tests can grade without a model. A file that was named and could not be used — missing,
  misspelled, outside the project, or not valid — was quietly treated as an empty set of answers. With no
  recorded answer for any check, every check fails, in *both* of the two measurements the proving command
  compares. Nothing then scores lower than anything else, so the edit is declared proven and the line
  telling you to apply it prints underneath. Reproduced end to end from another folder: `0/1 → 0/1`,
  "no test scored lower", "→ land it". Such a file is now refused, saying which one and why.

  **It was also being looked for in the wrong place.** A relative name was taken as relative to whatever
  folder the command was invoked from, while the draft file the same command reads is taken as relative to
  the project. So running from elsewhere looked somewhere else, found nothing, and — before the refusal —
  said nothing. Both now mean the same thing. Verified by running from `/tmp` against a project elsewhere.

  **The verdict that fault produced is reachable without it, and now says what it rests on.** The rule for
  approving an edit is "no test scored lower", which is satisfied trivially when every test fails on both
  sides: nothing can score lower than nothing. A skill whose tests all fail before and after an edit gets
  the same approval and the same offer to apply it. The verdict is unchanged — nothing did get worse, and
  refusing on other grounds is not this feature's decision to make — but the line above the suggestion now
  says that not one check passed in either measurement, so there is no evidence the edit helps.

  **A link where a real file belongs, one level below where that was already checked.** The scratch folder
  gets a small file telling version control to ignore it, so a run's raw output is never accidentally
  committed. The check before writing it asked whether a file exists there, which follows a link and
  answers about its destination — so a link pointing at nothing answered "no". Measured on this machine,
  the write then *replaces* the link rather than following it, so the outcome here was already safe; that
  is undocumented, differs between systems, and this project supports one it is not tested on, which is
  the same conclusion an earlier round reached about a different write. The folder was checked this way
  and the file inside it was not.

  **Recording what a run produced is now bounded by how many files there are.** A model given a folder can
  create as many as it likes, and the listing was built whole in memory before anything was filtered — so
  a runaway one could exhaust memory during the step meant to record what it did. Each file was already
  bounded by size; the number of them was not.

  **Three items are accepted rather than changed, each already a recorded decision.** The hidden test
  switches ship in the released program on purpose, so the suite exercises the built program — written up
  in the contributor guide with the shape of the stricter alternative. Naming the programs this tool runs,
  through settings or the environment, is the user choosing their own tools and is part of the stated
  trust assumptions. A folder-name comparison used only to shorten paths in messages crosses no boundary;
  the real confinement is done elsewhere. One residual window is noted and not closed: a regular file
  swapped for a link between the check and the copy during staging, which needs local write access to the
  project in that instant.

  Five undos, each confirming its test fails. 969 tests / 132 suites green, zero warnings; staged, no
  commits.

- **2026-08-22 — eighteenth round: one real defect, and one finding answered by disagreeing with its fix.**

  **The check that asks whether a model reaches for the right skill recorded a score of zero when it had
  never run.** That check hands a model a shelf of skills and a prompt and asks which it reaches for. A
  score of zero there reads as "we asked, and the skill was never reached for" — the most damning possible
  reading of the skill being tested — rather than "we never asked". Reproduced by building the case
  directly. The two other summary blocks in the same file were given exactly this rule a round earlier and
  this one was missed, which is the **twelfth** time in this feature that a rule has lived in one place and
  been absent from its sibling. Fixed, with cases separating the three situations that were being
  conflated: never tried records nothing, tried and not reached for records a real zero, tried and reached
  for records that.

  **The other finding is accurate about the facts and wrong about the remedy, and checking the message
  settled it.** A repeated test name in a freshly-finished run travels as a plain repeat and is classified
  by the command layer as a defect in this tool, exit code `70`, rather than as a bad file at exit `4`
  like the saved-file path. Suggested fix: convert it to a bad-file report. What a person would actually
  see today: *"internal error — this is a defect in skillet, not a problem with your project: two entries
  are both named 'e1'"*, with a link to report it.

  That wording is correct, and the suggested fix would make it wrong. The names a finished run reports come
  either from a check that already refuses repeats before any money is spent — naming the file and how to
  fix it — or from numbering generated in a loop. So a repeat arriving at the later point means one of
  those two failed, which is this tool's fault; blaming the project's file would send someone to inspect
  something that had already been checked and passed. Left as it is, with the reasoning written at the
  site and, more usefully, a test putting the two classifications side by side so the difference reads as
  a decision rather than as one path having been forgotten.

  Two undos, each confirming its test fails. 961 tests / 129 suites green, zero warnings; staged, no
  commits.

- **2026-08-21 — seventeenth round: five findings, all five real, and one of them could have changed a
  verdict.**

  **A reply could vanish from the conversation because a number beside it was unreadable.** Each reply a
  model sends carries a count of what it read and wrote. Refusing to count a half-reported one was right;
  the way it was written also skipped past the code that adds the reply to the transcript, so the reply
  disappeared. The automatic grader reads that transcript, so losing the model's last reply could turn a
  pass into a failure with nothing anywhere recording that a line had gone missing. Only the counting is
  abandoned now. This was the one finding of the five that could change a result today.

  **What a failed attempt cost was being thrown away.** Grading happens after the model has replied and
  its reply has been read, so an attempt whose grading fails has real measured counts in hand. Two error
  paths discarded them, on a comment claiming they are reached before any reply exists — true of one of
  them, false of the other. The totals a run reports are built from what those paths return, so that
  spending vanished from every figure while the file kept beside the attempt still had it. Providers
  charge for what a request consumed whether or not it succeeded, and audits of enterprise billing find a
  failed attempt is precisely where spending goes unnoticed; discarding it would be the same flattering
  omission as the invented zeros removed earlier, pointed the other way.

  **Content from outside the project could be copied in and shown to the model.** When measuring whether a
  model reaches for the right skill, each candidate skill's opening description is copied into a scratch
  folder. The reader used refuses a shortcut — a file entry that silently points elsewhere — only at the
  final step of a path, so a shortcut planted on a folder along the way was followed. The comment claimed
  it "refuses a link" without that qualification, which claimed more than it did; the gap is catalogued
  as `CWE-59` ("link following"). This runs once per attempt, so a start-up check cannot keep it true — a
  folder can be swapped in between. The folder every skill lives under is now passed down so the whole
  path is proved on every attempt. Undoing it stages the smuggled content and the test says so, which is
  what makes this a demonstrated hole rather than a theoretical one.

  **Two smaller ones.** The offline stand-in named only the first skill handed to a session while the real
  thing it stands in for takes as many as it is given — no caller passes more than one today, so a second
  would have gone unreported with nothing saying so. And the helper that totals token counts read the
  first item of its list, which stops the program if the list is empty; it now answers "nothing", because
  an empty list is the ordinary state of every run made without a real model rather than a mistake, and
  because the obvious repair — starting the sum at zero — would answer with a row of zeros, the invented
  measurement removed two rounds ago.

  **A note on how that last one was checked.** Restoring the original mistake makes the test process
  crash rather than fail, which hung a run and left a source file mid-revert until it was restored. The
  guarantee worth pinning is not "it does not crash" but "it does not answer with zeros", so it was
  checked against that repair instead — which fails cleanly and is the mistake the guidance actually warns
  about. Five undos in total, each confirming its test fails. 956 tests / 127 suites green, zero warnings;
  staged, no commits.

- **2026-08-21 — sixteenth round: the safety net renamed the skill it was protecting, and my own test
  hid it by using the guilty name.**

  **The net dropped everything except which run it was.** When the offline stand-in cannot write out its
  answer it falls back to a minimal one. That fallback carried only whether this was the run with the
  skill or without it, so the list of skills the answer reached for was lost — and a lost list used to
  mean "keep whatever the canned session claims", which is a skill called `demo`. Measured: an answer
  reaching for `tidy-notes`, carrying version marker `v2` and its own token counts, came back through the
  net as `["demo"]` with no marker and no counts. A net that renames the skill under test is worse than
  no net, because it reads as cover.

  **My own test could not catch it, because it used `demo` as the example name.** Two rounds ago this
  fallback was pulled out into a named function specifically so it could be tested, and then tested with
  the one value that makes a preserved answer and a discarded one look identical — the same magic name
  this whole sequence of rounds has been removing. Every name in those tests is now deliberately
  something else, and one of them contains a quotation mark, since the net now assembles text rather than
  writing it by hand.

  **Fixed in two independent layers, which is why the second one matters.** The net now carries the arm,
  the skills reached for, and the version marker, assembled by a serializer so a skill name containing a
  quotation mark cannot break the result. Separately, an answer can no longer stay silent about which
  skills it reached for: that field is required, so text lacking it fails to read at all — and unreadable
  text was already served as a session claiming nothing. Undoing the first layer proves the second: the
  answer comes back claiming *nothing* rather than claiming `demo`, which is the safe direction.

  This is the fourth place the canned name leaked through a different door — the routing measurement, the
  no-skill-named path, the version marker, and now the give-up path. The last of the silent defaults is
  gone: the answer always states what it reached for, so the canned session's own list is never consulted.

  Two undos, each confirming its test fails: the net emitting only the arm, and a silent answer inheriting
  the canned skill. 949 tests / 125 suites green, zero warnings; staged, no commits.

- **2026-08-21 — fifteenth round: four findings, two real defects, one note, and one change that cannot
  be proven by test.**

  **A session could answer as one skill while reporting a different one.** The offline stand-in can be
  given a list of skills to consider, or simply let loose on whatever is staged. Both are the session
  choosing for itself, so both should read the staged declarations — but only the first did. Measured:
  a staged skill called `tidy-notes` answered with its own version marker `v2` and its own stated token
  counts, and reported that a skill called `demo` had been reached for. No such skill was staged. That is
  the fault removed from the routing path a round earlier, left intact in its sibling.

  The cause was structural: three readers — the version marker, the token counts, and which skill was
  reached for — each worked out for themselves which staged skills a session could draw on, and the third
  simply omitted the no-skill-named case. They now resolve it in one place, so a fourth reader cannot
  repeat it, and a test asserts that all three name the same skill.

  **A run whose every attempt was thrown out recorded a score of zero.** An attempt is disqualified when a
  skill was used in the run that was supposed to be without it — it measures nothing and is never graded.
  When every attempt goes that way the run measured nothing at all, and a score of zero there is
  indistinguishable from a run that genuinely got everything wrong. It is also the most flattering
  possible reading of the skill being tested: *without it, nothing worked*. The command does refuse such a
  comparison — but the results file is written before the refusal and outlives it, so anything reading
  the file later saw a fabricated zero with nothing marking it as one.

  **The test covering that case asserted the bug.** Its name is "an average of nothing is not a
  measurement" and its body required the score to be written anyway. Corrected, with the reason recorded
  at the line, and joined by cases separating the three situations that were being conflated: nothing
  graded records no score; graded and failed everything records a real zero; some attempts thrown out and
  others graded is scored on the ones that were graded.

  **One difference-block observation is accurate and deliberate.** Elapsed time is signed text in the
  difference block and an object of figures in each run's own block. That holds for every field: a
  difference is one signed quantity, a run's own measurement is a spread. The rule is now stated where
  the block is built, because it reads as an inconsistency until someone tells you it is a rule.

  **One change is an alignment that no test can pin, and saying so matters more than the change.** The two
  commands with hidden test-only switches checked them differently — one switch at a time, or as a group
  naming whichever came first. Both refuse identically today, because one environment variable covers
  every switch, so undoing the alignment breaks nothing and the revert-check does not bite. It was still
  made, because the grouped form names only one of the switches actually used and becomes a real hole the
  moment two switches are gated differently. The tests added alongside pin the behaviour both forms share
  — every switch refused by name, in both commands — which is worth having and is *not* a check on this
  change. Recorded rather than presented as verified.

  Two undos, each confirming its test fails: the unnamed session keeping the canned answer, and a run that
  measured nothing recording a score. 947 tests / 125 suites green, zero warnings; staged, no commits.

- **2026-08-21 — fourteenth round: one real off-by-one, and the test that was written to agree with it.**

  **A test whose instruction was one long word lost its readable name.** A test with no name of its own
  gets one built from the opening words of its instruction — lower-cased, joined by hyphens, cut on a word
  boundary — followed by a short fingerprint of the full text so two tests starting alike stay apart. The
  cut charged for a joining hyphen before there was anything to join to, so the limit meant two different
  things: several words could reach the full length of 28, while a single opening word was cut at 27.
  Measured across the boundary rather than argued: 26 and 27 characters kept their name, 28 was thrown
  away whole and named `unnamed-0ce618d1`, and two words totalling exactly 28 were kept — the same length,
  opposite outcomes, decided by how many spaces were in it. Nothing was ever mis-identified, since the
  fingerprint still distinguishes them; what was lost is the ability to read a results table.

  **The existing test could not have caught it, because it rebuilt the rule and compared the rule to
  itself.** It re-implemented the splitting, joining and length limit inline and asserted the real one
  matched — so the same off-by-one sat in both copies and they agreed. That test is about one thing,
  whether the name changes on a machine set to a different language, and it now checks only that: the
  readable part is compared against the same text lower-cased with no language, which is the actual
  question, with no second copy of the rule to drift alongside the first. The length rule is pinned
  separately by cases that name the boundary directly and by a property holding across every length from
  1 to 40, so the numbers cannot drift away from the rule they illustrate.

  **The blocking question about spending was reviewed and deliberately left alone.** Waiting for a typed
  answer stops the thread it runs on, and blocking a thread that concurrent work shares can leave that
  work with nowhere to run. Checked rather than assumed: neither paid command starts any concurrent work
  — no task group, no parallel trials, nothing detached — and the question is asked before the first
  subprocess is launched, so there is nothing to starve. Isolating it would add machinery for a problem
  that cannot occur. The site now records that, and records what would end it: running trials
  concurrently, or asking anything else once measurement is under way.

  One undo, confirming its test fails: charging the joining hyphen again drops the exactly-at-the-limit
  word and the length test says so, while the language test — correctly — stays green, because it is no
  longer entangled with a rule it was never about. 939 tests / 123 suites green, zero warnings; staged,
  no commits.

- **2026-08-21 — thirteenth round: four findings, all four real, and the biggest one measured before it
  was believed.**

  **A run could report more tests than it ran.** Every comparison this tool makes joins results by test
  name, so two results carrying one name has no defined meaning. The saved-file path was corrected two
  rounds ago to refuse that on both sides; the live path checked only the side it looks names up in, on
  the reasoning that the other is merely walked in order. Measured rather than argued: three results for
  two distinct tests produced a report claiming three tests — one passed, one failed, the same name twice
  as though independent — and a comparison that paired the *same* without-skill result against both
  copies, so one measurement counted twice in the average behind a table showing two rows. Every arm now
  carries the guarantee, including the routing arm, which was unchecked for the same reason.

  It refuses with the plain repeat rather than the bad-file report the saved-file path uses, and that
  difference is deliberate: reading a file that may be old or hand-edited puts the file at fault and
  names it, whereas here the results were handed in by the caller and naming a file would send a reader
  to look at something that is fine.

  **The comparison now takes both arms as sets that cannot hold a repeat**, rather than checking for one.
  There is no branch left to forget, and the order a run measured its tests in is still preserved.

  **A half-reported token count was being completed with invented zeros.** The reply-reading code filled
  a missing count with zero, which turns a partly-reported reply into a confident under-count — the same
  invented number removed last round, arriving by a different door. Worse at the session level: dropping
  one unreadable reply and keeping the rest makes the total short while looking whole, and nothing about
  it reads as wrong. It is now all four counts or the session reports none. Every one of the **10,833**
  replies across the sessions on this machine carries all four, so this cannot be reached today — which
  is the reason to enforce it rather than describe it, since an invariant the code does not check is
  prose and the next change to what a provider sends decides whether it was ever true.

  **The same four numbers were called different things in the two files that carry them.** A run leaves a
  diagnostic file per attempt and a results file per run, and someone checking a suspicious figure reads
  them side by side — one said `cache_read`, the other `input_cache_read_tokens`. Both now take their
  names from one place, a test compares the two rather than trusting them to stay aligned, and both state
  the roll-up so a reader never has to add up four numbers whose correct summing is the exact thing that
  trips people up. The roll-up is written but never read back: a file whose stated roll-up disagrees with
  its own parts is resolved in favour of the parts.

  A trap worth recording: the names are spelled in the form the encoder converts *from*, not the form it
  writes. Both files are written with automatic camel-to-underscore conversion and read with the reverse,
  so a name written already in underscore form encodes correctly and then fails to decode.

  **One field name carried two units.** A run's token block is a total across every attempt; the
  difference between two runs is a per-attempt mean, because totals move with how many attempts each run
  recorded and the without-skill run records fewer whenever a trial is thrown out. Both were called
  `total_tokens`. The neighbouring pass-rate and elapsed-time differences need no such qualifier — each
  sits beside a per-run block that is plainly per-attempt — so the difference is now
  `total_tokens_per_attempt`, which is the narrowest fix that removes the ambiguity without making its
  neighbours inconsistent.

  Six undos, each confirming its test fails: the with-skill arm unchecked, the routing arm unchecked, a
  missing count filled with zero, the two files drifting to different names, a stated roll-up believed
  instead of recomputed, and the difference losing its unit. 934 tests / 122 suites green, zero warnings;
  staged, no commits.

- **2026-08-21 — twelfth round: stop inventing a token count, then actually count.**

  **The made-up number is gone.** A *token* is the unit a model charges and reasons in. The saved results
  file wrote a zero token count on every run and a zero difference beside them, for a quantity nothing
  measured — three lines below a comment stating that a key appears only when the quantity *was*
  measured, and the only field in the file breaking that rule. Elapsed time has always followed it by
  being left out when no attempt was timed. Absence is now how the file says "not counted", in one way
  rather than two.

  **Then the counting, because the numbers turned out to be already in hand.** Every reply a session
  reports carries what it read and wrote. Those lines were already being read for other reasons and the
  counts discarded unread. They are now read and totalled across the session, carried on each attempt
  beside its elapsed time, and written per run.

  **The naming is the load-bearing decision, and it exists because of a real, filed, roughly-doubling
  bug.** Two published conventions use the name `input_tokens` for opposite quantities: this provider
  means the input that was *not* served from its cache, and the industry telemetry convention means the
  whole input regardless. A system that maps one onto the other and then adds the cache counts on top
  reports about twice the truth — Langfuse issue 12306, whose reported numbers were 5 fresh tokens,
  128,955 read from cache and 1,253 written to it, and which closed as the *consumer's* fault because
  both producers were doing exactly what they documented. So nothing here is called `input_tokens`. The
  file publishes `total_tokens` alongside `input_uncached_tokens`, `input_cache_read_tokens`,
  `input_cache_write_tokens` and `output_tokens`. A test asserts no field by the ambiguous name exists,
  and undoing the fix reproduced the filed symptom precisely: 260,521 where the truth is 130,313.

  **Only the roll-up gets a difference between the two runs.** How much a model read is stable whether
  or not the provider's cache happened to be warm, so a difference in it is attributable to the skill.
  The cached-versus-fresh split moves on timing luck, so publishing *its* difference under a heading
  reading "what the skill did" would state luck as an effect. It is reported per run, where warmth is a
  fact about that run. The difference appears only when both runs counted — undoing that guard published
  `+650`, one run's entire usage presented as a difference.

  **No money figure, deliberately.** Converting counts to a bill needs per-token-type prices: a cache
  read costs a fraction of fresh input and a cache write 1.25× or 2× it, so one price per token is wrong
  in both directions. The counts ship in the shape that makes the sum computable by whoever has prices.
  `F60` is updated to say which half landed and which did not.

  **Offline, counts come from the fixture or not at all**, the same rule adopted for routing a round
  earlier: a skill's file states four numbers or the run counts nothing, and a half-written statement
  counts as no statement. The run *without* the skill has no skill file to read, so offline it counts
  nothing — which means the end-to-end offline path exercises "one run counted, difference therefore
  absent", and the difference arithmetic is covered by constructed inputs exactly as elapsed time's
  always has been. Stated here rather than discovered later.

  Five undos, each confirming its test fails: the zeros restored, the cache counts added onto the narrow
  field, the substitute inventing counts, the difference published from one side, and the roll-up no
  longer being the sum of its parts. 923 tests / 120 suites green, zero warnings; staged, no commits.

- **2026-08-21 — eleventh review round: seven items, four real, one reported backwards, two still open.**

  **Two give-up paths in the offline stand-in would have swapped the two things being compared.** The
  stand-in replaces the model so tests cost nothing; it answers either as a run that had the skill or as
  one deliberately without it, and a separate check throws out any without-skill measurement whose answer
  claims the skill was used. Both give-up paths returned the *with-skill* answer regardless of what they
  were handed — so a without-skill answer that failed to write, or failed to read back, came back
  claiming the skill had fired, and the run would report a broken measurement where there was only a
  parsing problem. Neither is reachable with today's fields, which is the reason to pin them rather than
  to shrug: an untested safety net reads as cover, and the next field added decides whether it was ever
  real. The write-side path is now a named function precisely so a test can call it, since reaching it
  through ordinary use would require making the change it guards against.

  **A repeated test name in a saved results file now reads as a bad file rather than a crash.** Reading
  a saved file is not the same as building results in memory — that file may be old, hand-edited, or
  merged from a branch. The refusal travelled as a bare "two entries share a name", which the command
  layer could only classify as an internal fault: exit 70, the tool blamed for the file's problem, and no
  route to fixing it. It now names the file, the repeated name, and what to do. Both places that read
  such a file were checked separately by undoing one at a time — the other's test kept passing, so
  neither is riding on the other.

  **A set of results with no repeated name is now declared safe to hand between concurrent tasks.**
  Nothing runs in that test; it compiles only if the declaration exists, and deleting the declaration
  breaks the build. Without it the first place that measures two things at once fails to compile with no
  hint why.

  **What a script reads now carries what a person is shown.** Asking to keep the throwaway copy printed
  where it went and told a script nothing, so anything automated had to guess at a folder name containing
  a random identifier. The command that applies a proven edit was printed and likewise absent, so a script
  had to rebuild it from its parts — and one wrong switch there applies edits nothing measured. Both are
  in the payload now; the applying command appears only beside a verdict that held up, for the same
  reason it is not printed beside one that did not.

  **A run with one arm summarised fewer fields than a run with two** — the same "present here, quietly
  missing there" shape this feature has now hit nine times. How long trials took is measured either way
  and recorded in the per-trial rows either way, but the aggregate dropped it whenever there was no
  second arm to compare against, so a chart of how long a suite takes drew from comparison runs and got
  nothing from plain ones. One builder now produces every arm block, and the test asserts the two have
  the same fields rather than naming one — so a field cannot go missing from a sibling again.

  **One item is reported backwards.** The claim is that the difference block's token entry should become
  a statistics object, to match the per-arm blocks. Generating a real record shows the opposite: that
  block is uniformly signed text — `"+1.00"`, `"+0.0"`, `"+0"` — while per-arm blocks are uniformly
  statistics objects. The token entry already follows its block's rule; changing it alone would make it
  the only exception. There *is* a defect one line above it, and a larger one: the block's own comment
  says a key appears only when the quantity was measured, and then writes a zero token difference for a
  quantity nothing measures — the fabricated-zero-versus-omit question that metrics formats settle by
  omitting. Raised as its own decision rather than changed.

  **The routing measurement no longer passes on a coincidence.** One thing this tool measures is whether
  a model, given a prompt and a shelf of skills, reaches for the right one. Offline, the stand-in reported
  that a skill named `demo` had been reached for — always — so the measurement passed when the skill under
  test happened to carry that name and failed otherwise, on setups identical in every other way.
  Reproduced: `demo` passes, `tidy-notes` fails. Six of the ten command-level tests of that measurement,
  and the lower-level one, were resting on the name they had picked; the lower-level one said so in a
  comment and asserted on it anyway.

  Baking an answer into a stand-in is defensible only when it serves a single test — shared across many it
  is how a suite goes green for a reason nobody wrote down. The answer now comes from the skill's own
  file, a `replay-fires: true` line read the same guarded way as the line that tells two versions of a
  skill apart. **Silence reaches for nothing**: a file that declares nothing is not reached for, because
  reaching for nothing is a real outcome and a silent default is how the original fault got in.

  **The line has to sit inside the frontmatter, and finding out why was the useful part.** This
  measurement stages each skill as its opening fence with the body withheld — deliberately, since the
  question is whether a short description alone is enough for a model to reach for the skill. My first
  attempt put the declaration in the body, where staging strips it, and every skill would have reached
  for nothing. The test that catches it is the one that drives the real staging chain; it is now proven to
  catch it, by moving the line back into the body and watching it fail.

  This does not make the offline measurement faithful to a real model, and the note now at the switch says
  so: what it checks is that the shelf is assembled, the reached-for skill is read back, pass and fail are
  computed from it, and the records merge. Making the stand-in resemble a real session needs a check run
  against both, which is the recorded-from-live work already tracked as `F74` and now cross-referenced
  there. An earlier attempt at this — making the stand-in reach for whichever skill was under test — was
  reverted, because it destroyed the ability to test offline that a session went to a *different* skill
  than the one being measured. Taking the answer from the file keeps that: the fixture says `demo` reaches,
  so `demo` still shows up as where the routing went when another skill is the one under test.

  **A test that nothing ran was quietly counted as a test that scored the same.** Reported as a display
  nuisance — a repeat count printing as zero beside rows that clearly ran — and reproducing it showed a
  second, worse fault the report had not mentioned. Rendering the case directly gives:

      real        0/3   3/3   +1.00 ▲
      never-ran   0/0   0/0   —
      average change   +0.50 ± 0.50  (observed k=0)

  The one genuine measurement moved a whole unit; a test that ran on neither side contributed a
  difference of exactly zero — not because it was unchanged but because nothing asked it — and halved the
  headline while inventing the spread around it. The uncertainty figure is an artefact of averaging a
  measurement with a non-measurement.

  **Two published rules pull opposite ways here, and both are right about different numbers.** Benchmark
  reporting says a task that crashed must count as zero rather than be dropped, or scores inflate by
  discarding inconvenient results. Metrics reporting says "no data" and "zero" mean different things and
  must not be shown as one. They reconcile because two quantities are involved: whether the edit is
  refused, and what the summary claims. The refusal is decided test by test — anything scoring lower
  blocks — and is untouched, so removing a passing test still shows its drop and still blocks. The
  average is now taken over tests that ran, and a test that ran on *either* side counts, because a test
  present before an edit and gone after it is a real and bad difference rather than an absence.

  **Reported as needing the count excluded; it is kept instead.** Computing it over the tests that ran
  would have made a report that measured nothing print a confident repeat count — hiding the problem in
  the name of tidying it. The zero stays and the summary now says what it means, in the words the
  measuring command already uses when its own headline would rest on nothing: `unmeasurable (k=0)`. That
  was the eleventh time this feature has found a rule applied in one command and silently missing from
  its neighbour.

  **The route to all of this is closed, and checking why was the point.** A test with no instruction to
  send records nothing (`Runner.swift:44`) but is refused before anything is spent
  (`SpendGate.swift:189`), and a test cannot go missing from one side because both measurements run the
  same list. So the guarantee is real and held entirely by two checks in other files. The wording for the
  omission is therefore built beside the logic that decides it rather than at the place it is printed —
  otherwise it would be prose no test ever ran, inherited unexamined by the next change to either guard.
  Which tests were left out is named in the report's omissions list and marked per row in the payload,
  derived from the counts so the flag and the counts cannot disagree.

  Every change was verified by undoing it and watching its test fail — fifteen undos, including each of
  the two file-reading sites separately, each half of the applying-command rule, each of the three ways
  the routing answer could go wrong (baked-in name, silent fallback to the first skill on the shelf,
  declaration written where staging strips it), and each of the five ways the unmeasured-test rule could
  go wrong — notably narrowing "ran on either side" to "ran on both", which silently drops a test that an
  edit deleted out of the very average meant to notice it. 908 tests / 116 suites green, zero warnings;
  staged, no commits.

- **2026-08-21 — tenth review round: a security sweep, seven items, two changes and one thing proven.**

  **The write that mattered.** Records are written after a measurement that takes minutes, and the check
  that the path is not a link ran only at the start — a long, predictable window. Measured on this
  platform, an atomic write *replaces* a link rather than following it, so the outcome would have been
  safe here; but that is undocumented, differs by platform, and this project supports one it is not
  tested on. The path is now checked again in the instant before the write.

  **That guard is proven to work, by an unusual route.** A link planted before a run is caught by the
  existing start-of-command check, so a test cannot reach the new one. Removing the earlier check
  temporarily does reach it: the write is refused with the new guard's own words and the file outside the
  project still reads `ORIGINAL`. The window itself cannot be driven from a test without timing a plant
  against a live run, which would make the suite flaky for a case it could only sometimes reach — so the
  test asserts the outcome that holds either way, and says plainly what it does not cover.

  **The throwaway copy's folder name used eight characters of a random identifier**; it now uses all of
  it. A clash would have failed safe — making the copy would error rather than reuse someone else's — but
  it is the same birthday bound that was just widened on a test's generated name, for the same reason.

  **What a run suggests doing next is asked of the binary rather than written down**, so a verb that has
  not shipped is never offered. `next` is in the list and unregistered; that is the intent, and it is now
  stated at the site and pinned by a test that speaks up when `next` ships rather than letting the
  suggestion change unnoticed.

  **Three items are accepted and recorded rather than changed.** The hidden test options ship in the
  binary on purpose — the suite exercises the built binary, which is what makes those tests worth having
  — now written in the contributor guide as a decision with its shape for reversing it. Short-lived
  working folders in the machine's shared temporary area, and a preflight check for leftovers, became
  `F76`. A prose pass over the remaining documents before release is worth doing and is not this feature's
  to do. 877 tests / 111 suites green, zero warnings; staged, no commits.

- **2026-08-21 — ninth review round: one of three findings real, and it was the one I had not thought
  about.** Names generated for unnamed tests ended in four hex characters — 65,536 possibilities — while
  the readable part is cut to a fixed length, so a suite whose prompts share an opening phrase leaves the
  ending as the only thing separating them. Measured: **200 tests, 8 colliding pairs**, each then refused
  as a duplicate despite being genuinely different — the refusal added the round before turning on
  correct input. Eight characters removes it; the same measurement now produces none, and it holds at a
  thousand tests.

  **The language finding was raised a second time and is still not a defect — now proven rather than
  argued.** The claim is that lowercasing follows the machine's language. Running the probe with the
  process language *actually set to Turkish* (`Locale.current = tr_TR`): the plain lowercasing used here
  gives `incident`, the language-aware method gives `ıncıdent`, and the language-neutral one gives
  `incident`. It does not consult the current language. The review's own evidence showed only that the
  explicitly-Turkish method differs, which is true and consistent, but does not demonstrate the plain one
  follows the system. The test now states the property the way the concern was raised — the readable part
  must equal what a language-neutral lowercasing produces — so if the method were ever swapped, it fails.

  **The third finding is a real mechanism with a fail-safe consequence and nothing that can reach it.** An
  unreadable recording falls back to a canned answer that claims a skill fired; on a without-skill trial
  that fires the isolation tripwire, so the trial is disqualified loudly rather than mis-graded. And no
  recording in the old format exists anywhere — recordings are produced at run time, never stored. Left
  as it is, recorded here.

  875 tests / 111 suites green, zero warnings; staged, no commits.

- **2026-08-20 — eighth review round: four of five findings real, one not a defect.** The
  machine-readable preview, the half-checked saved file, and the `+0.00 ▲` rounding were all real and are
  fixed; the rounding fault was also in the average line beneath the table, which the review had not
  spotted.

  **The locale finding does not reproduce.** Measured rather than reasoned: the lowercasing used here
  gives the same answer as an explicitly neutral language and a different one from Turkish, so it is
  already language-independent — the sensitive method is the one that takes a language as an argument.
  The recommended change was a no-op. Pinned by a test rather than applied.

  **The file-size finding is correct but incomplete.** Both new files are split and now sit well under
  the cap with the test count unchanged. Six of seven integration files exceeded it, the largest at 1113
  lines and predating this work — recorded rather than quietly fixed or quietly ignored.

  **One of my own tests was wrong twice while checking this.** The locale test compared names built from
  two *different* strings, so it compared hashes rather than lowercasing; and the rounding test matched
  the whole table, catching the summary line rather than the row. Both corrected, and the second is what
  revealed the summary line had the same fault. 867 tests / 109 suites green, zero warnings; staged, no
  commits.

- **2026-08-20 — coverage as a finding tool, and the fourth route to a false "proven".** Asked what still
  needed testing, measuring coverage rather than guessing pointed at two uncovered lines that turned out
  to be a live defect: two tests sharing a name silently dropped one of them from every comparison, so a
  regression could disappear and the tool would offer to ship the edit.

  **A structural note from that measurement:** coverage cannot see `Sources/skillet/` at all — zero of its
  files appear — because those commands are exercised by launching a separately-built binary rather than
  by calling into a library. Worth knowing before trusting a coverage number here.

  Resolved as D18 over four decisions, one of which reversed on evidence: refusing tests that carry no
  name looked right until the corpus showed **three of four real skills name none**, which would have
  rejected most of them. They are named from their content instead.

  **The refactor cost more than estimated and I mismanaged part of it.** Making two builders throwing
  rippled into test files across the suite; a blanket edit to add `throws` touched 46 of them, most
  entirely unrelated. Reverted to the six that genuinely needed it and redone. 862 tests / 103 suites
  green, zero warnings; staged, no commits.

- **2026-08-20 — seventh review round: four findings, all real; the first is a spend fault.** Naming a
  recorded-answer file without `--replay` was accepted, ignored, and followed by a **real model launch**
  — reproduced for free on a machine with no model program, where it reached "could not find the
  claude-code binary". Both paid commands, both recording options, now refused from one place.

  The grader gap turned out to matter more than parity: the file-reading grader exists for *created the
  file, contents wrong*, and without it the loop could find that failure, draft an edit for it, and never
  prove the fix. A settings key for the grader was considered and **deferred with reasons** (D17) rather
  than added by reflex — the precedent that requires the grader *model* to be pinned rests on the model
  floating, which the grader kind does not do.

  **Two of my own tests were the very defect being fixed.** One reused invocations that already carried
  the flag under test; one asserted an option was accepted rather than used, and stayed green when the
  fix was undone. Both were caught by the standing revert-check and both now assert the observable
  consequence instead of the acceptance. 848 tests / 101 suites green, zero warnings; staged, no commits.

- **2026-08-20 — first live run against a real model. The loop works, and the grader told two versions
  of a skill apart.** Everything before this had substituted the model and the grader, so nothing had
  proven the command works with real ones.

  **Run one was uninformative, and that was a test-design fault.** A skill that names owners but not
  dates, an edit adding "state when it is due", and two tests. Both read `1/1` before *and* after, so the
  verdict was "nothing got worse" — true and useless. The answers show why: the criterion was *"every
  action item states when it is due"*, and the unedited version already wrote *"due Friday"*. The edit
  did work — it turned relative dates into calendar dates and added a note about its assumptions — but
  **no test measured the thing it changed.** A tool that reports only what it can support is behaving
  correctly here; the eval was too loose to detect the improvement.

  **Run two, with a test the unedited skill genuinely fails, produced a real flip:**

  ```
  EVAL                      BEFORE   AFTER    Δ
  calendar-dates            0/1      1/1      +1.00 ▲
  ```

  The real grader (`text-judge`, prompt `v2`, model `sonnet`) failed the original — *"action items use
  only relative dates (Friday, over the weekend, early next week) with no explicit calendar dates"* — and
  passed the edited version — *"all three action items include explicit calendar dates (Fri 21 Aug, Sun
  23 Aug, Tue 25 Aug)"*. That is the one thing the offline tests structurally cannot show: that grading
  distinguishes two versions rather than collapsing to one answer.

  **Also confirmed live**, on both runs: the throwaway copy carried the edit (`Name the person
  responsible for every action item, and give its due date as a calendar date…` in the copy, the original
  sentence in the working tree); records written per measurement, per test, per trial; the working tree
  clean afterwards and no copies left in git's list.

  **What is still not proven, and cannot be by a run like this:** that the grader agrees with a person.
  That is calibration — `F10` — and needs a labelled sample, not a smoke test. A pass here means the
  machinery works, not that a verdict is right; the report says so on every verdict for that reason.

  **Packaged into the convention this project already had.** First attempt was a shell script under
  `Scripts/`, which was wrong on four counts and caught by asking whether it was the best shape: the
  repository already runs a paid check this way — `RunIntegrationTests.liveSmoke`, tagged `.slow` and
  gated on `SKILLET_LIVE_SMOKE` — so the script was a second mechanism for an existing convention, with
  its own gate variable; it rebuilt fixtures `makeRepo` already builds; it swallowed the exit code behind
  `|| true`; and it asserted by grepping the **printed table**, which this project publishes as carrying
  no compatibility promise (design **P7**), so a harmless rewording would have broken it.

  It is now `IterateIntegrationTests.liveSmoke`: same tag, same gate, same fixture builder, asserting on
  `skillet.iterate/1` rather than on printed text. Both paid checks are skipped by every ordinary run and
  **reported as skipped**, so their absence is visible rather than silent. It requires the unedited skill
  to fail its test and the edit to fix it — a live run where both versions score alike is equally what a
  collapsed grader would look like, which is the failure it exists to catch.

  The recording that would make this free and repeatable does not exist: every canned-answer file here is
  hand-written, so `F74` was added to build a `--record` switch, and today's real answers are preserved
  above as prose rather than as a fixture.

  **Running it exposed two mistakes of mine and one real finding.**

  *Mistake one — asserting the model's compliance.* The check demanded that the edit improve the score.
  That is an assertion about the **model**, not about this program: on a single sample a model need not
  follow an instruction, so the check went red twice while everything here worked correctly. The
  guidance for software that calls a model is to assert properties that hold whatever it writes, and to
  validate the deterministic layer — so the check now asserts only that: a real program launched twice in
  one command, both measurements recording a trial, **the skill actually invoked in each**, and the copy
  gone afterwards.

  *Mistake two — a wrong query, and conclusions drawn from it.* Diagnosing the first failure, a
  hand-written check read `skillInvocations` where the recorded file spells it `skill_invocations`. The
  empty result led to three claims, all false and all retracted: that the skill was never consulted, that
  the earlier live flip had been model variance rather than the edit, and that invocation detection was
  broken — which would have meant the isolation tripwire behind `--ab` could never fire. **The parser is
  correct.** An empty result from a hand-written query is not evidence.

  *The finding — a skill's description decides whether a real model consults it at all.* The shared test
  fixture describes its skill as *"A demo skill for proving edits, long enough to satisfy the lint
  rules"*, which is true and tells a real model nothing about any job. Against a live model that produced
  exactly what you would expect and what is easy to miss: staged, discovered, **never used**, in both
  measurements — with plausible-looking scores throughout, because the base model answered. Swapping in a
  description of an actual job made the skill fire in both arms. Offline this is invisible: the stand-in
  reads a marker out of the file and never decides anything. `makeRepo` therefore takes a description
  now, and the live check passes a real one.

  **"Can grading tell two answers apart" moved out of this check entirely** — inferring it from whether a
  nondeterministic edit moved a score was the least reliable way to ask a question about the grader. It
  is now `RunIntegrationTests.liveGraderDiscriminates`: one run, one reply, two expectations — one it
  must meet and one it cannot. Against a live grader it passed *"the reply contains the word hello"* and
  failed *"the entire reply is written in Japanese script"*, which rules out the collapsed-grader failure
  deterministically and without any dependence on a model obeying an instruction.

  **All three paid checks pass** (verified in two batches, not one run): the measuring command's
  end-to-end, the grading-discrimination check, and the proving command's two-measurement check. All
  three are skipped by every ordinary run and reported as skipped.

  **One caveat on the settings used**: the grader model was pinned to the alias `sonnet`, because this
  binary (Claude Code 2.1.232, bundled by the editor) does not recognise the `claude-sonnet-4-6` spelling
  in the repository's other settings files. An alias floats to whatever is latest, which is against this
  project's own required-explicit-model rule — acceptable for a smoke check, not for anything committed.

- **2026-08-20 — sixth review round: four findings actionable, two correctly identified as needing no
  change.** The promptless-test defect is the third distinct route to the same vacuous outcome in this
  feature, after a repeat count of zero and a comparison drawn from no data: with every test promptless,
  the proving command printed two `0/0` rows, declared the edit proven, **offered the command that lands
  it**, and exited `0`, while the measuring command exited `1` on the same skill.

  **One recommendation was not taken as written.** The reported fix for unreadable files was to make the
  measuring command match the proving one — but the proving one prints the reading library's entire error
  object, including its type and domain names. The guidance on error messages is against putting those in
  front of people; the durable, useful part is *where in your file* the fault is. So both were changed,
  not one, and the translation now lives in a single place used by every site that reports an unreadable
  file.

  **And two guarantees moved because a fix made their tests unreachable.** Refusing promptless tests
  removed the only offline way to record fewer repeats than were asked for, so the previous round's test
  for that could no longer fail; the report now derives its repeat count instead of being told it. The
  stand-ins likewise cannot produce an unusable comparison arm, so that condition is defined beside the
  data and tested directly. Both are better placements than the tests they replaced — a test that cannot
  fail is worse than none, because it reads as cover.

  **Verified by undoing each fix**: without the prompt check both commands let a test that cannot run
  through to a verdict; without the shared translation the measuring command stops saying where the fault
  is; without the caveat the blocked verdict loses it. 839 tests / 100 suites green, zero warnings;
  staged, no commits.

- **2026-08-20 — fifth review round: three findings, all real, all reproduced.** The threshold defect is
  the same shape as the round that preceded it, one field short: the gate built to stop settings being
  applied silently was itself forwarding one unchecked, and the free preflight vouched for it with a tick.
  The "observed" count was the requested count, which made two commands disagree about one skill —
  `observed k=3` from one and `observed_k: 0` from the other, on the same data, with a `0/0` row on screen.

  The third was latent and stayed latent: the marker boundaries hold only while the canned answers avoid
  two characters. Carrying the marker on a shared type would have fixed it by pushing a testing concern
  into what the real graders use, so instead the rule is written where the canned answers are and enforced
  by a test.

  **Verified by undoing each fix**: with the threshold check widened both commands accept a setting that
  makes every run stop to ask; with the requested count restored the report claims three repeats beside a
  row that recorded none; with a `[` added to a canned answer the invariant test fails on both answers.
  831 tests / 98 suites green, zero warnings; staged, no commits.

- **2026-08-20 — fourth review round: three findings, all real; two of four suggested test gaps were not gaps.**
  Every finding was reproduced against the built binary. The grader defect is the starkest measurement of
  this whole series: **twenty identical runs, ten reporting `0/3` and ten reporting `3/3`** — opposite
  verdicts, nothing changed. The cleanup defect was reproduced by substituting a git that always fails to
  remove a copy: full successful report, exit `0`, not a word about the folder left behind.

  **One finding was half right and the correction was worth more than the finding.** The unguarded read
  was described as hanging forever on a named pipe. It does not — measured, `String(contentsOf:)`,
  `Data(contentsOf:)` and `FileManager.contents(atPath:)` all refuse instantly and only
  `FileHandle.readDataToEndOfFile()` blocks. The read *was* unbounded (200 MB in one gulp), the guard is
  right, and one long-standing comment blamed the wrong call; that is now corrected in place.

  **Two things I got wrong mid-round, recorded because they cost time.** A check for ambiguous recordings
  was written and withdrawn: it compared recorded markers with each other, but the clash is between a
  recorded marker and the *skill's* marker, which the recording need not contain — it would have looked
  like cover without being any. And the new disclosure test **trapped instead of failing** when the fix
  was undone, because `#expect` does not stop a test and the next line indexed into an empty list; it took
  a hung revert-check to notice. It requires the element now.

  **Of the four suggested coverage gaps, one was added and one was reshaped.** Mixed line endings are
  already covered thirteen times over (`ApplyIntegrationTests.swift:436`, `:569`, `:591`, plus ten unit
  tests); a draft deleted mid-run has no window to test, because the file is read once into memory and
  never re-read. The identical-differences case is real and added. The concurrency suggestion became a
  **deterministic** two-runs-in-sequence test instead: what it was worried about is a naming collision,
  and a timing-dependent test would have been a flake generator for a guarantee that can be checked
  without a race.

  **Verified by undoing each fix**: without exact matching the overlapping markers grade by a fragment;
  without the guarded read a staged file that is a symbolic link is followed and one over the limit is
  read whole; without the returned cleanup result the surviving copy goes unmentioned in both the printed
  and the machine-readable result. 827 tests / 98 suites green, zero warnings; staged, no commits.

- **2026-08-19 — third review round: three findings, all real, one worse than reported and one whose
  reasoning needed replacing.** Each was reproduced against the built binary first.

  **The land-command defect is the serious one.** Proving `--edits 0` of a two-edit draft printed
  `→ land it: skillet suggest demo --proposals fix.json --apply` — which applies *both* edits. A command
  whose whole purpose is to refuse unproven changes was recommending one. Same class as the `--runs 0`
  vacuous pass from the previous round, by a different route.

  **The grammar finding was right, but not for the stated reason.** It was called a defect in a command
  that "prides itself on precise reporting"; checking first showed `(s)` appears eight times in that file,
  which would have made a lone fix the odd one out. It is *not* house style — the same file pluralises
  properly in seven places — so the fix aligns the outlier rather than creating one.

  **And one reported half is defence in depth, not a defect.** Passing the raw flag array instead of the
  canonical list is fixed, but with repeats refused up front the two can only differ in order, and order
  does not survive the applying engine (`--edits 1 0` and `--edits 0 1` give byte-identical output). No
  test is claimed for it, and the revert-check that would have proved one is recorded as not producible.

  Resolved as D13. Two existing tests of the applying command asserted the old refusal wording and were
  updated — to what the message must *carry* (the flag, the count) rather than to one phrasing, since the
  sentence is now shared and human text is explicitly not a contract (design P7).

  **Verified by undoing each fix**: without the duplicate check both commands report an edit overlapping
  itself and one leaves the wrong number; without the subset in the land command the offer reaches an edit
  nothing measured; with `test(s)` restored the single-regression line reads ungrammatically.
  818 tests / 98 suites green, zero warnings; staged, no commits.

- **2026-08-19 — second review round: five findings, all real, plus two more found while verifying them.**
  Every finding was reproduced against the built binary before anything was changed, and two were worse
  or narrower than reported. **The vacuous pass is the worst thing in this feature so far:** `--runs 0`
  printed `e1  0/0  0/0  —`, *"no test scored lower"*, exit `0`, **and the command to land the edit** —
  advice to ship something that was never measured. It reproduces three ways (`--runs 0`, `--runs=-2`,
  and `k: 0` in the settings file); the bare `--runs -2` is already refused by the argument parser, so
  the report's "negative values" needed the equals form to demonstrate.

  **The bracket finding needed a sharper reproduction than the report gave.** The reported case grades
  correctly by accident — the mis-parse falls through to a default that happens to agree. Constructed
  properly it *inverts a verdict*: identical recorded grades, identical harmful edit, marker `v1 release`
  → `3/3 → 0/3`, *"1 test(s) scored lower"*, exit `1`; marker `v[1] release` → `0/3 → 0/3`, *"no test
  scored lower"*, exit `0`.

  **Two more of the same family surfaced during verification.** The cost question fires above 20 trials
  here and 25 in the measuring command from the same settings file (at 22 trials with prompting off, one
  refuses and the other proceeds). And a time limit the tool cannot read — `"banana"`, `"10 minutes"`,
  `"1 h"` — is silently replaced with ten minutes in **both** commands, which predates this feature.

  All of it resolved as D12. The framing fix followed the codebase rather than the textbook: escaping or
  length-prefixing would each have repaired the bracket bug, but the real adapter already puts JSON in
  that field and reads it back with a decoder (`ClaudeCodeAdapter.swift:183` and `:134`), so the
  stand-in does too — one fewer way a double differs from the thing it stands in for. The double now has
  tests of its own framing, which it did not before, which is how the bug shipped.

  **Verified by undoing each fix**: without the repetition guard the vacuous pass returns; with the
  wording always blaming the flag the settings-file case misdirects; with the silent time fallback back
  the preflight goes quiet; with the hand-typed `20` restored the two commands disagree about when to
  ask; without the kept-copy line the preview leaves a folder unannounced; with the bracket format back
  the awkward markers truncate; and deleting the gate call stops the program compiling.
  811 tests / 98 suites green, zero warnings; staged, no commits.

- **2026-08-19 — documentation ripple applied; four drifts found, and one check that could not see them.**
  §9's list was applied in full and was **not sufficient**: four claims inside the design document's own
  section for this command were stale, listed in §9. The most telling is that the usage line had been
  corrected while the sentence directly beneath it still spelled the flag that correction removed —
  through a full green suite, because the only mechanical option check covered a different command.

  **So the check was widened, and verifying it exposed a false pass.** Undoing the fix and re-running
  showed the new check passing anyway: it compared against `--help`'s *text*, and this command's help
  names `suggest --apply` while telling you how to land a proven edit — so a flag the parser refuses
  looked accepted. It reads the parser's structured argument dump now. Both checks fail correctly in all
  three directions: a flag in the usage line the parser refuses, a flag in the prose the parser refuses,
  and a flag listed as planned that has quietly started working.

  The read-me was the only file with nothing applied, and two exit-code doc comments had drifted from the
  table they mirror — `0`'s narrowing for this command, and `5` gaining the declined cost confirmation
  (D8). 796 tests / 96 suites green, zero warnings; staged, no commits.

- **2026-08-19 — post-implementation review round: four defects, one finding disproved.**
  Five findings were raised against the staged feature; each was checked against the running binary
  rather than reasoned about, and one did not survive that — the import reported as unused is load-bearing
  (removing it fails to compile: `cannot find 'ProposalDrafter' in scope`).

  **The security defect was reproduced end to end before it was fixed.** With only `.skillet/runs`
  redirected by a symbolic link, this command wrote **six raw transcripts outside the project and
  reported success**, while the measured run given the same setup refuses: *".skillet/runs is invalid:
  cache path crosses a symlink (not allowed): runs"*. The cause was writing straight to the path instead
  of through the shared preparation routine that performs that check — the same shape as D9 and D10: one
  command guards, the other does not.

  **The three missing free refusals and the leaking copy** are recorded as D10 and D11, including the
  measurement that disproved the assumption behind leaving the leak alone: a dead copy record is *not*
  cleared by making the next copy, and git's own sweep does not touch it for three months.

  **Two smaller ones.** The renderer's new method was inserted directly beneath a doc comment that
  already belonged to another method, silently re-labelling the drafting command's renderer as this one's
  — each now documents itself. And the free stand-in's marker lookup *ignored the skill it was handed*,
  listing the staged folder and taking the first name alphabetically; with two skills staged, a
  measurement of `b` silently reported `a`. It reads the named skills now, loaded before merely-present,
  and falls back to the folder only when no skill was named — which is what every existing recording does.

  **Verified by undoing each fix**: without the cache guard the transcripts escape again (exit `0`, and
  the outside folder fills); without the scope the dead copy record survives (`git worktree list` shows
  two); without the shared routine the missing fixture and the breaking edit both sail through to a paid
  measurement; with the static check aimed at the live skill the repair is blocked *and* the breaking
  edit admitted; and with the alphabetical lookup restored the stand-in answers as the wrong skill.
  795 tests / 96 suites green, zero warnings; staged, no commits.

- **2026-08-19 — implemented, in two stages, with five things the plan could not have known.**
  Stage one changed the two things that could break what already works, and was verified before anything
  was built on it. **The free stand-in could not tell two versions of a skill apart** — in two places at
  once: the answer was built from the question alone, and the grader looked up a verdict by criterion
  wording while ignoring the answer. Both were needed, and a third link was found only after the first
  two appeared to work: the marker reached the raw text and was then discarded when the trace was
  parsed. **The cost confirmation was extracted** so both paid commands share the asking while each keeps
  its own number, and the shared statistic moved somewhere neither feature owns. **One path has no
  automated cover and was checked by hand**: the branch that actually prompts needs a terminal, which no
  test has. It behaves identically, confirmed interactively, and a real paid run through a live model
  proved the whole path end to end.

  Stage two built the rest, and hit a fork the plan had not foreseen. **Getting a runner was not
  reachable**: the plan said the measuring loop was reused unchanged — true — but the 76 lines that
  choose the program and the grader were private to the measuring command, and this command needs them
  including the offline seams. Neither wholesale sharing nor a private copy was right: one binary should
  wire its parts in one place, while generalising a routine around settings its new caller never uses is
  the shape you cannot read at the call site. **The common core moved and the run-only branches stayed**
  — the switched-off arm's grader and the grader-free axis have no second caller.

  **Three defects found by building it.** Registering the command flipped a branch nobody had executed:
  the closing hint replaced "commit your results" with the new verb the day such a verb existed — but a
  run leaves the tree dirty and this command refuses a dirty tree, so the suggested next step would have
  refused the instant anyone followed it. They are sequential now, not alternatives. The relative path
  to the skill was computed by cutting the project path out of the skill path, which ate the middle when
  the two were spelled differently (`/tmp/x` inside `/private/tmp/x` → `/privateskills/demo`) — the same
  partial-path trap this project already documents in its confinement checks; it is built from the
  configured location and the folder name instead. And the first fixture wrote its recorded verdicts
  *after* committing, so every test refused at the clean-tree gate — which is at least the gate working.

  **Verified by undoing each guarantee**: creating the copy with a branch, removing it without forcing,
  not removing it at all, and pointing both measurements at one folder each fail their matching test.
  783 tests / 95 suites green, zero warnings; staged, no commits.

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
