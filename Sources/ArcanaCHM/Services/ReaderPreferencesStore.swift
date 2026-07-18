import SwiftUI

@MainActor
final class ReaderPreferencesStore: ObservableObject {
    @Published var fontScale: Double = 1.0
    @Published var spotlightMode = false
    @Published var darkMode: Bool {
        didSet { UserDefaults.standard.set(darkMode, forKey: "ArcanaCHM.darkMode") }
    }

    init() {
        darkMode = UserDefaults.standard.bool(forKey: "ArcanaCHM.darkMode")
    }
}
