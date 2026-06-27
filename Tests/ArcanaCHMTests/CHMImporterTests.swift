import XCTest
@testable import ArcanaCHM

private final class RestrictedFileManager: FileManager {
    override func isExecutableFile(atPath path: String) -> Bool {
        false
    }
}

final class CHMImporterTests: XCTestCase {

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

    func testFindExtractor_findsBundledExecutable7zz() throws {
        let bundle = try createTestBundle(withExecutable: "7zz")
        let importer = CHMImporter()
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

        let importer = CHMImporter(fileManager: RestrictedFileManager())
        let extractor = importer.findExtractor(in: bundle)
        XCTAssertNil(extractor)
    }
}
