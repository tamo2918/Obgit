import Foundation

struct CommitEntry: Identifiable, Sendable {
    let shortHash: String
    let authorName: String
    let date: Date
    let subject: String  // コミットメッセージの先頭行

    var id: String { shortHash }
}
