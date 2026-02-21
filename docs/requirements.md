# Obgit 要件定義書

**バージョン:** 2.0
**更新日:** 2026-02-21
**ステータス:** Active

---

## 1. 背景と目的

### 1.1 背景

Obsidian の iOS アプリはネイティブの Git 同期機能を持たない。
Obgit はその空白を埋める専用アプリとして開発している。

### 1.2 目的

- Git リポジトリに保存された Obsidian Vault を iOS 上で閲覧・編集・同期できる環境を提供する
- HTTPS (PAT) と SSH (秘密鍵) の両認証方式に対応する
- マージコンフリクトを UI 上で解決できる仕組みを提供する
- Obsidian らしい 2 ペイン構成の UX を実現する

### 1.3 実装済みスコープ（v2.0）

| 機能 | 状態 |
|---|---|
| HTTPS Clone (PAT) | ✅ |
| SSH Clone (秘密鍵 + パスフレーズ) | ✅ |
| Pull (Fast-forward / 3-way merge / Conflict) | ✅ |
| Commit & Push | ✅ |
| ブランチ切替 | ✅ |
| コミット履歴表示 | ✅ |
| Diff 表示 | ✅ |
| マージコンフリクト解決 UI | ✅ |
| Markdown ビューア (Preview / Raw) | ✅ |
| WikiLink / frontmatter 処理 | ✅ |
| 画像ビューア (pinch-to-zoom) | ✅ |
| ファイルツリーサイドバー | ✅ |
| 全文検索 | ✅ |
| 複数リポジトリ管理 | ✅ |
| AI コミットメッセージ (Apple Intelligence) | ✅ (iOS 26+) |
| Dark / Light / System 外観切替 | ✅ |

---

## 2. ユーザーストーリー

```
As an Obsidian ユーザーとして、
アプリ初回起動時に迷わず Clone 設定を完了したい。
なぜなら、最初に何をすべきかを明確にしたいから。
```

```
As an Obsidian ユーザーとして、
Clone 後は Markdown をそのまま閲覧・編集できる画面を使いたい。
なぜなら、同期後に内容確認・変更まで同じアプリで完結したいから。
```

```
As an Obsidian ユーザーとして、
SSH 鍵でリポジトリを認証して Clone / Push したい。
なぜなら、PAT より SSH の方が自分の環境に合っているから。
```

```
As an Obsidian ユーザーとして、
Pull でコンフリクトが発生した場合も、アプリ内で解決して再 Push したい。
なぜなら、コンフリクト解決のためにデスクトップ PC を使いたくないから。
```

---

## 3. 機能要件

### 3.1 初期状態と画面分岐

- **FR-01**: Clone 済みリポジトリが 0 件の場合、Clone 画面を表示する
- **FR-02**: Clone 済みリポジトリが 1 件以上ある場合、Workspace 画面を表示する
- **FR-03**: Clone 成功後に Workspace 画面へ遷移する

### 3.2 Clone

- **FR-10**: HTTPS + PAT で Clone を実行できる
- **FR-11**: SSH + 秘密鍵（+ 任意のパスフレーズ）で Clone を実行できる
- **FR-12**: URL 形式（`git@` / `ssh://` → SSH、その他 → HTTPS）を自動判定する
- **FR-13**: Clone 中は進捗とログを表示する
- **FR-14**: 認証情報（PAT / 秘密鍵 / パスフレーズ）は Keychain に保存する

### 3.3 Pull

- **FR-20**: Workspace 上から Pull を実行できる
- **FR-21**: Fast-forward の場合は自動で hard reset を行う
- **FR-22**: 3-way merge でコンフリクトがなければ自動でマージコミットを生成する
- **FR-23**: コンフリクトが発生した場合は ConflictResolutionSheet を表示する
- **FR-24**: Pull 成功後にファイルツリーと表示内容を更新する

### 3.4 Commit & Push

- **FR-30**: 編集したファイルの Diff を表示できる
- **FR-31**: コミットメッセージを入力してコミット & プッシュできる
- **FR-32**: Apple Intelligence が利用可能な場合、AI でコミットメッセージを生成できる
- **FR-33**: テンプレート（10 種類）からコミットメッセージを選択できる
- **FR-34**: Push が reject された場合（non-fast-forward）は適切なエラーを表示する

### 3.5 マージコンフリクト解決

