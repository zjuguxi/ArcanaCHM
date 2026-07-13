import XCTest
@testable import ArcanaCHM

final class CHMImporterTests: XCTestCase {

    // MARK: - Utilities

    private var directories: AppDirectories!
    private var testRoot: URL!
    private var importer: CHMImporter { CHMImporter(directories: directories) }

    override func setUpWithError() throws {
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArcanaCHMImporterTests-\(UUID().uuidString)", isDirectory: true)
        directories = AppDirectories(appSupport: testRoot)
        precondition(testRoot.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        try directories.ensure()
    }

    override func tearDownWithError() throws {
        if let testRoot, testRoot.path.contains("ArcanaCHMImporterTests-") {
            try? FileManager.default.removeItem(at: testRoot)
        }
        directories = nil
        testRoot = nil
    }

    /// Create a temporary source directory with the given file tree.
    /// `files` maps relative paths to file contents; entries ending in "/" are directories.
    private func createSource(
        named name: String = "test-book",
        files: [String: String?]
    ) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("chmtest-src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }

        for (path, content) in files {
            let url = tmp.appendingPathComponent(path)
            if path.hasSuffix("/") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let data = content?.data(using: .utf8) {
                    try data.write(to: url)
                } else {
                    FileManager.default.createFile(atPath: url.path, contents: Data())
                }
            }
        }
        return tmp
    }

    /// Clean up a book that was imported via `importExtractedFolder`.
    private func cleanUp(book: Book) {
        if SecurityPolicy.isInsideBooks(book.rootURL, directories: directories) {
            try? FileManager.default.removeItem(at: book.rootURL)
        }
    }

    // MARK: - Helpers

    /// Import and then populate (parse TOC + fingerprint) to get a fully built book.
    private func importAndPopulate(from source: URL) throws -> Book {
        var book = try importer.importExtractedFolder(from: source)
        CHMImporter.populateBook(&book)
        return book
    }

    // MARK: - importExtractedFolder — happy paths

    func testImportExtractedFolder_withHHC() throws {
        let source = try createSource(files: [
            "test.hhc": """
            <html><body>
            <ul>
              <li><object><param name="Name" value="Chapter 1"><param name="Local" value="ch1.html"></object>
              <li><object><param name="Name" value="Chapter 2"><param name="Local" value="ch2.html"></object>
            </ul>
            </body></html>
            """,
            "ch1.html": "<html><body><h1>Chapter 1</h1></body></html>",
            "ch2.html": "<html><body><h1>Chapter 2</h1></body></html>",
            "style.css": "body { color: red; }",
        ])
        try directories.ensure()

        let book = try importAndPopulate(from: source)
        addTeardownBlock { [book] in self.cleanUp(book: book) }

        XCTAssertEqual(book.title, source.lastPathComponent)
        XCTAssertEqual(book.toc.count, 2)
        XCTAssertEqual(book.toc[0].title, "Chapter 1")
        XCTAssertEqual(book.toc[0].path, "ch1.html")
        XCTAssertEqual(book.toc[1].title, "Chapter 2")
        XCTAssertEqual(book.homePath, "ch1.html")
        XCTAssertEqual(book.lastReadPath, book.homePath)
        // files were copied into books directory
        XCTAssertTrue(SecurityPolicy.isInsideBooks(book.rootURL, directories: directories))
        XCTAssertTrue(FileManager.default.fileExists(atPath: book.rootURL.appendingPathComponent("ch1.html").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: book.rootURL.appendingPathComponent("style.css").path))
    }

    func testImportExtractedFolder_noHHC_fallbackFlatTOC() throws {
        let source = try createSource(files: [
            "intro.html": "<html><body>Intro</body></html>",
            "advanced.html": "<html><body>Advanced</body></html>",
        ])
        try directories.ensure()

        let book = try importAndPopulate(from: source)
        addTeardownBlock { [book] in self.cleanUp(book: book) }

        // Fallback TOC is sorted alphabetically
        XCTAssertEqual(book.toc.count, 2)
        XCTAssertEqual(book.toc[0].title, "advanced")    // sorted: "advanced" < "intro"
        XCTAssertEqual(book.toc[1].title, "intro")
        XCTAssertNotNil(book.homePath)
    }

