import SwiftUI

struct ReferenceSidebar: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var reader: ReaderStore

    @Binding var searchText: String
    @Binding var searchHits: [SearchHit]
    @Binding var isSearching: Bool
    @Binding var selectedTab: String
    let searchHistory: [String]
    var runSearch: () -> Void
    var runHistoricalSearch: (String) -> Void
    @State private var expandedTOCItems: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索正文、标题、关键词...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit(runSearch)
                    .help("输入搜索关键词")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        reader.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("清空搜索内容")
                }
                Button {
                    runSearch()
                } label: {
                    Image(systemName: "magnifyingglass.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.teal)
                .help("搜索")
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || isSearching)
                ZStack {
                    ProgressView()
                        .controlSize(.small)
                        .opacity(isSearching ? 1 : 0)
                }
                .frame(width: 16, height: 16)
                .accessibilityHidden(!isSearching)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .padding([.horizontal, .top], 12)

            Picker("", selection: tabSelection) {
                Label("目录", systemImage: "list.bullet").tag("toc")
                Label("搜索", systemImage: "text.magnifyingglass").tag("search")
                Label("收藏", systemImage: "bookmark").tag("favorites")
            }
            .pickerStyle(.segmented)
            .help("切换面板")
            .padding(12)

            Divider()

            Group {
                if let book = library.selectedBook {
                    switch selectedTab {
                    case "search":
                        SearchResultsView(
                            query: searchText,
                            hits: searchHits,
                            history: searchHistory,
                            runHistoricalSearch: runHistoricalSearch
                        )
                    case "favorites":
                        FavoritesPanel(book: book)
                    default:
                        TOCView(items: book.toc, expandedItems: $expandedTOCItems)
                    }
                } else {
                    ContentUnavailableView("导入 CHM 文档", systemImage: "book.closed")
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var tabSelection: Binding<String> {
        Binding {
            selectedTab
        } set: { newValue in
            selectedTab = newValue
        }
    }
}

struct TOCView: View {
    @EnvironmentObject private var reader: ReaderStore
    let items: [TOCItem]
    @Binding var expandedItems: Set<UUID>

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    TOCNodeRow(item: item, depth: 0, currentPath: reader.currentPath, expandedItems: $expandedItems)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            expandParentsForCurrentPath()
        }
        .onChange(of: reader.currentPath) { _, _ in
            expandParentsForCurrentPath()
        }
    }

    private func expandParentsForCurrentPath() {
        guard let currentPath = reader.currentPath else { return }
        expandedItems.formUnion(parentIDs(containing: currentPath, in: items))
    }

    private func parentIDs(containing path: String, in items: [TOCItem]) -> Set<UUID> {
        for item in items {
            if item.path == path {
                return []
            }

            let childMatches = parentIDs(containing: path, in: item.children)
            if !childMatches.isEmpty || item.children.contains(where: { $0.path == path }) {
                return childMatches.union([item.id])
            }
        }
        return []
    }
}

struct TOCNodeRow: View {
    @EnvironmentObject private var reader: ReaderStore
    let item: TOCItem
    let depth: Int
    let currentPath: String?
    @Binding var expandedItems: Set<UUID>
    @State private var handledChevronTap = false

    private var isExpanded: Bool {
        expandedItems.contains(item.id)
    }

    private var hasChildren: Bool {
        !item.children.isEmpty
    }

    private var isCurrent: Bool {
        item.path != nil && item.path == currentPath
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.teal.opacity(0.13))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                    Rectangle()
                        .fill(Color.teal)
                        .frame(width: 3)
                        .padding(.vertical, 6)
                        .padding(.leading, 6)
                }

                HStack(spacing: 7) {
                    Image(systemName: hasChildren ? (isExpanded ? "chevron.down" : "chevron.right") : "doc.text")
                        .font(.system(size: 11, weight: hasChildren ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? .teal : .secondary)
                        .frame(width: 22, height: 24)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handledChevronTap = true
                            toggleExpandedOrOpen()
                        }
                        .help(hasChildren ? "展开或收起：\(item.title)" : "打开章节：\(item.title)")

                    Text(item.title)
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? .teal : .primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, CGFloat(depth * 15) + 8)
                .padding(.trailing, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
                .onTapGesture {
                    if handledChevronTap {
                        handledChevronTap = false
                    } else {
                        openOrToggle()
                    }
                }
                .help(item.path == nil ? "展开或收起：\(item.title)" : "打开章节：\(item.title)")
            }
            .contentShape(Rectangle())

            Divider()
                .padding(.leading, CGFloat(depth * 15) + 34)

            if isExpanded {
                ForEach(item.children) { child in
                    TOCNodeRow(item: child, depth: depth + 1, currentPath: currentPath, expandedItems: $expandedItems)
                }
            }
        }
    }

    private func openOrToggle() {
        if let path = item.path {
            reader.open(path)
            if hasChildren {
                expandedItems.insert(item.id)
            }
        } else {
            toggleExpanded()
        }
    }

    private func toggleExpandedOrOpen() {
        if hasChildren {
            toggleExpanded()
        } else if let path = item.path {
            reader.open(path)
        }
    }

    private func toggleExpanded() {
        guard hasChildren else { return }
        if isExpanded {
            expandedItems.remove(item.id)
        } else {
            expandedItems.insert(item.id)
        }
    }
}

struct SearchResultsView: View {
    @EnvironmentObject private var reader: ReaderStore
    let query: String
    let hits: [SearchHit]
    let history: [String]
    var runHistoricalSearch: (String) -> Void

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 2 {
            SearchHistoryView(history: history, runHistoricalSearch: runHistoricalSearch)
        } else if hits.isEmpty {
            ContentUnavailableView("没有结果", systemImage: "magnifyingglass")
        } else {
            List(hits) { hit in
                Button {
                    reader.open(hit.path, searchQuery: trimmed)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(highlighted(hit.title, query: trimmed, baseSize: 13))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(highlighted(hit.snippet, query: trimmed, baseSize: 12))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .help("打开搜索结果")
            }
            .listStyle(.inset)
        }
    }

    private func highlighted(_ text: String, query: String, baseSize: CGFloat) -> AttributedString {
        var attributed = AttributedString(text)
        var searchStart = attributed.startIndex

        while let range = attributed[searchStart...].range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributed[range].backgroundColor = .yellow.opacity(0.48)
            attributed[range].foregroundColor = .primary
            attributed[range].font = .system(size: baseSize, weight: .semibold)
            searchStart = range.upperBound
        }

        return attributed
    }
}

struct SearchHistoryView: View {
    let history: [String]
    var runHistoricalSearch: (String) -> Void

    var body: some View {
        List {
            Section("搜索历史") {
                if history.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                        Text("暂无搜索历史")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 5)
                    .help("暂无搜索历史")
                } else {
                    ForEach(history, id: \.self) { query in
                        Button {
                            runHistoricalSearch(query)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(.secondary)
                                Text(query)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .help("再次搜索：\(query)")
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}
