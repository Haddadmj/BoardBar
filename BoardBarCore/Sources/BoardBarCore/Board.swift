import Foundation

public struct IssueLabel: Codable, Hashable, Sendable {
    public let name: String
    /// Six-digit hex, no leading `#`, as GitHub returns it.
    public let color: String

    public init(name: String, color: String) {
        self.name = name
        self.color = color
    }
}

public struct Card: Codable, Hashable, Sendable, Identifiable {
    public let number: Int
    public let title: String
    public let url: URL
    public let repository: String
    public let updatedAt: Date
    public let labels: [IssueLabel]

    public var id: Int { number }

    public init(
        number: Int, title: String, url: URL,
        repository: String, updatedAt: Date, labels: [IssueLabel]
    ) {
        self.number = number
        self.title = title
        self.url = url
        self.repository = repository
        self.updatedAt = updatedAt.wholeSeconds
        self.labels = labels
    }

    /// Ticket 07 renders a dot past this threshold. It is the one thing the
    /// popover shows that github.com's own board does not.
    public func isStale(asOf now: Date, threshold: TimeInterval = 7 * 24 * 3600) -> Bool {
        now.timeIntervalSince(updatedAt) > threshold
    }
}

public struct Column: Codable, Hashable, Sendable, Identifiable {
    public let name: String
    public let cards: [Card]

    public var id: String { name }
    public var count: Int { cards.count }

    public init(name: String, cards: [Card]) {
        self.name = name
        self.cards = cards
    }
}

public struct Board: Codable, Hashable, Sendable {
    /// Which of the two column-resolution paths produced this board. Surfaced
    /// so a board that silently fell back does not look like the view being
    /// mirrored faithfully.
    public enum ColumnSource: String, Codable, Sendable {
        case view
        case statusFieldFallback
    }

    public let columns: [Column]
    public let columnSource: ColumnSource
    public let fetchedAt: Date
    /// Total items the server reports. Compared against the number actually
    /// fetched so truncation is visible rather than silent.
    public let totalCount: Int
    /// A view filter that was fetched but could not be applied. Non-nil means
    /// the board on screen is wider than the board in the browser.
    public let unappliedFilter: String?

    public var shownCount: Int { columns.reduce(0) { $0 + $1.count } }
    public var isTruncated: Bool { totalCount > shownCount }

    public init(
        columns: [Column], columnSource: ColumnSource, fetchedAt: Date,
        totalCount: Int, unappliedFilter: String? = nil
    ) {
        self.columns = columns
        self.columnSource = columnSource
        self.fetchedAt = fetchedAt.wholeSeconds
        self.totalCount = totalCount
        self.unappliedFilter = unappliedFilter
    }
}

extension Date {
    /// Dates on a `Board` are stored to whole seconds.
    ///
    /// Not a rounding preference — a correctness requirement. The board is
    /// JSON-encoded as ISO-8601, which has no sub-second component, so a
    /// `Date()` with a fractional part would come back different from what went
    /// in and `saved == loaded` would be false forever. Nothing here needs
    /// finer resolution than a second: `fetchedAt` drives an "updated 40m ago"
    /// footer, and `updatedAt` arrives from GitHub already truncated.
    var wholeSeconds: Date {
        Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.down))
    }
}
