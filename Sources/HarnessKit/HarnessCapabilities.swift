/// What a harness adapter can do (§9.1). `runTask` is mandatory; the rest light up per harness.
public struct HarnessCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let runTask        = HarnessCapabilities(rawValue: 1 << 0)
    public static let skillInjection = HarnessCapabilities(rawValue: 1 << 1)
    public static let traceParsing   = HarnessCapabilities(rawValue: 1 << 2)
    public static let sessionCapture = HarnessCapabilities(rawValue: 1 << 3)
    public static let judging        = HarnessCapabilities(rawValue: 1 << 4)

    /// Stable snake_case names for `--json` output (not a bitmask).
    public var names: [String] {
        var out: [String] = []
        if contains(.runTask) { out.append("run_task") }
        if contains(.skillInjection) { out.append("skill_injection") }
        if contains(.traceParsing) { out.append("trace_parsing") }
        if contains(.sessionCapture) { out.append("session_capture") }
        if contains(.judging) { out.append("judging") }
        return out
    }
}
