import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct LibraryFile: Codable, Sendable {
    var schemaVersion: Int
    var books: [Book]
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published var books: [Book] = []
    @Published var selectedBookID: Book.ID?
    @Published var isImporting = false
    @Published var isRebuildingLibrary = false
    @Published var rebuildPreview: LibraryRebuildPreview?
    @Published var errorMessage: String?

    let scrollPositions: ScrollPositionStore
    private let directories: AppDirectories
    private let fileManager: FileManager
    private let repository: LibraryRepository
    private let rebuilder: LibraryRebuilder
    private var persistenceTask: Task<Void, Never>?

    init(directories: AppDirectories = .production, fileManager: FileManager = .default) {
        self.directories = directories
        self.fileManager = fileManager
        scrollPositions = ScrollPositionStore(directories: directories)
        repository = LibraryRepository(directories: directories)
        rebuilder = LibraryRebuilder(directories: directories)
    }

    var selectedBook: Book? {
        guard let selectedBookID else { return books.first }
        return books.first { $0.id == selectedBookID }
    }

    func book(id: Book.ID?) -> Book? {
        guard let id else { return nil }
        return books.first { $0.id == id }
    }

    func load() async {
        scrollPositions.load()
        do {
            guard let result = try await repository.load() else { return }
            books = result.library.books
            books = books.filter { SecurityPolicy.isInsideBooks($0.rootURL, directories: directories) }
            selectedBookID = books.first?.id
            if result.restoredFromBackup {
                errorMessage = "library_corrupted_restored".loc
            }
            await refreshLibraryMetadata()
        } catch {
            if case LibraryRepositoryError.noUsableBackup = error {
                errorMessage = "library_corrupted_no_backup".loc
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var saveDebounceTask: Task<Void, Never>?

    func save() {
        saveDebounceTask?.cancel()
        saveDebounceTask = nil
        enqueueSave(rotateBackup: true)
    }

    func saveDebounced() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.enqueueSave(rotateBackup: false)
        }
    }

    func flush() async {
        save()
        await persistenceTask?.value
        scrollPositions.flush()
    }

    private func enqueueSave(rotateBackup: Bool) {
        let snapshot = LibraryFile(schemaVersion: LibraryRepository.currentSchemaVersion, books: books)
        let previousTask = persistenceTask
        let repository = repository
        persistenceTask = Task { [weak self] in
            await previousTask?.value
            do {
                try await repository.save(snapshot, rotateBackup: rotateBackup)
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    private func refreshLibraryMetadata() async {
        let snapshot = books
        let updated = await Self.refreshMetadata(for: snapshot)
        guard updated != books else { return }
        books = updated
        save()
    }

    private nonisolated static func refreshMetadata(for books: [Book]) async -> [Book] {
        var results: [Book] = []
        for var book in books {
            let needsReparse = book.toc.isEmpty || anyNilPath(in: book.toc)
            if needsReparse {
                let parser = TOCParser(rootURL: book.rootURL)
                let toc = parser.parse()
                if !toc.isEmpty {
                    book.toc = toc
                    book.homePath = parser.homePath(from: toc) ?? book.homePath
                }
            }
            if book.contentFingerprint?.hasPrefix("sha256-v2:") != true {
                book.contentFingerprint = ContentFingerprint.hashDirectory(book.rootURL)
            }
            results.append(book)
        }
        return results
    }

    private nonisolated static func anyNilPath(in items: [TOCItem]) -> Bool {
        for item in items {
            if item.path == nil { return true }
            if anyNilPath(in: item.children) { return true }
        }
        return false
    }

    func importCHMWithPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let chmType = UTType(filenameExtension: "chm") {
            panel.allowedContentTypes = [chmType]
        }
        if panel.runModal() == .OK, let url = panel.url {
            importCHM(url)
        }
    }

    func importFolderWithPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            importFolder(url)
        }
    }

    func importCHM(_ url: URL) {
        isImporting = true
        let directories = directories
        Task {
            do {
                let book = try await Task.detached(priority: .userInitiated) {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    return try CHMImporter(directories: directories).importCHM(from: url)
                }.value
                finishImport(book)
                populateAfterImport(book.id)
            } catch {
                fail(error)
            }
        }
    }

    func importFolder(_ url: URL) {
        isImporting = true
        let directories = directories
        Task {
            do {
                let book = try await Task.detached(priority: .userInitiated) {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    return try CHMImporter(directories: directories).importExtractedFolder(from: url)
                }.value
                finishImport(book)
                populateAfterImport(book.id)
            } catch {
                fail(error)
            }
        }
    }

    func update(_ book: Book) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index] = book
        sortBooks()
        saveDebounced()
    }

    func togglePin(_ book: Book) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index].isPinned = books[index].isPinned == true ? nil : true
        sortBooks()
        save()
    }

    func delete(_ book: Book) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        let removed = books.remove(at: index)
        if SecurityPolicy.isInsideBooks(removed.rootURL, directories: directories) {
            try? fileManager.removeItem(at: removed.rootURL)
        }
        if selectedBookID == removed.id {
            selectedBookID = books.first?.id
        }
        save()
    }

    func toggleBookmark(path: String, scrollY: Double) {
        guard let bookID = selectedBook?.id else { return }
        toggleBookmark(bookID: bookID, path: path, scrollY: scrollY)
    }

    func toggleBookmark(bookID: Book.ID, path: String, scrollY: Double) {
        guard let idx = books.firstIndex(where: { $0.id == bookID }) else { return }
        if let bmIdx = books[idx].bookmarks.firstIndex(where: { $0.path == path }) {
            books[idx].bookmarks.remove(at: bmIdx)
        } else {
            let title = displayTitle(for: path, in: books[idx])
            books[idx].bookmarks.insert(
                Bookmark(id: UUID(), title: title, path: path, scrollY: scrollY, createdAt: Date()),
                at: 0
            )
        }
        saveDebounced()
    }

    func remember(path: String) {
        guard let selectedBookID else { return }
        remember(bookID: selectedBookID, path: path)
    }

    func remember(bookID: Book.ID, path: String) {
        guard let idx = books.firstIndex(where: { $0.id == bookID }),
              books[idx].lastReadPath != path else { return }
        books[idx].lastReadPath = path
        saveDebounced()
    }

    func search(_ query: String, in book: Book) async -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        return await SearchService().search(trimmed, in: book)
    }

    func prepareLibraryRebuild() async {
        guard !isImporting, !isRebuildingLibrary else { return }
        isRebuildingLibrary = true
        defer { isRebuildingLibrary = false }
        do {
            rebuildPreview = try await rebuilder.preview(existingBooks: books)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelLibraryRebuild() {
        rebuildPreview = nil
    }

    func applyLibraryRebuild(_ preview: LibraryRebuildPreview) async {
        guard rebuildPreview?.id == preview.id, !isImporting, !isRebuildingLibrary else { return }
        isRebuildingLibrary = true
        defer { isRebuildingLibrary = false }
        do {
            let library = LibraryFile(schemaVersion: LibraryRepository.currentSchemaVersion, books: preview.books)
            _ = try await repository.replaceWithRebuild(library)
            books = preview.books
            selectedBookID = books.first?.id
            rebuildPreview = nil
            errorMessage = "library_rebuild_completed".loc(books.count)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finishImport(_ book: Book) {
        if let fingerprint = book.contentFingerprint,
           let duplicate = books.first(where: { $0.contentFingerprint == fingerprint }) {
            selectedBookID = duplicate.id
            isImporting = false
            removeImportedFiles(for: book)
            errorMessage = "library_duplicate".loc
            return
        }

        books.insert(book, at: 0)
        sortBooks()
        selectedBookID = book.id
        isImporting = false
        save()
    }

    private func populateAfterImport(_ bookID: Book.ID) {
        guard let original = books.first(where: { $0.id == bookID }) else { return }
        Task {
            let book = await Task.detached(priority: .userInitiated) { () -> Book in
                var b = original
                CHMImporter.populateBook(&b)
                return b
            }.value
            applyPopulatedMetadata(book, for: bookID)
        }
    }

    func applyPopulatedMetadata(_ populatedBook: Book, for bookID: Book.ID) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        var book = populatedBook
        if let fingerprint = book.contentFingerprint,
           let duplicate = books.first(where: { $0.id != bookID && $0.contentFingerprint == fingerprint }) {
            let duplicateID = duplicate.id
            books.remove(at: index)
            selectedBookID = duplicateID
            errorMessage = "library_duplicate".loc
            removeImportedFiles(for: book)
        } else {
            book.id = books[index].id
            books[index] = book
        }
        save()
    }

    private func sortBooks() {
        books.sort { lhs, rhs in
            if (lhs.isPinned == true) != (rhs.isPinned == true) {
                return lhs.isPinned == true
            }
            return lhs.importedAt > rhs.importedAt
        }
    }

    private func removeImportedFiles(for book: Book) {
        if SecurityPolicy.isInsideBooks(book.rootURL, directories: directories) {
            try? fileManager.removeItem(at: book.rootURL)
        }
    }

    private func fail(_ error: Error) {
        isImporting = false
        guard let importError = error as? CHMImportError else {
            errorMessage = error.localizedDescription
            return
        }
        switch importError {
        case .extractorMissing:
            errorMessage = "error_no_extractor".loc
        case .extractionFailed(let message):
            errorMessage = "error_extraction_failed".loc(message)
        case .noReadableContent:
            errorMessage = "error_no_content".loc
        case .unsafeArchiveContent(let message), .resourceLimitExceeded(let message):
            errorMessage = "error_unsafe_content".loc(message)
        case .extractionTimedOut:
            errorMessage = "error_extraction_failed".loc("extraction exceeded the time limit")
        }
    }

    private func displayTitle(for path: String, in book: Book) -> String {
        let documentPath = SecurityPolicy.documentPath(path)
        func walk(_ items: [TOCItem]) -> String? {
            for item in items {
                if let itemPath = item.path,
                   SecurityPolicy.documentPath(itemPath) == documentPath {
                    return item.title
                }
                if let child = walk(item.children) {
                    return child
                }
            }
            return nil
        }
        return walk(book.toc) ?? URL(fileURLWithPath: documentPath).deletingPathExtension().lastPathComponent
    }
}

extension JSONEncoder {
    static var reader: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var reader: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
