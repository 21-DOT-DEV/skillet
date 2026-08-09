# F42 — Safe apply to the working tree (`skillet suggest --apply`)

| | |
|---|---|
| **Feature** | F42 — Safe apply to the working tree (Phase 6 · [phase-6-fix-suggestion-iteration.md](../../Roadmap/phase-6-fix-suggestion-iteration.md)) |
| **Command** | `skillet suggest <skill> --proposals <name>.json --apply [--edits <n>...] [-n\|--dry-run] [--json]` |
| **Status** | **IMPLEMENTED** — 2026-08-04 (staged, no commits — manual review). Planned 2026-08-02, then reviewed before implementation, which surfaced two decisions the plan could not have known (D6, D7) and one instruction in it that could not work. |
| **Decisions** | **D1 — A clean repository is required, whole-tree.** · **D2 — One file only; extraction is the next increment.** · **D3 — Verify everything, then write all or write nothing.** · **D4 — A refused apply exits `5` (a gate refused), not `4`.** · **D5 — The exact-once matching rule moves to the pure core and is shared by drafting and applying.** · **D6 (pre-implementation) — applying reports under its own machine-readable format.** · **D7 (pre-implementation) — `--apply` is a plain switch; `--edits` narrows it.** · **D8 (post-review) — `--dry-run` is a real preview of applying, not an error.** · **D9 (post-review, widened 2026-08-07) — a quoted passage *and its replacement* are converted into the file's own line-break convention, in both directions; nothing else about matching is relaxed.** · **D10 (post-review) — "appears exactly once" counts every *position* the passage matches, overlapping included.** · **D11 (post-review) — the replacement carries the original file's permissions, set before it goes into place.** · **D12 (post-review) — before overwriting, the tool asks version control directly whether *that file* can be restored, rather than inferring it from a whole-project summary.** |
| **Assumptions** | **A1 — Pure engine, effects in the shell.** · **A2 — Applying is free.** · **A3 — The saved-draft format graduates to stable.** · **A4 — Never commits, never stages.** · **A5 — Matching happens against the file on disk.** · **A6 — Selection by index stays explicit.** · **A7 — Test-first, every test free.** |

## 1. Outcome

You have a saved draft you have read and agree with. One command puts it into your working copy —
exactly, or not at all — and stops there. You review the change with your normal tools and commit it
yourself.

## 2. Scope

**In:** reading a saved draft back, requiring a clean repository, matching each edit's quoted passage
against the file as it is *now*, writing all selected edits or none, and reporting precisely what
happened.

**Out:** committing or staging anything (forbidden outright); creating or editing any file other than
the skill's own instruction file (§8); measuring whether the change helped (that is the next feature
after this one); choosing edits for you.

## 3. CLI contract

```
skillet suggest <skill> --proposals <name>.json --apply [--edits <n>...] [-n|--dry-run] [--json]
```

- `--proposals <name>.json` names the saved draft — a **filename**, looked up in the drafts folder, on
  the same rule that writing one uses. The tool never guesses which draft you meant, never picks "the
  most recent", and handles no user-supplied paths on this write path at all. The drafting run prints
  the exact apply command, so there is nothing to retype.
- `--apply` applies every edit in the draft. `--edits 0 2` narrows it to those, numbered in the order
  they appear in the draft (D7).
- `<skill>` is still required and is **cross-checked** against the draft. A mismatch is refused: a
  draft written for one skill must not be applied to another.
- `--from` and `--proposals` together are a usage error. One asks to draft, the other asks to apply a
  draft that already exists; doing both in one command hides which one you meant.
- Applying **makes no model call and costs nothing.** The paid path is drafting, which already exists.

### Exit codes

| Code | When |
|---|---|
| `0` | every selected edit was written |
| `2` | usage — no `--proposals`, a number that isn't an edit in the draft, a skill that doesn't match, asking to draft and apply at once, a draft with no edits |
| `3` | environment — `git` not found, not inside a repository, or the file could not be read or written |
| `4` | the draft file is unreadable or malformed |
| `5` | **a gate refused** — the repository is not clean, or an edit no longer matches. Nothing was written. |

**D4 — why `5` and not `4`.** A refused apply is not a broken file in your project; the draft is
valid and so is the skill file. What happened is that a safety check said no — the same shape as the
existing size ceiling, which already uses `5`. Reserving `4` for genuinely malformed input keeps the
two distinguishable by a script.

## 4. What runs, in order

Every step before the write is free and cheap, and the cheapest refusals come first.