- **FR-40**: コンフリクトマーカー（`<<<<<<<` / `=======` / `>>>>>>>>`）をセクション単位で解析する
- **FR-41**: 各セクションで "ours" / "theirs" を選択できる
- **FR-42**: 全セクション解決後にマージコミット & プッシュを実行できる

### 3.6 ブランチ操作

- **FR-50**: リモートブランチ一覧を取得して表示できる
- **FR-51**: ブランチを切り替えられる（fetch → checkout → HEAD 更新）

### 3.7 閲覧機能

- **FR-60**: ファイルツリーサイドバーを左端スワイプで開閉できる
- **FR-61**: `.md` ファイルをレンダリング Preview / Raw テキストで表示できる
- **FR-62**: `[[WikiLink]]` を変換してレンダリングする
- **FR-63**: YAML frontmatter を除去してからレンダリングする
- **FR-64**: 画像（PNG / JPEG / GIF / WebP / HEIC / TIFF / BMP）をビューアで表示できる
- **FR-65**: 全文検索で `.md` ファイルを横断検索できる

### 3.8 リポジトリ管理

- **FR-70**: 複数のリポジトリを管理できる
- **FR-71**: リポジトリの設定（名前・URL・ブランチ・認証情報）を編集できる
- **FR-72**: リポジトリを削除する際にローカルクローンと Keychain の認証情報も削除する

---

## 4. 非機能要件

### 4.1 安定性

- **NFR-01**: Git 操作は libgit2 ベース実装を使用する
- **NFR-02**: Pull 後の再読込で UI と実ファイル状態の乖離が生じないようにする
- **NFR-03**: C API のメモリリーク（`git_*_free()` 漏れ）を防ぐ

### 4.2 UX

- **NFR-10**: 初期画面は 1 画面で Clone 実行まで完結する
- **NFR-11**: サイドバー開閉は 250–300 ms 程度の応答にする
- **NFR-12**: Git 操作中は UI をブロックしない（`DispatchQueue.global` で実行）
- **NFR-13**: 検索は 280 ms debounce でバックグラウンド実行する

### 4.3 セキュリティ

- **NFR-20**: PAT・SSH 秘密鍵・パスフレーズは UserDefaults に保存しない
- **NFR-21**: SSH 秘密鍵はディスクに書き出さず、メモリ内で libgit2 に渡す
- **NFR-22**: Keychain の保護属性は `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` とする

### 4.4 互換性

- **NFR-30**: iOS 18.0+ をサポートする
- **NFR-31**: Apple Intelligence 機能は iOS 26+ の対応デバイスでのみ有効にし、非対応環境ではテンプレートにフォールバックする

---

## 5. 画面設計

### 5.1 画面一覧

| 画面 ID | 画面名 | 概要 |
|---|---|---|
| S-01 | Clone 画面 | リポジトリ入力・認証入力・Clone 実行 |
| S-02 | Workspace 画面 | 左サイドバー（ツリー）+ 右メイン（Markdown） |
| S-03 | Commit ダイアログ | Diff 確認・コミットメッセージ入力・Push |
| S-04 | ConflictResolution シート | セクション単位のコンフリクト解決 |
| S-05 | BranchSwitch シート | リモートブランチ一覧・切替 |
| S-06 | CommitHistory シート | コミットログ閲覧 |
| S-07 | Search シート | 全文検索 |
| S-08 | RepositoryDetail 画面 | リポジトリ設定の編集・削除 |

### 5.2 画面遷移

```
起動
 ├─ Clone 済みなし → S-01 Clone
 └─ Clone 済みあり → S-02 Workspace

S-01 Clone
 └─ Clone 成功 → S-02 Workspace

S-02 Workspace
 ├─ Pull → コンフリクト → S-04 ConflictResolution
 ├─ 編集後コミット → S-03 Commit
 ├─ ブランチ切替 → S-05 BranchSwitch
 ├─ コミット履歴 → S-06 CommitHistory
 └─ 全文検索 → S-07 Search
```

---

## 6. 受け入れ条件

1. HTTPS (PAT) および SSH（秘密鍵）で Clone が完了すること
2. Pull で Fast-forward / 3-way merge / Conflict の各ケースが正常動作すること
3. Commit & Push が完了し、リモートリポジトリへ反映されること
4. ConflictResolutionSheet で全セクション解決後にマージコミットが成功すること
5. ブランチ切替後にファイルツリーと表示内容が切替先ブランチのものに更新されること
6. 認証情報（PAT / SSH 鍵）が Keychain から正常に取得できること
