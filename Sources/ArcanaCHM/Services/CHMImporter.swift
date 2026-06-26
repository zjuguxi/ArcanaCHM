import Foundation

enum CHMImportError: LocalizedError {
    case extractorMissing
    case extractionFailed(String)
    case noReadableContent
    case unsafeArchiveContent(String)

    var errorDescription: String? {
        switch self {
        case .extractorMissing:
            return "No CHM extractor was found. Install 7-Zip with `brew install sevenzip` or The Unarchiver CLI with `brew install unar`."
        case .extractionFailed(let message):
            return "CHM extraction failed: \(message)"
        case .noReadableContent:
            return "The imported book does not contain readable HTML content."
        case .unsafeArchiveContent(let message):
            return "Import blocked for safety: \(message)"
        }
    }
}

final class CHMImporter {
    private let fileManager = FileManager.default

    func importCHM(from sourceURL: URL) throws -> Book {
        try AppPaths.ensure()
        let title = sourceURL.deletingPathExtension().lastPathComponent
        let destination = AppPaths.booksDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            try extract(sourceURL: sourceURL, destination: destination)
            try validateExtractedContent(at: destination)
            return try buildBook(title: title, rootURL: destination)
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
            return try buildBook(title: folderURL.lastPathComponent, rootURL: destination)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
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

    private func buildBook(title: String, rootURL: URL) throws -> Book {
        let parser = TOCParser(rootURL: rootURL)
        var book = Book.empty(title: title, rootURL: rootURL)
        book.toc = parser.parse()
        book.homePath = parser.homePath(from: book.toc) ?? firstHTMLPath(in: rootURL)
        book.lastReadPath = book.homePath

        guard book.homePath != nil else {
            throw CHMImportError.noReadableContent
        }

        if book.toc.isEmpty, let homePath = book.homePath {
            book.toc = [TOCItem(title: title, path: homePath)]
        }
        book.contentFingerprint = ContentFingerprint.hashDirectory(rootURL)

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

    private func validateExtractedContent(at rootURL: URL) throws {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
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

    private func findExtractor() -> Extractor? {
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

private struct Extractor {
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