1. **Resolve the skill** named on the command line ⇒ `2` if there is no such skill. *(Corrected after
   implementation: the plan had this after reading the draft. Getting the skill name wrong is answered
   better by "unknown skill — choose one of: …" than by a parse error from a draft you also got wrong,
   so the code's order was kept and this text was brought in line with it.)*
2. **Read the draft** (`--proposals`) through the confining reader every untrusted file goes through.
   Malformed ⇒ `4`. Then **cross-check the skill** against the draft ⇒ `2` on mismatch.
3. **Resolve the selection.** No `--edits` means every edit; a number outside the draft ⇒ `2`. This sits
   here because the draft is what defines the valid range, so this is the **first moment it can be
   checked** — and a mistake in what you typed must answer before anything about the state of your
   machine. It ran last for a while, which meant an unrelated uncommitted file answered first and hid
   the typo behind a different error. *(An audit of the whole sequence found this was the only step out
   of place; every other check already runs at the earliest point its information exists.)*
4. **Require a clean repository** (D1) ⇒ `5` when anything is modified, staged, or untracked.
5. **Read the skill file** as it is now.
6. **Verify every selected edit** against that text (D3). Any refusal ⇒ `5`, nothing written.
7. **Write once**, all selected edits together, as an **atomic replace**. *(Corrected during review: the
   plan first said "the same create-safely routine the rest of the tool uses" — that routine exists to
   **refuse** to replace an existing file, so it is the wrong tool for a command whose job is to
   overwrite one. A clean repository is what makes the overwrite safe to undo.)*
8. **Report** what was written, and say plainly that nothing was committed.

**`--dry-run` stops before step 7 and writes nothing** (added after implementation — see the status
log). It runs every check, reports which edits *would* land and everything that would block them, and
exits with the refusal status if a real run would not succeed right now.

### D1 — A clean repository is required, whole-tree

The charter is explicit: the only sanctioned way to edit a live skill file is this path, *"which
refuses a dirty tree and stops short of the commit"*. Whole-tree is the plain reading, it needs no
amendment, and the closest comparable tool — the one that rewrites your source from compiler
suggestions — refuses a dirty working directory by default for the same reason.

The safety story is that your version-control history **is** the undo button. That only holds if the
difference after applying is exactly what the tool did.

*If this proves obstructive in real use*, the amendment to propose is **recoverability**, not "only the
files being edited": permit changes that are already staged (they can be restored with a single
checkout) and refuse untracked targets (nothing to restore to). That is a sharper rule than a blanket
narrowing, and it is the rule the surrounding ecosystem actually converged on. Propose it with
evidence, through the amendment process — not by quietly relaxing the check.

### D3 — Verify everything, then write all or write nothing

Each edit carries a quoted passage that must appear in the file **exactly once**. Between drafting
and applying, the file may have changed, so a passage can now match nothing or match twice. Every
selected edit is checked before a single byte is written.

Two reasons this is all-or-nothing:

- **The failure state needs no undo.** "Nothing happened" is always recoverable. A half-applied file
  matches neither the original nor the draft.
- **A partial apply corrupts the measurement.** A draft carries a claim — *these tests should start
  passing*. Apply four of five edits silently and that claim still describes five. You re-measure, the
  tests don't flip, and you conclude the fix doesn't work when you never applied it. A false negative
  that discards a correct fix is the most expensive error this workflow can make.

Choosing a subset stays available and **explicit** (`--edits 0 1 3`), so nothing is lost — only the
tool guessing on your behalf. This matches the default behaviour of the standard patch tool, which
*"fails the whole patch and does not touch the working tree when some of the hunks do not apply."*

**Overlapping edits are refused too.** If two selected edits match ranges that overlap, applying
either changes the meaning of the other. That is a refusal, not a resolution attempt.

### D6 — applying reports under its own format

The drafting summary describes a different event: which model, which instruction version, how large the
request was, whether it was a preview. An apply run knows none of those. A payload should carry only the
facts of the event it describes, and the convention is a shared type tag with one shape per type — which
the `schema` field already provides. One format for both would make half of either payload meaningless
depending on a mode the reader must infer first.

### D7 — `--apply` is a switch, `--edits` narrows it

The plan wrote this as `--apply` optionally followed by edit numbers. The argument parser in use
**requires an option to carry a value** — verified: a bare option errors with "Missing value", and one
accepting zero-or-more values errors the same way. So `--apply` and `--apply 0 2` cannot be one
declaration. Keeping `--apply` meaning "apply the whole draft" preserves the documented behaviour and
confines the forced deviation to how you narrow it.

## 5. The saved-draft format graduates to stable

The drafted-file format shipped **provisional**, with a stated condition: it graduates when something
reads it back. This is that reader. On landing, the format's provisional note is replaced with the
same compatibility promise its sibling summary format already carries — additive-only, consumers
ignore fields they don't recognise.

Nothing about the format changes here. What changes is the promise attached to it.

## 6. Module & layering

The design assigns the content-anchored apply engine to a module that does not exist yet; this
feature creates it with that one engine. The rest of that module — throwaway-copy lifecycle — belongs
to the following feature.

```
EDDCore (pure)          EditProposal / ProposalSet  +  the exact-once matching rule (D5)
  → IterateKit (pure)   EditApply — verify a selection, produce the rewritten text
  → skillet             reads the draft, checks the repository, writes the file, reports
```

**D5 — one matching rule, two callers.** Drafting already implements exact-once matching, to check a
model's proposed passage before recording it. Applying needs the same rule against the file on disk.
Two copies of a safety-critical rule is how they drift apart, so the primitive moves into the pure
core and both call it. It returns the matched **range** (applying needs to splice) with the
human-readable line label derived from it, rather than the label alone.

No new dependency, so no amendment. `IterateKit` is pure — no filesystem, no processes.

## 7. Test plan (red → green; every test free)

**Unit — the engine (`IterateKitTests`)**

7a. A passage appearing exactly once is placed at the right range.
7b. A passage appearing nowhere is refused, naming the edit.
7c. A passage appearing twice is refused, with the count.
7d. Two selected edits whose ranges overlap are refused.
7e. Several non-overlapping edits apply in one pass and produce the expected text, regardless of the
    order they appear in — applied back-to-front so earlier offsets stay valid.
