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
    public static let defaultsKey = "boardURL"

    /// The configured board, or nil when none has been set yet.
    ///
    /// The URL is configuration rather than a secret — it names a board, not a
    /// credential — so `UserDefaults` is the right home for it. The token is
    /// the thing that must never land here.
    public static func storedRef(defaults: UserDefaults = .standard) -> BoardRef? {
        guard let raw = defaults.string(forKey: defaultsKey) else { return nil }
        return try? parse(raw)
    }

    public static func store(_ raw: String?, defaults: UserDefaults = .standard) {
        guard let raw, !raw.isEmpty else {
            defaults.removeObject(forKey: defaultsKey)
            return
        }
        defaults.set(raw, forKey: defaultsKey)
    }
}
