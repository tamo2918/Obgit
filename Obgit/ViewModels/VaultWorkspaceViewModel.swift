import Foundation
import Combine
import UIKit

@MainActor
final class VaultWorkspaceViewModel: ObservableObject {
    @Published private(set) var repo: RepositoryModel
    @Published private(set) var fileTree: [VaultFileNode] = []
    @Published private(set) var selectedFileURL: URL?
    @Published private(set) var selectedMarkdownText = ""

    @Published var isPulling = false
    @Published var progressMessage = ""
    @Published var operationMessage: String?
    @Published var errorMessage: String?

    // MARK: - Edit state
    @Published var isEditing = false
    @Published var editedText = ""
    @Published var isCommitting = false
    @Published var showCommitDialog = false
    @Published var commitProgress = ""

    // MARK: - Commit History
    @Published private(set) var commitLog: [CommitEntry] = []
    @Published var showCommitHistory = false

    // MARK: - Branch Switch
    @Published private(set) var availableBranches: [String] = []
    @Published var showBranchSwitch = false
    @Published var isSwitchingBranch = false
    @Published var branchSwitchProgress = ""

    // MARK: - Merge Conflict Resolution
    @Published var showConflictResolution = false
    @Published private(set) var conflictFiles: [ConflictFile] = []
    @Published var isResolvingConflicts = false
    @Published var conflictResolutionProgress = ""

    private(set) var snapshotBeforeEdit = ""

    var isDirty: Bool { isEditing && editedText != snapshotBeforeEdit }

