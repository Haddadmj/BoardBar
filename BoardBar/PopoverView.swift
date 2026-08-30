import BoardBarCore
import SwiftUI

struct PopoverView: View {
    let model: AppModel

    @Environment(\.openWindow) private var openWindow

    private var coordinator: BoardCoordinator { model.coordinator }
    private var status: StatusSummary { model.status }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch status.level {
            case .unauthorized:
                // Replaces the board rather than annotating it. A rejected
                // token is not transient — nothing fixes it until it is
                // replaced — so leaving a last-good board visible would be the
                // stale-board mistake in a different costume.
                message(
                    title: "Token rejected",
                    detail: "GitHub refused the stored token. Add a new one to carry on.",
                    systemImage: "exclamationmark.triangle",
                    tint: .orange
                )
            case .empty where coordinator.ref == nil:
                // First run says what is missing and waits. It does not open
                // settings by itself: two windows appearing from one click
                // reads as a glitch, and the choice to configure should be the
                // maintainer's.
                message(
                    title: "No board configured yet",
                    detail: "Add a project board URL and a GitHub token to see your board here.",
                    systemImage: "rectangle.3.group",
                    tint: .secondary
                )
            case .empty:
                message(
                    title: "Loading board…",
                    detail: nil,
                    systemImage: "arrow.clockwise",
                    tint: .secondary
                )
            case .fresh, .stale:
                if let board = coordinator.board {
                    BoardView(board: board, now: model.now)
                }
            }

            Divider()
            footer
        }
        .padding(12)
        .frame(width: needsSetup ? 420 : 640)
        .frame(maxHeight: 520)
        .environment(\.layoutDirection, .leftToRight)
        .task { model.popoverOpened() }
    }

    private var needsSetup: Bool {
        coordinator.board == nil
    }

    private func message(
        title: String, detail: String?, systemImage: String, tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SwiftUI.Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint == .secondary ? .primary : tint)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Open Settings…") { showSettings() }
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if coordinator.isFetching {
                ProgressView().controlSize(.small)
            }
            // Present in every state, including success. A timestamp that only
            // appears during failure is one nobody has learned to read by the
            // time it matters.
            Text(status.footer)
                .font(.caption)
                .foregroundStyle(status.level == .stale ? .orange : .secondary)
            if let warning = status.warning {
                Text("· \(warning)")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            Spacer()
            Button("Settings…") { showSettings() }
            Button("Refresh") { Task { await coordinator.refresh(reason: .manual) } }
                .disabled(coordinator.isFetching || coordinator.ref == nil)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private func showSettings() {
        openWindow(id: SettingsWindowID.value)
        // An LSUIElement app is not in the activation order, so a window it
        // opens comes up behind whatever is in front and cannot take the
        // keyboard. Without this the settings window appears unfocused, which
        // is indistinguishable from it having failed to open.
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
