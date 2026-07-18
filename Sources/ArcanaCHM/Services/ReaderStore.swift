import Foundation
import SwiftUI

@MainActor
final class ReaderStore: ObservableObject {
    @Published private(set) var currentBookID: UUID?
    @Published var currentPath: String?
    @Published var scrollY: Double = 0
    @Published var searchQuery = ""
    @Published var navigationToken = UUID()

    init() {}

    func beginSession(bookID: UUID, path: String?, scrollY: Double = 0) {
        currentBookID = bookID
        currentPath = path
        self.scrollY = scrollY
        navigationToken = UUID()
        searchQuery = ""
    }

    func endSession() {
        currentBookID = nil
        currentPath = nil
        scrollY = 0
        navigationToken = UUID()
        searchQuery = ""
    }

    func open(_ path: String, scrollY: Double = 0, searchQuery: String? = nil) {
        currentPath = path
        self.scrollY = scrollY
        navigationToken = UUID()
        self.searchQuery = searchQuery ?? ""
    }

    func synchronizeCommittedNavigation(bookID: UUID, path: String) {
        guard currentBookID == bookID else { return }
        currentPath = path
    }

    func synchronizeScroll(bookID: UUID, path: String, scrollY: Double) {
        guard currentBookID == bookID,
              let currentPath,
              SecurityPolicy.documentPath(currentPath) == SecurityPolicy.documentPath(path)
        else {
            return
        }
        self.scrollY = scrollY
    }
}
