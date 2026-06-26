import CoreFoundation
import Foundation

final class TOCParser {
    private let rootURL: URL
    private let fileManager = FileManager.default

    init(rootURL: URL) {
        self.rootURL = rootURL
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

    private func readText(_ url: URL) -> String? {
        let encodings: [String.Encoding] = [
            .utf8,
            .gb18030,
            .windowsCP1252,
            .isoLatin1
        ]

        for encoding in encodings {
            if let text = try? String(contentsOf: url, encoding: encoding).nilIfEmpty() {
                return text
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
        let name = param("Name", in: object) ?? param("Title", in: object)
        let local = param("Local", in: object)
        guard let name, !name.isEmpty else {
            return nil
        }
        return TOCItem(title: decodeEntities(name), path: SecurityPolicy.safeRelativePath(local))
    }

    private func param(_ name: String, in object: String) -> String? {
        let pattern = #"<PARAM\s+[^>]*name\s*=\s*["']?\#(name)["']?[^>]*value\s*=\s*["']?([^"'>]+)["']?[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(object.startIndex..<object.endIndex, in: object)
        guard let match = regex.firstMatch(in: object, range: range), match.numberOfRanges > 1 else {
            return nil
        }
        let valueRange = match.range(at: 1)
        guard let swiftRange = Range(valueRange, in: object) else { return nil }
        return String(object[swiftRange])
    }

    private func decodeEntities(_ text: String) -> String {
        var result = text
        let replacements = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&nbsp;": " "
        ]
        for (key, value) in replacements {
            result = result.replacingOccurrences(of: key, with: value)
        }
        return result
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
        return SecurityPolicy.isDescendant(url, of: rootURL)
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
            if lower.range(of: #"^<\s*ul\s*>"#, options: .regularExpression) != nil {
                return .ulStart
            }
            if lower.range(of: #"^<\s*/\s*ul\s*>"#, options: .regularExpression) != nil {
                return .ulEnd
            }
            if lower.range(of: #"^<\s*li\s*>"#, options: .regularExpression) != nil {
                return .li
            }
            return .object(raw)
        }
    }

    mutating func next() -> HHCToken? {
        guard index < tokens.count else { return nil }
        defer { index += 1 }
        return tokens[index]
    }
}

private extension String.Encoding {
    static let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
}

private extension String {
    func nilIfEmpty() -> String? {
        isEmpty ? nil : self
    }
}
