import SwiftUI

@main
struct ArcanaCHMApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var reader = ReaderStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(reader)
                .environmentObject(LocalizationService.shared)
                .frame(minWidth: 1180, minHeight: 760)
                .task {
                    await library.load()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active {
                        Task { await library.flush() }
                    }
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("sidebar_import_chm".loc) {
                    NotificationCenter.default.post(name: .importCHMRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("sidebar_import_folder_menu".loc) {
                    NotificationCenter.default.post(name: .openFolderRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let importCHMRequested = Notification.Name("ArcanaCHM.importCHMRequested")
    static let openFolderRequested = Notification.Name("ArcanaCHM.openFolderRequested")
}
