import SwiftUI

struct ReferenceSidebar: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var reader: ReaderStore
    @EnvironmentObject private var locale: LocalizationService
    @ObservedObject var tab: ReaderTabSession

    let searchHistory: [String]
    var runSearch: () -> Void
    var runHistoricalSearch: (String) -> Void
    var deleteHistoryItem: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("search_placeholder".loc, text: $tab.searchText)
                    .textFieldStyle(.plain)
                    .onSubmit(runSearch)
                    .help("search_help_keywords".loc)
                if !tab.searchText.isEmpty {
                    Button {
                        tab.searchText = ""
                        reader.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("search_help_clear".loc)
                }
                Button(action: runSearch) {
                    Image(systemName: "magnifyingglass.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.teal)
                .help("search_help_search".loc)
                .disabled(tab.searchText.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || tab.isSearching)
                ZStack {
                    ProgressView()
                        .controlSize(.small)
                        .opacity(tab.isSearching ? 1 : 0)
                }
                .frame(width: 16, height: 16)
                .accessibilityHidden(!tab.isSearching)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .padding([.horizontal, .top], 12)

            Picker("", selection: $tab.selectedReferenceTab) {
                Label("tab_toc".loc, systemImage: "list.bullet").tag("toc")
                Label("tab_search".loc, systemImage: "text.magnifyingglass").tag("search")
                Label("tab_favorites".loc, systemImage: "bookmark").tag("favorites")
            }
            .pickerStyle(.segmented)
            .help("tab_switch".loc)
            .padding(12)

            Divider()

            Group {
                if let book = library.book(id: tab.bookID) {
                    switch tab.selectedReferenceTab {
                    case "search":
                        SearchResultsView(
                            searchText: tab.searchText,
                            lastCompletedSearch: tab.completedSearch,
                            history: searchHistory,
                            runHistoricalSearch: runHistoricalSearch,
                            deleteHistoryItem: deleteHistoryItem
                        )
                    case "favorites":
                        FavoritesPanel(book: book)
                    default:
                        TOCView(items: book.toc, expandedItems: $tab.expandedTOCItems)
                    }
                } else {
                    switch tab.selectedReferenceTab {
                    case "search":
                        SearchResultsView(
                            searchText: tab.searchText,
                            lastCompletedSearch: tab.completedSearch,
                            history: searchHistory,
                            runHistoricalSearch: runHistoricalSearch,
                            deleteHistoryItem: deleteHistoryItem
                        )
                    case "favorites":
                        emptyFavoritesView
                    default:
                        TOCView(items: [], expandedItems: $tab.expandedTOCItems)
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
}
