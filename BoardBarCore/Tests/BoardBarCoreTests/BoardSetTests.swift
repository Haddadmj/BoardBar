import Foundation
import Testing

@testable import BoardBarCore

private let layoutJSON = """
{"data":{"user":{"projectV2":{"title":"Qurba bug reports",
  "statusField":{"name":"Status","options":[{"name":"Todo"}]},
  "view":{"name":"Main Board","layout":"BOARD_LAYOUT","filter":"",
    "verticalGroupByFields":{"nodes":[{"__typename":"ProjectV2SingleSelectField",
      "name":"Status","options":[{"name":"Todo"}]}]}}}}}}
"""

private let itemsJSON = """
{"data":{"user":{"projectV2":{"items":{"totalCount":1,"nodes":[{
  "fieldValues":{"nodes":[{"name":"Todo","field":{"name":"Status"}}]},
  "content":{"number":20,"title":"اضافة ختمات للغرفه",
    "url":"https://github.com/Haddadmj/qurba/issues/20",
    "updatedAt":"2026-08-30T19:23:45Z",
    "repository":{"nameWithOwner":"Haddadmj/qurba"},
    "labels":{"nodes":[]}}}]}}}}}
"""

/// Answers any number of fetches, and counts them per board so a per-tab
/// cadence can be asserted on requests rather than on intent.
private final actor CountingTransport: GitHubTransport {
    private(set) var requests = 0

    func post(
        query: String, variables: [String: String], token: String
    ) async throws(GitHubError) -> Data {
        requests += 1
        return Data((query.contains("items(") ? itemsJSON : layoutJSON).utf8)
    }
}

private func ref(_ view: Int) -> BoardRef {
    BoardRef(ownerKind: .users, owner: "Haddadmj", projectNumber: 2, viewNumber: view)
}

private func scratchDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
private final class Fixture {
    let defaults: UserDefaults
    let store = InMemoryBoardStore()
    private(set) var transports: [String: CountingTransport] = [:]
    private(set) var created = 0

    init(defaults: UserDefaults) { self.defaults = defaults }

    func makeSet(_ refs: [BoardRef]) -> BoardSet {
        BoardSet(refs: refs, defaults: defaults) { [self] boardRef in
            created += 1
            let transport = CountingTransport()
            transports[boardRef.storageKey] = transport
            return BoardCoordinator(
                ref: boardRef,
                fetcher: BoardFetcher(transport: transport),
                store: store,
                tokens: InMemoryTokenStore(token: "ghp_test")
            )
        }
    }

    /// Two requests per fetch — the layout pass and the item pass.
    func fetches(_ boardRef: BoardRef) async -> Int {
        await (transports[boardRef.storageKey]?.requests ?? 0) / 2
    }
}

