import SwiftUI

struct LibrarySidebar: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var reader: ReaderStore
    @State private var pendingDeleteBook: Book?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("文档")
                    .font(.headline)
                Spacer()
                Button {
                    library.importCHMWithPanel()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help("导入 CHM")
            }
            .padding()

            if library.books.isEmpty {
                ContentUnavailableView {
                    Label("没有文档", systemImage: "books.vertical")
                } description: {
                    Text("导入 CHM 文件或已解包目录。")
                } actions: {
                    Button("导入 CHM") {
                        library.importCHMWithPanel()
                    }
                    .help("导入 CHM 文件")
                    Button("打开目录") {
                        library.importFolderWithPanel()
                    }
                    .help("导入已解包目录")
                }
                .padding()
            } else {
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
                        .help("打开文档：\(book.title)")
                        .contextMenu {
                            Button {
                                library.togglePin(book)
                            } label: {
                                Label(book.isPinned == true ? "取消置顶" : "置顶", systemImage: book.isPinned == true ? "pin.slash" : "pin")
                            }
                            Button(role: .destructive) {
                                pendingDeleteBook = book
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .tag(book.id)
                    }
                }
                .listStyle(.sidebar)
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
        .alert("删除文档？", isPresented: Binding(
            get: { pendingDeleteBook != nil },
            set: { if !$0 { pendingDeleteBook = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let book = pendingDeleteBook {
                    library.delete(book)
                }
                pendingDeleteBook = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteBook = nil
            }
        } message: {
            Text("会从书库中移除“\(pendingDeleteBook?.title ?? "")”，并删除本地解包缓存。原始 CHM 文件不会被删除。")
        }
    }
}
