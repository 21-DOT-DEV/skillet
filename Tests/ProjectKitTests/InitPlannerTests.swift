import Testing
import Foundation
import ProjectKit

@Suite("Init planning")
struct InitPlannerTests {
    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }
    private func rel(_ url: URL, _ root: String) -> String {
        let path = url.standardizedFileURL.path
        return path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path
    }

    @Test("Fresh repo with one skill plans config, cache ignore, and per-skill evidence dirs")
    func freshRepo() {
        let plan = InitPlanner(probe: InMemoryProbe()).plan(
            root: url("/repo"), skillsRoot: "skills", skills: [url("/repo/skills/docc")]
        )
        let created = Set(plan.actions.map { rel($0.url, "/repo") })
        #expect(created.contains("skillet.yaml"))
        #expect(created.contains(".skillet"))
        #expect(created.contains(".skillet/.gitignore"))
        #expect(created.contains("skills/docc/evaluations"))
        #expect(created.contains("skills/docc/evaluations/friction"))
        #expect(created.contains("skills/docc/evaluations/friction/.gitignore"))
        #expect(created.contains("skills/docc/evaluations/findings"))
        #expect(created.contains("skills/docc/evaluations/sessions"))
        #expect(plan.skipped.isEmpty)
        #expect(plan.skills == ["docc"])
    }

    @Test("A JSON-special skill name still scaffolds VALID evals.json (round 6 — no injection)")
    func jsonSpecialSkillName() throws {
        let weird = #"we"ird\name"#
        let plan = InitPlanner(probe: InMemoryProbe()).plan(
            root: url("/repo"), skillsRoot: "skills", skills: [url("/repo/skills/\(weird)")]
        )
        let action = plan.actions.first {
            if case let .writeFile(target, _) = $0 { return target.lastPathComponent == "evals.json" }
            return false
        }
        guard case let .writeFile(_, contents) = action else {
            Issue.record("no evals.json skeleton planned")
            return
        }
        let object = try JSONSerialization.jsonObject(with: Data(contents.utf8)) as? [String: Any]
        #expect(object?["skill_name"] as? String == weird)   // escaped on write, intact on read
        #expect((object?["evals"] as? [Any])?.isEmpty == true)
    }

    @Test("Existing skillet.yaml is skipped, not recreated (idempotency)")
    func skipsExistingConfig() {
        var probe = InMemoryProbe()
        probe.entries = ["/repo": ["skillet.yaml"]]
        let plan = InitPlanner(probe: probe).plan(root: url("/repo"), skillsRoot: "skills", skills: [])
        #expect(!plan.actions.contains { $0.url.lastPathComponent == "skillet.yaml" })
        #expect(plan.skipped.contains { $0.lastPathComponent == "skillet.yaml" })
    }

    @Test("Empty repo plans skillet.yaml and an empty skills/ root, no per-skill dirs")
    func emptyRepo() {
        let plan = InitPlanner(probe: InMemoryProbe()).plan(root: url("/repo"), skillsRoot: "skills", skills: [])
        let created = Set(plan.actions.map { rel($0.url, "/repo") })
        #expect(created.contains("skillet.yaml"))
        #expect(created.contains("skills"))
        #expect(!created.contains { $0.contains("evaluations") })
        #expect(plan.skills.isEmpty)
    }
}
