import SwiftUI

struct RepositoryListView: View {
    @StateObject private var vm = RepositoryListViewModel()
    @State private var showAddSheet = false
    @State private var deletingRepo: RepositoryModel?
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.repositories.isEmpty {
                    emptyState
                } else {
                    repoList
                }
            }
            .navigationTitle("Obgit")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddRepositoryView()
            }
            .confirmationDialog(
                "リポジトリを削除",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("削除", role: .destructive) {
                    if let repo = deletingRepo {
                        vm.delete(repo)
                    }
                    deletingRepo = nil
                }
                Button("キャンセル", role: .cancel) {
                    deletingRepo = nil
                }
            } message: {
                if let repo = deletingRepo {
                    Text("「\(repo.name)」とローカルのクローンを削除します。この操作は取り消せません。")
                }
            }
        }
    }

    // MARK: - Views

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("リポジトリがありません", systemImage: "folder.badge.questionmark")
        } description: {
            Text("右上の + ボタンからリポジトリを追加してください。")
        } actions: {
            Button("リポジトリを追加") {
                showAddSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var repoList: some View {
        List {
            ForEach(vm.repositories) { repo in
                NavigationLink(destination: RepositoryDetailView(repo: repo)) {
                    RepositoryRowView(repo: repo)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deletingRepo = repo
                        showDeleteConfirm = true
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                }
            }
        }
    }
}

// MARK: - Row View

private struct RepositoryRowView: View {
    let repo: RepositoryModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: repo.isCloned ? "folder.fill" : "folder.badge.plus")
                .font(.title2)
                .foregroundStyle(repo.isCloned ? .blue : .secondary)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(repo.name)
                    .font(.headline)

                Text(repo.remoteURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let date = repo.lastPullDate {
                    Text("最終 Pull: \(date, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    RepositoryListView()
}
