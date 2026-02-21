import SwiftUI

struct ConflictResolutionSheet: View {
    @ObservedObject var vm: VaultWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFileIndex = 0
    @State private var commitMessage = "Merge remote-tracking branch"
    @AppStorage("commit_author_name") private var authorName = ""
    @AppStorage("commit_author_email") private var authorEmail = ""

    private var currentFile: ConflictFile? {
        guard vm.conflictFiles.indices.contains(selectedFileIndex) else { return nil }
        return vm.conflictFiles[selectedFileIndex]
    }

    private var totalUnresolved: Int {
        vm.conflictFiles.reduce(0) { $0 + $1.unresolvedCount }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // ファイルタブ（複数ファイルの場合）
                    if vm.conflictFiles.count > 1 {
                        fileTabBar
                    }

                    // コンフリクトセクション一覧
                    if let file = currentFile {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(file.blocks) { block in
                                    if case .conflict(let section) = block {
                                        ConflictSectionCard(
                                            section: section,
                                            onResolve: { lines in
                                                vm.resolveConflictSection(
                                                    fileID: file.id,
                                                    sectionID: section.id,
                                                    with: lines
                                                )
                                            }
                                        )
                                        .padding(.horizontal)
                                    }
                                }
                            }
                            .padding(.top, 12)
                            // 下部バーのスペースを確保
                            .padding(.bottom, currentFile?.allResolved == true ? 140 : 16)
                        }
                    } else {
                        Spacer()
                    }
                }

                // 全解決時の下部バー
                if currentFile?.allResolved == true && vm.conflictFiles.allSatisfy(\.allResolved) {
                    mergeBottomBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .background(ObgitLiquidBackground())
            .navigationTitle("コンフリクト解決")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        if !vm.isResolvingConflicts { dismiss() }
                    }
                    .disabled(vm.isResolvingConflicts)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if totalUnresolved > 0 {
                        Text("\(totalUnresolved) 残")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(ObgitPalette.coral)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(ObgitPalette.coral.opacity(0.15))
                            )
                    } else {
                        Label("解決済み", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ObgitPalette.mint)
                    }
                }
            }
            .animation(.spring(response: 0.3), value: totalUnresolved)
        }
    }

    // MARK: - File Tab Bar

    private var fileTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.conflictFiles.indices, id: \.self) { idx in
                    let file = vm.conflictFiles[idx]
                    Button {
                        selectedFileIndex = idx
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(file.allResolved ? ObgitPalette.mint : ObgitPalette.coral)
                                .frame(width: 7, height: 7)
                            Text(URL(fileURLWithPath: file.relativePath).lastPathComponent)
                                .font(.system(.caption, design: .rounded).weight(.medium))
                                .foregroundStyle(selectedFileIndex == idx
                                    ? ObgitPalette.ink : ObgitPalette.secondaryInk)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selectedFileIndex == idx
                                    ? ObgitPalette.accent.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(ObgitPalette.shellSurfaceStrong.opacity(0.6))
    }

    // MARK: - Merge Bottom Bar

    private var mergeBottomBar: some View {
        VStack(spacing: 10) {
            Divider()
            VStack(spacing: 10) {
                TextField("マージコミットメッセージ", text: $commitMessage)
                    .textFieldStyle(.roundedBorder)
                    .disabled(vm.isResolvingConflicts)

                Button {
                    Task {
                        await vm.completeMerge(
                            message: commitMessage,
                            authorName: authorName,
                            authorEmail: authorEmail
                        )
                    }
                } label: {
                    if vm.isResolvingConflicts {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                            Text(vm.conflictResolutionProgress.isEmpty ? "処理中..." : vm.conflictResolutionProgress)
                        }
                    } else {
                        Label("マージコミット & プッシュ", systemImage: "arrow.triangle.merge")
                    }
                }
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(vm.isResolvingConflicts
                            ? ObgitPalette.mint.opacity(0.5)
                            : ObgitPalette.mint)
                )
                .disabled(vm.isResolvingConflicts ||
                          commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - ConflictSectionCard

private struct ConflictSectionCard: View {
    let section: ConflictSection
    let onResolve: ([String]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ヘッダー
            HStack {
                Image(systemName: section.isResolved
                    ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(section.isResolved ? ObgitPalette.mint : ObgitPalette.coral)
                Text(section.isResolved ? "解決済み" : "コンフリクト")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(section.isResolved ? ObgitPalette.mint : ObgitPalette.coral)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // 解決済みの場合は採用された内容のみ表示
            if section.isResolved, let resolved = section.resolvedLines {
                CodePanel(
                    label: "採用済み",
                    labelColor: ObgitPalette.mint,
                    lines: resolved
                )
            } else {
                // 未解決: 両側を横並び表示
                HStack(alignment: .top, spacing: 1) {
                    CodePanel(
                        label: "現在 (HEAD)",
                        labelColor: ObgitPalette.accent,
                        lines: section.oursLines
                    )
                    Divider()
                    CodePanel(
                        label: "受信",
                        labelColor: ObgitPalette.coral,
                        lines: section.theirsLines
                    )
                }

                Divider()

                // 採用ボタン
                HStack(spacing: 10) {
                    ResolutionButton(title: "現在を採用", color: ObgitPalette.accent) {
                        onResolve(section.oursLines)
                    }
                    ResolutionButton(title: "受信を採用", color: ObgitPalette.coral) {
                        onResolve(section.theirsLines)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ObgitPalette.shellSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    section.isResolved
                        ? ObgitPalette.mint.opacity(0.4)
                        : ObgitPalette.coral.opacity(0.4),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.07), radius: 8, x: 0, y: 4)
        .animation(.spring(response: 0.25), value: section.isResolved)
    }
}

// MARK: - CodePanel

private struct CodePanel: View {
    let label: String
    let labelColor: Color
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(labelColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(labelColor.opacity(0.08))

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if lines.isEmpty {
                        Text("（空）")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(ObgitPalette.secondaryInk)
                            .padding(8)
                    } else {
                        ForEach(lines.indices, id: \.self) { idx in
                            Text(lines[idx])
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(ObgitPalette.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 1)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - ResolutionButton

private struct ResolutionButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(color.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
