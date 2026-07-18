import Foundation

/// A **machine-mined** evidence note (design §7.3): the shared `EvidenceHeader` plus how it was surfaced
/// (`source`), how sure the miner is (`confidence`), and the raw `signal`/`cluster`. Tagged
/// `skillet.finding/1`. `source`/`confidence` are **required** — a machine finding without them is
/// meaningless, which is why finding is a distinct type from friction rather than a superset (D2).
public struct Finding: Evidence {
    public static let schema = "skillet.finding/1"
    public var header: EvidenceHeader
    public var source: FindingSource
    public var confidence: Confidence
    public var cluster: String?
    public var signal: String?

    public init(header: EvidenceHeader, source: FindingSource, confidence: Confidence,
                cluster: String? = nil, signal: String? = nil) {
        self.header = header; self.source = source; self.confidence = confidence
        self.cluster = cluster; self.signal = signal
    }

    private enum Keys: String, CodingKey { case schema, source, confidence, cluster, signal }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        header = try EvidenceHeader(from: decoder)   // header flat from the top-level container
        source = try c.decode(FindingSource.self, forKey: .source)
        confidence = try c.decode(Confidence.self, forKey: .confidence)
        cluster = try c.decodeIfPresent(String.self, forKey: .cluster)
        signal = try c.decodeIfPresent(String.self, forKey: .signal)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(Self.schema, forKey: .schema)   // schema first
        try header.encode(to: encoder)               // then the shared header fields
        try c.encode(source, forKey: .source)        // then the finding-only fields
        try c.encode(confidence, forKey: .confidence)
        try c.encodeIfPresent(cluster, forKey: .cluster)
        try c.encodeIfPresent(signal, forKey: .signal)
    }
}
