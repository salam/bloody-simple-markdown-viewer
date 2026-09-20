import Foundation

/// Conversions between the two ways a position in the source can be counted.
///
/// Every source position in this codebase is a UTF-8 **byte** offset: that is
/// what cmark reports, what `.sourceOffset` carries and what `LineIndex` maps.
/// AppKit's text APIs count UTF-16 units instead. The two numbers are equal for
/// as long as a document stays ASCII and diverge the moment it does not, which
/// is why mixing them survives testing and then quietly points at the wrong
/// line in the first document with an umlaut or an em dash in it.
///
/// Anywhere the two meet, the conversion goes through here.
public enum SourceOffset {
    /// UTF-16 index for a UTF-8 byte offset. A byte offset landing inside a
    /// character resolves to that character's start.
    public static func utf16(forByte offset: Int, in source: String) -> Int {
        guard offset > 0 else { return 0 }
        let utf8 = source.utf8
        guard offset < utf8.count else { return source.utf16.count }

        var index = utf8.index(utf8.startIndex, offsetBy: offset)
        while index > utf8.startIndex, index.samePosition(in: source.utf16) == nil {
            index = utf8.index(before: index)
        }
        guard let position = index.samePosition(in: source.utf16) else { return 0 }
        return source.utf16.distance(from: source.utf16.startIndex, to: position)
    }

    /// UTF-8 byte offset for a UTF-16 index, the inverse of the above.
    public static func byte(forUTF16 offset: Int, in source: String) -> Int {
        guard offset > 0 else { return 0 }
        let utf16 = source.utf16
        guard offset < utf16.count else { return source.utf8.count }

        var index = utf16.index(utf16.startIndex, offsetBy: offset)
        while index > utf16.startIndex, index.samePosition(in: source.utf8) == nil {
            index = utf16.index(before: index)
        }
        guard let position = index.samePosition(in: source.utf8) else { return 0 }
        return source.utf8.distance(from: source.utf8.startIndex, to: position)
    }

    /// The source line containing a byte offset, trimmed.
    public static func line(atByte offset: Int, in source: String) -> String {
        guard let found = line(atByte: offset, in: Array(source.utf8)) else { return "" }
        return found.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The whole source line containing a UTF-8 byte offset, and where it starts.
    ///
    /// Scanning bytes rather than characters is deliberate: only the line feed
    /// can appear as byte 0x0A, so a multi-byte character can never be mistaken
    /// for a boundary. Callers walking many lines pass the bytes in once.
    public static func line(atByte offset: Int, in bytes: [UInt8]) -> (text: String, range: Range<Int>)? {
        guard !bytes.isEmpty else { return nil }
        let probe = min(max(offset, 0), bytes.count - 1)
        var start = probe
        while start > 0, bytes[start - 1] != 0x0A { start -= 1 }
        var end = probe
        while end < bytes.count, bytes[end] != 0x0A { end += 1 }
        guard end > start else { return nil }
        return (String(decoding: bytes[start..<end], as: UTF8.self), start..<end)
    }
}
