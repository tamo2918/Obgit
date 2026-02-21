import SwiftUI

// MARK: - Sheet

struct SearchSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var searchVM: SearchViewModel
    let onSelectFile: (URL) -> Void

    init(rootURL: URL, onSelectFile: @escaping (URL) -> Void) {
        _searchVM = StateObject(wrappedValue: SearchViewModel(rootURL: rootURL))
        self.onSelectFile = onSelectFile
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                Divider()
                    .overlay(ObgitPalette.line)

                Group {
                    if searchVM.query.trimmingCharacters(in: .whitespaces).isEmpty {
                        placeholderState
                    } else if searchVM.isSearching {
                        searchingState
                    } else if searchVM.results.isEmpty {
                        noResultsState
                    } else {
                        resultsList
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(ObgitLiquidBackground())
            .navigationTitle("検索")
            .navigationBarTitleDisplayMode(.inline)
            .tint(ObgitPalette.accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .onChange(of: searchVM.query) { _, _ in
            searchVM.onQueryChange()
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ObgitPalette.secondaryInk)

            TextField("ファイル名・本文を検索", text: $searchVM.query)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(ObgitPalette.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)

            if !searchVM.query.isEmpty {
                Button {
                    searchVM.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(ObgitPalette.secondaryInk)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .obgitGlassCard(cornerRadius: 16)
    }

    // MARK: - States

    private var placeholderState: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 52))
                .foregroundStyle(ObgitPalette.accent.opacity(0.35))

            Text("ファイル名や本文で全文検索できます")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(ObgitPalette.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 72)
    }

    private var searchingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.regular)
                .tint(ObgitPalette.accent)

            Text("検索中...")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(ObgitPalette.secondaryInk)
        }
        .padding(.top, 72)
    }

    private var noResultsState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(ObgitPalette.secondaryInk.opacity(0.45))

            Text("「\(searchVM.query)」に一致するファイルがありません")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(ObgitPalette.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .padding(.top, 72)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                Text("\(searchVM.results.count) 件")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(ObgitPalette.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                ForEach(searchVM.results) { result in
                    SearchResultCard(result: result, query: searchVM.query) {
                        onSelectFile(result.fileURL)
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Result Card

private struct SearchResultCard: View {
    let result: FileSearchResult
    let query: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // ファイル名ヘッダー
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ObgitPalette.accent)

                    HighlightedText(
                        text: result.fileName,
                        highlight: query,
                        baseFont: .system(.subheadline, design: .rounded).weight(.semibold),
                        baseColor: ObgitPalette.ink,
                        highlightColor: ObgitPalette.accent
                    )
                    .lineLimit(1)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ObgitPalette.secondaryInk.opacity(0.55))
                }

                if result.isFileNameMatch {
                    // ファイル名一致バッジ
                    Label("ファイル名が一致", systemImage: "checkmark.circle.fill")
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(ObgitPalette.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(ObgitPalette.accentSoft.opacity(0.65))
                        )
                } else {
                    // 一致行リスト
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(result.lineMatches) { match in
                            HStack(alignment: .top, spacing: 8) {
                                Text("L\(match.lineNumber)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(ObgitPalette.accent.opacity(0.70))
                                    .frame(width: 36, alignment: .trailing)
                                    .padding(.top, 1)

                                HighlightedText(
                                    text: match.text,
                                    highlight: query,
                                    baseFont: .system(.caption, design: .rounded),
                                    baseColor: ObgitPalette.ink,
                                    highlightColor: ObgitPalette.accent
                                )
                                .lineLimit(2)
                            }
                        }
                    }
                    .padding(.top, 2)
                    .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .obgitGlassCard(cornerRadius: 20)
    }
}

// MARK: - Highlighted Text

private struct HighlightedText: View {
    let text: String
    let highlight: String
    let baseFont: Font
    let baseColor: Color
    let highlightColor: Color

    var body: some View {
        Text(buildAttributed())
    }

    private func buildAttributed() -> AttributedString {
        var attr = AttributedString(text)
        attr.font = baseFont
        attr.foregroundColor = baseColor

        guard !highlight.isEmpty else { return attr }

        var start = attr.startIndex
        while start < attr.endIndex {
            guard let range = attr[start...].range(of: highlight, options: .caseInsensitive) else { break }
            attr[range].foregroundColor = highlightColor
            attr[range].font = baseFont.bold()
            start = range.upperBound
        }

        return attr
    }
}
