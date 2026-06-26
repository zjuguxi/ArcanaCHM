import Foundation

struct Book: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var rootPath: String
    var homePath: String?
    var importedAt: Date
    var toc: [TOCItem]
    var bookmarks: [Bookmark]
    var notes: [DocumentNote]
    var tags: [String]
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
            notes: [],
            tags: [],
            lastReadPath: nil,
            contentFingerprint: nil,
            isPinned: nil
        )
    }
}

struct TOCItem: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var path: String?
    var children: [TOCItem]
    var outlineChildren: [TOCItem]? { children.isEmpty ? nil : children }

    init(id: UUID = UUID(), title: String, path: String? = nil, children: [TOCItem] = []) {
        self.id = id
        self.title = title
        self.path = path
        self.children = children
    }
}

struct Bookmark: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var path: String
    var scrollY: Double
    var createdAt: Date
}

struct DocumentNote: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var body: String
    var path: String
    var createdAt: Date
    var updatedAt: Date
}

struct SearchHit: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var path: String
    var snippet: String
}
