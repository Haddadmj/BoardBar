import BoardBarCore
import Foundation

/// The App Group container the menu-bar app writes into and the widget will
/// later read from.
///
/// Availability is probed rather than assumed. A missing entitlement is silent
/// — `containerURL` simply returns nil and every later write quietly does
/// nothing — and it is the one part of the app that can fail for reasons
/// outside the code.
enum SharedContainer {
    static let appGroupID = "group.com.haddadmj.boardbar"

    enum Availability: Equatable {
        case available(URL)
        case unavailable
    }

    static func probe() -> Availability {
        guard
            let url = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupID
            )
        else { return .unavailable }
        return .available(url)
    }

    static var url: URL? {
        guard case let .available(url) = probe() else { return nil }
        return url
    }

    /// The board cache. Falls back to memory when the container is unavailable,
    /// so a signing problem costs the cache rather than the whole app — the
    /// board still fetches and renders, it just does not survive a relaunch.
    static func makeBoardStore() -> any BoardStore {
        guard let url else { return InMemoryBoardStore() }
        return FileBoardStore(directory: url.appendingPathComponent("Boards", isDirectory: true))
    }
}
