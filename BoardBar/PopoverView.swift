import BoardBarCore
import SwiftUI

struct PopoverView: View {
    let model: AppModel
    @State private var showsSettings = false

    private var coordinator: BoardCoordinator { model.coordinator }
    private var status: StatusSummary { model.status }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch status.level {
            case .unauthorized:
                // Replaces the board rather than annotating it. A rejected
                // token is not transient — nothing will fix it until it is
                // replaced — so leaving a last-good board visible would be the
                // stale-board mistake in a different costume.
                reauthPrompt
            case .empty:
                placeholder
            case .fresh, .stale:
                if let board = coordinator.board {
                    BoardView(board: board, now: model.now)
                }
            }

            Divider()
            footer
        }
        .padding(12)
        .frame(width: 640)
        .frame(maxHeight: 520)
        .environment(\.layoutDirection, .leftToRight)
        .task {
            model.popoverOpened()
            // A first run has nothing to show and nothing to explain, so it
            // opens the sheet rather than an empty board.
            if model.needsConfiguration { showsSettings = true }
        }
        .sheet(isPresented: $showsSettings) { SettingsSheet(model: model) }
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
            Button("Settings") { showsSettings = true }
            Button("Refresh") { Task { await coordinator.refresh(reason: .manual) } }
                .disabled(coordinator.isFetching)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private var reauthPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            SwiftUI.Label("Token rejected", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("GitHub refused the stored token. Paste a new one to carry on.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Settings") { showsSettings = true }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(coordinator.ref == nil ? "No board configured" : "Loading board…")
                .font(.headline)
            if coordinator.ref == nil {
                Text("Paste a project board URL in Settings to get started.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
    }
}
