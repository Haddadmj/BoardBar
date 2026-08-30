import BoardBarCore
import SwiftUI

/// A real window, deliberately not a sheet.
///
/// A MenuBarExtra popover is a transient panel that dismisses itself the moment
/// it stops being the key window. A sheet presented from inside one steals key
/// status, which closes the popover underneath it and takes the sheet with it —
/// the window flickers, loses focus mid-typing, and disappears before a URL can
/// be pasted. Nothing about the sheet can be tuned to fix that; it has to stop
/// living inside the popover.
///
/// Has no poll-interval control: the back-off is the right behaviour, and
/// exposing it invites tuning a number with no observable effect on a solo
/// board.
struct SettingsWindow: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var boardURL: String = ""
    @State private var token: String = ""
    @State private var loaded = false

    /// Live validation through the same parser the app runs on, so the messages
    /// are the specific ones — "that's a repository's issues list, not a
    /// project board" beats "invalid URL".
    private var urlError: BoardURLError? {
        guard !boardURL.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        do {
            _ = try BoardURLParser.parse(boardURL)
            return nil
        } catch {
            return error
        }
    }

    private var canSave: Bool {
        urlError == nil
            && !boardURL.trimmingCharacters(in: .whitespaces).isEmpty
            && (model.hasToken || !token.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Project board URL").font(.subheadline.weight(.medium))
                TextField(
                    "https://github.com/users/you/projects/2/views/1",
                    text: $boardURL
                )
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                if let urlError {
                    Text(urlError.message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Open the board on github.com and copy the URL from the address bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("GitHub token").font(.subheadline.weight(.medium))
                SecureField(
                    model.hasToken ? "A token is stored — type to replace it" : "ghp_…",
                    text: $token
                )
                .textFieldStyle(.roundedBorder)
                HStack(spacing: 6) {
                    Text(model.hasToken ? "A token is stored." : "No token stored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if model.hasToken {
                        Button("Remove") {
                            model.clearToken()
                            token = ""
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                    Spacer()
                    Text("Needs read:project and repo.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            HStack {
                Button("Check now") { save() }
                    .disabled(!canSave)
                Spacer()
                Button("Close") { dismiss() }
                Button("Save") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 460)
        // Both fields hold pure ASCII — a URL and a token. This is Qurba's
        // TextInput carve-out: a field resolves its own natural alignment, and
        // forcing a direction onto one holding Latin characters lays them out
        // backwards. So nothing here sets a direction at all.
        .onAppear {
            // Guarded: the window is reused across openings, and re-reading on
            // every appearance would wipe what was half-typed if it ever
            // re-appears without being closed.
            guard !loaded else { return }
            boardURL = model.boardURLString
            loaded = true
        }
    }

    private func save() {
        model.save(boardURL: boardURL, token: token.isEmpty ? nil : token)
        token = ""
    }
}
