import Foundation

/// Obsidian Markdown のプレビュー用前処理ユーティリティ
///
/// プレビュー表示時に以下の変換を行う:
/// 1. YAML frontmatter (`---` ... `---`) の除去
/// 2. `[[WikiLink]]` を Markdown インラインリンクへ変換
///    （MarkdownUI が `wikilink://` スキームの URL を生成し、`OpenURLAction` で処理する）
enum MarkdownProcessor {

    // MARK: - Frontmatter Stripping

    /// YAML frontmatter を除去してノート本文を返す
    ///
    /// frontmatter はファイル先頭の `---` 行から始まり、次の `---` または `...` 行で終わる。
    /// 閉じ記号が見つからない場合はテキストをそのまま返す。
    static func stripFrontmatter(from text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard !lines.isEmpty else { return text }

        // 先頭行が "---"（CR 付きでも対応）
        let firstLine = lines[0].trimmingCharacters(in: .init(charactersIn: "\r"))
        guard firstLine == "---" else { return text }

        for i in 1 ..< lines.count {
            let line = lines[i].trimmingCharacters(in: .init(charactersIn: "\r"))
            if line == "---" || line == "..." {
                // 閉じ記号より後の行が本文
                let body = lines[(i + 1)...].joined(separator: "\n")
                return body.trimmingCharacters(in: .newlines)
            }
        }

        // 閉じ記号なし → 元のテキストをそのまま返す
        return text
    }

    // MARK: - WikiLink Conversion

    /// `[[WikiLink]]` を Markdown インラインリンクへ変換する
    ///
    /// | 入力形式                       | 出力形式                                      |
    /// |-------------------------------|-----------------------------------------------|
    /// | `[[note]]`                    | `[note](wikilink://note)`                     |
    /// | `[[note\|Display Text]]`      | `[Display Text](wikilink://note)`             |
    /// | `[[note#heading]]`            | `[note](wikilink://note)`                     |
    /// | `[[note#heading\|Display]]`   | `[Display](wikilink://note)`                  |
    /// | `[[path/to/note]]`            | `[path/to/note](wikilink://path/to/note)`     |
    ///
    /// - Note: コードブロック内の `[[...]]` も変換されるが、MarkdownUI が
    ///   コードとして扱うためリンクとして機能しない（許容範囲内の制約）。
    static func convertWikiLinks(in text: String) -> String {
        // [[...]] の内容をキャプチャ（ネストした [] を含まない）
        guard let regex = try? NSRegularExpression(
            pattern: #"\[\[([^\[\]]+)\]\]"#,
            options: []
        ) else { return text }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)
        guard !matches.isEmpty else { return text }

        var result = ""
        result.reserveCapacity(text.count + matches.count * 24)
        var lastEnd = text.startIndex

        for match in matches {
            guard let fullRange = Range(match.range, in: text),
                  let contentRange = Range(match.range(at: 1), in: text) else { continue }

            // マッチ前のテキストをそのまま追記
            result += text[lastEnd ..< fullRange.lowerBound]
            lastEnd = fullRange.upperBound

            let (target, display) = parseWikiLinkContent(String(text[contentRange]))

            // ターゲット名を URL パス用にエンコード（スペース → %20、/ はそのまま）
            let encoded = target
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                ?? target

            result += "[\(display)](wikilink://\(encoded))"
        }

        result += text[lastEnd...]
        return result
    }

    // MARK: - Combined

    /// プレビュー表示用テキストを生成する
    ///
    /// frontmatter 除去 → WikiLink 変換 の順で処理する。
    static func processForPreview(_ text: String) -> String {
        convertWikiLinks(in: stripFrontmatter(from: text))
    }

    // MARK: - URL Parsing

    /// `wikilink://` URL からノート名を取り出す
    ///
    /// - Returns: パーセントデコード済みのノート名。`wikilink://` スキーム以外は `nil`。
    static func noteName(from url: URL) -> String? {
        guard url.scheme == "wikilink" else { return nil }
        // absoluteString 例: "wikilink://My%20Note" → "My Note"
        let raw = String(url.absoluteString.dropFirst("wikilink://".count))
        return raw.removingPercentEncoding ?? raw
    }

    // MARK: - Private

    /// `[[...]]` 内の文字列を `(target, display)` にパースする
    ///
    /// - `|` で分割: 左＝ターゲット（見出しアンカー含む）、右＝表示テキスト
    /// - `#` で分割: 左をターゲット名として使用（見出しアンカーを除去）
    private static func parseWikiLinkContent(_ content: String) -> (target: String, display: String) {
        // | で最大 1 回分割
        let pipeIndex = content.firstIndex(of: "|")
        let rawTarget: String
        let rawDisplay: String?

        if let idx = pipeIndex {
            rawTarget = String(content[content.startIndex ..< idx])
            rawDisplay = String(content[content.index(after: idx)...])
                .trimmingCharacters(in: .whitespaces)
        } else {
            rawTarget = content
            rawDisplay = nil
        }

        // # より前をターゲット名として使用（見出しアンカーを除去）
        let target: String
        if let hashIndex = rawTarget.firstIndex(of: "#") {
            target = String(rawTarget[rawTarget.startIndex ..< hashIndex])
                .trimmingCharacters(in: .whitespaces)
        } else {
            target = rawTarget.trimmingCharacters(in: .whitespaces)
        }

        // 表示テキスト: rawDisplay が空でなければ使用、なければターゲット名
        let display = rawDisplay?.isEmpty == false ? rawDisplay ?? target : target
        return (target, display)
    }
}
