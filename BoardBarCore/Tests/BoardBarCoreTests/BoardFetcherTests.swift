import Foundation
import Testing

@testable import BoardBarCore

/// Replays canned bodies in order, and records what was asked for.
final actor StubTransport: GitHubTransport {
    private var bodies: [Result<String, GitHubError>]
    private(set) var queries: [String] = []
    private(set) var variables: [[String: String]] = []

    init(_ bodies: [Result<String, GitHubError>]) { self.bodies = bodies }

    func post(
        query: String, variables vars: [String: String], token: String
    ) async throws(GitHubError) -> Data {
        queries.append(query)
        variables.append(vars)
        guard !bodies.isEmpty else { return Data(#"{"data":{}}"#.utf8) }
        switch bodies.removeFirst() {
        case let .success(body): return Data(body.utf8)
        case let .failure(error): throw error
        }
    }
}

// Captured verbatim from the live board on 2026-08-30.
private let layoutBody = """
{"data":{"user":{"projectV2":{
  "title":"Qurba bug reports",
  "statusField":{"name":"Status","options":[
    {"name":"Todo"},{"name":"In Progress"},{"name":"Done"},{"name":"Rejected"}]},
  "view":{"name":"Main Board","layout":"BOARD_LAYOUT","filter":"",
    "verticalGroupByFields":{"nodes":[{"__typename":"ProjectV2SingleSelectField",
      "name":"Status","options":[
        {"name":"Todo"},{"name":"In Progress"},{"name":"Done"},{"name":"Rejected"}]}]}}
}}}}
"""

private let itemsBody = """
{"data":{"user":{"projectV2":{"items":{"totalCount":1,"nodes":[{
  "fieldValues":{"nodes":[{},{},{},{"name":"Todo","field":{"name":"Status"}}]},
  "content":{"number":20,
    "title":"اضافة ختمات للغرفه كنوع اضافي وليس كعمل",
    "url":"https://github.com/Haddadmj/qurba/issues/20",
    "updatedAt":"2026-08-30T19:23:45Z",
    "repository":{"nameWithOwner":"Haddadmj/qurba"},
    "labels":{"nodes":[{"name":"from-app","color":"0e8a16"},
                       {"name":"feature-request","color":"5319e7"}]}}}]}}}}}
"""

private let targetRef = BoardRef(
    ownerKind: .users, owner: "Haddadmj", projectNumber: 2, viewNumber: 2
)

@Suite("Board fetching")
struct BoardFetcherTests {
    @Test("the real board resolves to four columns with #20 in Todo")
    func realBoard() async throws {
        let stub = StubTransport([.success(layoutBody), .success(itemsBody)])
        let board = try await BoardFetcher(transport: stub).fetch(targetRef, token: "t")

        #expect(board.columns.map(\.name) == ["Todo", "In Progress", "Done", "Rejected"])
        #expect(board.columnSource == .view)
        #expect(board.shownCount == 1)
        #expect(board.isTruncated == false)

        let card = try #require(board.columns.first(where: { $0.name == "Todo" })?.cards.first)
        #expect(card.number == 20)
        #expect(card.title == "اضافة ختمات للغرفه كنوع اضافي وليس كعمل")
        #expect(card.repository == "Haddadmj/qurba")
        #expect(card.labels.map(\.name) == ["from-app", "feature-request"])
        #expect(card.labels.first?.color == "0e8a16")
    }

    /// The fallback is easy to leave untested: on the target board both paths
    /// happen to produce identical output, so it has to be exercised on purpose.
    @Test("no view number takes the Status-field fallback and asks for no view")
    func fallbackPath() async throws {
        let noView = BoardRef(ownerKind: .users, owner: "Haddadmj", projectNumber: 2, viewNumber: nil)
        let stub = StubTransport([.success(layoutBody), .success(itemsBody)])
        let board = try await BoardFetcher(transport: stub).fetch(noView, token: "t")

        #expect(board.columnSource == .statusFieldFallback)
        #expect(board.columns.map(\.name) == ["Todo", "In Progress", "Done", "Rejected"])
        let sent = await stub.queries
        #expect(!sent[0].contains("view(number:"))
    }

    @Test("an org board queries the organization root, not user")
    func orgRoot() async throws {
        let ref = BoardRef(ownerKind: .orgs, owner: "neotek", projectNumber: 7, viewNumber: 1)
        let stub = StubTransport([.success(layoutBody.replacingOccurrences(of: "\"user\"", with: "\"organization\"")), .success(itemsBody.replacingOccurrences(of: "\"user\"", with: "\"organization\""))])
        _ = try? await BoardFetcher(transport: stub).fetch(ref, token: "t")
        let sent = await stub.queries
        #expect(sent[0].contains("organization(login: $owner)"))
    }

    @Test("the view's filter is passed to the server rather than applied here")
    func filterIsServerSide() async throws {
        let filtered = layoutBody.replacingOccurrences(
            of: "\"filter\":\"\"", with: "\"filter\":\"status:Todo\""
        )
        let stub = StubTransport([.success(filtered), .success(itemsBody)])
        _ = try await BoardFetcher(transport: stub).fetch(targetRef, token: "t")
        let vars = await stub.variables
        #expect(vars[1]["q"] == "status:Todo")
    }

    @Test("a 401 surfaces as unauthorized, distinct from any other failure")
    func unauthorized() async {
        let stub = StubTransport([.failure(.unauthorized)])
        await #expect(throws: GitHubError.unauthorized) {
            try await BoardFetcher(transport: stub).fetch(targetRef, token: "bad")
        }
    }

    /// GitHub returns bad credentials as a GraphQL error inside HTTP 200, so
    /// status-code checking alone would miss a revoked token entirely.
    @Test("bad credentials inside an HTTP 200 still reads as unauthorized")
    func badCredentialsAt200() async {
        let body = #"{"errors":[{"message":"Bad credentials"}]}"#
        let stub = StubTransport([.success(body)])
        await #expect(throws: GitHubError.unauthorized) {
            try await BoardFetcher(transport: stub).fetch(targetRef, token: "revoked")
        }
    }

    @Test("a view grouped by an iteration falls back instead of failing")
    func unsupportedGroupingFallsBack() async throws {
        let iteration = layoutBody.replacingOccurrences(
            of: "\"__typename\":\"ProjectV2SingleSelectField\"",
            with: "\"__typename\":\"ProjectV2IterationField\""
        )
        let stub = StubTransport([.success(iteration), .success(itemsBody)])
        let board = try await BoardFetcher(transport: stub).fetch(targetRef, token: "t")
        #expect(board.columnSource == .statusFieldFallback)
        #expect(board.shownCount == 1)
    }

    /// The fallback path cannot carry the view's filter, so a board that falls
    /// back from a filtered view shows more than the browser does. That has to
    /// be visible or it is the stale-board mistake in a different costume.
    @Test("a filter dropped by the fallback is reported, not swallowed")
    func droppedFilterIsReported() async throws {
        let filteredIteration = layoutBody
            .replacingOccurrences(of: "\"filter\":\"\"", with: "\"filter\":\"status:Todo\"")
            .replacingOccurrences(
                of: "\"__typename\":\"ProjectV2SingleSelectField\"",
                with: "\"__typename\":\"ProjectV2IterationField\""
            )
        let stub = StubTransport([.success(filteredIteration), .success(itemsBody)])
        let board = try await BoardFetcher(transport: stub).fetch(targetRef, token: "t")
        #expect(board.columnSource == .statusFieldFallback)
        #expect(board.unappliedFilter == "status:Todo")
    }

    @Test("a supported view reports no dropped filter")
    func noDroppedFilterOnHappyPath() async throws {
        let stub = StubTransport([.success(layoutBody), .success(itemsBody)])
        let board = try await BoardFetcher(transport: stub).fetch(targetRef, token: "t")
        #expect(board.unappliedFilter == nil)
    }

    @Test("an item with no status lands in its own leading column")
    func orphanItems() async throws {
        let orphan = itemsBody.replacingOccurrences(
            of: #"{"name":"Todo","field":{"name":"Status"}}"#, with: "{}"
        )
        let stub = StubTransport([.success(layoutBody), .success(orphan)])
        let board = try await BoardFetcher(transport: stub).fetch(targetRef, token: "t")
        #expect(board.columns.first?.name == "No Status")
        #expect(board.columns.first?.count == 1)
    }

    @Test("truncation past the item limit is visible, not silent")
    func truncationIsVisible() async throws {
        let many = itemsBody.replacingOccurrences(of: "\"totalCount\":1", with: "\"totalCount\":250")
        let stub = StubTransport([.success(layoutBody), .success(many)])
        let board = try await BoardFetcher(transport: stub).fetch(targetRef, token: "t")
        #expect(board.isTruncated)
        #expect(board.totalCount == 250)
        #expect(board.shownCount == 1)
    }

    @Test("no query in the fetcher mutates anything")
    func readOnly() async throws {
        let stub = StubTransport([.success(layoutBody), .success(itemsBody)])
        _ = try await BoardFetcher(transport: stub).fetch(targetRef, token: "t")
        for query in await stub.queries {
            #expect(!query.contains("mutation"))
            #expect(!query.lowercased().contains("updateprojectv2"))
        }
    }

    @Test("staleness is measured from updatedAt")
    func staleness() throws {
        let updated = try #require(ISO8601DateFormatter().date(from: "2026-08-30T19:23:45Z"))
        let card = Card(
            number: 20, title: "t", url: URL(string: "https://x")!,
            repository: "a/b", updatedAt: updated, labels: []
        )
        #expect(card.isStale(asOf: updated.addingTimeInterval(6 * 24 * 3600)) == false)
        #expect(card.isStale(asOf: updated.addingTimeInterval(8 * 24 * 3600)))
    }
}

