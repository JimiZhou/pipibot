import Foundation
import Security
#if canImport(CryptoKit)
import CryptoKit
#endif
#if os(macOS)
import IOKit
#endif

/// Abstraction for sensitive credential storage (API keys, tokens).
/// Production macOS builds use `PipiLocalEncryptedSecretStore` (AES-256-GCM `0600` local vault,
/// zero Keychain ACL popups across ad-hoc rebuilds and GitHub auto-updates);
/// `PipiKeychainSecretStore` is retained for optional manual one-time migration;
/// unit tests use `PipiInMemorySecretStore`.
public protocol PipiSecretStore: Sendable {
    func secret(for account: String) -> String?
    func setSecret(_ value: String, for account: String)
    func deleteSecret(for account: String)
}

/// Local AES-256-GCM encrypted credential vault stored at `~/Library/Application Support/PiPiBot/vault.enc`
/// with strict `0600` POSIX permissions and a machine-bound HKDF-SHA256 key.
/// Never touches macOS legacy `login.keychain-db`, completely eliminating repeated password prompts
/// on ad-hoc signed rebuilds and GitHub Release auto-updates.
public final class PipiLocalEncryptedSecretStore: PipiSecretStore, @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()
    private let keyMaterial: Data
    private var cache: [String: String] = [:]
    private var isLoaded = false

    public static func defaultVaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("PiPiBot", isDirectory: true)
            .appendingPathComponent("vault.enc", isDirectory: false)
    }

    public init(fileURL: URL? = nil, machineSeedOverride: String? = nil) {
        self.fileURL = fileURL ?? Self.defaultVaultURL()
        let seed = machineSeedOverride ?? Self.resolveMachineSeed()
        self.keyMaterial = Data(seed.utf8)
    }

    public func secret(for account: String) -> String? {
        let trimmed = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        return cache[trimmed]
    }

    public func setSecret(_ value: String, for account: String) {
        let trimmed = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        if cleaned.isEmpty {
            cache.removeValue(forKey: trimmed)
        } else {
            cache[trimmed] = cleaned
        }
        persistLocked()
    }

    public func deleteSecret(for account: String) {
        let trimmed = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        if cache.removeValue(forKey: trimmed) != nil {
            persistLocked()
        }
    }

    public var storedAccountCount: Int {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        return cache.count
    }

    /// Manually imports specified account keys from legacy macOS Keychain into this local encrypted vault.
    /// Called ONLY when the user explicitly clicks the import button in Settings.
    @discardableResult
    public func migrateFromLegacyKeychain(
        accounts: [String],
        legacyStore: any PipiSecretStore = PipiKeychainSecretStore()
    ) -> Int {
        var imported = 0
        for rawAccount in accounts {
            let acct = rawAccount.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !acct.isEmpty else { continue }
            if let existing = secret(for: acct), !existing.isEmpty {
                continue
            }
            if let legacyVal = legacyStore.secret(for: acct),
               !legacyVal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                setSecret(legacyVal, for: acct)
                imported += 1
            }
        }
        return imported
    }

    // MARK: - CryptoKit AES-256-GCM Storage

    private func ensureLoadedLocked() {
        guard !isLoaded else { return }
        isLoaded = true
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let encryptedData = try? Data(contentsOf: fileURL),
              !encryptedData.isEmpty else {
            return
        }
        if let decrypted = decryptPayload(encryptedData),
           let decoded = try? JSONDecoder().decode([String: String].self, from: decrypted) {
            cache = decoded
        }
    }

    private func persistLocked() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let plainData = try? JSONEncoder().encode(cache),
              let encrypted = encryptPayload(plainData) else {
            return
        }
        do {
            try encrypted.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            // Keep in-memory cache intact even if disk write fails transiently
        }
    }

    #if canImport(CryptoKit)
    private func derivedKey() -> SymmetricKey {
        let inputKey = SymmetricKey(data: keyMaterial)
        let salt = Data("ai.pipibot.local.vault.salt.v1".utf8)
        let info = Data("pipibot-aes256gcm-secret-vault".utf8)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: info,
            outputByteCount: 32
        )
    }

    private func encryptPayload(_ plain: Data) -> Data? {
        guard let sealed = try? AES.GCM.seal(plain, using: derivedKey()),
              let combined = sealed.combined else {
            return nil
        }
        var out = Data("PPVT1".utf8)
        out.append(combined)
        return out
    }

    private func decryptPayload(_ data: Data) -> Data? {
        let magic = Data("PPVT1".utf8)
        guard data.count > magic.count, data.prefix(magic.count) == magic else {
            return nil
        }
        let body = data.dropFirst(magic.count)
        guard let box = try? AES.GCM.SealedBox(combined: body),
              let plain = try? AES.GCM.open(box, using: derivedKey()) else {
            return nil
        }
        return plain
    }
    #else
    private func encryptPayload(_ plain: Data) -> Data? { plain }
    private func decryptPayload(_ data: Data) -> Data? { data }
    #endif

    private static func resolveMachineSeed() -> String {
        #if os(macOS)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            if let uuidRef = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
               !uuidRef.isEmpty {
                return "macos-\(uuidRef)-\(NSUserName())"
            }
        }
        #endif
        return "host-\(ProcessInfo.processInfo.hostName)-\(NSUserName())-pipibot"
    }
}

/// Keychain-backed credential store using `kSecClassGenericPassword`.
/// Retained for optional manual migration on macOS or signed iOS builds.
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
