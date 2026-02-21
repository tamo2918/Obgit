import Foundation
import Security

/// PAT / SSH 秘密鍵 / SSH パスフレーズ を iOS Keychain に安全保存するサービス
final class KeychainService: Sendable {
    static let shared = KeychainService()
    private let service = "com.tamo.Obgit.credentials"

    private init() {}

    // MARK: - PAT (HTTPS)

    /// PAT を保存（既存の場合は上書き）
    func save(token: String, for repositoryID: UUID) {
        saveItem(token, account: repositoryID.uuidString)
    }

    /// PAT を取得
    func retrieve(for repositoryID: UUID) -> String? {
        retrieveItem(account: repositoryID.uuidString)
    }

    // MARK: - SSH 秘密鍵

    func saveSSHKey(_ key: String, for repositoryID: UUID) {
        saveItem(key, account: "ssh_\(repositoryID.uuidString)")
    }

    func retrieveSSHKey(for repositoryID: UUID) -> String? {
        retrieveItem(account: "ssh_\(repositoryID.uuidString)")
    }

    // MARK: - SSH パスフレーズ

    func savePassphrase(_ passphrase: String, for repositoryID: UUID) {
        saveItem(passphrase, account: "pass_\(repositoryID.uuidString)")
    }

    func retrievePassphrase(for repositoryID: UUID) -> String? {
        retrieveItem(account: "pass_\(repositoryID.uuidString)")
    }

    // MARK: - 削除

    /// 指定リポジトリの全 Keychain エントリ（PAT・SSH 鍵・パスフレーズ）を削除
    func delete(for repositoryID: UUID) {
        deleteItem(account: repositoryID.uuidString)
        deleteItem(account: "ssh_\(repositoryID.uuidString)")
        deleteItem(account: "pass_\(repositoryID.uuidString)")
    }

    // MARK: - Private Helpers

    private func saveItem(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        deleteItem(account: account)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func retrieveItem(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private func deleteItem(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
