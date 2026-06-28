import SwiftUI

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
                    children: filteredChildren
                )
            }
            return nil
        }
    }

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

    static func expandedIDsForSearch(in items: [TOCItem], query: String) -> Set<UUID> {
        let leafIDs = leafMatchIDs(in: items, query: query)
        guard !leafIDs.isEmpty else { return [] }
        var result = Set<UUID>()
        func collect(item: TOCItem) -> Bool {
            var childIsOrHasLeaf = false
            for child in item.children {
                if collect(item: child) { childIsOrHasLeaf = true }
            }
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
