import XCTest
@testable import ArcanaCHM

@MainActor
final class LibraryStoreTests: XCTestCase {

    private var store: LibraryStore!
    private var directories: AppDirectories!
    private var testRoot: URL!

    override func setUp() {
        super.setUp()
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArcanaCHMTests-\(UUID().uuidString)", isDirectory: true)
        directories = AppDirectories(appSupport: testRoot)
        precondition(testRoot.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        try? directories.ensure()
        store = LibraryStore(directories: directories)
        addTeardownBlock { [weak self] in
            await self?.store?.flush()
        }
    }

    override func tearDown() {
        store = nil
        if let testRoot, testRoot.path.contains("ArcanaCHMTests-") {
            try? FileManager.default.removeItem(at: testRoot)
        }
        directories = nil
        testRoot = nil
        super.tearDown()
    }

    private func writeLibrary(_ data: Data) throws {
        try data.write(to: directories.libraryFile, options: [.atomic])
    }

    private func makeBook(title: String) -> Book {
        let path = directories.booksDirectory.appendingPathComponent("test-\(UUID().uuidString)")
        return Book.empty(title: title, rootURL: path)
    }

    // MARK: - Load

    func testLoad_noFile() async {
        await store.load()
        XCTAssertTrue(store.books.isEmpty)
        XCTAssertNil(store.selectedBookID)
    }

    func testLoad_emptyArray() async throws {
        try writeLibrary(try JSONEncoder.reader.encode([Book]()))
        await store.load()
        XCTAssertTrue(store.books.isEmpty)
    }

    func testLoad_booksFromFile() async throws {
        let book = makeBook(title: "Test")
        let lib = LibraryFile(schemaVersion: 1, books: [book])
        try writeLibrary(try JSONEncoder.reader.encode(lib))
        await store.load()
        XCTAssertEqual(store.books.count, 1)
        XCTAssertEqual(store.books[0].title, "Test")
    }

    func testLoad_legacyBareArray() async throws {
        let book = makeBook(title: "Legacy")
        try writeLibrary(try JSONEncoder.reader.encode([book]))
        await store.load()
        XCTAssertEqual(store.books.count, 1)
        XCTAssertEqual(store.books[0].title, "Legacy")
    }

    func testLoad_futureSchemaIsRejectedWithoutRollback() async throws {
        let future = LibraryFile(schemaVersion: 999, books: [makeBook(title: "Future")])
        try writeLibrary(try JSONEncoder.reader.encode(future))
        let older = LibraryFile(schemaVersion: 1, books: [makeBook(title: "Older Backup")])
        try JSONEncoder.reader.encode(older).write(to: directories.backupFile, options: [.atomic])

        await store.load()

        XCTAssertTrue(store.books.isEmpty)
        XCTAssertTrue(store.errorMessage?.contains("999") == true)
    }

    // MARK: - Save

    func testSave_andLoadRoundtrip() async throws {
        let book = makeBook(title: "Roundtrip")
        store.books = [book]
        await store.flush()

        let newStore = LibraryStore(directories: directories)
        await newStore.load()
        XCTAssertEqual(newStore.books.count, 1)
        XCTAssertEqual(newStore.books[0].title, "Roundtrip")
    }

    func testSave_createsBackup() async throws {
        let book1 = makeBook(title: "First")
        store.books = [book1]
        await store.flush() // writes library.json (no prior file → no backup)
        await store.flush() // copies library.json → backup, then overwrites with same
        XCTAssertTrue(FileManager.default.fileExists(atPath: directories.backupFile.path))

        let book2 = makeBook(title: "Second")
        store.books = [book2]
        await store.flush()
        // Backup should now contain "First"
        let backupData = try Data(contentsOf: directories.backupFile)
        let lib = try JSONDecoder.reader.decode(LibraryFile.self, from: backupData)
        XCTAssertEqual(lib.books[0].title, "First")
    }

    // MARK: - Backup Restore

    func testLoad_corruptedFileRestoresFromBackup() async throws {
        let book = makeBook(title: "Safe")
        store.books = [book]
        await store.flush() // writes [book] to library.json
        await store.flush() // copies library.json → backup, then overwrites with same data

        // Corrupt the main file
        try "garbage".write(to: directories.libraryFile, atomically: true, encoding: .utf8)

        let restored = LibraryStore(directories: directories)
        await restored.load()
        let loadedBook = try XCTUnwrap(restored.books.first, "err=\(restored.errorMessage ?? "nil")")
        XCTAssertEqual(loadedBook.title, "Safe")
        XCTAssertNotNil(restored.errorMessage)

        let preservedBackup = try Data(contentsOf: directories.backupFile)
        let preservedLibrary = try JSONDecoder.reader.decode(LibraryFile.self, from: preservedBackup)
        XCTAssertEqual(preservedLibrary.books.first?.title, "Safe")
    }

    func testLoad_corruptedNoBackup() async throws {
        try "garbage".write(to: directories.libraryFile, atomically: true, encoding: .utf8)
        let store = LibraryStore(directories: directories)
        await store.load()
        XCTAssertTrue(store.books.isEmpty)
        XCTAssertNotNil(store.errorMessage)
    }

    // MARK: - In-Memory Operations

    func testSelectedBook_none() {
        XCTAssertNil(store.selectedBook)
    }

    func testSelectedBook_firstWhenNoSelection() {
        let b1 = makeBook(title: "A")
        let b2 = makeBook(title: "B")
        store.books = [b1, b2]
        XCTAssertEqual(store.selectedBook?.title, "A")
    }

    func testSelectedBook_byID() {
        let b1 = makeBook(title: "A")
        let b2 = makeBook(title: "B")
        store.books = [b1, b2]
        store.selectedBookID = b2.id
        XCTAssertEqual(store.selectedBook?.title, "B")
    }

    func testUpdate() {
        let book = makeBook(title: "Original")
        store.books = [book]
        var updated = book
        updated.title = "Updated"
        store.update(updated)
        XCTAssertEqual(store.books[0].title, "Updated")
    }

    func testUpdate_unknownID() {
        let book = makeBook(title: "Alone")
        store.books = [book]
        let other = makeBook(title: "Ghost")
        store.update(other)
        XCTAssertEqual(store.books.count, 1)
        XCTAssertEqual(store.books[0].title, "Alone")
    }

    func testDuplicatePopulationUsesStableIDAfterRemovingEarlierIndex() {
        var imported = makeBook(title: "Imported")
        imported.contentFingerprint = "sha256-v2:same"
        var existing = makeBook(title: "Existing")
        existing.contentFingerprint = imported.contentFingerprint
        store.books = [imported, existing]

        store.applyPopulatedMetadata(imported, for: imported.id)

        XCTAssertEqual(store.books.map(\.id), [existing.id])
        XCTAssertEqual(store.selectedBookID, existing.id)
    }

    func testTogglePin() {
        let book = makeBook(title: "Pin Me")
        store.books = [book]
        store.togglePin(book)
        XCTAssertEqual(store.books[0].isPinned, true)
    }

    func testTogglePin_unpin() {
        var book = makeBook(title: "Unpin Me")
        book.isPinned = true
        store.books = [book]
        store.togglePin(book)
        XCTAssertNil(store.books[0].isPinned)
    }

    func testTogglePin_sortsPinnedFirst() {
        var a = makeBook(title: "A")
        a.isPinned = true
        let b = makeBook(title: "B")
        store.books = [b, a]
        store.togglePin(b)  // pin B as well

        // Both pinned — newer pin (B) should come first (importedAt closer to now)
        let bImported = store.books[0]
        let aImported = store.books[1]
        XCTAssertEqual(bImported.title, "B")
        XCTAssertEqual(aImported.title, "A")
    }

    func testDelete_removesFromArray() {
        let book = makeBook(title: "Delete Me")
        store.books = [book]
        store.delete(book)
        XCTAssertTrue(store.books.isEmpty)
    }

    func testDelete_switchesSelection() {
        let b1 = makeBook(title: "First")
        let b2 = makeBook(title: "Second")
        store.books = [b1, b2]
        store.selectedBookID = b1.id
        store.delete(b1)
        XCTAssertEqual(store.selectedBookID, b2.id)
    }

    func testDelete_selectionClearsWhenLast() {
        let book = makeBook(title: "Last")
        store.books = [book]
        store.selectedBookID = book.id
        store.delete(book)
        XCTAssertNil(store.selectedBookID)
    }

    // MARK: - Bookmarks

    func testToggleBookmark_add() {
        let book = makeBook(title: "BM")
        store.books = [book]
        store.selectedBookID = book.id
        store.toggleBookmark(path: "page.html", scrollY: 100)
        XCTAssertEqual(store.selectedBook?.bookmarks.count, 1)
        XCTAssertEqual(store.selectedBook?.bookmarks[0].path, "page.html")
    }

    func testToggleBookmark_remove() {
        let book = makeBook(title: "BM")
        store.books = [book]
        store.selectedBookID = book.id
        store.toggleBookmark(path: "page.html", scrollY: 100)
        store.toggleBookmark(path: "page.html", scrollY: 100)
        XCTAssertTrue(store.selectedBook?.bookmarks.isEmpty == true)
    }

    func testToggleBookmark_noSelection() {
        let book = makeBook(title: "No Sel")
        store.books = [book]
        store.toggleBookmark(path: "p.html", scrollY: 0)
        // selectedBook is nil because selectedBookID is nil and there's 1 book
        // selectedBook picks the first book when selectedBookID is nil
        XCTAssertEqual(store.selectedBook?.bookmarks.count, 1)
    }

    func testToggleBookmarkExplicitBookDoesNotUseGlobalSelection() {
        let first = makeBook(title: "First")
        let second = makeBook(title: "Second")
        store.books = [first, second]
        store.selectedBookID = first.id

        store.toggleBookmark(bookID: second.id, path: "second.html", scrollY: 12)

        XCTAssertTrue(store.books[0].bookmarks.isEmpty)
        XCTAssertEqual(store.books[1].bookmarks.first?.path, "second.html")
    }

    // MARK: - Remember

    func testRemember() {
        let book = makeBook(title: "Rem")
        store.books = [book]
        store.selectedBookID = book.id
        store.remember(path: "ch1.html")
        XCTAssertEqual(store.selectedBook?.lastReadPath, "ch1.html")
    }

    func testRemember_samePathNoop() {
        let book = makeBook(title: "Rem")
        store.books = [book]
        store.selectedBookID = book.id
        store.remember(path: "ch1.html")
        store.remember(path: "ch1.html")  // same path, should not update
        XCTAssertEqual(store.selectedBook?.lastReadPath, "ch1.html")
    }

    func testRememberExplicitBookDoesNotUseGlobalSelection() {
        let first = makeBook(title: "First")
        let second = makeBook(title: "Second")
        store.books = [first, second]
        store.selectedBookID = first.id

        store.remember(bookID: second.id, path: "second.html")

        XCTAssertNil(store.books[0].lastReadPath)
        XCTAssertEqual(store.books[1].lastReadPath, "second.html")
    }
}
