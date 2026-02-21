import SwiftUI

struct AddRepositoryView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var remoteURL = ""
    @State private var branch = "main"
    @State private var username = ""
    @State private var pat = ""
    @State private var showPAT = false

    private let store = RepositoryStore.shared

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("リポジトリ情報")) {
                    LabeledContent("表示名") {
                        TextField("my-vault", text: $name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("リモート URL") {
                        TextField("https://github.com/user/repo.git", text: $remoteURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .multilineTextAlignment(.trailing)
                    }

                    if isSSHURL {
                        Label("SSH URL は非対応です。HTTPS URL（https://...）を入力してください。", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    LabeledContent("ブランチ") {
                        TextField("main", text: $branch)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section(
                    header: Text("認証情報"),
                    footer: Text("PAT (Personal Access Token) は Keychain に暗号化して保存されます。\nGitHub: Settings → Developer settings → Personal access tokens")
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
                                TextField("ghp_xxxx...", text: $pat)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .multilineTextAlignment(.trailing)
                            } else {
                                SecureField("ghp_xxxx...", text: $pat)
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
            .navigationTitle("リポジトリを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") { save() }
                        .disabled(!isValid)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var isSSHURL: Bool {
        remoteURL.trimmingCharacters(in: .whitespaces).hasPrefix("git@")
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !remoteURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !isSSHURL &&
        !branch.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !pat.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedURL = remoteURL.trimmingCharacters(in: .whitespaces)
        let trimmedBranch = branch.trimmingCharacters(in: .whitespaces)
        let trimmedUser = username.trimmingCharacters(in: .whitespaces)
        let trimmedPAT = pat.trimmingCharacters(in: .whitespaces)

        let repo = RepositoryModel(
            name: trimmedName,
            remoteURL: trimmedURL,
            branch: trimmedBranch,
            username: trimmedUser
        )
        store.add(repo)
        // PAT を Keychain に保存
        KeychainService.shared.save(token: trimmedPAT, for: repo.id)
        dismiss()
    }
}

#Preview {
    AddRepositoryView()
}
