import Foundation

enum CHMImportError: LocalizedError {
    case extractorMissing
    case extractionFailed(String)
    case noReadableContent
    case unsafeArchiveContent(String)

    var errorDescription: String? {
        switch self {
        case .extractorMissing:
            return "error_no_extractor".loc
        case .extractionFailed(let message):
            return "error_extraction_failed".loc(message)
        case .noReadableContent:
            return "error_no_content".loc
        case .unsafeArchiveContent(let message):
            return "error_unsafe_content".loc(message)
        }
    }
}

final class CHMImporter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func importCHM(from sourceURL: URL) throws -> Book {
        try AppPaths.ensure()
        let title = sourceURL.deletingPathExtension().lastPathComponent
        let destination = AppPaths.booksDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            try extract(sourceURL: sourceURL, destination: destination)
            try validateExtractedContent(at: destination)
            return try buildMinimalBook(title: title, rootURL: destination)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    func importExtractedFolder(from folderURL: URL) throws -> Book {
        try AppPaths.ensure()
        let destination = AppPaths.booksDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try copyDirectoryContents(from: folderURL, to: destination)
            try validateExtractedContent(at: destination)
            return try buildMinimalBook(title: folderURL.lastPathComponent, rootURL: destination)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    /// Populate a book's TOC and fingerprint after it has been displayed.
    /// Call this on a background queue after `finishImport`.
    static func populateBook(_ book: inout Book) {
        let parser = TOCParser(rootURL: book.rootURL)
        let toc = parser.parse()
        if !toc.isEmpty {
            book.toc = toc
            if let hp = parser.homePath(from: toc) {
                book.homePath = hp
            }
        } else if let homePath = book.homePath {
            book.toc = [TOCItem(title: book.title, path: homePath)]
        }
        book.contentFingerprint = ContentFingerprint.hashDirectory(book.rootURL)
    }

    private func extract(sourceURL: URL, destination: URL) throws {
        guard let extractor = findExtractor() else {
            throw CHMImportError.extractorMissing
        }

        let process = Process()
        process.executableURL = extractor.url
        process.currentDirectoryURL = destination
        process.arguments = extractor.arguments(sourceURL, destination)

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "exit code \(process.terminationStatus)"
            throw CHMImportError.extractionFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func buildMinimalBook(title: String, rootURL: URL) throws -> Book {
        var book = Book.empty(title: title, rootURL: rootURL)
        book.homePath = firstHTMLPath(in: rootURL)
        book.lastReadPath = book.homePath

        guard book.homePath != nil else {
            throw CHMImportError.noReadableContent
        }

        return book
    }

    private func firstHTMLPath(in rootURL: URL) -> String? {
        guard let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            return nil
        }

        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  SecurityPolicy.isDescendant(url, of: rootURL)
            else {
                continue
            }
            if SecurityPolicy.readableExtensions.contains(ext),
               let path = SecurityPolicy.relativePath(for: url, rootURL: rootURL) {
                return path
            }
        }
        return nil
    }

    private func copyDirectoryContents(from source: URL, to destination: URL) throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let children = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        for child in children {
            try fileManager.copyItem(at: child, to: destination.appendingPathComponent(child.lastPathComponent))
        }
    }

    func validateExtractedContent(at rootURL: URL) throws {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ) else {
            return
        }

        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                throw CHMImportError.unsafeArchiveContent("symbolic links are not allowed in imported content")
            }
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            guard SecurityPolicy.isDescendant(resolved, of: root) else {
                throw CHMImportError.unsafeArchiveContent("an extracted file points outside the import directory")
            }
        }
    }

    func findExtractor(in bundle: Bundle = .main) -> Extractor? {
        if let bundled = bundle.url(forResource: "7zz", withExtension: nil),
           fileManager.isExecutableFile(atPath: bundled.path) {
            return Extractor(url: bundled, kind: .sevenZip)
        }
        let candidates: [Extractor] = [
            Extractor(url: URL(fileURLWithPath: "/opt/homebrew/bin/7zz"), kind: .sevenZip),
            Extractor(url: URL(fileURLWithPath: "/usr/local/bin/7zz"), kind: .sevenZip),
            Extractor(url: URL(fileURLWithPath: "/opt/homebrew/bin/7z"), kind: .sevenZip),
            Extractor(url: URL(fileURLWithPath: "/usr/local/bin/7z"), kind: .sevenZip),
            Extractor(url: URL(fileURLWithPath: "/opt/homebrew/bin/unar"), kind: .unar),
            Extractor(url: URL(fileURLWithPath: "/usr/local/bin/unar"), kind: .unar)
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0.url.path) }
    }
}

struct Extractor {
    enum Kind {
        case sevenZip
        case unar
    }

    var url: URL
    var kind: Kind

    func arguments(_ source: URL, _ destination: URL) -> [String] {
        switch kind {
        case .sevenZip:
            return ["x", "-y", "-o\(destination.path)", source.path]
        case .unar:
            return ["-quiet", "-force-overwrite", "-output-directory", destination.path, source.path]
        }
    }
}
