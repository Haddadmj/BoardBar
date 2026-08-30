import Foundation

/// What the popover should be showing, and how the menu-bar icon should look.
///
/// Derived rather than stored, so there is exactly one place that decides —
/// two surfaces disagreeing about whether data is stale is the failure this
/// type exists to prevent.
public enum StatusLevel: String, Sendable, Equatable {
    /// A board, fetched recently enough to trust at a glance.
    case fresh
    /// A board, but old enough that showing it without saying so would mislead.
    case stale
    /// The token was rejected. Nothing will fix this until it is replaced, so
    /// it replaces the board rather than annotating it.
    case unauthorized
    /// Nothing has ever been fetched.
    case empty
}

public struct StatusSummary: Sendable, Equatable {
    public let level: StatusLevel
    /// Always present, in every state including success. A timestamp that only
    /// appears when something is wrong is a timestamp nobody has learned to
    /// read by the time it matters.
    public let footer: String
    /// Set when the last refresh failed but a usable board is still on screen.
    public let warning: String?

    public var dimsMenuBarIcon: Bool { level == .stale }
    public var showsErrorIcon: Bool { level == .unauthorized }
}

public enum Freshness {
    /// Past this, the menu-bar icon dims. The popover always shows the exact
    /// age; the icon only needs to say "do not trust this at a glance", because
    /// it is looked at without focus and silence there is what misleads.
    public static let staleAfter: TimeInterval = 30 * 60

    public static func summarize(
        hasBoard: Bool,
        lastFetchedAt: Date?,
        error: GitHubError?,
        now: Date,
        staleAfter: TimeInterval = Freshness.staleAfter
    ) -> StatusSummary {
        // Checked before anything else: a 401 is not a degraded board, it is no
        // board at all until the maintainer acts.
        if error == .unauthorized {
            return StatusSummary(
                level: .unauthorized,
                footer: "Token rejected",
                warning: nil
            )
        }

        guard hasBoard, let lastFetchedAt else {
            return StatusSummary(
                level: .empty,
                footer: error.map { $0.message } ?? "Never updated",
                warning: nil
            )
        }

        let age = now.timeIntervalSince(lastFetchedAt)
        return StatusSummary(
            level: age > staleAfter ? .stale : .fresh,
            footer: "Updated \(relativeAge(age))",
            // A failure with a good board still on screen is stated, not hidden
            // behind an unchanged-looking board.
            warning: error?.message
        )
    }

    /// Coarse on purpose. "Updated 37m ago" and "Updated 40m ago" mean the same
    /// thing to someone glancing at a board, and a footer that changes every
    /// second is a footer that draws the eye for no reason.
    public static func relativeAge(_ age: TimeInterval) -> String {
        switch age {
        case ..<60: "just now"
        case ..<3600: "\(Int(age / 60))m ago"
        case ..<86400: "\(Int(age / 3600))h ago"
        default: "\(Int(age / 86400))d ago"
        }
    }
}
