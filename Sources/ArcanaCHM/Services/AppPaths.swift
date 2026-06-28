import Foundation

enum AppPaths {
    private static let _appSupport: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ArcanaCHM", isDirectory: true)
    }()

    static var appSupport: URL { _appSupport }
    static var booksDirectory: URL { _appSupport.appendingPathComponent("Books", isDirectory: true) }
    static var libraryFile: URL { _appSupport.appendingPathComponent("library.json") }
    static var backupFile: URL { _appSupport.appendingPathComponent("library.json.backup") }

    private static var ensured = false
    static func ensure() throws {
        guard !ensured else { return }
        try FileManager.default.createDirectory(at: _appSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
        ensured = true
    }
}
