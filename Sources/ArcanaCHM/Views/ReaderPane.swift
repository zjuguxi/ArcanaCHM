import SwiftUI

struct ReaderPane: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var reader: ReaderStore
    @EnvironmentObject private var preferences: ReaderPreferencesStore
    @EnvironmentObject private var workspace: ReaderWorkspaceStore
    @EnvironmentObject private var locale: LocalizationService
    @ObservedObject var tab: ReaderTabSession
    let isActive: Bool
    @StateObject private var navigationController = ReaderNavigationController()

    @State private var hoveredToolbarTitle: String?
    @State private var showFindBar = false
    @State private var findQuery = ""
    @State private var findCurrentMatch = 0
    @State private var findTotalMatches = 0
    @State private var findNavigationTrigger = UUID()
    @State private var findDirection: FindDirection = .next
    @FocusState private var findFieldFocused: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                toolbar
                if showFindBar {
                    findBar
                    Divider()
                }
                Divider()

                if let book = library.book(id: tab.bookID), let path = reader.currentPath ?? book.homePath {
                    WebReaderView(
                        book: book,
                        navigationController: navigationController,
                        path: path,
                        scrollY: reader.scrollY,
                        fontScale: preferences.fontScale,
                        spotlightMode: preferences.spotlightMode,
                        searchQuery: reader.searchQuery,
                        navigationToken: reader.navigationToken,
                        onNavigationCommitted: { bookID, path in
                            guard tab.bookID == bookID else { return }
                            reader.synchronizeCommittedNavigation(bookID: bookID, path: path)
                        },
                        onNavigationFinished: { bookID, path in
                            guard tab.bookID == bookID else { return }
                            reader.synchronizeCommittedNavigation(bookID: bookID, path: path)
                            if workspace.activeTabID == tab.id {
                                library.remember(bookID: bookID, path: path)
                            }
                        },
                        onScroll: { bookID, path, scrollY in
                            guard tab.bookID == bookID else { return }
                            reader.synchronizeScroll(bookID: bookID, path: path, scrollY: scrollY)
                            library.scrollPositions.save(
                                bookID: bookID,
                                path: SecurityPolicy.documentPath(path),
                                scrollY: scrollY
                            )
                        },
                        onTitle: { title in
                            tab.pageTitle = title.nilIfBlank() ?? book.title
                        },
                        findQuery: findQuery,
                        findNavigationTrigger: findNavigationTrigger,
                        findDirection: findDirection,
                        onFindResults: { current, total in
                            findCurrentMatch = current
                            findTotalMatches = total
                        }
                    )
                    .id(book.id)
                } else {
                    Color.clear
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
        .onChange(of: showFindBar) { _, newValue in
            if newValue {
                findFieldFocused = true
            } else {
                findQuery = ""
                findTotalMatches = 0
                findCurrentMatch = 0
            }
        }
        .onChange(of: tab.bookID) { _, _ in
            navigationController.reset()
            tab.pageTitle = ""
        }
        .background {
            Group {
                Button("") { showFindBar = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .hidden()
                    .disabled(!isActive)
                Button("") { navigationController.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .hidden()
                    .disabled(!isActive || !navigationController.canGoBack)
                Button("") { navigationController.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                    .hidden()
                    .disabled(!isActive || !navigationController.canGoForward)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            ReaderToolbarButton(
                title: "reader_back".loc,
                systemImage: "chevron.left",
                isDisabled: !navigationController.canGoBack,
                hoveredTitle: $hoveredToolbarTitle
            ) {
                navigationController.goBack()
            }

            ReaderToolbarButton(
                title: "reader_forward".loc,
                systemImage: "chevron.right",
                isDisabled: !navigationController.canGoForward,
                hoveredTitle: $hoveredToolbarTitle
            ) {
                navigationController.goForward()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tab.pageTitle.isEmpty ? "reader_no_document".loc : tab.pageTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(library.book(id: tab.bookID)?.title ?? "reader_no_document".loc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            ReaderToolbarButton(title: "reader_find".loc, systemImage: "magnifyingglass", isActive: showFindBar, hoveredTitle: $hoveredToolbarTitle) {
                showFindBar.toggle()
            }

            ReaderToolbarButton(title: "reader_font_decrease".loc, systemImage: "textformat.size.smaller", hoveredTitle: $hoveredToolbarTitle) {
                preferences.fontScale = max(0.82, preferences.fontScale - 0.08)
            }

            ReaderToolbarButton(title: "reader_font_increase".loc, systemImage: "textformat.size.larger", hoveredTitle: $hoveredToolbarTitle) {
                preferences.fontScale = min(1.42, preferences.fontScale + 0.08)
            }

            ReaderToolbarButton(
                title: "reader_focus_mode".loc,
                systemImage: preferences.spotlightMode ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
                isActive: preferences.spotlightMode,
                hoveredTitle: $hoveredToolbarTitle
            ) {
                preferences.spotlightMode.toggle()
            }

            ReaderToolbarButton(
                title: isCurrentPageBookmarked ? "reader_bookmarked".loc : "reader_bookmark".loc,
                systemImage: isCurrentPageBookmarked ? "bookmark.fill" : "bookmark",
                isActive: isCurrentPageBookmarked,
                isDisabled: activeReadingPath == nil,
                hoveredTitle: $hoveredToolbarTitle
            ) {
                if let path = activeReadingPath {
                    if let bookID = tab.bookID {
                        library.toggleBookmark(bookID: bookID, path: path, scrollY: reader.scrollY)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("reader_find_placeholder".loc, text: $findQuery)
                .textFieldStyle(.plain)
                .focused($findFieldFocused)
                .onSubmit {
                    findDirection = .next
                    findNavigationTrigger = UUID()
                }

            if findTotalMatches > 0 {
                Text("\(findCurrentMatch)/\(findTotalMatches)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 40)
                    .monospacedDigit()
            }

            Button {
                findDirection = .previous
                findNavigationTrigger = UUID()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(findTotalMatches == 0)
            .help("reader_find_previous".loc)

            Button {
                findDirection = .next
                findNavigationTrigger = UUID()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .disabled(findTotalMatches == 0)
            .help("reader_find_next".loc)

            Button {
                showFindBar = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("reader_find_close".loc)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var activeReadingPath: String? {
        reader.currentPath ?? library.book(id: tab.bookID)?.homePath
    }

    private var isCurrentPageBookmarked: Bool {
        guard let path = activeReadingPath,
              let book = library.book(id: tab.bookID)
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
