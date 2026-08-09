import Foundation
import ProjectKit
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

    /// Replace an **existing** file's contents, atomically, **keeping the permissions it already had**.
    ///
    /// The sibling above refuses to replace anything; this one exists to replace, so it is a different
    /// routine rather than a flag. Same shape: write a neighbour, put it in place with one operation, so
    /// the destination name never holds a partly-written file.
    ///
    /// **The permissions are set on the neighbour, before it goes into place** — not corrected
    /// afterwards. A rename inherits the mode of the file being moved, and a freshly written one gets
    /// generic defaults, so correcting it afterwards leaves a gap in which the file is readable by
    /// people the original excluded. That gap is not merely brief: if the process dies inside it, the
    /// file keeps the wrong permissions permanently and silently. Rust's package manager shipped exactly
    /// this bug — writing a settings file reset its mode — and fixed it by setting the mode before the
    /// swap, which is what this does.
    /// The underlying reason, without the wrapper. A failed write arrives wrapped in layers naming the
    /// temporary file; the cause a person can act on is the innermost one ("Permission denied").
    private static func plainCause(_ error: Error) -> String {
        let outer = error as NSError
        if let underlying = outer.userInfo[NSUnderlyingErrorKey] as? NSError {
            return underlying.localizedDescription
        }
        return outer.localizedDescription
    }

    static func replacingContents(of destination: URL, with contents: String) throws {
        // **A pointer to somewhere else is refused, not replaced.** Reading the mode of a symbolic link
        // returns the *link's* own mode — always 0755 here — not that of the file it points at, so a
        // private 0600 file's path ended up holding a world-readable 0755 file while the private file
        // itself sat untouched. Measured, not reasoned about. Nothing escaped the project, because
        // renaming over a name never writes through a pointer; what was untrue was this routine's own
        // promise to keep the permissions the file already had. Turning someone's pointer into an
        // ordinary file is a surprise on its own terms too.
        //
        // Every caller happens to check this already. That is exactly the argument for checking here:
        // the promise above should hold because of what this routine does, not because each caller
        // remembers. **This is a check, not a race that is closed** — a pointer swapped in between here
        // and the rename would still be replaced. The consequence stays bounded for the reason above.
        guard !SafeFile.isSymlink(destination) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError,
                          userInfo: [NSFilePathErrorKey: destination.path,
                                     NSLocalizedDescriptionKey:
                                        "it points somewhere else, and replacing it would turn the pointer into an ordinary file"])
        }
        let directory = destination.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(
            ".\(destination.lastPathComponent).replacing-\(UUID().uuidString)")
        // Read the mode first: after the swap there is nothing left to read it from.
        //
        // **A failure here stops the write.** This used to fall back to whatever the system hands out by
        // default, silently — so a file you had deliberately made private could come back readable by
        // others with no mention of it. Being unable to carry out a safety step is not the same as the
        // step saying "nothing to do", and the direction of the wrong guess here is widening who can read
        // your file. The two causes are told apart because their fixes are unrelated.
        let mode: NSNumber
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            guard let found = attributes[.posixPermissions] as? NSNumber else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError,
                              userInfo: [NSFilePathErrorKey: destination.path,
                                         NSLocalizedDescriptionKey:
                                            "its permissions could not be read, so they could not be preserved"])
            }
            mode = found
        } catch let readFailure as NSError where readFailure.code == NSFileReadUnknownError {
            throw readFailure
        } catch {
            let missing = !FileManager.default.fileExists(atPath: destination.path)
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError,
                          userInfo: [NSFilePathErrorKey: destination.path,
                                     NSLocalizedDescriptionKey: missing
                                        ? "the file to replace is not there"
                                        : "its permissions could not be read, so they could not be preserved: \(plainCause(error))"])
        }

        do { try Data(contents.utf8).write(to: temporary, options: [.withoutOverwriting]) }
        catch {
            // Report the file you asked to write, not the neighbour it travels through. Verified: the
            // raw failure named `.SKILL.md.replacing-E1E6566C-…`, telling you that you lack permission
            // on a randomly-named file you have never seen and cannot find.
            throw NSError(domain: NSCocoaErrorDomain, code: (error as NSError).code,
                          userInfo: [NSFilePathErrorKey: destination.path,
                                     NSLocalizedDescriptionKey: plainCause(error)])
        }
        var placed = false
        defer { if !placed { try? FileManager.default.removeItem(at: temporary) } }

        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: temporary.path)
        // `rename` replaces the destination in one step. Unlike the creating sibling, replacing is the
        // whole point here, so a link that refuses an existing name would be the wrong primitive.
        guard rename(temporary.path, destination.path) == 0 else {
            let code = errno
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError,
                          userInfo: [NSFilePathErrorKey: destination.path,
                                     NSLocalizedDescriptionKey:
                                        "could not replace the file (\(String(cString: strerror(code))))"])
        }
        placed = true
    }
}
