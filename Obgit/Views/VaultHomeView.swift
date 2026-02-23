import SwiftUI
import MarkdownUI

struct VaultHomeView: View {
    @ObservedObject private var store = RepositoryStore.shared
    @AppStorage("selected_cloned_repository_id") private var selectedClonedRepositoryID = ""
    @State private var showCloneSheet = false

    private var clonedRepositories: [RepositoryModel] {
        store.repositories
            .filter(\.isCloned)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var notClonedRepositories: [RepositoryModel] {
        store.repositories
            .filter { !$0.isCloned }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var selectedRepository: RepositoryModel? {
        if let id = UUID(uuidString: selectedClonedRepositoryID),
           let repo = clonedRepositories.first(where: { $0.id == id }) {
            return repo
        }
        return clonedRepositories.first
    }

    var body: some View {
        Group {
            if clonedRepositories.isEmpty {
                NavigationStack {
                    CloneRepositoryScreen(
                        existingDrafts: notClonedRepositories,
                        onComplete: { repo in
                            selectedClonedRepositoryID = repo.id.uuidString
                        }
                    )
                }
            } else if let selectedRepository {
                VaultWorkspaceShellView(
                    repositories: clonedRepositories,
                    selectedRepository: selectedRepository,
                    onSelectRepository: { repo in
                        selectedClonedRepositoryID = repo.id.uuidString
                    },
                    onAddRepository: {
                        showCloneSheet = true
                    }
                )
                .id(selectedRepository.id)
                .sheet(isPresented: $showCloneSheet) {
                    NavigationStack {
                        CloneRepositoryScreen(
                            existingDrafts: notClonedRepositories,
                            onComplete: { repo in
                                selectedClonedRepositoryID = repo.id.uuidString
                                showCloneSheet = false
                            },
                            onCancel: {
                                showCloneSheet = false
                            }
                        )
                    }
                }
            }
        }
        .onAppear(perform: normalizeSelection)
        .onChange(of: clonedRepositories.map(\.id)) { _, _ in
            normalizeSelection()
        }
    }

    private func normalizeSelection() {
        guard !clonedRepositories.isEmpty else {
            selectedClonedRepositoryID = ""
            return
        }
        if selectedRepository == nil {
            selectedClonedRepositoryID = clonedRepositories[0].id.uuidString
        }
    }
}

// MARK: - Clone Screen

private struct CloneRepositoryScreen: View {
    let existingDrafts: [RepositoryModel]
    let onComplete: (RepositoryModel) -> Void
    var onCancel: (() -> Void)? = nil

    @StateObject private var vm = CloneRepositoryViewModel()
    @State private var showPAT = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Obsidian Vault を Clone")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("最初にリポジトリをクローンすると、以降はファイルツリーと Markdown ビューアが表示されます。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if !existingDrafts.isEmpty {
                Section("保存済み設定を再利用") {
                    ForEach(existingDrafts) { repo in
                        Button {
                            vm.applyPreset(repo)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(repo.name)
                                        .fontWeight(.medium)
                                    Text(repo.remoteURL)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                    }
                }
            }

            Section("リポジトリ情報") {
                LabeledContent("表示名") {
                    TextField("my-vault", text: $vm.name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("リモート URL") {
                    TextField("https://github.com/user/repo.git", text: $vm.remoteURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("ブランチ") {
                    TextField("main", text: $vm.branch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                LabeledContent("ユーザー名") {
                    TextField(vm.isSSHURL ? "git" : "username", text: $vm.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }

                if vm.isSSHURL {
                    // SSH 認証フィールド
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SSH 秘密鍵（PEM 形式）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $vm.sshPrivateKey)
                            .font(.system(.caption, design: .monospaced))
                            .frame(height: 120)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    LabeledContent("パスフレーズ") {
                        SecureField("（省略可）", text: $vm.sshPassphrase)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                } else {
                    // HTTPS 認証フィールド
                    LabeledContent("PAT") {
                        HStack(spacing: 8) {
                            Group {
                                if showPAT {
                                    TextField("ghp_xxxx...", text: $vm.pat)
                                } else {
                                    SecureField("ghp_xxxx...", text: $vm.pat)
                                }
                            }
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)

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
            } header: {
                Text("認証情報")
            } footer: {
                if vm.isSSHURL {
                    Text("SSH 秘密鍵とパスフレーズは iOS Keychain に暗号化保存されます。")
                } else {
                    Text("PAT は iOS Keychain に暗号化保存されます。")
                }
            }

            if vm.isCloning {
                Section("クローン中") {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(vm.progressMessage.isEmpty ? "処理中..." : vm.progressMessage)
                            .font(.subheadline)
                    }
                    ForEach(vm.progressLogs, id: \.self) { log in
                        Text("• \(log)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let error = vm.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            if let success = vm.successMessage {
                Section {
                    Label(success, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            if !vm.isCloning {
                Section {
                    Button {
                        // タップ直後に触覚フィードバック（ラグを感じさせない）
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task {
                            if let repo = await vm.startClone() {
                                // 成功時の触覚フィードバック
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                onComplete(repo)
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Clone を実行", systemImage: "arrow.down.to.line")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!vm.isFormValid)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(ObgitLiquidBackground())
        .tint(ObgitPalette.accent)
        .navigationTitle("Clone")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        onCancel()
                    }
                }
            }
        }
    }
}

// MARK: - Workspace

private struct VaultWorkspaceShellView: View {
    let repositories: [RepositoryModel]
    let selectedRepository: RepositoryModel
    let onSelectRepository: (RepositoryModel) -> Void
    let onAddRepository: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var vm: VaultWorkspaceViewModel
    @State private var isSidebarOpen = false
    @State private var dragTranslation: CGFloat = 0
    @State private var showRawText = false
    @State private var showSearch = false
    @State private var showDiscardConfirm = false
    @State private var showSettings = false
    @State private var repoToEdit: RepositoryModel? = nil
    @State private var repoToDelete: RepositoryModel? = nil
    @State private var showDeleteConfirm = false
    @State private var toastText: String? = nil
    @State private var toastIsError = false
    @State private var fileTreeID = UUID()
    @State private var hasAppearedOnce = false
    private let toastDisplayDuration: TimeInterval = 1.8

    init(
        repositories: [RepositoryModel],
        selectedRepository: RepositoryModel,
        onSelectRepository: @escaping (RepositoryModel) -> Void,
        onAddRepository: @escaping () -> Void
    ) {
        self.repositories = repositories
        self.selectedRepository = selectedRepository
        self.onSelectRepository = onSelectRepository
        self.onAddRepository = onAddRepository
        _vm = StateObject(wrappedValue: VaultWorkspaceViewModel(repo: selectedRepository))
    }

    var body: some View {
        GeometryReader { proxy in
            let sidebarWidth = min(proxy.size.width * 0.82, 340)
            let progress = sidebarProgress(width: sidebarWidth)

            ZStack(alignment: .leading) {
                ObgitLiquidBackground()

                // メインコンテンツ：サイドバー開閉に合わせて右にシフト、Pull中はぼかし
                VaultMainPaneView(
                    vm: vm,
                    showRawText: $showRawText,
                    showDiscardConfirm: $showDiscardConfirm,
                    onToggleSidebar: toggleSidebar
                )
                .offset(x: sidebarWidth * 0.30 * progress)
                .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.84), value: progress)
                .disabled(isSidebarOpen || vm.isPulling || vm.isCommitting)
                .blur(radius: (vm.isPulling || vm.isCommitting) ? 3.5 : 0)
                .animation(.easeInOut(duration: 0.25), value: vm.isPulling)
                .animation(.easeInOut(duration: 0.25), value: vm.isCommitting)

                // Pull中 / Commit中のディム効果
                if vm.isPulling || vm.isCommitting {
                    Color.black.opacity(0.10)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .zIndex(0.5)
                }

                // ディミング層：タップで閉じる
                if progress > 0.001 {
                    Color.black
                        .opacity(0.28 * progress)
                        .ignoresSafeArea()
                        .onTapGesture {
                            closeSidebar()
                        }
                        .zIndex(1)
                }

                // サイドバー本体
                VaultSidebarView(
                    vm: vm,
                    repositories: repositories,
                    selectedRepository: selectedRepository,
                    fileTreeID: fileTreeID,
                    showSearch: $showSearch,
                    showSettings: $showSettings,
                    onSelectRepository: onSelectRepository,
                    onAddRepository: onAddRepository,
                    onCloseSidebar: closeSidebar,
                    onReloadFileTree: {
                        vm.reloadFileTree()
                        fileTreeID = UUID()
                    },
                    onEditRepository: { repo in
                        closeSidebar()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                            repoToEdit = repo
                        }
                    },
                    onDeleteRepository: { repo in
                        repoToDelete = repo
                        showDeleteConfirm = true
                        closeSidebar()
                    },
                    width: sidebarWidth
                )
                .offset(x: -sidebarWidth + sidebarWidth * progress)
                .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.84), value: progress)
                .zIndex(2)
            }
            // ディミング層のクローズドラッグ（サイドバーが開いているとき画面全体で左スワイプ）
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        if isSidebarOpen {
                            if value.translation.width < 0 {
                                dragTranslation = value.translation.width
                            }
                        } else {
                            if value.translation.width > 0 && value.startLocation.x <= 50 {
                                dragTranslation = value.translation.width
                            }
                        }
                    }
                    .onEnded { value in
                        let predictedTranslation: CGFloat
                        if isSidebarOpen {
                            predictedTranslation = min(0, value.predictedEndTranslation.width)
                        } else {
                            predictedTranslation = max(0, value.predictedEndTranslation.width)
                        }
                        finishDrag(width: sidebarWidth, predictedTranslation: predictedTranslation)
                    }
            )
        }
        .onChange(of: isSidebarOpen) { _, _ in
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
        .onChange(of: vm.operationMessage) { _, newValue in
            guard let msg = newValue else { return }
            showToast(msg, isError: false)
        }
        .onChange(of: vm.errorMessage) { _, newValue in
            guard let msg = newValue else { return }
            showToast(msg, isError: true)
        }
        .onAppear {
            // 初回表示時（cold start）に自動 pull
            if !hasAppearedOnce {
                hasAppearedOnce = true
                vm.pullLatest()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // バックグラウンドから復帰時に自動 pull
            if newPhase == .active {
                vm.pullLatest()
            }
        }
        .overlay(alignment: .top) {
            // Pull中: Loading Toast を表示し続ける
            // Pull完了/エラー: 通常 Toast を一時表示
            Group {
                if vm.isPulling {
                    LoadingToastView(
                        text: vm.progressMessage.isEmpty ? "チェック中..." : vm.progressMessage
                    )
                } else if let text = toastText {
                    ToastNotificationView(text: text, isError: toastIsError)
                }
            }
            .padding(.top, 56)
            .padding(.horizontal, 20)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.42, dampingFraction: 0.74), value: vm.isPulling)
            .animation(.spring(response: 0.42, dampingFraction: 0.74), value: toastText)
        }
        .sheet(isPresented: $showSearch) {
            SearchSheetView(rootURL: vm.repo.localURL) { url in
                vm.selectFile(at: url)
            }
        }
        .sheet(isPresented: $vm.showCommitDialog) {
            CommitDialogView(vm: vm)
        }
        .sheet(isPresented: $vm.showCommitHistory) {
            CommitHistorySheet(vm: vm)
        }
        .sheet(isPresented: $vm.showBranchSwitch) {
            BranchSwitchSheet(vm: vm)
        }
        .sheet(isPresented: $vm.showConflictResolution) {
            ConflictResolutionSheet(vm: vm)
        }
        .sheet(isPresented: $showSettings) {
            AppearanceSettingsSheet()
        }
        .confirmationDialog(
            "変更を破棄しますか？",
            isPresented: $showDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button("変更を破棄", role: .destructive) {
                vm.cancelEditing()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("編集内容は保存されません。")
        }
        // リポジトリ削除確認
        .confirmationDialog(
            "「\(repoToDelete?.name ?? "")」を削除しますか？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                if let repo = repoToDelete {
                    RepositoryStore.shared.delete(repo)
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    repoToDelete = nil
                }
            }
            Button("キャンセル", role: .cancel) {
                repoToDelete = nil
            }
        } message: {
            Text("ローカルのクローンと Keychain に保存された認証情報が削除されます。この操作は元に戻せません。")
        }
        // リポジトリ設定編集
        .sheet(item: $repoToEdit) { repo in
            RepositoryEditSheet(repo: repo)
        }
    }

    private func sidebarProgress(width: CGFloat) -> CGFloat {
        let base: CGFloat = isSidebarOpen ? 1 : 0
        return min(1, max(0, base + (dragTranslation / width)))
    }

    private func toggleSidebar() {
        withAnimation(.spring(response: 0.40, dampingFraction: 0.76)) {
            isSidebarOpen.toggle()
            dragTranslation = 0
        }
    }

    private func closeSidebar() {
        withAnimation(.spring(response: 0.40, dampingFraction: 0.76)) {
            isSidebarOpen = false
            dragTranslation = 0
        }
    }

    private func showToast(_ text: String, isError: Bool) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) {
            toastText = text
            toastIsError = isError
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + toastDisplayDuration) {
            withAnimation(.easeOut(duration: 0.28)) {
                toastText = nil
            }
        }
    }

    private func finishDrag(width: CGFloat, predictedTranslation: CGFloat) {
        let base: CGFloat = isSidebarOpen ? 1 : 0
        let projectedProgress = min(1, max(0, base + (predictedTranslation / width)))

        withAnimation(.spring(response: 0.40, dampingFraction: 0.76)) {
            isSidebarOpen = projectedProgress > 0.5
            dragTranslation = 0
        }
    }
}

// MARK: - Main Pane

private struct VaultMainPaneView: View {
    @ObservedObject var vm: VaultWorkspaceViewModel
    @Binding var showRawText: Bool
    @Binding var showDiscardConfirm: Bool
    let onToggleSidebar: () -> Void
    @State private var isQuickMenuOpen = false

    var body: some View {
        let isMarkdownOpen = vm.selectedFileURL != nil && !vm.selectedFileIsImage

        ZStack(alignment: .bottomTrailing) {
            Group {
                if let fileURL = vm.selectedFileURL {
                    if vm.selectedFileIsImage {
                        ImageViewerContent(url: fileURL)
                            .id(fileURL)
                    } else if vm.isEditing {
                        TextEditor(text: $vm.editedText)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(ObgitPalette.ink)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    } else {
                        ScrollView {
                            if showRawText {
                                Text(vm.selectedMarkdownText)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(ObgitPalette.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 22)
                                    .padding(.vertical, 20)
                            } else {
                                Markdown(MarkdownProcessor.processForPreview(vm.selectedMarkdownText))
                                    .markdownTextStyle(\.text) {
                                        FontSize(17)
                                        ForegroundColor(ObgitPalette.ink)
                                    }
                                    .markdownTextStyle(\.code) {
                                        FontFamilyVariant(.monospaced)
                                        BackgroundColor(ObgitPalette.shellSurfaceStrong)
                                    }
                                    .foregroundStyle(ObgitPalette.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 22)
                                    .padding(.vertical, 20)
                                    .environment(\.openURL, OpenURLAction { url in
                                        guard let name = MarkdownProcessor.noteName(from: url) else {
                                            return .systemAction
                                        }
                                        if let targetURL = vm.findFile(named: name) {
                                            vm.selectFile(at: targetURL)
                                        } else {
                                            vm.errorMessage = "「\(name)」が見つかりませんでした"
                                        }
                                        return .handled
                                    })
                            }
                        }
                        .scrollIndicators(.hidden)
                        .background(Color.clear)
                    }
                } else {
                    ContentUnavailableView(
                        "ファイルを選択してください",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("サイドバーで `.md` または画像ファイルを選択してください。")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ObgitPalette.shellSurface)

            if isQuickMenuOpen && !vm.isEditing {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeQuickMenu()
                    }
            }

            if vm.isEditing {
                HStack(spacing: 10) {
                    editorActionButton(
                        title: "プッシュ",
                        systemImage: "arrow.up.circle.fill",
                        tint: ObgitPalette.accent
                    ) {
                        vm.showCommitDialog = true
                    }
                    .disabled(!vm.isDirty)
                    .opacity(vm.isDirty ? 1.0 : 0.58)

                    editorActionButton(
                        title: "完了",
                        systemImage: "checkmark.circle",
                        tint: ObgitPalette.mint
                    ) {
                        if vm.isDirty {
                            showDiscardConfirm = true
                        } else {
                            vm.cancelEditing()
                        }
                    }
                }
                .padding(.trailing, 18)
                .padding(.top, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .disabled(vm.isPulling || vm.isCommitting)
            } else {
                VStack(alignment: .trailing, spacing: 10) {
                    if isQuickMenuOpen {
                        quickMenuPanel(isMarkdownOpen: isMarkdownOpen)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                            isQuickMenuOpen.toggle()
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(isQuickMenuOpen ? ObgitPalette.accent : ObgitPalette.ink)
                            .rotationEffect(.degrees(isQuickMenuOpen ? 45 : 0))
                    }
                    .obgitIconChip(size: 56, cornerRatio: 0.36)
                    .overlay {
                        if isQuickMenuOpen {
                            RoundedRectangle(cornerRadius: 56 * 0.36, style: .continuous)
                                .strokeBorder(ObgitPalette.accent.opacity(0.90), lineWidth: 1.6)
                        }
                    }
                    .animation(.spring(response: 0.28, dampingFraction: 0.80), value: isQuickMenuOpen)
                }
                .padding(.trailing, 18)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .disabled(vm.isPulling || vm.isCommitting)
            }
        }
        .toolbar {
            if vm.isEditing {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        dismissKeyboard()
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .accessibilityLabel("キーボードを閉じる")
                }
            }
        }
        .onChange(of: vm.isEditing) { _, isEditing in
            if isEditing {
                closeQuickMenu(animated: false)
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func editorActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.96))
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.96), tint.opacity(0.74)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: tint.opacity(0.35), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    private func quickMenuPanel(isMarkdownOpen: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            quickActionButton("サイドバーを開く", systemImage: "line.3.horizontal") {
                closeQuickMenu(afterClose: {
                    onToggleSidebar()
                })
            }

            if isMarkdownOpen {
                quickActionButton(
                    showRawText ? "Preview 表示" : "Raw 表示",
                    systemImage: showRawText ? "doc.richtext" : "doc.plaintext"
                ) {
                    closeQuickMenu(afterClose: {
                        showRawText.toggle()
                    })
                }

                quickActionButton("編集", systemImage: "pencil") {
                    closeQuickMenu(afterClose: {
                        vm.beginEditing()
                    })
                }
            }

            quickActionButton(
                "Pull で更新",
                systemImage: "arrow.triangle.2.circlepath",
                disabled: vm.isPulling
            ) {
                closeQuickMenu(afterClose: {
                    vm.pullLatest()
                })
            }
        }
        .padding(10)
        .frame(width: 230)
        .obgitGlassCard(cornerRadius: 20)
    }

    private func quickActionButton(
        _ title: String,
        systemImage: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(disabled ? ObgitPalette.secondaryInk : ObgitPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(ObgitPalette.shellSurfaceStrong.opacity(disabled ? 0.42 : 0.78))
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func closeQuickMenu(animated: Bool = true, afterClose: (() -> Void)? = nil) {
        if animated {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                isQuickMenuOpen = false
            }
        } else {
            isQuickMenuOpen = false
        }

        guard let afterClose else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.08 : 0)) {
            afterClose()
        }
    }
}

// MARK: - Sidebar

private struct VaultSidebarView: View {
    @ObservedObject var vm: VaultWorkspaceViewModel
    let repositories: [RepositoryModel]
    let selectedRepository: RepositoryModel
    let fileTreeID: UUID
    @Binding var showSearch: Bool
    @Binding var showSettings: Bool
    let onSelectRepository: (RepositoryModel) -> Void
    let onAddRepository: () -> Void
    let onCloseSidebar: () -> Void
    let onReloadFileTree: () -> Void
    let onEditRepository: (RepositoryModel) -> Void
    let onDeleteRepository: (RepositoryModel) -> Void
    let width: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            Divider()
                .overlay(ObgitPalette.line)
            sidebarList
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ObgitPalette.sidebarSurface.ignoresSafeArea(edges: .vertical))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(ObgitPalette.line.opacity(0.9))
                .frame(width: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 14, x: 8, y: 0)
    }

    private var sidebarHeader: some View {
        HStack(spacing: 10) {
            Image("icon")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
            Text("Obgit")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(ObgitPalette.ink)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var sidebarList: some View {
        List {
            repositorySection
            actionSection
            fileSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    private var repositorySection: some View {
        Section {
            ForEach(repositories) { repo in
                Button {
                    onSelectRepository(repo)
                    onCloseSidebar()
                } label: {
                    sidebarRow(isActive: repo.id == selectedRepository.id) {
                        HStack(spacing: 12) {
                            Image(systemName: repo.id == selectedRepository.id ? "checkmark.circle.fill" : "circle.dashed")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(repo.id == selectedRepository.id ? ObgitPalette.accent : ObgitPalette.secondaryInk)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(repo.name)
                                    .font(.system(.subheadline, design: .rounded).weight(repo.id == selectedRepository.id ? .bold : .medium))
                                    .foregroundStyle(ObgitPalette.ink)
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.triangle.branch")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(repo.branch)
                                        .font(.system(.caption, design: .rounded))
                                }
                                .foregroundStyle(ObgitPalette.secondaryInk)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                .contextMenu {
                    Button("編集", systemImage: "pencil") {
                        onCloseSidebar()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                            onEditRepository(repo)
                        }
                    }
                    Divider()
                    Button("削除", systemImage: "trash", role: .destructive) {
                        onDeleteRepository(repo)
                    }
                }
            }

            Button {
                onAddRepository()
                onCloseSidebar()
            } label: {
                sidebarRow {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.down.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(ObgitPalette.mint)
                        Text("新しいリポジトリを Clone")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(ObgitPalette.ink)
                    }
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
        } header: {
            sectionHeader("リポジトリ")
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                onCloseSidebar()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showSettings = true
                }
            } label: {
                sidebarRow {
                    HStack(spacing: 12) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(ObgitPalette.secondaryInk)
                        Text("設定")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(ObgitPalette.ink)
                    }
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))

            Button {
                onCloseSidebar()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showSearch = true
                }
            } label: {
                sidebarRow {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(ObgitPalette.ink)
                        Text("ファイルを検索")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(ObgitPalette.ink)
                    }
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))

            Button {
                vm.pullLatest()
                onCloseSidebar()
            } label: {
                sidebarRow {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(ObgitPalette.accent)
                        Text("Pull で更新")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(ObgitPalette.ink)
                    }
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))

            Button {
                onCloseSidebar()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    vm.showCommitHistory = true
                }
            } label: {
                sidebarRow {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(ObgitPalette.secondaryInk)
                        Text("コミット履歴")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(ObgitPalette.ink)
                    }
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))

            Button {
                onCloseSidebar()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    vm.showBranchSwitch = true
                }
            } label: {
                sidebarRow {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(ObgitPalette.secondaryInk)
                        Text("ブランチ切り替え")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(ObgitPalette.ink)
                    }
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))

            Button(action: onReloadFileTree) {
                sidebarRow {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(ObgitPalette.secondaryInk)
                        Text("ファイルツリーを再読み込み")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(ObgitPalette.ink)
                    }
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
        } header: {
            sectionHeader("操作")
        }
    }

    private var fileSection: some View {
        Section {
            if vm.fileTree.isEmpty {
                sidebarRow {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.questionmark")
                            .font(.system(size: 18))
                            .foregroundStyle(ObgitPalette.secondaryInk)
                        Text("ファイルがありません")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(ObgitPalette.secondaryInk)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
            } else {
                OutlineGroup(vm.fileTree, children: \.outlineChildren) { node in
                    SidebarTreeRow(
                        node: node,
                        isSelected: vm.selectedFileURL == node.url,
                        onTap: node.isViewable ? {
                            vm.select(node)
                            onCloseSidebar()
                        } : nil
                    )
                }
                .id(fileTreeID)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 24))
            }
        } header: {
            sectionHeader("ファイル")
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(ObgitPalette.secondaryInk)
            .textCase(nil)
    }

    private func sidebarRow<Content: View>(isActive: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isActive ? ObgitPalette.accentSoft.opacity(0.95) : Color.black.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isActive ? ObgitPalette.accent.opacity(0.34) : Color.clear, lineWidth: 1)
            )
    }
}

