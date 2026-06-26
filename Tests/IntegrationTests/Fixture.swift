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

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
