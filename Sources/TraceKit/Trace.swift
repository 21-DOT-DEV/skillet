import Foundation
import EDDCore

/// The one harness-independent record of an execution (design §9.3) — what capture bundles,
/// corrective-turn mining, judge evidence, and the viewer all consume. Per-harness parsers (which
/// produce a `Trace` from a native log) live beside their adapters; this model is harness-agnostic
/// by construction.
///
/// `skillet.trace/1` is designed now (D4) but treated as a **greenfield internal schema**, not a
/// frozen boundary format (§7.2) — later features may add *optional* fields additively.
public struct Trace: SchemaIdentified, Decodable, Sendable, Equatable {
    public static let schema = "skillet.trace/1"

    public var harness: HarnessID
    public var harnessVersion: String
    public var startedAt: Date
    public var endedAt: Date
    public var turns: [Turn]
    public var skillInvocations: [SkillInvocation]
    public var workspaceDiff: WorkspaceDiff
    public var usage: Usage?

    public init(
        harness: HarnessID,
        harnessVersion: String,
        startedAt: Date,
        endedAt: Date,
        turns: [Turn],
        skillInvocations: [SkillInvocation],
        workspaceDiff: WorkspaceDiff,
        usage: Usage? = nil
    ) {
        self.harness = harness
        self.harnessVersion = harnessVersion
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.turns = turns
        self.skillInvocations = skillInvocations
        self.workspaceDiff = workspaceDiff
        self.usage = usage
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

/// Token / cost usage where the harness reports it. All optional — structurally `nil` until usage
/// parsing lands (Phase 8).
public struct Usage: Codable, Sendable, Equatable {
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var costUSD: Double?
    public init(inputTokens: Int? = nil, outputTokens: Int? = nil, costUSD: Double? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
    }
}
