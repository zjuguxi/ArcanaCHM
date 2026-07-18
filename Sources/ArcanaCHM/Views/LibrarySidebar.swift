import SwiftUI

struct LibrarySidebar: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var workspace: ReaderWorkspaceStore
    @EnvironmentObject private var locale: LocalizationService
    @State private var pendingDeleteBook: Book?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("sidebar_documents".loc)
                    .font(.headline)
                Spacer()
                Button {
                    library.importCHMWithPanel()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help("sidebar_import_chm_help".loc)
            }
            .padding()

            ScrollViewReader { proxy in
                List(selection: bookSelection) {
                    ForEach(library.books) { book in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                if book.isPinned == true {
                                    Image(systemName: "pin.fill")
                                        .font(.caption)
                                        .foregroundStyle(.teal)
                                }
                                Text(book.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .lineLimit(2)
                            }
                            HStack(spacing: 8) {
                                Label("\(book.bookmarks.count)", systemImage: "bookmark")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        .help("sidebar_open_document".loc(book.title))
                        .contextMenu {
                            Button {
                                library.togglePin(book)
                            } label: {
                                Label(book.isPinned == true ? "sidebar_unpin".loc : "sidebar_pin".loc, systemImage: book.isPinned == true ? "pin.slash" : "pin")
                            }
                            Button {
                                openInNewTab(book)
                            } label: {
                                Label("sidebar_open_new_tab".loc, systemImage: "plus.square.on.square")
                            }
                            Button(role: .destructive) {
                                pendingDeleteBook = book
                            } label: {
                                Label("sidebar_delete".loc, systemImage: "trash")
                            }
                        }
                        .tag(book.id)
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: library.selectedBookID) { _, newID in
                    if let newID {
                        withAnimation {
                            proxy.scrollTo(newID, anchor: .top)
                        }
                    }
                }
                .onChange(of: workspace.activeTabID) { _, _ in
                    if let bookID = workspace.activeTab.bookID {
                        withAnimation {
                            proxy.scrollTo(bookID, anchor: .top)
                        }
                    }
                }
                .overlay {
                    if library.books.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "book.pages")
                                .font(.system(size: 36))
                                .foregroundStyle(.tertiary)
                            Text("ArcanaCHM")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("reader_start_reading".loc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("reader_import_chm".loc) {
                                library.importCHMWithPanel()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.teal)
                            .controlSize(.small)
                            Spacer()
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            openDefaultBookIfNeeded()
        }
        .onChange(of: library.selectedBookID) { _, _ in
            openDefaultBookIfNeeded()
        }
        .alert("sidebar_delete_confirm_title".loc, isPresented: Binding(
            get: { pendingDeleteBook != nil },
            set: { if !$0 { pendingDeleteBook = nil } }
        )) {
            Button("sidebar_delete".loc, role: .destructive) {
                if let book = pendingDeleteBook {
                    workspace.closeTabs(forBookID: book.id)
                    library.delete(book)
                }
                pendingDeleteBook = nil
            }
            Button("sidebar_cancel".loc, role: .cancel) {
                pendingDeleteBook = nil
            }
        } message: {
            Text("sidebar_delete_confirm_message".loc(pendingDeleteBook?.title ?? ""))
        }
    }

    private var bookSelection: Binding<Book.ID?> {
        Binding {
            workspace.activeTab.bookID
        } set: { bookID in
            guard let book = library.book(id: bookID) else { return }
            openBookInActiveTab(book)
        }
    }

    private func openDefaultBookIfNeeded() {
        guard workspace.activeTab.bookID == nil,
              let book = library.selectedBook
        else { return }
        openBookInActiveTab(book)
    }

    private func openBookInActiveTab(_ book: Book) {
        let path = book.lastReadPath ?? book.homePath
        workspace.openBook(
            bookID: book.id,
            path: path,
            scrollY: library.scrollPositions.scrollY(
                bookID: book.id,
                path: path.map(SecurityPolicy.documentPath)
            )
        )
    }

    private func openInNewTab(_ book: Book) {
        guard workspace.tabs.count < ReaderWorkspaceStore.maximumTabCount else { return }
        workspace.newTab()
        openBookInActiveTab(book)
    }
}