    private let store = RepositoryStore.shared
    private let git = GitService.shared

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tiff", "bmp"
    ]

    var selectedFileIsImage: Bool {
        guard let url = selectedFileURL else { return false }
        return Self.imageExtensions.contains(url.pathExtension.lowercased())
    }

    init(repo: RepositoryModel) {
        self.repo = repo
        reloadFileTree()
    }

    func reloadFileTree() {
        fileTree = VaultFileTreeBuilder.buildTree(at: repo.localURL)
        restoreOrSelectFirst()
    }

    // 選択を保持しながらファイルツリーを再構築する（pull後などで明示的に呼ぶ用）
    func reloadFileTreePreservingSelection(fallbackURL: URL?) {
        fileTree = VaultFileTreeBuilder.buildTree(at: repo.localURL)

        // pull 前の URL を優先して復元を試みる
        let candidates = [fallbackURL, selectedFileURL].compactMap { $0 }
        for url in candidates {
            if (try? url.checkResourceIsReachable()) == true {
                openFile(at: url)
                return
            }
        }

        // どちらも存在しなければ先頭ファイル
        if let firstMarkdown = VaultFileTreeBuilder.firstMarkdownFile(in: fileTree) {
            loadMarkdown(at: firstMarkdown)
        } else {
            selectedFileURL = nil
            selectedMarkdownText = ""
        }
    }

    // MARK: - Private

    private func restoreOrSelectFirst() {
        if let current = selectedFileURL,
           (try? current.checkResourceIsReachable()) == true {
            openFile(at: current)
            return
        }

        if let firstMarkdown = VaultFileTreeBuilder.firstMarkdownFile(in: fileTree) {
            loadMarkdown(at: firstMarkdown)
        } else {
            selectedFileURL = nil
            selectedMarkdownText = ""
        }
    }

    func select(_ node: VaultFileNode) {
        guard node.isViewable else { return }
        openFile(at: node.url)
    }

    func selectFile(at url: URL) {
        openFile(at: url)
    }

    // MARK: - Editing

    func beginEditing() {
        guard selectedFileURL != nil, !selectedFileIsImage else { return }
        snapshotBeforeEdit = selectedMarkdownText
        editedText = selectedMarkdownText
        isEditing = true
        errorMessage = nil
    }

    func cancelEditing() {
        isEditing = false
        editedText = ""
        snapshotBeforeEdit = ""
        errorMessage = nil
    }

    func commitAndPush(message: String, authorName: String, authorEmail: String) async {
        guard let fileURL = selectedFileURL else { return }

        let (username, password, sshKey, sshPassphrase) = authCredentials()
        guard password != "" || sshKey != nil else {
            errorMessage = "認証情報が見つかりません。再クローンして認証情報を保存してください。"
            return
        }

        isCommitting = true
        commitProgress = "ファイルを保存中..."
        errorMessage = nil

        // ファイルをディスクに書き込む
        do {
            try editedText.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            isCommitting = false
            errorMessage = "ファイルの保存に失敗しました: \(error.localizedDescription)"
            return
        }

        // Stage → Commit → Push
        do {
            try await git.stageCommitPush(
                repoURL: repo.localURL,
                branch: repo.branch,
                username: username,
                password: password,
                sshPrivateKey: sshKey,
                sshPassphrase: sshPassphrase,
                message: message,
                authorName: authorName,
                authorEmail: authorEmail,
                progress: { [weak self] msg in
                    Task { @MainActor [weak self] in
                        self?.commitProgress = msg
                    }
                }
            )

            // 成功
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            selectedMarkdownText = editedText
            snapshotBeforeEdit = editedText
            isCommitting = false
            showCommitDialog = false
            isEditing = false

            repo.addLog("コミット & プッシュ完了: \(message)")
            store.update(repo)
            reloadFromStore()
            operationMessage = "コミットしてプッシュしました"

        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            isCommitting = false
            errorMessage = error.localizedDescription
        }
    }

    // マークダウンと画像でルーティングする
    private func openFile(at url: URL) {
        if Self.imageExtensions.contains(url.pathExtension.lowercased()) {
            selectedFileURL = url
            selectedMarkdownText = ""
            errorMessage = nil
        } else {
            loadMarkdown(at: url)
        }
    }

    func pullLatest() {
        guard !isPulling, !isEditing else { return }

        let (username, password, sshKey, sshPassphrase) = authCredentials()
        guard password != "" || sshKey != nil else {
            errorMessage = "認証情報が見つかりません。再クローンして認証情報を保存してください。"
            return
        }

        isPulling = true
        progressMessage = "準備中..."
        operationMessage = nil
        errorMessage = nil

        // pull 開始前に選択ファイルを記録しておく（非同期処理後の復元用）
        let urlBeforePull = selectedFileURL

        Task {
            do {
                let changed = try await git.pull(
                    repoURL: repo.localURL,
                    branch: repo.branch,
                    username: username,
                    password: password,
                    sshPrivateKey: sshKey,
                    sshPassphrase: sshPassphrase,
                    progress: { [weak self] message in
                        Task { @MainActor [weak self] in
                            self?.progressMessage = message
                        }
                    }
                )

                repo.lastPullDate = Date()
                if changed == 0 {
                    repo.addLog("Already up to date")
                    operationMessage = "すでに最新です"
                } else {
                    repo.addLog("Pull 完了（変更あり）")
                    operationMessage = "最新の内容を取得しました"
                }
                store.update(repo)
                reloadFromStore()
                // pull 前の選択ファイルを優先して復元する
                reloadFileTreePreservingSelection(fallbackURL: urlBeforePull)
            } catch GitError.mergeConflicts(let files) {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                conflictFiles = files
                showConflictResolution = true
            } catch {
                errorMessage = error.localizedDescription
                repo.addLog(error.localizedDescription, isError: true)
                store.update(repo)
            }

            progressMessage = ""
            isPulling = false
        }
    }

    // MARK: - Commit Log

    func loadCommitLog() {
        Task {
            do {
                let entries = try await git.getCommitLog(repoURL: repo.localURL)
                commitLog = entries
            } catch {
                commitLog = []
            }
        }
    }

    // MARK: - Branch Switch

    func loadBranches() {
        Task {
            do {
                let branches = try await git.listBranches(repoURL: repo.localURL)
                availableBranches = branches
            } catch {
                availableBranches = []
            }
        }
    }

    func switchBranch(to newBranch: String) async {
        guard !isSwitchingBranch else { return }

        let (username, password, sshKey, sshPassphrase) = authCredentials()
        guard password != "" || sshKey != nil else {
            errorMessage = "認証情報が見つかりません。"
            return
        }

        isSwitchingBranch = true
        branchSwitchProgress = ""
        errorMessage = nil

        do {
            try await git.switchBranch(
                repoURL: repo.localURL,
                branch: newBranch,
                username: username,
                password: password,
                sshPrivateKey: sshKey,
                sshPassphrase: sshPassphrase,
                progress: { [weak self] msg in
                    Task { @MainActor [weak self] in
                        self?.branchSwitchProgress = msg
                    }
                }
            )

            // ブランチ名をモデルに反映
            var updated = repo
            updated.branch = newBranch
            updated.addLog("ブランチを切り替えました: \(newBranch)")
            store.update(updated)
            reloadFromStore()
            reloadFileTreePreservingSelection(fallbackURL: nil)

            showBranchSwitch = false
            operationMessage = "ブランチを「\(newBranch)」に切り替えました"

        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }

        isSwitchingBranch = false
        branchSwitchProgress = ""
    }

    // MARK: - Conflict Resolution

    func resolveConflictSection(fileID: UUID, sectionID: UUID, with lines: [String]) {
        guard let idx = conflictFiles.firstIndex(where: { $0.id == fileID }) else { return }
        conflictFiles[idx].resolve(sectionID: sectionID, with: lines)
    }

    func completeMerge(message: String, authorName: String, authorEmail: String) async {
        let (username, password, sshKey, sshPassphrase) = authCredentials()
        guard password != "" || sshKey != nil else {
            errorMessage = "認証情報が見つかりません。"
            return
        }

        isResolvingConflicts = true
        conflictResolutionProgress = "マージコミットを作成中..."
        errorMessage = nil

        do {
            try await git.completeMerge(
                repoURL: repo.localURL,
                branch: repo.branch,
                username: username,
                password: password,
                sshPrivateKey: sshKey,
                sshPassphrase: sshPassphrase,
                message: message,
                authorName: authorName,
                authorEmail: authorEmail,
                progress: { [weak self] msg in
                    Task { @MainActor [weak self] in
                        self?.conflictResolutionProgress = msg
                    }
                }
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showConflictResolution = false
            conflictFiles = []
            repo.addLog("マージコミット & プッシュ完了: \(message)")
            store.update(repo)
            reloadFromStore()
            reloadFileTreePreservingSelection(fallbackURL: selectedFileURL)
            operationMessage = "マージが完了しました"
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }

        isResolvingConflicts = false
        conflictResolutionProgress = ""
    }

    // MARK: - Auth Helpers

    /// 現在のリポジトリの認証情報を返す (username, password, sshKey, sshPassphrase)
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

    private func reloadFromStore() {
        guard let latest = store.repositories.first(where: { $0.id == repo.id }) else { return }
        repo = latest
    }

    // MARK: - WikiLink Navigation

    /// ノート名から vault 内のファイル URL を解決する（Obsidian WikiLink 解決ルール）
    ///
    /// 解決順序:
    /// 1. vault ルートからの相対パスとして探す（拡張子なし・.md・.markdown を試行）
    /// 2. 見つからなければファイルツリー全体からファイル名で検索（大文字小文字を無視）
    func findFile(named noteName: String) -> URL? {
        let name = noteName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        // 相対パスとして試みる
        for ext in ["", ".md", ".markdown"] {
            let url = repo.localURL.appendingPathComponent(name + ext)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        // ファイルツリー全体からファイル名（拡張子なし）で検索
        // パス区切りがある場合は末尾のコンポーネントだけで検索
        let fileName = name.split(separator: "/").last.map(String.init) ?? name
        return findInTree(fileTree, targetName: fileName)
    }

    private func findInTree(_ nodes: [VaultFileNode], targetName: String) -> URL? {
        let lowerTarget = (targetName as NSString).deletingPathExtension.lowercased()
        for node in nodes {
            if node.isDirectory {
                if let found = findInTree(node.children, targetName: targetName) {
                    return found
                }
            } else if node.isMarkdown {
                let nodeName = (node.name as NSString).deletingPathExtension.lowercased()
                if nodeName == lowerTarget {
                    return node.url
                }
            }
        }
        return nil
    }

    private func loadMarkdown(at url: URL) {
        selectedFileURL = url
        errorMessage = nil

        do {
            let text = try Self.loadText(from: url)
            selectedMarkdownText = text
        } catch {
            selectedMarkdownText = ""
            errorMessage = "ファイルを読み込めませんでした: \(url.lastPathComponent)"
        }
    }

    private static func loadText(from url: URL) throws -> String {
        let encodings: [String.Encoding] = [
            .utf8,
            .unicode,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .shiftJIS
        ]

        for encoding in encodings {
            if let text = try? String(contentsOf: url, encoding: encoding) {
                return text
            }
        }
        throw CocoaError(.fileReadCorruptFile)
    }
}
