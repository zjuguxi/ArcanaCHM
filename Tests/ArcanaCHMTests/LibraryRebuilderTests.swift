import XCTest
@testable import ArcanaCHM

final class LibraryRebuilderTests: XCTestCase {
    private var testRoot: URL!
    private var directories: AppDirectories!

    override func setUpWithError() throws {
        try super.setUpWithError()
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArcanaCHMRebuilderTests-\(UUID().uuidString)", isDirectory: true)
        directories = AppDirectories(appSupport: testRoot)
        try directories.ensure()
    }

    override func tearDownWithError() throws {
        if let testRoot, testRoot.path.contains("ArcanaCHMRebuilderTests-") {
            try? FileManager.default.removeItem(at: testRoot)
        }
        directories = nil
        testRoot = nil
        try super.tearDownWithError()
    }

    private func makeBookDirectory(
        name: String = UUID().uuidString,
        title: String,
        projectTitle: String? = nil,
        body: String = "content"
    ) throws -> URL {
        let root = directories.booksDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "<html><head><title>\(title)</title></head><body>\(body)</body></html>"
            .write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        if let projectTitle {
            try "[OPTIONS]\nTitle=\(projectTitle)\nDefault topic=index.html\n"
                .write(to: root.appendingPathComponent("book.hhp"), atomically: true, encoding: .utf8)
        }
        return root
    }

    func testPreviewRecoversTitleFromProjectMetadata() async throws {
        let root = try makeBookDirectory(title: "HTML Title", projectTitle: "Project Title")
        let preview = try await LibraryRebuilder(directories: directories).preview(existingBooks: [])

        XCTAssertEqual(preview.scannedDirectoryCount, 1)
        XCTAssertEqual(preview.recoveredBookCount, 1)
        XCTAssertEqual(preview.books.first?.title, "Project Title")
        XCTAssertEqual(preview.books.first?.homePath, "index.html")
        XCTAssertEqual(preview.books.first?.rootURL.standardizedFileURL, root.standardizedFileURL)
        XCTAssertTrue(preview.books.first?.contentFingerprint?.hasPrefix("sha256-v2:") == true)
    }

    func testPreviewPreservesMatchingUserMetadata() async throws {
        let root = try makeBookDirectory(title: "Recovered")
        var existing = Book.empty(title: "User Title", rootURL: root)
        existing.isPinned = true
        existing.lastReadPath = "index.html"
        existing.bookmarks = [Bookmark(id: UUID(), title: "Saved", path: "index.html", scrollY: 42, createdAt: Date())]

        let preview = try await LibraryRebuilder(directories: directories).preview(existingBooks: [existing, existing])

        let rebuilt = try XCTUnwrap(preview.books.first)
        XCTAssertEqual(preview.preservedBookCount, 1)
        XCTAssertEqual(rebuilt.id, existing.id)
        XCTAssertEqual(rebuilt.title, "User Title")
        XCTAssertEqual(rebuilt.bookmarks, existing.bookmarks)
        XCTAssertEqual(rebuilt.lastReadPath, "index.html")
        XCTAssertEqual(rebuilt.isPinned, true)
    }

    func testPreviewSkipsUnreadableAndDuplicateDirectories() async throws {
        _ = try makeBookDirectory(name: "a", title: "First", body: "same")
        _ = try makeBookDirectory(name: "b", title: "First", body: "same")
        let empty = directories.booksDirectory.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        let preview = try await LibraryRebuilder(directories: directories).preview(existingBooks: [])

        XCTAssertEqual(preview.scannedDirectoryCount, 3)
        XCTAssertEqual(preview.books.count, 1)
        XCTAssertEqual(Set(preview.warnings.map(\.reason)), [.duplicateContent, .noReadableContent])
    }

    func testReplaceWithRebuildSnapshotsCorruptedMetadata() async throws {
        let root = try makeBookDirectory(title: "Recovered")
        let originalMain = Data("corrupted-main".utf8)
        let originalBackup = Data("corrupted-backup".utf8)
        try originalMain.write(to: directories.libraryFile)
        try originalBackup.write(to: directories.backupFile)

        let preview = try await LibraryRebuilder(directories: directories).preview(existingBooks: [])
        let repository = LibraryRepository(directories: directories)
        let snapshot = try await repository.replaceWithRebuild(
            LibraryFile(schemaVersion: LibraryRepository.currentSchemaVersion, books: preview.books)
        )

        let snapshotURL = try XCTUnwrap(snapshot)
        XCTAssertEqual(try Data(contentsOf: snapshotURL.appendingPathComponent("library.json")), originalMain)
        XCTAssertEqual(try Data(contentsOf: snapshotURL.appendingPathComponent("library.json.backup")), originalBackup)
        let attributes = try FileManager.default.attributesOfItem(atPath: snapshotURL.appendingPathComponent("library.json").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o400)
        let loaded = try await repository.load()
        XCTAssertEqual(loaded?.library.books.first?.rootURL.standardizedFileURL, root.standardizedFileURL)
    }
}
