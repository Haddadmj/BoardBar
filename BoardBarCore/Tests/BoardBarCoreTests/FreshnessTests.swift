import Foundation
import Testing

@testable import BoardBarCore

@Suite("Freshness")
struct FreshnessTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func summary(
        hasBoard: Bool = true, age: TimeInterval = 0, error: GitHubError? = nil
    ) -> StatusSummary {
        Freshness.summarize(
            hasBoard: hasBoard,
            lastFetchedAt: hasBoard ? now.addingTimeInterval(-age) : nil,
            error: error,
            now: now
        )
    }

    /// The rule the whole table rests on: the timestamp is there in every
    /// state, not only when something has gone wrong.
    @Test("a successful fetch still shows a timestamp")
    func timestampOnSuccess() {
        let s = summary(age: 10)
        #expect(s.level == .fresh)
        #expect(s.footer == "Updated just now")
        #expect(s.warning == nil)
    }

    @Test("a board past 30 minutes goes stale and dims the icon")
    func staleDimsIcon() {
        #expect(summary(age: 29 * 60).level == .fresh)
        #expect(!summary(age: 29 * 60).dimsMenuBarIcon)
        #expect(summary(age: 31 * 60).level == .stale)
        #expect(summary(age: 31 * 60).dimsMenuBarIcon)
    }

    /// A network failure with a good board on screen keeps the board and says
    /// so. Silence here is the characteristic bug of ambient displays.
    @Test("an offline failure keeps the board and states the problem")
    func offlineKeepsBoard() {
        let s = summary(age: 40 * 60, error: .transport("offline"))
        #expect(s.level == .stale)
        #expect(s.footer == "Updated 40m ago")
        #expect(s.warning == "Couldn't reach GitHub: offline")
    }

    /// Checked ahead of staleness: a rejected token is not a degraded board.
    @Test("a 401 replaces the board rather than annotating it")
    func unauthorizedWins() {
        let s = summary(age: 10, error: .unauthorized)
        #expect(s.level == .unauthorized)
        #expect(s.showsErrorIcon)
        #expect(!s.dimsMenuBarIcon, "an error state is not a dimmed state")
    }

    @Test("no board yet reads as empty, carrying the reason when there is one")
    func emptyState() {
        #expect(summary(hasBoard: false).level == .empty)
        #expect(summary(hasBoard: false).footer == "Never updated")
        #expect(summary(hasBoard: false, error: .rateLimited).footer.contains("Rate-limited"))
    }

    @Test(
        "ages read coarsely",
        arguments: [
            (0.0, "just now"), (59.0, "just now"), (60.0, "1m ago"),
            (2400.0, "40m ago"), (3599.0, "59m ago"), (3600.0, "1h ago"),
            (86_399.0, "23h ago"), (86_400.0, "1d ago"), (259_200.0, "3d ago"),
        ]
    )
    func relativeAges(_ age: TimeInterval, _ expected: String) {
        #expect(Freshness.relativeAge(age) == expected)
    }
}
