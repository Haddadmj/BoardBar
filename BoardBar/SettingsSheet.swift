import BoardBarCore
import SwiftUI

/// A sheet, not a Preferences window — there is no window in this app to hang
/// one off. Deliberately has no poll-interval control: the back-off is the
/// right behaviour, and exposing it invites tuning a number with no observable
/// effect on a solo board.
struct SettingsSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var boardURL: String = ""
    @State private var token: String = ""

    /// Live validation, using the same parser the app runs on. Its messages are
    /// specific enough to act on — "that's a repository's issues list, not a
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
        urlError == nil && !boardURL.trimmingCharacters(in: .whitespaces).isEmpty
            && (model.hasToken || !token.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BoardBar Settings").font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Project board URL").font(.subheadline)
                TextField(
                    "https://github.com/users/you/projects/2/views/1",
                    text: $boardURL
                )
                .textFieldStyle(.roundedBorder)
                if let urlError {
                    Text(urlError.message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("GitHub token").font(.subheadline)
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
                        Button("Remove") { model.clearToken(); token = "" }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
                Text("Needs the read:project and repo scopes.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            HStack {
                Button("Check now") {
                    model.save(boardURL: boardURL, token: token.isEmpty ? nil : token)
                    token = ""
                }
                .disabled(!canSave)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    model.save(boardURL: boardURL, token: token.isEmpty ? nil : token)
                    token = ""
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(16)
        .frame(width: 420)
        // Both fields hold pure ASCII — a URL and a token. This is Qurba's
        // `TextInput` carve-out: a field resolves its own natural alignment,
        // and forcing a direction onto one holding Latin characters lays them
        // out backwards. So nothing here sets a direction at all.
        .onAppear { boardURL = model.boardURLString }
    }
}
