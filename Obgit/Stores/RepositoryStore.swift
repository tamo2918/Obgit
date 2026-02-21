import Foundation
import Combine

/// リポジトリ一覧を UserDefaults に永続化するストア
@MainActor
final class RepositoryStore: ObservableObject {
    static let shared = RepositoryStore()

    @Published private(set) var repositories: [RepositoryModel] = []

    private let key = "saved_repositories_v1"
    private let defaults = UserDefaults.standard

    private init() {
        load()
    }

    // MARK: CRUD

    func add(_ repo: RepositoryModel) {
        repositories.append(repo)
        save()
    }

    func update(_ repo: RepositoryModel) {
        guard let index = repositories.firstIndex(where: { $0.id == repo.id }) else { return }
        repositories[index] = repo
        save()
    }

    func delete(_ repo: RepositoryModel) {
        repositories.removeAll { $0.id == repo.id }
        // Keychain からも認証情報を削除
        KeychainService.shared.delete(for: repo.id)
        // ローカルディレクトリを削除
        try? FileManager.default.removeItem(at: repo.localURL)
        save()
    }

    // MARK: Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(repositories) else { return }
        defaults.set(data, forKey: key)
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let repos = try? JSONDecoder().decode([RepositoryModel].self, from: data) else {
            return
        }
        // ローカルに実際にクローンされているかを再チェック
        repositories = repos.map { repo in
            var updated = repo
            let exists = FileManager.default.fileExists(atPath: repo.localURL.path)
            if !exists { updated.isCloned = false }
            return updated
        }
    }
}
