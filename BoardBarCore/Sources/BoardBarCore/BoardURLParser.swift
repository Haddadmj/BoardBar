import Foundation

public enum BoardURLError: Error, Equatable, Sendable {
    case empty
    case notAURL
    case notGitHub(host: String)
    case looksLikeRepoIssues
    case looksLikeRepo
    case missingProjectSegment
    case projectNumberNotAnInteger(String)
    case viewNumberNotAnInteger(String)

    /// Written to be acted on, not just read. "That looks like a repository
    /// URL, not a project board" tells you what to go and find; "invalid URL"
    /// does not.
    public var message: String {
        switch self {
        case .empty:
            "Paste a project board URL."
        case .notAURL:
            "That isn't a URL."
        case let .notGitHub(host):
            "That points at \(host), not github.com."
        case .looksLikeRepoIssues:
            "That's a repository's issues list, not a project board. Open the "
                + "board on github.com and copy the URL from there — it looks "
                + "like github.com/users/you/projects/2."
        case .looksLikeRepo:
            "That's a repository URL, not a project board."
        case .missingProjectSegment:
            "That github.com URL isn't a project board. A board URL looks like "
                + "github.com/users/you/projects/2 or github.com/orgs/team/projects/2."
        case let .projectNumberNotAnInteger(found):
            "Expected a project number after /projects/, found \"\(found)\"."
        case let .viewNumberNotAnInteger(found):
            "Expected a view number after /views/, found \"\(found)\"."
        }
    }
}

public enum BoardURLParser {
    /// Parses `https://github.com/{users|orgs}/{owner}/projects/{n}[/views/{v}]`.
    ///
    /// Tolerates what GitHub actually puts in the address bar: a trailing
    /// slash, and a query string such as `?pane=issue&itemId=…` that appears
    /// whenever a card is open when the URL is copied.
    public static func parse(_ raw: String) throws(BoardURLError) -> BoardRef {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }

        // Accept a bare "github.com/..." paste as well as a full URL.
        let normalized = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let components = URLComponents(string: normalized), let host = components.host else {
            throw .notAURL
        }
        let bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        guard bareHost == "github.com" else { throw .notGitHub(host: bareHost) }

        let segments = components.path.split(separator: "/").map(String.init)

        guard let kindSegment = segments.first, let kind = BoardRef.OwnerKind(rawValue: kindSegment)
        else {
            // /owner/repo/issues and /owner/repo are the two wrong URLs most
            // likely to be pasted, and each earns its own message.
            if segments.count >= 3, segments[2] == "issues" { throw .looksLikeRepoIssues }
            if segments.count == 2 { throw .looksLikeRepo }
            throw .missingProjectSegment
        }

        guard segments.count >= 4, segments[2] == "projects" else { throw .missingProjectSegment }
        let owner = segments[1]
        guard let projectNumber = Int(segments[3]) else {
            throw .projectNumberNotAnInteger(segments[3])
        }

        var viewNumber: Int?
        if segments.count >= 5 {
            guard segments[4] == "views" else { throw .missingProjectSegment }
            guard segments.count >= 6, let parsed = Int(segments[5]) else {
                throw .viewNumberNotAnInteger(segments.count >= 6 ? segments[5] : "")
            }
            viewNumber = parsed
        }

        return BoardRef(
            ownerKind: kind,
            owner: owner,
            projectNumber: projectNumber,
            viewNumber: viewNumber
        )
    }
}

extension BoardURLParser {
    /// v1's single-board key. Still read by the migration below, and
    /// deliberately never written or deleted by v2 — see `migrateIfNeeded`.
    public static let defaultsKey = "boardURL"
    /// v2's ordered list of board URLs. Order is the tab order, so it is the
    /// user's and must round-trip exactly.
    public static let listDefaultsKey = "boardURLs"
    /// Records that the one-time seed from `boardURL` has happened.
    ///
    /// The presence of `boardURLs` cannot play this role. Removing the last
    /// board clears that key, which would leave the migration looking at a
    /// fresh v1 install again and silently resurrect the board that was just
    /// deleted.
    public static let migratedKey = "boardURLsMigrated"

    /// The configured board URLs, in tab order, exactly as they were entered.
    ///
    /// Raw strings rather than refs, because Settings edits what was typed and
    /// a round-trip through `BoardRef` would rewrite a paste the user
    /// recognises into a canonical form they did not.
    public static func storedURLs(defaults: UserDefaults = .standard) -> [String] {
        migrateIfNeeded(defaults: defaults)
        return defaults.stringArray(forKey: listDefaultsKey) ?? []
    }

    /// The configured boards, in tab order. Entries that no longer parse are
    /// dropped rather than thrown: one bad row in the list must not cost the
    /// rest of the list, and there is no one to report it to at launch.
    public static func storedRefs(defaults: UserDefaults = .standard) -> [BoardRef] {
        storedURLs(defaults: defaults).compactMap { try? parse($0) }
    }

    public static func store(urls: [String], defaults: UserDefaults = .standard) {
        // Writing the flag here too: saving a list is as much a statement that
        // the list is now v2's business as the migration itself is.
        defaults.set(true, forKey: migratedKey)
        let cleaned = urls.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else {
            defaults.removeObject(forKey: listDefaultsKey)
            return
        }
        defaults.set(cleaned, forKey: listDefaultsKey)
    }

    /// Seeds the list from v1's single key, once.
    ///
    /// `boardURL` is left in place. It costs nothing, and keeping it means a
    /// build of v2 that has to be rolled back does not lose the board that was
    /// already configured. Removing it is its own change, made deliberately
    /// once v2 has been in use for a while.
    public static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: migratedKey) else { return }
        defaults.set(true, forKey: migratedKey)
        guard defaults.stringArray(forKey: listDefaultsKey) == nil,
            let legacy = defaults.string(forKey: defaultsKey),
            !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        defaults.set([legacy], forKey: listDefaultsKey)
    }
}
