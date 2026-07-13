import CryptoKit
import Foundation

enum ContentFingerprint {
    private static let algorithm = "sha256-v2"
    private static let chunkSize = 1_048_576

    static func hashDirectory(_ rootURL: URL) -> String? {
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.path
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let files = enumerator.compactMap { item -> (URL, String, UInt64)? in
            guard let url = item as? URL,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let relative = SecurityPolicy.relativePath(path: url.standardizedFileURL.resolvingSymlinksInPath().path, rootPath: rootPath),
                  !relative.isEmpty
            else {
                return nil
            }
            return (url, relative.precomposedStringWithCanonicalMapping, UInt64(max(0, values.fileSize ?? 0)))
        }.sorted { $0.1.utf8.lexicographicallyPrecedes($1.1.utf8) }

        var hasher = SHA256()
        hasher.update(data: Data("\(algorithm)\u{0}".utf8))

        for (url, relative, fileSize) in files {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }

            let pathData = Data(relative.utf8)
            updateLength(UInt64(pathData.count), hasher: &hasher)
            hasher.update(data: pathData)
            updateLength(fileSize, hasher: &hasher)

            do {
                while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
                    hasher.update(data: chunk)
                }
            } catch {
                return nil
            }
        }

        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return "\(algorithm):\(digest)"
    }

    private static func updateLength(_ value: UInt64, hasher: inout SHA256) {
        var length = value.bigEndian
        withUnsafeBytes(of: &length) { hasher.update(data: Data($0)) }
    }
}
