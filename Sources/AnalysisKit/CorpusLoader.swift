import Foundation
import EDDCore
import ProjectKit

/// The imperative shell over one skill's `sessions/` corpus (F33 §4 steps 1–2): enumerate bundle stems
/// from the **union** of the two files triage reads (a meta-less or SARIF-less bundle must still
/// surface — Specs/016 round 2), decode each side, and hand the engine in-memory `BundleInput`s plus
/// disclosures. Symlinks are never followed (the scoring/staging precedent); full six-file bundle
/// layout validation is `bundle verify`'s job, not this loader's.
public struct CorpusLoader: Sendable {
    /// Per-file read cap — bundle SARIFs/metas are small; anything past this is disclosed, not decoded.
    public static let sizeCap = 4 << 20   // 4 MiB

    static let metaSuffix = ".session-meta.json"
    static let sarifSuffix = ".audit-input.sarif"

    public init() {}

    public func load(sessionsDir: URL, since: String? = nil) -> (bundles: [BundleInput], disclosures: [DisclosedInput]) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sessionsDir.path, isDirectory: &isDir), isDir.boolValue else {
            return ([], [])   // no corpus yet — the command renders "no recordings"
        }
        guard let entries = try? fm.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: nil) else {
            return ([], [DisclosedInput(subject: sessionsDir.lastPathComponent, reason: "sessions directory unreadable")])
        }

        // Union-stem discovery (round 2): either input file announces the bundle. Hidden entries are
        // skipped like every other directory probe in the project (round 4 — `DirectoryProbe` uses
        // `.skipsHiddenFiles`, the scorer walk drops dot-segments): a `.DS_Store` or a dot-prefixed
        // `.x.session-meta.json` never becomes a stem.
        var stems: Set<String> = []
        for url in entries {
            let name = url.lastPathComponent
            // Regular files only (round 6) — like the scorer walk. A dir/FIFO/socket/device named like a
            // bundle file must never seed a stem: `boundedRead`'s `FileHandle(forReadingFrom:)` is an
            // `open(O_RDONLY)` with **no `O_NONBLOCK`**, so a FIFO would **hang triage forever** (CERT
            // FIO32-C). `isRegularFile` (a `stat`, non-blocking) runs *after* the symlink lstat, so a
            // symlink is excluded before its target is stat'd.
            // …and a **single link** (round 8): a hard link (`linkCount > 1`) points at another inode —
            // possibly a file outside the project that the symlink guard can't catch (CWE-59/CWE-62).
            // This is the codebase-wide posture (BodyExtractor / ClaudeCodeAdapter / WorkspaceManager).
            guard !SafeFile.isHidden(name), !SafeFile.isSymlink(url),
                  SafeFile.isRegularFile(url), SafeFile.linkCount(url) == 1 else { continue }
            if name.hasSuffix(Self.metaSuffix) { stems.insert(String(name.dropLast(Self.metaSuffix.count))) }
            if name.hasSuffix(Self.sarifSuffix) { stems.insert(String(name.dropLast(Self.sarifSuffix.count))) }
        }
        // `--since`: bundle stems open with their YYYY-MM-DD date, so a lexical prefix compare is exact.
        let selected = stems.sorted().filter { stem in
            guard let since else { return true }
            return String(stem.prefix(10)) >= since
        }
        // A filter that excluded EVERYTHING must say so (round 12): rendering the generic "no
        // recordings yet — capture one" would masquerade an active date filter as an empty corpus
        // (the zero-results-from-filter rule: name the constraint, not "no data").
        if let since, selected.isEmpty, !stems.isEmpty {
            return ([], [DisclosedInput(
                subject: "sessions",
                reason: "\(stems.count) recording(s) predate --since \(since) — the corpus is not empty, only filtered")])
        }

        var bundles: [BundleInput] = []
        var disclosures: [DisclosedInput] = []
        for stem in selected {
            let metaURL = sessionsDir.appendingPathComponent(stem + Self.metaSuffix)
            let sarifURL = sessionsDir.appendingPathComponent(stem + Self.sarifSuffix)
            guard let meta: SessionMeta = decode(metaURL, stem: stem, what: "session-meta.json", into: &disclosures) else { continue }
            guard let sarif: SarifLog = decode(sarifURL, stem: stem, what: "audit-input.sarif", into: &disclosures) else { continue }
            bundles.append(BundleInput(
                stem: stem,
                skillVersion: meta.skillVersion, model: meta.model,
                toolVersion: sarif.toolVersion, results: sarif.resultSlices))
        }
        return (bundles, disclosures)
    }

    /// Read + JSON-decode one bundle file; any failure becomes a disclosure (never a crash, never a
    /// silent skip — malformed input is data). The read goes through **the one sanctioned untrusted
    /// read** (`SafeFile.readPlainData` — F33 security pass), which bundles the guards rounds 6–8
    /// added here piecemeal (symlink / special-file / hard-link / bounded); this site keeps only its
    /// disclosure vocabulary. It remains the safety net for the **mixed** case the enumeration walk
    /// can't catch (a regular meta seeds the stem; its sibling is a FIFO or hard link).
    private func decode<T: Decodable>(_ url: URL, stem: String, what: String,
                                      into disclosures: inout [DisclosedInput]) -> T? {
        let data: Data
        switch SafeFile.readPlainData(url, cap: Self.sizeCap) {
        case let .success(bytes):
            data = bytes
        case .failure(.notFound):
            disclosures.append(DisclosedInput(subject: stem, reason: "missing \(what) (incomplete bundle — re-capture or remove)"))
            return nil
        case let .failure(refusal):
            disclosures.append(DisclosedInput(subject: stem, reason: "\(what) \(refusal.reason)"))
            return nil
        }
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            disclosures.append(DisclosedInput(subject: stem, reason: "\(what) is not valid JSON — skipped"))
            return nil
        }
        return decoded
    }
}