@Suite("Board naming")
struct BoardNamingTests {
    /// Both come off nodes the layout query already visits, so a tab label
    /// costs no extra request.
    @Test("the live target board yields its project title and view name")
    func namesTheBoard() async throws {
        let stub = StubTransport([.success(layoutBody), .success(itemsBody)])
        let board = try await BoardFetcher(transport: stub).fetch(targetRef, token: "t")

        #expect(board.projectTitle == "Qurba bug reports")
        #expect(board.viewName == "Main Board")
        #expect(await stub.queries.count == 2, "still two round trips")
    }

    /// A board that fell back to the Status field is still the tab the
    /// maintainer configured, and says what it did through `columnSource`.
    @Test("a fallback board keeps the name of the view it could not mirror")
    func fallbackKeepsTheName() async throws {
        let tableView = """
        {"data":{"user":{"projectV2":{
          "title":"Qurba bug reports",
          "statusField":{"name":"Status","options":[{"name":"Todo"}]},
          "view":{"name":"Everything","layout":"TABLE_LAYOUT","filter":"is:open",
            "verticalGroupByFields":{"nodes":[]}}}}}}
        """
        let stub = StubTransport([.success(tableView), .success(itemsBody)])
        let board = try await BoardFetcher(transport: stub).fetch(targetRef, token: "t")

        #expect(board.columnSource == .statusFieldFallback)
        #expect(board.viewName == "Everything")
        #expect(board.projectTitle == "Qurba bug reports")
    }

    /// Nothing about a name is worth failing a fetch for.
    @Test("a response without either name still produces a board")
    func namesAreOptional() async throws {
        let unnamed = """
        {"data":{"user":{"projectV2":{
          "statusField":{"name":"Status","options":[{"name":"Todo"}]},
          "view":{"layout":"BOARD_LAYOUT","filter":"",
            "verticalGroupByFields":{"nodes":[{"__typename":"ProjectV2SingleSelectField",
              "name":"Status","options":[{"name":"Todo"}]}]}}}}}}
        """
        let stub = StubTransport([.success(unnamed), .success(itemsBody)])
        let board = try await BoardFetcher(transport: stub).fetch(targetRef, token: "t")

        #expect(board.projectTitle == nil)
        #expect(board.viewName == nil)
        #expect(board.shownCount == 1)
    }
}
