import Testing

/// Central tags so CI can run the free suite by default and filter slow/live work
/// (`swift test --skip slow`), per the constitution's free-before-paid discipline.
extension Tag {
    @Tag static var integration: Self
    @Tag static var slow: Self
}
