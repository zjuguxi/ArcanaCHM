import CryptoKit
import Foundation

enum ContentFingerprint {
    static func hashDirectory(_ rootURL: URL) -> String? {
        let rootPath = rootURL.standardizedFileURL.resolvingSymlinksInPath().path
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var hhcData: Data?
        var fileCount = 0

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true
                    && values.isSymbolicLink != true
                    && SecurityPolicy.isDescendant(url, rootPath: rootPath)
            else {
                continue
            }
            fileCount += 1
            if url.pathExtension.lowercased() == "hhc",
               let data = try? Data(contentsOf: url) {
                hhcData = data
            }
        }

        var hasher = SHA256()
        withUnsafeBytes(of: fileCount) { hasher.update(data: $0) }
        if let hhcData {
            hasher.update(data: hhcData)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
