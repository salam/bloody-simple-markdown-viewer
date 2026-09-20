import Foundation
import Testing
@testable import MarkdownCore

@Suite("SourceOffset")
struct SourceOffsetTests {
    /// German text with the punctuation these documents actually contain. Every
    /// one of these characters is one UTF-16 unit and two or three UTF-8 bytes,
    /// which is what makes the two counts diverge.
    private let source = """
    # Überschrift — mit Sonderzeichen

    - [x] **LLM-Keys in `.env`** — Infomaniak AI gesetzt
    - [~] Tagesordnungen → SessionId → SharePoint
    - [ ] «Aktuell» prüfen

    ## Ziel
    """

    @Test func theFixtureActuallyDistinguishesTheTwoCounts() {
        #expect(source.utf8.count != source.utf16.count)
    }

    @Test func roundTripsEveryCharacterBoundary() {
        for index in source.indices {
            let byte = source.utf8.distance(from: source.utf8.startIndex,
                                            to: index.samePosition(in: source.utf8)!)
            let utf16 = source.utf16.distance(from: source.utf16.startIndex,
                                              to: index.samePosition(in: source.utf16)!)
            #expect(SourceOffset.utf16(forByte: byte, in: source) == utf16)
            #expect(SourceOffset.byte(forUTF16: utf16, in: source) == byte)
        }
    }

    /// A byte offset can land inside a multi-byte character; it must resolve to
    /// that character's start rather than to zero or to a crash.
    @Test func roundsDownFromInsideACharacter() {
        let text = "aÜb"                       // a=1 byte, Ü=2 bytes, b=1 byte
        #expect(SourceOffset.utf16(forByte: 2, in: text) == 1)   // inside the Ü
        #expect(SourceOffset.utf16(forByte: 1, in: text) == 1)   // start of the Ü
        #expect(SourceOffset.utf16(forByte: 3, in: text) == 2)   // the b
    }

    @Test func clampsAtTheEnds() {
        #expect(SourceOffset.utf16(forByte: -1, in: source) == 0)
        #expect(SourceOffset.byte(forUTF16: -1, in: source) == 0)
        #expect(SourceOffset.utf16(forByte: 99_999, in: source) == source.utf16.count)
        #expect(SourceOffset.byte(forUTF16: 99_999, in: source) == source.utf8.count)
        #expect(SourceOffset.utf16(forByte: 0, in: "") == 0)
        #expect(SourceOffset.byte(forUTF16: 0, in: "") == 0)
    }

    @Test func readsTheLineAtAByteOffset() {
        let byte = source.utf8.distance(
            from: source.utf8.startIndex,
            to: source.range(of: "SharePoint")!.lowerBound.samePosition(in: source.utf8)!)
        #expect(SourceOffset.line(atByte: byte, in: source)
            == "- [~] Tagesordnungen → SessionId → SharePoint")
    }

    /// The failure this was written for, at the scale it actually happens.
    ///
    /// A handful of multi-byte characters shifts the two counts by less than a
    /// line, so a small fixture reads the same either way and the bug survives
    /// the test suite. It took a real 28 KB document, where the counts differ
    /// by 649, to land on the wrong line.
    @Test func theLineIsNotWhatAUTF16ReadingWouldGive() {
        let filler = Array(repeating: "- [x] **Ein Punkt** — mit Pfeil → und «Zitat»", count: 200)
        // Target in the middle, with filler after it too: at the end of the
        // document the wrong offset merely clamps back onto the right line.
        let document = (filler + ["", "## Das Ziel", ""] + filler).joined(separator: "\n")
        #expect(document.utf8.count - document.utf16.count > 200,
                "the fixture must diverge by more than a line")

        let byte = document.utf8.distance(
            from: document.utf8.startIndex,
            to: document.range(of: "## Das Ziel")!.lowerBound.samePosition(in: document.utf8)!)

        // What the old code did: take the byte offset as an NSString index.
        // The clamp is not incidental — unclamped it raises, because in a
        // non-ASCII document the byte count exceeds the UTF-16 length.
        let ns = document as NSString
        let naive = ns
            .substring(with: ns.lineRange(for: NSRange(location: min(byte, ns.length - 1), length: 0)))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(naive != "## Das Ziel", "the fixture must actually expose the bug")
        #expect(SourceOffset.line(atByte: byte, in: document) == "## Das Ziel")
    }

    @Test func emptyLinesGiveAnEmptySnippet() {
        #expect(SourceOffset.line(atByte: 0, in: "") == "")
    }
}
