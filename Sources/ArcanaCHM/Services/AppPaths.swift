import Foundation

enum AppPaths {
    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ArcanaCHM", isDirectory: true)
    }

    static var booksDirectory: URL {
        appSupport.appendingPathComponent("Books", isDirectory: true)
    }

    static var libraryFile: URL {
        appSupport.appendingPathComponent("library.json")
    }

    static func ensure() throws {
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
    }
}
