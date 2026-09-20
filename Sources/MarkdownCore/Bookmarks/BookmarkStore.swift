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

    /// Adds a mark at a UTF-8 byte offset, or removes the one already there.
    ///
    /// - Returns: `true` when a mark was added, `false` when one was removed.
    ///   The caller needs to know which, because the two look identical
    ///   otherwise and the same keystroke does both.
    @discardableResult
    public func add(for url: URL, sourceOffset: Int, snippet: String) -> Bool {
        var entry = entries[key(for: url)] ?? Entry(
            bookmarkData: try? url.bookmarkData(options: .withSecurityScope),
            lastKnownPath: url.path,
            bookmarks: []
        )
        // Adding at a position that already has a mark toggles it off.
        let added: Bool
        if let existing = entry.bookmarks.firstIndex(where: { abs($0.sourceOffset - sourceOffset) < 4 }) {
            entry.bookmarks.remove(at: existing)
            added = false
        } else {
            entry.bookmarks.append(Bookmark(sourceOffset: sourceOffset, snippet: snippet))
            added = true
        }
        entries[key(for: url)] = entry
        save()
        return added
    }

    public func remove(_ bookmark: Bookmark, for url: URL) {
        guard var entry = entries[key(for: url)] else { return }
        entry.bookmarks.removeAll { $0.id == bookmark.id }
        entries[key(for: url)] = entry
        save()
    }

    /// Re-locates a bookmark whose file has changed underneath it, by looking
    /// for its snippet near the recorded offset before falling back to it.
    ///
    /// Returns a UTF-8 byte offset, the same unit `sourceOffset` is stored in.
    /// `NSString.range(of:)` answers in UTF-16, so the match has to be
    /// converted; returning it raw put every mark in a document containing so
    /// much as an umlaut on the wrong line.
    public func resolvedOffset(for bookmark: Bookmark, in source: String) -> Int {
        let byteCount = source.utf8.count
        let fallback = min(bookmark.sourceOffset, max(byteCount - 1, 0))
        guard !bookmark.snippet.isEmpty, byteCount > 0 else { return fallback }

        let found = (source as NSString).range(of: bookmark.snippet)
        guard found.location != NSNotFound else { return fallback }
        return SourceOffset.byte(forUTF16: found.location, in: source)
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
