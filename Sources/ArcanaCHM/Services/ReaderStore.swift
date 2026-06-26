import Foundation
import SwiftUI

@MainActor
final class ReaderStore: ObservableObject {
    @Published var currentPath: String?
    @Published var scrollY: Double = 0
    @Published var fontScale: Double = 1.0
    @Published var spotlightMode = false
    @Published var searchQuery = ""
    @Published var navigationToken = UUID()
    @Published var darkMode: Bool {
        didSet {
            UserDefaults.standard.set(darkMode, forKey: "ArcanaCHM.darkMode")
        }
    }

    init() {
        darkMode = UserDefaults.standard.bool(forKey: "ArcanaCHM.darkMode")
    }

    func open(_ path: String, scrollY: Double = 0, searchQuery: String? = nil) {
        currentPath = path
        self.scrollY = scrollY
        navigationToken = UUID()
        self.searchQuery = searchQuery ?? ""
    }
}
