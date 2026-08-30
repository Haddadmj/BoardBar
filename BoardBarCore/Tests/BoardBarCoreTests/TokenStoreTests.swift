import Foundation
import Testing

@testable import BoardBarCore

/// The contract both stores must honour. Written once and run against both, so
/// the in-memory double cannot quietly drift from the real Keychain and make
/// every other test in the suite a lie.
private func assertContract(_ store: some TokenStore) throws {
    try store.write(nil)
    #expect(try store.read() == nil, "an empty store reads as nil, not as an error")

    try store.write("ghp_first")
    #expect(try store.read() == "ghp_first")

    // Overwrite rather than duplicate — the Keychain path takes a different
    // branch here (update, not add) and it is where a naive implementation
    // fails with errSecDuplicateItem.
    try store.write("ghp_second")
    #expect(try store.read() == "ghp_second")

    try store.write(nil)
    #expect(try store.read() == nil, "writing nil deletes")

    // Deleting nothing is not an error; the settings sheet clears a field that
    // may already be empty.
    try store.write(nil)
    #expect(try store.read() == nil)

    // An empty string is a cleared field, not a token of length zero.
    try store.write("")
    #expect(try store.read() == nil)
}

@Suite("Token storage")
struct TokenStoreTests {
    @Test("the in-memory store honours the contract")
    func inMemory() throws {
        try assertContract(InMemoryTokenStore())
    }

    /// Uses a throwaway service name so it can never touch the real stored
    /// token, and cleans up after itself either way.
    @Test("the Keychain store honours the same contract")
    func keychain() throws {
        let store = KeychainTokenStore(
            service: "com.haddadmj.boardbar.tests", account: "contract"
        )
        defer { try? store.write(nil) }
        try assertContract(store)
    }

    @Test("a token round-trips through the real Keychain unchanged")
    func roundTripFidelity() throws {
        let store = KeychainTokenStore(
            service: "com.haddadmj.boardbar.tests", account: "fidelity"
        )
        defer { try? store.write(nil) }
        // Length and character set of a real fine-grained PAT.
        let token = "github_pat_11ABCDEFG0" + String(repeating: "aZ9_", count: 15)
        try store.write(token)
        #expect(try store.read() == token)
    }

    @Test("two accounts in the same service do not collide")
    func accountIsolation() throws {
        let a = KeychainTokenStore(service: "com.haddadmj.boardbar.tests", account: "a")
        let b = KeychainTokenStore(service: "com.haddadmj.boardbar.tests", account: "b")
        defer { try? a.write(nil); try? b.write(nil) }
        try a.write("token-a")
        try b.write("token-b")
        #expect(try a.read() == "token-a")
        #expect(try b.read() == "token-b")
    }
}
