import Foundation

/// Saying why a file could not be read, in terms of **the file** rather than of this program.
///
/// **Why one place.** Seven spots reported an unreadable file, in two incompatible ways: five printed the
/// reading library's whole error object, and two printed nothing beyond "not valid". So the same broken
/// test file told you the exact character position from one command and nothing at all from another. The
/// settings file had already been fixed alone, by appending the raw error — a local repair that is what
/// the inconsistency was made of.
///
/// **What it says, and what it leaves out.** The durable, useful part of a decoding failure is *where in
/// your document* the fault is: JSON validators publish this as a path like `/evals/0/expectations`
/// (RFC 6901), and the guidance is that the location survives version and wording changes while the
/// message does not. The parts left out are the reading library's own type and domain names —
/// `DecodingError.typeMismatch`, `NSCocoaErrorDomain Code=3840` — which describe how this program is
/// built rather than what is wrong with your file, and which the guidance on error messages warns against
/// putting in front of people.
enum DecodeFailure {
    /// A short sentence naming the fault and the place in the reader's own file.
    static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return concise(error) }
        switch decoding {
        case let .keyNotFound(key, context):
            return "missing `\(key.stringValue)`\(at(context.codingPath))"
        case let .typeMismatch(_, context):
            return "wrong kind of value\(at(context.codingPath)) — \(plainly(context.debugDescription))"
        case let .valueNotFound(_, context):
            return "no value\(at(context.codingPath))"
        case let .dataCorrupted(context):
            let where_ = at(context.codingPath)
            let detail = position(in: context.underlyingError) ?? plainly(context.debugDescription)
            return where_.isEmpty ? detail : "unreadable\(where_) — \(detail)"
        @unknown default:
            return concise(error)
        }
    }

    /// `evals[0].expectations` — the reader's own structure, in the spelling they wrote it in.
    private static func at(_ path: [CodingKey]) -> String {
        guard !path.isEmpty else { return "" }
        let rendered = path.reduce(into: "") { text, key in
            if let index = key.intValue { text += "[\(index)]" }
            else { text += text.isEmpty ? key.stringValue : ".\(key.stringValue)" }
        }
        return " at `\(rendered)`"
    }

    /// The line and column a syntax fault sits on, when the reader reported one.
    private static func position(in underlying: Error?) -> String? {
        guard let text = (underlying as NSError?)?.userInfo["NSDebugDescription"] as? String,
              text.lowercased().contains("line") else { return nil }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func plainly(_ description: String) -> String {
        description.trimmingCharacters(in: .whitespaces)
    }

    /// Anything that is not a decoding failure: its own sentence, without the surrounding object dump.
    private static func concise(_ error: Error) -> String {
        (error as NSError).localizedDescription
    }
}
