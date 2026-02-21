import SwiftUI
import FoundationModels
import UIKit

struct CommitDialogView: View {
    @ObservedObject var vm: VaultWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var message = ""
    @State private var isGenerating = false
    @State private var aiError: String?
    @State private var showAISetupAlert = false
    @State private var showDiff = false

    // UserDefaults に永続保存
    @AppStorage("commit_author_name") private var authorName = ""
    @AppStorage("commit_author_email") private var authorEmail = ""

    private var canPush: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !authorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !authorEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !vm.isCommitting
            && !isGenerating
    }

    var body: some View {
        NavigationStack {
            Form {
                // コミットメッセージ入力
                Section {
                    TextField("変更内容を入力...", text: $message, axis: .vertical)
                        .lineLimit(3...6)
                        .disabled(vm.isCommitting || isGenerating)
                } header: {
                    Text("コミットメッセージ")
                } footer: {
                    Text("変更内容を簡潔に記述してください。")
                }

                // AI生成 & テンプレートチップ
                Section {
                    suggestionRow

                    // AI エラー表示（発生時のみ）
                    if let aiError {
                        Text(aiError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("候補")
                }

                // 差分プレビュー
                Section {
                    Button {
                        showDiff = true
                    } label: {
                        Label("変更差分を表示", systemImage: "plusminus.circle.fill")
                            .foregroundStyle(ObgitPalette.accent)
                    }
                    .disabled(vm.isCommitting)
                } header: {
                    Text("差分")
                }

                // 作成者情報
                Section {
                    LabeledContent("名前") {
                        TextField("Your Name", text: $authorName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                            .disabled(vm.isCommitting)
                    }
                    LabeledContent("メール") {
                        TextField("email@example.com", text: $authorEmail)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                            .multilineTextAlignment(.trailing)
                            .disabled(vm.isCommitting)
                    }
                } header: {
                    Text("作成者")
                } footer: {
                    Text("次回以降は自動で入力されます。")
                }

                // コミット進捗
                if vm.isCommitting {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(ObgitPalette.accent)
                            Text(vm.commitProgress.isEmpty ? "処理中..." : vm.commitProgress)
                                .font(.subheadline)
                                .foregroundStyle(ObgitPalette.secondaryInk)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Git エラー
                if let error = vm.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ObgitLiquidBackground())
            .sheet(isPresented: $showDiff) {
                DiffSheet(
                    originalText: vm.snapshotBeforeEdit,
                    editedText: vm.editedText,
                    fileName: vm.selectedFileURL?.lastPathComponent ?? "ファイル"
                )
            }
            .navigationTitle("コミット & プッシュ")
            .navigationBarTitleDisplayMode(.inline)
            .tint(ObgitPalette.accent)
            .onAppear {
                if authorName.isEmpty {
                    authorName = vm.repo.username.isEmpty ? "Obgit User" : vm.repo.username
                }
                if authorEmail.isEmpty {
                    authorEmail = "\(vm.repo.username)@users.noreply.github.com"
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        if !vm.isCommitting {
                            vm.errorMessage = nil
                            dismiss()
                        }
                    }
                    .disabled(vm.isCommitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        // キーボードを先に閉じてから UI を更新する
                        // （同期的な isCommitting = true による再描画でキーボードが
                        //   再表示されるのを防ぐ）
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        vm.isCommitting = true
                        Task {
                            await vm.commitAndPush(
                                message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                                authorName: authorName.trimmingCharacters(in: .whitespacesAndNewlines),
                                authorEmail: authorEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                        }
                    } label: {
                        Label("プッシュ", systemImage: "arrow.up.circle.fill")
                            .fontWeight(.semibold)
                    }
                    .disabled(!canPush)
                }
            }
        }
    }

    // MARK: - Suggestion Row

    private var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // AI ボタン: SystemLanguageModel を直接参照して SwiftUI の観察チェーンに乗せる
                if #available(iOS 26.0, *) {
                    aiButtonView
                }

                // テンプレートチップ（常時表示）
                ForEach(CommitMessageGenerator.templates, id: \.self) { template in
                    Button {
                        message = template
                        aiError = nil
                    } label: {
                        Text(template)
                            .font(.system(.subheadline, design: .rounded))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.secondary.opacity(0.10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Color.secondary.opacity(0.20), lineWidth: 1)
                                    )
                            )
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isCommitting || isGenerating)
                }
            }
            .padding(.vertical, 2)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    // MARK: - AI Button（Observable 経由で availability を監視）

    @available(iOS 26.0, *)
    @ViewBuilder
    private var aiButtonView: some View {
        // ここで SystemLanguageModel.default.availability を直接参照することで
        // SwiftUI の Observation チェーンが確立され、状態変化時に View が再描画される
        switch SystemLanguageModel.default.availability {

        case .available:
            // 利用可能: AI生成ボタン（機能あり）
            Button {
                Task { await generateWithAI() }
            } label: {
                HStack(spacing: 5) {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Color.purple)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text("AI生成")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.purple.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.purple.opacity(0.35), lineWidth: 1)
                        )
                )
                .foregroundStyle(Color.purple)
            }
            .buttonStyle(.plain)
            .disabled(isGenerating || vm.isCommitting)

        case .unavailable(.appleIntelligenceNotEnabled):
            // 機種は対応しているが Apple Intelligence が未有効化
            Button {
                showAISetupAlert = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("AI生成")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        Text("Apple Intelligence を有効化")
                            .font(.system(size: 9, design: .rounded))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.20), lineWidth: 1)
                        )
                )
                .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)
            .alert("Apple Intelligence を有効化", isPresented: $showAISetupAlert) {
                Button("設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("設定アプリ → 「Apple Intelligence & Siri」→ 画面上部の「Apple Intelligence」をオンにしてください。\n\nその後、モデルのダウンロードが完了するまでしばらくお待ちください。")
            }

        case .unavailable:
            // deviceNotEligible など: ボタン非表示（テンプレートのみ）
            EmptyView()
        }
    }

    // MARK: - AI Generation

    @available(iOS 26.0, *)
    private func generateWithAI() async {
        guard !isGenerating else { return }
        isGenerating = true
        aiError = nil

        let fileName = vm.selectedFileURL?.lastPathComponent ?? "不明なファイル"
        let original = vm.snapshotBeforeEdit
        let edited   = vm.editedText

        do {
            let generated = try await CommitMessageGenerator.generate(
                fileName: fileName,
                original: original,
                edited: edited
            )
            message = generated
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation:
                aiError = "コンテンツポリシーにより生成できませんでした。手動で入力してください。"
            case .assetsUnavailable:
                aiError = "モデルが準備中です。しばらくしてから再試行してください。"
            case .rateLimited:
                aiError = "リクエストが多すぎます。しばらくしてから再試行してください。"
            default:
                aiError = "AI生成に失敗しました。テンプレートをご利用ください。"
            }
        } catch {
            aiError = error.localizedDescription
        }

        isGenerating = false
    }
}
