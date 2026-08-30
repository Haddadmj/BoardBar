import Foundation
import Testing

@testable import BoardBarCore

private func ref(_ project: Int, view: Int?) -> BoardRef {
    BoardRef(ownerKind: .users, owner: "Haddadmj", projectNumber: project, viewNumber: view)
}

private func board(project: String?, view: String?) -> Board {
    Board(
        columns: [], columnSource: .view,
        fetchedAt: Date(timeIntervalSince1970: 1_800_000_000), totalCount: 0,
        projectTitle: project, viewName: view
    )
}

@Suite("Tab labels")
struct TabLabelTests {
    @Test("one tab per project is named after the project")
    func distinctProjects() {
        let labels = TabLabel.labels(for: [
            (ref(2, view: 2), board(project: "Qurba bug reports", view: "Main Board")),
            (ref(3, view: 1), board(project: "Site rebuild", view: "Board")),
        ])
        #expect(labels == ["Qurba bug reports", "Site rebuild"])
    }

    /// Two tabs reading "Qurba bug reports" tell you nothing.
    @Test("two views of one project are named after the views")
    func sharedProject() {
        let labels = TabLabel.labels(for: [
            (ref(2, view: 2), board(project: "Qurba bug reports", view: "Main Board")),
            (ref(2, view: 3), board(project: "Qurba bug reports", view: "My Items")),
        ])
        #expect(labels == ["Main Board", "My Items"])
    }

    /// Sharing a project changes the label of *those* tabs only.
    @Test("a third tab on its own project keeps its project title")
    func mixedList() {
        let labels = TabLabel.labels(for: [
            (ref(2, view: 2), board(project: "Qurba bug reports", view: "Main Board")),
            (ref(2, view: 3), board(project: "Qurba bug reports", view: "My Items")),
            (ref(9, view: 1), board(project: "Site rebuild", view: "Board")),
        ])
        #expect(labels == ["Main Board", "My Items", "Site rebuild"])
    }

    @Test("a board that has never loaded is still identifiable")
    func neverLoaded() {
        let labels = TabLabel.labels(for: [
            (ref(2, view: 2), nil),
            (ref(7, view: nil), nil),
        ])
        #expect(labels == ["Project 2 · View 2", "Project 7"])
    }

    /// A v1 cache decodes with no names at all, and one unreachable tab must
    /// not go blank next to one that loaded.
    @Test("a board without names falls back rather than rendering empty")
    func namelessBoard() {
        let labels = TabLabel.labels(for: [
            (ref(2, view: 2), board(project: nil, view: nil)),
            (ref(2, view: 3), board(project: "Qurba bug reports", view: nil)),
        ])
        #expect(labels == ["Project 2 · View 2", "Qurba bug reports"])
    }
}
