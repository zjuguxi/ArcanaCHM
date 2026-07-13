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
    var maximumListingDuration: TimeInterval = 30
    var maximumListingOutputBytes = 32 * 1_024 * 1_024
    var maximumErrorOutputBytes = 64 * 1_024
    var minimumFreeDiskBytes: Int64 = 512 * 1_024 * 1_024

    static let `default` = ExtractionLimits()
}

private final class BoundedProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var truncated = false
    private let maximumBytes: Int

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard data.count < maximumBytes else {
            truncated = true
            return
        }
        let remaining = maximumBytes - data.count
        if newData.count > remaining { truncated = true }
        data.append(newData.prefix(remaining))
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    var didTruncate: Bool {
        lock.lock()
        defer { lock.unlock() }
        return truncated
    }
}

struct ArchiveListingReport: Equatable, Sendable {
    var fileCount: Int
    var expandedBytes: Int64
}

enum SevenZipListingValidator {
    private struct Entry {
        var path: String?
        var size: Int64?
        var attributes = ""
        var isFolder = false
        var isSymbolicLink = false
    }

    static func validate(_ data: Data, limits: ExtractionLimits) throws -> ArchiveListingReport {
        guard let listing = String(data: data, encoding: .utf8) else {
            throw CHMImportError.unsafeArchiveContent("the archive listing is not valid UTF-8")
        }

        var readingEntries = false
        var entry = Entry()
        var fileCount = 0
        var expandedBytes: Int64 = 0
        var normalizedPaths = Set<String>()

        func validateEntry() throws {
            guard let rawPath = entry.path else { return }
            let path = rawPath.replacingOccurrences(of: "\\", with: "/")
            let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            let firstScalars = Array((components.first ?? "").unicodeScalars)
            let isWindowsDrivePath = firstScalars.count == 2
                && CharacterSet.letters.contains(firstScalars[0])
                && firstScalars[1] == ":"
            guard !path.isEmpty,
                  !path.hasPrefix("/"),
                  !path.hasPrefix("~"),
                  components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  !isWindowsDrivePath
            else {
                throw CHMImportError.unsafeArchiveContent("the archive contains an absolute or traversing path")
            }
            guard path.utf8.count <= limits.maximumPathLength else {
                throw CHMImportError.resourceLimitExceeded("an archive path exceeds the length limit")
            }
            guard components.count <= limits.maximumDirectoryDepth else {
                throw CHMImportError.resourceLimitExceeded("archive directory depth exceeds the limit")
            }
            guard !entry.isSymbolicLink, !entry.attributes.localizedCaseInsensitiveContains("L") else {
                throw CHMImportError.unsafeArchiveContent("symbolic links are not allowed in imported content")
            }

            let collisionKey = path.precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "en_US_POSIX"))
            guard normalizedPaths.insert(collisionKey).inserted else {
                throw CHMImportError.unsafeArchiveContent("the archive contains duplicate or case-conflicting paths")
            }

            guard !entry.isFolder, !entry.attributes.localizedCaseInsensitiveContains("D") else { return }
            guard let size = entry.size, size >= 0 else {
                throw CHMImportError.unsafeArchiveContent("an archive entry has no valid declared size")
            }
            guard size <= limits.maximumSingleFileBytes else {
                throw CHMImportError.resourceLimitExceeded("an archive entry exceeds the size limit")
            }
            fileCount += 1
            guard fileCount <= limits.maximumFileCount else {
                throw CHMImportError.resourceLimitExceeded("archive contains too many files")
            }
            let (newTotal, overflow) = expandedBytes.addingReportingOverflow(size)
            guard !overflow, newTotal <= limits.maximumExpandedBytes else {
                throw CHMImportError.resourceLimitExceeded("archive declared size exceeds the expansion limit")
            }
            expandedBytes = newTotal
        }

        for rawLine in listing.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "----------" {
                readingEntries = true
                entry = Entry()
                continue
            }
            guard readingEntries else { continue }
            if line.isEmpty {
                try validateEntry()
                entry = Entry()
                continue
            }
            let parts = line.components(separatedBy: " = ")
            guard parts.count >= 2 else { continue }
            let value = parts.dropFirst().joined(separator: " = ")
            switch parts[0] {
            case "Path": entry.path = value
            case "Size": entry.size = Int64(value)
            case "Attributes": entry.attributes = value
            case "Folder": entry.isFolder = value == "+"
            case "Symbolic Link": entry.isSymbolicLink = !value.isEmpty
            default: break
            }
        }
        try validateEntry()
        return ArchiveListingReport(fileCount: fileCount, expandedBytes: expandedBytes)
    }
}

final class CHMImporter: @unchecked Sendable {
    private let fileManager: FileManager
    private let directories: AppDirectories
    private let limits: ExtractionLimits
    private let extractorOverride: Extractor?

    init(
        fileManager: FileManager = .default,
        directories: AppDirectories = .production,
        limits: ExtractionLimits = .default,
        extractorOverride: Extractor? = nil
    ) {
        self.fileManager = fileManager
        self.directories = directories
        self.limits = limits
        self.extractorOverride = extractorOverride
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
        guard let extractor = extractorOverride ?? findExtractor() else {
            throw CHMImportError.extractorMissing
        }
        try preflightArchive(sourceURL, using: extractor)

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
            if currentTaskIsCancelled {
                extractionError = CancellationError()
                stop(process)
                break
            }
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

    private func preflightArchive(_ sourceURL: URL, using extractor: Extractor) throws {
        guard let arguments = extractor.listingArguments(sourceURL) else { return }

        let process = Process()
        process.executableURL = extractor.url
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let output = BoundedProcessOutput(maximumBytes: limits.maximumListingOutputBytes)
        let errors = BoundedProcessOutput(maximumBytes: limits.maximumErrorOutputBytes)
        outputPipe.fileHandleForReading.readabilityHandler = { output.append($0.availableData) }
        errorPipe.fileHandleForReading.readabilityHandler = { errors.append($0.availableData) }
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        let deadline = Date().addingTimeInterval(limits.maximumListingDuration)
        var preflightError: Error?
        while process.isRunning {
            Thread.sleep(forTimeInterval: 0.05)
            if currentTaskIsCancelled {
                preflightError = CancellationError()
                stop(process)
                break
            }
            if Date() >= deadline {
                preflightError = CHMImportError.extractionTimedOut
                stop(process)
                break
            }
        }
        process.waitUntilExit()
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        output.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        errors.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

        if let preflightError { throw preflightError }
        guard !output.didTruncate else {
            throw CHMImportError.resourceLimitExceeded("archive listing exceeds the inspection limit")
        }
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.snapshot(), encoding: .utf8) ?? "exit code \(process.terminationStatus)"
            throw CHMImportError.extractionFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        _ = try SevenZipListingValidator.validate(output.snapshot(), limits: limits)
    }

    private var currentTaskIsCancelled: Bool {
        var isCancelled = false
        withUnsafeCurrentTask { isCancelled = $0?.isCancelled == true }
        return isCancelled
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

    func listingArguments(_ source: URL) -> [String]? {
        switch kind {
        case .sevenZip:
            return ["l", "-slt", "--", source.path]
        case .unar:
            return nil
        }
    }
}
