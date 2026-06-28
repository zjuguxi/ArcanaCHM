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
            refreshImportedTOCs()
            refreshContentFingerprints()
            selectedBookID = books.first?.id
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
        refreshImportedTOCs()
        refreshContentFingerprints()
        selectedBookID = books.first?.id
        save()
        errorMessage = "library_corrupted_restored".loc
    }

    func save() {
        do {
            try AppPaths.ensure()
            if FileManager.default.fileExists(atPath: AppPaths.libraryFile.path) {
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

    private func refreshImportedTOCs() {
        var changed = false
        for index in books.indices where books[index].toc.isEmpty {
            let parser = TOCParser(rootURL: books[index].rootURL)
            let toc = parser.parse()
            guard !toc.isEmpty else { continue }
            books[index].toc = toc
            books[index].homePath = parser.homePath(from: toc) ?? books[index].homePath
            changed = true
        }
        if changed {
            save()
        }
    }

    private func refreshContentFingerprints() {
        var changed = false
        for index in books.indices where books[index].contentFingerprint == nil {
            books[index].contentFingerprint = ContentFingerprint.hashDirectory(books[index].rootURL)
            changed = true
        }
        if changed {
            save()
        }
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let book = try CHMImporter().importCHM(from: url)
                DispatchQueue.main.async {
                    self.finishImport(book)
                }
            } catch {
                DispatchQueue.main.async {
                    self.fail(error)
                }
            }
        }
    }

    func importFolder(_ url: URL) {
        isImporting = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let book = try CHMImporter().importExtractedFolder(from: url)
                DispatchQueue.main.async {
                    self.finishImport(book)
                }
            } catch {
                DispatchQueue.main.async {
                    self.fail(error)
                }
            }
        }
    }

    func update(_ book: Book) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index] = book
        sortBooks()
        save()
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
        guard var book = selectedBook else { return }
        if let index = book.bookmarks.firstIndex(where: { $0.path == path }) {
            book.bookmarks.remove(at: index)
            update(book)
            return
        }

        let title = displayTitle(for: path, in: book)
        book.bookmarks.insert(Bookmark(id: UUID(), title: title, path: path, scrollY: scrollY, createdAt: Date()), at: 0)
        update(book)
    }

    func remember(path: String) {
        guard var book = selectedBook, book.lastReadPath != path else { return }
        book.lastReadPath = path
        update(book)
    }

    func search(_ query: String, in book: Book) async -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        return await withUnsafeContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let hits = SearchService().search(trimmed, in: book)
                continuation.resume(returning: hits)
            }
        }
    }

    private func finishImport(_ book: Book) {
        if let duplicate = duplicateBook(for: book) {
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
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
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
