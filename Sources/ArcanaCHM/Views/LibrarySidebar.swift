import SwiftUI

struct LibrarySidebar: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var reader: ReaderStore
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

            List(selection: $library.selectedBookID) {
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
                            Label("\(book.notes.count)", systemImage: "note.text")
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
            .overlay {
                if library.books.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "books.vertical")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("sidebar_no_documents".loc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: library.selectedBookID) { _, _ in
            if let book = library.selectedBook, let path = book.lastReadPath ?? book.homePath {
                reader.open(path, scrollY: library.scrollPositions.scrollY(bookID: book.id, path: path))
            }
        }
        .onChange(of: library.books) { _, _ in
            if let book = library.selectedBook, reader.currentPath == nil, let path = book.lastReadPath ?? book.homePath {
                reader.open(path, scrollY: library.scrollPositions.scrollY(bookID: book.id, path: path))
            }
        }
        .alert("sidebar_delete_confirm_title".loc, isPresented: Binding(
            get: { pendingDeleteBook != nil },
            set: { if !$0 { pendingDeleteBook = nil } }
        )) {
            Button("sidebar_delete".loc, role: .destructive) {
                if let book = pendingDeleteBook {
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
}
