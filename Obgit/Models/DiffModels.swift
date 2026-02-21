import Foundation

enum DiffLineKind: Sendable {
    case context
    case added
    case removed
}

extension DiffLineKind: Equatable {
    nonisolated static func == (lhs: DiffLineKind, rhs: DiffLineKind) -> Bool {
        switch (lhs, rhs) {
        case (.context, .context), (.added, .added), (.removed, .removed): return true
        default: return false
        }
    }
}

struct DiffLine: Identifiable, Sendable {
    let id = UUID()
    let kind: DiffLineKind
    let text: String
    let leftLineNumber: Int?   // removed / context のみ
    let rightLineNumber: Int?  // added / context のみ
}

struct DiffHunk: Identifiable, Sendable {
    let id = UUID()
    let lines: [DiffLine]
    let leftStart: Int
    let rightStart: Int
}

struct FileDiff: Sendable {
    let fileName: String
    let hunks: [DiffHunk]

    var isEmpty: Bool { hunks.isEmpty }

    var totalAdded: Int {
        hunks.flatMap(\.lines).filter { $0.kind == .added }.count
    }

    var totalRemoved: Int {
        hunks.flatMap(\.lines).filter { $0.kind == .removed }.count
    }
}
