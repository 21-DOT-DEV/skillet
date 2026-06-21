/// The `--json` payload for `skillet init`: what the command created vs. skipped, and the skills it
/// scaffolded. Created/skipped are repo-relative paths.
public struct InitReport: SchemaIdentified, Sendable, Equatable {
    public static let schema = "skillet.init/1"
    public let created: [String]
    public let skipped: [String]
    public let skills: [String]

    public init(created: [String], skipped: [String], skills: [String]) {
        self.created = created
        self.skipped = skipped
        self.skills = skills
    }
}
