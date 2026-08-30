import BoardBarCore
import SwiftUI

/// One row of tabs above the board, drawn only when there is more than one
/// board configured.
///
/// With a single board this view is never built at all, so v1's popover and
/// v2's popover with one tab are the same pixels. That is what makes it safe to
/// have built this before a second board exists.
struct TabBarView: View {
    let model: AppModel

    private var boardSet: BoardSet { model.boardSet }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(boardSet.labels.enumerated()), id: \.offset) { index, label in
                    Tab(
                        label: label,
                        isSelected: index == boardSet.selectedIndex,
                        needsAttention: needsAttention(index),
                        select: { model.select(index) }
                    )
                }
            }
            .padding(.horizontal, 2)
        }
        // The tabs are a row of controls in the app's own direction; only each
        // label's text resolves its own base direction, inside `Tab`.
        .environment(\.layoutDirection, .leftToRight)
    }

    /// A background tab that has failed would otherwise be silent until it is
    /// clicked, which is the same mistake as a stale board that looks fresh.
    /// The tab says which one to go and look at; the tab's own footer says what
    /// happened, once it is selected.
    private func needsAttention(_ index: Int) -> Bool {
        guard boardSet.boards.indices.contains(index) else { return false }
        return boardSet.boards[index].lastError != nil
    }
}

private struct Tab: View {
    let label: String
    let isSelected: Bool
    let needsAttention: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    // A project title can be Arabic while the app's chrome is
                    // not. Base direction of this run, and nothing else — the
                    // dot beside it is chrome and stays where it is.
                    .environment(
                        \.layoutDirection, TextDirection.resolve(label).layoutDirection
                    )
                if needsAttention {
                    Circle()
                        .fill(.orange)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                isSelected ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear),
                in: .rect(cornerRadius: 5)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .help(label)
    }
}