7f. A selection naming an index the draft doesn't have is refused.
7g. **Nothing is written when any edit is refused** — the engine returns either a full set of
    placements or a set of refusals, never a partial set.

**Integration — the command (drives the built binary)**

7h. Clean repository, valid draft ⇒ the file contains the new text, exit `0`.
7i. **Nothing is committed and nothing is staged** — asserted directly against the repository state
    after a successful apply. This is the charter's absolute rule and gets its own test.
7j. A modified file anywhere in the repository ⇒ exit `5`, skill file byte-identical.
7k. An untracked file anywhere ⇒ exit `5`.
7l. The skill file edited since drafting so one passage no longer matches ⇒ exit `5`, **and the file
    is byte-identical** — the all-or-nothing proof, with a second edit in the draft that *would* have
    applied.
7m. Not inside a repository ⇒ exit `3` with a remedy.
7n. A malformed draft file ⇒ exit `4`.
7o. `--from` and `--proposals` together ⇒ exit `2`.
7p. A draft whose skill doesn't match the one named ⇒ exit `2`.
7q. `--apply --edits 9` on a two-edit draft ⇒ exit `2` naming the valid range.
7r. `--json` reports what was applied under a versioned schema, and the human output says the same.

**Regression discipline:** every guarantee verified by undoing it and confirming its own test fails —
the clean-repository check, the all-or-nothing property, the splice, and the two-jobs separation.

**What that discipline caught.** Undoing the splice ordering did not fail a test — it **hung the test
run for twenty-one minutes**. The first implementation edited the file text in place, reusing positions
measured against the original; in Swift *any* mutation invalidates positions already held, so the wrong
order was undefined behaviour rather than merely wrong output. Rewritten to build the new text by
reading the untouched original once and never mutating — removing the hazard instead of ordering around
it — and a test now pins that the result cannot depend on the order placements arrive in.

## 8. Open items deliberately deferred

- **Extraction into reference files — the next increment, agreed.** The canonical guidance for an
  over-long instruction file is to move bulk content into a separate reference file, and this
  project's own static check already flags the length. Today that fix cannot even be *drafted*: the
  instructions never mention it and the target file is validated to the one skill file. It therefore
  needs **both halves in one increment** — drafting (mention extraction; widen target validation;
  confine new paths inside the skill folder) and applying (a create operation, which has **no existing
  text to match**, so the exact-once check does not protect it and needs its own rule). Kept out of
  this feature because the charter requires a documented security review of this write path, and that
  review is worth far more when what it reviews is one narrow operation.
- **Measuring whether the applied change helped** — the following feature owns re-measurement in a
  throwaway copy.
- **Recording which edits were applied back into the draft** — useful for attribution, but it means
  writing to a file the tool otherwise only reads. Revisit with the marking feature.
- **An override for the clean-repository rule** — see D1. Needs evidence and an amendment, in that
  order.
- **The seven remaining unconfined reads** — audited 2026-08-07, no code changed. Two ways exist to read
  a file: a plain one, and a confined one that first walks the path from a chosen folder down to the file
  and refuses if any part of it is a pointer to somewhere else on disk. The draft read in
  `SuggestCommand.swift` moved to the confined call this round; these seven did not, and here is the
  judgement on each, so the next person does not have to redo it.

  | Where | Is there a folder it must stay inside? | Judgement |
  |---|---|---|
  | `ConfigSupport.swift:44` — a settings file named by `--config` | No | **Cannot be confined.** The point of the flag is naming a file anywhere on the machine. |
  | `ConfigSupport.swift:61` — `skillet.yaml` at the project root | The project root | **Low value.** This is the read that establishes where the project *is*; confining it against the root it just derived is close to circular, and the file sits directly in that root. |
  | `RunCommand.swift:138` — a skill file, before a paid run | The project root | **Candidate.** Already covered by an explicit neighbouring check (`RunCommand.swift:474`) that rejects a pointer anywhere between the project root and the skill folder — the same situation as the read that moved this round. |
  | `TriageCommand.swift:258` — evidence files | The project root | **Should not change.** A pointer here is deliberately *reported* rather than refused, a decision made in an earlier round; confining would silently turn a disclosure into a refusal. |
  | `SuggestCommand.swift:765` — friction notes | The evaluations folder | **Candidate, and an inconsistency.** The other evidence read in the same file (`SuggestCommand.swift:721`) already confines to exactly that folder. |
  | `SkillReader.swift:41` — a skill file | Not in scope | **Needs a signature change.** This is a low-level reader handed a folder; the project root would have to be threaded in from every caller. |
  | `WorkspaceManager.swift:224` — a staged file, per trial | The staged folder | **Low value.** The line immediately above already rejects a pointer at that exact path. |

  So: two genuine candidates, one that must not change, and four where it is either impossible or buys
  nothing. None is a defect today.

## 9. Docs ripple on landing (not now)

The how-to guide on turning evidence into a fix carries a note saying applying automatically is
"planned but not shipped" — that note goes, and the guide gains the apply step. The tutorial's
free-versus-paid table gains a row (applying is free). The contributor guide's command list, which is
checked against the binary by the test suite, gains the flags. Roadmap phase 6 marks this feature
implemented; the release log gains an entry; the specification index gains a row. Design §6.1 loses
the "no `--apply` yet" annotation and §7.3 loses the provisional-format note.

