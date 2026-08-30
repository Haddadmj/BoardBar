import Foundation
import Observation

/// The configured boards, and which one is on screen.
///
/// `BoardCoordinator` is untouched — one per board, still the only thing that
/// fetches. This owns the collection and the selection, and is what the views
/// talk to.
///
/// It adds nothing to `PollPolicy`, deliberately. Only the selected tab is told
/// the popover was opened, so a background tab is already a board nobody has
/// looked at recently — which is what the policy has always called idle. The
/// 5-minute/30-minute split falls out of the existing rule with no second
/// notion of "background" to keep consistent with the first.
@MainActor
@Observable
public final class BoardSet {
    public private(set) var boards: [BoardCoordinator] = []

    public var selectedIndex: Int = 0 {
        didSet { defaults.set(selectedIndex, forKey: Self.selectionKey) }
    }

    public var selected: BoardCoordinator? {
        boards.indices.contains(selectedIndex) ? boards[selectedIndex] : nil
    }

    public static let selectionKey = "selectedBoardIndex"

    private let defaults: UserDefaults
    private let makeCoordinator: (BoardRef) -> BoardCoordinator

    public init(
        refs: [BoardRef],
        defaults: UserDefaults = .standard,
        makeCoordinator: @escaping (BoardRef) -> BoardCoordinator
    ) {
        self.defaults = defaults
        self.makeCoordinator = makeCoordinator
        boards = refs.map(makeCoordinator)
        // Clamped rather than trusted: the list may have shrunk while the app
        // was closed, and a stored index past the end would leave the popover
        // showing nothing with no way to say why.
        selectedIndex = Self.clamp(defaults.integer(forKey: Self.selectionKey), count: boards.count)
    }

    /// The refs currently configured, in tab order.
    public var refs: [BoardRef] { boards.compactMap(\.ref) }

    public var labels: [String] {
        TabLabel.labels(for: boards.compactMap { coordinator in
            coordinator.ref.map { (ref: $0, board: coordinator.board) }
        })
    }

    /// Whether a tab bar is worth drawing. One board is v1, and v1's popover
    /// had no tab bar.
    public var showsTabBar: Bool { boards.count > 1 }

    // MARK: - Reconfiguration

    /// Applies a new list of boards, keeping the coordinators that survive it.
    ///
    /// Rebuilding all of them would drop every cached board and in-flight
    /// timestamp on the floor, so adding a third tab would blank the two that
    /// were already loaded and refetch them for nothing.
    ///
    /// Returns the boards that are no longer configured, so their caches can be
    /// deleted by whoever owns the store — an orphaned cache file would mean a
    /// removed board silently reappearing with pre-removal data if it were ever
    /// added back.
    @discardableResult
    public func setRefs(_ refs: [BoardRef]) -> [BoardRef] {
        let previous = boards
        let selectedKey = selected?.ref?.storageKey
        let existing = Dictionary(
            previous.compactMap { coordinator in coordinator.ref.map { ($0.storageKey, coordinator) } },
            uniquingKeysWith: { first, _ in first }
        )

        boards = refs.map { existing[$0.storageKey] ?? makeCoordinator($0) }

        let survivingKeys = Set(refs.map(\.storageKey))
        let removed = previous.compactMap(\.ref).filter { !survivingKeys.contains($0.storageKey) }

        // The selected board keeps its selection wherever it moved to. When it
        // is the one that was removed, the index stays put and lands on the tab
        // that took its place on screen — which is what a neighbour is.
        if let selectedKey, let moved = boards.firstIndex(where: { $0.ref?.storageKey == selectedKey }) {
            selectedIndex = moved
        } else {
            selectedIndex = Self.clamp(selectedIndex, count: boards.count)
        }
        return removed
    }

    // MARK: - Triggers

    /// Selecting a tab is the same event as opening the popover on it: it
    /// promotes that board to the active cadence, and refreshes it if what is
    /// on screen is older than a minute.
    public func select(_ index: Int, now: Date = Date()) async {
        guard boards.indices.contains(index) else { return }
        selectedIndex = index
        await boards[index].popoverOpened(now: now)
    }

    public func popoverOpened(now: Date = Date()) async {
        await selected?.popoverOpened(now: now)
    }

    /// Every board is ticked; each one's own policy decides whether the tick
    /// does anything. That is the whole of the background cadence.
    public func tick(now: Date = Date()) async -> Bool {
        var attempted = false
        for board in boards where await board.tick(now: now) { attempted = true }
        return attempted
    }

    private static func clamp(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }
}
