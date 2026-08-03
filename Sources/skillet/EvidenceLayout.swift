import Foundation
import EDDCore
import ProjectKit

/// Where a skill's evidence lives, and whether that layout is actually intact.
///
/// **Detection is shared; the reaction is not.** Both commands need the same answer to "is a plain file
/// sitting where one of these folders belongs?" — but they must respond differently: the clustering
/// command reports it and carries on (it is a report, and one broken folder shouldn't suppress the rest),
/// while drafting has to stop, because it cannot read the evidence it was asked for. Sharing the rule and
/// keeping each command's handling local is the split that fits; folding the handling in too would mean
/// parameters and branches to serve two callers.
enum EvidenceLayout {
    /// The folders a skill is expected to have, in the order a person would look for them.
    static func expectedFolders(skillDir: URL) -> [(label: String, url: URL)] {
        let evaluations = skillDir.appendingPathComponent("evaluations")
        return [("evaluations", evaluations),
                ("evaluations/sessions", evaluations.appendingPathComponent("sessions")),
                ("evaluations/findings", evaluations.appendingPathComponent("findings")),
                ("evaluations/friction", evaluations.appendingPathComponent("friction"))]
    }

    /// Every expected folder that exists but is a plain file. Absent folders are fine — nothing has been
    /// recorded yet. **The parent is included deliberately:** when `evaluations` itself is a file, the
    /// paths *inside* it don't exist, so a check that only inspects the children finds nothing wrong and
    /// the command ends up reporting "no such evidence" — true, useless, and it hides the real problem.
    static func misshapen(skillDir: URL) -> [(label: String, url: URL)] {
        expectedFolders(skillDir: skillDir).filter { _, url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && !isDirectory.boolValue
        }
    }

    /// The evidence ids currently on disk for a skill — the `.md` stems under `findings/` and `friction/`,
    /// de-duplicated and sorted. Used to tell someone what they *could* have named.
    static func availableIDs(skillDir: URL) -> [String] {
        let evaluations = skillDir.appendingPathComponent("evaluations")
        var ids = Set<String>()
        for folder in ["findings", "friction"] {
            let dir = evaluations.appendingPathComponent(folder)
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in entries where name.hasSuffix(".md") && !SafeFile.isHidden(name) {
                // A shortcut is refused by the reader, so listing it as something you could name offers
                // a choice that fails the moment it is taken.
                guard !SafeFile.isSymlink(dir.appendingPathComponent(name)) else { continue }
                ids.insert(String(name.dropLast(3)))
            }
        }
        return ids.sorted()
    }
}
