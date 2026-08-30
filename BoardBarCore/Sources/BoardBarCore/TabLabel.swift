import Foundation

/// What to write on a tab.
///
/// Deliberately not a property on `Board`: the right label depends on the
/// *other* tabs, and a board knows nothing about them. It carries both strings
/// and this decides between them.
///
/// It lives in the package rather than beside the tab bar because it is a rule
/// about strings, with no view in it — which makes it the kind of thing that
/// can be checked in a test rather than by opening the popover and squinting.
public enum TabLabel {
    /// Labels for the configured boards, in the same order.
    ///
    /// Shows the **view name** when more than one tab points at the same
    /// project, and the **project title** otherwise. Two tabs both reading
    /// "Qurba bug reports" tell you nothing; "Main Board" and "My Items" do.
    ///
    /// A board that has never loaded falls back to its project number, so a
    /// tab for an unreachable board is still identifiable rather than blank.
    public static func labels(for boards: [(ref: BoardRef, board: Board?)]) -> [String] {
        var tabsPerProject: [String: Int] = [:]
        for entry in boards {
            tabsPerProject[projectKey(entry.ref), default: 0] += 1
        }

        return boards.map { entry in
            let sharesProject = (tabsPerProject[projectKey(entry.ref)] ?? 0) > 1
            let candidates =
                sharesProject
                ? [entry.board?.viewName, entry.board?.projectTitle]
                : [entry.board?.projectTitle, entry.board?.viewName]
            let found = candidates.compactMap { $0 }.first { !$0.isEmpty }
            return found ?? fallback(for: entry.ref)
        }
    }

    /// Two views of one project are two tabs, so the view number is
    /// deliberately not part of this.
    private static func projectKey(_ ref: BoardRef) -> String {
        "\(ref.ownerKind.rawValue)-\(ref.owner)-\(ref.projectNumber)"
    }

    /// Names the view too when there is one, because two tabs on the same
    /// unreachable project would otherwise be the same word twice.
    public static func fallback(for ref: BoardRef) -> String {
        guard let view = ref.viewNumber else { return "Project \(ref.projectNumber)" }
        return "Project \(ref.projectNumber) · View \(view)"
    }
}
