import Testing
@testable import Obgit

// MARK: - RepositoryModel Tests

@Suite("RepositoryModel")
struct RepositoryModelTests {

    @Test("localDirName: スペースはアンダースコアに変換される")
    func localDirNameSpaces() {
        let repo = RepositoryModel(name: "My Vault", remoteURL: "https://example.com", username: "user")
        #expect(repo.localDirName == "My_Vault")
    }

    @Test("localDirName: スラッシュは除去される")
    func localDirNameSlash() {
        let repo = RepositoryModel(name: "foo/bar", remoteURL: "https://example.com", username: "user")
        #expect(!repo.localDirName.contains("/"))
    }

    @Test("localDirName: ドットドットは除去される")
    func localDirNameDotDot() {
        let repo = RepositoryModel(name: "../etc", remoteURL: "https://example.com", username: "user")
        #expect(!repo.localDirName.contains("/"))
    }

    @Test("localDirName: 空文字列になる場合は 'repository' にフォールバック")
    func localDirNameEmpty() {
        let repo = RepositoryModel(name: "///", remoteURL: "https://example.com", username: "user")
        #expect(repo.localDirName == "repository")
    }

    @Test("localDirName: 64文字を超える名前は切り捨てられる")
    func localDirNameTruncated() {
        let longName = String(repeating: "a", count: 100)
        let repo = RepositoryModel(name: longName, remoteURL: "https://example.com", username: "user")
        #expect(repo.localDirName.count <= 64)
    }

    @Test("addLog: ログが先頭に追加される")
    func addLogInsertsAtHead() {
        var repo = RepositoryModel(name: "test", remoteURL: "https://example.com", username: "user")
        repo.addLog("first")
        repo.addLog("second")
        #expect(repo.logs.first?.message == "second")
        #expect(repo.logs.last?.message == "first")
    }

    @Test("addLog: ログは最大100件に制限される")
    func addLogLimit() {
        var repo = RepositoryModel(name: "test", remoteURL: "https://example.com", username: "user")
        for i in 0..<110 {
            repo.addLog("log \(i)")
        }
        #expect(repo.logs.count == 100)
    }

    @Test("addLog: isError フラグが正しく保存される")
    func addLogErrorFlag() {
        var repo = RepositoryModel(name: "test", remoteURL: "https://example.com", username: "user")
        repo.addLog("error occurred", isError: true)
        repo.addLog("success")
        #expect(repo.logs[0].isError == false)
        #expect(repo.logs[1].isError == true)
    }
}

// MARK: - VaultFileNode Tests

@Suite("VaultFileNode")
struct VaultFileNodeTests {

    private func makeNode(name: String, isDirectory: Bool = false) -> VaultFileNode {
        let url = URL(fileURLWithPath: "/tmp/\(name)")
        return VaultFileNode(url: url, isDirectory: isDirectory)
    }

    @Test("isMarkdown: .md 拡張子を正しく識別する")
    func isMarkdownMd() {
        #expect(makeNode(name: "note.md").isMarkdown == true)
    }

    @Test("isMarkdown: .markdown 拡張子を正しく識別する")
    func isMarkdownMarkdown() {
        #expect(makeNode(name: "note.markdown").isMarkdown == true)
    }

    @Test("isMarkdown: ディレクトリは false")
    func isMarkdownDirectory() {
        #expect(makeNode(name: "folder.md", isDirectory: true).isMarkdown == false)
    }

    @Test("isMarkdown: 拡張子なしは false")
    func isMarkdownNoExt() {
        #expect(makeNode(name: "README").isMarkdown == false)
    }

    @Test("isImage: 各画像形式を正しく識別する")
    func isImageFormats() {
        for ext in ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tiff", "bmp"] {
            #expect(makeNode(name: "photo.\(ext)").isImage == true, ".\(ext) should be image")
        }
    }

    @Test("isImage: .md は false")
    func isImageNotMd() {
        #expect(makeNode(name: "note.md").isImage == false)
    }

    @Test("isViewable: Markdown は true")
    func isViewableMarkdown() {
        #expect(makeNode(name: "note.md").isViewable == true)
    }

    @Test("isViewable: 画像は true")
    func isViewableImage() {
        #expect(makeNode(name: "photo.png").isViewable == true)
    }

    @Test("isViewable: Swift ファイルは false")
    func isViewableSwift() {
        #expect(makeNode(name: "main.swift").isViewable == false)
    }

    @Test("outlineChildren: ディレクトリは子ノードを返す")
    func outlineChildrenDirectory() {
        let child = makeNode(name: "child.md")
        let dir = VaultFileNode(url: URL(fileURLWithPath: "/tmp/folder"), isDirectory: true, children: [child])
        #expect(dir.outlineChildren != nil)
        #expect(dir.outlineChildren?.count == 1)
    }

    @Test("outlineChildren: ファイルは nil を返す")
    func outlineChildrenFile() {
        #expect(makeNode(name: "note.md").outlineChildren == nil)
    }
}

