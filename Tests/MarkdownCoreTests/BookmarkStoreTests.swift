import Foundation
import Testing
@testable import MarkdownCore

@MainActor
@Suite("BookmarkStore")
struct BookmarkStoreTests {
    private func makeStore() -> (BookmarkStore, URL) {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bsmv-tests-\(UUID().uuidString).json")
        return (BookmarkStore(storeURL: temp), temp)
    }

    private let file = URL(fileURLWithPath: "/tmp/notes.md")

    @Test func startsEmpty() {
        let (store, _) = makeStore()
        #expect(store.bookmarks(for: file).isEmpty)
    }

    @Test func addsAndListsBookmarks() {
        let (store, _) = makeStore()
        store.add(for: file, sourceOffset: 120, snippet: "## Design notes")
        store.add(for: file, sourceOffset: 40, snippet: "# Title")
        let marks = store.bookmarks(for: file)
        #expect(marks.count == 2)
        // Listed in document order, not insertion order.
        #expect(marks.map(\.sourceOffset) == [40, 120])
    }

    @Test func addingAtTheSamePlaceRemovesIt() {
        let (store, _) = makeStore()
        store.add(for: file, sourceOffset: 100, snippet: "line")
        #expect(store.bookmarks(for: file).count == 1)
        store.add(for: file, sourceOffset: 101, snippet: "line")
        #expect(store.bookmarks(for: file).isEmpty, "a second mark at the same spot should toggle off")
    }

    @Test func keepsFilesSeparate() {
        let (store, _) = makeStore()
        let other = URL(fileURLWithPath: "/tmp/other.md")
        store.add(for: file, sourceOffset: 10, snippet: "a")
        store.add(for: other, sourceOffset: 20, snippet: "b")
        #expect(store.bookmarks(for: file).count == 1)
        #expect(store.bookmarks(for: other).count == 1)
    }

    @Test func removesOne() {
        let (store, _) = makeStore()
        store.add(for: file, sourceOffset: 10, snippet: "a")
        store.add(for: file, sourceOffset: 50, snippet: "b")
        let first = store.bookmarks(for: file)[0]
        store.remove(first, for: file)
        #expect(store.bookmarks(for: file).count == 1)
    }

    @Test func survivesReloadFromDisk() {
        let (store, url) = makeStore()
        store.add(for: file, sourceOffset: 77, snippet: "persisted line")
        let reopened = BookmarkStore(storeURL: url)
        #expect(reopened.bookmarks(for: file).first?.snippet == "persisted line")
    }

    /// The point of storing a snippet: a mark must not silently point at the
    /// wrong line after the file is edited above it.
    @Test func relocatesByContentWhenTheFileHasChanged() {
        let (store, _) = makeStore()
        let original = "# Title\n\nfirst\n\n## Target section\n\nbody\n"
        let offset = (original as NSString).range(of: "## Target section").location
        store.add(for: file, sourceOffset: offset, snippet: "## Target section")
        let bookmark = store.bookmarks(for: file)[0]

        // Insert a paragraph above, shifting everything down.
        let edited = "# Title\n\nAn inserted paragraph that was not there before.\n\nfirst\n\n## Target section\n\nbody\n"
        let resolved = store.resolvedOffset(for: bookmark, in: edited)
        let expected = (edited as NSString).range(of: "## Target section").location
        #expect(resolved == expected)
        #expect(resolved != bookmark.sourceOffset, "the stored offset was stale and should not have been used")
    }

    @Test func fallsBackToTheStoredOffsetWhenTheSnippetIsGone() {
        let (store, _) = makeStore()
        store.add(for: file, sourceOffset: 5, snippet: "## Deleted heading")
        let bookmark = store.bookmarks(for: file)[0]
        let resolved = store.resolvedOffset(for: bookmark, in: "completely different content here")
        #expect(resolved == 5)
    }

    /// The bug this was written for. Marks are stored as UTF-8 byte offsets;
    /// `NSString.range(of:)` answers in UTF-16. Returning the match raw put
    /// every mark in a document containing so much as an umlaut on the wrong
    /// line, and the whole feature looked broken.
    @Test func resolvedOffsetIsAUTF8ByteOffset() {
        let (store, _) = makeStore()
        let source = """
        # Überschrift — mit Sonderzeichen

        Ein Absatz mit «Anführungszeichen» und einem Pfeil →.

        ## Ziel
        """
        let target = source.range(of: "## Ziel")!
        let byteOffset = source.utf8.distance(from: source.utf8.startIndex,
                                              to: target.lowerBound.samePosition(in: source.utf8)!)
        let utf16Offset = (source as NSString).range(of: "## Ziel").location
        #expect(byteOffset != utf16Offset, "the fixture must actually distinguish the two")

        store.add(for: file, sourceOffset: byteOffset, snippet: "## Ziel")
        let bookmark = store.bookmarks(for: file)[0]
        #expect(store.resolvedOffset(for: bookmark, in: source) == byteOffset)
    }

    /// The same keystroke adds and removes, so the caller has to be told which
    /// happened or it cannot give the reader any feedback at all.
    @Test func addingReportsWhetherItAddedOrRemoved() {
        let (store, _) = makeStore()
        #expect(store.add(for: file, sourceOffset: 100, snippet: "line") == true)
        #expect(store.add(for: file, sourceOffset: 101, snippet: "line") == false)
        #expect(store.add(for: file, sourceOffset: 101, snippet: "line") == true)
    }

    @Test func clampsToTheEndOfAShrunkenDocument() {
        let (store, _) = makeStore()
        store.add(for: file, sourceOffset: 9_000, snippet: "gone")
        let bookmark = store.bookmarks(for: file)[0]
        let resolved = store.resolvedOffset(for: bookmark, in: "tiny")
        #expect(resolved < 4)
    }
}
