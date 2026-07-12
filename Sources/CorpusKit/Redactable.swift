import TraceKit

/// A value that can map **every** `String` it contains through a transform — the explicit alternative
/// to reflection (C4). `Mirror` is read-only (it can't write the scrubbed values back) and fragile;
/// each type instead spells out its own `String` fields and recurses into children. Value-based
/// redaction only ever replaces *detected* secrets, so applying it to non-secret fields (paths, names)
/// is harmless — defense-in-depth at no cost.
public protocol Redactable {
    func redacting(_ transform: (String) -> String) -> Self
}

extension ToolCall: Redactable {
    public func redacting(_ f: (String) -> String) -> ToolCall {
        ToolCall(name: name, input: input.map(f))   // tool arguments — the documented leak vector
    }
}

extension Turn: Redactable {
    public func redacting(_ f: (String) -> String) -> Turn {
        Turn(role: role, text: f(text), toolCalls: toolCalls.map { $0.redacting(f) },
             filesTouched: filesTouched.map(f), at: at)
    }
}

extension WorkspaceDiff: Redactable {
    public func redacting(_ f: (String) -> String) -> WorkspaceDiff {
        WorkspaceDiff(added: added.map(f), modified: modified.map(f), deleted: deleted.map(f))
    }
}

extension SkillInvocation: Redactable {
    public func redacting(_ f: (String) -> String) -> SkillInvocation {
        SkillInvocation(skill: f(skill), turnIndex: turnIndex)
    }
}

extension Trace: Redactable {
    public func redacting(_ f: (String) -> String) -> Trace {
        // `harness`/`harnessVersion` (ids/version strings) and `usage` (numbers) are not secret-bearing
        // and are left as-is; every free-text field is scrubbed.
        Trace(harness: harness, harnessVersion: harnessVersion, startedAt: startedAt, endedAt: endedAt,
              turns: turns.map { $0.redacting(f) },
              skillInvocations: skillInvocations.map { $0.redacting(f) },
              workspaceDiff: workspaceDiff.redacting(f),
              usage: usage)
    }
}

extension Trace {
    /// The trace's secret-bearing free text as one blob, for the scanner to detect over: each turn's
    /// text and tool arguments, **plus every path string** (touched files, workspace-diff paths, skill
    /// names) — a secret can hide in a filename, and these paths appear in no other scanned artifact when
    /// the workspace is non-git or the file was transient. (Redaction stays value-based across the whole
    /// structure — `Trace.redacting` already scrubs these fields; this only feeds *detection*.)
    var scannableText: String {
        var parts: [String] = []
        for turn in turns {
            if !turn.text.isEmpty { parts.append(turn.text) }
            for call in turn.toolCalls where !(call.input ?? "").isEmpty { parts.append(call.input!) }
            parts.append(contentsOf: turn.filesTouched)
        }
        for inv in skillInvocations { parts.append(inv.skill) }
        parts.append(contentsOf: workspaceDiff.added)
        parts.append(contentsOf: workspaceDiff.modified)
        parts.append(contentsOf: workspaceDiff.deleted)
        return parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
