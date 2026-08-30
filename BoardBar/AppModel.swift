import BoardBarCore
import Foundation
import Observation
import os

/// Owns the coordinator and the one timer that drives it.
///
/// The timer ticks at a fixed low frequency and `PollPolicy` decides whether
/// each tick does anything. A self-rescheduling timer would have to be torn
/// down and rebuilt every time the cadence changed — on every popover opening,
/// and again an hour later — and a missed rebuild would silently stop polling.
/// A dumb timer that mostly does nothing cannot fail that way.
@MainActor
@Observable
final class AppModel {
    let coordinator: BoardCoordinator
    private var timer: Timer?

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
    var status: StatusSummary {
        Freshness.summarize(
            hasBoard: coordinator.board != nil,
            lastFetchedAt: coordinator.lastFetchedAt,
            error: coordinator.lastError,
            now: now
        )
    }

    private let tokens: any TokenStore

    init() {
        let tokens = KeychainTokenStore()
        self.tokens = tokens
        coordinator = BoardCoordinator(
            ref: BoardURLParser.storedRefs().first,
            store: SharedContainer.makeBoardStore(),
            tokens: tokens
        )
        startTimer()
    }

    /// Whether a token exists — never what it is. The settings field is
    /// write-only by design: there is no reason to render a credential back to
    /// someone who already has it, and every reason not to.
    var hasToken: Bool { (try? tokens.read()) != nil }

    /// True on a first run, where an empty board would explain nothing.
    var needsConfiguration: Bool { coordinator.ref == nil || !hasToken }

    var boardURLString: String {
        BoardURLParser.storedURLs().first ?? ""
    }

    func save(boardURL: String, token: String?) {
        BoardURLParser.store(urls: [boardURL])
        // An empty field means "leave the stored token alone", not "delete it".
        // The field renders empty even when a token exists, so treating empty
        // as a delete would wipe the token every time the sheet is saved.
        if let token, !token.isEmpty {
            try? tokens.write(token)
        }
        // Assigning `ref` already triggers a refresh when it changes, so
        // asking for one again would fire a second fetch that the in-flight
        // guard merely drops. Only nudge the coordinator when the board itself
        // did not change and the token is the thing that did.
        let newRef = BoardURLParser.storedRefs().first
        let refChanged = newRef != coordinator.ref
        coordinator.ref = newRef
        Task {
            if !refChanged { await coordinator.tokenChanged() }
            self.report("settingsSaved")
        }
    }

    func clearToken() {
        try? tokens.write(nil)
        Task { await coordinator.tokenChanged() }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                let cadence = Int(self.coordinator.currentInterval() / 60)
                self.log.debug("tick: cadence \(cadence)m, fetching \(self.coordinator.isFetching)")
                if await self.coordinator.tick() { self.report("tick") }
            }
        }
        // The board should be current when the popover first opens, not a
        // minute later.
        Task {
            await coordinator.refresh(reason: .launch)
            report("launch")
        }
    }

    func popoverOpened() {
        now = Date()
        Task {
            await coordinator.popoverOpened()
            report("popoverOpened")
        }
    }

    private func report(_ reason: String) {
        if let error = coordinator.lastError {
            log.notice("\(reason, privacy: .public): failed — \(error.message, privacy: .public)")
        } else if let board = coordinator.board {
            log.notice("\(reason, privacy: .public): ok — \(board.shownCount, privacy: .public) items in \(board.columns.count, privacy: .public) columns")
        } else {
            log.notice("\(reason, privacy: .public): no board")
        }
    }
}
