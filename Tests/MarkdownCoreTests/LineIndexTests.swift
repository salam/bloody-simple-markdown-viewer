import Testing
@testable import MarkdownCore

@Suite("LineIndex")
struct LineIndexTests {
    @Test func mapsLineAndColumnToByteOffset() {
        let index = LineIndex(source: "abc\ndefg\nhi")
        #expect(index.utf8Offset(line: 1, column: 1) == 0)
        #expect(index.utf8Offset(line: 2, column: 1) == 4)
        #expect(index.utf8Offset(line: 3, column: 2) == 10)
    }

    @Test func handlesMultibyteCharacters() {
        // "é" is 2 UTF-8 bytes, "🎉" is 4, plus the newline = 7
        let index = LineIndex(source: "é🎉\nx")
        #expect(index.utf8Offset(line: 2, column: 1) == 7)
    }

    @Test func clampsOutOfRangeInput() {
        let index = LineIndex(source: "a\nb")
        #expect(index.utf8Offset(line: 99, column: 1) == 3)
        #expect(index.utf8Offset(line: 0, column: 1) == 0)
    }
}
