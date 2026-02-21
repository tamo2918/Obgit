import SwiftUI

struct RepositoryDetailView: View {
    @StateObject private var vm: RepositoryDetailViewModel
    @State private var showEditCredential = false
    @State private var showRecloneConfirm = false

    init(repo: RepositoryModel) {
        _vm = StateObject(wrappedValue: RepositoryDetailViewModel(repo: repo))
    }

    var body: some View {
        List {
            // ステータスセクション
            statusSection

            // 保存場所セクション
            saveLocationSection

            // メインアクションセクション
            actionSection

            // ログセクション（常時表示）
            logSection
        }
        .navigationTitle(vm.repo.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showEditCredential = true
                    } label: {
                        Label("認証情報を編集", systemImage: "key")
                    }

                    if vm.repo.isCloned {
                        Button(role: .destructive) {
                            showRecloneConfirm = true
                        } label: {
                            Label("再クローン", systemImage: "arrow.clockwise")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(vm.isLoading)
            }
        }
        .sheet(isPresented: $showEditCredential) {
            EditCredentialView(vm: vm)
        }
        .confirmationDialog(
            "再クローン",
            isPresented: $showRecloneConfirm,
            titleVisibility: .visible
        ) {
            Button("再クローンする", role: .destructive) {
                vm.startReclone()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("既存のクローンを削除して再クローンします。")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var statusSection: some View {
        Section {
            LabeledContent("リモート") {
                Text(vm.repo.remoteURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent("ブランチ") {
                Text(vm.repo.branch)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("ステータス") {
                if vm.repo.isCloned {
                    Label("クローン済み", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                } else {
                    Label("未クローン", systemImage: "circle")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }

            if let date = vm.repo.lastPullDate {
                LabeledContent("最終 Pull") {
                    Text(date, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var saveLocationSection: some View {
        Section(
            header: Text("保存場所"),
            footer: Text("ファイル → このiPhone/iPad → Obgit → Repositories → \(vm.repo.localDirName)")
        ) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Repositories / \(vm.repo.localDirName)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(vm.repo.localURL.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        Section {
            if vm.isLoading {
                // ローディング中はリアルタイムログを表示
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(vm.progressMessage.isEmpty ? "処理中..." : vm.progressMessage)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    if !vm.progressLogs.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(vm.progressLogs, id: \.self) { log in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("›")
                                        .foregroundStyle(.tertiary)
                                        .font(.caption)
                                    Text(log)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.leading, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else {
                // エラーメッセージ
                if let error = vm.errorMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }

                // 成功メッセージ
                if let success = vm.successMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(success)
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                }

                // アクションボタン
                if !vm.repo.isCloned {
                    Button {
                        vm.startClone()
                    } label: {
                        Label("Clone を実行", systemImage: "arrow.down.to.line")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .disabled(!vm.hasCredential)
                } else {
                    Button {
                        vm.startPull()
                    } label: {
                        Label("Pull を実行", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                if !vm.hasCredential {
                    HStack(spacing: 6) {
                        Image(systemName: "key.slash")
                            .foregroundStyle(.orange)
                        Text("PAT が設定されていません。右上のメニューから設定してください。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var logSection: some View {
        Section(header: Text("操作ログ")) {
            if vm.repo.logs.isEmpty {
                Text("まだ操作を行っていません")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(vm.repo.logs) { log in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: log.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(log.isError ? .red : .green)
                            .font(.caption)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.message)
                                .font(.caption)
                                .foregroundStyle(log.isError ? .red : .primary)
                            Text(log.date, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - EditCredentialView

struct EditCredentialView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RepositoryDetailViewModel

    @State private var username: String
    @State private var pat = ""
    @State private var showPAT = false

    init(vm: RepositoryDetailViewModel) {
        self.vm = vm
        _username = State(initialValue: vm.repo.username)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    header: Text("認証情報"),
                    footer: Text("PAT を空欄にすると既存の PAT はそのまま保持されます。")
                ) {
                    LabeledContent("ユーザー名") {
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("PAT") {
                        HStack {
                            if showPAT {
                                TextField("新しい PAT (空欄=変更なし)", text: $pat)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .multilineTextAlignment(.trailing)
                            } else {
                                SecureField("新しい PAT (空欄=変更なし)", text: $pat)
                                    .multilineTextAlignment(.trailing)
                            }
                            Button {
                                showPAT.toggle()
                            } label: {
                                Image(systemName: showPAT ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("認証情報を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        vm.updateCredentials(username: username, token: pat)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
