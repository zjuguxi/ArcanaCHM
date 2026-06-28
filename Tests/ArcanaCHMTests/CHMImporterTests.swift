import XCTest
@testable import ArcanaCHM

final class CHMImporterTests: XCTestCase {

    // MARK: - Utilities

    private var importer: CHMImporter { CHMImporter() }

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
        if SecurityPolicy.isInsideAppBooks(book.rootURL) {
            try? FileManager.default.removeItem(at: book.rootURL)
        }
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
        try AppPaths.ensure()

        let book = try importer.importExtractedFolder(from: source)
        addTeardownBlock { [book] in self.cleanUp(book: book) }

        XCTAssertEqual(book.title, source.lastPathComponent)
        XCTAssertEqual(book.toc.count, 2)
        XCTAssertEqual(book.toc[0].title, "Chapter 1")
        XCTAssertEqual(book.toc[0].path, "ch1.html")
        XCTAssertEqual(book.toc[1].title, "Chapter 2")
        XCTAssertEqual(book.homePath, "ch1.html")
        XCTAssertEqual(book.lastReadPath, book.homePath)
        XCTAssertNotNil(book.contentFingerprint)
        // files were copied into books directory
        XCTAssertTrue(SecurityPolicy.isInsideAppBooks(book.rootURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: book.rootURL.appendingPathComponent("ch1.html").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: book.rootURL.appendingPathComponent("style.css").path))
    }

    func testImportExtractedFolder_noHHC_fallbackFlatTOC() throws {
        let source = try createSource(files: [
            "intro.html": "<html><body>Intro</body></html>",
            "advanced.html": "<html><body>Advanced</body></html>",
        ])
        try AppPaths.ensure()

        let book = try importer.importExtractedFolder(from: source)
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
        try AppPaths.ensure()

        let book = try importer.importExtractedFolder(from: source)
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
        try AppPaths.ensure()

        let book = try importer.importExtractedFolder(from: source)
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
        try AppPaths.ensure()

        let book1 = try importer.importExtractedFolder(from: source)
        addTeardownBlock { [book1] in self.cleanUp(book: book1) }

        let book2 = try importer.importExtractedFolder(from: source)
        addTeardownBlock { [book2] in self.cleanUp(book: book2) }

        XCTAssertEqual(book1.contentFingerprint, book2.contentFingerprint,
                       "identical sources must produce the same fingerprint")
    }

    // MARK: - importExtractedFolder — error paths

    func testImportExtractedFolder_noReadableContent_emptyDir() throws {
        let source = try createSource(files: [:])
        try AppPaths.ensure()

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
        try AppPaths.ensure()

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
        try AppPaths.ensure()

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
        try AppPaths.ensure()

        // Count books directories before
        let before = try FileManager.default.contentsOfDirectory(at: AppPaths.booksDirectory, includingPropertiesForKeys: nil)

        XCTAssertThrowsError(try importer.importExtractedFolder(from: source))

        // Verify stub destination was removed
        let after = try FileManager.default.contentsOfDirectory(at: AppPaths.booksDirectory, includingPropertiesForKeys: nil)
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

        let restricted = CHMImporter(fileManager: RestrictedFileManager())
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
