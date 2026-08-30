import Foundation
import Testing

@testable import BoardBarCore

private func makeBoard(
    todo: [Card] = [], fetchedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
) -> Board {
    Board(
        columns: [
            Column(name: "Todo", cards: todo),
            Column(name: "In Progress", cards: []),
            Column(name: "Done", cards: []),
            Column(name: "Rejected", cards: []),
        ],
        columnSource: .view,
        fetchedAt: fetchedAt,
        totalCount: todo.count
    )
}

private let issue20 = Card(
    number: 20,
    title: "اضافة ختمات للغرفه كنوع اضافي وليس كعمل",
    url: URL(string: "https://github.com/Haddadmj/qurba/issues/20")!,
    repository: "Haddadmj/qurba",
    updatedAt: Date(timeIntervalSince1970: 1_756_582_425),
    labels: [IssueLabel(name: "from-app", color: "0e8a16")]
)

private let refA = BoardRef(ownerKind: .users, owner: "Haddadmj", projectNumber: 2, viewNumber: 2)
private let refB = BoardRef(ownerKind: .users, owner: "Haddadmj", projectNumber: 2, viewNumber: 3)

private func contract(_ store: some BoardStore) throws {
    try store.clear(refA)
    try store.clear(refB)
    #expect(store.load(refA) == nil, "an empty store loads nil, not an error")

    let board = makeBoard(todo: [issue20])
    try store.save(board, for: refA)
    let loaded = try #require(store.load(refA))
    #expect(loaded == board, "a board round-trips unchanged, Arabic title included")

    // Keyed per board: saving one must not disturb another. If these collided,
    // two widgets would silently overwrite each other.
    #expect(store.load(refB) == nil)
    try store.save(makeBoard(), for: refB)
    #expect(store.load(refA)?.shownCount == 1)
    #expect(store.load(refB)?.shownCount == 0)

    try store.clear(refA)
    #expect(store.load(refA) == nil)
    #expect(store.load(refB) != nil, "clearing one board leaves the other alone")

    // Clearing something that isn't there is not an error.
    try store.clear(refA)
}

@Suite("Board storage")
struct BoardStoreTests {
    @Test("the in-memory store honours the contract")
    func inMemory() throws {
        try contract(InMemoryBoardStore())
    }

    @Test("the file store honours the same contract")
    func fileStore() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("boardbar-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try contract(FileBoardStore(directory: dir))
    }

    @Test("the file store creates its directory rather than failing")
    func createsDirectory() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("boardbar-tests-\(UUID().uuidString)")
            .appendingPathComponent("nested")
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let store = FileBoardStore(directory: dir)
        try store.save(makeBoard(todo: [issue20]), for: refA)
        #expect(store.load(refA)?.shownCount == 1)
    }

    /// A cache that cannot be decoded is the same as no cache. It must never
    /// become an error the maintainer has to clear by hand.
    @Test("a corrupt file reads as no cache, not as a failure")
    func corruptFile() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("boardbar-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileBoardStore(directory: dir)
        try store.save(makeBoard(), for: refA)

        let file = dir.appendingPathComponent("board-\(refA.storageKey).json")
        try Data("not json".utf8).write(to: file)
        #expect(store.load(refA) == nil)
    }

    /// The staleness model in ticket 08 reads `fetchedAt` off whatever is
    /// stored. If a failed poll could touch it, "updated 40m ago" would be a
    /// decoration rather than a fact.
    @Test("a failed fetch leaves the stored board and its timestamp untouched")
    func failedFetchDoesNotDisturbTheCache() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("boardbar-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileBoardStore(directory: dir)

        let original = makeBoard(todo: [issue20], fetchedAt: Date(timeIntervalSince1970: 1_000))
        try store.save(original, for: refA)

        // A poll that throws performs no save at all — the store is only ever
        // written on success.
        let stub = StubTransport([.failure(.transport("offline"))])
        _ = try? await_fetch(stub, refA)

        #expect(store.load(refA)?.fetchedAt == Date(timeIntervalSince1970: 1_000))
        #expect(store.load(refA)?.shownCount == 1)
    }

    /// Regression: the first version of this suite only ever used whole-second
    /// fixture dates, so ISO-8601's lack of a sub-second component never showed
    /// up. The app caught it immediately with a real `Date()` and reported
    /// "round-trip MISMATCH". Fixtures that are tidier than production data
    /// hide exactly this class of bug.
    @Test("a board built from a fractional-second Date still round-trips equal")
    func fractionalSecondDates() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("boardbar-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileBoardStore(directory: dir)

        let messy = Date(timeIntervalSince1970: 1_756_582_425.987_654)
        let board = makeBoard(todo: [issue20], fetchedAt: messy)
        try store.save(board, for: refA)
        #expect(store.load(refA) == board)
        #expect(board.fetchedAt.timeIntervalSince1970 == 1_756_582_425)
    }

    @Test("nothing resembling a token is written to disk")
    func noTokenOnDisk() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("boardbar-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileBoardStore(directory: dir)
        try store.save(makeBoard(todo: [issue20]), for: refA)

        let file = dir.appendingPathComponent("board-\(refA.storageKey).json")
        let contents = try String(contentsOf: file, encoding: .utf8)
        #expect(!contents.contains("ghp_"))
        #expect(!contents.contains("github_pat_"))
        #expect(!contents.lowercased().contains("token"))
        #expect(!contents.lowercased().contains("authorization"))
    }

    /// A v1 cache was written before boards carried names. Decoding is
    /// all-or-nothing, so a missing title must not throw away a board that is
    /// otherwise perfectly good — the tab falls back to a number instead.
    @Test("a board cached by v1 decodes without its new fields")
    func v1CacheStillDecodes() throws {
        let v1JSON = """
        {"columns":[{"name":"Todo","cards":[]}],"columnSource":"view",
         "fetchedAt":"2026-08-30T19:23:45Z","totalCount":0}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let board = try decoder.decode(Board.self, from: Data(v1JSON.utf8))

        #expect(board.columns.count == 1)
        #expect(board.projectTitle == nil)
        #expect(board.viewName == nil)
    }
}

/// Bridges the synchronous test to the async fetcher without making the whole
/// contract async.
private func await_fetch(_ transport: some GitHubTransport, _ ref: BoardRef) throws -> Board {
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: Result<Board, any Error>!
    Task {
        do { result = .success(try await BoardFetcher(transport: transport).fetch(ref, token: "t")) }
        catch { result = .failure(error) }
        semaphore.signal()
    }
    semaphore.wait()
    return try result.get()
}