    func testImportExtractedFolder_noHHC_singleHTML() throws {
        let source = try createSource(files: [
            "index.html": "<html><body>Home</body></html>",
        ])
        try directories.ensure()

        let book = try importAndPopulate(from: source)
        addTeardownBlock { [book] in self.cleanUp(book: book) }

        XCTAssertEqual(book.toc.count, 1)
        XCTAssertEqual(book.toc[0].title, "index")  // auto-generated from filename sans extension
        XCTAssertEqual(book.toc[0].path, "index.html")
        XCTAssertEqual(book.homePath, "index.html")
    }

    func testImportExtractedFolder_nestedSubdirectory() throws {
        let source = try createSource(files: [
            "test.hhc": """
            <html><body>
            <ul><li><object><param name="Name" value="Sub Page"><param name="Local" value="sub/page.html"></object></ul>
            </body></html>
            """,
            "sub/page.html": "<html><body>Nested</body></html>",
        ])
        try directories.ensure()

        let book = try importAndPopulate(from: source)
        addTeardownBlock { [book] in self.cleanUp(book: book) }

        XCTAssertEqual(book.toc.count, 1)
        XCTAssertEqual(book.toc[0].path, "sub/page.html")
        XCTAssertEqual(book.homePath, "sub/page.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: book.rootURL.appendingPathComponent("sub/page.html").path))
    }

    // MARK: - Fingerprint

    func testImportExtractedFolder_fingerprintIsConsistent() throws {
        let source = try createSource(files: [
            "index.html": "<html><body>Hello</body></html>",
        ])
        try directories.ensure()

        var book1 = try importer.importExtractedFolder(from: source)
        addTeardownBlock { [book1] in self.cleanUp(book: book1) }

        var book2 = try importer.importExtractedFolder(from: source)
        addTeardownBlock { [book2] in self.cleanUp(book: book2) }

        // Populate to compute fingerprints
        CHMImporter.populateBook(&book1)
        CHMImporter.populateBook(&book2)

        XCTAssertNotNil(book1.contentFingerprint)
        XCTAssertEqual(book1.contentFingerprint, book2.contentFingerprint,
                       "identical sources must produce the same fingerprint")
    }

    func testFingerprintDiffersWhenFileContentsDiffer() throws {
        let first = try createSource(named: "first", files: [
            "index.html": "<html><body>First</body></html>",
        ])
        let second = try createSource(named: "second", files: [
            "index.html": "<html><body>Second</body></html>",
        ])

        var firstBook = try importer.importExtractedFolder(from: first)
        var secondBook = try importer.importExtractedFolder(from: second)
        addTeardownBlock { [firstBook, secondBook] in
            self.cleanUp(book: firstBook)
            self.cleanUp(book: secondBook)
        }

        CHMImporter.populateBook(&firstBook)
        CHMImporter.populateBook(&secondBook)
        XCTAssertNotEqual(firstBook.contentFingerprint, secondBook.contentFingerprint)
        XCTAssertTrue(firstBook.contentFingerprint?.hasPrefix("sha256-v2:") == true)
    }

    func testImportRejectsExpandedContentOverLimit() throws {
        let source = try createSource(files: [
            "index.html": String(repeating: "x", count: 128),
        ])
        var limits = ExtractionLimits.default
        limits.maximumExpandedBytes = 32
        let limitedImporter = CHMImporter(directories: directories, limits: limits)

        XCTAssertThrowsError(try limitedImporter.importExtractedFolder(from: source)) { error in
            guard case CHMImportError.resourceLimitExceeded = error else {
                return XCTFail("expected resourceLimitExceeded, got \(error)")
            }
        }
    }

    // MARK: - importExtractedFolder — error paths

    func testImportExtractedFolder_noReadableContent_emptyDir() throws {
        let source = try createSource(files: [:])
        try directories.ensure()

        XCTAssertThrowsError(try importer.importExtractedFolder(from: source)) { error in
            guard case CHMImportError.noReadableContent = error else {
                return XCTFail("expected noReadableContent, got \(error)")
            }
        }
    }

    func testImportExtractedFolder_noReadableContent_nonHTMLOnly() throws {
        let source = try createSource(files: [
            "readme.txt": "hello",
            "data.bin": nil,
        ])
        try directories.ensure()

        XCTAssertThrowsError(try importer.importExtractedFolder(from: source)) { error in
            guard case CHMImportError.noReadableContent = error else {
                return XCTFail("expected noReadableContent, got \(error)")
            }
        }
    }

    func testImportExtractedFolder_rejectsSymlink() throws {
        let source = try createSource(files: [
            "index.html": "<html></html>",
        ])
        try FileManager.default.createSymbolicLink(
            at: source.appendingPathComponent("escape"),
            withDestinationURL: FileManager.default.temporaryDirectory
        )
        try directories.ensure()

        XCTAssertThrowsError(try importer.importExtractedFolder(from: source)) { error in
            guard case CHMImportError.unsafeArchiveContent = error else {
                return XCTFail("expected unsafeArchiveContent, got \(error)")
            }
        }
    }

    func testImportExtractedFolder_cleanupOnFailure() throws {
        let source = try createSource(files: [
            "index.html": "<html></html>",
        ])
        // Create a symlink to trigger validation failure
        try FileManager.default.createSymbolicLink(
            at: source.appendingPathComponent("bad"),
            withDestinationURL: FileManager.default.temporaryDirectory
        )
        try directories.ensure()

        // Count books directories before
        let before = try FileManager.default.contentsOfDirectory(at: directories.booksDirectory, includingPropertiesForKeys: nil)

        XCTAssertThrowsError(try importer.importExtractedFolder(from: source))

        // Verify stub destination was removed
        let after = try FileManager.default.contentsOfDirectory(at: directories.booksDirectory, includingPropertiesForKeys: nil)
        XCTAssertEqual(before.count, after.count, "failed import must clean up its stub directory")
    }

    // MARK: - validateExtractedContent (existing tests, preserved)

    func testValidateExtractedContent_rejectsHiddenSymlink() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-hidden-symlink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        try Data("<html></html>".utf8).write(to: root.appendingPathComponent("index.html"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent(".hidden-link"),
            withDestinationURL: FileManager.default.temporaryDirectory
        )

        XCTAssertThrowsError(try importer.validateExtractedContent(at: root)) { error in
            guard case CHMImportError.unsafeArchiveContent = error else {
                return XCTFail("expected unsafeArchiveContent, got \(error)")
            }
        }
    }

    func testValidateExtractedContent_allowsHiddenRegularFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-hidden-file-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        try Data("<html></html>".utf8).write(to: root.appendingPathComponent("index.html"))
        try Data("config".utf8).write(to: root.appendingPathComponent(".hidden"))

        XCTAssertNoThrow(try importer.validateExtractedContent(at: root))
    }

