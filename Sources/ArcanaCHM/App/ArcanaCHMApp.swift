import SwiftUI

@main
struct ArcanaCHMApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var reader = ReaderStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(reader)
                .frame(minWidth: 1180, minHeight: 760)
                .task {
                    await library.load()
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入 CHM...") {
                    NotificationCenter.default.post(name: .importCHMRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("打开已解包目录...") {
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
