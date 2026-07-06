import Foundation
import EDDCore
import HarnessKit

/// The one shared answer to "can this skill's trigger-test file actually run?" — used by **both**
/// `run` (to load cases) and `doctor` (to predict `run`), so the two can never disagree again.
/// Factored after F14 review round 3 (decided in-session): the health check's private copy of this
/// judgment drifted from the runner's twice in a row — first on case validity, then on symlink
/// handling — and each drift shipped as a false-green prediction. Same drift-proofing precedent as
/// the shared lint-input assembly in `LintSupport`.
enum TriggerEvalsLoad {
    /// No `evaluations/trigger-eval.json` — the axis simply doesn't exist for this skill.
    case absent
    /// The file exists and parses but contains zero cases — nothing to run.
    case empty
    /// The file exists but the runner would refuse it: undecodable, an invalid case, or a
    /// symlinked path (the runner never follows symlinks on its read paths).
    case invalid(reason: String)
    case usable([(id: String, query: String, shouldTrigger: Bool)])
}

func loadTriggerEvals(skillDir: URL) -> TriggerEvalsLoad {
    let evaluations = skillDir.appendingPathComponent("evaluations")
    let url = evaluations.appendingPathComponent("trigger-eval.json")
    // Symlink check FIRST (lstat semantics, doesn't follow): the follow-the-link exists check calls
    // a DANGLING symlink "absent", but the entry exists and `run` refuses it — checking in the other
    // order shipped exactly that false green (review round 6). Mirror `run`'s read-path guard: a
    // symlinked evaluations/ or trigger file is refused, never followed.
    guard !SkillBundleRules.isSymlink(evaluations), !SkillBundleRules.isSymlink(url) else {
        return .invalid(reason: "evaluations/ or trigger-eval.json is a symlink (not allowed)")
    }
    guard FileManager.default.fileExists(atPath: url.path) else { return .absent }
    guard let data = try? Data(contentsOf: url),
          let file = try? JSONDecoder().decode(TriggerEvalFile.self, from: data) else {
        return .invalid(reason: "not valid trigger-eval.json (a JSON array of {query, should_trigger})")
    }
    // Validate the RAW array, not the codec's `cases` accessor: the frozen codec deliberately
    // preserves-and-skips non-object elements for round-tripping, but at run time a junk element is
    // an authoring error the user must hear about — silently dropping it would also shift every
    // later case's positional id (review round 4, finding 1).
    let elements = file.raw.arrayValue ?? []
    guard !elements.isEmpty else { return .empty }
    var loaded: [(id: String, query: String, shouldTrigger: Bool)] = []
    for (index, element) in elements.enumerated() {
        guard let fields = element.objectValue else {
            return .invalid(reason: "element #\(index) is not an object ({query, should_trigger})")
        }
        let triggerCase = TriggerCase(fields: fields)
        guard let query = triggerCase.query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty,
              let shouldTrigger = triggerCase.shouldTrigger else {
            return .invalid(reason: "case #\(index) needs a non-empty `query` and a boolean `should_trigger`")
        }
        loaded.append((id: "trigger-\(index)", query: query, shouldTrigger: shouldTrigger))
    }
    return .usable(loaded)
}
