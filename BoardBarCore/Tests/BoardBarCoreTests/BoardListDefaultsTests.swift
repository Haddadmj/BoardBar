import Foundation
import Testing

@testable import BoardBarCore

/// A `UserDefaults` of its own per test, so nothing here can read or write the
/// maintainer's real configuration.
private func scratchDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

private let main = "https://github.com/users/Haddadmj/projects/2/views/2"
private let mine = "https://github.com/users/Haddadmj/projects/2/views/3"

@Suite("Stored board list")
struct BoardListDefaultsTests {
    @Test("the stored order is the order that comes back")
    func orderRoundTrips() {
        let defaults = scratchDefaults()
        BoardURLParser.store(urls: [mine, main], defaults: defaults)

        #expect(BoardURLParser.storedURLs(defaults: defaults) == [mine, main])
        #expect(BoardURLParser.storedRefs(defaults: defaults).map(\.viewNumber) == [3, 2])
    }

    @Test("a v1 install with only boardURL set yields exactly one board")
    func migratesTheSingleBoard() {
        let defaults = scratchDefaults()
        defaults.set(main, forKey: BoardURLParser.defaultsKey)

        let refs = BoardURLParser.storedRefs(defaults: defaults)
        #expect(refs.count == 1)
        #expect(refs.first?.projectNumber == 2)
        #expect(refs.first?.viewNumber == 2)
    }

    /// The migration runs on every launch, and every read.
    @Test("migrating twice yields one board, not two")
    func migrationIsIdempotent() {
        let defaults = scratchDefaults()
        defaults.set(main, forKey: BoardURLParser.defaultsKey)

        BoardURLParser.migrateIfNeeded(defaults: defaults)
        BoardURLParser.migrateIfNeeded(defaults: defaults)
        BoardURLParser.migrateIfNeeded(defaults: defaults)

        #expect(BoardURLParser.storedURLs(defaults: defaults) == [main])
    }

    /// v1's key survives the migration untouched, so a rollback to a v1 build
    /// still finds the board that was configured.
    @Test("the migration leaves v1's key alone")
    func legacyKeyIsPreserved() {
        let defaults = scratchDefaults()
        defaults.set(main, forKey: BoardURLParser.defaultsKey)
        _ = BoardURLParser.storedRefs(defaults: defaults)

        #expect(defaults.string(forKey: BoardURLParser.defaultsKey) == main)
    }

    @Test("an entry that no longer parses is dropped, and the rest survive")
    func unparseableEntryIsDropped() {
        let defaults = scratchDefaults()
        BoardURLParser.store(
            urls: [main, "https://github.com/Haddadmj/qurba", mine], defaults: defaults
        )

        let refs = BoardURLParser.storedRefs(defaults: defaults)
        #expect(refs.count == 2)
        #expect(refs.map(\.viewNumber) == [2, 3])
        #expect(
            BoardURLParser.storedURLs(defaults: defaults).count == 3,
            "dropped for use, not deleted from what the user typed"
        )
    }

    @Test("saving an empty list clears the key and returns no boards")
    func emptyListClears() {
        let defaults = scratchDefaults()
        BoardURLParser.store(urls: [main], defaults: defaults)
        BoardURLParser.store(urls: [], defaults: defaults)

        #expect(defaults.stringArray(forKey: BoardURLParser.listDefaultsKey) == nil)
        #expect(BoardURLParser.storedRefs(defaults: defaults).isEmpty)
    }

    /// The reason the migration is flagged rather than inferred from the
    /// list being absent: removing the last board must stay removed.
    @Test("removing the last board does not resurrect the v1 one")
    func emptyingDoesNotResurrect() {
        let defaults = scratchDefaults()
        defaults.set(main, forKey: BoardURLParser.defaultsKey)
        #expect(BoardURLParser.storedRefs(defaults: defaults).count == 1)

        BoardURLParser.store(urls: [], defaults: defaults)
        #expect(BoardURLParser.storedRefs(defaults: defaults).isEmpty)
    }

    @Test("blank rows are not stored")
    func blankRowsDropped() {
        let defaults = scratchDefaults()
        BoardURLParser.store(urls: ["  ", main, ""], defaults: defaults)
        #expect(BoardURLParser.storedURLs(defaults: defaults) == [main])
    }
}
