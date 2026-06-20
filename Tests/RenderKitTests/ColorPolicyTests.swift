import Testing
import RenderKit

@Suite("Color policy")
struct ColorPolicyTests {
    @Test("never is always off; always is always on (overrides NO_COLOR)")
    func neverAndAlways() {
        #expect(ColorPolicy.resolve(choice: .never, noColorEnv: false, isTTY: true).enabled == false)
        #expect(ColorPolicy.resolve(choice: .always, noColorEnv: true, isTTY: false).enabled == true)
    }

    @Test("auto is on only with a TTY and no NO_COLOR")
    func auto() {
        #expect(ColorPolicy.resolve(choice: .auto, noColorEnv: false, isTTY: true).enabled == true)
        #expect(ColorPolicy.resolve(choice: .auto, noColorEnv: false, isTTY: false).enabled == false)
        #expect(ColorPolicy.resolve(choice: .auto, noColorEnv: true, isTTY: true).enabled == false)
    }
}