## 10. Status log

- **2026-08-08 (third) — one reported refusal, and a silent corruption underneath it that the report did
  not reach.** Text files mark the end of a line one of three ways: a line feed (Unix, modern macOS), a
  carriage return followed by a line feed (Windows), or a carriage return alone (Macs before 2001). The
  tool translated between the first two so a quoted passage still matches when file and quote disagree,
  and did nothing for the third. **(1) The reported symptom, reproduced through the command rather than a
  stand-in.** A passage spanning two lines failed to match such a file and was refused with "the text it
  replaces is no longer in the file — the file changed since this draft was made; draft again". The file
  had not changed and drafting again hits the identical wall, so the remedy could not work — the same
  false-retry shape fixed once already for the Windows case. **(2) The half the report missed, and the
  worse half.** A single-line quote matches fine, so an edit whose *replacement* spans two lines applied
  **successfully** and wrote a plain newline into a carriage-return file, leaving it using both
  conventions at once — measured at 7 carriage returns and 1 line feed. A refusal is visible; this was
  silent. **(3) A third consequence, found while fixing the first two.** Line numbers were counted by
  looking for line feeds, so every match in such a file reported line 1 — a confidently wrong location,
  which is worse than none. Now 7, verified. All three come from one mechanism: reduce to plain, then
  adopt the file's convention, which is what the other two already do — this adds the third to it rather
  than inventing anything, and matches how text tooling has handled all three since universal newline
  support became standard. **Reachability, stated precisely rather than assumed:** drafting is gated by
  the free static check, which rejects such a file for an unrelated reason ("frontmatter is missing or
  unparseable"), so this tool will not produce a draft against one — a hand-written draft is the only
  route, which the format expressly allows. **Two corrections to the report:** the file is
  `Sources/EDDCore/ExcerptAnchor.swift`, not under `Boundary/`; and the impact is not only a false
  refusal, since the silent case above succeeds. The other two conventions are unchanged, checked
  end-to-end: a plain file comes back 0 carriage returns / 8 line feeds, a Windows file 8 / 8. Verified by
  undoing each of the three parts and confirming the matching test fails. 759 tests / 92 suites green,
  zero warnings; staged, no commits.
- **2026-08-08 (second) — a check that could not run reported "all clear", and a routine that promised
  to keep a file's permissions gave it different ones.** Five findings; all five real, but **two were
  right about the symptom and wrong about why**, which changed both fixes. (1) **The pointer check
  answered "clean" when it had not looked.** Before reading a file the tool asks two things: that the
  file really sits inside the project once every pointer is followed, and separately that no part of the
  path *is* a pointer — the second matters because the first looks at a path with all pointers already
  resolved and so can never see one. That second walk required one path to start with the other as
  **text**, and answered "no pointer found" when it did not. Two spellings of one folder are ordinary
  here, since `/tmp` is itself a pointer to `/private/tmp`; measured, a real pointer inside a folder was
  reported when the folder was written one way and **not reported** when written the other. The finding
  called this fragile and hard to reach and blamed letter case; the reachable route needs no case
  mismatch at all, and reporting "clean" when a security check did not run is the fail-open shape OWASP
  names by that name. Where the folder sits is now settled by asking the filesystem which ancestor *is*
  it — device and file number, immune to spelling, case and aliases — while the walk itself stays on the
  path as written, because a resolved path has its pointers already followed and so cannot contain one.
  **A third outcome fell out of the fix**, and one caller found it for us: a folder that is simply not
  there and a folder we were refused sight of are different questions. Nothing can exist below the first,
  so "clean" is true and callers legitimately ask about paths not yet created; the second might hold
  anything. Collapsing them broke a caller, which is how the distinction got noticed. (2) **Replacing a
  file that is a pointer gave it the wrong permissions.** The finding said the permission read follows
  the pointer; measured, it does not — it returns the *pointer's* own mode, always `755` here. So a
  private `600` file's path ended up holding a world-readable `755` file while the private file itself
  sat untouched. Nothing escaped, since renaming over a name never writes through a pointer; what was
  untrue was the routine's promise to keep the permissions the file already had. It now refuses a pointer
  outright — turning someone's pointer into an ordinary file is a surprise on its own terms. Stated
  plainly in the code and here: this is a check, not a closed race, because a pointer swapped in between
  the check and the rename would still be replaced. (3) **An empty project could be told to review
  findings it does not have.** The empty-project branch returned only when the recording command was
  registered; otherwise it fell through to advice about reading findings. Whether one command exists
  cannot decide whether a different sentence is true. (4) **Draft names that name nothing, or contain a
  space.** `.json` and `...json` were accepted, naming nothing you could pick out of a folder listing,
  and so were names with spaces — which break the apply command the tool prints for you to paste, since
  a shell reads it as two arguments. Both refused now. Hidden names such as `.draft.json` still work: an
  earlier round removed a blanket leading-dot rejection deliberately, so this narrows that rather than
  reversing it. A leading hyphen turned out to be already handled by the argument parser, so no change
  there. (5) **A run producing nothing says `written`, and that stays.** It reports what happened to the
  *file*, and a file genuinely was written; the field answering "is there anything here" is the edit
  count, at zero, which is how structured output conventionally reports an empty result. Adding a second
  field would duplicate a signal that already exists, so the gap was documentation and the fix is
  documentation — in the field's own description and in [Specs/018 §5b](../018-draft-edit-proposals/plan.md).
  **Two things without tests, stated rather than glossed:** the empty-project fix (3), because the
  command list is fixed when the tool is built and no test target can reach inside the executable to
  substitute one — the function already takes a substitute list at `TriageCommand.swift:292` that nothing
  supplies, which is how the gap survived; and the pointer refusal (2), because every caller rejects a
  pointer earlier, so the refusal cannot be reached from the command line. **One of my own tests passed
  for the wrong reason** and was rewritten: it named a folder outside the project, so the escape check
  answered first and the code it was meant to cover never ran. Verified by undoing each fix and
  confirming the matching test fails. 754 tests / 92 suites green, zero warnings; staged, no commits.
- **2026-08-08 — a rejection named a flag you never typed, and the previous round's advice fix was
  finished.** Applying and drafting share one rule for naming a draft file, so one function checks it —
  but its message hard-coded `--out`, meaning `--proposals badname` answered `--out 'badname' must end in
  .json` and sent you to look at a flag that was not on your command line. Reproduced; the flag is now
  supplied by whichever job is running. Separately, the cause-matched advice added last round had reached
  only two of the six places that turn a declined read into a rejection, so four still advised correcting
  a file's contents when the problem was that a path pointed outside the project; the conversion now
  lives with the refusal itself so the advice cannot be left behind again. Both were found while checking
  a review of the drafting half — **full detail, and the four other findings from that round, are in
  [Specs/018 §10](../018-draft-edit-proposals/plan.md#10-status-log)** (2026-08-08). 746 tests / 91
  suites green, zero warnings; staged, no commits.
- **2026-08-07 (fourth today) — one failure wore another's clothes, and a whole class of rejections gave advice
  about the wrong thing.** A review round of six findings; four checked out with nothing to fix, and were
  confirmed by reproduction rather than by reading — hostile settings values (`../evil`, `/etc`,
  `skills/../../evil`) are all refused, and the file-creation and text-matching rules behave as described.
  Two were real. (1) **Running out of time and never starting read identically.** Both version-control
  checks reported every failure as "could not be run", though a distinct signal for the time limit
  already existed and was being discarded. Those need opposite responses — raise the limit, versus fix or
  install the program — and the well-known trap is exactly this one, a program that could not start
  reported as a timeout, which sends you tuning limits on something that was never going to run. The two
  are now separate, and everything that is not a timeout carries the system's own words. Asking those
  errors for a "localized description" turned out to yield the placeholder "The operation couldn't be
  completed", naming nothing, so they are interpolated directly. (2) **The time limit was too tight for
  what it guards.** It was 30 seconds. The check costs 0.01 seconds here, but the published worst case for
  this command is around 18 seconds, of which 6 is listing files version control has never seen — the
  expensive mode this tool asks for deliberately, after that listing's absence let it overwrite unsaved
  work. Under twice the known worst case is thin, and the harms are lopsided: waiting longer is an
  annoyance, being refused a write that would have succeeded means the command does not work for you.
  Now 120 seconds, raisable with `SKILLET_GIT_TIMEOUT_SECONDS`, which the timeout message names so the
  way out is visible when you need it. **No value means "wait forever"** — a check you cannot rely on
  finishing is not one to build an irreversible write on. (3) **Rejections advised fixing a schema when
  no schema was involved.** One fixed line — "fix or regenerate the file so it matches its schema (see
  skillet-design §7)" — was attached to all 27 places a file is rejected, including four that reject a
  path for pointing somewhere else on disk, a folder that turned out to be a file, and a name that does
  not match. It also cited an internal design document to end users. The rejection now takes optional
  advice; the standard line stays for the majority, where it is right. Two mechanisms, because there are
  two sources of truth: the nine places that know their own cause supply it directly, and the read-refusal
  type supplies its own for the several places that wrap one, so "escapes its base directory" advises
  replacing the link everywhere it surfaces rather than at each wrapping site separately. Existing spelling
  kept working via a two-argument overload, so the 18 places that never needed advice were not touched.
  (4) **The draft read moved to the path-confined call**, matching the read of the same folder a few
  hundred lines above it. Nothing observable changes — hence, honestly, **no test can fail for it**, which
  the revert check confirmed. It is defense in depth: the ordinary reason to repeat a check an earlier
  layer already made is so that no single missing check is the only thing standing between a crafted
  layout and a read outside the project. The other seven unconfined reads were audited without changing
  any of them; the table is in §8. **Two process notes worth keeping.** Adding a third value to a
  rejection changed that type's memory layout, and the incremental build did not recompile everything —
  the result was not a compile error but tests reading enum payloads under the wrong tag, so
  `.harnessUnauthenticated(harness: "claude-code")` came back as `.usage(message: "claude-code", remedy: "")`.
  A clean rebuild fixed it; the symptom is nonsense values, not a failure to build. Separately, the first
  version of the timeout test used a stand-in that slept 30 seconds against a 1-second limit, and the
  whole suite waited on the abandoned child — the watchdog stops waiting but does not reap. Verified by
  undoing each fix and confirming the matching test fails. 740 tests / 91 suites green, zero warnings;
  staged, no commits.
- **2026-08-07 (third today) — a safety check that could not run was read as a "no", and the advice after it
  named the wrong program.** (1) **The tool told you a committed file was not in version control.**
  Before overwriting a skill file, `--apply` asks git whether that file is tracked, because an untracked
  file cannot be restored afterwards. Any failure to *ask* — git missing, the call refused, the index
  unreadable — was recorded as the answer "not tracked", so the refusal asserted something it had never
  established and advised committing a file that may already be committed. Reproduced with a stand-in
  `git` that fails only that one query. There are three outcomes, not two: tracked, not tracked, and
  could-not-tell. The third now stops the write and says the answer is unknown, reported as a problem
  with the machine (exit code 3, the "your surroundings" code) rather than as a refusal. This is the same
  shape as every other defect in this round of review — code offering two branches where reality has
  three, so the missing case silently lands in whichever branch is the default. (2) **A missing git was
  treated as nothing to object to.** The same check, unable to find git at all, returned "no objection"
  and the write went ahead — a check that cannot run permitting the thing it exists to prevent. Harmless
  only by accident: the neighbouring clean-tree check runs first and stops for the same reason. Both now
  stop. (3) **Every version-control failure ended with sign-in advice.** "Check you are signed in, that
  you are within any usage limits, and that the configured model name is valid" is advice about the paid
  model; it was printed whenever git was the obstacle, including simply running `--apply` outside a
  repository. Pre-existing, not introduced here, and reproduced. Advice for the wrong program is worse
  than none, because it sends you to look where the problem is not; the advice now depends on which
  program failed, matching how these messages already name `claude auth login` for the sign-in case.
  (4) **Replacing a file could quietly change who can read it.** Writing a modified skill file goes to a
  neighbouring temporary file which is then renamed into place, and the original's permissions are read
  first so they carry over. If that read failed, the code moved on with a default and the file silently
  came back readable or writable by different people than before. It now refuses instead. **Verified** by
  undoing each fix and confirming the matching test fails; undoing (1) reproduced the false "is not in
  version control" claim verbatim, and undoing (3) reproduced the sign-in advice. **One test initially
  passed for the wrong reason** and is worth recording: the stand-in `git` was written inside the test
  project, which made the project dirty, so the clean-tree check stopped the run before the code under
  test was ever reached. It now lives outside the project. **No end-to-end test exists for (4)**, honestly:
  both callers read the file immediately before writing it, so the read can only fail in the gap between
  the two, and no test target can reach the executable's internals directly to force it. 737 tests /
  91 suites green, zero warnings; staged, no commits.
- **2026-08-07 (second today) — a mistyped selection blamed the draft, and a replacement could leave a file
  mixing line breaks.** (1) **Naming the same edit twice reported that an edit overlapped itself.**
  Asking to apply edit 0 twice produced "edits 0 and 0 cover overlapping text" and advised applying them
  "one at a time with `--edits`" — the very flag just used. An edit cannot overlap itself, and this is a
  slip in the command rather than a condition of the world, so it now says the edit was named more than
  once and writes nothing. Chosen over quietly collapsing the repeat: there is no external convention
  either way, so it rests on what happens when the guess is wrong — a fumbled second number would write
  the file having applied fewer edits than intended, and undoing a write costs more than retyping.
  (2) **Converting line breaks only worked in one direction.** A replacement carrying Windows line breaks
  was written unchanged into a file using plain ones, leaving it mixing both — reproduced. The giveaway
  was the asymmetry: the conversion already ran when the file used Windows breaks, so the code already
  held the view that a replacement should follow the file; only half the rule existed. Now symmetric,
  which is not a loosening, because a line break has exactly one correct representation in a given file.
  **A consequence worth recording:** a quoted passage carrying Windows breaks against a plain file used
  to be refused and is now simply matched, so a test that asserted the refusal was retargeted at what
  converting genuinely cannot rescue — a file that mixes both conventions and so has no single
  convention to convert to. **Verified** by undoing each fix and confirming its tests fail.

- **2026-08-07 (first today) — a typo could be hidden behind an unrelated problem.** (1) **The same mistyped command
  answered differently depending on something unrelated.** Asking to apply an edit number the draft does
  not have gave a clear "no edit 7" on a clean working copy, but "you have uncommitted changes" when any
  stray file existed — so you fixed the wrong thing and met the real mistake on a second run. The
  convention is that argument checks come before environment checks, and the sharper form of it is to
  check each thing as early as its information allows **but no earlier**. I audited every step against
  that rule: the edit-number check was **the only one out of place**; every other check already runs at
  the first moment its information exists. Moved to immediately after the draft is read, which is when
  the valid range first exists. (2) **One report did not hold as stated.** It said the way an existing
  draft is rewritten "creates a new temp file with default permissions… losing any mode". Tested
  directly: permissions are preserved here, `600` stays `600`. The recommendation still stands for a
  different reason — that behaviour is undocumented and platform-specific — so both writes now share one
  routine, recorded as consistency rather than as fixing a loss. (3) **Testing that surfaced a worse
  defect than the one reported.** A refused write named the internal neighbouring file the write travels
  through — telling you that you lack permission on `.SKILL.md.replacing-E1E6566C-…`, a randomly-named
  file you have never seen — and printed the whole error structure around it. It now names the file you
  asked to write and gives the cause in plain words. (4) **The mismatched error label stays, with its
  meaning written down.** A failed write to your skill file reports the machine-readable label
  `cache_unwritable`. Reuse-first is the guidance for machine-readable error identifiers: a new one is
  minted only when no existing one suits, and here the reaction is identical either way — check
  permissions and disk, retry. The message a person sees never says "cache"; it names the real file. The
  name cannot be changed without breaking anything matching on it, so it is documented as covering any
  write the machine refused rather than given a near-duplicate beside it. (5) **Two near-identical
  permissions tests merged** — one checked a single setting the other already covered among three.
  **Verified** by undoing the two behavioural fixes and confirming their tests fail.

- **2026-08-06 — review round: the safety check could be switched off by a setting, and work was
  destroyed.** (1) **Two ways to lose uncommitted work, both reproduced.** Before writing, the tool asked
  version control for a one-line summary of uncommitted changes and refused if there was any. That summary
  can be muted: the setting `status.showUntrackedFiles=no` — which people enable to make version control
  faster — hides files it is not tracking, so the tool saw a clean tree, overwrote a skill file that had
  never been committed, and `git checkout` could not bring it back. The reported fix (asking for untracked
  files explicitly) closes that route; I found a second it does not — a skills folder listed in the
  project's ignore file is invisible to the same summary, with the same unrecoverable result. Published
  guidance adds a third: per-file markers meaning "pretend this hasn't changed" hide edits to tracked
  files too. **Both the flag and a direct question now run (D12):** is *this file* known to version
  control at all? That is the property that decides whether the change can be undone, and the recognised
  shape for an irreversible operation is to validate the target and confirm an undo path exists rather
  than infer both from ambient state. It also makes the tool's own closing advice true — it tells you to
  review and commit, which assumes version control has your back, and for a file it has never seen it
  does not. The one new refusal is a skill you have not committed yet, which is exactly the case where
  nothing could be restored. (2) **The paid drafting step still had the line-break bug that applying had
  been fixed for.** On a file using Windows line breaks it dropped every multi-line edit as "does not
  appear in SKILL.md" and advised a re-draft, which hit the same wall — **charging for a model call each
  time round**. The translation helpers moved beside the shared match rule in the pure core and both
  halves now use them, which is what decision **D5** (one match rule shared by drafting and applying)
  intended all along. (3) **A redundant unwrap removed.** I suspected the two forms were not equivalent
  and checked before agreeing — Swift collapses the nesting here, so the report was right. **Verified** by
  undoing each of the three fixes and confirming its own tests fail.
- **2026-08-04 — review round: seven real findings, one that did not hold.** (1) **File permissions are
  now carried deliberately rather than inherited by luck.** Writing the edited file replaced it via the
  standard library's atomic write, which happened to preserve permissions on this platform but is not
  guaranteed to. Replacing is now done by the same shape as the existing create-safely helper — write a
  neighbour, put it in place in one step — with **the mode set on the neighbour before the swap**.
  Correcting it afterwards was considered and rejected: the gap is not merely brief, because a process
  that dies inside it leaves the file permanently and silently readable by people the original excluded.
  Rust's package manager shipped exactly this bug and fixed it the same way. **A detail worth recording:**
  the hand-rolled replace does *not* inherit permissions the way the standard library's did, so the
  explicit step is load-bearing — proved by undoing it and watching the pre-existing permissions test
  fail. (2) **A model naming a mix of real and invented evidence had the invented ones removed in
  silence** — hiding fabrication exactly when it is hardest to notice, because the rest of the answer
  looked right. They are now named. The edit is still kept, which follows the practice for partly
  fabricated references: keep what verifies, surface what did not, rather than discard the whole answer.
  (3) **A refusal saying "this version only writes the skill file" was paired with advice to draft
  again**, which cannot help — that case now has its own advice. (4) **The test helper was the only place
  in the entire codebase launching a program through the standard library instead of the one sanctioned
  launcher** the charter requires without exception; converted, and there are now zero such uses. (5)
  **Three small corrections:** a comment claiming the repository check runs before any file is read (it runs
  before the *write*; the draft must be read first to know which skill it belongs to), an unused module
  import, and a written note on why a lone carriage return as a line break — last standard on Mac OS 9 —
  is deliberately not handled. (6) **One finding did not hold.** It reported that building a path from a
  multi-part skills folder setting produces a percent-encoded slash, and recommended a project-wide fix.
  Tested: joining `a/b` onto a path yields `/tmp/proj/a/b`, unencoded, and an end-to-end test named
  `multiSegmentSkillsRootResolves` already proves a nested skills folder works. Recorded here so it is
  not re-raised. **Verified** by undoing each of the three behavioural fixes and confirming its own tests
  fail.
- **2026-08-04 — review round: the exactly-once rule could be broken by ordinary markdown.** (1) **A
  passage matching at overlapping positions was called unique, and the tool silently picked one.** Three
  identical bullet lines is unremarkable markdown; a quoted passage covering two of them matches at two
  places. The scan skipped past each match before looking again, so it found one, declared the passage
  unique, replaced the first and reported success — exactly the ambiguity the whole feature exists to
  refuse. Reproduced end to end. Counting now resumes one character on, so what it measures is **how many
  positions the passage could be replaced at**, which is what the rule has to mean for a tool that
  replaces one of them. Both drafting and applying share the rule, so both got stricter together, and the
  only newly-refused cases are the genuinely ambiguous ones. (2) **The refusal now names where the
  duplicates are.** Best-practice error design says to show the source with the location — but here every
  match has *identical* text by construction, so echoing it would repeat the same line three times and
  add nothing. Line numbers carry all the distinguishing information there is; the list is capped so a
  short repeated passage cannot bury the message. (3) **The advice attached to a refusal now follows its
  cause.** "The file changed since this draft was made" is right for a file that has moved on, useless
  for a passage that is not unique, and wrong for two edits covering the same text — each now gets its
  own remedy. (4) **Every failure from asking git about the repository was reported as "you are not in a
  git repository"** — a confident wrong diagnosis for a damaged index, a permissions problem or a held
  lock, pointing at a remedy that cannot help. git's own words are now reported, keeping the tailored
  explanation only when git itself gives that as the cause. (5) **A skill folder configured as the
  project root produced a path with a leading `./`**; the reported path is now plain project-relative.
  **Verified** by undoing each of the three fixes and confirming its own tests fail.
- **2026-08-04 — review round: the feature did not work on a Windows checkout.** (1) **Every multi-line
  edit was refused there, with advice that could not work.** A file checked out on Windows holds carriage
  returns; a model quotes it back with plain newlines, so nothing lined up — and the tool said "no longer
  in the file — draft again", which sends you round a loop, because re-drafting produces the same
  mismatch. Reproduced, then fixed by **translating the quoted passage into the file's own convention
  before matching** (D9), with the replacement given the same treatment so the file keeps one convention
  throughout. **This is a translation, not a tolerance:** every newline has exactly one correct
  representation in the target file, and after it runs the match is as strict as before. That distinction
  is why only this step of the cascade comparable tools use was adopted — whitespace- and
  indentation-insensitive matching genuinely relax what counts as a match, and this feature's whole
  guarantee is exactly-once-or-refuse. Where translating cannot rescue it, the refusal now names which
  side carries the carriage returns instead of blaming drift, because the remedies are entirely
  different. (2) **Two shared flag descriptions still described only drafting**, including one that
  promised applying would "cost" something; both now cover each job, and the subset flag says its numbers
  start at zero. (3) **The design document showed the pre-implementation flag spelling in five places**
  (the finding named two) — corrected to what shipped, since that spelling was forced by the
  argument-parsing library and already settled. (4) **The contributor guide's status banner** gains the
  new capability; **the plan's own test-plan line** was still written in the old spelling. (5) **A helper
  with no callers** was removed. (6) **Two coverage gaps closed:** a valid subset is now driven through
  the command line, and file permissions are pinned across the write — verified preserved here, so a
  difference on the other build platform will surface as a failure rather than a surprise. **Noted, not
  built:** when a match fails, comparable tools show the closest actual text, which would make a drift
  refusal far more useful than naming the missing passage — worth its own round. **Verified** by undoing
  the translation and confirming its tests fail.
- **2026-08-04 — review round: a preview flag that wrote anyway.** (1) **`--apply --dry-run` applied the
  edits and reported success.** The dispatcher routed to the apply path before the preview flag was read,
  so the one flag that means "change nothing" changed the file. Reproduced, then fixed as a **real
  preview** rather than by refusing the combination: the two tools closest to this — the standard patch
  tool's applicability check, and the container tooling's server-side preview — both run the entire real
  path and simply do not persist, and neither treats previewing as an error. Two details taken from them:
  the exit status answers "would a real run succeed right now?", so it is scriptable; and a preview
  reports **every** blocker rather than the first, since only a run about to write has a reason to stop
  early. (2) **The command's own help said it "applies nothing"** a few lines above the flag that applies
  things; rewritten to describe both jobs, keeping the absolute promise that nothing is ever committed or
  staged. (3) **Both user guides and the contributor guide** still described applying as unbuilt; the
  how-to gains the apply step, the tutorial's cost table gains a row (applying is free), and the
  contributor guide's entry is corrected. (4) **A read limit named after one of its two uses** — it
  bounded both a saved draft and the skill file — renamed to say what it bounds. (5) **The plan's step
  order was corrected to match the code**, not the other way round: see step 1. **Verified** by undoing
  the preview branch and confirming the tests fail. 
- **2026-08-04 — implemented.** Reviewed before writing code, which surfaced two decisions the plan
  could not have anticipated and one instruction in it that was wrong. **The wrong instruction:** it said
  the modified file is written through the routine used elsewhere for creating files — a routine whose
  entire purpose is refusing to replace anything. Applying overwrites by design, so it uses an atomic
  replace, with the clean-repository rule providing the undo. **D6** gave applying its own machine-readable
  format rather than reusing the drafting one, whose fields describe an event that did not happen here.
  **D7** followed from testing the argument parser: an option always requires a value, so the planned
  `--apply[=<indices>]` spelling is not expressible. **The regression discipline earned its keep:** undoing
  the splice ordering hung the test run rather than failing it, exposing that the implementation reused
  string positions after mutating the string — undefined behaviour that happened to work. 706 tests / 91
  suites green, zero warnings; staged, no commits.
- **2026-08-02 — planned.** Three unknowns resolved through Q&A. The clean-repository rule was checked
  against the project charter first and turns out to be a binding MUST rather than a preference, so
  the strict reading ships and any loosening is an amendment with evidence behind it. Scope was held
  to one file after establishing that extraction is blocked on the drafting side, so building only the
  applying half would deliver nothing usable. All-or-nothing was chosen over partial application on
  two grounds: the failure state needs no undo, and a silent partial apply produces a measured result
  that misrepresents what was applied — a false negative that throws away a correct fix.
