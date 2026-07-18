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

            ScrollViewReader { proxy in
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
                .onChange(of: library.selectedBookID) { _, newID in
                    if let newID {
                        withAnimation {
                            proxy.scrollTo(newID, anchor: .top)
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
        .onChange(of: library.selectedBookID) { _, _ in
            synchronizeReadingSession()
        }
        .onChange(of: library.books) { _, _ in
            synchronizeReadingSession()
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

    private func synchronizeReadingSession() {
        guard let book = library.selectedBook else {
            reader.endSession()
            return
        }
        guard reader.currentBookID != book.id else { return }
        let path = book.lastReadPath ?? book.homePath
        reader.beginSession(
            bookID: book.id,
            path: path,
            scrollY: library.scrollPositions.scrollY(
                bookID: book.id,
                path: path.map(SecurityPolicy.documentPath)
            )
        )
    }
}
