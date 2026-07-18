import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var preferences: ReaderPreferencesStore
    @EnvironmentObject private var locale: LocalizationService

    @StateObject private var workspace = ReaderWorkspaceStore()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
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
        let activeTab = workspace.activeTab

        VStack(spacing: 0) {
            ReaderTabBar()
            Divider()

            NavigationSplitView(columnVisibility: $columnVisibility) {
                LibrarySidebar()
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            } content: {
                ReferenceSidebar(
                    tab: activeTab,
                    searchHistory: searchHistory,
                    runSearch: { runSearch(for: activeTab) },
                    runHistoricalSearch: { runHistoricalSearch($0, for: activeTab) },
                    deleteHistoryItem: deleteHistoryItem
                )
                .environmentObject(activeTab.reader)
                .navigationSplitViewColumnWidth(min: 300, ideal: 360)
                .id(activeTab.id)
            } detail: {
                readerDetail
            }
        }
        .environmentObject(workspace)
        .focusedSceneValue(
            \.readerWorkspaceCommands,
            ReaderWorkspaceCommandActions(
                newTab: { workspace.newTab() },
                closeActiveTabOrWindow: closeActiveTabOrWindow,
                selectNextTab: { workspace.selectNextTab() },
                selectPreviousTab: { workspace.selectPreviousTab() }
            )
        )
        .tint(.teal)
        .preferredColorScheme(preferences.darkMode ? .dark : .light)
        .toolbar {
            ReaderGlobalToolbar()
        }
        .onReceive(NotificationCenter.default.publisher(for: .importCHMRequested)) { _ in
            library.importCHMWithPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFolderRequested)) { _ in
            library.importFolderWithPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rebuildLibraryRequested)) { _ in
            Task { await library.prepareLibraryRebuild() }
        }
        .sheet(item: Binding(
            get: { library.rebuildPreview },
            set: { if $0 == nil { library.cancelLibraryRebuild() } }
        )) { preview in
            LibraryRebuildPreviewView(
                preview: preview,
                onCancel: { library.cancelLibraryRebuild() },
                onConfirm: { Task { await library.applyLibraryRebuild(preview) } }
            )
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
            if library.isImporting || library.isRebuildingLibrary {
                ZStack {
                    Color.black.opacity(0.18)
                    ProgressView(library.isRebuildingLibrary ? "library_rebuild_scanning".loc : "reader_importing".loc)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .onChange(of: library.books) { _, books in
            workspace.reconcile(validBookIDs: Set(books.map(\.id)))
        }
        .onDisappear {
            for tab in workspace.tabs {
                tab.cancelSearch()
            }
        }
    }

    private var readerDetail: some View {
        ZStack {
            ForEach(workspace.tabs) { tab in
                let isActive = tab.id == workspace.activeTabID
                ReaderTabPaneHost(tab: tab, isActive: isActive)
            }
        }
    }

    private func runSearch(for tab: ReaderTabSession) {
        let query = tab.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2,
              let bookID = tab.bookID,
              let book = library.book(id: bookID)
        else { return }

        tab.isSearching = true
        tab.reader.searchQuery = query
        rememberSearch(query)
        tab.searchTask?.cancel()
        let generation = UUID()
        tab.searchGeneration = generation
        tab.searchTask = Task {
            let hits = await library.search(query, in: book)
            guard !Task.isCancelled,
                  workspace.tabs.contains(where: { $0.id == tab.id }),
                  tab.bookID == bookID,
                  tab.searchGeneration == generation,
                  tab.searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query
            else { return }
            tab.completedSearch = CompletedReaderSearch(query: query, hits: hits)
            tab.isSearching = false
            tab.selectedReferenceTab = "search"
        }
    }

    private func runHistoricalSearch(_ query: String, for tab: ReaderTabSession) {
        tab.searchText = query
        runSearch(for: tab)
    }

    private func rememberSearch(_ query: String) {
        var history = searchHistory.filter { $0.localizedCaseInsensitiveCompare(query) != .orderedSame }
        history.insert(query, at: 0)
        searchHistory = history
    }

    private func deleteHistoryItem(_ query: String) {
        searchHistory = searchHistory.filter { $0 != query }
    }

    private func closeActiveTabOrWindow() {
        if workspace.tabs.count > 1 {
            workspace.closeTab(workspace.activeTabID)
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }
}

private struct ReaderTabPaneHost: View {
    @ObservedObject var tab: ReaderTabSession
    let isActive: Bool

    var body: some View {
        ReaderPane(tab: tab, isActive: isActive)
            .environmentObject(tab.reader)
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
            .zIndex(isActive ? 1 : 0)
    }
}

private struct ReaderGlobalToolbar: ToolbarContent {
    @EnvironmentObject private var preferences: ReaderPreferencesStore
    @EnvironmentObject private var locale: LocalizationService

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                preferences.darkMode.toggle()
            } label: {
                Label(
                    preferences.darkMode ? "reader_dark_mode".loc : "reader_light_mode".loc,
                    systemImage: preferences.darkMode ? "sun.max" : "moon"
                )
            }
            .help(preferences.darkMode ? "reader_switch_light".loc : "reader_switch_dark".loc)
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("language_title".loc, selection: $locale.currentLanguage) {
                    ForEach(LocalizationService.Language.allCases, id: \.self) { language in
                        Text(locale.label(for: language))
                            .tag(language)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("language_title".loc, systemImage: "globe")
            }
        }
    }
}
