import CoreFoundation
import Foundation

private let stripScriptRegex = try! NSRegularExpression(pattern: #"<script[\s\S]*?</script>"#, options: [.caseInsensitive])
private let stripStyleRegex = try! NSRegularExpression(pattern: #"<style[\s\S]*?</style>"#, options: [.caseInsensitive])
private let stripTagsRegex = try! NSRegularExpression(pattern: #"<[^>]+>"#, options: [])
private let collapseSpaceRegex = try! NSRegularExpression(pattern: #"\s+"#, options: [])
private let titleTagRegex = try! NSRegularExpression(pattern: #"<title[^>]*>([\s\S]*?)</title>"#, options: [.caseInsensitive])
private let removeTitleTagRegex = try! NSRegularExpression(pattern: #"</?title[^>]*>"#, options: [.caseInsensitive])

final class SearchService {
    private let fileManager = FileManager.default
    private let maximumFileBytes = 16 * 1_024 * 1_024
    private let maximumSearchBytes = 256 * 1_024 * 1_024
    private let maximumFiles = 50_000

    func search(_ query: String, in book: Book) async -> [SearchHit] {
        let needle = query.lowercased()
        let rootPath = book.rootURL.standardizedFileURL.resolvingSymlinksInPath().path
        guard let enumerator = fileManager.enumerator(at: book.rootURL, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else {
            return []
        }

        var hits: [SearchHit] = []
        var processed = 0
        var searchedBytes = 0
        while let item = enumerator.nextObject() {
            guard let url = item as? URL else { continue }
            if Task.isCancelled { return [] }
            guard hits.count < 80 else { break }
            guard let fileSize = safeRegularFileSize(url, rootPath: rootPath) else { continue }
            guard ["html", "htm", "xhtml"].contains(url.pathExtension.lowercased()) else { continue }
            guard fileSize <= maximumFileBytes,
                  searchedBytes + fileSize <= maximumSearchBytes,
                  processed < maximumFiles else { continue }
            searchedBytes += fileSize
            processed += 1
            if processed & 0xF == 0 {
                await Task.yield()
                if Task.isCancelled { return [] }
            }
            guard let raw = readText(url) else { continue }

            let plain = stripHTML(raw)
            guard plain.range(of: needle, options: .caseInsensitive) != nil else { continue }
            let snippet = snippetAround(needle, in: plain)
            hits.append(SearchHit(
                title: title(from: raw, fallback: url.deletingPathExtension().lastPathComponent),
                path: SecurityPolicy.relativePath(path: url.standardizedFileURL.resolvingSymlinksInPath().path, rootPath: rootPath) ?? url.lastPathComponent,
                snippet: snippet
            ))
        }
        return hits
    }

    private func safeRegularFileSize(_ url: URL, rootPath: String) -> Int? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true
        else {
            return nil
        }
        guard SecurityPolicy.isDescendant(url, rootPath: rootPath) else { return nil }
        return max(0, values.fileSize ?? 0)
    }

    private func stripHTML(_ html: String) -> String {
        var text = stripScriptRegex.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: " ")
        text = stripStyleRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        text = stripTagsRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        text = collapseSpaceRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        return decodeEntities(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func title(from raw: String, fallback: String) -> String {
        guard let match = titleTagRegex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              match.numberOfRanges > 1
        else {
            return fallback
        }
        let titleRange = match.range(at: 1)
        guard let swiftRange = Range(titleRange, in: raw) else { return fallback }
        let title = String(raw[swiftRange])
        return decodeEntities(title).trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank() ?? fallback
    }

    private func snippetAround(_ needle: String, in text: String) -> String {
        guard let range = text.range(of: needle, options: .caseInsensitive) else { return "" }
        let lower = text.index(range.lowerBound, offsetBy: -90, limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(range.upperBound, offsetBy: 160, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[lower..<upper]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
