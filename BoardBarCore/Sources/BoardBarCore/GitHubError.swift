import Foundation

public enum GitHubError: Error, Equatable, Sendable {
    /// 401. Distinct from every other failure because nothing will fix it until
    /// the maintainer pastes a new token — ticket 08 replaces the board rather
    /// than annotating it.
    case unauthorized
    /// No token has been stored yet. Not `unauthorized`: GitHub has refused
    /// nothing, and telling someone mid-setup their token was rejected sends
    /// them looking for a problem they do not have.
    case missingToken
    /// The Keychain could not be read — locked, usually, and usually temporary.
    /// Says nothing about whether the token is any good.
    case keychain(String)
    case forbidden(String)
    case rateLimited
    case http(status: Int)
    case transport(String)
    case graphQL([String])
    case boardNotFound
    case viewNotFound(number: Int)
    case malformedResponse(String)

    public var message: String {
        switch self {
        case .unauthorized:
            "Your token was rejected. Paste a new one in Settings."
        case .missingToken:
            "No token stored. Add one in Settings."
        case let .keychain(detail):
            detail
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
        case let .malformedResponse(detail):
            "Unexpected response from GitHub: \(detail)"
        }
    }
}
