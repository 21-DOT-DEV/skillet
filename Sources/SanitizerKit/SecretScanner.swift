import Foundation
import HarnessKit

/// One artifact to scan: its bundle-relative path (used as the `--set-attr path=` label so findings
/// carry a filename) and its text.
public struct ScanInput: Sendable, Equatable {
    public let path: String
    public let text: String
    public init(path: String, text: String) { self.path = path; self.text = text }
}

/// The scanner seam — runs a secret detector over artifacts and returns findings. Injectable so the
/// sanitizer's logic is unit-tested with a stub (no real `betterleaks` in CI).
public protocol SecretScanner: Sendable {
    func scan(_ inputs: [ScanInput]) async throws -> [Finding]
}

/// The production scanner: `betterleaks stdin -f json -r - --set-attr path=<path>` **per artifact**, fed
/// through the sanctioned `ProcessLauncher`'s stdin — the raw text stays in memory and never touches
/// disk (spike-verified against betterleaks 1.6.1). Detection-only and offline: skillet never passes the
/// `--validation` network flag.
///
/// **Fail-closed exit-code discipline (Spec 014 §R3-3).** betterleaks/gitleaks reuse exit `1` for *both*
/// "leaks found" and "error," so a naive "non-zero ⇒ error" rule would fail-closed on every finding. We
/// therefore run with **`--exit-code 0`** (findings-as-success): a clean *or* found scan exits `0`, so a
/// non-zero exit signals a genuine scanner error. Success is decided by parseable findings JSON, and we
/// **fail closed** (`scannerUnparseable`) on a non-zero exit that produced no findings — an errored run
/// that prints `[]` must never be mistaken for "clean" and write an unscrubbed bundle — as well as on
/// unparseable/absent output. A binary that won't launch throws `scannerNotFound`.
public struct BetterleaksScanner: SecretScanner {
    let binaryPath: String
    let launcher: any ProcessLauncher
    let timeout: Duration

    public init(binaryPath: String, launcher: any ProcessLauncher, timeout: Duration = .seconds(120)) {
        self.binaryPath = binaryPath
        self.launcher = launcher
        self.timeout = timeout
    }

    public func scan(_ inputs: [ScanInput]) async throws -> [Finding] {
        var all: [Finding] = []
        for input in inputs {
            all += try await scanOne(input)
        }
        return all
    }

    /// Prove the resolved binary is a **working** secret scanner before capture trusts it: feed a known
    /// planted secret through it and confirm it's flagged. A non-scanner (`/usr/bin/true`, or a stub that
    /// always prints `[]`) fails this, so capture refuses rather than writing an "unverified clean" bundle
    /// — closing the "any exit-0 binary passes as a clean scanner" bypass. Defense in depth beside
    /// `--exit-code 0` + the parseable-array requirement (both CRITICAL findings).
    ///
    /// **Limitation (by design):** this is a *liveness* check, not an *integrity* check. It cannot detect a
    /// tampered/broken binary that flags this one planted canary while missing real secrets. The trust
    /// model is "user-controlled binary (resolved from flag/env/config/`PATH`) + self-test"; a stronger
    /// guarantee would require pinning a known-good betterleaks hash/signature (deferred — see §12).
    public func verify() async throws {
        // A **synthetic**, self-labelling canary (not a real credential — it literally spells out its
        // purpose) with enough entropy that betterleaks' github-pat rule flags it. Never issued by GitHub.
        let canary = "ghp_skilletSyntheticCanaryDoNotUse123456"
        let findings = try await scan([ScanInput(path: "__selftest__", text: "token = \(canary)\n")])
        guard findings.contains(where: { $0.secret == canary }) else {
            throw SanitizerError.scannerUnparseable(
                reason: "betterleaks did not flag a planted test secret — refusing to trust it as a scanner")
        }
    }

    private func scanOne(_ input: ScanInput) async throws -> [Finding] {
        let output: ProcessOutput
        do {
            output = try await launcher.run(
                binaryPath,
                // `--exit-code 0`: a found-secrets scan exits 0 like a clean one, so a non-zero exit means
                // a genuine error (Spec 014 §R3-3). The fail-closed guard below relies on this.
                ["stdin", "-f", "json", "-r", "-", "--log-level", "error", "--exit-code", "0", "--set-attr", "path=\(input.path)"],
                input: Data(input.text.utf8),
                workingDirectory: nil,
                timeout: timeout,
                environment: nil,
                // A generous cap (matches gitDiff): a findings array for an artifact with many secrets can
                // exceed the launcher's 64 MiB default → truncated JSON → a false `scannerUnparseable` on
                // an otherwise-valid session. Still bounded so a runaway scanner can't exhaust memory.
                outputLimitBytes: 256 << 20
            )
        } catch {
            throw SanitizerError.scannerNotFound(reason: "could not run betterleaks at \(binaryPath): \(error)")
        }

        let json = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // A real betterleaks scan ALWAYS emits a JSON array — `[]` when clean, findings when not. Empty
        // stdout is therefore NOT "clean": it means the binary produced no findings JSON (a non-scanner
        // like `/usr/bin/true`, or an errored run), so we fail closed. **Only a parseable `[Finding]`
        // array is trusted** — this closes the `/usr/bin/true` class of bypass (CRITICAL).
        guard !json.isEmpty, let data = json.data(using: .utf8) else {
            throw SanitizerError.scannerUnparseable(
                reason: "betterleaks produced no JSON findings array (empty output — not a real scan)")
        }
        let findings: [Finding]
        do {
            findings = try JSONDecoder().decode([Finding].self, from: data)
        } catch {
            throw SanitizerError.scannerUnparseable(reason: "betterleaks output was not a findings array: \(error)")
        }
        // Fail closed on a genuine scanner error (constitution VI). With `--exit-code 0`, found+clean both
        // exit 0, so a non-zero exit is an error → refuse it. The `&& findings.isEmpty` clause keeps us
        // correct even if a betterleaks build ignores `--exit-code` and reuses exit `1` for "leaks found":
        // a real finding set still redacts; only an errored run with nothing to show (it printed `[]`/empty
        // then failed) is refused. This closes the fail-open gap where an error that emits `[]` was read as
        // "clean" and an unscrubbed bundle got written.
        if output.exitCode != 0 && findings.isEmpty {
            throw SanitizerError.scannerUnparseable(
                reason: "betterleaks exited \(output.exitCode) with no findings — treating as a scan error; refusing to write from an unverified scan")
        }
        return findings
    }
}
