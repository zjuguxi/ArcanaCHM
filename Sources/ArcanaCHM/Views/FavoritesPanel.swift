import SwiftUI

struct FavoritesPanel: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var reader: ReaderStore
    @EnvironmentObject private var locale: LocalizationService
    let book: Book

    var body: some View {
        if book.bookmarks.isEmpty {
            List {
                HStack(spacing: 8) {
                    Image(systemName: "bookmark")
                        .foregroundStyle(.secondary)
                    Text("favorites_no_bookmarks".loc)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 5)
                .help("favorites_no_bookmarks".loc)
            }
            .listStyle(.inset)
        } else {
            List(book.bookmarks) { bookmark in
                Button {
                    reader.open(bookmark.path, scrollY: bookmark.scrollY)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(bookmark.title, systemImage: "bookmark")
                            .lineLimit(2)
                        Text(bookmark.createdAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("favorites_help_open".loc(bookmark.title))
            }
            .listStyle(.inset)
        }
    }
}
