import Foundation
import SwiftGit2
import Clibgit2

// MARK: - Credential Context (C callback 用)

/// libgit2 の C 認証コールバックに渡すペイロード
/// Unmanaged<T> パターンで C ポインタとして安全に渡すため class で定義
private final class CredentialContext: @unchecked Sendable {
    let username: String
    let password: String        // PAT (HTTPS) または空文字 (SSH)
    let sshPrivateKey: String?  // nil = HTTPS 認証
    let sshPassphrase: String?  // nil = パスフレーズなし

    var isSSH: Bool { sshPrivateKey != nil }

    /// HTTPS (PAT) 認証用
    nonisolated init(username: String, password: String) {
        self.username = username
        self.password = password
        self.sshPrivateKey = nil
        self.sshPassphrase = nil
    }

    /// SSH 鍵認証用
    nonisolated init(username: String, sshPrivateKey: String, sshPassphrase: String?) {
        self.username = username
        self.password = ""
        self.sshPrivateKey = sshPrivateKey
        self.sshPassphrase = sshPassphrase
    }
}

// MARK: - C Credential Callback
//
// libgit2 の credential callback は C 関数ポインタ型を要求する。
// @convention(c) クロージャとして定義し、外部変数をキャプチャしない。
//
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor の環境では、
// ファイルスコープの let は暗黙的に MainActor-isolated になる。
// nonisolated(unsafe) を付けることで isolation を外す。

nonisolated(unsafe) private let gitCredentialCallback: @convention(c) (
    UnsafeMutablePointer<UnsafeMutablePointer<git_cred>?>?,  // output: credential
    UnsafePointer<CChar>?,                                    // url
    UnsafePointer<CChar>?,                                    // username from url
    UInt32,                                                   // allowed credential types
    UnsafeMutableRawPointer?                                  // payload
) -> Int32 = { credOut, _, _, allowedTypes, payload in
    guard let payload = payload else { return -1 }
    let ctx = Unmanaged<CredentialContext>.fromOpaque(payload).takeUnretainedValue()

    if ctx.isSSH {
        // USERNAME (32): libgit2 が最初にユーザー名だけを要求する
        if allowedTypes & 32 != 0 {
            return ctx.username.withCString { userPtr in
                git_cred_username_new(credOut, userPtr)
            }
        }
        // SSH_MEMORY (64): メモリ上の秘密鍵で認証
        if allowedTypes & 64 != 0, let privateKey = ctx.sshPrivateKey {
            return ctx.username.withCString { userPtr in
                privateKey.withCString { keyPtr in
                    if let passphrase = ctx.sshPassphrase, !passphrase.isEmpty {
                        return passphrase.withCString { passPtr in
                            git_cred_ssh_key_memory_new(credOut, userPtr, nil, keyPtr, passPtr)
                        }
                    } else {
                        return git_cred_ssh_key_memory_new(credOut, userPtr, nil, keyPtr, nil)
                    }
                }
            }
        }
    } else {
        // USERPASS_PLAINTEXT (1): HTTPS + PAT
        if allowedTypes & 1 != 0 {
            return ctx.username.withCString { user in
                ctx.password.withCString { pass in
                    git_cred_userpass_plaintext_new(credOut, user, pass)
                }
            }
        }
    }
    return -1
}

// MARK: - GitService

