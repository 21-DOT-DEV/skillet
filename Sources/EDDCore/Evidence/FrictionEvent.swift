import Foundation

/// A **human-logged** friction event — "I had to hand-fix the skill's output" (design §7.3). It is
/// exactly the shared `EvidenceHeader`; the `skillet.friction/1` schema tag distinguishes it from a
/// `Finding`. On the wire the header fields sit at the **top level** of the frontmatter (flattened), so
/// `encode`/`init(from:)` splice the schema tag around the header rather than nesting it under a key.
public struct FrictionEvent: Evidence {
    public static let schema = "skillet.friction/1"
    public var header: EvidenceHeader

    public init(header: EvidenceHeader) { self.header = header }

    private enum SchemaKey: String, CodingKey { case schema }

    public init(from decoder: any Decoder) throws {
        // The seam's dispatch already matched `schema`; decode the header flat from the top-level container.
        header = try EvidenceHeader(from: decoder)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: SchemaKey.self)
        try c.encode(Self.schema, forKey: .schema)   // schema first (the discriminator)
        try header.encode(to: encoder)               // then the header fields, at the same top level
    }
}
