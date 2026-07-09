import Foundation
import EDDCore
import ProjectKit

/// Runs the deterministic scorers over a folder (or single file) and produces both boundary outputs:
/// the SARIF findings document and the native `ScoreReport`. Free, model-free, no network. Walk order
/// is irrelevant — findings are sorted `(relativePath, charOffset, ruleId)` for byte-stable output.
public struct ScoreRunner: Sendable {
    /// Files larger than this are disclosed (`S000`) rather than read/scored (§3.2).
    public static let sizeCap = 1 << 20   // 1 MiB
    let toolVersion: String
    public init(toolVersion: String) { self.toolVersion = toolVersion }

    public struct Output: Sendable {
        public let sarif: SarifDocument
        public let report: ScoreReport
    }

    /// One accumulated finding, holding everything both outputs and the sort need.
    struct RawFinding {
        let relativePath: String
        let ruleId: String
        let level: SarifLevel
        let rank: Double?
        let message: String
        let region: SarifRegion?                 // nil ⇒ categorical (file-level)
        let properties: [String: JSONValue]?
    }

    /// Score `path`, which the caller has already confirmed exists (a missing/unreadable path is the
    /// command's exit-3 concern). A directory is walked recursively; a single file is scored alone.
    /// `onStart` is called once with the candidate-file count before scoring begins — the command uses
    /// it for a stderr progress note on a TTY.
    public func run(path: URL, config: SkilletConfig.Scorers,
                    onStart: (@Sendable (Int) -> Void)? = nil) -> Output {
        var findings: [RawFinding] = []
        var perRule: [String: Int] = [:]
        var scored = 0, skipped = 0, unreadable = 0
        let scorers = ScorerRegistry.active(config)

        let toScore = candidates(under: path, config: config)
        onStart?(toScore.count)
        for (rel, url) in toScore {
            guard let (data, fullSize) = SafeFile.boundedRead(url, cap: Self.sizeCap) else {
                findings.append(disclosure(rel, "Not scored: unreadable (permissions)")); unreadable += 1
                bump(&perRule, "SKILL-S000"); continue
            }
            let isSarif = rel.hasSuffix(".sarif") || rel.hasSuffix(".sarif.json")
            if fullSize > Self.sizeCap {                              // oversized ⇒ S000, never decoded
                findings.append(disclosure(rel, "Not scored: exceeds 1 MiB")); unreadable += 1
                bump(&perRule, "SKILL-S000"); continue
            }
            guard let text = SafeFile.decodeText(data, truncated: false) else {   // binary / non-UTF-8
                if isSarif {
                    findings.append(sarifInvalid(rel, "not UTF-8")); scored += 1; bump(&perRule, "SKILL-S007")
                } else {
                    skipped += 1                                     // silent skip — no finding
                }
                continue
            }
            if isSarif {                                             // validity only; excluded from density
                if let reason = sarifInvalidReason(text) {
                    findings.append(sarifInvalid(rel, reason)); bump(&perRule, "SKILL-S007")
                }
                scored += 1; continue
            }
            let file = ScoredFile(relativePath: rel, text: text)     // density scorers
            for scorer in scorers {
                for f in map(scorer.measure(file, config: config), scorer: scorer, file: file) {
                    findings.append(f); bump(&perRule, f.ruleId)
                }
            }
            scored += 1
        }

        findings.sort {
            if $0.relativePath != $1.relativePath { return $0.relativePath < $1.relativePath }
            let a = $0.region?.charOffset ?? -1, b = $1.region?.charOffset ?? -1
            if a != b { return a < b }
            return $0.ruleId < $1.ruleId
        }

        let sarif = SarifDocument(runs: [SarifRun(
            tool: SarifTool(driver: SarifDriver(name: "skillet", version: toolVersion, rules: ScorerRegistry.catalog)),
            results: findings.map(sarifResult))])
        let report = ScoreReport(
            findings: findings.map(scoreFinding),
            summary: ScoreSummary(perRule: perRule, filesScored: scored, filesSkipped: skipped, filesUnreadable: unreadable))
        return Output(sarif: sarif, report: report)
    }

    // MARK: - Candidate selection (§3.2)

