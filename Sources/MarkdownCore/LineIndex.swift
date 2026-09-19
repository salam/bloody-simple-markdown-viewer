import Foundation

/// Maps swift-markdown's 1-based line/column source locations onto UTF-8 byte
/// offsets in the original document.
///
/// Every rendered run carries a byte offset so that search, bookmarks and the
/// rendered/source toggle can all be expressed as one mapping rather than three.
public struct LineIndex: Sendable {
    private let lineStarts: [Int]
    private let utf8Count: Int

    public init(source: String) {
        var starts = [0]
        var offset = 0
        for byte in source.utf8 {
            offset += 1
            if byte == 0x0A { starts.append(offset) }
        }
        self.lineStarts = starts
        self.utf8Count = offset
    }

    public var byteCount: Int { utf8Count }

    /// - Parameters:
    ///   - line: 1-based line number, as reported by swift-markdown.
    ///   - column: 1-based column in UTF-8 code units.
    public func utf8Offset(line: Int, column: Int) -> Int {
        guard line >= 1 else { return 0 }
        guard line <= lineStarts.count else { return utf8Count }
        return min(lineStarts[line - 1] + max(0, column - 1), utf8Count)
    }
}
