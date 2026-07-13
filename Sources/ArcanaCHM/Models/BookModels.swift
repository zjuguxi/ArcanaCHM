import Foundation

struct Book: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var rootPath: String
    var homePath: String?
    var importedAt: Date
    var toc: [TOCItem]
    var bookmarks: [Bookmark]
    var lastReadPath: String?
    var contentFingerprint: String?
    var isPinned: Bool?

    var rootURL: URL { URL(fileURLWithPath: rootPath) }

    static func empty(title: String, rootURL: URL) -> Book {
        Book(
            id: UUID(),
            title: title,
            rootPath: rootURL.path,
            homePath: nil,
            importedAt: Date(),
            toc: [],
            bookmarks: [],
            lastReadPath: nil,
            contentFingerprint: nil,
            isPinned: nil
        )
    }
}

struct TOCItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var path: String?
    var children: [TOCItem]

    init(id: UUID = UUID(), title: String, path: String? = nil, children: [TOCItem] = []) {
        self.id = id
        self.title = title
        self.path = path
        self.children = children
    }
}

struct Bookmark: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var path: String
    var scrollY: Double
    var createdAt: Date
}

struct SearchHit: Identifiable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var path: String
    var snippet: String
}
