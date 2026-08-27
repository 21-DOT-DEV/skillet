import Foundation

/// Two entries in one set of results answer to the same name, so which one a comparison means is not
/// decidable. Carried out to whoever read the file, because only they know which file to name.
public struct RepeatedName: Error, CustomStringConvertible, Equatable {
    public let name: String
    public init(name: String) { self.name = name }
    public var description: String { "two entries are both named '\(name)'" }

    /// The same fault, classified for a person: a **file that is wrong**, not a defect in this tool.
    /// Left unclassified it surfaced as an internal error — the code that means "we owe you a fix" — for
    /// a saved file an older version or a merge had produced, with no remedy attached. Nothing reads a
    /// saved file from the command line today, so this is not reachable yet; it is here so the first
    /// command that does reads correctly rather than blaming itself.
    public func asInvalidArtifact(path: String) -> EDDError {
        .invalidArtifact(
            path: path, reason: description,
            fix: "give each entry its own name — results are matched up by it, so a name that means two "
                + "things leaves a comparison unable to say which it is about")
    }
}

/// A set of results in which **no two entries share a name** — and which cannot be built if any do.
///
/// **Why a type rather than a check.** A test's name is the key every comparison joins on: before against
/// after, with-skill against without, this week's results against last week's. Those comparisons used to
/// build their own lookup with a rule that kept the first entry for a name and silently discarded the
/// rest — so two tests sharing a name meant one test's result vanished from the comparison, and a
/// regression could disappear with it. Measured: two tests both named `same`, the first improving and the
/// second getting worse, produced one row reading `+1.00`, the verdict "no test scored lower", and an
/// offer to apply the edit.
///
/// Checking for repeats at each comparison would have been the same rule written four times, re-verifying
/// something a reader of the file already established. Instead the guarantee is carried *in the type*: a
/// comparison takes one of these, so it has nothing to decide and no rule to get wrong, and the four
/// discard-the-rest lines are gone rather than merely unreachable.
public struct UniqueByName<Element> {
    /// The entries, in the order they were given.
    public let items: [Element]
    /// Their names, in the same order.
    public let names: [String]
    private let byName: [String: Element]

    /// Fails when two entries share a name, naming the one that repeats.
    public init(_ items: [Element], name: (Element) -> String) throws {
        var byName: [String: Element] = [:]
        var names: [String] = []
        for item in items {
            let key = name(item)
            guard byName.updateValue(item, forKey: key) == nil else { throw RepeatedName(name: key) }
            names.append(key)
        }
        self.items = items
        self.names = names
        self.byName = byName
    }

    public subscript(_ name: String) -> Element? { byName[name] }
    public var isEmpty: Bool { items.isEmpty }
}

/// Passing one of these between concurrent tasks is safe whenever its contents are — stated explicitly
/// so it can be handed across a boundary without the compiler having to be argued with.
extension UniqueByName: Sendable where Element: Sendable {}
