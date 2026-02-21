import Foundation
import Combine

@MainActor
final class CloneRepositoryViewModel: ObservableObject {
    @Published var name = ""
    @Published var remoteURL = ""
    @Published var branch = "main"
    @Published var username = ""
    @Published var pat = ""
    @Published var sshPrivateKey = ""
    @Published var sshPassphrase = ""

    @Published var isCloning = false
    @Published var progressMessage = ""
    @Published var progressLogs: [String] = []
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let store = RepositoryStore.shared
    private let git = GitService.shared

    /// `git@...` または `ssh://...` 形式の SSH URL かどうか
    var isSSHURL: Bool {
        let url = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.hasPrefix("git@") || url.lowercased().hasPrefix("ssh://")
    }

    var isFormValid: Bool {
        let trimName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimURL = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimName.isEmpty, !trimURL.isEmpty, !trimBranch.isEmpty, !trimUsername.isEmpty else {
            return false
        }

        if isSSHURL {
            // SSH 認証: 秘密鍵が必要
            return !sshPrivateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            // HTTPS 認証: PAT が必要
            return !pat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func applyPreset(_ repo: RepositoryModel) {
        name = repo.name
        remoteURL = repo.remoteURL
        branch = repo.branch
        username = repo.username
        pat = ""
        sshPrivateKey = ""
        sshPassphrase = ""
        errorMessage = nil
        successMessage = nil
    }

    func startClone() async -> RepositoryModel? {
        guard !isCloning else { return nil }
        guard isFormValid else {
            errorMessage = "入力内容を確認してください。"
            return nil
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPAT = pat.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSSHKey = sshPrivateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassphrase = sshPassphrase.trimmingCharacters(in: .whitespacesAndNewlines)

        // HTTPS URL の場合のみ URL 形式を検証（SSH SCP 形式は URL(string:) が失敗するため除外）
        if !isSSHURL {
            guard URL(string: trimmedURL) != nil else {
                errorMessage = "リモート URL の形式が正しくありません。"
                return nil
            }
        }

        let previewRepo = RepositoryModel(
            name: trimmedName,
            remoteURL: trimmedURL,
            branch: trimmedBranch,
            username: trimmedUsername
        )

        if store.repositories.contains(where: { $0.localDirName == previewRepo.localDirName && $0.isCloned }) {
            errorMessage = "同名の保存先フォルダが存在します。表示名を変更してください。"
            return nil
        }

        isCloning = true
        errorMessage = nil
        successMessage = nil
        progressMessage = "リモートに接続中..."
        progressLogs = ["リモートに接続中..."]

        // UI の更新を先に描画させてからクローン処理に入る
        await Task.yield()

        do {
            try await git.clone(
                from: trimmedURL,
                to: previewRepo.localURL,
                branch: trimmedBranch,
                username: trimmedUsername,
                password: isSSHURL ? "" : trimmedPAT,
                sshPrivateKey: isSSHURL ? trimmedSSHKey : nil,
                sshPassphrase: isSSHURL ? (trimmedPassphrase.isEmpty ? nil : trimmedPassphrase) : nil,
                progress: { [weak self] message in
                    Task { @MainActor [weak self] in
                        self?.progressMessage = message
                        self?.progressLogs.append(message)
                        self?.truncateProgressLogs()
                    }
                }
            )

            var savedRepo = previewRepo
            savedRepo.isCloned = true
            savedRepo.lastPullDate = Date()
            savedRepo.addLog("初回クローン完了")
            store.add(savedRepo)

            // Keychain に認証情報を保存
            if isSSHURL {
                KeychainService.shared.saveSSHKey(trimmedSSHKey, for: savedRepo.id)
                if !trimmedPassphrase.isEmpty {
                    KeychainService.shared.savePassphrase(trimmedPassphrase, for: savedRepo.id)
                }
            } else {
                KeychainService.shared.save(token: trimmedPAT, for: savedRepo.id)
            }

            successMessage = "クローンが完了しました"
            progressMessage = ""
            progressLogs = []
            isCloning = false
            return savedRepo
        } catch {
            errorMessage = error.localizedDescription
            progressMessage = ""
            progressLogs = []
            isCloning = false
            return nil
        }
    }

    private func truncateProgressLogs() {
        if progressLogs.count > 12 {
            progressLogs = Array(progressLogs.suffix(12))
        }
    }
}
