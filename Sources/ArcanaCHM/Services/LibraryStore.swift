import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

private let currentSchemaVersion = 1

struct LibraryFile: Codable {
    var schemaVersion: Int
    var books: [Book]
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published var books: [Book] = []
    @Published var selectedBookID: Book.ID?
    @Published var isImporting = false
    @Published var errorMessage: String?

    let scrollPositions = ScrollPositionStore()

    var selectedBook: Book? {
        guard let selectedBookID else { return books.first }
        return books.first { $0.id == selectedBookID }
    }

    func load() async {
        scrollPositions.load()
        do {
            try AppPaths.ensure()
            guard FileManager.default.fileExists(atPath: AppPaths.libraryFile.path) else {
                return
            }
            let data = try Data(contentsOf: AppPaths.libraryFile)
            if let libraryFile = try? JSONDecoder.reader.decode(LibraryFile.self, from: data) {
                books = libraryFile.books
            } else {
                books = try JSONDecoder.reader.decode([Book].self, from: data)
            }
            books = books.filter { SecurityPolicy.isInsideAppBooks($0.rootURL) }
            selectedBookID = books.first?.id
            await refreshLibraryMetadata()
        } catch {
            try? loadFromBackup()
        }
    }

    private func loadFromBackup() throws {
        guard FileManager.default.fileExists(atPath: AppPaths.backupFile.path) else {
            errorMessage = "library_corrupted_no_backup".loc
            return
        }
        let backupData = try Data(contentsOf: AppPaths.backupFile)
        if let libraryFile = try? JSONDecoder.reader.decode(LibraryFile.self, from: backupData) {
            books = libraryFile.books
        } else {
            books = try JSONDecoder.reader.decode([Book].self, from: backupData)
        }
        books = books.filter { SecurityPolicy.isInsideAppBooks($0.rootURL) }
        selectedBookID = books.first?.id
        save()
        errorMessage = "library_corrupted_restored".loc
        Task { await refreshLibraryMetadata() }
    }

    private var saveDebounceTask: Task<Void, Never>?

    func save() {
        saveDebounceTask?.cancel()
        saveDebounceTask = nil
        saveImmediately(backup: true)
    }

    func saveDebounced() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.saveImmediately(backup: false)
        }
    }

    private func saveImmediately(backup: Bool = true) {
        saveDebounceTask?.cancel()
        saveDebounceTask = nil
        do {
            try AppPaths.ensure()
            if backup && FileManager.default.fileExists(atPath: AppPaths.libraryFile.path) {
                try? FileManager.default.removeItem(at: AppPaths.backupFile)
                try FileManager.default.copyItem(at: AppPaths.libraryFile, to: AppPaths.backupFile)
            }
            let libraryFile = LibraryFile(schemaVersion: currentSchemaVersion, books: books)
            let data = try JSONEncoder.reader.encode(libraryFile)
            try data.write(to: AppPaths.libraryFile, options: [.atomic])
        } catch {
            errorMessage = error.localizedDescription
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
            if book.contentFingerprint == nil {
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
        Task {
            do {
                let book = try await Task.detached(priority: .userInitiated) {
                    try CHMImporter().importCHM(from: url)
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
        Task {
            do {
                let book = try await Task.detached(priority: .userInitiated) {
                    try CHMImporter().importExtractedFolder(from: url)
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
        if SecurityPolicy.isInsideAppBooks(removed.rootURL) {
            try? FileManager.default.removeItem(at: removed.rootURL)
        }
        if selectedBookID == removed.id {
            selectedBookID = books.first?.id
        }
        save()
    }

    func toggleBookmark(path: String, scrollY: Double) {
        guard let book = selectedBook,
              let idx = books.firstIndex(where: { $0.id == book.id }) else { return }
        if let bmIdx = books[idx].bookmarks.firstIndex(where: { $0.path == path }) {
            books[idx].bookmarks.remove(at: bmIdx)
        } else {
            let title = displayTitle(for: path, in: books[idx])
            books[idx].bookmarks.insert(
                Bookmark(id: UUID(), title: title, path: path, scrollY: scrollY, createdAt: Date()),
                at: 0
            )
        }
        save()
    }

    func remember(path: String) {
        guard let idx = books.firstIndex(where: { $0.id == selectedBookID }),
              books[idx].lastReadPath != path else { return }
        books[idx].lastReadPath = path
        saveDebounced()
    }

    func search(_ query: String, in book: Book) async -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        return await Task.detached(priority: .userInitiated) {
            SearchService().search(trimmed, in: book)
        }.value
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
            var book = await Task.detached(priority: .userInitiated) { () -> Book in
                var b = original
                CHMImporter.populateBook(&b)
                return b
            }.value
            guard let idx = books.firstIndex(where: { $0.id == bookID }) else { return }
            if let fingerprint = book.contentFingerprint,
               let dupIdx = books.firstIndex(where: { $0.id != bookID && $0.contentFingerprint == fingerprint }) {
                books.remove(at: idx)
                selectedBookID = books[dupIdx].id
                errorMessage = "library_duplicate".loc
                removeImportedFiles(for: book)
            } else {
                book.id = books[idx].id
                books[idx] = book
            }
            save()
        }
    }

    private func sortBooks() {
        books.sort { lhs, rhs in
            if (lhs.isPinned == true) != (rhs.isPinned == true) {
                return lhs.isPinned == true
            }
            return lhs.importedAt > rhs.importedAt
        }
    }

    private func duplicateBook(for book: Book) -> Book? {
        guard let fingerprint = book.contentFingerprint else { return nil }
        return books.first { $0.contentFingerprint == fingerprint }
    }

    private func removeImportedFiles(for book: Book) {
        if SecurityPolicy.isInsideAppBooks(book.rootURL) {
            try? FileManager.default.removeItem(at: book.rootURL)
        }
    }

    private func fail(_ error: Error) {
        isImporting = false
        errorMessage = error.localizedDescription
    }

    private func displayTitle(for path: String, in book: Book) -> String {
        func walk(_ items: [TOCItem]) -> String? {
            for item in items {
                if item.path == path {
                    return item.title
                }
                if let child = walk(item.children) {
                    return child
                }
            }
            return nil
        }
        return walk(book.toc) ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
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
