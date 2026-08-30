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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if card.isStale(asOf: now) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                        .help("No activity in over 7 days")
                }
                Text("#\(card.number)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Text(card.title)
                .font(.callout)
                .lineLimit(3)
                // Without this a Text inside a stack truncates instead of
                // wrapping, however high its line limit is.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: alignment)
                // The base direction of this run only. An Arabic paragraph
                // settles against its own edge, which is what makes a wrapped
                // title and any trailing neutrals order correctly.
                .environment(\.layoutDirection, direction.layoutDirection)

            if !card.labels.isEmpty {
                LabelStrip(labels: card.labels)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
        .contentShape(.rect)
        .onTapGesture { open() }
        .help(card.title)
    }

    private var alignment: Alignment {
        direction == .rightToLeft ? .trailing : .leading
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
        HStack(spacing: 4) {
            ForEach(labels, id: \.name) { label in
                Text(label.name)
                    .font(.caption2)
                    .padding(.horizontal, 5)
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
