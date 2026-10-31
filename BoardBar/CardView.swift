import BoardBarCore
import SwiftUI

extension Color {
    /// GitHub returns label colours as six hex digits with no leading `#`.
    init?(githubHex hex: String) {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension BaseDirection {
    var layoutDirection: LayoutDirection {
        self == .rightToLeft ? .rightToLeft : .leftToRight
    }
}

struct CardView: View {
    let card: Card
    let now: Date

    /// The base direction of the **title text**, and nothing else.
    ///
    /// Not applied to the card. Setting `layoutDirection` on the container
    /// mirrors the view hierarchy — it reverses the HStack and the label strip,
    /// putting "#20" on the right and rendering the labels backwards from the
    /// order GitHub returns them. That is view mirroring, which is the half
    /// Qurba explicitly disables in `src/theme/rtl.ts`; its `writingDirection`
    /// rule is about the base direction of a text run.
    ///
    /// The issue number, the staleness dot and the label chips are app chrome,
    /// not part of the Arabic sentence, so they follow the app's direction. The
    /// title is the only thing here that is actually Arabic.
    private var direction: BaseDirection { TextDirection.resolve(card.title) }

    @State private var isHovered = false

    var body: some View {
        // A real button rather than a tap gesture, so a card is a control to
        // VoiceOver and not just some text that happens to respond.
        Button(action: open) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    if card.isStale(asOf: now) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                            .help("No activity in over 7 days")
                    }
                    Text("#\(card.number)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }

                Text(card.title)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    // Without this a Text inside a stack truncates instead of
                    // wrapping, however high its line limit is.
                    .fixedSize(horizontal: false, vertical: true)
                    // `.leading`, not a side chosen by direction. Leading is
                    // logical and the environment below reaches this frame too,
                    // so it already means the right edge for an Arabic title.
                    // Asking for `.trailing` there lands on the left, which is
                    // the swap the README warns about.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The base direction of this run only. An Arabic paragraph
                    // settles against its own edge, which is what makes a wrapped
                    // title and any trailing neutrals order correctly.
                    .environment(\.layoutDirection, direction.layoutDirection)

                if !card.labels.isEmpty {
                    LabelStrip(labels: card.labels)
                        .padding(.top, Space.xs)
                }
            }
            .padding(Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: isHovered ? .selectedContentBackgroundColor : .controlBackgroundColor)
                    .opacity(isHovered ? 0.12 : 1),
                in: .rect(cornerRadius: Radius.card)
            )
            .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(card.title)
    }

    /// Opens the issue on github.com and gets out of the way. The card body is
    /// deliberately not expandable in place: the body would want comments, and
    /// comments would want a reply box, and the popover would become the work
    /// surface this app exists not to be.
    private func open() {
        NSWorkspace.shared.open(card.url)
        // The popover for a `.window`-style MenuBarExtra is an ordinary window,
        // and closing the key window is the only supported way to dismiss it —
        // `@Environment(\.dismiss)` does not reach it.
        NSApplication.shared.keyWindow?.close()
    }
}

/// Label chips keep their own direction: a Latin label name inside an Arabic
/// card must not have its characters reordered.
private struct LabelStrip: View {
    let labels: [IssueLabel]

    var body: some View {
        FlowLayout(spacing: Space.xs) {
            ForEach(labels, id: \.name) { label in
                Text(label.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, Space.xs + 2)
                    .padding(.vertical, 1)
                    .background(
                        (Color(githubHex: label.color) ?? .secondary).opacity(0.25),
                        in: .capsule
                    )
                    // Chips sit in the app's direction so they stay in the
                    // order GitHub returns them; only the chip's own text
                    // resolves its base direction.
                    .environment(\.layoutDirection, TextDirection.resolve(label.name).layoutDirection)
            }
        }
    }
}

/// Lays its children out left to right, wrapping when a row is full.
///
/// A plain HStack has nowhere to put five labels in a card this narrow, so it
/// squeezes them until each one wraps inside its own capsule. No stack in
/// SwiftUI wraps, so this one is written out.
private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(in: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var y = bounds.minY
        for row in rows(in: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for (index, size) in row.items {
                subviews[index].place(
                    at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(in width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            // Capped at the row, so one very long label truncates rather than
            // pushing past the edge of the card.
            let natural = subviews[index].sizeThatFits(.unspecified)
            let size = CGSize(width: min(natural.width, width), height: natural.height)
            if !row.items.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append((index, size))
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
