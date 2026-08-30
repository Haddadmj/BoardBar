import Foundation

/// When to poll, expressed as pure arithmetic over three dates.
///
/// Kept separate from anything that owns a timer so the rules can be tested
/// without waiting on a clock. The app drives `tick` from a `Timer`; every
/// decision about whether that tick does anything is made here.
public struct PollPolicy: Sendable, Equatable {
    /// Cadence while the maintainer has looked at the board recently.
    public let activeInterval: TimeInterval
    /// Cadence when they have not. The app runs all day; polling a board nobody
    /// is looking at every 5 minutes spends most of a day's requests on nothing.
    public let idleInterval: TimeInterval
    /// How long after a popover opening the board still counts as watched.
    public let activeWindow: TimeInterval
    /// Opening the popover on data fresher than this does not trigger a fetch —
    /// it would only re-render the same board and burn a request.
    public let openFetchThreshold: TimeInterval

    public init(
        activeInterval: TimeInterval = 5 * 60,
        idleInterval: TimeInterval = 30 * 60,
        activeWindow: TimeInterval = 60 * 60,
        openFetchThreshold: TimeInterval = 60
    ) {
        self.activeInterval = activeInterval
        self.idleInterval = idleInterval
        self.activeWindow = activeWindow
        self.openFetchThreshold = openFetchThreshold
    }

    public func isActive(lastPopoverOpen: Date?, now: Date) -> Bool {
        guard let lastPopoverOpen else { return false }
        return now.timeIntervalSince(lastPopoverOpen) <= activeWindow
    }

    public func interval(lastPopoverOpen: Date?, now: Date) -> TimeInterval {
        isActive(lastPopoverOpen: lastPopoverOpen, now: now) ? activeInterval : idleInterval
    }

    /// A tick is due when nothing has been *attempted* yet, or when the
    /// applicable interval has elapsed since the last attempt.
    ///
    /// Deliberately keyed on the last attempt rather than the last success. A
    /// board that keeps failing never advances its success timestamp, so keying
    /// on success would make every tick due forever and collapse the poll rate
    /// to the tick rate — the tight retry loop this policy exists to prevent.
    /// The next scheduled poll is the retry.
    public func isDue(lastAttempt: Date?, lastPopoverOpen: Date?, now: Date) -> Bool {
        guard let lastAttempt else { return true }
        let elapsed = now.timeIntervalSince(lastAttempt)
        return elapsed >= interval(lastPopoverOpen: lastPopoverOpen, now: now)
    }

    public func shouldFetchOnOpen(lastFetch: Date?, now: Date) -> Bool {
        guard let lastFetch else { return true }
        return now.timeIntervalSince(lastFetch) > openFetchThreshold
    }
}
