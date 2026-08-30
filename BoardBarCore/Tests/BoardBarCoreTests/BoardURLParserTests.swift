import Testing

@testable import BoardBarCore

@Suite("Board URL parsing")
struct BoardURLParserTests {
    /// The real target board, from the spec.
    @Test("the worked example parses exactly")
    func workedExample() throws {
        let ref = try BoardURLParser.parse("https://github.com/users/Haddadmj/projects/2/views/2")
        #expect(ref.ownerKind == .users)
        #expect(ref.owner == "Haddadmj")
        #expect(ref.projectNumber == 2)
        #expect(ref.viewNumber == 2)
    }

    @Test("an org board parses")
    func orgBoard() throws {
        let ref = try BoardURLParser.parse("https://github.com/orgs/neotek/projects/7/views/1")
        #expect(ref.ownerKind == .orgs)
        #expect(ref.owner == "neotek")
        #expect(ref.viewNumber == 1)
    }

    @Test("a URL without /views/ yields a nil view number, sending ticket 04 down its fallback")
    func noViewSegment() throws {
        let ref = try BoardURLParser.parse("https://github.com/users/Haddadmj/projects/2")
        #expect(ref.viewNumber == nil)
    }

    @Test(
        "GitHub's own address-bar shapes parse",
        arguments: [
            "https://github.com/users/Haddadmj/projects/2/views/2/",
            "https://github.com/users/Haddadmj/projects/2/views/2?pane=issue&itemId=123",
            "https://www.github.com/users/Haddadmj/projects/2/views/2",
            "  https://github.com/users/Haddadmj/projects/2/views/2  ",
            "github.com/users/Haddadmj/projects/2/views/2",
        ]
    )
    func tolerantShapes(_ input: String) throws {
        let ref = try BoardURLParser.parse(input)
        #expect(ref.owner == "Haddadmj")
        #expect(ref.projectNumber == 2)
        #expect(ref.viewNumber == 2)
    }

    @Test("a repo issues URL is rejected by name, not generically")
    func repoIssuesURL() {
        #expect(throws: BoardURLError.looksLikeRepoIssues) {
            try BoardURLParser.parse("https://github.com/Haddadmj/qurba/issues?q=is%3Aopen")
        }
    }

    @Test("a bare repo URL is rejected by name")
    func repoURL() {
        #expect(throws: BoardURLError.looksLikeRepo) {
            try BoardURLParser.parse("https://github.com/Haddadmj/qurba")
        }
    }

    @Test("a non-GitHub host names the host it found")
    func wrongHost() {
        #expect(throws: BoardURLError.notGitHub(host: "gitlab.com")) {
            try BoardURLParser.parse("https://gitlab.com/users/x/projects/2")
        }
    }

    @Test("a non-numeric project number names what it found")
    func badProjectNumber() {
        #expect(throws: BoardURLError.projectNumberNotAnInteger("abc")) {
            try BoardURLParser.parse("https://github.com/users/Haddadmj/projects/abc")
        }
    }

    @Test("empty input is its own error")
    func empty() {
        #expect(throws: BoardURLError.empty) { try BoardURLParser.parse("   ") }
    }

    /// Ticket 05 keys the App Group store per board. Two different boards must
    /// not collide, or one silently overwrites the other on disk.
    @Test("storage keys are distinct per board")
    func storageKeys() throws {
        let a = try BoardURLParser.parse("https://github.com/users/Haddadmj/projects/2/views/2")
        let b = try BoardURLParser.parse("https://github.com/users/Haddadmj/projects/2/views/3")
        let c = try BoardURLParser.parse("https://github.com/users/Haddadmj/projects/2")
        #expect(Set([a.storageKey, b.storageKey, c.storageKey]).count == 3)
    }
}
