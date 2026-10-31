import BoardBarCore
import SwiftUI

struct BoardView: View {
    let board: Board
    var now: Date = Date()

    static let columnWidth: CGFloat = 200
    static let columnSpacing = Space.s
    /// Past this the lanes scroll on their own, so the popover stays on screen
    /// and a column's header stays in sight above its cards.
    static let maxHeight: CGFloat = 400
    /// A lane's header row and the padding around its cards.
    private static let laneChrome: CGFloat = 20 + Space.s * 3

    /// Width needed to show every column without scrolling, capped so a board
    /// with nine columns does not open a popover wider than the screen, and
    /// floored so a one-column board still has room for the footer's buttons.
    static func preferredWidth(columns: Int) -> CGFloat {
        let content = CGFloat(columns) * columnWidth + CGFloat(max(0, columns - 1)) * columnSpacing
        return max(420, min(content + 28, 900))
    }

    /// How tall each lane's cards came out, by column.
    ///
    /// A vertical ScrollView has no height of its own to offer, and a popover
    /// sizes to its content, so the lanes must be told how tall to be. Left to
    /// itself a tall column overflowed the popover: centred, clipped at both
    /// ends, with nothing to scroll.
    @State private var cardHeights: [Column.ID: CGFloat] = [:]

    /// Read through the current columns only, so a tall board does not hold the
    /// popover open after switching to a short one.
    private var laneHeight: CGFloat {
        let tallest = board.columns.compactMap { cardHeights[$0.id] }.max() ?? 0
        return min(tallest + Self.laneChrome, Self.maxHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if board.isTruncated {
                Notice(
                    text: "Showing \(board.shownCount) of \(board.totalCount) items.",
                    systemImage: "line.3.horizontal.decrease"
                )
            }
            if let filter = board.unappliedFilter {
                Notice(
                    text: "This view's filter (\(filter)) isn't applied — showing the whole board.",
                    systemImage: "exclamationmark.triangle"
                )
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Self.columnSpacing) {
                    ForEach(board.columns) { column in
                        ColumnView(column: column, now: now, width: Self.columnWidth) { height in
                            cardHeights[column.id] = height
                        }
                        .frame(height: laneHeight)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: laneHeight)
        }
        // The board's own chrome is Latin — column names, counts, these
        // notices — so it stays left-to-right regardless of what the cards
        // inside it contain. Direction is set per card, never here.
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// Truncation and dropped filters are stated, never implied by absence. A board
/// that is quietly showing less (or more) than the browser is the same class of
/// mistake as a stale board that looks fresh.
private struct Notice: View {
    let text: String
    let systemImage: String

    var body: some View {
        SwiftUI.Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ColumnView: View {
    let column: Column
    let now: Date
    let width: CGFloat
    let measured: (CGFloat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.xs) {
                Text(column.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text("\(column.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(height: 20)
            .padding(.horizontal, Space.xs)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Space.s) {
                    // An empty column keeps its header and its zero. Hiding it would
                    // change the shape of the board, which is the one thing this is for.
                    if column.cards.isEmpty {
                        Text("—")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, Space.xs)
                    } else {
                        ForEach(column.cards) { card in
                            CardView(card: card, now: now)
                        }
                    }
                }
                .onGeometryChange(for: CGFloat.self, of: \.size.height, action: measured)
            }
            .scrollIndicators(.automatic)
        }
        .padding(Space.s)
        .frame(width: width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: Radius.lane))
    }
}

// MARK: - Previews

private let sampleBoard = Board(
    columns: [
        Column(
            name: "Todo",
            cards: [
                Card(
                    number: 20,
                    title: "اضافة ختمات للغرفه كنوع اضافي وليس كعمل",
                    url: URL(string: "https://github.com/Haddadmj/qurba/issues/20")!,
                    repository: "Haddadmj/qurba",
                    updatedAt: Date(timeIntervalSince1970: 1_756_582_425),
                    labels: [
                        IssueLabel(name: "from-app", color: "0e8a16"),
                        IssueLabel(name: "feature-request", color: "5319e7"),
                    ]
                ),
                Card(
                    number: 21,
                    title: "Fix the poll scheduler back-off",
                    url: URL(string: "https://github.com/Haddadmj/qurba/issues/21")!,
                    repository: "Haddadmj/qurba",
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    labels: [IssueLabel(name: "bug", color: "d73a4a")]
                ),
            ]
        ),
        Column(name: "In Progress", cards: []),
        Column(name: "Done", cards: []),
        Column(name: "Rejected", cards: []),
    ],
    columnSource: .view,
    fetchedAt: Date(timeIntervalSince1970: 1_756_582_425),
    totalCount: 2
)

#Preview("Board") {
    BoardView(board: sampleBoard, now: Date(timeIntervalSince1970: 1_756_582_425))
        .padding()
        .frame(width: 620, height: 320)
}
