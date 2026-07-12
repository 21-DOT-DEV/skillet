import Foundation

/// One secret `betterleaks` detected in scanned text, decoded from its **PascalCase** JSON report
/// (`RuleID`/`Secret`/`Match`/`File`) — verified against betterleaks 1.6.1 (the config-DSL's lowercase
/// `finding["secret"]` accessors are a *different* surface; the report is Go-struct PascalCase).
///
/// `secret` is the credential itself — what we redact. `match` is the credential **plus** surrounding
/// context and is never used for redaction (it would over-scrub the line). `file` carries the
/// `--set-attr path=` label, so a finding can be dropped when its artifact is exempt.
public struct Finding: Decodable, Sendable, Equatable {
    public let ruleID: String
    public let secret: String
    public let match: String
    public let file: String

    public init(ruleID: String, secret: String, match: String = "", file: String = "") {
        self.ruleID = ruleID
        self.secret = secret
        self.match = match
        self.file = file
    }

    enum CodingKeys: String, CodingKey {
        case ruleID = "RuleID"
        case secret = "Secret"
        case match = "Match"
        case file = "File"
    }

    // Tolerant decode: `RuleID`/`Secret` are required; `Match`/`File` default to "" if a future/edge
    // report omits them, so one odd finding never fails the whole scan (which would fail closed).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ruleID = try c.decode(String.self, forKey: .ruleID)
        secret = try c.decode(String.self, forKey: .secret)
        match = try c.decodeIfPresent(String.self, forKey: .match) ?? ""
        file = try c.decodeIfPresent(String.self, forKey: .file) ?? ""
    }
}
