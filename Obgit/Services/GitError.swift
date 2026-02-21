import Foundation

enum GitError: Error, LocalizedError {
    case cloneFailed(String)
    case fetchFailed(String)
    case resetFailed(String)
    case stagingFailed(String)
    case commitFailed(String)
    case pushFailed(String)
    case pushRejected(String)
    case nothingToCommit
    case repositoryNotFound
    case remoteNotFound
    case branchNotFound(String)
    case authenticationFailed
    case alreadyCloned
    case switchBranchFailed(String)
    case commitLogFailed(String)
    case mergeConflicts([ConflictFile])
    case mergeFailed(String)
    case conflictResolutionFailed(String)
    case noMergeInProgress
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .cloneFailed(let msg):
            return "クローン失敗: \(humanReadable(msg))"
        case .fetchFailed(let msg):
            return "フェッチ失敗: \(humanReadable(msg))"
        case .resetFailed(let msg):
            return "リセット失敗: \(humanReadable(msg))"
        case .stagingFailed(let msg):
            return "ステージング失敗: \(humanReadable(msg))"
        case .commitFailed(let msg):
            return "コミット失敗: \(humanReadable(msg))"
        case .pushFailed(let msg):
            return "プッシュ失敗: \(humanReadable(msg))"
        case .pushRejected:
            return "プッシュが拒否されました（non-fast-forward）。先に Pull してください。"
        case .nothingToCommit:
            return "コミットする変更がありません。"
        case .repositoryNotFound:
            return "リポジトリが見つかりません。URL を確認してください。"
        case .remoteNotFound:
            return "リモート (origin) が見つかりません。"
        case .branchNotFound(let branch):
            return "ブランチ '\(branch)' が見つかりません。ブランチ名を確認してください。"
        case .authenticationFailed:
            return "認証に失敗しました。ユーザー名と PAT を確認してください。"
        case .alreadyCloned:
            return "すでにクローン済みです。"
        case .switchBranchFailed(let msg):
            return "ブランチの切り替えに失敗しました: \(msg)"
        case .commitLogFailed(let msg):
            return "コミット履歴の取得に失敗しました: \(msg)"
        case .mergeConflicts(let files):
            let total = files.reduce(0) { $0 + $1.conflictCount }
            return "マージコンフリクトが発生しました（\(files.count) ファイル、\(total) 箇所）。解決してください。"
        case .mergeFailed(let msg):
            return "マージに失敗しました: \(msg)"
        case .conflictResolutionFailed(let msg):
            return "コンフリクト解決の保存に失敗しました: \(msg)"
        case .noMergeInProgress:
            return "マージ進行中の状態が見つかりません。"
        case .unknown(let msg):
            return "不明なエラー: \(msg)"
        }
    }

    /// libgit2 のエラーメッセージを日本語に変換
    private func humanReadable(_ msg: String) -> String {
        Self.humanReadableMessage(from: msg)
    }

    /// NSError（SwiftGit2 がラップして返す）を GitError に変換する
    static func mapFromNSError(_ error: NSError) -> GitError {
        let msg = error.localizedDescription
        let lower = msg.lowercased()
        if lower.contains("authentication") || lower.contains("credentials") ||
           lower.contains("401") || lower.contains("403") {
            return .authenticationFailed
        }
        if lower.contains("not found") || lower.contains("404") {
            return .repositoryNotFound
        }
        return .cloneFailed(humanReadableMessage(from: msg))
    }

    /// 英語のエラー文字列を日本語へ変換する共通ロジック
    static func humanReadableMessage(from msg: String) -> String {
        let lower = msg.lowercased()
        if lower.contains("authentication") || lower.contains("credentials") ||
           lower.contains("401") || lower.contains("403") {
            return "認証に失敗しました。ユーザー名と PAT を確認してください。"
        }
        if lower.contains("not found") || lower.contains("404") || lower.contains("repository") {
            return "リポジトリが見つかりません。URL を確認してください。"
        }
        if lower.contains("network") || lower.contains("connect") || lower.contains("resolve") {
            return "ネットワーク接続を確認してください。"
        }
        if lower.contains("no space") || lower.contains("disk full") {
            return "ストレージの空き容量が不足しています。"
        }
        if lower.contains("timeout") || lower.contains("timed out") {
            return "接続がタイムアウトしました。再度お試しください。"
        }
        return msg
    }
}
