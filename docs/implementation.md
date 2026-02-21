# Obgit 実装ドキュメント

**バージョン:** 2.0
**更新日:** 2026-02-21

---

## 1. 実装サマリー

アプリは **Clone 画面** と **Workspace 画面** の 2 状態をルートで切り替える構成。

```
起動 → RepositoryStore.repositories を監視
       ├─ isCloned == 0 → CloneRepositoryScreen
       └─ isCloned ≥ 1 → VaultWorkspaceShellView
```

Git 操作はすべて `GitService` (libgit2 C API) が担い、UI 層は Swift 6 の `async/await` + `withCheckedThrowingContinuation` で呼び出す。

---

## 2. ファイル構成

### Models

| ファイル | 概要 |
|---|---|
| `RepositoryModel.swift` | Codable モデル（UserDefaults に JSON 保存）、`AuthType` computed property で URL から認証方式を自動判定 |
| `VaultFileNode.swift` | ファイルツリーノード定義 + `VaultFileTreeBuilder`（隠しファイル・`.git`・シンボリックリンク除外、ディレクトリ優先ソート） |
| `CommitEntry.swift` | コミット履歴エントリ（shortHash / authorName / date / subject） |
| `DiffModels.swift` | `DiffLineKind` / `DiffHunk` / `FileDiff`（差分表示用） |
| `ConflictFile.swift` | コンフリクトマーカーをパースして `ContentBlock` 列挙型（plain / conflict）に分解、セクション単位で解決を記録、全メソッドを `nonisolated` で定義 |

### Services

| ファイル | 概要 |
|---|---|
| `GitService.swift` | Clone / Pull / Commit / Push / Branch 操作（〜1,200 行） |
| `GitError.swift` | 24 種類のエラー型、英語 → 日本語の自動変換メッセージ |
| `KeychainService.swift` | `kSecClassGenericPassword` で PAT / SSH 秘密鍵 / パスフレーズを保存 |
| `DiffEngine.swift` | Myers O(ND) アルゴリズム（pure Swift、`nonisolated`） |
| `MarkdownProcessor.swift` | YAML frontmatter 除去、`[[WikiLink]]` 変換（Display Text / Heading Anchor 対応） |
| `CommitMessageGenerator.swift` | Apple Intelligence (`SystemLanguageModel`) による生成 + 10 種テンプレートフォールバック |

### Stores

| ファイル | 概要 |
|---|---|
| `RepositoryStore.swift` | Singleton `@MainActor`、UserDefaults に JSON serialize、起動時にローカル存在確認して `isCloned` を再検証 |

### ViewModels

| ファイル | 概要 |
|---|---|
| `CloneRepositoryViewModel.swift` | Clone 画面入力状態管理、URL 形式から SSH/HTTPS を自動判定、clone 実行制御 |
| `VaultWorkspaceViewModel.swift` | ファイルツリー管理、Markdown 読込、Pull 実行、編集状態管理、Commit/Push 制御 |
| `RepositoryDetailViewModel.swift` | 設定編集、再 Clone、認証情報の更新 |
| `RepositoryListViewModel.swift` | リポジトリ一覧の表示ラッパー |
| `SearchViewModel.swift` | 280 ms debounce、`Task.detached` で background 実行、前回タスクを cancel |

### Views

| ファイル | 概要 |
|---|---|
| `VaultHomeView.swift` | ルート分岐、Clone 画面、Workspace シェル、サイドバー |
| `CommitDialogView.swift` | Diff 表示 + コミットメッセージ入力 + AI 生成 + Push |
| `ConflictResolutionSheet.swift` | セクション単位の ours/theirs 選択 UI |
| `DiffSheet.swift` | Unified diff ビューア |
| `BranchSwitchSheet.swift` | リモートブランチ一覧取得 + 切替 |
| `CommitHistorySheet.swift` | コミットログ一覧 |
| `SearchView.swift` | 全文検索シート |
| `AddRepositoryView.swift` | リポジトリ追加画面 |
| `RepositoryDetailView.swift` | リポジトリ設定の編集・削除 |
| `ObgitLiquidStyle.swift` | デザインシステム（カラーパレット、共通スタイル） |

---

## 3. GitService 実装詳細

### 3.1 認証コールバック

```swift
// C コールバック（@convention(c)、ファイルスコープ）
nonisolated(unsafe) private let gitCredentialCallback: @convention(c) (...) = { ... }

// CredentialContext: @unchecked Sendable で Unmanaged<T> パターン
final class CredentialContext: @unchecked Sendable {
    let username: String
    let password: String         // PAT
    let sshPrivateKey: String?
    let sshPassphrase: String?
}

// 呼び出し側
let unmanagedCtx = Unmanaged.passRetained(credCtx)
defer { unmanagedCtx.release() }
```

`allowedTypes` ビットマスク判定:
- `& 32` (GIT_CREDENTIAL_USERNAME) → `git_cred_username_new`
- `& 64` (GIT_CREDENTIAL_SSH_MEMORY) → `git_cred_ssh_key_memory_new`（秘密鍵）
- `& 1` (GIT_CREDENTIAL_USERPASS_PLAINTEXT) → `git_cred_userpass_plaintext_new`（PAT）

