import AppKit
import Foundation
import SwiftUI

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
            errorMessage = error.localizedDescription
        }
    }

    func save() {
        do {
            try AppPaths.ensure()
            let libraryFile = LibraryFile(schemaVersion: currentSchemaVersion, books: books)
            let data = try JSONEncoder.reader.encode(libraryFile)
            try data.write(to: AppPaths.libraryFile, options: [.atomic])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshImportedTOCs() {
        var changed = false
        for index in books.indices {
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
        panel.allowedContentTypes = [.init(filenameExtension: "chm")!]
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
        Task.detached {
            do {
                let book = try CHMImporter().importCHM(from: url)
                await self.finishImport(book)
            } catch {
                await self.fail(error)
            }
        }
    }

    func importFolder(_ url: URL) {
        isImporting = true
        Task.detached {
            do {
                let book = try CHMImporter().importExtractedFolder(from: url)
                await self.finishImport(book)
            } catch {
                await self.fail(error)
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
        books[index].isPinned = !(books[index].isPinned == true)
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

    func addOrUpdateNote(path: String, title: String, body: String) {
        guard var book = selectedBook else { return }
        if let index = book.notes.firstIndex(where: { $0.path == path }) {
            book.notes[index].title = title
            book.notes[index].body = body
            book.notes[index].updatedAt = Date()
        } else {
            book.notes.insert(DocumentNote(id: UUID(), title: title, body: body, path: path, createdAt: Date(), updatedAt: Date()), at: 0)
        }
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
        return await Task.detached(priority: .userInitiated) {
            SearchService().search(trimmed, in: book)
        }.value
    }

    private func finishImport(_ book: Book) {
        if let duplicate = duplicateBook(for: book) {
            selectedBookID = duplicate.id
            isImporting = false
            removeImportedFiles(for: book)
            errorMessage = "这个 CHM 文档已经在书库中，已为你打开现有副本。"
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

private extension JSONEncoder {
    static var reader: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var reader: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
