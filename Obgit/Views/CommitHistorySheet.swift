import SwiftUI

struct CommitHistorySheet: View {
    @ObservedObject var vm: VaultWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if vm.commitLog.isEmpty {
                    ContentUnavailableView(
                        "コミット履歴がありません",
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        description: Text("Pull 後にリロードすると履歴が表示されます。")
                    )
                } else {
                    List {
                        ForEach(vm.commitLog) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.subject)
                                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                                    .foregroundStyle(ObgitPalette.ink)
                                    .lineLimit(2)

                                HStack(spacing: 8) {
                                    // 短縮ハッシュ
                                    Text(entry.shortHash)
                                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                                        .foregroundStyle(ObgitPalette.accent)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(ObgitPalette.accentSoft)
                                        )

                                    Image(systemName: "person.circle")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(ObgitPalette.secondaryInk)

                                    Text(entry.authorName)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(ObgitPalette.secondaryInk)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(Self.dateFormatter.string(from: entry.date))
                                        .font(.system(.caption2, design: .rounded))
                                        .foregroundStyle(ObgitPalette.secondaryInk)
                                }
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(ObgitLiquidBackground())
            .navigationTitle("コミット履歴")
            .navigationBarTitleDisplayMode(.inline)
            .tint(ObgitPalette.accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        vm.loadCommitLog()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .onAppear {
            if vm.commitLog.isEmpty {
                vm.loadCommitLog()
            }
        }
    }
}
