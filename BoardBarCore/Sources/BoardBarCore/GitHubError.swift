import Foundation

public enum GitHubError: Error, Equatable, Sendable {
    /// 401. Distinct from every other failure because nothing will fix it until
    /// the maintainer pastes a new token — ticket 08 replaces the board rather
    /// than annotating it.
    case unauthorized
    case forbidden(String)
    case rateLimited
    case http(status: Int)
    case transport(String)
    case graphQL([String])
    case boardNotFound
    case viewNotFound(number: Int)
    /// The view groups by something this version cannot render as columns —
    /// an iteration, a multi-select, or a plain text field.
    case unsupportedGrouping(typeName: String)
    case malformedResponse(String)

    public var message: String {
        switch self {
        case .unauthorized:
            "Your token was rejected. Paste a new one in Settings."
        case let .forbidden(detail):
            "GitHub refused the request: \(detail)"
        case .rateLimited:
            "Rate-limited by GitHub. The next scheduled poll will retry."
        case let .http(status):
            "GitHub returned HTTP \(status)."
        case let .transport(detail):
            "Couldn't reach GitHub: \(detail)"
        case let .graphQL(messages):
            messages.joined(separator: "; ")
        case .boardNotFound:
            "No project board at that URL, or your token can't see it."
        case let .viewNotFound(number):
            "That project has no view \(number)."
        case let .unsupportedGrouping(typeName):
            "This view groups by \(typeName), which BoardBar can't show as "
                + "columns yet. Showing the project's Status field instead."
        case let .malformedResponse(detail):
            "Unexpected response from GitHub: \(detail)"
        }
    }
}
