/// The canonical, commented `skillet.yaml` emitted by `skillet init`.
///
/// Written as **text** (not via `swift-yaml`) on purpose: `init` only *writes* config, and the
/// documented comments must survive — `swift-yaml` can't preserve them on re-emit (design §5.2).
/// `swift-yaml` is wired in only when a feature must *parse* config.
public enum SkilletConfigTemplate {
    public static func contents(skillsRoot: String = "skills") -> String {
        """
        # skillet.yaml — created by `skillet init`, committed to the repo.
        # Full configuration reference: skillet-design.md §5.2.

        project:
          skills_root: \(skillsRoot)        # glob roots for SKILL.md discovery

        runs:
          k: 3                              # trials per eval
          concurrency: 1                    # >1 is a deliberate choice, not a default
          confirm_above_trials: 25          # estimate + confirm beyond this (TTY)
          timeout: "10m"                    # per-trial watchdog
          infra_retries: 1                  # retry harness/network only — never judged failures
          max_output_bytes: 67108864        # cap on a trial's captured stdout/stderr (64 MiB)

        harness:
          default: claude-code
          matrix: [claude-code, opencode]

        judge:
          provider: claude-code             # adapter id with the judging capability (Phase 1: shells the claude CLI)
          model: claude-sonnet-4-6          # required — paid runs refuse without an explicit judge model (design §14-4)

        # The methodology's numbers, shipped as defaults, tunable per repo.
        gates:
          codify:
            min_evidence: 3
            same_root_cause: 2
          prose_edit:
            min_sessions: 3
            min_domains: 2
          judge_only:
            min_sessions: 3
            min_domains: 2

        scorers:
          vendored_prefixes: ["Vendored/", "Generated/"]
          vocab:
            exempt: []

        lint:
          disable: []
          body_warn_lines: 500
          body_error_lines: 1000
        """
    }
}
