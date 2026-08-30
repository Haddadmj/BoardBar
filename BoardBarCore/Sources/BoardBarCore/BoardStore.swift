import Foundation

/// Where the last good board lives between polls, between launches, and
/// (eventually) between the app and the widget.
public protocol BoardStore: Sendable {
    /// Returns nil when nothing is stored, and also when what is stored can no
    /// longer be read — a cache that cannot be decoded is the same as no cache,
    /// and must never be an error the user has to deal with.
    func load(_ ref: BoardRef) -> Board?
    func save(_ board: Board, for ref: BoardRef) throws
    func clear(_ ref: BoardRef) throws
}

/// One JSON file per board under `directory`.
///
/// Keyed by `BoardRef.storageKey` rather than a single `board.json`. That costs
/// nothing today and is what lets two widgets show two different boards later
/// without migrating what is already on disk — the third of the three shortcuts
/// the spec pre-pays against a possible public release.
public struct FileBoardStore: BoardStore {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private func url(for ref: BoardRef) -> URL {
        directory.appendingPathComponent("board-\(ref.storageKey).json")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public func load(_ ref: BoardRef) -> Board? {
        guard let data = try? Data(contentsOf: url(for: ref)) else { return nil }
        return try? Self.decoder.decode(Board.self, from: data)
    }

    public func save(_ board: Board, for ref: BoardRef) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(board)
        // Atomic: the widget may read this file at any moment, and a partial
        // write would show it a board that never existed.
        try data.write(to: url(for: ref), options: .atomic)
    }

    public func clear(_ ref: BoardRef) throws {
        let target = url(for: ref)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }
}

public final class InMemoryBoardStore: BoardStore, @unchecked Sendable {
    private let lock = NSLock()
    private var boards: [String: Board] = [:]

    public init() {}

    public func load(_ ref: BoardRef) -> Board? {
        lock.lock(); defer { lock.unlock() }
        return boards[ref.storageKey]
    }

    public func save(_ board: Board, for ref: BoardRef) throws {
        lock.lock(); defer { lock.unlock() }
        boards[ref.storageKey] = board
    }

    public func clear(_ ref: BoardRef) throws {
        lock.lock(); defer { lock.unlock() }
        boards[ref.storageKey] = nil
    }
}
