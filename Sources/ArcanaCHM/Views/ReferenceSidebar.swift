import SwiftUI

struct ReferenceSidebar: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var reader: ReaderStore
    @EnvironmentObject private var locale: LocalizationService

    @Binding var searchText: String
    let lastCompletedSearch: (query: String, hits: [SearchHit])?
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
                            searchText: searchText,
                            lastCompletedSearch: lastCompletedSearch,
                            history: searchHistory,
                            runHistoricalSearch: runHistoricalSearch,
                            deleteHistoryItem: deleteHistoryItem
                        )
                        .transition(.opacity)
                        .id("search")
                    case "favorites":
                        FavoritesPanel(book: book)
                            .transition(.opacity)
                            .id("favorites")
                    default:
                        TOCView(items: book.toc, expandedItems: $expandedTOCItems)
                            .transition(.opacity)
                            .id("toc")
                    }
                } else {
                    switch selectedTab {
                    case "search":
                        SearchResultsView(
                            searchText: searchText,
                            lastCompletedSearch: lastCompletedSearch,
                            history: searchHistory,
                            runHistoricalSearch: runHistoricalSearch,
                            deleteHistoryItem: deleteHistoryItem
                        )
                        .transition(.opacity)
                        .id("search")
                    case "favorites":
                        emptyFavoritesView
                            .transition(.opacity)
                            .id("favorites")
                    default:
                        TOCView(items: [], expandedItems: $expandedTOCItems)
                            .transition(.opacity)
                            .id("toc")
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