### 3.2 Clone

| 認証方式 | 実装 |
|---|---|
| HTTPS | `Repository.clone()` (SwiftGit2) |
| SSH | `git_clone()` (Clibgit2 C API) — SwiftGit2 は SSH 非対応のため |

### 3.3 Pull

```
git_remote_fetch()               // 認証付きフェッチ
  ↓
git_merge_analysis()
  ├─ UP_TO_DATE  → スキップ（0 件変更を返す）
  ├─ FASTFORWARD → git_reset(GIT_RESET_HARD)（fast-forward）
  └─ NORMAL      → git_merge()
                     ├─ コンフリクトなし → 自動マージコミット生成
                     └─ コンフリクトあり → GitError.mergeConflicts([ConflictFile]) をスロー
```

`git_merge_analysis` / `git_merge` の heads 引数:
```swift
var heads: [OpaquePointer?] = [fetchHead]
heads.withUnsafeMutableBufferPointer { buf in
    git_merge(repo, buf.baseAddress, 1, &mergeOpts, &checkoutOpts)
}
```

### 3.4 Commit & Push

```
git_index_add_all()              // 全変更をステージング
git_index_write_tree()           // インデックスをツリーに変換
git_commit_create()              // コミットオブジェクト作成
git_remote_upload()              // 認証付きプッシュ
```

Push reject 検出: `git_remote_upload` のエラーメッセージを解析して `GitError.pushRejected` をスロー。

### 3.5 Merge Conflict 解決

```
collectConflictFiles()
  → git_index_conflict_iterator で OID を取得
  → git_blob_rawcontent() でコンフリクト内容を読み込み
  → ConflictFile.parse() でセクション分解

stageResolvedFile(conflictFile:)
  → ConflictFile.resolvedContent() で解決済みテキスト生成
  → ファイルに書き出し
  → git_index_add() でステージング

completeMergeCommit(...)
  → git_commit_create() で 2 親コミット（HEAD + MERGE_HEAD）
  → .git/MERGE_HEAD を削除
  → git_remote_upload() でプッシュ
```

### 3.6 Branch 切替

```
git_remote_fetch()
  → refs/remotes/origin/<branch> を解決
  → git_branch_create(force: true)
  → git_checkout_tree(GIT_CHECKOUT_FORCE)
  → git_repository_set_head()
```

---

## 4. DiffEngine

- **アルゴリズム**: Myers O(ND)（pure Swift）
- **実装方式**: V 配列スナップショットで backward-trace 可能
- **hunk 分割**: context lines（デフォルト 3 行）で分割
- **スレッド安全性**: 全メソッドが `nonisolated`（`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 環境でも background thread で実行可能）

---

## 5. ConflictFile

- `parse()`: state machine でコンフリクトマーカーを解析し `[ContentBlock]` を生成
- `resolve(sectionIndex:lines:)`: セクション単位で解決済み行を記録（`mutating`）
- `resolvedContent()`: 全 block を走査し解決済みコンテンツを生成
- 全メソッドが `nonisolated`（MainActor 環境での background 実行に対応）

---

## 6. KeychainService

| account キー | 内容 |
|---|---|
| `repositoryID` | PAT |
| `ssh_repositoryID` | SSH 秘密鍵（PEM テキスト） |
| `pass_repositoryID` | SSH パスフレーズ |

保護属性: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`

---

## 7. 非同期パターン

```swift
// GitService の blocking C API を async に変換
func pull(...) async throws -> Int {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let count = try self.performPull(...)
                continuation.resume(returning: count)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// Progress callback を MainActor で UI 更新
git_remote_fetch(remote, nil, &fetchOpts, nil)
// fetchOpts.callbacks.transfer_progress = { stats, payload in
//     Task { @MainActor in progress(stats.received_objects) }
// }
```

---

## 8. Xcode プロジェクト設定

| 設定 | 値 | 目的 |
|---|---|---|
| `SWIFT_DEFAULT_ACTOR_ISOLATION` | `MainActor` | 全型・関数のデフォルト isolation を MainActor に設定 |
| `SWIFT_STRICT_CONCURRENCY` | `complete` | Swift 6 完全並行性チェック |
| `UIFileSharingEnabled` | `true` | Files アプリからリポジトリ閲覧可能 |
| `LSSupportsOpeningDocumentsInPlace` | `true` | Files アプリからその場で開く |
| `objectVersion` | `77` | Xcode 26（`PBXFileSystemSynchronizedRootGroup` を使用） |

---

## 9. 検証観点

1. HTTPS (PAT) Clone が完了し Workspace へ遷移すること
2. SSH（秘密鍵 + パスフレーズ）Clone が完了すること
3. Pull — Fast-forward / 3-way merge / Conflict の各ケースが正常動作すること
4. ConflictResolutionSheet で全セクション解決後にマージコミットが成功すること
5. ブランチ切替後にファイルツリーと表示内容が切替先のものに更新されること
6. Commit & Push が完了しリモートリポジトリへ反映されること
7. PAT / SSH 鍵 / パスフレーズが Keychain から正常に取得できること
8. 全文検索で `.md` ファイルの横断検索が機能すること
