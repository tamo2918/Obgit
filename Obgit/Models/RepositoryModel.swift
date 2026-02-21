import Foundation

// MARK: - AuthType

/// リポジトリの認証方式
/// remoteURL から自動判定する（stored ではなく computed）
enum AuthType: Sendable {
    case https   // HTTPS + PAT
    case sshKey  // SSH 鍵認証
}

// MARK: - RepositoryModel

struct RepositoryModel: Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    var remoteURL: String
    var branch: String
    var username: String
    // Documents/Repositories/<localDirName>/ にクローンされる
    var localDirName: String
    var isCloned: Bool
    var lastPullDate: Date?
    var logs: [OperationLog]

    struct OperationLog: Codable, Sendable, Identifiable {
        var id: UUID
        var date: Date
        var message: String
        var isError: Bool

        init(message: String, isError: Bool = false) {
            self.id = UUID()
            self.date = Date()
            self.message = message
            self.isError = isError
        }
    }

    init(name: String, remoteURL: String, branch: String = "main", username: String) {
        self.id = UUID()
        self.name = name
        self.remoteURL = remoteURL
        self.branch = branch
        self.username = username
        self.localDirName = Self.safeDirectoryName(from: name)
        self.isCloned = false
        self.lastPullDate = nil
        self.logs = []
    }

    /// パスに使用しても安全なディレクトリ名を生成する。
    /// 英数字・ハイフン・アンダースコア・ドット・スペース以外の文字（`/`, `..` 等）を除去する。
    private static func safeDirectoryName(from name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_. "))
        let base = name
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
            .unicodeScalars
            .filter { allowed.contains($0) }
            .map(String.init)
            .joined()
            .trimmingCharacters(in: .init(charactersIn: "._-"))
        let truncated = String(base.prefix(64))
        return truncated.isEmpty ? "repository" : truncated
    }

    /// remoteURL から認証方式を判定（git@ または ssh:// → SSH 鍵、それ以外 → HTTPS）
    var authType: AuthType {
        let url = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return (url.hasPrefix("git@") || url.lowercased().hasPrefix("ssh://")) ? .sshKey : .https
    }

    /// クローン先のローカル URL
    var localURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Repositories", isDirectory: true)
            .appendingPathComponent(localDirName, isDirectory: true)
    }

    mutating func addLog(_ message: String, isError: Bool = false) {
        let log = OperationLog(message: message, isError: isError)
        logs.insert(log, at: 0)
        // 最大 100 件保持
        if logs.count > 100 { logs = Array(logs.prefix(100)) }
    }
}