    // MARK: - findExtractor

    func testFindExtractor_findsBundledExecutable7zz() throws {
        let bundle = try createTestBundle(withExecutable: "7zz")
        let extractor = importer.findExtractor(in: bundle)
        XCTAssertNotNil(extractor)
        XCTAssertEqual(extractor?.kind, .sevenZip)
    }

    func testFindExtractor_nonExecutableInBundleNotReturned() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-nonexec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }

        let execPath = tmp.appendingPathComponent("7zz")
        FileManager.default.createFile(atPath: execPath.path, contents: Data())
        // Not executable — omit executable permission

        let infoPlist: [String: Any] = [
            "CFBundlePackageType": "BNDL",
            "CFBundleIdentifier": "com.arcanachm.test"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try plistData.write(to: tmp.appendingPathComponent("Info.plist"))

        guard let bundle = Bundle(url: tmp) else {
            throw XCTSkip("Failed to create test bundle")
        }

        let restricted = CHMImporter(fileManager: RestrictedFileManager(), directories: directories)
        let extractor = restricted.findExtractor(in: bundle)
        XCTAssertNil(extractor)
    }

    // MARK: - Helpers

    private func createTestBundle(withExecutable name: String) throws -> Bundle {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-bundle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }

        let execPath = tmp.appendingPathComponent(name)
        FileManager.default.createFile(atPath: execPath.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: execPath.path)

        let infoPlist: [String: Any] = [
            "CFBundlePackageType": "BNDL",
            "CFBundleIdentifier": "com.arcanachm.test"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try plistData.write(to: tmp.appendingPathComponent("Info.plist"))

        guard let bundle = Bundle(url: tmp) else {
            throw XCTSkip("Failed to create test bundle")
        }
        return bundle
    }
}

private final class RestrictedFileManager: FileManager {
    override func isExecutableFile(atPath path: String) -> Bool {
        false
    }
}
