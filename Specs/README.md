# Specs

Feature specs, **spec-kit-aligned but lightweight**: one numbered folder per feature
(`NNN-slug/`) with a canonical `plan.md` inside. We keep spec-kit's *folder convention* (so the
`speckit.*` workflow could be adopted later with no file moves) but skip its scripts/templates
machinery and create only the files we actually use. Each plan's roadmap **phase / feature mapping
lives in its header**, not the path — the spec number is a stable global counter, independent of
roadmap re-phasing.

> **Casing note:** this directory is intentionally `Specs/` (capitalized, matching `Roadmap/`).
> spec-kit's scripts default to lowercase `specs/`, so adopting that tooling later would need the
> path adjusted.

| # | Feature | Phase | Status | Plan |
|---|---|---|---|---|
| 001 | Project discovery & output contract | 1 · F1 | Implemented | [plan.md](001-project-discovery-output-contract/plan.md) |
| 002 | Adopt skillet in a repo (`skillet init`) | 1 · F2 | Implemented | [plan.md](002-adopt-skillet-repo/plan.md) |
| 003 | Normalized trace & harness-adapter seam | 1 · F5 | Implemented | [plan.md](003-normalized-trace-harness-seam/plan.md) |
| 004 | claude-code adapter (trace parser, resolution & probe) | 1 · F6 | Implemented | [plan.md](004-claude-code-adapter/plan.md) |
| 005 | Free static lint — error-tier core (`skillet lint`) | 1 · F4 | Implemented | [plan.md](005-free-static-lint/plan.md) |
| 006 | Frozen boundary-format codecs + golden tests | 1 · F8 | Implemented | [plan.md](006-frozen-boundary-codecs/plan.md) |
| 007 | The neutral runner — behavioral axis + `pass^k` (`skillet run`) | 1 · F7 | Implemented | [plan.md](007-neutral-runner/plan.md) |
| 008 | $0 preflight & skill-visibility check (`skillet doctor`) | 2 · F3 | Implemented | [plan.md](008-doctor-preflight/plan.md) |
| 009 | The trigger axis — description-fires-skill measurement (`skillet run --axis trigger`) | 2 · F14 | Implemented | [plan.md](009-trigger-axis/plan.md) |
| 010 | The A/B baseline arm — paired with/without-skill Δ (`skillet run --ab`) | 2 · F15 | Implemented | [plan.md](010-ab-baseline/plan.md) |
| 011 | The grounded judge — file-contents grading (`skillet run --judge grounded-judge`) | 2 · F16 | Implemented | [plan.md](011-grounded-judge/plan.md) |
| 012 | Deterministic scorers → SARIF (`skillet score`) | 2 · F17 | Implemented | [plan.md](012-deterministic-scorers/plan.md) |
| 013 | Capture a session as evidence (`skillet capture`) | 3 · F26 | Implemented | [plan.md](013-capture-session-evidence/plan.md) |
| 014 | Capture secret-sanitization (`skillet capture` redact-by-default) | 3 · F32 | Implemented | [plan.md](014-capture-secret-sanitization/plan.md) |
| 015 | Structured friction & finding evidence + lifecycle (`skillet.friction/1` / `skillet.finding/1`) | 3 · F29 | Implemented (2026-07-17) | [plan.md](015-friction-finding-evidence/plan.md) |
