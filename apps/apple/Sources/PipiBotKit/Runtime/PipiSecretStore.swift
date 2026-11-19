import Foundation
import Security

/// Abstraction for sensitive credential storage (API keys, tokens).
/// Production builds use `PipiKeychainSecretStore`; unit tests use `PipiInMemorySecretStore`.
public protocol PipiSecretStore: Sendable {
    func secret(for account: String) -> String?
    func setSecret(_ value: String, for account: String)
    func deleteSecret(for account: String)
}

/// Keychain-backed credential store using `kSecClassGenericPassword`.
/// Service is fixed to `app.pipibot.engine` and account is the provider ID.
public struct PipiKeychainSecretStore: PipiSecretStore, Sendable {
    public let service: String

    public init(service: String = "app.pipibot.engine") {
        self.service = service
    }

    public func secret(for account: String) -> String? {
        let trimmedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccount.isEmpty else { return nil }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: trimmedAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    public func setSecret(_ value: String, for account: String) {
        let trimmedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccount.isEmpty else { return }

        let cleanedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedValue.isEmpty {
            deleteSecret(for: trimmedAccount)
            return
        }

        guard let data = cleanedValue.data(using: .utf8) else { return }

        let matchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: trimmedAccount
        ]

        let updateAttrs: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(matchQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = matchQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            _ = SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    public func deleteSecret(for account: String) {
        let trimmedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccount.isEmpty else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: trimmedAccount
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}

/// Thread-safe in-memory secret store for isolated unit tests.
public final class PipiInMemorySecretStore: PipiSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    public init(initial: [String: String] = [:]) {
        self.storage = initial
    }

    public func secret(for account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[account]
    }

    public func setSecret(_ value: String, for account: String) {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        if cleaned.isEmpty {
            storage.removeValue(forKey: account)
        } else {
            storage[account] = cleaned
        }
    }

    public func deleteSecret(for account: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: account)
    }

    public var allStoredAccounts: [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
