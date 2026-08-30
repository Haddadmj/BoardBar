import BoardBarCore
import Foundation
import Observation
import os

/// Owns the configured boards and the one timer that drives them.
///
/// The timer ticks at a fixed low frequency and `PollPolicy` decides whether
/// each tick does anything. A self-rescheduling timer would have to be torn
/// down and rebuilt every time the cadence changed — on every popover opening,
/// and again an hour later — and a missed rebuild would silently stop polling.
/// A dumb timer that mostly does nothing cannot fail that way.
@MainActor
@Observable
final class AppModel {
    let boardSet: BoardSet
    private var timer: Timer?

    /// The board on screen. Optional because "no board configured" is a real
    /// state on a first run, not a failure to be defaulted around.
    var coordinator: BoardCoordinator? { boardSet.selected }

    /// A menu-bar app polls with no window to report into. Without a trace
    /// there is no way to answer "is it still polling?" after the fact — not
    /// for the maintainer and not for a test. Nothing here logs the token:
    /// only outcomes, never credentials or request bodies.
    private let log = Logger(subsystem: "com.haddadmj.boardbar", category: "poll")

    /// Fine enough to honour a 5-minute cadence without meaningful drift, and
    /// cheap enough to leave running all day.
    private let tickInterval: TimeInterval = 60

    /// Advanced on every tick so anything derived from "how old is this board"
    /// re-evaluates. Without it a board would cross the staleness threshold
    /// with nothing on screen changing, because no state changed — only time
    /// passed, and SwiftUI cannot observe that.
    private(set) var now = Date()

    /// The single place that decides what is being shown and how the icon
    /// looks. Two surfaces disagreeing about staleness is exactly what deriving
    /// this once prevents.
    ///
    /// Derived from the **selected** board only. Worst-across-all-tabs sounds
    /// more informative and is not: background tabs poll on a 30-minute cadence
    /// against a 30-minute staleness threshold, so they sit permanently at the
    /// boundary and an icon driven by them would dim more or less constantly.
    /// An icon that is always dim says nothing.
    var status: StatusSummary {
        Freshness.summarize(
            hasBoard: coordinator?.board != nil,
            lastFetchedAt: coordinator?.lastFetchedAt,
            error: coordinator?.lastError,
            now: now
        )
    }

    private let tokens: any TokenStore
    private let store: any BoardStore

    init() {
        let tokens = KeychainTokenStore()
        let store = SharedContainer.makeBoardStore()
        self.tokens = tokens
        self.store = store
        boardSet = BoardSet(refs: BoardURLParser.storedRefs()) { ref in
            BoardCoordinator(ref: ref, store: store, tokens: tokens)
        }
        startTimer()
    }

    /// Whether a token exists — never what it is. The settings field is
    /// write-only by design: there is no reason to render a credential back to
    /// someone who already has it, and every reason not to.
    var hasToken: Bool { (try? tokens.read()) != nil }

    /// True on a first run, where an empty board would explain nothing.
    var needsConfiguration: Bool { boardSet.boards.isEmpty || !hasToken }

    var boardURLStrings: [String] { BoardURLParser.storedURLs() }

    func save(boardURLs: [String], token: String?) {
        BoardURLParser.store(urls: boardURLs)
        // An empty field means "leave the stored token alone", not "delete it".
        // The field renders empty even when a token exists, so treating empty
        // as a delete would wipe the token every time settings are saved.
        let tokenChanged = !(token ?? "").isEmpty
        if let token, !token.isEmpty {
            try? tokens.write(token)
        }

        // A removed board takes its cache with it. An orphaned file would mean
        // a board that was removed and later added back coming up showing what
        // it held before it was removed.
        let removed = boardSet.setRefs(BoardURLParser.storedRefs())
        for ref in removed { try? store.clear(ref) }

        Task {
            // A board added just now has never fetched; one that was already
            // there has, and only needs telling when the credential changed
            // underneath it.
            for board in boardSet.boards where board.board == nil {
                await board.refresh(reason: .configurationChanged)
            }
            if tokenChanged {
                for board in boardSet.boards { await board.tokenChanged() }
            }
            self.report("settingsSaved")
        }
    }

    /// Fetches every configured board now, whatever its cadence says. The
    /// only place that ignores the policy, and it is doing so because someone
    /// asked in as many words.
    func refreshAll() {
        now = Date()
        Task {
            for board in boardSet.boards {
                await board.refresh(reason: .manual)
            }
            report("refreshAll")
        }
    }

    func clearToken() {
        try? tokens.write(nil)
        Task {
            for board in boardSet.boards { await board.tokenChanged() }
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                let cadence = self.coordinator.map { Int($0.currentInterval() / 60) } ?? 0
                self.log.debug("tick: \(self.boardSet.boards.count) boards, selected cadence \(cadence)m")
                // Every board is ticked; each one's policy decides whether its
                // tick does anything. The background cadence is that, and
                // nothing else.
                if await self.boardSet.tick() { self.report("tick") }
            }
        }
        // The board should be current when the popover first opens, not a
        // minute later.
        Task {
            for board in boardSet.boards {
                await board.refresh(reason: .launch)
            }
            report("launch")
        }
    }

    func popoverOpened() {
        now = Date()
        Task {
            await boardSet.popoverOpened()
            report("popoverOpened")
        }
    }

    /// Switching tabs is the same event as opening the popover on that board:
    /// it promotes it to the active cadence and refreshes it if what is on
    /// screen has gone off.
    func select(_ index: Int) {
        now = Date()
        Task {
            await boardSet.select(index)
            report("tabSelected")
        }
    }

    private func report(_ reason: String) {
        guard let coordinator else {
            log.notice("\(reason, privacy: .public): no board configured")
            return
        }
        if let error = coordinator.lastError {
            log.notice("\(reason, privacy: .public): failed — \(error.message, privacy: .public)")
        } else if let board = coordinator.board {
            log.notice("\(reason, privacy: .public): ok — \(board.shownCount, privacy: .public) items in \(board.columns.count, privacy: .public) columns")
        } else {
            log.notice("\(reason, privacy: .public): no board")
        }
    }
}
