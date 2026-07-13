import Darwin
import Foundation

enum CHMImportError: LocalizedError {
    case extractorMissing
    case extractionFailed(String)
    case noReadableContent
    case unsafeArchiveContent(String)
    case resourceLimitExceeded(String)
    case extractionTimedOut

    var errorDescription: String? {
        switch self {
        case .extractorMissing:
            return "No supported CHM extractor was found."
        case .extractionFailed(let message):
            return "CHM extraction failed: \(message)"
        case .noReadableContent:
            return "No readable HTML content was found."
        case .unsafeArchiveContent(let message):
            return "Import blocked for safety: \(message)"
        case .resourceLimitExceeded(let message):
            return "Import blocked for safety: \(message)"
        case .extractionTimedOut:
            return "CHM extraction failed: extraction exceeded the time limit"
        }
    }
}

struct ExtractionLimits: Sendable {
    var maximumSourceBytes: Int64 = 2 * 1_024 * 1_024 * 1_024
    var maximumExpandedBytes: Int64 = 1 * 1_024 * 1_024 * 1_024
    var maximumSingleFileBytes: Int64 = 256 * 1_024 * 1_024
    var maximumFileCount = 50_000
    var maximumDirectoryDepth = 64
    var maximumPathLength = 1_024
    var maximumDuration: TimeInterval = 120
    var maximumErrorOutputBytes = 64 * 1_024
    var minimumFreeDiskBytes: Int64 = 512 * 1_024 * 1_024

    static let `default` = ExtractionLimits()
}

private final class BoundedProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let maximumBytes: Int

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard data.count < maximumBytes else { return }
        data.append(newData.prefix(maximumBytes - data.count))
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

final class CHMImporter {
    private let fileManager: FileManager
    private let directories: AppDirectories
    private let limits: ExtractionLimits

    init(
        fileManager: FileManager = .default,
        directories: AppDirectories = .production,
        limits: ExtractionLimits = .default
    ) {
        self.fileManager = fileManager
        self.directories = directories
        self.limits = limits
    }

    func importCHM(from sourceURL: URL) throws -> Book {
        try directories.ensure(fileManager: fileManager)
        try validateSourceSize(sourceURL)
        let title = sourceURL.deletingPathExtension().lastPathComponent
        let destination = directories.booksDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
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
        try directories.ensure(fileManager: fileManager)
        try inspectTree(at: folderURL)
        let destination = directories.booksDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
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
        let errorOutput = BoundedProcessOutput(maximumBytes: limits.maximumErrorOutputBytes)
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            errorOutput.append(handle.availableData)
        }
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        let deadline = Date().addingTimeInterval(limits.maximumDuration)
        var nextInspection = Date()
        var extractionError: Error?
        while process.isRunning {
            Thread.sleep(forTimeInterval: 0.05)
            if Date() >= deadline {
                extractionError = CHMImportError.extractionTimedOut
                stop(process)
                break
            }
            if Date() >= nextInspection {
                do {
                    try inspectTree(at: destination)
                } catch {
                    extractionError = error
                    stop(process)
                    break
                }
                nextInspection = Date().addingTimeInterval(0.25)
            }
        }
        process.waitUntilExit()
        errorPipe.fileHandleForReading.readabilityHandler = nil
        errorOutput.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
        let capturedErrorOutput = errorOutput.snapshot()

        if let extractionError { throw extractionError }

        guard process.terminationStatus == 0 else {
            let message = String(data: capturedErrorOutput, encoding: .utf8) ?? "exit code \(process.terminationStatus)"
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
        try inspectTree(at: rootURL)
    }

    @discardableResult
    private func inspectTree(at rootURL: URL) throws -> (fileCount: Int, totalBytes: Int64) {
        let capacity = try? rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        if let capacity, capacity < limits.minimumFreeDiskBytes {
            throw CHMImportError.resourceLimitExceeded("insufficient free disk space for a safe import")
        }
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        ) else {
            return (0, 0)
        }

        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        var fileCount = 0
        var totalBytes: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            if values.isSymbolicLink == true {
                throw CHMImportError.unsafeArchiveContent("symbolic links are not allowed in imported content")
            }
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            guard SecurityPolicy.isDescendant(resolved, of: root) else {
                throw CHMImportError.unsafeArchiveContent("an extracted file points outside the import directory")
            }
            guard let relative = SecurityPolicy.relativePath(for: resolved, rootURL: root) else {
                throw CHMImportError.unsafeArchiveContent("an extracted path could not be normalized")
            }
            if relative.utf8.count > limits.maximumPathLength {
                throw CHMImportError.resourceLimitExceeded("an extracted path exceeds the length limit")
            }
            let depth = relative.split(separator: "/", omittingEmptySubsequences: true).count
            if depth > limits.maximumDirectoryDepth {
                throw CHMImportError.resourceLimitExceeded("archive directory depth exceeds the limit")
            }
            if values.isRegularFile == true {
                fileCount += 1
                let size = Int64(values.fileSize ?? 0)
                if size > limits.maximumSingleFileBytes {
                    throw CHMImportError.resourceLimitExceeded("an extracted file exceeds the size limit")
                }
                totalBytes += size
                if fileCount > limits.maximumFileCount {
                    throw CHMImportError.resourceLimitExceeded("archive contains too many files")
                }
                if totalBytes > limits.maximumExpandedBytes {
                    throw CHMImportError.resourceLimitExceeded("expanded archive exceeds the size limit")
                }
            }
        }
        return (fileCount, totalBytes)
    }

    private func validateSourceSize(_ sourceURL: URL) throws {
        let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else {
            throw CHMImportError.unsafeArchiveContent("the selected CHM is not a regular file")
        }
        if Int64(values.fileSize ?? 0) > limits.maximumSourceBytes {
            throw CHMImportError.resourceLimitExceeded("the selected CHM exceeds the source size limit")
        }
    }

    private func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let graceDeadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < graceDeadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
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
