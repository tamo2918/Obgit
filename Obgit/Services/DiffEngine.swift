import Foundation

/// Myers O(ND) diff アルゴリズムで2テキスト間の差分を計算する
nonisolated final class DiffEngine: Sendable {

    static let shared = DiffEngine()
    private nonisolated init() {}

    /// 2つのテキストの差分を計算して FileDiff を返す
    nonisolated func diff(
        originalText: String,
        editedText: String,
        fileName: String,
        contextLines: Int = 3
    ) -> FileDiff {
        let left  = splitLines(originalText)
        let right = splitLines(editedText)
        let ops   = myersDiff(left: left, right: right)
        let hunks = buildHunks(ops: ops, left: left, right: right, contextLines: contextLines)
        return FileDiff(fileName: fileName, hunks: hunks)
    }

    // MARK: - Private: Split Lines

    private func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        // 末尾の空行を除去（テキスト末尾の改行によって生じる空要素）
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    // MARK: - Private: Myers Diff

    /// 編集操作の種類
    private enum EditOp {
        case equal(Int, Int)   // (left index, right index)
        case insert(Int)       // right index
        case delete(Int)       // left index
    }

    /// Myers の O(ND) アルゴリズムで最短編集スクリプトを求める
    private func myersDiff(left: [String], right: [String]) -> [EditOp] {
        let n = left.count
        let m = right.count

        if n == 0 && m == 0 { return [] }
        if n == 0 { return right.indices.map { .insert($0) } }
        if m == 0 { return left.indices.map  { .delete($0) } }

        let max = n + m
        // V[k + max] = x 座標（diagonal k 上の最遠点）
        var v = [Int](repeating: 0, count: 2 * max + 1)
        // スナップショット: trace[d] = d ステップ後の v 配列
        var trace: [[Int]] = []

        // 前進フェーズ: SES の長さ d を探す
        outer: for d in 0...max {
            trace.append(v)
            for k in stride(from: -d, through: d, by: 2) {
                let ki = k + max
                var x: Int
                if k == -d || (k != d && v[ki - 1] < v[ki + 1]) {
                    x = v[ki + 1]
                } else {
                    x = v[ki - 1] + 1
                }
                var y = x - k
                // snake（一致行を進む）
                while x < n && y < m && left[x] == right[y] {
                    x += 1
                    y += 1
                }
                v[ki] = x
                if x >= n && y >= m {
                    trace.append(v)
                    break outer
                }
            }
        }

        // バックトラックフェーズ
        var ops: [EditOp] = []
        var x = n
        var y = m

        for d in stride(from: trace.count - 1, through: 1, by: -1) {
            let vPrev = trace[d - 1]
            let k  = x - y
            let ki = k + max

            let prevK: Int
            if k == -(d - 1) || (k != (d - 1) && vPrev[ki - 1] < vPrev[ki + 1]) {
                prevK = k + 1
            } else {
                prevK = k - 1
            }

            let prevX = vPrev[prevK + max]
            let prevY = prevX - prevK

            // snake を逆順に equal として追加
            while x > prevX + 1 && y > prevY + 1 {
                x -= 1
                y -= 1
                ops.append(.equal(x, y))
            }

            if d > 0 {
                if x == prevX {
                    // insert（右のみ進んだ）
                    y -= 1
                    ops.append(.insert(y))
                } else {
                    // delete（左のみ進んだ）
                    x -= 1
                    ops.append(.delete(x))
                }
            }
        }

        // 残りの snake（先頭部分）
        while x > 0 && y > 0 {
            x -= 1
            y -= 1
            ops.append(.equal(x, y))
        }

        return ops.reversed()
    }

    // MARK: - Private: Build Hunks

    private func buildHunks(
        ops: [EditOp],
        left: [String],
        right: [String],
        contextLines: Int
    ) -> [DiffHunk] {
        // 差分がない場合
        let hasDiff = ops.contains { if case .equal = $0 { return false } else { return true } }
        if !hasDiff { return [] }

        // まず全行を DiffLine に変換
        var allLines: [DiffLine] = []
        for op in ops {
            switch op {
            case .equal(let li, let ri):
                allLines.append(DiffLine(
                    kind: .context, text: left[li],
                    leftLineNumber: li + 1, rightLineNumber: ri + 1
                ))
            case .insert(let ri):
                allLines.append(DiffLine(
                    kind: .added, text: right[ri],
                    leftLineNumber: nil, rightLineNumber: ri + 1
                ))
            case .delete(let li):
                allLines.append(DiffLine(
                    kind: .removed, text: left[li],
                    leftLineNumber: li + 1, rightLineNumber: nil
                ))
            }
        }

        // 変更行のインデックスを収集
        let changedIndices = allLines.indices.filter { allLines[$0].kind != .context }
        guard !changedIndices.isEmpty else { return [] }

        // context 範囲でグループ化
        var groups: [[Int]] = []
        var currentGroup: [Int] = []

        for idx in changedIndices {
            let start = max(0, idx - contextLines)
            let end   = min(allLines.count - 1, idx + contextLines)
            let range = Array(start...end)

            if currentGroup.isEmpty {
                currentGroup = range
            } else if let last = currentGroup.last, start <= last + 1 {
                // 前のグループと重なる or 隣接
                let merged = Array(Set(currentGroup + range)).sorted()
                currentGroup = merged
            } else {
                groups.append(currentGroup)
                currentGroup = range
            }
        }
        if !currentGroup.isEmpty { groups.append(currentGroup) }

        // グループを DiffHunk に変換
        return groups.compactMap { indices -> DiffHunk? in
            let lines = indices.map { allLines[$0] }
            guard let firstLeft  = lines.compactMap(\.leftLineNumber).first,
                  let firstRight = lines.compactMap(\.rightLineNumber).first else { return nil }
            return DiffHunk(lines: lines, leftStart: firstLeft, rightStart: firstRight)
        }
    }
}
