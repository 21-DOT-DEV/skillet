import Foundation
import TraceKit

/// Renders the human-readable `transcript.md` from the normalized `Trace` (D-4). A clean skillet-native
/// rendering that echoes the familiar `## User` / `## Assistant` / `**Tool Call: <name>**` headers so a
/// maintainer reading old and new bundles isn't jarred — **not** a byte-match of another editor's export
/// (the machine-readable record is the separate `trace.json`). The rendered string is a normal bundle
/// artifact, so it is scrubbed alongside the rest.
public enum TranscriptRenderer {
    public static func render(_ trace: Trace) -> String {
        var out = ""
        for turn in trace.turns {
            out += "\(header(for: turn.role))\n\n"
            let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { out += "\(text)\n\n" }
            for call in turn.toolCalls {
                out += "**Tool Call: \(call.name)**\n\n"
                if let input = call.input, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    out += "```\n\(input)\n```\n\n"
                }
            }
        }
        return out
    }

    private static func header(for role: Turn.Role) -> String {
        switch role {
        case .user: return "## User"
        case .assistant: return "## Assistant"
        case .tool: return "## Tool"
        case .system: return "## System"
        }
    }
}
