import Foundation
import EDDCore
import ProjectKit

/// Preparing the tool's throwaway working folder, in one place.
///
/// Both the measured-run command and the drafting command need the same thing before they write
/// anything: refuse a path that crosses a symbolic link, refuse a plain file sitting where a folder
/// belongs, make sure the folder ignores itself so its contents can never be committed, and only then
/// create it. That is one operation, not two similar ones — sharing it means the checks can't be present
/// in one command and missing in the other, which is exactly how the file-blocking-a-folder case came to
/// be unguarded in both.
enum CacheSupport {
    /// Ensure `<projectRoot>/.skillet[/subdirectory]` exists and is safe to write into.
    /// Returns the prepared directory.
    @discardableResult
    static func prepareCacheDirectory(projectRoot: URL, subdirectory: String? = nil) throws -> URL {
        let cache = projectRoot.appendingPathComponent(".skillet", isDirectory: true)
        let target = subdirectory.map { cache.appendingPathComponent($0, isDirectory: true) } ?? cache

        // A symlinked cache path could redirect writes outside the project entirely.
        if let link = SafeFile.firstSymlinkOnPath(from: projectRoot, to: target) {
            throw EDDError.invalidArtifact(
                path: relativeLabel(target, from: projectRoot),
                reason: "cache path crosses a symlink (not allowed): \(link.lastPathComponent)",
                fix: "replace the symbolic link with a real folder — a link could send this outside the project, where the checks that keep it undoable do not reach")
        }
        // A plain file where a folder belongs is a malformed project — the user's problem to fix, with a
        // specific remedy. Without this check the folder-creation call throws a raw filesystem error,
        // which the command's last-resort handler reports as "a defect in skillet": blaming ourselves for
        // their broken layout, and burying the one fact that would let them fix it.
        for candidate in subdirectory == nil ? [cache] : [cache, target] {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               !isDirectory.boolValue {
                throw EDDError.invalidArtifact(
                    path: relativeLabel(candidate, from: projectRoot),
                    reason: "is a file, but a directory is expected here — remove or rename it",
                    fix: "remove or rename that file so a folder can take its place, then re-run")
            }
        }
        // **The entry itself, not what it points at.** Asking "does a file exist here" follows a link and
        // answers about its destination, so a link pointing at nothing answers "no" and the write below
        // goes ahead. Measured on this platform, that write replaces the link rather than following it, so
        // the outcome is safe here — but that is undocumented, differs between systems, and this project
        // supports one it is not tested on. The folder this sits in is already checked this way and the
        // entry inside it was not, which is the same rule holding one level up and not the next.
        //
        // Checked *here* rather than beside the write: everything in the block below is reported as "the
        // machine would not let us write", and a link someone put there is a broken layout to fix in the
        // project, not a failing disk.
        let ignoreFile = cache.appendingPathComponent(".gitignore")
        if SafeFile.isSymlink(ignoreFile) {
            throw EDDError.invalidArtifact(
                path: relativeLabel(ignoreFile, from: projectRoot),
                reason: "is a link, and skillet will not write through or over one",
                fix: "delete the link and re-run — what keeps this cache out of version control has to be "
                    + "a real file, or it could be pointed somewhere else entirely")
        }
        // Keep the cache self-ignoring even when this is the first skillet command run in a repo, so a
        // written artifact is never left committable (constitution VI). Self-ignoring is deliberate: the
        // `*` covers this file too, which is the convention generated cache folders use.
        // **The rule for filesystem failures, in one sentence — classify by the remedy, not the cause:**
        // a broken *layout* is something to fix in the project (bad artifact, above); the operating system
        // refusing us — no permission, disk full, an I/O fault — is something to fix on the machine
        // (environment); anything we did not anticipate is our bug (internal). Deciding this case-by-case
        // is how a permissions problem came to be reported as "a defect in skillet".
        do {
            let ignore = cache.appendingPathComponent(".gitignore")
            if !FileManager.default.fileExists(atPath: ignore.path) {
                try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                // **Created through the shared routine, not by hand.** Asking whether the file is there
                // and then writing it are two steps, and the name can change between them. The routine
                // used everywhere else here makes "create this only if it is absent" a single step the
                // operating system settles, and reports the lost race as an ordinary "file exists" —
                // which, for this file, means somebody else already wrote what we were going to write.
                do {
                    try FileCreate.exclusively(
                        "# Created by skillet automatically — this whole folder is a rebuildable cache.\n*\n",
                        at: ignore)
                } catch let error as NSError where error.code == NSFileWriteFileExistsError {
                    // Already there; nothing to do and nothing wrong.
                }
            }
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        } catch {
            throw EDDError.cacheUnwritable(
                path: relativeLabel(target, from: projectRoot),
                reason: "\(error)")
        }
        return target
    }

    private static func relativeLabel(_ url: URL, from root: URL) -> String {
        url.path.hasPrefix(root.path + "/") ? String(url.path.dropFirst(root.path.count + 1)) : url.path
    }
}
