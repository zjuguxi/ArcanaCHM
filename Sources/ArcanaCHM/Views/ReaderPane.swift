import SwiftUI

struct ReaderPane: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var reader: ReaderStore
    @EnvironmentObject private var locale: LocalizationService

    @State private var currentTitle = ""
    @State private var hoveredToolbarTitle: String?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                toolbar
                Divider()

                if let book = library.selectedBook, let path = reader.currentPath ?? book.homePath {
                    WebReaderView(
                        book: book,
                        path: path,
                        scrollY: reader.scrollY,
                        fontScale: reader.fontScale,
                        spotlightMode: reader.spotlightMode,
                        searchQuery: reader.searchQuery,
                        navigationToken: reader.navigationToken,
                        onNavigate: { path in
                            reader.currentPath = path
                            library.remember(path: path)
                        },
                        onScroll: { path, scrollY in
                            reader.scrollY = scrollY
                            library.scrollPositions.save(bookID: book.id, path: path, scrollY: scrollY)
                        },
                        onTitle: { title in
                            currentTitle = title.nilIfBlank() ?? book.title
                        }
                    )
                } else {
                    VStack(spacing: 0) {
                        Spacer()
                        Image(systemName: "book.pages")
                            .font(.system(size: 42))
                            .foregroundStyle(.tertiary)
                            .padding(.bottom, 16)
                        Text("ArcanaCHM")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("reader_start_reading".loc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 24)
                        Button("reader_import_chm".loc) {
                            library.importCHMWithPanel()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.teal)
                        .controlSize(.large)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))

            if let hoveredToolbarTitle {
                Text(hoveredToolbarTitle)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.top, 48)
                    .padding(.trailing, 16)
                    .allowsHitTesting(false)
                    .zIndex(9999)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(currentTitle.isEmpty ? "reader_no_document".loc : currentTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(library.selectedBook?.title ?? "reader_no_document".loc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            ReaderToolbarButton(title: "reader_font_decrease".loc, systemImage: "textformat.size.smaller", hoveredTitle: $hoveredToolbarTitle) {
                reader.fontScale = max(0.82, reader.fontScale - 0.08)
            }

            ReaderToolbarButton(title: "reader_font_increase".loc, systemImage: "textformat.size.larger", hoveredTitle: $hoveredToolbarTitle) {
                reader.fontScale = min(1.42, reader.fontScale + 0.08)
            }

            ReaderToolbarButton(
                title: "reader_focus_mode".loc,
                systemImage: reader.spotlightMode ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
                isActive: reader.spotlightMode,
                hoveredTitle: $hoveredToolbarTitle
            ) {
                reader.spotlightMode.toggle()
            }

            ReaderToolbarButton(
                title: isCurrentPageBookmarked ? "reader_bookmarked".loc : "reader_bookmark".loc,
                systemImage: isCurrentPageBookmarked ? "bookmark.fill" : "bookmark",
                isActive: isCurrentPageBookmarked,
                isDisabled: activeReadingPath == nil,
                hoveredTitle: $hoveredToolbarTitle
            ) {
                if let path = activeReadingPath {
                    library.toggleBookmark(path: path, scrollY: reader.scrollY)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var activeReadingPath: String? {
        reader.currentPath ?? library.selectedBook?.homePath
    }

    private var isCurrentPageBookmarked: Bool {
        guard let path = activeReadingPath,
              let book = library.selectedBook
        else {
            return false
        }
        return book.bookmarks.contains { $0.path == path }
    }
}

private struct ReaderToolbarButton: View {
    @EnvironmentObject private var locale: LocalizationService
    let title: String
    let systemImage: String
    var isActive = false
    var isDisabled = false
    @Binding var hoveredTitle: String?
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            hoveredTitle = nil
            isHovering = false
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isActive ? .teal : .primary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering ? Color(nsColor: .controlAccentColor).opacity(0.12) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.38 : 1)
        .help(title)
        .onHover { hovering in
            isHovering = hovering
            if hovering && !isDisabled {
                hoveredTitle = title
            } else if hoveredTitle == title {
                hoveredTitle = nil
            }
        }
        .accessibilityLabel(title)
    }
}

private extension String {
    func nilIfBlank() -> String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
