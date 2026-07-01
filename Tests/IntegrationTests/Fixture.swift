import Foundation

/// Builds throwaway, per-test project directories so integration tests are isolated and
/// parallel-safe. Each call returns a unique temp directory; remove it with `defer`.
enum Fixture {
    static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillet-it-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A temp directory containing a `skillet.yaml` marker — a discoverable project root.
    static func makeProject() throws -> URL {
        let root = try makeTempDirectory()
        try "project:\n  skills_root: skills\n".write(
            to: root.appendingPathComponent("skillet.yaml"),
            atomically: true,
            encoding: .utf8
        )
        return root
    }

    /// A temp repo containing `skills/<name>/SKILL.md` (a discoverable skill), no `skillet.yaml` yet.
    static func makeRepoWithSkill(_ name: String = "demo") throws -> URL {
        let root = try makeTempDirectory()
        let skill = root.appendingPathComponent("skills/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try "# \(name)\n".write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return root
    }

    /// A discoverable project (`skillet.yaml`) with one skill — frontmatter built from `description`,
    /// plus `evals` eval cases (nil = no `evals.json`) — for exercising `skillet lint`.
    static func makeLintRepo(
        skill: String = "demo",
        description: String,
        body: String = "# demo\nbody\n",
        evals: Int? = 3
    ) throws -> URL {
        let root = try makeTempDirectory()
        try "project:\n  skills_root: skills\n".write(
            to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8
        )
        let dir = root.appendingPathComponent("skills/\(skill)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "---\nname: \(skill)\ndescription: \(description)\n---\n\(body)".write(
            to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        if let evals {
            let evalDir = dir.appendingPathComponent("evaluations", isDirectory: true)
            try FileManager.default.createDirectory(at: evalDir, withIntermediateDirectories: true)
            let cases = (0..<evals).map { #"{"id":\#($0),"prompt":"p\#($0)","expectations":["x"]}"# }.joined(separator: ",")
            try #"{"skill_name":"\#(skill)","evals":[\#(cases)]}"#.write(
                to: evalDir.appendingPathComponent("evals.json"), atomically: true, encoding: .utf8
            )
        }
        return root
    }

    /// A discoverable project with one skill ready for `skillet run`: SKILL.md + `evaluations/evals.json`
    /// (skill-creator 2.0 form). `harnessPath` pins `harness.claude-code.path` (for exit-3 probe tests);
    /// `evalsRaw` overrides the generated evals.json verbatim (for corrupt-artifact tests).
    static func makeRunRepo(
        skill: String = "demo",
        evals: [(id: String, expectations: [String])] = [("e1", ["did the thing"])],
        harnessPath: String? = nil,
        judgeProvider: String? = nil,
        evalsRaw: String? = nil
    ) throws -> URL {
        let root = try makeTempDirectory()
        var yaml = "project:\n  skills_root: skills\n"
        if let harnessPath { yaml += "harness:\n  claude-code:\n    path: \(harnessPath)\n" }
        if let judgeProvider { yaml += "judge:\n  provider: \(judgeProvider)\n" }
        try yaml.write(to: root.appendingPathComponent("skillet.yaml"), atomically: true, encoding: .utf8)

        let dir = root.appendingPathComponent("skills/\(skill)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("evaluations"), withIntermediateDirectories: true)
        try "---\nname: \(skill)\ndescription: a demo skill for run integration tests\n---\nBody.\n"
            .write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let evalsJSON: String
        if let evalsRaw {
            evalsJSON = evalsRaw
        } else {
            let cases = evals.map { c in
                let exps = c.expectations.map { "\"\($0)\"" }.joined(separator: ",")
                return "{\"id\":\"\(c.id)\",\"prompt\":\"do it\",\"expectations\":[\(exps)]}"
            }.joined(separator: ",")
            evalsJSON = "{\"skill_name\":\"\(skill)\",\"evals\":[\(cases)]}"
        }
        try evalsJSON.write(to: dir.appendingPathComponent("evaluations/evals.json"), atomically: true, encoding: .utf8)
        return root
    }

    /// Write a `criterion → passed` replay verdict map (the hidden test-only judge seam); return its path.
    static func writeReplayMap(_ map: [String: Bool], in root: URL) throws -> String {
        let entries = map.map { "\"\($0.key)\":\($0.value)" }.joined(separator: ",")
        let url = root.appendingPathComponent("replay-map.json")
        try "{\(entries)}".write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