private struct SidebarTreeRow: View {
    let node: VaultFileNode
    let isSelected: Bool
    var onTap: (() -> Void)? = nil

    var body: some View {
        // MDファイルは Button 全体でタップ可能に
        if let onTap {
            Button(action: onTap) {
                rowContent
            }
            .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 22)

            Text(node.name)
                .font(.system(.subheadline, design: .rounded).weight(node.isMarkdown ? .medium : .regular))
                .foregroundStyle(textColor)
                .lineLimit(1)

            Spacer()

            // 閲覧可能ファイルのみアクションインジケーターを表示
            if node.isMarkdown {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ObgitPalette.accent.opacity(0.70))
            } else if node.isImage {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ObgitPalette.mint.opacity(0.80))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? ObgitPalette.accentSoft.opacity(0.95) : Color.black.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? ObgitPalette.accent.opacity(0.34) : Color.clear, lineWidth: 1)
        )
    }

    private var iconName: String {
        if node.isDirectory { return "folder.fill" }
        if node.isMarkdown { return "doc.text.fill" }
        if node.isImage { return "photo.fill" }
        return "doc.fill"
    }

    private var iconSize: CGFloat {
        node.isDirectory ? 20 : 18
    }

    private var iconColor: Color {
        if node.isDirectory { return ObgitPalette.accent }
        if node.isMarkdown { return ObgitPalette.accent }
        if node.isImage { return ObgitPalette.mint }
        return ObgitPalette.secondaryInk
    }

    private var textColor: Color {
        node.isViewable ? ObgitPalette.ink : ObgitPalette.secondaryInk
    }
}

