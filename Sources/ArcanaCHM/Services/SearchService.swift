import CoreFoundation
import Foundation

final class SearchService {
    private let fileManager = FileManager.default

    func search(_ query: String, in book: Book) -> [SearchHit] {
        let needle = query.lowercased()
        guard let enumerator = fileManager.enumerator(at: book.rootURL, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            return []
        }

        var hits: [SearchHit] = []
        for case let url as URL in enumerator {
            guard hits.count < 80 else { break }
            guard isSafeRegularFile(url, rootURL: book.rootURL) else { continue }
            guard ["html", "htm", "xhtml"].contains(url.pathExtension.lowercased()) else { continue }
            guard let raw = readText(url) else { continue }

            let plain = stripHTML(raw)
            guard let range = plain.lowercased().range(of: needle) else { continue }
            let snippet = snippetAround(range, in: plain)
            hits.append(SearchHit(
                title: title(for: url, fallback: url.deletingPathExtension().lastPathComponent),
                path: relativePath(url, root: book.rootURL),
                snippet: snippet
            ))
        }
        return hits
    }

    private func isSafeRegularFile(_ url: URL, rootURL: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true
        else {
            return false
        }
        return SecurityPolicy.isDescendant(url, of: rootURL)
    }

    private func stripHTML(_ html: String) -> String {
        var text = html.replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return ArcanaCHM.decodeEntities(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func title(for url: URL, fallback: String) -> String {
        guard let raw = readText(url),
              let range = raw.range(of: #"<title[^>]*>([\s\S]*?)</title>"#, options: [.regularExpression, .caseInsensitive])
        else {
            return fallback
        }
        let title = raw[range]
            .replacingOccurrences(of: #"</?title[^>]*>"#, with: "", options: [.regularExpression, .caseInsensitive])
        return ArcanaCHM.decodeEntities(String(title)).trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank() ?? fallback
    }

    private func snippetAround(_ range: Range<String.Index>, in text: String) -> String {
        let lower = text.index(range.lowerBound, offsetBy: -90, limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(range.upperBound, offsetBy: 160, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[lower..<upper]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func relativePath(_ url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

}
