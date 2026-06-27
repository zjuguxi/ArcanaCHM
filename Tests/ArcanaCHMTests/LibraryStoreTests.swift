import XCTest
@testable import ArcanaCHM

@MainActor
final class LibraryStoreTests: XCTestCase {

    private var store: LibraryStore!

    override func setUp() {
        super.setUp()
        store = LibraryStore()
        removeTestData()
        try? AppPaths.ensure()
    }

    override func tearDown() {
        store = nil
        removeTestData()
        super.tearDown()
    }

    private func removeTestData() {
        try? FileManager.default.removeItem(at: AppPaths.libraryFile)
        try? FileManager.default.removeItem(at: AppPaths.backupFile)
    }

    private func writeLibrary(_ data: Data) throws {
        try data.write(to: AppPaths.libraryFile, options: [.atomic])
    }

    private func makeBook(title: String) -> Book {
        let path = AppPaths.booksDirectory.appendingPathComponent("test-\(UUID().uuidString)")
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

    // MARK: - Save

    func testSave_andLoadRoundtrip() async throws {
        let book = makeBook(title: "Roundtrip")
        store.books = [book]
        store.save()

        let newStore = LibraryStore()
        await newStore.load()
        XCTAssertEqual(newStore.books.count, 1)
        XCTAssertEqual(newStore.books[0].title, "Roundtrip")
    }

    func testSave_createsBackup() async throws {
        let book1 = makeBook(title: "First")
        store.books = [book1]
        store.save() // writes library.json (no prior file → no backup)
        store.save() // copies library.json → backup, then overwrites with same
        XCTAssertTrue(FileManager.default.fileExists(atPath: AppPaths.backupFile.path))

        let book2 = makeBook(title: "Second")
        store.books = [book2]
        store.save()
        // Backup should now contain "First"
        let backupData = try Data(contentsOf: AppPaths.backupFile)
        let lib = try JSONDecoder.reader.decode(LibraryFile.self, from: backupData)
        XCTAssertEqual(lib.books[0].title, "First")
    }

    // MARK: - Backup Restore

    func testLoad_corruptedFileRestoresFromBackup() async throws {
        let book = makeBook(title: "Safe")
        store.books = [book]
        store.save() // writes [book] to library.json
        store.save() // copies library.json → backup, then overwrites with same data

        // Corrupt the main file
        try "garbage".write(to: AppPaths.libraryFile, atomically: true, encoding: .utf8)

        let restored = LibraryStore()
        await restored.load()
        let loadedBook = try XCTUnwrap(restored.books.first, "err=\(restored.errorMessage ?? "nil")")
        XCTAssertEqual(loadedBook.title, "Safe")
        XCTAssertNotNil(restored.errorMessage)
    }

    func testLoad_corruptedNoBackup() async throws {
        try "garbage".write(to: AppPaths.libraryFile, atomically: true, encoding: .utf8)
        let store = LibraryStore()
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

    // MARK: - Notes

    func testAddNote() {
        let book = makeBook(title: "Notes")
        store.books = [book]
        store.selectedBookID = book.id
        store.addOrUpdateNote(path: "p.html", title: "My Note", body: "Body text")
        XCTAssertEqual(store.selectedBook?.notes.count, 1)
        XCTAssertEqual(store.selectedBook?.notes[0].title, "My Note")
    }

    func testUpdateNote() {
        let book = makeBook(title: "Notes")
        store.books = [book]
        store.selectedBookID = book.id
        store.addOrUpdateNote(path: "p.html", title: "Original", body: "Body")
        store.addOrUpdateNote(path: "p.html", title: "Updated", body: "New body")
        XCTAssertEqual(store.selectedBook?.notes.count, 1)
        XCTAssertEqual(store.selectedBook?.notes[0].title, "Updated")
        XCTAssertEqual(store.selectedBook?.notes[0].body, "New body")
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
}
