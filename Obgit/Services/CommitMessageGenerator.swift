import Foundation
import FoundationModels

/// コミットメッセージの AI 生成 + テンプレート提供
///
/// - Foundation Models (iOS 26+ / Apple Intelligence 対応機種) が使えれば AI 生成
/// - 使えない機種ではテンプレート一覧をフォールバックとして提供
struct CommitMessageGenerator {

    // MARK: - テンプレート（常に使用可能）

    static let templates: [String] = [
        "ノートを更新",
        "内容を編集",
        "情報を追加",
        "誤字を修正",
        "構成を整理",
        "アイデアを追記",
        "メモを更新",
        "説明を修正",
        "見出しを変更",
        "リストを更新",
    ]

    // MARK: - 利用可能判定

    /// Foundation Models (Apple Intelligence) がこのデバイスで使えるか
    static var isAIAvailable: Bool {
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
    }

    // MARK: - AI 生成

    /// 変更前後のテキストから差分を生成してコミットメッセージを AI で生成する
    ///
    /// - Parameters:
    ///   - fileName: 編集したファイル名（例: "2024-01-01.md"）
    ///   - original: 編集前の内容
    ///   - edited: 編集後の内容
    /// - Returns: 生成されたコミットメッセージ
    /// - Throws: `GenerationError.modelNotAvailable` または `LanguageModelSession.GenerationError`
    @available(iOS 26.0, *)
    static func generate(fileName: String, original: String, edited: String) async throws -> String {
        guard SystemLanguageModel.default.isAvailable else {
            throw GenerationError.modelNotAvailable
        }

        let session = LanguageModelSession(
            instructions: """
            あなたはgitコミットメッセージの専門家です。
            Obsidianのmarkdownノートの変更差分を見て、
            簡潔なコミットメッセージを日本語で1行だけ生成してください。

            ルール:
            - 72文字以内
            - 「〜を更新」「〜を追加」「〜を修正」「〜を整理」などの命令形
            - コミットメッセージのテキストのみを出力（前置き・説明・引用符は一切不要）
            - ファイル名は含めなくてよい
            """
        )

        let diff = makeDiff(original: original, edited: edited)
        let prompt = """
        ファイル名: \(fileName)

        変更差分（- が削除行、+ が追加行）:
        \(String(diff.prefix(800)))
        """

        let response = try await session.respond(to: prompt)
        let result = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`「」『』"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Simple line-level diff

    /// 行単位の簡易差分を生成する（削除行に `-`、追加行に `+` を付与）
    private static func makeDiff(original: String, edited: String) -> String {
        let originalLines = original.components(separatedBy: .newlines)
        let editedLines   = edited.components(separatedBy: .newlines)

        let originalSet = Set(originalLines)
        let editedSet   = Set(editedLines)

        var lines: [String] = []

        // 削除された行
        for line in originalLines where !editedSet.contains(line) && !line.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("- \(line)")
        }
        // 追加された行
        for line in editedLines where !originalSet.contains(line) && !line.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("+ \(line)")
        }

        return lines.isEmpty ? "(変更なし)" : lines.joined(separator: "\n")
    }

    // MARK: - Errors

    enum GenerationError: Error, LocalizedError {
        case modelNotAvailable

        var errorDescription: String? {
            "Apple Intelligence がこのデバイスでは利用できません"
        }
    }
}
