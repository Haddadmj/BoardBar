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

    /// Resolved per card from the title, not set once for the app.
    ///
    /// Qurba forces right-to-left globally because it is Arabic-only. BoardBar
    /// is not: its column names, timestamps and settings labels are Latin and
    /// only the issue titles are Arabic, so a global force would put all of its
    /// own chrome against the wrong edge.
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
                Text(card.title)
                    .font(.callout)
                    .lineLimit(3)
            }

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
        // The whole rule, in one line: set the base direction and let alignment
        // stay natural. No `.multilineTextAlignment` anywhere in this file, and
        // no `NSTextAlignment.left`/`.right` — those are the absolute values
        // that cannot survive a direction change. `HStack` reverses under this,
        // which is what puts `#20` on the correct side of an Arabic title.
        .environment(\.layoutDirection, direction.layoutDirection)
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
                    .environment(\.layoutDirection, TextDirection.resolve(label.name).layoutDirection)
            }
        }
    }
}
