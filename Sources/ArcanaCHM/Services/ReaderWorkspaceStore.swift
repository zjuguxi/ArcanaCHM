import SwiftUI

struct CompletedReaderSearch: Equatable, Sendable {
    let query: String
    let hits: [SearchHit]
}

@MainActor
final class ReaderTabSession: ObservableObject, Identifiable {
    let id: UUID
    let reader: ReaderStore

    @Published private(set) var bookID: Book.ID?
    @Published var pageTitle = ""
    @Published var searchText = ""
    @Published var completedSearch: CompletedReaderSearch?
    @Published var isSearching = false
    @Published var selectedReferenceTab = "toc"
    @Published var expandedTOCItems: Set<UUID> = []

    var searchGeneration = UUID()
    var searchTask: Task<Void, Never>?

    init(id: UUID = UUID()) {
        self.id = id
        reader = ReaderStore()
    }

    func openBook(bookID: Book.ID, path: String?, scrollY: Double) {
        guard self.bookID != bookID else { return }
        cancelSearch()
        self.bookID = bookID
        pageTitle = ""
        searchText = ""
        completedSearch = nil
        selectedReferenceTab = "toc"
        expandedTOCItems = []
        reader.beginSession(bookID: bookID, path: path, scrollY: scrollY)
    }

    func clear() {
        cancelSearch()
        bookID = nil
        pageTitle = ""
        searchText = ""
        completedSearch = nil
        selectedReferenceTab = "toc"
        expandedTOCItems = []
        reader.endSession()
    }

    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchGeneration = UUID()
        isSearching = false
    }

    deinit {
        searchTask?.cancel()
    }
}

@MainActor
final class ReaderWorkspaceStore: ObservableObject {
    static let maximumTabCount = 20

    @Published private(set) var tabs: [ReaderTabSession]
    @Published private(set) var activeTabID: ReaderTabSession.ID

    init() {
        let initialTab = ReaderTabSession()
        tabs = [initialTab]
        activeTabID = initialTab.id
    }

    var activeTab: ReaderTabSession {
        tabs.first(where: { $0.id == activeTabID }) ?? tabs[0]
    }

    @discardableResult
    func newTab() -> ReaderTabSession {
        guard tabs.count < Self.maximumTabCount else { return activeTab }
        let tab = ReaderTabSession()
        tabs.append(tab)
        activeTabID = tab.id
        return tab
    }

    func openBook(bookID: Book.ID, path: String?, scrollY: Double) {
        activeTab.openBook(bookID: bookID, path: path, scrollY: scrollY)
    }

    func activateTab(_ id: ReaderTabSession.ID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
    }

    func closeTab(_ id: ReaderTabSession.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].cancelSearch()
        let wasActive = activeTabID == id
        tabs.remove(at: index)

        if tabs.isEmpty {
            let replacement = ReaderTabSession()
            tabs = [replacement]
            activeTabID = replacement.id
        } else if wasActive {
            activeTabID = tabs[min(index, tabs.count - 1)].id
        }
    }

    func closeTabs(forBookID bookID: Book.ID) {
        let ids = tabs.filter { $0.bookID == bookID }.map(\.id)
        for id in ids {
            closeTab(id)
        }
    }

    func reconcile(validBookIDs: Set<Book.ID>) {
        let invalidIDs: [ReaderTabSession.ID] = tabs.compactMap { tab -> ReaderTabSession.ID? in
            guard let bookID = tab.bookID, !validBookIDs.contains(bookID) else { return nil }
            return tab.id
        }
        for id in invalidIDs {
            closeTab(id)
        }
    }

    func selectNextTab() {
        cycleTabs(offset: 1)
    }

    func selectPreviousTab() {
        cycleTabs(offset: -1)
    }

    private func cycleTabs(offset: Int) {
        guard tabs.count > 1,
              let currentIndex = tabs.firstIndex(where: { $0.id == activeTabID })
        else { return }
        let count = tabs.count
        activeTabID = tabs[(currentIndex + offset + count) % count].id
    }
}
