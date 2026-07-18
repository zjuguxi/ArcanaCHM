import SwiftUI

struct ReaderWorkspaceCommandActions {
    let newTab: () -> Void
    let closeActiveTabOrWindow: () -> Void
    let selectNextTab: () -> Void
    let selectPreviousTab: () -> Void
}

private struct ReaderWorkspaceCommandActionsKey: FocusedValueKey {
    typealias Value = ReaderWorkspaceCommandActions
}

extension FocusedValues {
    var readerWorkspaceCommands: ReaderWorkspaceCommandActions? {
        get { self[ReaderWorkspaceCommandActionsKey.self] }
        set { self[ReaderWorkspaceCommandActionsKey.self] = newValue }
    }
}

struct ReaderWorkspaceCommandMenu: Commands {
    @FocusedValue(\.readerWorkspaceCommands) private var actions

    var body: some Commands {
        CommandGroup(before: .saveItem) {
            Button("reader_new_tab".loc) {
                actions?.newTab()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(actions == nil)

            Button("reader_close_tab".loc) {
                actions?.closeActiveTabOrWindow()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(actions == nil)

            Button("reader_previous_tab".loc) {
                actions?.selectPreviousTab()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled(actions == nil)

            Button("reader_next_tab".loc) {
                actions?.selectNextTab()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled(actions == nil)
        }
    }
}
