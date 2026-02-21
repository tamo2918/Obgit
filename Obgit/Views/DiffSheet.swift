import SwiftUI

struct DiffSheet: View {
    let diff: FileDiff
    @Environment(\.dismiss) private var dismiss

    init(originalText: String, editedText: String, fileName: String) {
        self.diff = DiffEngine.shared.diff(
            originalText: originalText,
            editedText: editedText,
            fileName: fileName
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if diff.isEmpty {
                    ContentUnavailableView(
                        "変更なし",
                        systemImage: "doc.badge.checkmark",
                        description: Text("ファイルに変更はありません。")
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                            ForEach(diff.hunks) { hunk in
                                HunkView(hunk: hunk)
                            }
                        }
                        .padding(.bottom, 16)
                    }
                }
            }
            .background(ObgitLiquidBackground())
            .navigationTitle(diff.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                if !diff.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 6) {
                            DiffBadge(count: diff.totalAdded, color: ObgitPalette.mint, prefix: "+")
                            DiffBadge(count: diff.totalRemoved, color: ObgitPalette.coral, prefix: "-")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - HunkView

private struct HunkView: View {
    let hunk: DiffHunk

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hunk ヘッダー
            Text("@@ -\(hunk.leftStart) +\(hunk.rightStart) @@")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(ObgitPalette.secondaryInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ObgitPalette.shellSurfaceStrong.opacity(0.6))

            // 各行
            ForEach(hunk.lines) { line in
                DiffLineRow(line: line)
            }
        }
        .padding(.bottom, 8)
    }
}

// MARK: - DiffLineRow

private struct DiffLineRow: View {
    let line: DiffLine

    private var bgColor: Color {
        switch line.kind {
        case .added:   return ObgitPalette.mint.opacity(0.12)
        case .removed: return ObgitPalette.coral.opacity(0.12)
        case .context: return Color.clear
        }
    }

    private var prefixChar: String {
        switch line.kind {
        case .added:   return "+"
        case .removed: return "-"
        case .context: return " "
        }
    }

    private var prefixColor: Color {
        switch line.kind {
        case .added:   return ObgitPalette.mint
        case .removed: return ObgitPalette.coral
        case .context: return ObgitPalette.secondaryInk
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // 左行番号
            Text(line.leftLineNumber.map { "\($0)" } ?? "")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(ObgitPalette.secondaryInk)
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 4)

            // 右行番号
            Text(line.rightLineNumber.map { "\($0)" } ?? "")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(ObgitPalette.secondaryInk)
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 4)

            // +/-/ 記号
            Text(prefixChar)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(prefixColor)
                .frame(width: 14)

            // コード内容
            Text(line.text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(ObgitPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 6)
        .background(bgColor)
    }
}

// MARK: - DiffBadge

private struct DiffBadge: View {
    let count: Int
    let color: Color
    let prefix: String

    var body: some View {
        Text("\(prefix)\(count)")
            .font(.system(.caption, design: .monospaced).weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.15))
            )
    }
}
