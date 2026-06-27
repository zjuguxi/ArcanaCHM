import SwiftUI

struct ReferenceSidebar: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var reader: ReaderStore
    @EnvironmentObject private var locale: LocalizationService

    @Binding var searchText: String
    @Binding var searchHits: [SearchHit]
    @Binding var isSearching: Bool
    @Binding var selectedTab: String
    let searchHistory: [String]
    var runSearch: () -> Void
    var runHistoricalSearch: (String) -> Void
    var deleteHistoryItem: (String) -> Void
    @State private var expandedTOCItems: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("search_placeholder".loc, text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit(runSearch)
                    .help("search_help_keywords".loc)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        reader.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("search_help_clear".loc)
                }
                Button {
                    runSearch()
                } label: {
                    Image(systemName: "magnifyingglass.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.teal)
                .help("search_help_search".loc)
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
                Label("tab_toc".loc, systemImage: "list.bullet").tag("toc")
                Label("tab_search".loc, systemImage: "text.magnifyingglass").tag("search")
                Label("tab_favorites".loc, systemImage: "bookmark").tag("favorites")
            }
            .pickerStyle(.segmented)
            .help("tab_switch".loc)
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
                            runHistoricalSearch: runHistoricalSearch,
                            deleteHistoryItem: deleteHistoryItem
                        )
                    case "favorites":
                        FavoritesPanel(book: book)
                    default:
                        TOCView(items: book.toc, expandedItems: $expandedTOCItems)
                    }
                } else {
                    switch selectedTab {
                    case "search":
                        SearchResultsView(
                            query: searchText,
                            hits: searchHits,
                            history: searchHistory,
                            runHistoricalSearch: runHistoricalSearch,
                            deleteHistoryItem: deleteHistoryItem
                        )
                    case "favorites":
                        emptyFavoritesView
                    default:
                        TOCView(items: [], expandedItems: $expandedTOCItems)
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var emptyFavoritesView: some View {
        List {
            HStack(spacing: 8) {
                Image(systemName: "bookmark")
                    .foregroundStyle(.secondary)
                Text("search_no_document".loc)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 5)
        }
        .listStyle(.inset)
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
    @EnvironmentObject private var locale: LocalizationService
    let items: [TOCItem]
    @Binding var expandedItems: Set<UUID>
    @State private var tocQuery = ""

    private var filteredItems: [TOCItem] {
        Self.filter(items: items, query: tocQuery)
    }

    private var isSearching: Bool {
        !tocQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(.secondary)
                TextField("toc_search_placeholder".loc, text: $tocQuery)
                    .textFieldStyle(.plain)
                    .help("toc_search_placeholder".loc)
                if !tocQuery.isEmpty {
                    Button {
                        tocQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("search_help_clear".loc)
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .padding([.horizontal, .top], 12)
            .padding(.bottom, 6)

            if filteredItems.isEmpty && !tocQuery.isEmpty {
                Spacer()
                ContentUnavailableView("toc_no_results".loc, systemImage: "list.bullet")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredItems) { item in
                            TOCNodeRow(item: item, depth: 0, currentPath: reader.currentPath, expandedItems: $expandedItems)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            expandParentsForCurrentPath()
        }
        .onChange(of: reader.currentPath) { _, _ in
            guard !isSearching else { return }
            expandParentsForCurrentPath()
        }
        .onChange(of: tocQuery) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                expandedItems.removeAll()
                expandParentsForCurrentPath()
            } else {
                expandedItems = Self.expandedIDsForSearch(in: items, query: trimmed)
            }
        }
    }

    private func expandParentsForCurrentPath() {
        guard let currentPath = reader.currentPath else { return }
        expandedItems.formUnion(parentIDs(containing: currentPath, in: items))
    }

    private func parentIDs(containing path: String, in items: [TOCItem]) -> Set<UUID> {
        for item in items {
            if item.path == path { return [] }
            let childMatches = parentIDs(containing: path, in: item.children)
            if !childMatches.isEmpty || item.children.contains(where: { $0.path == path }) {
                return childMatches.union([item.id])
            }
        }
        return []
    }

    static func filter(items: [TOCItem], query: String) -> [TOCItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        let lower = trimmed.lowercased()
        return items.compactMap { item in
            let matches = item.title.lowercased().contains(lower)
            let filteredChildren = Self.filter(items: item.children, query: query)
            if matches || !filteredChildren.isEmpty {
                return TOCItem(
                    id: item.id,
                    title: item.title,
                    path: item.path,
                    children: matches ? item.children : filteredChildren
                )
            }
            return nil
        }
    }

    /// IDs of the deepest matching items — items whose own title matches but
    /// none of their descendants also match.
    static func leafMatchIDs(in items: [TOCItem], query: String) -> Set<UUID> {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lower = trimmed.lowercased()
        var result = Set<UUID>()
        for item in items {
            let selfMatches = item.title.lowercased().contains(lower)
            let childLeafIDs = leafMatchIDs(in: item.children, query: query)
            if childLeafIDs.isEmpty {
                if selfMatches { result.insert(item.id) }
            } else {
                result.formUnion(childLeafIDs)
            }
        }
        return result
    }

    /// IDs of all items that are ancestors of at least one leaf match.
    /// These should be expanded so the leaf matches are visible.
    static func expandedIDsForSearch(in items: [TOCItem], query: String) -> Set<UUID> {
        let leafIDs = leafMatchIDs(in: items, query: query)
        guard !leafIDs.isEmpty else { return [] }
        var result = Set<UUID>()
        func collect(item: TOCItem) -> Bool {
            let childIsOrHasLeaf = item.children.contains { collect(item: $0) }
            if childIsOrHasLeaf { result.insert(item.id) }
            return childIsOrHasLeaf || leafIDs.contains(item.id)
        }
        for item in items { _ = collect(item: item) }
        return result
    }
}

struct TOCNodeRow: View {
    @EnvironmentObject private var reader: ReaderStore
    @EnvironmentObject private var locale: LocalizationService
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
                        .help(hasChildren ? "toc_help_expand".loc(item.title) : "toc_help_open".loc(item.title))

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
                .help(item.path == nil ? "toc_help_expand".loc(item.title) : "toc_help_open".loc(item.title))
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
    @EnvironmentObject private var locale: LocalizationService
    let query: String
    let hits: [SearchHit]
    let history: [String]
    var runHistoricalSearch: (String) -> Void
    var deleteHistoryItem: (String) -> Void

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 2 {
            SearchHistoryView(history: history, runHistoricalSearch: runHistoricalSearch, deleteHistoryItem: deleteHistoryItem)
        } else if hits.isEmpty {
            ContentUnavailableView("search_no_results".loc, systemImage: "magnifyingglass")
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
                .help("search_help_open_result".loc)
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
    @EnvironmentObject private var locale: LocalizationService
    let history: [String]
    var runHistoricalSearch: (String) -> Void
    var deleteHistoryItem: (String) -> Void

    var body: some View {
        List {
            Section("search_history".loc) {
                if history.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                        Text("search_no_history".loc)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 5)
                    .help("search_no_history".loc)
                } else {
                    ForEach(history, id: \.self) { query in
                        HStack(spacing: 8) {
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
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("search_help_search_again".loc(query))

                            Button {
                                deleteHistoryItem(query)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("search_help_delete_entry".loc)
                            .opacity(0.7)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}
