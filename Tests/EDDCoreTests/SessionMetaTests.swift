import Testing
import Foundation
@testable import EDDCore

@Suite("SessionMeta — frozen record codec (RawJSONObject)")
struct SessionMetaTests {
    // Synthetic fixture mirroring the real corpus shape (constitution VI — no real artifacts committed).
    static let v2JSON = #"""
    {"captured_at":"2026-05-24T10:09:39Z","harness":"claude-code","id":"2026-05-24-x","model":"claude-opus-4-8","sanitization":{"redactions":2,"scanner":"betterleaks","version":"1.6.1"},"schema_version":2,"skill":"docc-articles","skill_version":"1.3.0"}
    """#

    @Test("Decodes typed accessors from v2 JSON")
    func decodesV2() throws {
        let m = try JSONDecoder().decode(SessionMeta.self, from: Data(Self.v2JSON.utf8))
        #expect(m.id == "2026-05-24-x")
        #expect(m.harness == "claude-code")
        #expect(m.model == "claude-opus-4-8")
        #expect(m.skillVersion == "1.3.0")
        #expect(m.schemaVersion == 2)
        #expect(m.sanitization?["scanner"]?.stringValue == "betterleaks")
        #expect(m.sanitization?["redactions"]?.numberValue == 2)
    }

    @Test("v1 (no sanitization) decodes; sanitization is nil")
    func decodesV1() throws {
        let json = #"{"captured_at":"t","harness":"zed","id":"x","model":"m","schema_version":1,"skill":"s","skill_version":"1.0.0"}"#
        let m = try JSONDecoder().decode(SessionMeta.self, from: Data(json.utf8))
        #expect(m.schemaVersion == 1)
        #expect(m.sanitization == nil)
    }

    @Test("Round-trips raw (sorted keys) and preserves an unknown key")
    func roundTripsRaw() throws {
        let json = #"{"future_key":"kept","harness":"claude-code","id":"x","schema_version":2}"#
        let m = try JSONDecoder().decode(SessionMeta.self, from: Data(json.utf8))
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let out = String(data: try enc.encode(m), encoding: .utf8)!
        #expect(out == #"{"future_key":"kept","harness":"claude-code","id":"x","schema_version":2}"#)
    }

    @Test("resolve fills \"unknown\" for nil model / skill_version")
    func resolveUnknown() {
        let m = SessionMeta.resolve(id: "x", skill: "s", harness: "claude-code",
                                    model: nil, skillVersion: nil, capturedAt: "2026-07-11T00:00:00Z")
        #expect(m.model == "unknown")
        #expect(m.skillVersion == "unknown")
        #expect(m.schemaVersion == 2)
    }

    @Test("schema_version encodes as an integer, not 2.0")
    func schemaVersionIsInt() throws {
        let m = SessionMeta(id: "x", skill: "s", skillVersion: "1.0", model: "m", harness: "h", capturedAt: "t")
        let out = String(data: try JSONEncoder().encode(m), encoding: .utf8)!
        #expect(out.contains(#""schema_version":2"#))
        #expect(!out.contains("2.0"))
    }
}
