import Foundation

// MARK: - ConflictSection

/// git コンフリクトマーカーで区切られたひとつのコンフリクトセクション
struct ConflictSection: Identifiable, Sendable {
    let id = UUID()
    let oursLines: [String]    // <<<<<<< HEAD 〜 ======= の間
    let theirsLines: [String]  // ======= 〜 >>>>>>> の間
    var resolvedLines: [String]? = nil

    var isResolved: Bool { resolvedLines != nil }
}

// MARK: - ContentBlock

/// ファイルのコンテンツブロック（通常テキスト or コンフリクトセクション）
enum ContentBlock: Identifiable, Sendable {
    case plain(id: UUID, lines: [String])
    case conflict(ConflictSection)

    nonisolated var id: UUID {
        switch self {
        case .plain(let id, _): return id
        case .conflict(let section): return section.id
        }
    }

    nonisolated var isConflict: Bool {
        if case .conflict = self { return true }
        return false
    }
}

// MARK: - ConflictFile

/// コンフリクトマーカーを含むファイル
struct ConflictFile: Identifiable, Sendable {
    let id = UUID()
    let relativePath: String   // repo 相対パス（git index 操作に使用）
    let absoluteURL: URL
    var blocks: [ContentBlock]

    var conflictCount: Int {
        blocks.filter(\.isConflict).count
    }

    var unresolvedCount: Int {
        blocks.compactMap {
            if case .conflict(let s) = $0 { return s }
            return nil
        }.filter { !$0.isResolved }.count
    }

    var allResolved: Bool { unresolvedCount == 0 }

    // MARK: - Parser

    /// ファイルをパースして ConflictFile を返す。コンフリクトがなければ nil を返す
    nonisolated static func parse(relativePath: String, absoluteURL: URL) -> ConflictFile? {
        guard let content = try? String(contentsOf: absoluteURL, encoding: .utf8) else { return nil }
        var lines = content.components(separatedBy: "\n")
        // 末尾の空行を除去
        if lines.last == "" { lines.removeLast() }

        enum State { case normal, inOurs, inTheirs }
        var state: State = .normal
        var blocks: [ContentBlock] = []
        var plainBuf: [String] = []
        var oursBuf: [String] = []
        var theirsBuf: [String] = []

        for line in lines {
            switch state {
            case .normal:
                if line.hasPrefix("<<<<<<<") {
                    if !plainBuf.isEmpty {
                        blocks.append(.plain(id: UUID(), lines: plainBuf))
                        plainBuf = []
                    }
                    state = .inOurs
                } else {
                    plainBuf.append(line)
                }
            case .inOurs:
                if line.hasPrefix("=======") {
                    state = .inTheirs
                } else {
                    oursBuf.append(line)
                }
            case .inTheirs:
                if line.hasPrefix(">>>>>>>") {
                    let section = ConflictSection(oursLines: oursBuf, theirsLines: theirsBuf)
                    blocks.append(.conflict(section))
                    oursBuf = []
                    theirsBuf = []
                    state = .normal
                } else {
                    theirsBuf.append(line)
                }
            }
        }

        // 末尾の通常テキスト
        if !plainBuf.isEmpty {
            blocks.append(.plain(id: UUID(), lines: plainBuf))
        }

        // コンフリクトが1つもなければ nil
        let hasConflict = blocks.contains(where: \.isConflict)
        guard hasConflict else { return nil }

        return ConflictFile(relativePath: relativePath, absoluteURL: absoluteURL, blocks: blocks)
    }

    // MARK: - Resolution

    /// 指定セクションを与えられた行で解決済みにする
    nonisolated mutating func resolve(sectionID: UUID, with lines: [String]) {
        for i in blocks.indices {
            if case .conflict(var section) = blocks[i], section.id == sectionID {
                section.resolvedLines = lines
                blocks[i] = .conflict(section)
                return
            }
        }
    }

    /// 全ブロックを結合した解決済みコンテンツを返す
    nonisolated func resolvedContent() -> String {
        var result: [String] = []
        for block in blocks {
            switch block {
            case .plain(_, let lines):
                result.append(contentsOf: lines)
            case .conflict(let section):
                if let resolved = section.resolvedLines {
                    result.append(contentsOf: resolved)
                } else {
                    // 未解決の場合はオリジナルのコンフリクトマーカーを維持
                    result.append("<<<<<<< HEAD")
                    result.append(contentsOf: section.oursLines)
                    result.append("=======")
                    result.append(contentsOf: section.theirsLines)
                    result.append(">>>>>>> theirs")
                }
            }
        }
        return result.joined(separator: "\n")
    }
}
