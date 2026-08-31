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

    /// The board list, in tab order. Edits to it commit immediately — adding a
    /// board, removing one and dragging one are each an explicit act, and
    /// making them wait behind a Save button would leave the tabs disagreeing
    /// with the list that is on screen.
    @State private var urls: [String] = []
    @State private var draft: String = ""
    @State private var token: String = ""
    @State private var loaded = false

    /// Live validation through the same parser the app runs on, so the messages
    /// are the specific ones — "that's a repository's issues list, not a
    /// project board" beats "invalid URL".
    private var draftError: String? {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let ref: BoardRef
        do {
            ref = try BoardURLParser.parse(trimmed)
        } catch {
            return error.message
        }
        // Refused by name rather than accepted silently: a second tab of the
        // same board would poll it twice and write the same cache file from
        // both, which is worse than being told no.
        guard !urls.contains(where: { (try? BoardURLParser.parse($0))?.storageKey == ref.storageKey })
        else { return "That board is already added." }
        return nil
    }

    private var canAdd: Bool {
        !draft.trimmingCharacters(in: .whitespaces).isEmpty && draftError == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            boards
            Divider()
            tokenField
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 460)
        .background(FloatingWindow())
        // Both fields hold pure ASCII — a URL and a token. This is Qurba's
        // TextInput carve-out: a field resolves its own natural alignment, and
        // forcing a direction onto one holding Latin characters lays them out
        // backwards. So nothing here sets a direction at all.
        .onAppear {
            // Guarded: the window is reused across openings, and re-reading on
            // every appearance would wipe what was half-typed if it ever
            // re-appears without being closed.
            guard !loaded else { return }
            urls = model.boardURLStrings
            loaded = true
        }
    }

    // MARK: - Boards

    private var boards: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Project boards").font(.subheadline.weight(.medium))

            if urls.isEmpty {
                Text("No boards yet. Paste one below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                List {
                    ForEach(Array(urls.enumerated()), id: \.element) { _, url in
                        row(url)
                    }
                    .onMove { source, destination in
                        urls.move(fromOffsets: source, toOffset: destination)
                        commit()
                    }
                }
                .listStyle(.bordered)
                .frame(height: min(CGFloat(urls.count) * 32 + 12, 160))
            }

            HStack(spacing: 6) {
                TextField(
                    "https://github.com/users/you/projects/2/views/1",
                    text: $draft
                )
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onSubmit { add() }
                Button("Add") { add() }
                    .disabled(!canAdd)
            }

            if let draftError {
                Text(draftError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(
                    "Open the board on github.com and copy the URL from the address bar. "
                        + "Drag to reorder — the order here is the order of the tabs."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ url: String) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label(for: url))
                    .font(.callout)
                    .lineLimit(1)
                    // A project title can be Arabic. Base direction of that run
                    // only; the row around it is chrome and does not mirror.
                    .environment(
                        \.layoutDirection, TextDirection.resolve(label(for: url)).layoutDirection
                    )
                Text(url)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Button {
                remove(url)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove this board")
        }
        .padding(.vertical, 1)
    }

    /// The tab's own label where the board has loaded, so the list reads the
    /// way the tab bar does. A board that has never loaded names its project
    /// number rather than going blank.
    private func label(for url: String) -> String {
        guard let ref = try? BoardURLParser.parse(url) else { return url }
        let boards = model.boardSet
        if let index = boards.boards.firstIndex(where: { $0.ref?.storageKey == ref.storageKey }),
            boards.labels.indices.contains(index)
        {
            return boards.labels[index]
        }
        return TabLabel.fallback(for: ref)
    }

    // MARK: - Token

    private var tokenField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("GitHub token").font(.subheadline.weight(.medium))
            // One token for every board. Boards on one account share a
            // credential, and a per-board token is a second thing to get wrong
            // for no gain.
            SecureField(
                model.hasToken ? "A token is stored — type to replace it" : "ghp_…",
                text: $token
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit { saveToken() }
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
                Button("Save token") { saveToken() }
                    .buttonStyle(.link)
                    .font(.caption)
                    .disabled(token.isEmpty)
                Spacer()
                Text("Needs read:project and repo.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Check now") { model.refreshAll() }
                .disabled(urls.isEmpty)
            Spacer()
            // Escape rather than Return: Return belongs to whichever field has
            // focus, and closing the window out from under a half-pasted URL
            // is the sheet bug in a new form.
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: - Actions

    private func add() {
        guard canAdd else { return }
        urls.append(draft.trimmingCharacters(in: .whitespaces))
        draft = ""
        commit()
    }

    private func remove(_ url: String) {
        urls.removeAll { $0 == url }
        // The cache goes with it, in `AppModel.save`. An orphaned cache file
        // would mean a board that was removed and later added back coming up
        // showing what it held before it was removed.
        commit()
    }

    private func saveToken() {
        guard !token.isEmpty else { return }
        model.save(boardURLs: urls, token: token)
        token = ""
    }

    private func commit() {
        model.save(boardURLs: urls, token: nil)
    }
}

/// Keeps the settings window above other apps until it is closed.
///
/// An `LSUIElement` app has no Dock icon and no app-switcher entry, so when it
/// deactivates its windows drop behind whatever was clicked into with no way
/// back to them — the menu-bar icon is the only route, which reads as the
/// window having closed itself.
///
/// Floating is the right answer here rather than a general one, because of what
/// this particular window is for: both fields are filled by going to github.com
/// and copying something. A settings window that hides the moment you go to
/// fetch what it asked for is a window that cannot be used for its only job.
private struct FloatingWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // The view has no window until it is in the hierarchy, which is one
        // run-loop turn after this.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = .floating
            // Follows to whichever Space is in front, rather than yanking that
            // Space back to wherever the window was opened.
            window.collectionBehavior.insert(.moveToActiveSpace)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
