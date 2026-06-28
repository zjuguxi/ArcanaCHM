import CoreFoundation
import Foundation

private let nameParamPattern = try! NSRegularExpression(pattern: #"<PARAM\s+[^>]*name\s*=\s*["']?Name["']?[^>]*value\s*=\s*["']?([^"'>]+)["']?[^>]*>"#, options: [.caseInsensitive])
private let titleParamPattern = try! NSRegularExpression(pattern: #"<PARAM\s+[^>]*name\s*=\s*["']?Title["']?[^>]*value\s*=\s*["']?([^"'>]+)["']?[^>]*>"#, options: [.caseInsensitive])
private let localParamPattern = try! NSRegularExpression(pattern: #"<PARAM\s+[^>]*name\s*=\s*["']?Local["']?[^>]*value\s*=\s*["']?([^"'>]+)["']?[^>]*>"#, options: [.caseInsensitive])

final class TOCParser {
    private let rootURL: URL
    private let rootPath: String
    private let fileManager = FileManager.default

    init(rootURL: URL) {
        self.rootURL = rootURL
        self.rootPath = rootURL.standardizedFileURL.resolvingSymlinksInPath().path
    }

    func parse() -> [TOCItem] {
        guard let hhc = findFile(extensions: ["hhc"]) else {
            return fallbackTOC()
        }

        guard let text = readText(hhc) else {
            return fallbackTOC()
        }

        let items = parseNestedItems(text)
        if items.isEmpty {
            return fallbackTOC()
        }

        return items
    }

    func homePath(from toc: [TOCItem]) -> String? {
        for item in toc {
            if let path = item.path {
                return path
            }
            if let childPath = homePath(from: item.children) {
                return childPath
            }
        }
        return nil
    }

    private func parseNestedItems(_ html: String) -> [TOCItem] {
        var tokenizer = HHCTokenizer(html)
        return parseList(&tokenizer)
    }

    private func parseList(_ tokenizer: inout HHCTokenizer) -> [TOCItem] {
        var items: [TOCItem] = []

        while let token = tokenizer.next() {
            switch token {
            case .ulStart:
                let nested = parseList(&tokenizer)
                if let last = items.indices.last {
                    items[last].children.append(contentsOf: nested)
                } else {
                    items.append(contentsOf: nested)
                }
            case .ulEnd:
                return items
            case .li:
                if case let .object(object)? = tokenizer.next(),
                   let item = item(from: object) {
                    items.append(item)
                }
            case .object(let object):
                if let item = item(from: object) {
                    items.append(item)
                }
            }
        }

        return items
    }

    private func item(from object: String) -> TOCItem? {
        let name = firstParam(nameParamPattern, in: object) ?? firstParam(titleParamPattern, in: object)
        let local = firstParam(localParamPattern, in: object)
        guard let name, !name.isEmpty else {
            return nil
        }
        return TOCItem(title: ArcanaCHM.decodeEntities(name), path: SecurityPolicy.safeRelativePath(local))
    }

    private func firstParam(_ regex: NSRegularExpression, in object: String) -> String? {
        let range = NSRange(object.startIndex..<object.endIndex, in: object)
        guard let match = regex.firstMatch(in: object, range: range), match.numberOfRanges > 1 else {
            return nil
        }
        let valueRange = match.range(at: 1)
        guard let swiftRange = Range(valueRange, in: object) else { return nil }
        return String(object[swiftRange])
    }

    private func fallbackTOC() -> [TOCItem] {
        guard let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            return []
        }

        var items: [TOCItem] = []
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            guard isSafeRegularFile(url) else { continue }
            guard ["html", "htm", "xhtml"].contains(ext) else { continue }
            guard let path = SecurityPolicy.relativePath(for: url, rootURL: rootURL) else { continue }
            items.append(TOCItem(title: url.deletingPathExtension().lastPathComponent, path: path))
        }
        return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func findFile(extensions: Set<String>) -> URL? {
        guard let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            return nil
        }
        for case let url as URL in enumerator where extensions.contains(url.pathExtension.lowercased()) && isSafeRegularFile(url) {
            return url
        }
        return nil
    }

    private func isSafeRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true
        else {
            return false
        }
        return SecurityPolicy.isDescendant(url, rootPath: rootPath)
    }

}

private enum HHCToken {
    case ulStart
    case ulEnd
    case li
    case object(String)
}

private struct HHCTokenizer {
    private var tokens: [HHCToken]
    private var index = 0

    init(_ html: String) {
        let pattern = #"(?is)<\s*UL\s*>|<\s*/\s*UL\s*>|<\s*LI\s*>|<\s*OBJECT\b[\s\S]*?<\s*/\s*OBJECT\s*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            tokens = []
            return
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        tokens = regex.matches(in: html, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: html) else { return nil }
            let raw = String(html[swiftRange])
            let lower = raw.lowercased()
            // Fast path: check prefixes instead of regex
            if lower.hasPrefix("</ul>") || lower == "</ul>" { return .ulEnd }
            if lower == "<li>" { return .li }
            if lower.hasPrefix("<ul") { return .ulStart }
            return .object(raw)
        }
    }

    mutating func next() -> HHCToken? {
        guard index < tokens.count else { return nil }
        defer { index += 1 }
        return tokens[index]
    }
}
