import Foundation

struct AppDirectories: Sendable {
    let appSupport: URL
    let booksDirectory: URL
    let libraryFile: URL
    let backupFile: URL
    let secondaryBackupFile: URL
    let scrollPositionsFile: URL
    private let legacyAppSupport: URL?

    init(appSupport: URL, legacyAppSupport: URL? = nil) {
        let root = appSupport.standardizedFileURL
        self.appSupport = root
        booksDirectory = root.appendingPathComponent("Books", isDirectory: true)
        libraryFile = root.appendingPathComponent("library.json")
        backupFile = root.appendingPathComponent("library.json.backup")
        secondaryBackupFile = root.appendingPathComponent("library.json.backup.2")
        scrollPositionsFile = root.appendingPathComponent("scroll_positions.json")
        self.legacyAppSupport = legacyAppSupport?.standardizedFileURL
    }

    static let production: AppDirectories = {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        let legacy = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/ArcanaCHM", isDirectory: true)
        return AppDirectories(
            appSupport: supportDir.appendingPathComponent("ArcanaCHM", isDirectory: true),
            legacyAppSupport: legacy
        )
    }()

    func ensure(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
        try migrateLegacyDataIfNeeded(fileManager: fileManager)
    }

    private func migrateLegacyDataIfNeeded(fileManager: FileManager) throws {
        guard let legacyAppSupport,
              legacyAppSupport.path != appSupport.path,
              fileManager.fileExists(atPath: legacyAppSupport.path),
              !fileManager.fileExists(atPath: libraryFile.path)
        else { return }

        let legacyBooks = legacyAppSupport.appendingPathComponent("Books", isDirectory: true)
        if let children = try? fileManager.contentsOfDirectory(at: legacyBooks, includingPropertiesForKeys: nil) {
            for child in children {
                let destination = booksDirectory.appendingPathComponent(child.lastPathComponent, isDirectory: true)
                if !fileManager.fileExists(atPath: destination.path) {
                    try fileManager.copyItem(at: child, to: destination)
                }
            }
        }

        for name in ["library.json", "library.json.backup", "library.json.backup.2", "scroll_positions.json"] {
            let source = legacyAppSupport.appendingPathComponent(name)
            let destination = appSupport.appendingPathComponent(name)
            if fileManager.fileExists(atPath: source.path), !fileManager.fileExists(atPath: destination.path) {
                try fileManager.copyItem(at: source, to: destination)
            }
        }
    }
}

/// Production-only compatibility access. Tests and services must inject AppDirectories.
enum AppPaths {
    static let directories = AppDirectories.production
    static var appSupport: URL { directories.appSupport }
    static var booksDirectory: URL { directories.booksDirectory }
    static var libraryFile: URL { directories.libraryFile }
    static var backupFile: URL { directories.backupFile }

    static func ensure() throws {
        try directories.ensure()
    }
}