// MARK: - GitError Tests

@Suite("GitError")
struct GitErrorTests {

    @Test("errorDescription: cloneFailed")
    func cloneFailed() {
        let error = GitError.cloneFailed("some message")
        #expect(error.errorDescription?.contains("クローン失敗") == true)
    }

    @Test("errorDescription: authenticationFailed")
    func authenticationFailed() {
        let error = GitError.authenticationFailed
        #expect(error.errorDescription?.contains("認証") == true)
    }

    @Test("errorDescription: repositoryNotFound")
    func repositoryNotFound() {
        let error = GitError.repositoryNotFound
        #expect(error.errorDescription?.contains("見つかりません") == true)
    }

    @Test("errorDescription: branchNotFound")
    func branchNotFound() {
        let error = GitError.branchNotFound("develop")
        #expect(error.errorDescription?.contains("develop") == true)
    }

    @Test("errorDescription: nothingToCommit")
    func nothingToCommit() {
        let error = GitError.nothingToCommit
        #expect(error.errorDescription?.isEmpty == false)
    }

    @Test("errorDescription: pushRejected")
    func pushRejected() {
        let error = GitError.pushRejected("rejected")
        #expect(error.errorDescription?.contains("拒否") == true)
    }

    @Test("humanReadableMessage: 認証エラーキーワードを日本語に変換する")
    func humanReadableAuth() {
        let msg = GitError.humanReadableMessage(from: "authentication required")
        #expect(msg.contains("認証"))
    }

    @Test("humanReadableMessage: ネットワークエラーキーワードを日本語に変換する")
    func humanReadableNetwork() {
        let msg = GitError.humanReadableMessage(from: "failed to connect")
        #expect(msg.contains("ネットワーク"))
    }

    @Test("humanReadableMessage: 不明なメッセージはそのまま返す")
    func humanReadableUnknown() {
        let input = "completely unknown error xyz"
        let msg = GitError.humanReadableMessage(from: input)
        #expect(msg == input)
    }

    @Test("mapFromNSError: 認証エラーは .authenticationFailed に変換される")
    func mapFromNSErrorAuth() {
        let nsError = NSError(domain: "git", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "401 authentication failed"])
        let error = GitError.mapFromNSError(nsError)
        if case .authenticationFailed = error { } else {
            Issue.record("Expected .authenticationFailed, got \(error)")
        }
    }

    @Test("mapFromNSError: not found は .repositoryNotFound に変換される")
    func mapFromNSErrorNotFound() {
        let nsError = NSError(domain: "git", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "repository not found 404"])
        let error = GitError.mapFromNSError(nsError)
        if case .repositoryNotFound = error { } else {
            Issue.record("Expected .repositoryNotFound, got \(error)")
        }
    }
}

// MARK: - CommitMessageGenerator Tests

@Suite("CommitMessageGenerator")
struct CommitMessageGeneratorTests {

    @Test("templates: 空でないこと")
    func templatesNotEmpty() {
        #expect(!CommitMessageGenerator.templates.isEmpty)
    }

    @Test("templates: 各テンプレートが空文字列でないこと")
    func templatesAllNonEmpty() {
        for template in CommitMessageGenerator.templates {
            #expect(!template.isEmpty)
        }
    }
}

// MARK: - FileSearchResult Tests

@Suite("FileSearchResult")
struct FileSearchResultTests {

    @Test("isFileNameMatch: lineMatches が空の場合 true")
    func isFileNameMatchTrue() {
        let result = FileSearchResult(
            fileURL: URL(fileURLWithPath: "/tmp/note.md"),
            fileName: "note.md",
            lineMatches: []
        )
        #expect(result.isFileNameMatch == true)
    }

    @Test("isFileNameMatch: lineMatches がある場合 false")
    func isFileNameMatchFalse() {
        let match = FileSearchResult.LineMatch(lineNumber: 1, text: "hello")
        let result = FileSearchResult(
            fileURL: URL(fileURLWithPath: "/tmp/note.md"),
            fileName: "note.md",
            lineMatches: [match]
        )
        #expect(result.isFileNameMatch == false)
    }
}