@MainActor
@Suite("Board set")
struct BoardSetTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("three configured boards yield three coordinators, each with its own cache")
    func threeBoards() async throws {
        let fixture = Fixture(defaults: scratchDefaults())
        let set = fixture.makeSet([ref(1), ref(2), ref(3)])
        #expect(set.boards.count == 3)

        for board in set.boards {
            await board.refresh(reason: .launch, now: now)
        }
        for view in 1...3 {
            #expect(fixture.store.load(ref(view))?.shownCount == 1, "board \(view) cached on its own key")
        }
    }

    /// The heart of the ticket: no board is told it is in the background. Only
    /// the selected one is told the popover was opened, and that alone is what
    /// separates a 5-minute cadence from a 30-minute one.
    @Test("only the selected board polls at five minutes")
    func selectedPollsFaster() async throws {
        let fixture = Fixture(defaults: scratchDefaults())
        let set = fixture.makeSet([ref(1), ref(2)])
        await set.select(0, now: now)

        #expect(set.boards[0].currentInterval(now: now) == 300)
        #expect(set.boards[1].currentInterval(now: now) == 1800)

        // Every board is ticked. Ten minutes on, both are due: the selected one
        // because its 5 minutes have elapsed, the background one because it has
        // never been attempted at all.
        _ = await set.tick(now: now.addingTimeInterval(600))
        #expect(await fixture.fetches(ref(1)) == 2)
        #expect(await fixture.fetches(ref(2)) == 1)

        // Ten minutes later the selected board polls again and the background
        // one does not — it is only 10 minutes into its 30.
        _ = await set.tick(now: now.addingTimeInterval(1200))
        #expect(await fixture.fetches(ref(1)) == 3)
        #expect(await fixture.fetches(ref(2)) == 1)

        // Half an hour after its own last attempt, it finally comes due.
        _ = await set.tick(now: now.addingTimeInterval(2500))
        #expect(await fixture.fetches(ref(2)) == 2)
    }

    @Test("selecting a tab with stale data triggers exactly one fetch")
    func selectingRefreshesStaleTab() async throws {
        let fixture = Fixture(defaults: scratchDefaults())
        let set = fixture.makeSet([ref(1), ref(2)])
        await set.select(0, now: now)
        let before = await fixture.fetches(ref(2))

        await set.select(1, now: now.addingTimeInterval(3600))
        #expect(set.selectedIndex == 1)
        #expect(await fixture.fetches(ref(2)) == before + 1)
    }

    @Test("selecting a tab that is already current spends nothing")
    func selectingFreshTabDoesNotFetch() async throws {
        let fixture = Fixture(defaults: scratchDefaults())
        let set = fixture.makeSet([ref(1), ref(2)])
        await set.select(1, now: now)
        let after = await fixture.fetches(ref(2))

        await set.select(1, now: now.addingTimeInterval(10))
        #expect(await fixture.fetches(ref(2)) == after)
    }

    @Test("selection survives relaunch")
    func selectionPersists() async throws {
        let defaults = scratchDefaults()
        let first = Fixture(defaults: defaults)
        let set = first.makeSet([ref(1), ref(2), ref(3)])
        await set.select(2, now: now)

        let relaunched = Fixture(defaults: defaults).makeSet([ref(1), ref(2), ref(3)])
        #expect(relaunched.selectedIndex == 2)
    }

    /// The list can shrink while the app is closed.
    @Test("a stored index past the end is clamped")
    func clampsStoredIndex() async throws {
        let defaults = scratchDefaults()
        defaults.set(7, forKey: BoardSet.selectionKey)

        let set = Fixture(defaults: defaults).makeSet([ref(1), ref(2)])
        #expect(set.selectedIndex == 1)
        #expect(set.selected?.ref == ref(2))
    }

    @Test("removing the selected board selects its neighbour")
    func removingSelectedSelectsNeighbour() async throws {
        let fixture = Fixture(defaults: scratchDefaults())
        let set = fixture.makeSet([ref(1), ref(2), ref(3)])
        await set.select(1, now: now)

        let removed = set.setRefs([ref(1), ref(3)])
        #expect(removed == [ref(2)])
        #expect(set.selectedIndex == 1, "the tab that took its place on screen")
        #expect(set.selected?.ref == ref(3))
    }

    @Test("removing the last board clamps rather than leaving nothing selected")
    func removingLastBoard() async throws {
        let fixture = Fixture(defaults: scratchDefaults())
        let set = fixture.makeSet([ref(1), ref(2)])
        await set.select(1, now: now)

        set.setRefs([ref(1)])
        #expect(set.selectedIndex == 0)
        #expect(set.selected?.ref == ref(1))

        set.setRefs([])
        #expect(set.selected == nil)
        #expect(set.showsTabBar == false)
    }

    /// Reordering must not blank the boards that were already loaded.
    @Test("surviving boards keep their coordinator across a reconfiguration")
    func survivorsAreReused() async throws {
        let fixture = Fixture(defaults: scratchDefaults())
        let set = fixture.makeSet([ref(1), ref(2)])
        for board in set.boards { await board.refresh(reason: .launch, now: now) }
        #expect(fixture.created == 2)

        set.setRefs([ref(2), ref(1), ref(3)])
        #expect(fixture.created == 3, "only the new board was built")
        #expect(set.boards[0].board != nil, "the reordered board kept what it had fetched")
        #expect(set.boards[2].board == nil)
    }

    @Test("the selected board keeps its selection when the list is reordered")
    func selectionFollowsTheBoard() async throws {
        let fixture = Fixture(defaults: scratchDefaults())
        let set = fixture.makeSet([ref(1), ref(2), ref(3)])
        await set.select(0, now: now)

        set.setRefs([ref(3), ref(2), ref(1)])
        #expect(set.selected?.ref == ref(1), "the same board, at its new index")
        #expect(set.selectedIndex == 2)
    }

    @Test("one board renders no tab bar")
    func oneBoardIsV1() async throws {
        let set = Fixture(defaults: scratchDefaults()).makeSet([ref(1)])
        #expect(set.showsTabBar == false)
    }

    @Test("tab labels follow the configured order")
    func labelsFollowOrder() async throws {
        let fixture = Fixture(defaults: scratchDefaults())
        let set = fixture.makeSet([ref(1), ref(2)])
        // Both tabs sit on project 2, so they are named after their views —
        // and neither has loaded, so both fall back to numbers.
        #expect(set.labels == ["Project 2 · View 1", "Project 2 · View 2"])

        for board in set.boards { await board.refresh(reason: .launch, now: now) }
        #expect(set.labels == ["Main Board", "Main Board"])
    }
}

@MainActor
@Suite("Popover width")
struct BoardSetWidthTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// The width follows the widest board that has loaded, so switching tabs
    /// cannot resize the popover.
    @Test("an unloaded board contributes no width")
    func unloadedContributesNothing() async throws {
        let fixture = Fixture(defaults: scratchDefaults())
        let set = fixture.makeSet([ref(1), ref(2)])
        #expect(set.widestLoadedColumnCount == 0, "nothing loaded, nothing to size to")

        await set.boards[0].refresh(reason: .launch, now: now)
        #expect(set.widestLoadedColumnCount == 1, "the one board that has loaded")
    }
}