    private func candidates(under path: URL, config: SkilletConfig.Scorers) -> [(rel: String, url: URL)] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path.path, isDirectory: &isDir) else { return [] }
        guard isDir.boolValue else { return [(path.lastPathComponent, path)] }   // single file

        let root = path.standardizedFileURL
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: []) else { return [] }
        var out: [(String, URL)] = []
        for case let url as URL in en {
            let rel = relativePath(of: url, under: root)
            let segments = rel.split(separator: "/").map(String.init)
            if segments.contains(where: { $0.hasPrefix(".") }) { continue }        // dot-entries (.git/.build)
            if SafeFile.isSymlink(url) { continue }                                // never follow
            if isVendored(segments, prefixes: config.vendoredPrefixes) { continue } // skip before read
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            out.append((rel, url))
        }
        return out
    }

    /// gitignore-style: skip when any whole path segment equals a configured folder name (trailing slash
    /// stripped, case-sensitive) — so `Vendored/` skips `Vendored/x` and `sub/Vendored/x`, never `VendoredFoo.swift`.
    private func isVendored(_ segments: [String], prefixes: [String]) -> Bool {
        guard !prefixes.isEmpty else { return false }
        let names = Set(prefixes.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 })
        return segments.contains(where: names.contains)
    }

    private func relativePath(of url: URL, under root: URL) -> String {
        let full = url.standardizedFileURL.path, base = root.path
        if full.hasPrefix(base + "/") { return String(full.dropFirst(base.count + 1)) }
        return url.lastPathComponent
    }

    // MARK: - Measurement → findings

    private func map(_ m: ScorerMeasurement, scorer: any Scorer, file: ScoredFile) -> [RawFinding] {
        switch m {
        case .notApplicable:
            return []
        case let .categorical(level, message):
            return [RawFinding(relativePath: file.relativePath, ruleId: scorer.ruleId, level: level, rank: nil, message: message, region: nil, properties: nil)]
        case let .density(value, denominator, occurrences):
            let goodness = scorer.scale.normalizedGoodness(value)
            guard goodness < 0.5 else { return [] }                 // clean ⇒ no findings
            let level: SarifLevel = goodness < 0.4 ? .error : .warning
            let rank = ((1 - goodness) * 100).rounded()
            var props: [String: JSONValue] = [
                "skillet.goodness": .number(goodness),
                "skillet.scale": scorer.scale.json,
            ]
            if let denominator {
                props["skillet.density"] = .number(value)
                props["skillet.denominator"] = .number(Double(denominator))
            } else {
                props["skillet.count"] = .number(value)
            }
            return occurrences.map { occ in
                RawFinding(relativePath: file.relativePath, ruleId: scorer.ruleId, level: level, rank: rank,
                           message: occ.message, region: SarifRegionCompute.region(for: occ.range, in: file.text), properties: props)
            }
        }
    }

    private func disclosure(_ rel: String, _ message: String) -> RawFinding {
        RawFinding(relativePath: rel, ruleId: "SKILL-S000", level: .note, rank: nil, message: message, region: nil, properties: nil)
    }
    private func sarifInvalid(_ rel: String, _ reason: String) -> RawFinding {
        RawFinding(relativePath: rel, ruleId: "SKILL-S007", level: .error, rank: nil, message: "Invalid SARIF 2.1.0: \(reason)", region: nil, properties: nil)
    }

    /// `nil` if the text is a valid SARIF 2.1.0 shell (parses, `version == "2.1.0"`, `runs` present), else the defect.
    private func sarifInvalidReason(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "not valid JSON" }
        guard let version = obj["version"] as? String else { return "missing version" }
        guard version == "2.1.0" else { return "version \(version) ≠ 2.1.0" }
        guard obj["runs"] != nil else { return "missing runs" }
        return nil
    }

    private func bump(_ perRule: inout [String: Int], _ ruleId: String) { perRule[ruleId, default: 0] += 1 }

    private func sarifResult(_ f: RawFinding) -> SarifResult {
        let locations: [SarifLocation] = f.region.map {
            [SarifLocation(physicalLocation: SarifPhysicalLocation(artifactLocation: SarifArtifactLocation(uri: f.relativePath), region: $0))]
        } ?? [.file(f.relativePath)]
        return SarifResult(ruleId: f.ruleId, level: f.level, rank: f.rank, message: f.message, locations: locations, properties: f.properties)
    }

    private func scoreFinding(_ f: RawFinding) -> ScoreFinding {
        let loc: ScoreLocation = f.region.map {
            .region(file: f.relativePath, startLine: $0.startLine, startColumn: $0.startColumn,
                    endLine: $0.endLine, endColumn: $0.endColumn, charOffset: $0.charOffset, charLength: $0.charLength)
        } ?? .file(f.relativePath)
        return ScoreFinding(ruleId: f.ruleId, level: f.level, rank: f.rank, message: f.message, location: loc, properties: f.properties)
    }
}
