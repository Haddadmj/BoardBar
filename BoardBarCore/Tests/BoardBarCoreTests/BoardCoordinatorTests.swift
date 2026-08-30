import Foundation
import Testing

@testable import BoardBarCore

/// A transport that parks on the first request until released, so two refreshes
/// can genuinely overlap. Counting requests alone cannot prove a drop — it only
/// shows the second one did not happen, not that it was refused while the first
/// was in flight.
final actor GatedTransport: GitHubTransport {
    private var gate: CheckedContinuation<Void, Never>?
    private(set) var requests = 0
    private let layout: String
    private let items: String

    init(layout: String, items: String) {
        self.layout = layout
        self.items = items
    }

    func openGate() {
        gate?.resume()
        gate = nil
    }

    func post(
        query: String, variables: [String: String], token: String
    ) async throws(GitHubError) -> Data {
        requests += 1
        if requests == 1 {
            await withCheckedContinuation { gate = $0 }
        }
        return Data((query.contains("items(") ? items : layout).utf8)
    }
}

private let layoutJSON = """
{"data":{"user":{"projectV2":{
  "statusField":{"name":"Status","options":[{"name":"Todo"},{"name":"Done"}]},
  "view":{"layout":"BOARD_LAYOUT","filter":"","verticalGroupByFields":{"nodes":[
    {"__typename":"ProjectV2SingleSelectField","name":"Status",
     "options":[{"name":"Todo"},{"name":"Done"}]}]}}}}}}
"""

private let itemsJSON = """
{"data":{"user":{"projectV2":{"items":{"totalCount":1,"nodes":[{
  "fieldValues":{"nodes":[{"name":"Todo","field":{"name":"Status"}}]},
  "content":{"number":20,"title":"اضافة ختمات للغرفه كنوع اضافي وليس كعمل",
    "url":"https://github.com/Haddadmj/qurba/issues/20",
    "updatedAt":"2026-08-30T19:23:45Z",
    "repository":{"nameWithOwner":"Haddadmj/qurba"},
    "labels":{"nodes":[]}}}]}}}}}
"""

private let ref = BoardRef(ownerKind: .users, owner: "Haddadmj", projectNumber: 2, viewNumber: 2)

@MainActor
private func makeCoordinator(
    transport: any GitHubTransport,
    store: any BoardStore = InMemoryBoardStore(),
    token: String? = "ghp_test",
    policy: PollPolicy = PollPolicy()
) -> BoardCoordinator {
    BoardCoordinator(
        ref: ref,
        fetcher: BoardFetcher(transport: transport),
        store: store,
        tokens: InMemoryTokenStore(token: token),
        policy: policy
    )
}

