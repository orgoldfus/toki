import Foundation
import Security

public protocol SessionTokenStoring: Sendable {
    func loadToken() throws -> String?
    func saveToken(_ token: String) throws
    func clearToken() throws
}

public enum SessionTokenStoreError: Error, Equatable, Sendable {
    case invalidTokenData
    case keychainFailure(OSStatus)
}

public final class InMemorySessionTokenStore: SessionTokenStoring, @unchecked Sendable {
    private var token: String?

    public init(token: String? = nil) {
        self.token = token
    }

    public func loadToken() throws -> String? {
        token
    }

    public func saveToken(_ token: String) throws {
        self.token = token
    }

    public func clearToken() throws {
        token = nil
    }
}

public final class KeychainSessionTokenStore: SessionTokenStoring, @unchecked Sendable {
    private let service: String
    private let account: String

    public init(service: String = "com.toki.session", account: String = "session-token") {
        self.service = service
        self.account = account
    }

    public func loadToken() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw SessionTokenStoreError.keychainFailure(status)
        }

        guard
            let data = result as? Data,
            let token = String(data: data, encoding: .utf8)
        else {
            throw SessionTokenStoreError.invalidTokenData
        }

        return token
    }

    public func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            return
        }

        guard status == errSecDuplicateItem else {
            throw SessionTokenStoreError.keychainFailure(status)
        }

        let updateStatus = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        guard updateStatus == errSecSuccess else {
            throw SessionTokenStoreError.keychainFailure(updateStatus)
        }
    }

    public func clearToken() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SessionTokenStoreError.keychainFailure(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
