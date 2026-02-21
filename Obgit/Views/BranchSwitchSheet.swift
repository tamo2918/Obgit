import SwiftUI

struct BranchSwitchSheet: View {
    @ObservedObject var vm: VaultWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if vm.isSwitchingBranch {
                    VStack(spacing: 20) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(ObgitPalette.accent)

                        Text(vm.branchSwitchProgress.isEmpty ? "切り替え中..." : vm.branchSwitchProgress)
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .foregroundStyle(ObgitPalette.secondaryInk)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.availableBranches.isEmpty {
                    ContentUnavailableView(
                        "ブランチが見つかりません",
                        systemImage: "arrow.triangle.branch",
                        description: Text("リモートブランチを取得できませんでした。ネットワーク接続を確認してください。")
                    )
                } else {
                    List {
                        Section {
                            ForEach(vm.availableBranches, id: \.self) { branch in
                                Button {
                                    Task { await vm.switchBranch(to: branch) }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(
                                            systemName: branch == vm.repo.branch
                                                ? "checkmark.circle.fill"
                                                : "circle"
                                        )
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(
                                            branch == vm.repo.branch
                                                ? ObgitPalette.accent
                                                : ObgitPalette.secondaryInk
                                        )

                                        Text(branch)
                                            .font(.system(.body, design: .rounded).weight(
                                                branch == vm.repo.branch ? .semibold : .regular
                                            ))
                                            .foregroundStyle(ObgitPalette.ink)

                                        Spacer()

                                        if branch == vm.repo.branch {
                                            Text("現在")
                                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                                .foregroundStyle(ObgitPalette.accent)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(
                                                    Capsule()
                                                        .fill(ObgitPalette.accentSoft)
                                                )
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                                .disabled(branch == vm.repo.branch)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        } header: {
                            Text("リモートブランチ")
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(ObgitPalette.secondaryInk)
                                .textCase(nil)
                        } footer: {
                            Text("ブランチを切り替えると、リモートの最新状態でワーキングディレクトリが上書きされます。")
                                .font(.caption)
                                .foregroundStyle(ObgitPalette.secondaryInk)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(ObgitLiquidBackground())
            .navigationTitle("ブランチ切り替え")
            .navigationBarTitleDisplayMode(.inline)
            .tint(ObgitPalette.accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .disabled(vm.isSwitchingBranch)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        vm.loadBranches()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(vm.isSwitchingBranch)
                }
            }
        }
        .onAppear {
            if vm.availableBranches.isEmpty {
                vm.loadBranches()
            }
        }
    }
}