@MainActor
@Suite("Board coordinator")
struct BoardCoordinatorTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("a successful refresh renders the board and writes it to the store")
    func successPath() async throws {
        let store = InMemoryBoardStore()
        let stub = StubTransport([.success(layoutJSON), .success(itemsJSON)])
        let coordinator = makeCoordinator(transport: stub, store: store)

        #expect(await coordinator.refresh(reason: .launch, now: now))
        #expect(coordinator.board?.shownCount == 1)
        #expect(coordinator.lastError == nil)
        #expect(store.load(ref)?.shownCount == 1)
    }

    @Test("a cached board renders before any fetch returns")
    func rendersCacheOnLaunch() throws {
        let store = InMemoryBoardStore()
        let cached = Board(
            columns: [Column(name: "Todo", cards: [])],
            columnSource: .view, fetchedAt: now, totalCount: 0
        )
        try store.save(cached, for: ref)

        let coordinator = makeCoordinator(transport: StubTransport([]), store: store)
        #expect(coordinator.board == cached)
        #expect(coordinator.lastFetchedAt == cached.fetchedAt)
    }

    /// The whole staleness model rests on this. If a failed poll could advance
    /// the timestamp, "updated 40m ago" would be decoration.
    @Test("a failed refresh keeps the last good board and does not advance the clock")
    func failureKeepsLastGood() async throws {
        let store = InMemoryBoardStore()
        let good = StubTransport([.success(layoutJSON), .success(itemsJSON)])
        let coordinator = makeCoordinator(transport: good, store: store)
        await coordinator.refresh(reason: .launch, now: now)
        let firstFetch = coordinator.lastFetchedAt

        let failing = makeCoordinator(
            transport: StubTransport([.failure(.transport("offline"))]), store: store
        )
        #expect(!(await failing.refresh(reason: .tick, now: now.addingTimeInterval(2400))))
        #expect(failing.board?.shownCount == 1, "last good board stays on screen")
        #expect(failing.lastFetchedAt == firstFetch, "timestamp did not move")
        #expect(failing.lastError == .transport("offline"))
        #expect(store.load(ref)?.fetchedAt == firstFetch, "store untouched by the failure")
    }

    @Test("a refresh arriving while one is in flight is dropped, not queued")
    func inFlightIsDropped() async throws {
        let gated = GatedTransport(layout: layoutJSON, items: itemsJSON)
        let coordinator = makeCoordinator(transport: gated)

        let first = Task { await coordinator.refresh(reason: .launch, now: now) }
        // Let the first refresh reach the parked transport.
        while await gated.requests == 0 { await Task.yield() }
        #expect(coordinator.isFetching)

        let second = await coordinator.refresh(reason: .tick, now: now)
        #expect(second == false)
        #expect(coordinator.droppedRefreshes == 1)

        await gated.openGate()
        #expect(await first.value)
        #expect(coordinator.board?.shownCount == 1)
    }

    @Test("opening the popover on fresh data does not fetch again")
    func openOnFreshData() async throws {
        let stub = StubTransport([.success(layoutJSON), .success(itemsJSON)])
        let coordinator = makeCoordinator(transport: stub)
        await coordinator.refresh(reason: .launch, now: now)
        let before = await stub.queries.count

        await coordinator.popoverOpened(now: now.addingTimeInterval(30))
        #expect(await stub.queries.count == before, "no new request")
        #expect(coordinator.lastPopoverOpen == now.addingTimeInterval(30))
    }

    @Test("opening the popover on stale data fetches immediately")
    func openOnStaleData() async throws {
        let stub = StubTransport([
            .success(layoutJSON), .success(itemsJSON),
            .success(layoutJSON), .success(itemsJSON),
        ])
        let coordinator = makeCoordinator(transport: stub)
        await coordinator.refresh(reason: .launch, now: now)

        await coordinator.popoverOpened(now: now.addingTimeInterval(120))
        #expect(await stub.queries.count == 4)
    }

    @Test("a tick inside the interval spends nothing")
    func tickNotDue() async throws {
        let stub = StubTransport([.success(layoutJSON), .success(itemsJSON)])
        let coordinator = makeCoordinator(transport: stub)
        await coordinator.refresh(reason: .launch, now: now)

        await coordinator.tick(now: now.addingTimeInterval(60))
        #expect(await stub.queries.count == 2, "still just the first fetch")
    }

    @Test("the cadence moves to idle after an hour and back on open")
    func cadenceFollowsAttention() async throws {
        let coordinator = makeCoordinator(transport: StubTransport([]))
        #expect(coordinator.currentInterval(now: now) == 1800)

        await coordinator.popoverOpened(now: now)
        #expect(coordinator.currentInterval(now: now.addingTimeInterval(60)) == 300)
        #expect(coordinator.currentInterval(now: now.addingTimeInterval(3700)) == 1800)
    }

    @Test("changing the board clears the old one instead of showing it as stale")
    func configurationChangeClearsBoard() async throws {
        let stub = StubTransport([.success(layoutJSON), .success(itemsJSON)])
        let coordinator = makeCoordinator(transport: stub)
        await coordinator.refresh(reason: .launch, now: now)
        #expect(coordinator.board != nil)

        coordinator.ref = BoardRef(
            ownerKind: .users, owner: "Haddadmj", projectNumber: 2, viewNumber: 3
        )
        #expect(coordinator.board == nil, "a different board is not a stale version of this one")
        #expect(coordinator.lastFetchedAt == nil)
    }

    /// The bug the app's log exposed: a board that keeps failing must poll on
    /// its normal cadence, not on every tick.
    @Test("a repeatedly failing board does not retry on every tick")
    func failingBoardDoesNotRetryEveryTick() async throws {
        let stub = StubTransport([
            .failure(.transport("offline")), .failure(.transport("offline")),
            .failure(.transport("offline")), .failure(.transport("offline")),
        ])
        let coordinator = makeCoordinator(transport: stub)
        await coordinator.popoverOpened(now: now)  // active cadence: 5 minutes
        let afterFirst = await stub.queries.count
        #expect(afterFirst == 1, "one failed attempt")

        // Four ticks a minute apart, all inside the 5-minute interval.
        for minute in 1...4 {
            await coordinator.tick(now: now.addingTimeInterval(Double(minute) * 60))
        }
        #expect(await stub.queries.count == afterFirst, "no retries inside the interval")

        await coordinator.tick(now: now.addingTimeInterval(301))
        #expect(await stub.queries.count == afterFirst + 1, "one retry once the interval elapsed")
    }

    @Test("a missing token backs off like any other failure")
    func missingTokenBacksOff() async throws {
        let stub = StubTransport([])
        let coordinator = makeCoordinator(transport: stub, token: nil)
        await coordinator.popoverOpened(now: now)
        #expect(coordinator.lastAttemptAt == now, "a missing token still counts as an attempt")
        await coordinator.tick(now: now.addingTimeInterval(60))
        #expect(coordinator.lastAttemptAt == now, "the tick was not due")
    }

    /// Second regression from the same log. The first fix stamped
    /// `lastAttemptAt` after the `ref` guard, so an unconfigured app never
    /// stamped it and ticked every 60 seconds for ever.
    @Test("an unconfigured app does not tick at all")
    func unconfiguredDoesNotTick() async throws {
        let stub = StubTransport([])
        let coordinator = BoardCoordinator(
            ref: nil,
            fetcher: BoardFetcher(transport: stub),
            store: InMemoryBoardStore(),
            tokens: InMemoryTokenStore(token: "ghp_test")
        )
        for minute in 1...5 {
            let attempted = await coordinator.tick(now: now.addingTimeInterval(Double(minute) * 60))
            #expect(attempted == false, "nothing to poll, so nothing attempted")
        }
        #expect(coordinator.lastAttemptAt == nil)
        #expect(await stub.queries.isEmpty)
    }

    @Test("no token reads as unauthorized without touching the network")
    func missingToken() async throws {
        let stub = StubTransport([.success(layoutJSON)])
        let coordinator = makeCoordinator(transport: stub, token: nil)
        #expect(!(await coordinator.refresh(reason: .launch, now: now)))
        #expect(coordinator.lastError == .unauthorized)
        #expect(await stub.queries.isEmpty, "never asked GitHub")
    }
}
