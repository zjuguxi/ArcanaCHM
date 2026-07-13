import Foundation

enum LibraryRepositoryError: LocalizedError {
    case unsupportedSchema(Int)
    case noUsableBackup

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "Unsupported library schema version \(version)."
        case .noUsableBackup:
            return "The library is corrupted and no usable backup was found."
        }
    }
}

struct LibraryLoadResult: Sendable {
    var library: LibraryFile
    var restoredFromBackup: Bool
}

actor LibraryRepository {
    static let currentSchemaVersion = 1

    private let directories: AppDirectories
    private let fileManager: FileManager

    init(directories: AppDirectories) {
        self.directories = directories
        fileManager = .default
    }

    func load() throws -> LibraryLoadResult? {
        try directories.ensure(fileManager: fileManager)
        guard fileManager.fileExists(atPath: directories.libraryFile.path) else { return nil }

        do {
            let data = try Data(contentsOf: directories.libraryFile)
            return LibraryLoadResult(library: try Self.decode(data), restoredFromBackup: false)
        } catch let schemaError as LibraryRepositoryError {
            if case .unsupportedSchema = schemaError { throw schemaError }
            throw schemaError
        } catch {
            var lastError: Error = error
            for backupURL in [directories.backupFile, directories.secondaryBackupFile]
                where fileManager.fileExists(atPath: backupURL.path) {
                do {
                    let backupData = try Data(contentsOf: backupURL)
                    let library = try Self.decode(backupData)
                    try backupData.write(to: directories.libraryFile, options: [.atomic])
                    return LibraryLoadResult(library: library, restoredFromBackup: true)
                } catch {
                    lastError = error
                }
            }
            if lastError is LibraryRepositoryError { throw lastError }
            throw LibraryRepositoryError.noUsableBackup
        }
    }

    func save(_ library: LibraryFile, rotateBackup: Bool) throws {
        try directories.ensure(fileManager: fileManager)
        let data = try JSONEncoder.reader.encode(library)
        _ = try Self.decode(data)

        let previousMain = validatedData(at: directories.libraryFile)
        let previousBackup = validatedData(at: directories.backupFile)
        try data.write(to: directories.libraryFile, options: [.atomic])

        guard rotateBackup else { return }
        if let previousBackup {
            try previousBackup.write(to: directories.secondaryBackupFile, options: [.atomic])
        }
        if let previousMain {
            try previousMain.write(to: directories.backupFile, options: [.atomic])
        }
    }

    func replaceWithRebuild(_ library: LibraryFile) throws -> URL? {
        let snapshot = try createRecoverySnapshot()
        try save(library, rotateBackup: false)
        return snapshot
    }

    private func createRecoverySnapshot() throws -> URL? {
        try directories.ensure(fileManager: fileManager)
        let sources = [directories.libraryFile, directories.backupFile, directories.secondaryBackupFile]
            .filter { fileManager.fileExists(atPath: $0.path) }
        guard !sources.isEmpty else { return nil }

        try fileManager.createDirectory(
            at: directories.recoverySnapshotsDirectory,
            withIntermediateDirectories: true
        )
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let destination = directories.recoverySnapshotsDirectory
            .appendingPathComponent("library-rebuild-\(timestamp)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        do {
            for source in sources {
                let snapshotFile = destination.appendingPathComponent(source.lastPathComponent)
                try fileManager.copyItem(
                    at: source,
                    to: snapshotFile
                )
                try fileManager.setAttributes([.posixPermissions: 0o400], ofItemAtPath: snapshotFile.path)
            }
            try fileManager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: destination.path)
            return destination
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    private func validatedData(at url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url),
              (try? Self.decode(data)) != nil else { return nil }
        return data
    }

    private static func decode(_ data: Data) throws -> LibraryFile {
        if let libraryFile = try? JSONDecoder.reader.decode(LibraryFile.self, from: data) {
            guard libraryFile.schemaVersion <= currentSchemaVersion else {
                throw LibraryRepositoryError.unsupportedSchema(libraryFile.schemaVersion)
            }
            return libraryFile
        }
        let books = try JSONDecoder.reader.decode([Book].self, from: data)
        return LibraryFile(schemaVersion: currentSchemaVersion, books: books)
    }
}
