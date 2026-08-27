# Skillet

The SKILL.md Evaluation Toolkit — eval-driven development for agent skills.

@Metadata {
    @TechnologyRoot
}

## Overview

`skillet` answers one question: does this `SKILL.md` actually work? It runs a skill's behavioural
tests repeatedly through a real agent, grades each expectation, and reports how often the skill got
it right *every* time — so a change ships only after a previously-failing test proves it, with a
human landing every commit.

The loop it supports:

- **Adopt** — `init` sets a project up.
- **Measure** — `run` scores the skill; `lint`, `doctor` and `score` check things for free first.
- **Discover** — `capture` records real sessions as scrubbed, scored evidence.
- **Interpret** — `triage` groups what went wrong into categories, free.
- **Fix and prove** — `suggest` drafts a minimal edit from that evidence; you apply it and re-measure.

Most of that costs nothing. Only running trials and drafting an edit call a model, and both tell you
what they will cost before they do it.

### Commands

| Command | What it does | Cost |
|---|---|---|
| `init` | Adopt skillet in a project. | free |
| `doctor` | Preflight: configuration, agent, skill visibility, static gate. | free |
| `lint` | Static analysis of the skill source. | free |
| `score` | Deterministic checks over text an agent produced. | free |
| `harness` | Inspect the available agent adapters. | free |
| `capture` | Record a session as scrubbed, scored evidence. | free |
| `triage` | Group recorded failures into categories. | free |
| `run` | Run the skill's tests and report the score. | paid |
| `suggest` | Draft a minimal skill edit from evidence. | paid |
| `iterate` | Prove a reviewed edit by measuring the skill before and after it. | paid |

`skillet --help` is authoritative for the current surface, including flags.

## Topics

### Learning

- <doc:TryingItForFree>

### Doing the work

- <doc:MeasuringASkill>
- <doc:TurningEvidenceIntoAFix>