/// Git 操作（clone / pull / commit / push / log / branch）を担当するサービス
///
/// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor の設定があるため、
/// blocking な Git 操作は DispatchQueue.global で明示的にバックグラウンド実行する。
nonisolated final class GitService: Sendable {

    static let shared = GitService()
    private nonisolated init() {}

    // MARK: - Clone

    /// リポジトリをクローンする
    ///
    /// - Parameters:
    ///   - remoteURLString: リモート URL 文字列（HTTPS / SSH SCP 形式どちらも可）
    ///   - localURL: クローン先のローカルパス
    ///   - branch: チェックアウトするブランチ名
    ///   - username: 認証ユーザー名
    ///   - password: Personal Access Token（HTTPS の場合）
    ///   - sshPrivateKey: SSH 秘密鍵の PEM 文字列（SSH の場合）
    ///   - sshPassphrase: SSH 秘密鍵のパスフレーズ（不要な場合は nil）
    ///   - progress: 進捗コールバック（バックグラウンドスレッドから呼ばれる）
    nonisolated func clone(
        from remoteURLString: String,
        to localURL: URL,
        branch: String,
        username: String,
        password: String,
        sshPrivateKey: String? = nil,
        sshPassphrase: String? = nil,
        progress: @escaping @Sendable (String) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.prepareDirectory(at: localURL)
                    progress("リモートに接続中...")

                    if let sshPrivateKey = sshPrivateKey {
                        // SSH clone: Clibgit2 C API を使用
                        try self.performSSHClone(
                            remoteURL: remoteURLString,
                            localURL: localURL,
                            branch: branch,
                            username: username,
                            sshPrivateKey: sshPrivateKey,
                            sshPassphrase: sshPassphrase,
                            progress: progress
                        )
                    } else {
                        // HTTPS clone: SwiftGit2 を使用
                        guard let remote = URL(string: remoteURLString) else {
                            throw GitError.cloneFailed("URL の形式が正しくありません")
                        }
                        let credentials = Credentials.plaintext(username: username, password: password)
                        let result = Repository.clone(
                            from: remote,
                            to: localURL,
                            localClone: false,
                            bare: false,
                            credentials: credentials,
                            checkoutStrategy: .Safe,
                            checkoutProgress: { _, completed, total in
                                let pct = total > 0 ? Int(Double(completed) / Double(total) * 100) : 0
                                progress("チェックアウト中... \(pct)%")
                            }
                        )
                        switch result {
                        case .success:
                            break
                        case .failure(let error):
                            try? FileManager.default.removeItem(at: localURL)
                            throw self.mapCloneError(error)
                        }
                    }

                    progress("クローン完了")
                    continuation.resume()
                } catch {
                    try? FileManager.default.removeItem(at: localURL)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Pull

    /// pull (fetch + hard reset) を実行する
    ///
    /// - Returns: 0 = already up to date, 1 = 変更あり
    nonisolated func pull(
        repoURL: URL,
        branch: String,
        username: String,
        password: String,
        sshPrivateKey: String? = nil,
        sshPassphrase: String? = nil,
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> Int {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let changed = try self.performPull(
                        repoURL: repoURL,
                        branch: branch,
                        username: username,
                        password: password,
                        sshPrivateKey: sshPrivateKey,
                        sshPassphrase: sshPassphrase,
                        progress: progress
                    )
                    continuation.resume(returning: changed)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Stage, Commit, and Push

    /// ファイルを全てステージして、コミットし、リモートにプッシュする
    nonisolated func stageCommitPush(
        repoURL: URL,
        branch: String,
        username: String,
        password: String,
        sshPrivateKey: String? = nil,
        sshPassphrase: String? = nil,
        message: String,
        authorName: String,
        authorEmail: String,
        progress: @escaping @Sendable (String) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.performStageAndCommit(
                        repoURL: repoURL,
                        message: message,
                        authorName: authorName,
                        authorEmail: authorEmail,
                        progress: progress
                    )
                    try self.performPush(
                        repoURL: repoURL,
                        branch: branch,
                        username: username,
                        password: password,
                        sshPrivateKey: sshPrivateKey,
                        sshPassphrase: sshPassphrase,
                        progress: progress
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Commit Log

    /// 最新のコミット履歴を取得する
    ///
    /// - Parameters:
    ///   - repoURL: リポジトリのローカル URL
    ///   - limit: 取得する最大件数（デフォルト 50）
    /// - Returns: CommitEntry の配列（新しい順）
    nonisolated func getCommitLog(repoURL: URL, limit: Int = 50) async throws -> [CommitEntry] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let entries = try self.performGetCommitLog(repoURL: repoURL, limit: limit)
                    continuation.resume(returning: entries)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Branch List

    /// リモートブランチ一覧を取得する
    ///
    /// origin/ プレフィックスを除いたブランチ名の配列を返す。
    nonisolated func listBranches(repoURL: URL) async throws -> [String] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let branches = try self.performListBranches(repoURL: repoURL)
                    continuation.resume(returning: branches)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Branch Switch

    /// ブランチを切り替える（fetch → checkout force → HEAD 更新）
    ///
    /// 処理フロー:
    ///   1. origin をフェッチ（認証付き）
    ///   2. refs/remotes/origin/<branch> から OID を取得
    ///   3. ローカルブランチを作成／更新
    ///   4. git_checkout_tree(GIT_CHECKOUT_FORCE) でワーキングディレクトリを同期
    ///   5. git_repository_set_head で HEAD を新しいブランチに向ける
    nonisolated func switchBranch(
        repoURL: URL,
        branch: String,
        username: String,
        password: String,
        sshPrivateKey: String? = nil,
        sshPassphrase: String? = nil,
        progress: @escaping @Sendable (String) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.performSwitchBranch(
                        repoURL: repoURL,
                        branch: branch,
                        username: username,
                        password: password,
                        sshPrivateKey: sshPrivateKey,
                        sshPassphrase: sshPassphrase,
                        progress: progress
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Stage Resolved File

    /// コンフリクト解決済みファイルをステージングする
    nonisolated func stageResolvedFile(
        repoURL: URL,
        conflictFile: ConflictFile
    ) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.performStageResolvedFile(repoURL: repoURL, conflictFile: conflictFile)
                    c.resume()
                } catch {
                    c.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Complete Merge (commit + push)

    /// マージコミットを作成してリモートにプッシュする
    nonisolated func completeMerge(
        repoURL: URL,
        branch: String,
        username: String,
        password: String,
        sshPrivateKey: String? = nil,
        sshPassphrase: String? = nil,
        message: String,
        authorName: String,
        authorEmail: String,
        progress: @escaping @Sendable (String) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.performCompleteMergeCommit(
                        repoURL: repoURL,
                        message: message,
                        authorName: authorName,
                        authorEmail: authorEmail,
                        progress: progress
                    )
                    try self.performPush(
                        repoURL: repoURL,
                        branch: branch,
                        username: username,
                        password: password,
                        sshPrivateKey: sshPrivateKey,
                        sshPassphrase: sshPassphrase,
                        progress: progress
                    )
                    c.resume()
                } catch {
                    c.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Repository Validation

    nonisolated func isRepositoryValid(at url: URL) -> Bool {
        switch Repository.at(url) {
        case .success: return true
        case .failure: return false
        }
    }

    // MARK: - Private: SSH Clone (Clibgit2 C API)

    private nonisolated func performSSHClone(
        remoteURL: String,
        localURL: URL,
        branch: String,
        username: String,
        sshPrivateKey: String,
        sshPassphrase: String?,
        progress: (String) -> Void
    ) throws {
        let credCtx = CredentialContext(
            username: username,
            sshPrivateKey: sshPrivateKey,
            sshPassphrase: sshPassphrase
        )
        let unmanagedCtx = Unmanaged.passRetained(credCtx)
        defer { unmanagedCtx.release() }

        var cloneOpts = git_clone_options()
        git_clone_options_init(&cloneOpts, 1)
        cloneOpts.fetch_opts.callbacks.credentials = gitCredentialCallback
        cloneOpts.fetch_opts.callbacks.payload = unmanagedCtx.toOpaque()

        progress("SSH クローン中...")

        var outRepo: OpaquePointer?
        defer { if let outRepo { git_repository_free(outRepo) } }
        let result = remoteURL.withCString { urlPtr in
            localURL.path.withCString { pathPtr in
                branch.withCString { branchPtr in
                    cloneOpts.checkout_branch = branchPtr
                    return git_clone(&outRepo, urlPtr, pathPtr, &cloneOpts)
                }
            }
        }

        if result != 0 {
            let msg = latestLibgit2ErrorMessage()
            if result == -16 { throw GitError.authenticationFailed }
            throw GitError.cloneFailed(msg)
        }
    }

    // MARK: - Private: Pull Implementation (libgit2 C API)

    private nonisolated func performPull(
        repoURL: URL,
        branch: String,
        username: String,
        password: String,
        sshPrivateKey: String?,
        sshPassphrase: String?,
        progress: (String) -> Void
    ) throws -> Int {
        // Step 1: リポジトリを開く
        let repo: Repository
        switch Repository.at(repoURL) {
        case .success(let r): repo = r
        case .failure: throw GitError.repositoryNotFound
        }

        progress("リモートを確認中...")

        // Step 2: CredentialContext を Unmanaged で保持
        let credCtx: CredentialContext
        if let sshKey = sshPrivateKey {
            credCtx = CredentialContext(username: username, sshPrivateKey: sshKey, sshPassphrase: sshPassphrase)
        } else {
            credCtx = CredentialContext(username: username, password: password)
        }
        let unmanagedCtx = Unmanaged.passRetained(credCtx)
        defer { unmanagedCtx.release() }

        // Step 3: origin リモートを取得
        var rawRemote: OpaquePointer?
        guard git_remote_lookup(&rawRemote, repo.pointer, "origin") == 0,
              let rawRemote = rawRemote else {
            throw GitError.remoteNotFound
        }
        defer { git_remote_free(rawRemote) }

        // Step 4: fetch オプションを設定して認証付きフェッチを実行
        var fetchOpts = git_fetch_options()
        git_fetch_init_options(&fetchOpts, 1)
        fetchOpts.callbacks.credentials = gitCredentialCallback
        fetchOpts.callbacks.payload = unmanagedCtx.toOpaque()

        progress("フェッチ中...")

        let fetchResult = git_remote_fetch(rawRemote, nil, &fetchOpts, "pull")
        if fetchResult != 0 {
            let msg = latestLibgit2ErrorMessage()
            if fetchResult == -16 { throw GitError.authenticationFailed }
            throw GitError.fetchFailed(msg)
        }

        progress("変更を適用中...")

        // Step 5: refs/remotes/origin/<branch> の OID を取得
        let remoteRefName = "refs/remotes/origin/\(branch)"
        var remoteRef: OpaquePointer?
        guard git_reference_lookup(&remoteRef, repo.pointer, remoteRefName) == 0,
              let remoteRef = remoteRef else {
            throw GitError.branchNotFound(branch)
        }
        defer { git_reference_free(remoteRef) }

        var resolvedRef: OpaquePointer?
        guard git_reference_resolve(&resolvedRef, remoteRef) == 0,
              let resolvedRef = resolvedRef else {
            throw GitError.branchNotFound(branch)
        }
        defer { git_reference_free(resolvedRef) }

        guard let targetOID = git_reference_target(resolvedRef) else {
            throw GitError.unknown("リモートブランチの OID を取得できませんでした")
        }

        // Step 6: Annotated commit 取得
        var theirAnnotated: OpaquePointer?
        guard git_annotated_commit_lookup(&theirAnnotated, repo.pointer, targetOID) == 0,
              let theirAnnotated = theirAnnotated else {
            throw GitError.fetchFailed("annotated commit 取得失敗")
        }
        defer { git_annotated_commit_free(theirAnnotated) }

        // Step 7: Merge analysis
        var analysisResult = git_merge_analysis_t(rawValue: 0)
        var preference = git_merge_preference_t(rawValue: 0)
        var headsArray: [OpaquePointer?] = [theirAnnotated]
        let ar = headsArray.withUnsafeMutableBufferPointer { buf in
            git_merge_analysis(&analysisResult, &preference, repo.pointer,
                               buf.baseAddress, 1)
        }
        guard ar == 0 else { throw GitError.fetchFailed("merge analysis 失敗") }

        // GIT_MERGE_ANALYSIS_UP_TO_DATE = 2, FASTFORWARD = 4, NORMAL = 1
        let upToDate    = (analysisResult.rawValue & 2) != 0
        let fastForward = (analysisResult.rawValue & 4) != 0
        let normal      = (analysisResult.rawValue & 1) != 0

        if upToDate {
            return 0
        } else if fastForward {
            try performHardReset(repo: repo, targetOID: targetOID)
            return 1
        } else if normal {
            progress("マージ中...")
            return try performMergePull(
                repo: repo,
                theirAnnotated: theirAnnotated,
                repoURL: repoURL,
                progress: progress
            )
        } else {
            // UNBORN など
            try performHardReset(repo: repo, targetOID: targetOID)
            return 1
        }
    }

    // MARK: - Private: Hard Reset (既存ロジックを抽出)

    private nonisolated func performHardReset(
        repo: Repository,
        targetOID: UnsafePointer<git_oid>
    ) throws {
        var targetObject: OpaquePointer?
        guard git_object_lookup(&targetObject, repo.pointer, targetOID, GIT_OBJECT_COMMIT) == 0,
              let targetObject = targetObject else {
            throw GitError.unknown("コミットオブジェクト取得失敗")
        }
        defer { git_object_free(targetObject) }
        guard git_reset(repo.pointer, targetObject, GIT_RESET_HARD, nil) == 0 else {
            throw GitError.resetFailed(latestLibgit2ErrorMessage())
        }
    }

    // MARK: - Private: Merge Pull

    private nonisolated func performMergePull(
        repo: Repository,
        theirAnnotated: OpaquePointer,
        repoURL: URL,
        progress: (String) -> Void
    ) throws -> Int {
        var mergeOpts = git_merge_options()
        git_merge_options_init(&mergeOpts, 1)
        var checkoutOpts = git_checkout_options()
        git_checkout_options_init(&checkoutOpts, 1)
        // GIT_CHECKOUT_FORCE(2) | GIT_CHECKOUT_ALLOW_CONFLICTS(16) = 18
        checkoutOpts.checkout_strategy = GIT_CHECKOUT_FORCE.rawValue | 16

        var headsArray: [OpaquePointer?] = [theirAnnotated]
        let mr = headsArray.withUnsafeMutableBufferPointer { buf in
            git_merge(repo.pointer, buf.baseAddress, 1, &mergeOpts, &checkoutOpts)
        }
        if mr != 0 { throw GitError.mergeFailed(latestLibgit2ErrorMessage()) }

        // index でコンフリクト確認
        var index: OpaquePointer?
        guard git_repository_index(&index, repo.pointer) == 0, let index = index else {
            throw GitError.mergeFailed("インデックス取得失敗")
        }
        defer { git_index_free(index) }

        if git_index_has_conflicts(index) != 0 {
            let files = try collectConflictFiles(index: index, repoURL: repoURL)
            throw GitError.mergeConflicts(files)
        }

        // コンフリクトなし → 自動マージコミット
        progress("マージコミット作成中...")
        let mergeMsgURL = repoURL.appendingPathComponent(".git/MERGE_MSG")
        let msg = (try? String(contentsOf: mergeMsgURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Merge remote-tracking branch"
        try performCompleteMergeCommit(
            repoURL: repoURL, message: msg,
            authorName: "Obgit", authorEmail: "obgit@local",
            progress: { _ in }
        )
        return 1
    }

    // MARK: - Private: Collect Conflict Files

    private nonisolated func collectConflictFiles(
        index: OpaquePointer,
        repoURL: URL
    ) throws -> [ConflictFile] {
        var iter: OpaquePointer?
        guard git_index_conflict_iterator_new(&iter, index) == 0, let iter = iter else {
            throw GitError.mergeFailed("conflict iterator 作成失敗")
        }
        defer { git_index_conflict_iterator_free(iter) }

        var paths: [String] = []
        var ancestor: UnsafePointer<git_index_entry>? = nil
        var ours: UnsafePointer<git_index_entry>? = nil
        var theirs: UnsafePointer<git_index_entry>? = nil
        let GIT_ITEROVER: Int32 = -31

        while true {
            let ret = git_index_conflict_next(&ancestor, &ours, &theirs, iter)
            if ret == GIT_ITEROVER { break }
            guard ret == 0 else { break }
            let pathPtr = ours?.pointee.path ?? theirs?.pointee.path ?? ancestor?.pointee.path
            if let p = pathPtr {
                let s = String(cString: p)
                if !paths.contains(s) { paths.append(s) }
            }
        }

        // ワーキングディレクトリにコンフリクトマーカーを書き出す
        git_index_write(index)

        return paths.compactMap { path in
            ConflictFile.parse(
                relativePath: path,
                absoluteURL: repoURL.appendingPathComponent(path)
            )
        }
    }

    // MARK: - Private: Complete Merge Commit

    private nonisolated func performCompleteMergeCommit(
        repoURL: URL,
        message: String,
        authorName: String,
        authorEmail: String,
        progress: (String) -> Void
    ) throws {
        let repo: Repository
        switch Repository.at(repoURL) {
        case .success(let r): repo = r
        case .failure: throw GitError.repositoryNotFound
        }

        // index を書き込んでツリーを得る
        var index: OpaquePointer?
        guard git_repository_index(&index, repo.pointer) == 0, let index = index else {
            throw GitError.conflictResolutionFailed("インデックス取得失敗")
        }
        defer { git_index_free(index) }

        var treeOID = git_oid()
        guard git_index_write_tree(&treeOID, index) == 0 else {
            throw GitError.conflictResolutionFailed("ツリー書き込み失敗: \(latestLibgit2ErrorMessage())")
        }
        var treePtr: OpaquePointer?
        guard git_tree_lookup(&treePtr, repo.pointer, &treeOID) == 0, let treePtr = treePtr else {
            throw GitError.conflictResolutionFailed("ツリーオブジェクト取得失敗")
        }
        defer { git_tree_free(treePtr) }

        // シグネチャ作成
        var sig: UnsafeMutablePointer<git_signature>?
        let sigResult = authorName.withCString { namePtr in
            authorEmail.withCString { emailPtr in
                git_signature_now(&sig, namePtr, emailPtr)
            }
        }
        guard sigResult == 0, let sig = sig else {
            throw GitError.conflictResolutionFailed("署名作成失敗")
        }
        defer { git_signature_free(sig) }

        // parent 1: HEAD コミット
        var headOID = git_oid()
        guard git_reference_name_to_id(&headOID, repo.pointer, "HEAD") == 0 else {
            throw GitError.conflictResolutionFailed("HEAD 解決失敗")
        }
        var headCommit: OpaquePointer?
        guard git_commit_lookup(&headCommit, repo.pointer, &headOID) == 0,
              let headCommit = headCommit else {
            throw GitError.conflictResolutionFailed("HEAD コミット取得失敗")
        }
        defer { git_commit_free(headCommit) }

        // parent 2: MERGE_HEAD
        let mergeHeadURL = repoURL.appendingPathComponent(".git/MERGE_HEAD")
        guard let rawMergeHead = try? String(contentsOf: mergeHeadURL, encoding: .utf8) else {
            throw GitError.noMergeInProgress
        }
        let mergeHeadStr = rawMergeHead.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mergeHeadStr.isEmpty else {
            throw GitError.noMergeInProgress
        }
        var mergeHeadOID = git_oid()
        guard mergeHeadStr.withCString({ git_oid_fromstr(&mergeHeadOID, $0) }) == 0 else {
            throw GitError.conflictResolutionFailed("MERGE_HEAD OID 解析失敗")
        }
        var mergeHeadCommit: OpaquePointer?
        guard git_commit_lookup(&mergeHeadCommit, repo.pointer, &mergeHeadOID) == 0,
              let mergeHeadCommit = mergeHeadCommit else {
            throw GitError.conflictResolutionFailed("MERGE_HEAD コミット取得失敗")
        }
        defer { git_commit_free(mergeHeadCommit) }

        progress("マージコミット作成中...")

        // 2親コミット作成
        var commitOID = git_oid()
        var parents: [OpaquePointer?] = [headCommit, mergeHeadCommit]
        let commitResult = parents.withUnsafeMutableBufferPointer { buf in
            message.withCString { msgPtr in
                git_commit_create(
                    &commitOID, repo.pointer, "HEAD",
                    sig, sig, nil, msgPtr, treePtr, 2, buf.baseAddress
                )
            }
        }
        if commitResult != 0 {
            throw GitError.conflictResolutionFailed("コミット作成失敗: \(latestLibgit2ErrorMessage())")
        }

        // MERGE_HEAD / MERGE_MSG などを削除
        git_repository_state_cleanup(repo.pointer)
        progress("マージコミット完了")
    }

    // MARK: - Private: Stage Resolved File

    private nonisolated func performStageResolvedFile(
        repoURL: URL,
        conflictFile: ConflictFile
    ) throws {
        // 解決済みコンテンツをディスクに書き込む
        let content = conflictFile.resolvedContent()
        try content.write(to: conflictFile.absoluteURL, atomically: true, encoding: .utf8)

        let repo: Repository
        switch Repository.at(repoURL) {
        case .success(let r): repo = r
        case .failure: throw GitError.repositoryNotFound
        }

        var index: OpaquePointer?
        guard git_repository_index(&index, repo.pointer) == 0, let index = index else {
            throw GitError.conflictResolutionFailed("インデックス取得失敗")
        }
        defer { git_index_free(index) }

        // コンフリクトエントリを削除してから通常ステージング
        conflictFile.relativePath.withCString { pathPtr in
            git_index_conflict_remove(index, pathPtr)
            git_index_add_bypath(index, pathPtr)
        }
        if git_index_write(index) != 0 {
            throw GitError.conflictResolutionFailed("インデックス書き込み失敗: \(latestLibgit2ErrorMessage())")
        }
    }

    // MARK: - Private: Stage and Commit Implementation (libgit2 C API)

    private nonisolated func performStageAndCommit(
        repoURL: URL,
        message: String,
        authorName: String,
        authorEmail: String,
        progress: (String) -> Void
    ) throws {
        progress("ステージング中...")

        let repo: Repository
        switch Repository.at(repoURL) {
        case .success(let r): repo = r
        case .failure: throw GitError.repositoryNotFound
        }

        var index: OpaquePointer?
        guard git_repository_index(&index, repo.pointer) == 0,
              let index = index else {
            throw GitError.stagingFailed("インデックスの取得に失敗しました")
        }
        defer { git_index_free(index) }

        let addResult = git_index_add_all(index, nil, 0, nil, nil)
        if addResult != 0 { throw GitError.stagingFailed(latestLibgit2ErrorMessage()) }

        let updateResult = git_index_update_all(index, nil, nil, nil)
        if updateResult != 0 { throw GitError.stagingFailed(latestLibgit2ErrorMessage()) }

        if git_index_write(index) != 0 { throw GitError.stagingFailed(latestLibgit2ErrorMessage()) }

        var treeOID = git_oid()
        if git_index_write_tree(&treeOID, index) != 0 {
            throw GitError.commitFailed("ツリーの書き込みに失敗しました: \(latestLibgit2ErrorMessage())")
        }

        var treePtr: OpaquePointer?
        guard git_tree_lookup(&treePtr, repo.pointer, &treeOID) == 0,
              let treePtr = treePtr else {
            throw GitError.commitFailed("ツリーオブジェクトの取得に失敗しました")
        }
        defer { git_tree_free(treePtr) }

        progress("コミット中...")

        var sig: UnsafeMutablePointer<git_signature>?
        let sigResult = authorName.withCString { namePtr in
            authorEmail.withCString { emailPtr in
                git_signature_now(&sig, namePtr, emailPtr)
            }
        }
        guard sigResult == 0, let sig = sig else {
            throw GitError.commitFailed("署名の作成に失敗しました")
        }
        defer { git_signature_free(sig) }

        var headOID = git_oid()
        var parentCommit: OpaquePointer?
        let hasParent = git_reference_name_to_id(&headOID, repo.pointer, "HEAD") == 0
            && git_commit_lookup(&parentCommit, repo.pointer, &headOID) == 0
        defer { if let pc = parentCommit { git_commit_free(pc) } }

        var commitOID = git_oid()
        let commitResult: Int32
        if hasParent, let parent = parentCommit {
            var parents: [OpaquePointer?] = [parent]
            commitResult = parents.withUnsafeMutableBufferPointer { buf in
                message.withCString { msgPtr in
                    git_commit_create(
                        &commitOID, repo.pointer, "HEAD",
                        sig, sig, nil, msgPtr, treePtr, 1, buf.baseAddress
                    )
                }
            }
        } else {
            commitResult = message.withCString { msgPtr in
                git_commit_create(
                    &commitOID, repo.pointer, "HEAD",
                    sig, sig, nil, msgPtr, treePtr, 0, nil
                )
            }
        }

        if commitResult != 0 { throw GitError.commitFailed(latestLibgit2ErrorMessage()) }
        progress("コミット完了")
    }

    // MARK: - Private: Push Implementation (libgit2 C API)

    private nonisolated func performPush(
        repoURL: URL,
        branch: String,
        username: String,
        password: String,
        sshPrivateKey: String?,
        sshPassphrase: String?,
        progress: (String) -> Void
    ) throws {
        progress("プッシュ中...")

        let repo: Repository
        switch Repository.at(repoURL) {
        case .success(let r): repo = r
        case .failure: throw GitError.repositoryNotFound
        }

        var rawRemote: OpaquePointer?
        guard git_remote_lookup(&rawRemote, repo.pointer, "origin") == 0,
              let rawRemote = rawRemote else {
            throw GitError.remoteNotFound
        }
        defer { git_remote_free(rawRemote) }

        let credCtx: CredentialContext
        if let sshKey = sshPrivateKey {
            credCtx = CredentialContext(username: username, sshPrivateKey: sshKey, sshPassphrase: sshPassphrase)
        } else {
            credCtx = CredentialContext(username: username, password: password)
        }
        let unmanagedCtx = Unmanaged.passRetained(credCtx)
        defer { unmanagedCtx.release() }

        var pushOpts = git_push_options()
        git_push_options_init(&pushOpts, 1)
        pushOpts.callbacks.credentials = gitCredentialCallback
        pushOpts.callbacks.payload = unmanagedCtx.toOpaque()

        let refspecStr = "refs/heads/\(branch):refs/heads/\(branch)"
        guard let refspecCStr = strdup(refspecStr) else {
            throw GitError.pushFailed("メモリ確保に失敗しました")
        }
        defer { free(refspecCStr) }

        var refspecPtr: UnsafeMutablePointer<CChar>? = refspecCStr
        let pushResult = withUnsafeMutablePointer(to: &refspecPtr) { ptrToPtr in
            var strarray = git_strarray(strings: ptrToPtr, count: 1)
            return git_remote_push(rawRemote, &strarray, &pushOpts)
        }

        if pushResult != 0 {
            let msg = latestLibgit2ErrorMessage()
            if pushResult == -16 { throw GitError.authenticationFailed }
            let lower = msg.lowercased()
            if lower.contains("non-fast-forward") || lower.contains("rejected") {
                throw GitError.pushRejected(msg)
            }
            throw GitError.pushFailed(humanReadablePushError(msg))
        }

        progress("プッシュ完了")
    }

    // MARK: - Private: Commit Log (libgit2 C API)

    private nonisolated func performGetCommitLog(repoURL: URL, limit: Int) throws -> [CommitEntry] {
        let repo: Repository
        switch Repository.at(repoURL) {
        case .success(let r): repo = r
        case .failure: throw GitError.repositoryNotFound
        }

        var walker: OpaquePointer?
        guard git_revwalk_new(&walker, repo.pointer) == 0, let walker = walker else {
            throw GitError.commitLogFailed("revwalk の初期化に失敗しました")
        }
        defer { git_revwalk_free(walker) }

        // GIT_SORT_TIME = 2 (1 << 1)
        git_revwalk_sorting(walker, 2)

        // 空リポジトリ（コミットなし）では push_head が失敗する → 空配列を返す
        if git_revwalk_push_head(walker) != 0 {
            return []
        }

        var entries: [CommitEntry] = []
        var oid = git_oid()

        while entries.count < limit && git_revwalk_next(&oid, walker) == 0 {
            var commitPtr: OpaquePointer?
            guard git_commit_lookup(&commitPtr, repo.pointer, &oid) == 0,
                  let commitPtr = commitPtr else { continue }
            defer { git_commit_free(commitPtr) }

            // 短縮ハッシュ (7文字)
            var hashBuf = [CChar](repeating: 0, count: 41)
            git_oid_tostr(&hashBuf, 41, &oid)
            let shortHash = String(String(cString: hashBuf).prefix(7))

            // 作者名
            let authorName: String
            if let sig = git_commit_author(commitPtr), let namePtr = sig.pointee.name {
                authorName = String(cString: namePtr)
            } else {
                authorName = "Unknown"
            }

            // コミット日時
            let timestamp = git_commit_time(commitPtr)
            let date = Date(timeIntervalSince1970: Double(timestamp))

            // コミットメッセージの先頭行
            let subject: String
            if let msgPtr = git_commit_message(commitPtr) {
                let fullMsg = String(cString: msgPtr)
                subject = (fullMsg.components(separatedBy: "\n").first ?? fullMsg)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                subject = ""
            }

            entries.append(CommitEntry(
                shortHash: shortHash,
                authorName: authorName,
                date: date,
                subject: subject
            ))
        }

        return entries
    }

    // MARK: - Private: Branch List (libgit2 C API)

    private nonisolated func performListBranches(repoURL: URL) throws -> [String] {
        let repo: Repository
        switch Repository.at(repoURL) {
        case .success(let r): repo = r
        case .failure: throw GitError.repositoryNotFound
        }

        var iter: OpaquePointer?
        guard git_branch_iterator_new(&iter, repo.pointer, GIT_BRANCH_REMOTE) == 0,
              let iter = iter else {
            return []
        }
        defer { git_branch_iterator_free(iter) }

        var branches: [String] = []
        var ref: OpaquePointer?
        var branchType = git_branch_t(rawValue: 0)

        while git_branch_next(&ref, &branchType, iter) == 0 {
            if let ref = ref {
                var namePtr: UnsafePointer<CChar>?
                if git_branch_name(&namePtr, ref) == 0, let namePtr = namePtr {
                    let name = String(cString: namePtr)
                    // "origin/" プレフィックスを除去
                    let stripped = name.hasPrefix("origin/") ? String(name.dropFirst("origin/".count)) : name
                    // HEAD エントリを除外
                    if stripped != "HEAD" {
                        branches.append(stripped)
                    }
                }
                git_reference_free(ref)
            }
            ref = nil
        }

        return branches.sorted()
    }

    // MARK: - Private: Branch Switch (libgit2 C API)

    private nonisolated func performSwitchBranch(
        repoURL: URL,
        branch: String,
        username: String,
        password: String,
        sshPrivateKey: String?,
        sshPassphrase: String?,
        progress: (String) -> Void
    ) throws {
        // Step 1: リポジトリを開く
        let repo: Repository
        switch Repository.at(repoURL) {
        case .success(let r): repo = r
        case .failure: throw GitError.repositoryNotFound
        }

        // Step 2: fetch でリモートを最新化
        progress("リモートをフェッチ中...")
        let credCtx: CredentialContext
        if let sshKey = sshPrivateKey {
            credCtx = CredentialContext(username: username, sshPrivateKey: sshKey, sshPassphrase: sshPassphrase)
        } else {
            credCtx = CredentialContext(username: username, password: password)
        }
        let unmanagedCtx = Unmanaged.passRetained(credCtx)
        defer { unmanagedCtx.release() }

        var rawRemote: OpaquePointer?
        guard git_remote_lookup(&rawRemote, repo.pointer, "origin") == 0,
              let rawRemote = rawRemote else {
            throw GitError.remoteNotFound
        }
        defer { git_remote_free(rawRemote) }

        var fetchOpts = git_fetch_options()
        git_fetch_init_options(&fetchOpts, 1)
        fetchOpts.callbacks.credentials = gitCredentialCallback
        fetchOpts.callbacks.payload = unmanagedCtx.toOpaque()

        let fetchResult = git_remote_fetch(rawRemote, nil, &fetchOpts, "branch-switch")
        if fetchResult != 0 {
            let msg = latestLibgit2ErrorMessage()
            if fetchResult == -16 { throw GitError.authenticationFailed }
            throw GitError.fetchFailed(msg)
        }

        // Step 3: refs/remotes/origin/<branch> の OID を解決
        progress("ブランチを切り替え中...")
        let remoteRefName = "refs/remotes/origin/\(branch)"
        var remoteRef: OpaquePointer?
        guard git_reference_lookup(&remoteRef, repo.pointer, remoteRefName) == 0,
              let remoteRef = remoteRef else {
            throw GitError.branchNotFound(branch)
        }
        defer { git_reference_free(remoteRef) }

        var resolvedRef: OpaquePointer?
        guard git_reference_resolve(&resolvedRef, remoteRef) == 0,
              let resolvedRef = resolvedRef else {
            throw GitError.branchNotFound(branch)
        }
        defer { git_reference_free(resolvedRef) }

        guard let targetOID = git_reference_target(resolvedRef) else {
            throw GitError.switchBranchFailed("リモートブランチの OID を取得できませんでした")
        }

        // Step 4: コミットオブジェクトを取得
        var commitPtr: OpaquePointer?
        guard git_commit_lookup(&commitPtr, repo.pointer, targetOID) == 0,
              let commitPtr = commitPtr else {
            throw GitError.switchBranchFailed("コミットオブジェクトの取得に失敗しました")
        }
        defer { git_commit_free(commitPtr) }

        // Step 5: ローカルブランチを作成／更新（force = 1）
        var localBranchRef: OpaquePointer?
        defer { if let localBranchRef { git_reference_free(localBranchRef) } }
        let branchResult = branch.withCString { branchPtr in
            git_branch_create(&localBranchRef, repo.pointer, branchPtr, commitPtr, 1)
        }
        if branchResult != 0 {
            throw GitError.switchBranchFailed("ローカルブランチの作成に失敗しました: \(latestLibgit2ErrorMessage())")
        }

        // Step 6: ワーキングディレクトリをチェックアウト（force）
        var targetObject: OpaquePointer?
        guard git_object_lookup(&targetObject, repo.pointer, targetOID, GIT_OBJECT_COMMIT) == 0,
              let targetObject = targetObject else {
            throw GitError.switchBranchFailed("コミットオブジェクトの取得に失敗しました")
        }
        defer { git_object_free(targetObject) }

        var checkoutOpts = git_checkout_options()
        git_checkout_options_init(&checkoutOpts, 1)
        // GIT_CHECKOUT_FORCE = 1 << 1 = 2
        checkoutOpts.checkout_strategy = GIT_CHECKOUT_FORCE.rawValue

        let checkoutResult = git_checkout_tree(repo.pointer, targetObject, &checkoutOpts)
        if checkoutResult != 0 {
            throw GitError.switchBranchFailed("チェックアウトに失敗しました: \(latestLibgit2ErrorMessage())")
        }

        // Step 7: HEAD を新しいブランチに更新
        let headResult = "refs/heads/\(branch)".withCString { refPtr in
            git_repository_set_head(repo.pointer, refPtr)
        }
        if headResult != 0 {
            throw GitError.switchBranchFailed("HEAD の更新に失敗しました: \(latestLibgit2ErrorMessage())")
        }

        progress("ブランチの切り替えが完了しました")
    }

    // MARK: - Private Helpers

    private nonisolated func prepareDirectory(at url: URL) throws {
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    private nonisolated func currentHeadDescription(repo: Repository) -> String? {
        switch repo.HEAD() {
        case .success(let ref): return ref.oid.description
        case .failure: return nil
        }
    }

    private nonisolated func mapCloneError(_ error: NSError) -> GitError {
        GitError.mapFromNSError(error)
    }

    private nonisolated func latestLibgit2ErrorMessage() -> String {
        guard let errPtr = git_error_last(),
              let msg = errPtr.pointee.message else {
            return "不明なエラー"
        }
        return String(cString: msg)
    }

    private nonisolated func humanReadablePushError(_ msg: String) -> String {
        GitError.humanReadableMessage(from: msg)
    }
}