private struct LoadingToastView: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .tint(ObgitPalette.accent)

            Text(text)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(ObgitPalette.ink)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            Capsule(style: .continuous)
                .fill(ObgitPalette.shellSurface)
                .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 8)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(ObgitPalette.accent.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct ToastNotificationView: View {
    let text: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isError ? ObgitPalette.coral : ObgitPalette.mint)

            Text(text)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(ObgitPalette.ink)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            Capsule(style: .continuous)
                .fill(ObgitPalette.shellSurface)
                .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 8)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    (isError ? ObgitPalette.coral : ObgitPalette.mint).opacity(0.30),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Image Viewer

private struct ImageViewerContent: View {
    let url: URL
    @GestureState private var pinchScale: CGFloat = 1.0
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            if let uiImage = UIImage(contentsOfFile: url.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(scale * pinchScale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .updating($pinchScale) { value, state, _ in
                                state = value
                            }
                            .onEnded { value in
                                let next = max(1.0, min(6.0, scale * value))
                                scale = next
                                if next == 1.0 {
                                    withAnimation(.spring(response: 0.3)) {
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                guard scale > 1.0 else { return }
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in lastOffset = offset }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                            if scale > 1.5 {
                                scale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2.5
                            }
                        }
                    }
                    .clipped()
            } else {
                ContentUnavailableView("画像を読み込めません", systemImage: "photo.slash")
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

// MARK: - Appearance Settings Sheet

private struct AppearanceSettingsSheet: View {
    @AppStorage("app_appearance") private var appearanceRaw = 0
    @Environment(\.dismiss) private var dismiss

    private let options: [(label: String, icon: String, value: Int, iconColor: Color)] = [
        ("システム",  "iphone",       0, ObgitPalette.secondaryInk),
        ("ライト",   "sun.max.fill",  1, ObgitPalette.coral),
        ("ダーク",   "moon.fill",     2, ObgitPalette.accent),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(options, id: \.value) { option in
                        Button {
                            appearanceRaw = option.value
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: option.icon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(option.iconColor)
                                    .frame(width: 28)

                                Text(option.label)
                                    .font(.system(.body, design: .rounded).weight(.medium))
                                    .foregroundStyle(ObgitPalette.ink)

                                Spacer()

                                if appearanceRaw == option.value {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(ObgitPalette.accent)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("外観テーマ")
                } footer: {
                    Text("「システム」を選択すると端末の設定に従って自動で切り替わります。")
                }
            }
            .scrollContentBackground(.hidden)
            .background(ObgitLiquidBackground())
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .tint(ObgitPalette.accent)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Repository Edit Sheet

private struct RepositoryEditSheet: View {
    let repo: RepositoryModel

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var remoteURL: String
    @State private var branch: String
    @State private var username: String
    @State private var pat: String
    @State private var sshPrivateKey: String
    @State private var sshPassphrase: String
    @State private var showPAT = false
    @State private var showRecloneAlert = false

    init(repo: RepositoryModel) {
        self.repo = repo
        _name = State(initialValue: repo.name)
        _remoteURL = State(initialValue: repo.remoteURL)
        _branch = State(initialValue: repo.branch)
        _username = State(initialValue: repo.username)
        _pat = State(initialValue: KeychainService.shared.retrieve(for: repo.id) ?? "")
        _sshPrivateKey = State(initialValue: "")  // セキュリティ上、秘密鍵は事前入力しない
        _sshPassphrase = State(initialValue: "")
    }

    private var isSSHURL: Bool {
        let url = remoteURL.trimmed
        return url.hasPrefix("git@") || url.lowercased().hasPrefix("ssh://")
    }

    /// URL またはブランチが変わった場合は再クローンが必要
    private var needsReclone: Bool {
        remoteURL.trimmed != repo.remoteURL || branch.trimmed != repo.branch
    }

    private var isFormValid: Bool {
        !name.trimmed.isEmpty &&
        !remoteURL.trimmed.isEmpty &&
        !branch.trimmed.isEmpty &&
        !username.trimmed.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // リポジトリ情報
                Section("リポジトリ情報") {
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
                    LabeledContent("ブランチ") {
                        TextField("main", text: $branch)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                }

                // 認証情報
                Section {
                    LabeledContent("ユーザー名") {
                        TextField(isSSHURL ? "git" : "username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }

                    if isSSHURL {
                        // SSH 認証フィールド
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SSH 秘密鍵（PEM 形式、空のままにすると変更しません）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $sshPrivateKey)
                                .font(.system(.caption, design: .monospaced))
                                .frame(height: 100)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        LabeledContent("パスフレーズ") {
                            SecureField("（空のままにすると変更しません）", text: $sshPassphrase)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .multilineTextAlignment(.trailing)
                        }
                    } else {
                        // HTTPS 認証フィールド
                        LabeledContent("PAT") {
                            HStack(spacing: 8) {
                                Group {
                                    if showPAT {
                                        TextField("ghp_xxxx...", text: $pat)
                                    } else {
                                        SecureField("ghp_xxxx...", text: $pat)
                                    }
                                }
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .multilineTextAlignment(.trailing)

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
                } header: {
                    Text("認証情報")
                } footer: {
                    if isSSHURL {
                        Text("SSH 秘密鍵とパスフレーズは iOS Keychain に暗号化保存されます。")
                    } else {
                        Text("PAT を空のままにすると、既存の Keychain 値を維持します。")
                    }
                }

                // 再クローン警告
                if needsReclone {
                    Section {
                        Label("URL またはブランチを変更すると、ローカルのクローンが削除されます。保存後にワークスペース画面から再クローンしてください。", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ObgitLiquidBackground())
            .tint(ObgitPalette.accent)
            .navigationTitle("設定を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if needsReclone {
                            showRecloneAlert = true
                        } else {
                            save()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!isFormValid)
                }
            }
            .confirmationDialog(
                "再クローンが必要です",
                isPresented: $showRecloneAlert,
                titleVisibility: .visible
            ) {
                Button("削除して変更を保存", role: .destructive) {
                    save()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("ローカルのクローンを削除して新しい設定を保存します。Workspace 画面から再クローンしてください。")
            }
        }
    }

    private func save() {
        var updated = repo
        updated.name = name.trimmed
        updated.remoteURL = remoteURL.trimmed
        updated.branch = branch.trimmed
        updated.username = username.trimmed

        if needsReclone && repo.isCloned {
            updated.isCloned = false
            try? FileManager.default.removeItem(at: repo.localURL)
        }

        // Keychain を更新（入力がある場合のみ）
        if isSSHURL {
            let newKey = sshPrivateKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newKey.isEmpty {
                KeychainService.shared.saveSSHKey(newKey, for: repo.id)
            }
            let newPassphrase = sshPassphrase.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newPassphrase.isEmpty {
                KeychainService.shared.savePassphrase(newPassphrase, for: repo.id)
            }
        } else {
            let newPAT = pat.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newPAT.isEmpty {
                KeychainService.shared.save(token: newPAT, for: repo.id)
            }
        }

        RepositoryStore.shared.update(updated)
        dismiss()
    }
}

// MARK: - String helper

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

#Preview {
    VaultHomeView()
}
