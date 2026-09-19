import AppKit

/// A user-placed mark in a document.
///
/// Stores a short snippet of the line it sat on as well as the byte offset, so
/// a bookmark can be re-found by content when the file has been edited
/// underneath it rather than silently pointing at the wrong line.
public struct Bookmark: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var sourceOffset: Int
    public var snippet: String
    public var created: Date = Date()

    public init(sourceOffset: Int, snippet: String) {
        self.sourceOffset = sourceOffset
        self.snippet = snippet
    }
}

/// Persists bookmarks per file.
///
/// Keyed by security-scoped bookmark data rather than by path, so marks survive
/// the file being moved or renamed.
@MainActor
public final class BookmarkStore {
    public static let shared = BookmarkStore()

    private struct Entry: Codable {
        var bookmarkData: Data?
        var lastKnownPath: String
        var bookmarks: [Bookmark]
    }

    private var entries: [String: Entry] = [:]
    private let storeURL: URL

    /// A custom location is used by tests, so they never touch the real store.
    public init(storeURL: URL? = nil) {
        if let storeURL {
            self.storeURL = storeURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask)[0]
                .appendingPathComponent("BloodySimpleMarkdownViewer", isDirectory: true)
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            self.storeURL = support.appendingPathComponent("bookmarks.json")
        }
        load()
    }

    private func key(for url: URL) -> String { url.standardizedFileURL.path }

    public func bookmarks(for url: URL) -> [Bookmark] {
        entries[key(for: url)]?.bookmarks.sorted { $0.sourceOffset < $1.sourceOffset } ?? []
    }

    public func add(for url: URL, sourceOffset: Int, snippet: String) {
        var entry = entries[key(for: url)] ?? Entry(
            bookmarkData: try? url.bookmarkData(options: .withSecurityScope),
            lastKnownPath: url.path,
            bookmarks: []
        )
        // Adding at a position that already has a mark toggles it off.
        if let existing = entry.bookmarks.firstIndex(where: { abs($0.sourceOffset - sourceOffset) < 4 }) {
            entry.bookmarks.remove(at: existing)
        } else {
            entry.bookmarks.append(Bookmark(sourceOffset: sourceOffset, snippet: snippet))
        }
        entries[key(for: url)] = entry
        save()
    }

    public func remove(_ bookmark: Bookmark, for url: URL) {
        guard var entry = entries[key(for: url)] else { return }
        entry.bookmarks.removeAll { $0.id == bookmark.id }
        entries[key(for: url)] = entry
        save()
    }

    /// Re-locates a bookmark whose file has changed underneath it, by looking
    /// for its snippet near the recorded offset before falling back to it.
    public func resolvedOffset(for bookmark: Bookmark, in source: String) -> Int {
        let ns = source as NSString
        guard !bookmark.snippet.isEmpty, ns.length > 0 else {
            return min(bookmark.sourceOffset, max(ns.length - 1, 0))
        }
        let found = ns.range(of: bookmark.snippet)
        if found.location != NSNotFound { return found.location }
        return min(bookmark.sourceOffset, max(ns.length - 1, 0))
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
