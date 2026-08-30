import BoardBarCore
import SwiftUI

struct BoardView: View {
    let board: Board
    var now: Date = Date()

    static let columnWidth: CGFloat = 190
    static let columnSpacing: CGFloat = 10

    /// Width needed to show every column without scrolling, capped so a board
    /// with nine columns does not open a popover wider than the screen.
    static func preferredWidth(columns: Int) -> CGFloat {
        let content = CGFloat(columns) * columnWidth + CGFloat(max(0, columns - 1)) * columnSpacing
        return min(content + 28, 900)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                        ColumnView(column: column, now: now, width: Self.columnWidth)
                    }
                }
                .padding(.horizontal, 2)
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(column.name)
                    .font(.caption.weight(.semibold))
                Text("\(column.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)

            // An empty column keeps its header and its zero. Hiding it would
            // change the shape of the board, which is the one thing this is for.
            if column.cards.isEmpty {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 2)
            } else {
                ForEach(column.cards) { card in
                    CardView(card: card, now: now)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .leading)
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
