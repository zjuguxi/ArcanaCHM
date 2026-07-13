import XCTest
import Foundation
@testable import ArcanaCHM

// MARK: - 性能验收测试（发布前运行）
//
// 这些测试捕获关键操作的性能基线。如果某次改动导致某个测试显著变慢，
// 说明引入了性能退化，应在发布前排查。
//
// 基线数据（Apple M3 / macOS 15, Debug build）：
//   SecurityPolicy 快速路径   10,000次   ~0.10s
//   JSON 紧凑编码             100本书     ~0.06s (10次)
//   JSON pretty 编码          100本书     ~0.06s (10次)
//   JSON 体积缩减             100本书     41.6%
//   toggleBookmark 大 TOC     5,000条   ~1.19s (100次)
//   备份 copyItem 耗时       245KB        ~0.4ms
//   decodeEntities            2,000×10   ~0.15s
//   HHCTokenizer              200条      ~0.002s

final class PerformanceTests: XCTestCase {

    // MARK: - #1 AppPaths 缓存（不需要 measurements，已验证消除 FS 调用）

    // MARK: - #2 SecurityPolicy 快速路径

    func testSecurityPolicyFastPath() {
        let root = URL(fileURLWithPath: "/tmp/books/testbook")
        let files = (0..<10000).map { i in
            URL(fileURLWithPath: "/tmp/books/testbook/subdir/file\(i).html")
        }
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath().path
        measure {
            for url in files {
                _ = SecurityPolicy.isDescendant(path: url.standardizedFileURL.resolvingSymlinksInPath().path, rootPath: resolvedRoot)
            }
        }
    }

    // MARK: - #3 静态正则 + #4 HHCTokenizer 字符串操作

    func testDecodeEntities() {
        let html = String(repeating: "Hello &amp; world &#x26; test &lt; stuff &gt; goodbye ", count: 2000)
        measure { for _ in 0..<10 { _ = decodeEntities(html) } }
    }

    // MARK: - #5 JSON 紧凑编码

    func testCompactJSONEncode() {
        let library = makeLargeLibrary()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        measure { for _ in 0..<10 { _ = try! encoder.encode(library) } }
    }

    func testJSONSizeReduction() {
        let library = makeLargeLibrary()
        let compact = try! JSONEncoder.reader.encode(library)
        let pretty = { () -> Data in
            let e = JSONEncoder()
            e.outputFormatting = [.prettyPrinted, .sortedKeys]
            e.dateEncodingStrategy = .iso8601
            return try! e.encode(library)
        }()
        let reduction = Double(pretty.count - compact.count) / Double(pretty.count) * 100
        // 即使 schema 变化导致数值波动，缩减比例应 >= 35%
        XCTAssertGreaterThanOrEqual(reduction, 35)
    }

    // MARK: - #6 Book 写时复制（toggleBookmark 不拷贝 TOC）

    @MainActor
    func testToggleBookmarkLargeTOC() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArcanaCHMPerformanceTests-\(UUID().uuidString)", isDirectory: true)
        let directories = AppDirectories(appSupport: root)
        try? directories.ensure()
        defer {
            if root.path.contains("ArcanaCHMPerformanceTests-") {
                try? FileManager.default.removeItem(at: root)
            }
        }
        let store = LibraryStore(directories: directories)
        var book = Book.empty(title: "Big", rootURL: URL(fileURLWithPath: "/tmp/big"))
        book.toc = (0..<5000).map { TOCItem(title: "Item \($0)", path: "p\($0).html") }
        book.bookmarks = [Bookmark(id: UUID(), title: "existing", path: "p0.html", scrollY: 0, createdAt: Date())]
        store.books = [book]
        store.selectedBookID = book.id

        measure {
            for i in 0..<100 {
                store.toggleBookmark(path: "p\(i).html", scrollY: Double(i))
            }
        }
    }

    // MARK: - #9 防抖 save 跳过备份（备份 copyItem 耗时）

    func testBackupCopyCost() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("perftest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let jsonFile = tmp.appendingPathComponent("library.json")
        let backupFile = tmp.appendingPathComponent("library.backup")

        let data = try! JSONEncoder.reader.encode(makeLargeLibrary())
        try! data.write(to: jsonFile)

        measure {
            if FileManager.default.fileExists(atPath: jsonFile.path) {
                try? FileManager.default.removeItem(at: backupFile)
                try? FileManager.default.copyItem(at: jsonFile, to: backupFile)
            }
        }
    }

    // MARK: - Helpers

    private func makeLargeLibrary() -> LibraryFile {
        let books = (0..<100).map { i -> Book in
            var b = Book(
                id: UUID(), title: "Book \(i)", rootPath: "/tmp/books/book\(i)",
                homePath: "index.html", importedAt: Date(timeIntervalSince1970: TimeInterval(i)),
                toc: [], bookmarks: [], lastReadPath: "page\(i % 10).html",
                contentFingerprint: nil, isPinned: i < 10 ? true : nil
            )
            var bookmarks: [Bookmark] = []
            for j in 0..<10 {
                bookmarks.append(Bookmark(
                    id: UUID(), title: "\(j)-\(i)", path: "p\(j).html",
                    scrollY: Double(j * 100), createdAt: Date(timeIntervalSince1970: TimeInterval(j + i * 10))
                ))
            }
            b.bookmarks = bookmarks
            for j in 0..<10 {
                b.toc.append(TOCItem(title: "Chapter \(j)", path: "ch\(j).html"))
            }
            return b
        }
        return LibraryFile(schemaVersion: 2, books: books)
    }
}
