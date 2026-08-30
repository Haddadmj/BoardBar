import Foundation
import Testing

@testable import BoardBarCore

@Suite("Poll policy")
struct PollPolicyTests {
    let policy = PollPolicy()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("a board looked at recently polls every 5 minutes")
    func activeCadence() {
        let justOpened = now.addingTimeInterval(-60)
        #expect(policy.interval(lastPopoverOpen: justOpened, now: now) == 300)
    }

    @Test("a board nobody has opened for over an hour drops to 30 minutes")
    func idleCadence() {
        let stale = now.addingTimeInterval(-3601)
        #expect(policy.interval(lastPopoverOpen: stale, now: now) == 1800)
    }

    @Test("a board never opened is idle, not active")
    func neverOpened() {
        #expect(policy.interval(lastPopoverOpen: nil, now: now) == 1800)
    }

    @Test("the active window boundary is inclusive")
    func windowBoundary() {
        #expect(policy.interval(lastPopoverOpen: now.addingTimeInterval(-3600), now: now) == 300)
        #expect(policy.interval(lastPopoverOpen: now.addingTimeInterval(-3601), now: now) == 1800)
    }

    /// Regression: keyed on the last *attempt*, not the last success. Keying on
    /// success meant a board that kept failing never advanced its timestamp, so
    /// every tick was due and the poll rate collapsed to the tick rate. Caught
    /// in the app's log, not by any test that existed at the time.
    @Test("a failing board still backs off instead of retrying every tick")
    func failingBoardBacksOff() {
        let attempted = now.addingTimeInterval(-120)
        #expect(!policy.isDue(lastAttempt: attempted, lastPopoverOpen: now, now: now))
        #expect(policy.isDue(lastAttempt: now.addingTimeInterval(-301), lastPopoverOpen: now, now: now))
    }

    @Test("nothing fetched yet is always due")
    func neverFetched() {
        #expect(policy.isDue(lastAttempt: nil, lastPopoverOpen: nil, now: now))
    }

    @Test("a tick inside the interval does nothing")
    func tickNotDue() {
        let open = now.addingTimeInterval(-60)
        #expect(!policy.isDue(lastAttempt: now.addingTimeInterval(-299), lastPopoverOpen: open, now: now))
        #expect(policy.isDue(lastAttempt: now.addingTimeInterval(-300), lastPopoverOpen: open, now: now))
    }

    /// The same elapsed time is due when idle-polling and not when active — the
    /// interval, not the clock, decides.
    @Test("the same gap is due or not depending on the cadence")
    func cadenceDecidesDueness() {
        let gap = now.addingTimeInterval(-600)
        #expect(policy.isDue(lastAttempt: gap, lastPopoverOpen: now, now: now))
        #expect(!policy.isDue(lastAttempt: gap, lastPopoverOpen: nil, now: now))
    }

    @Test("opening the popover on fresh data does not spend a request")
    func openOnFreshData() {
        #expect(!policy.shouldFetchOnOpen(lastFetch: now.addingTimeInterval(-59), now: now))
        #expect(policy.shouldFetchOnOpen(lastFetch: now.addingTimeInterval(-61), now: now))
        #expect(policy.shouldFetchOnOpen(lastFetch: nil, now: now))
    }
}
