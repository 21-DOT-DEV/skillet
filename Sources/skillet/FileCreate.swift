import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Creating a file that must **never replace** one already there, without ever leaving a half-written
/// one behind.
///
/// Two commands need exactly this: one writes drafted edits, the other writes mined evidence, and both
/// treat an existing file as sacred. Foundation cannot give both guarantees through one call — and not
/// merely as a missing feature: `.withoutOverwriting` writes the bytes straight into the final name, so
/// a crash partway through leaves a truncated file at that name; `.atomic` avoids that by renaming over
/// the name, which replaces whatever is there; and asking for both **traps the process**
/// (`Fatal error: withoutOverwriting is not supported with atomic`).
///
/// The portable recipe instead: write a temporary neighbour in the same folder, then hard-link it into
/// place. The link fails when the name is taken, so "never replace" is enforced by the kernel at the
/// instant of creation rather than by a check that ran earlier and might now be stale. The destination
/// name therefore either does not exist or holds the complete file — never part of one.
enum FileCreate {
    /// Not flushed to the physical disk, **deliberately**. Linking makes the name appear all at once, but
    /// surviving a power cut would additionally require forcing the file's data and then the folder entry
    /// to disk, which costs real time on every write. What a command-line tool actually suffers is the
    /// process dying — an interrupt, an unhandled error, a kill — and by then the data is already with the
    /// operating system, so linking is enough. A draft lost to a power cut can be recreated by re-running;
    /// a half-written one could not be told apart from a real one, which is the failure worth preventing.
    static func exclusively(_ contents: String, at destination: URL) throws {
        let directory = destination.deletingLastPathComponent()
        // Same folder, so the link cannot cross filesystems. Dot-prefixed and uniquely named so a stray
        // one after a crash is obviously debris rather than something that reads as a real artifact.
        let temporary = directory.appendingPathComponent(
            ".\(destination.lastPathComponent).partial-\(UUID().uuidString)")

        try Data(contents.utf8).write(to: temporary, options: [.withoutOverwriting])
        defer { try? FileManager.default.removeItem(at: temporary) }

        guard link(temporary.path, destination.path) == 0 else {
            let code = errno
            // Not every filesystem supports hard links — some network mounts and FAT-family volumes
            // refuse. Falling back to the plain create keeps the tool working there, losing only the
            // crash-safety this routine adds; refusing outright would break projects that work today,
            // which is a far worse trade than the narrow window being closed.
            if code == EPERM || code == EOPNOTSUPP {
                try Data(contents.utf8).write(to: destination, options: [.withoutOverwriting])
                return
            }
            // EEXIST is the race this routine exists to lose safely: someone created the name between
            // the caller's check and now. Reported with Foundation's own "file exists" shape, so callers
            // that already branch on that keep working unchanged.
            throw NSError(domain: NSCocoaErrorDomain,
                          code: code == EEXIST ? NSFileWriteFileExistsError : NSFileWriteUnknownError,
                          userInfo: [NSFilePathErrorKey: destination.path,
                                     NSLocalizedDescriptionKey: code == EEXIST
                                        ? "file already exists"
                                        : "could not create the file (\(String(cString: strerror(code))))"])
        }
    }
}
