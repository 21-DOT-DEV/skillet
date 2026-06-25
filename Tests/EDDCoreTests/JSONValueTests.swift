import Testing
import Foundation
import EDDCore

@Suite("JSONValue + golden support")
struct JSONValueTests {
    @Test("Round-trips every JSON kind, semantically")
    func roundTrips() throws {
        let doc = """
        {"s":"hi","n":3,"f":0.5,"b":true,"z":null,"a":[1,"two",false,null],"o":{"nested":[1]}}
        """
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(doc.utf8))
        let reencoded = try JSONEncoder().encode(value)
        #expect(try jsonSemanticEqual(Data(doc.utf8), reencoded))
    }

    @Test("Semantic equality is order-independent and 1 == 1.0")
    func semanticEquality() throws {
        #expect(try jsonSemanticEqual(#"{"a":1,"b":2}"#, #"{"b":2,"a":1}"#))
        #expect(try jsonSemanticEqual(#"{"x":1}"#, #"{"x":1.0}"#))
        #expect(try jsonSemanticEqual(#"[1,2,3]"#, #"[1,2,3]"#))
        #expect(try !jsonSemanticEqual(#"{"x":1}"#, #"{"x":2}"#))
        #expect(try !jsonSemanticEqual(#"[1,2]"#, #"[2,1]"#))  // arrays are ordered
    }

    @Test("Integral numbers re-encode without a decimal point (viewer byte-compat, D5)")
    func integerFidelity() throws {
        // `passed:3` must survive as `3`, not `3.0`. jsonSemanticEqual treats 3 == 3.0 and would mask a
        // regression, so assert the encoded bytes directly — this locks JSONEncoder's integral-Double
        // behavior that every run-record integer field (passed/failed/total/tokens) relies on.
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"passed":3,"rate":0.5}"#.utf8))
        let out = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        #expect(out.contains(#""passed":3"#))
        #expect(!out.contains("3.0"))
        #expect(out.contains("0.5"))
    }

    @Test("Decode ordering: bool and number never cross (pins the load-bearing Bool-before-Double)")
    func typeDisambiguation() throws {
        func d(_ s: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) }
        #expect(try d("true") == .bool(true))     // not .number(1)
        #expect(try d("false") == .bool(false))
        #expect(try d("1") == .number(1))         // not .bool(true)
        #expect(try d("0") == .number(0))         // not .bool(false)
        #expect(try d("1.5") == .number(1.5))
        #expect(try d(#""1""#) == .string("1"))   // not .number(1)
        #expect(try d("null") == .null)
    }
}
