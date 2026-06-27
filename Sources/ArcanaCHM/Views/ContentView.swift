import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var reader: ReaderStore
    @EnvironmentObject private var locale: LocalizationService

    @State private var searchText = ""
    @State private var searchHits: [SearchHit] = []
    @State private var isSearching = false
    @State private var selectedTab = "toc"
    @AppStorage("ArcanaCHM.searchHistory") private var searchHistoryStorage = "[]"

    private var searchHistory: [String] {
        get {
            guard let data = searchHistoryStorage.data(using: .utf8),
                  let history = try? JSONDecoder().decode([String].self, from: data)
            else {
                return []
            }
            return history
        }
        nonmutating set {
            let data = (try? JSONEncoder().encode(Array(newValue.prefix(20)))) ?? Data("[]".utf8)
            searchHistoryStorage = String(data: data, encoding: .utf8) ?? "[]"
        }
    }

    var body: some View {
        NavigationSplitView {
            LibrarySidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } content: {
            ReferenceSidebar(
                searchText: $searchText,
                searchHits: $searchHits,
                isSearching: $isSearching,
                selectedTab: $selectedTab,
                searchHistory: searchHistory,
                runSearch: runSearch,
                runHistoricalSearch: runHistoricalSearch,
                deleteHistoryItem: deleteHistoryItem
            )
            .navigationSplitViewColumnWidth(min: 300, ideal: 360)
        } detail: {
            ReaderPane()
        }
        .tint(.teal)
        .preferredColorScheme(reader.darkMode ? .dark : .light)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    reader.darkMode.toggle()
                } label: {
                    Label(reader.darkMode ? "reader_dark_mode".loc : "reader_light_mode".loc, systemImage: reader.darkMode ? "sun.max" : "moon")
                }
                .help(reader.darkMode ? "reader_switch_light".loc : "reader_switch_dark".loc)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("language_title".loc, selection: $locale.currentLanguage) {
                        ForEach(LocalizationService.Language.allCases, id: \.self) { lang in
                            Text(locale.label(for: lang)).tag(lang)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("language_title".loc, systemImage: "globe")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .importCHMRequested)) { _ in
            library.importCHMWithPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFolderRequested)) { _ in
            library.importFolderWithPanel()
        }
        .alert("arcana_chm".loc, isPresented: Binding(
            get: { library.errorMessage != nil },
            set: { if !$0 { library.errorMessage = nil } }
        )) {
            Button("alert_ok".loc, role: .cancel) {}
        } message: {
            Text(library.errorMessage ?? "")
        }
        .overlay {
            if library.isImporting {
                ZStack {
                    Color.black.opacity(0.18)
                    ProgressView("reader_importing".loc)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func runSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            return
        }
        guard let book = library.selectedBook else { return }
        isSearching = true
        reader.searchQuery = query
        rememberSearch(query)
        Task {
            searchHits = await library.search(query, in: book)
            isSearching = false
            selectedTab = "search"
        }
    }

    private func runHistoricalSearch(_ query: String) {
        searchText = query
        runSearch()
    }

    private func rememberSearch(_ query: String) {
        var history = searchHistory.filter { $0.localizedCaseInsensitiveCompare(query) != .orderedSame }
        history.insert(query, at: 0)
        searchHistory = history
    }

    private func deleteHistoryItem(_ query: String) {
        searchHistory = searchHistory.filter { $0 != query }
    }
}
