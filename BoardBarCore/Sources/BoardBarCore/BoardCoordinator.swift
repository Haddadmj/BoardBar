import Foundation
import Observation

/// Why a fetch was attempted. Carried so tests can assert on cause rather than
/// only on effect, and so ticket 08 can decide what to surface.
public enum FetchReason: String, Sendable {
    case launch
    case tick
    case popoverOpened
    case configurationChanged
    case manual
}

/// Owns the board's lifecycle: what is on screen, when to refresh it, and what
/// to do when a refresh fails.
///
/// This is the app's only network client. The widget reads the shared store and
/// never fetches, so board traffic stays at one poll regardless of how many
/// surfaces are showing it.
@MainActor
@Observable
public final class BoardCoordinator {
    public private(set) var board: Board?
    public private(set) var lastError: GitHubError?
    public private(set) var isFetching = false
    /// When a board was last fetched *successfully*. Drives the "updated 40m
    /// ago" footer, so it must not move on failure.
    public private(set) var lastFetchedAt: Date?
    /// When a refresh was last *attempted*, successful or not. Drives the poll
    /// cadence, so a persistently failing board backs off like any other
    /// instead of retrying on every tick.
    public private(set) var lastAttemptAt: Date?
    public private(set) var lastPopoverOpen: Date?

    /// Counts refreshes skipped because one was already running. Not shown to
    /// anyone — it exists so a test can prove the drop happened rather than
    /// inferring it from a request count.
    public private(set) var droppedRefreshes = 0

    public var ref: BoardRef? { didSet { if ref != oldValue { configurationChanged() } } }

    private let fetcher: BoardFetcher
    private let store: any BoardStore
    private let tokens: any TokenStore
    private let policy: PollPolicy

    public init(
        ref: BoardRef? = nil,
        fetcher: BoardFetcher = BoardFetcher(),
        store: any BoardStore,
        tokens: any TokenStore,
        policy: PollPolicy = PollPolicy()
    ) {
        self.ref = ref
        self.fetcher = fetcher
        self.store = store
        self.tokens = tokens
        self.policy = policy
        loadCached()
    }

    /// Renders whatever is on disk before the first fetch returns, so a relaunch
    /// shows the last known board immediately instead of an empty popover.
    private func loadCached() {
        guard let ref, let cached = store.load(ref) else { return }
        board = cached
        lastFetchedAt = cached.fetchedAt
    }

    // MARK: - Triggers

    public func popoverOpened(now: Date = Date()) async {
        lastPopoverOpen = now
        guard policy.shouldFetchOnOpen(lastFetch: lastFetchedAt, now: now) else { return }
        await refresh(reason: .popoverOpened, now: now)
    }

    /// Driven by the app's timer. Most ticks do nothing; the policy decides.
    ///
    /// Returns whether a refresh was actually attempted, so a caller logging
    /// the outcome does not report on ticks that did nothing — which would make
    /// a quiet, correctly backed-off poller look like a busy one.
    @discardableResult
    public func tick(now: Date = Date()) async -> Bool {
        // No board configured is not a failed attempt — it is nothing to do.
        // Treating it as an attempt would leave `lastAttemptAt` nil forever
        // (refresh returns before stamping it), so every tick would stay due
        // and the app would wake once a minute, for ever, to decide it has no
        // work. Cheap, but it is a busy loop and it floods the log.
        guard ref != nil else { return false }
        guard policy.isDue(lastAttempt: lastAttemptAt, lastPopoverOpen: lastPopoverOpen, now: now)
        else { return false }
        await refresh(reason: .tick, now: now)
        return true
    }

    public func currentInterval(now: Date = Date()) -> TimeInterval {
        policy.interval(lastPopoverOpen: lastPopoverOpen, now: now)
    }

    private func configurationChanged() {
        // A board from the previous configuration is not a stale version of the
        // new one — it is a different board, and leaving it on screen would be a
        // lie rather than a cache.
        board = nil
        lastFetchedAt = nil
        lastAttemptAt = nil
        lastError = nil
        loadCached()
        Task { await refresh(reason: .configurationChanged) }
    }

    /// Call after the token changes. Separate from `ref` because the board
    /// identity has not changed — only whether it can be read.
    public func tokenChanged() async {
        lastError = nil
        await refresh(reason: .configurationChanged)
    }

    // MARK: - The fetch

    @discardableResult
    public func refresh(reason: FetchReason, now: Date = Date()) async -> Bool {
        // Dropped, not queued. A queued refresh would fire against a board the
        // maintainer has already stopped looking at, and two polls racing to
        // write the same file is exactly what the atomic write in ticket 05 is
        // protecting against.
        guard !isFetching else {
            droppedRefreshes += 1
            return false
        }
        guard let ref else { return false }
        // Stamped before the token check: a missing token is an attempt that
        // failed, and must back off exactly like a network failure does.
        lastAttemptAt = now

        let token: String?
        do { token = try tokens.read() } catch { token = nil }
        guard let token, !token.isEmpty else {
            lastError = .unauthorized
            return false
        }

        isFetching = true
        defer { isFetching = false }

        do {
            let fetched = try await fetcher.fetch(ref, token: token, now: now)
            board = fetched
            lastFetchedAt = fetched.fetchedAt
            lastError = nil
            // Saved only on success, so a failed poll leaves both the stored
            // board and its timestamp untouched and "updated 40m ago" stays a
            // fact rather than a decoration.
            try? store.save(fetched, for: ref)
            return true
        } catch {
            // The last good board stays on screen. Ticket 08 decides how that
            // is dressed; nothing here hides the failure — `lastError` is set
            // and the timestamp is deliberately not advanced.
            lastError = error
            return false
        }
    }
}
