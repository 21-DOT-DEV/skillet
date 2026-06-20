/// How to colorize output (`--color`), per clig.dev + `NO_COLOR`.
public enum ColorChoice: String, CaseIterable, Sendable {
    case auto
    case always
    case never
}

/// The resolved decision of whether to emit ANSI color, derived from the flag, the environment, and
/// whether stdout is a TTY.
public struct ColorPolicy: Sendable, Equatable {
    public let enabled: Bool
    public init(enabled: Bool) { self.enabled = enabled }

    /// Resolve color: `never` always off, `always` always on (overriding `NO_COLOR`), `auto` on only
    /// when stdout is a TTY and `NO_COLOR` is unset.
    public static func resolve(choice: ColorChoice, noColorEnv: Bool, isTTY: Bool) -> ColorPolicy {
        switch choice {
        case .never: ColorPolicy(enabled: false)
        case .always: ColorPolicy(enabled: true)
        case .auto: ColorPolicy(enabled: !noColorEnv && isTTY)
        }
    }
}
