import Foundation

enum LibraryRebuildSkippedReason: String, Sendable {
    case unsafeDirectory
    case noReadableContent
    case duplicateContent
}

struct LibraryRebuildWarning: Identifiable, Sendable {
    let id = UUID()
    var folderName: String
    var reason: LibraryRebuildSkippedReason
}

struct LibraryRebuildPreview: Identifiable, Sendable {
    let id = UUID()
    var books: [Book]
    var scannedDirectoryCount: Int
    var preservedBookCount: Int
    var recoveredBookCount: Int
    var warnings: [LibraryRebuildWarning]
}

enum LibraryRebuildError: LocalizedError {
    case tooManyDirectories

    var errorDescription: String? {
        switch self {
        case .tooManyDirectories:
            return "The Books directory contains too many entries to rebuild safely."
        }
    }
}

actor LibraryRebuilder {
    private static let maximumBookDirectories = 10_000
    private static let maximumMetadataBytes = 256 * 1_024

    private let directories: AppDirectories
    private let fileManager: FileManager

    init(directories: AppDirectories) {
        self.directories = directories
        fileManager = .default
    }

    func preview(existingBooks: [Book]) throws -> LibraryRebuildPreview {
        try directories.ensure(fileManager: fileManager)
        var existingByRoot: [String: Book] = [:]
        for book in existingBooks {
            let rootPath = book.rootURL.standardizedFileURL.resolvingSymlinksInPath().path
            if existingByRoot[rootPath] == nil {
                existingByRoot[rootPath] = book
            }
        }
        let children = try fileManager.contentsOfDirectory(
            at: directories.booksDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .creationDateKey],
            options: []
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard children.count <= Self.maximumBookDirectories else {
            throw LibraryRebuildError.tooManyDirectories
        }

        var books: [Book] = []
        var warnings: [LibraryRebuildWarning] = []
        var preservedBookCount = 0
        var recoveredBookCount = 0
        var fingerprints = Set<String>()

        for child in children {
            try Task.checkCancellation()
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .creationDateKey])
            guard values?.isDirectory == true,
                  values?.isSymbolicLink != true,
                  SecurityPolicy.isInsideBooks(child, directories: directories),
                  child.deletingLastPathComponent().standardizedFileURL.path == directories.booksDirectory.standardizedFileURL.path
            else {
                warnings.append(.init(folderName: child.lastPathComponent, reason: .unsafeDirectory))
                continue
            }

            let parser = TOCParser(rootURL: child)
            let toc = parser.parse()
            guard !toc.isEmpty, let homePath = parser.homePath(from: toc) else {
                warnings.append(.init(folderName: child.lastPathComponent, reason: .noReadableContent))
                continue
            }

            let fingerprint = ContentFingerprint.hashDirectory(child)
            if let fingerprint, !fingerprints.insert(fingerprint).inserted {
                warnings.append(.init(folderName: child.lastPathComponent, reason: .duplicateContent))
                continue
            }

            let rootPath = child.standardizedFileURL.resolvingSymlinksInPath().path
            var book: Book
            if var existing = existingByRoot[rootPath] {
                existing.rootPath = child.path
                existing.toc = toc
                existing.homePath = homePath
                existing.contentFingerprint = fingerprint
                book = existing
                preservedBookCount += 1
            } else {
                let title = recoveredTitle(rootURL: child, homePath: homePath, toc: toc)
                book = Book.empty(title: title, rootURL: child)
                book.homePath = homePath
                book.toc = toc
                book.contentFingerprint = fingerprint
                book.importedAt = values?.creationDate ?? Date()
                recoveredBookCount += 1
            }
            books.append(book)
        }

        books.sort { lhs, rhs in
            let comparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            return comparison == .orderedSame ? lhs.rootPath < rhs.rootPath : comparison == .orderedAscending
        }
        return LibraryRebuildPreview(
            books: books,
            scannedDirectoryCount: children.count,
            preservedBookCount: preservedBookCount,
            recoveredBookCount: recoveredBookCount,
            warnings: warnings
        )
    }

    private func recoveredTitle(rootURL: URL, homePath: String, toc: [TOCItem]) -> String {
        if let title = projectTitle(rootURL: rootURL) { return title }
        if let homeURL = SecurityPolicy.safeFileURL(rootURL: rootURL, relativePath: homePath),
           let html = readLimitedText(homeURL),
           let title = htmlTitle(html) {
            return title
        }
        if let title = toc.first?.title.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return rootURL.lastPathComponent
    }

    private func projectTitle(rootURL: URL) -> String? {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var inspected = 0
        for case let url as URL in enumerator {
            inspected += 1
            guard inspected <= 10_000 else { return nil }
            guard url.pathExtension.lowercased() == "hhp",
                  SecurityPolicy.isDescendant(url, of: rootURL),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  (values.fileSize ?? 0) <= Self.maximumMetadataBytes,
                  let text = readLimitedText(url)
            else { continue }

            for line in text.split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2,
                      parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "title"
                else { continue }
                let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { return title }
            }
        }
        return nil
    }

    private func readLimitedText(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.maximumMetadataBytes), !data.isEmpty else { return nil }
        return readText(from: data)
    }

    private func htmlTitle(_ html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<title[^>]*>(.*?)</title>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let titleRange = Range(match.range(at: 1), in: html)
        else { return nil }
        let title = decodeEntities(String(html[titleRange])).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }
}
