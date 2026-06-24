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
| 005 | Free static lint — error-tier core (`skillet lint`) | 1 · F4 | Planned | [plan.md](005-free-static-lint/plan.md) |
