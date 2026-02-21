import Foundation
import Combine

// MARK: - Data Model

struct FileSearchResult: Identifiable, Sendable {
    let id = UUID()
    let fileURL: URL
    let fileName: String
    /// 空 = ファイル名が一致。非空 = 本文中の一致行
    let lineMatches: [LineMatch]

    var isFileNameMatch: Bool { lineMatches.isEmpty }

    struct LineMatch: Identifiable, Sendable {
        let id = UUID()
        let lineNumber: Int
        let text: String
    }
}

// MARK: - ViewModel

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var results: [FileSearchResult] = []
    @Published private(set) var isSearching = false

    private var searchTask: Task<Void, Never>?
    private let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    func onQueryChange() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)

        guard !q.isEmpty else {
            results = []
            isSearching = false
            return
        }

        isSearching = true

        searchTask = Task { [weak self, rootURL] in
            // 280ms debounce
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }

            let found = await Task.detached(priority: .userInitiated) {
                SearchViewModel.performSearch(query: q, in: rootURL)
            }.value

            guard !Task.isCancelled else { return }
            self?.results = found
            self?.isSearching = false
        }
    }

    // MARK: - Search Logic (nonisolated, background-safe)

    nonisolated private static func performSearch(query: String, in rootURL: URL) -> [FileSearchResult] {
        let allFiles = collectMarkdownFiles(at: rootURL)
        var results: [FileSearchResult] = []
        let lowQuery = query.lowercased()

        for fileURL in allFiles {
            let fileName = fileURL.lastPathComponent

            // ファイル名が一致する場合
            if fileName.lowercased().contains(lowQuery) {
                results.append(FileSearchResult(fileURL: fileURL, fileName: fileName, lineMatches: []))
                continue
            }

            // 本文検索
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            let lines = content.components(separatedBy: .newlines)
            var lineMatches: [FileSearchResult.LineMatch] = []

            for (index, line) in lines.enumerated() {
                guard line.lowercased().contains(lowQuery) else { continue }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                lineMatches.append(FileSearchResult.LineMatch(lineNumber: index + 1, text: trimmed))
                if lineMatches.count >= 3 { break }   // ファイルあたり最大3行
            }

            if !lineMatches.isEmpty {
                results.append(FileSearchResult(fileURL: fileURL, fileName: fileName, lineMatches: lineMatches))
            }
        }

        return results
    }

    nonisolated private static func collectMarkdownFiles(at rootURL: URL) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []

        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == false else { continue }
            let ext = fileURL.pathExtension.lowercased()
            if ext == "md" || ext == "markdown" {
                result.append(fileURL)
            }
        }

        return result
    }
}
