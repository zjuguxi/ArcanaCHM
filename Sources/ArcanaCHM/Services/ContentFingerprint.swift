import CryptoKit
import Foundation

enum ContentFingerprint {
    static func hashDirectory(_ rootURL: URL) -> String? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true
                    && values.isSymbolicLink != true
                    && SecurityPolicy.isDescendant(url, of: rootURL)
            else {
                continue
            }
            urls.append(url)
        }

        var hasher = SHA256()
        for url in urls.sorted(by: { relativePath($0, root: rootURL) < relativePath($1, root: rootURL) }) {
            let relative = relativePath(url, root: rootURL)
            hasher.update(data: Data(relative.utf8))
            hasher.update(data: Data([0]))
            guard let data = try? Data(contentsOf: url) else {
                continue
            }
            hasher.update(data: data)
            hasher.update(data: Data([0]))
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func relativePath(_ url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
