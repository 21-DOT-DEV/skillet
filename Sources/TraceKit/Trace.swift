import Foundation
import EDDCore

/// The one harness-independent record of an execution (design §9.3) — what capture bundles,
/// corrective-turn mining, judge evidence, and the viewer all consume. Per-harness parsers (which
/// produce a `Trace` from a native log) live beside their adapters; this model is harness-agnostic
/// by construction.
///
/// `skillet.trace/1` is designed now (D4) but treated as a **greenfield internal schema**, not a
/// frozen boundary format (§7.2) — later features may add *optional* fields additively.
public struct Trace: SchemaIdentified, Codable, Sendable, Equatable {
    public static let schema = "skillet.trace/1"

    public var harness: HarnessID
    public var harnessVersion: String
    public var startedAt: Date
    public var endedAt: Date
    public var turns: [Turn]
    public var skillInvocations: [SkillInvocation]
    public var workspaceDiff: WorkspaceDiff
    public var usage: Usage?
    /// **Why ``usage`` is absent, when it is.** Absent covers two different situations that used to be
    /// indistinguishable: nothing was reported at all, and something was reported that could not be
    /// trusted — a missing field, a figure below none. The counts are discarded either way, deliberately,
    /// so that a part-read figure never enters a total; but the second is a problem worth telling someone
    /// about and the first is not. Defaults to counted-or-absent so records written before this, and every
    /// stand-in that reports nothing, read back unchanged.
    public var usageState: UsageState

    /// What is known about a session's cost figures.
    public enum UsageState: String, Codable, Sendable, Equatable {
        /// Figures were reported and are usable — ``Trace/usage`` holds them.
        case counted
        /// No figures were offered. Not a fault: an offline stand-in reports none, and so does a tool
        /// that does not publish them.
        case absent
        /// Figures were offered and could not be used, so the whole session's counts were dropped rather
        /// than partly believed.
        case unreadable
    }

    public init(
        harness: HarnessID,
        harnessVersion: String,
        startedAt: Date,
        endedAt: Date,
        turns: [Turn],
        skillInvocations: [SkillInvocation],
        workspaceDiff: WorkspaceDiff,
        usage: Usage? = nil,
        usageState: UsageState? = nil
    ) {
        self.harness = harness
        self.harnessVersion = harnessVersion
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.turns = turns
        self.skillInvocations = skillInvocations
        self.workspaceDiff = workspaceDiff
        self.usage = usage
        // Not stated: infer it, so every existing construction site keeps its meaning without change.
        self.usageState = usageState ?? (usage == nil ? .absent : .counted)
    }
}

/// One conversational turn in a `Trace`.
public struct Turn: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable, Equatable {
        case user, assistant, tool, system
    }

    public var role: Role
    public var text: String
    public var toolCalls: [ToolCall]
    public var filesTouched: [String]
    public var at: Date

    public init(role: Role, text: String, toolCalls: [ToolCall] = [], filesTouched: [String] = [], at: Date) {
        self.role = role
        self.text = text
        self.toolCalls = toolCalls
        self.filesTouched = filesTouched
        self.at = at
    }
}

/// A tool invocation within a turn. Minimal now; richer shape arrives when a parser needs it (F6+).
public struct ToolCall: Codable, Sendable, Equatable {
    public var name: String
    public var input: String?
    public init(name: String, input: String? = nil) {
        self.name = name
        self.input = input
    }
}

/// Which skill fired, and at which turn — the signal the trigger axis grades on (§9.3).
public struct SkillInvocation: Codable, Sendable, Equatable {
    public var skill: String
    public var turnIndex: Int
    public init(skill: String, turnIndex: Int) {
        self.skill = skill
        self.turnIndex = turnIndex
    }
}

/// The net change the run made to its workspace, as repo-relative paths.
public struct WorkspaceDiff: Codable, Sendable, Equatable {
    public var added: [String]
    public var modified: [String]
    public var deleted: [String]
    public init(added: [String] = [], modified: [String] = [], deleted: [String] = []) {
        self.added = added
        self.modified = modified
        self.deleted = deleted
    }
}

/// What a session cost in tokens, where the tool that ran it reports them; `nil` means nothing counted.
/// The counts themselves live in ``EDDCore/TokenCounts``, which explains why none of its fields is
/// called `inputTokens`.
public typealias Usage = TokenCounts
