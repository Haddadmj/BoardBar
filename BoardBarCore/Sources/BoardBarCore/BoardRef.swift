import Foundation

/// A pointer to one GitHub Projects v2 board view.
///
/// The owner is always parsed from the pasted URL and never defaulted to the
/// maintainer's own account. That costs nothing here — the URL is being parsed
/// regardless — and it is one of the three shortcuts the spec pre-pays so a
/// possible public release later is not a migration.
public struct BoardRef: Codable, Hashable, Sendable {
    public enum OwnerKind: String, Codable, Sendable {
        case users
        case orgs
    }

    public let ownerKind: OwnerKind
    public let owner: String
    public let projectNumber: Int
    /// nil when the URL carried no `/views/{n}`, which sends ticket 04 down its
    /// fallback path: columns from the project's `Status` field, unfiltered.
    public let viewNumber: Int?

    public init(ownerKind: OwnerKind, owner: String, projectNumber: Int, viewNumber: Int?) {
        self.ownerKind = ownerKind
        self.owner = owner
        self.projectNumber = projectNumber
        self.viewNumber = viewNumber
    }

    /// Stable key for the App Group store (ticket 05). Keyed per board rather
    /// than a single `board.json` so two widgets can show two boards later
    /// without migrating what is already on disk.
    public var storageKey: String {
        "\(ownerKind.rawValue)-\(owner)-\(projectNumber)-\(viewNumber.map(String.init) ?? "default")"
    }
}
