import Foundation

enum SecurityPolicy {
    static let readableExtensions: Set<String> = ["html", "htm", "xhtml"]

    static func safeRelativePath(_ rawPath: String?) -> String? {
        guard var path = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }

        path = path.replacingOccurrences(of: "\\", with: "/")
        if let hash = path.firstIndex(of: "#") {
            path = String(path[..<hash])
        }
        if let query = path.firstIndex(of: "?") {
            path = String(path[..<query])
        }
        path = path.removingPercentEncoding ?? path
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !path.isEmpty,
              !path.hasPrefix("~"),
              !path.hasPrefix("/"),
              URL(string: path)?.scheme == nil
        else {
            return nil
        }

        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        var resolved: [String] = []
        for part in parts {
            if part == ".." {
                if !resolved.isEmpty {
                    resolved.removeLast()
                }
            } else if part != "." {
                resolved.append(String(part))
            }
        }
        guard !resolved.isEmpty else { return nil }
        return resolved.joined(separator: "/")
    }

    static func safeFileURL(rootURL: URL, relativePath: String?) -> URL? {
        let raw = relativePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hashParts = raw.split(separator: "#", maxSplits: 1).map(String.init)
        guard let basePath = safeRelativePath(hashParts.first.flatMap({ $0.isEmpty ? nil : $0 })) else {
            return nil
        }
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = root.appendingPathComponent(basePath).standardizedFileURL.resolvingSymlinksInPath()
        guard isDescendant(candidate, of: root) else { return nil }
        if hashParts.count > 1 {
            var components = URLComponents(url: candidate, resolvingAgainstBaseURL: false)!
            components.fragment = hashParts[1]
            return components.url!
        }
        return candidate
    }

    /// Resolve a root URL once, then reuse the resolved root for many file checks.
    static func relativePath(for fileURL: URL, rootURL: URL) -> String? {
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath().path
        let path = fileURL.standardizedFileURL.resolvingSymlinksInPath().path
        return relativePath(path: path, rootPath: root)
    }

    static func relativePath(path: String, rootPath: String) -> String? {
        guard path == rootPath || path.hasPrefix(rootPath + "/") else { return nil }
        return String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func isDescendant(_ url: URL, of rootURL: URL) -> Bool {
        isDescendant(
            path: url.standardizedFileURL.resolvingSymlinksInPath().path,
            rootPath: rootURL.standardizedFileURL.resolvingSymlinksInPath().path
        )
    }

    static func isDescendant(_ url: URL, rootPath: String) -> Bool {
        isDescendant(path: url.standardizedFileURL.resolvingSymlinksInPath().path, rootPath: rootPath)
    }

    static func isDescendant(path: String, rootPath: String) -> Bool {
        path == rootPath || path.hasPrefix(rootPath + "/")
    }

    static func isDescendant(_ url: URL, rootURL: URL, resolvedRootPath: String) -> Bool {
        isDescendant(path: url.standardizedFileURL.resolvingSymlinksInPath().path, rootPath: resolvedRootPath)
    }

    static func isInsideAppBooks(_ url: URL) -> Bool {
        isDescendant(url, of: AppPaths.booksDirectory)
    }
}
