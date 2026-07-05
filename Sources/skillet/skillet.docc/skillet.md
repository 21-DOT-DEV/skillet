# Skillet

The SKILL.md Evaluation Toolkit — eval-driven development for agent skills.

@Metadata {
    @TechnologyRoot
}

## Overview

`skillet` measures whether a `SKILL.md` actually works. It runs a skill's behavioral evals *k* times
through a harness, grades each expectation with a judge, and reports a `pass^k` consistency score — so
a skill change ships only after a previously-failing eval proves it, with a human landing every commit.

The eval-driven loop is **adopt** (`init`) → **measure** (`run`, repeated *k*× for `pass^k`) →
discover → interpret → fix-and-prove → re-measure, with the free static gate (`lint`) in front of every
paid `run`. Phase 1 ships `init`, `lint`, `run`, and `harness`; Phase 2 has begun with `doctor` — the
free $0 preflight (config, harness resolution, skill visibility, lint) — and the rest lights up across
the roadmap.

## Topics

### Guides

- <doc:TestingEndToEnd>
