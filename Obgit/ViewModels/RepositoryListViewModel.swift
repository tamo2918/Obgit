import Foundation
import Combine

@MainActor
final class RepositoryListViewModel: ObservableObject {
    private let store = RepositoryStore.shared
    private var cancellables = Set<AnyCancellable>()

    var repositories: [RepositoryModel] { store.repositories }

    init() {
        // store の変更を View に転送する
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func delete(_ repo: RepositoryModel) {
        store.delete(repo)
    }
}
