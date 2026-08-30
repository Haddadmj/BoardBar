import Foundation
import Security

/// The whole surface the rest of the app sees for the GitHub token.
///
/// Everything reaches the token through this, never through `SecItem*` calls
/// directly. That is the second of the three shortcuts the spec pre-pays: if a
/// PAT is swapped for an OAuth token later, the change is one conforming type
/// rather than a search across the codebase.
public protocol TokenStore: Sendable {
    func read() throws -> String?
    /// Passing nil deletes the stored token.
    func write(_ token: String?) throws
}

public enum TokenStoreError: Error, Equatable, Sendable {
    case keychain(OSStatus)
    case notUTF8

    public var message: String {
        switch self {
        case let .keychain(status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Keychain error: \(detail)"
        case .notUTF8:
            return "The stored token wasn't readable text."
        }
    }
}

public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    public init(service: String = "com.haddadmj.boardbar", account: String = "github-pat") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw TokenStoreError.notUTF8 }
            guard let token = String(data: data, encoding: .utf8) else {
                throw TokenStoreError.notUTF8
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw TokenStoreError.keychain(status)
        }
    }

    public func write(_ token: String?) throws {
        guard let token, !token.isEmpty else {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw TokenStoreError.keychain(status)
            }
            return
        }

        let data = Data(token.utf8)
        // Update first: SecItemAdd on an existing item fails with duplicate,
        // and an add-then-delete dance would briefly leave no token stored.
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw TokenStoreError.keychain(updateStatus)
        }

        var insert = baseQuery
        insert[kSecValueData as String] = data
        // The app polls on a timer and must reach the token whenever it wakes,
        // so it cannot require an unlocked keychain at that moment — but it
        // should not leave the device either.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw TokenStoreError.keychain(addStatus) }
    }
}

/// Test double. Also what the app falls back to if the Keychain is unreachable,
/// so a broken Keychain degrades to "asks for the token again" rather than a
/// crash on launch.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    public init(token: String? = nil) { self.token = token }

    public func read() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return token
    }

    public func write(_ token: String?) throws {
        lock.lock(); defer { lock.unlock() }
        self.token = (token?.isEmpty ?? true) ? nil : token
    }
}
