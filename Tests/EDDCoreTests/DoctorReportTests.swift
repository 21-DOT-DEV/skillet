import Testing
import EDDCore

@Suite("DoctorReport — skillet.doctor/1")
struct DoctorReportTests {
    @Test("Healthy when no row fails; warnings never fail (frozen contract)")
    func warningsNeverFail() {
        let report = DoctorReport(rows: [
            .init(check: DoctorReport.Check.config, status: .pass, message: "loaded skillet.yaml"),
            .init(check: DoctorReport.Check.harnessAuth, subject: "claude-code", status: .warning,
                  message: "not authenticated", remedy: "claude auth login")
        ])
        #expect(report.healthy)
        #expect(report.exitCode == .success)
    }

    @Test("Any failure row flips healthy and exits 3 (environment)")
    func failureExitsEnvironment() {
        let report = DoctorReport(rows: [
            .init(check: DoctorReport.Check.config, status: .pass, message: "loaded skillet.yaml"),
            .init(check: DoctorReport.Check.harnessBinary, subject: "claude-code", status: .failure,
                  message: "could not find the claude-code binary", remedy: "install claude")
        ])
        #expect(!report.healthy)
        #expect(report.exitCode == .environment)
        #expect(report.exitCode.rawValue == 3)
    }

    @Test("Empty report is healthy (config-only projects preflight clean)")
    func emptyIsHealthy() {
        #expect(DoctorReport(rows: []).healthy)
    }

    @Test("Golden: byte-stable skillet.doctor/1 encoding (frozen boundary, F8 discipline)")
    func golden() throws {
        let report = DoctorReport(rows: [
            .init(check: DoctorReport.Check.config, status: .pass, message: "loaded skillet.yaml"),
            .init(check: DoctorReport.Check.harnessAuth, subject: "claude-code", status: .warning,
                  message: "not authenticated", remedy: "claude auth login")
        ])
        let encoded = try SkilletJSON.encode(report)
        let expected = #"{"healthy":true,"rows":[{"check":"config","message":"loaded skillet.yaml","status":"pass"},"#
            + #"{"check":"harness.auth","message":"not authenticated","remedy":"claude auth login","status":"warning","subject":"claude-code"}],"#
            + #""schema":"skillet.doctor/1"}"#
        #expect(encoded == expected)
    }

    @Test("Check-id vocabulary is the frozen dotted set")
    func checkIDs() {
        #expect(DoctorReport.Check.config == "config")
        #expect(DoctorReport.Check.harnessBinary == "harness.binary")
        #expect(DoctorReport.Check.harnessVersion == "harness.version")
        #expect(DoctorReport.Check.harnessAuth == "harness.auth")
        #expect(DoctorReport.Check.skillVisibility == "skill.visibility")
        #expect(DoctorReport.Check.skillLint == "skill.lint")
        #expect(DoctorReport.Check.skillTriggerEvals == "skill.trigger-evals")   // added round 4 (additive)
    }
}
