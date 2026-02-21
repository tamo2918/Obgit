import Foundation
import SwiftUI
import Combine

@MainActor
final class RepositoryDetailViewModel: ObservableObject {
    @Published var repo: RepositoryModel
    @Published var isLoading = false
    @Published var progressMessage = ""
    @Published var progressLogs: [String] = []   // 操作中のリアルタイムログ
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let store = RepositoryStore.shared
    private let git = GitService.shared

    init(repo: RepositoryModel) {
        self.repo = repo
    }

    // MARK: - Clone

    func startClone() {
        guard !isLoading else { return }

        let (username, password, sshKey, sshPassphrase) = authCredentials()
        guard password != "" || sshKey != nil else {
            errorMessage = "認証情報が見つかりません。設定から認証情報を入力してください。"
            return
        }

        isLoading = true
        errorMessage = nil
        successMessage = nil
        progressMessage = "準備中..."
        progressLogs = ["準備中..."]

        Task {
            do {
                try await git.clone(
                    from: repo.remoteURL,
                    to: repo.localURL,
                    branch: repo.branch,
                    username: username,
                    password: password,
                    sshPrivateKey: sshKey,
                    sshPassphrase: sshPassphrase,
                    progress: { [weak self] msg in
                        Task { @MainActor [weak self] in
                            self?.progressMessage = msg
                            self?.progressLogs.append(msg)
                        }
                    }
                )

                repo.isCloned = true
                let detail = progressLogs.joined(separator: " → ")
                repo.addLog("クローン完了 (\(detail))")
                store.update(repo)
                successMessage = "クローンが完了しました"
            } catch {
                repo.addLog(error.localizedDescription, isError: true)
                store.update(repo)
                errorMessage = error.localizedDescription
            }
            isLoading = false
            progressMessage = ""
            progressLogs = []
        }
    }

    // MARK: - Pull

    func startPull() {
        guard !isLoading else { return }
        guard repo.isCloned else {
            errorMessage = "先にクローンを実行してください。"
            return
        }

        let (username, password, sshKey, sshPassphrase) = authCredentials()
        guard password != "" || sshKey != nil else {
            errorMessage = "認証情報が見つかりません。設定から認証情報を入力してください。"
            return
        }

        isLoading = true
        errorMessage = nil
        successMessage = nil
        progressMessage = "準備中..."
        progressLogs = ["準備中..."]

        Task {
            do {
                let changed = try await git.pull(
                    repoURL: repo.localURL,
                    branch: repo.branch,
                    username: username,
                    password: password,
                    sshPrivateKey: sshKey,
                    sshPassphrase: sshPassphrase,
                    progress: { [weak self] msg in
                        Task { @MainActor [weak self] in
                            self?.progressMessage = msg
                            self?.progressLogs.append(msg)
                        }
                    }
                )

                repo.lastPullDate = Date()
                if changed == 0 {
                    repo.addLog("Already up to date")
                    store.update(repo)
                    successMessage = "すでに最新の状態です"
                } else {
                    repo.addLog("Pull 完了（変更あり）")
                    store.update(repo)
                    successMessage = "最新の状態に更新しました"
                }
            } catch {
                repo.addLog(error.localizedDescription, isError: true)
                store.update(repo)
                errorMessage = error.localizedDescription
            }
            isLoading = false
            progressMessage = ""
            progressLogs = []
        }
    }

    // MARK: - Re-Clone

    /// 既存クローンを削除して再クローン
    func startReclone() {
        guard !isLoading else { return }

        let (username, password, sshKey, sshPassphrase) = authCredentials()
        guard password != "" || sshKey != nil else {
            errorMessage = "認証情報が見つかりません。設定から認証情報を入力してください。"
            return
        }

        isLoading = true
        errorMessage = nil
        successMessage = nil
        progressMessage = "再クローン準備中..."
        progressLogs = ["再クローン準備中..."]

        Task {
            // 既存ディレクトリを削除
            try? FileManager.default.removeItem(at: repo.localURL)
            repo.isCloned = false
            store.update(repo)

            do {
                try await git.clone(
                    from: repo.remoteURL,
                    to: repo.localURL,
                    branch: repo.branch,
                    username: username,
                    password: password,
                    sshPrivateKey: sshKey,
                    sshPassphrase: sshPassphrase,
                    progress: { [weak self] msg in
                        Task { @MainActor [weak self] in
                            self?.progressMessage = msg
                            self?.progressLogs.append(msg)
                        }
                    }
                )

                repo.isCloned = true
                repo.lastPullDate = Date()
                repo.addLog("再クローン完了")
                store.update(repo)
                successMessage = "再クローンが完了しました"
            } catch {
                repo.addLog(error.localizedDescription, isError: true)
                store.update(repo)
                errorMessage = error.localizedDescription
            }
            isLoading = false
            progressMessage = ""
            progressLogs = []
        }
    }

    // MARK: - Credential Update

    func updateCredentials(username: String, token: String) {
        repo.username = username
        store.update(repo)
        if !token.isEmpty {
            KeychainService.shared.save(token: token, for: repo.id)
        }
    }

    var hasCredential: Bool {
        KeychainService.shared.retrieve(for: repo.id) != nil
            || KeychainService.shared.retrieveSSHKey(for: repo.id) != nil
    }

    // MARK: - Private

    private func authCredentials() -> (username: String, password: String, sshKey: String?, sshPassphrase: String?) {
        if repo.authType == .sshKey {
            let sshKey = KeychainService.shared.retrieveSSHKey(for: repo.id)
            let passphrase = KeychainService.shared.retrievePassphrase(for: repo.id)
            return (repo.username, "", sshKey, passphrase)
        } else {
            let pat = KeychainService.shared.retrieve(for: repo.id) ?? ""
            return (repo.username, pat, nil, nil)
        }
    }
}
