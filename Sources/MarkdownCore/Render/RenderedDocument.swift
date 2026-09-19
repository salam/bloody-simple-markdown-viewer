import AppKit

/// One entry in the document outline, derived from a heading.
public struct OutlineEntry: Sendable, Identifiable {
    public let id = UUID()
    public let level: Int
    public let title: String
    /// GitHub-compatible anchor slug. No Markdown parser produces these;
    /// GitHub generates them in a separate post-processing pass, so we do too.
    public let anchor: String
    /// UTF-8 byte offset of the heading in the source document.
    public let sourceOffset: Int
    /// UTF-16 offset of the heading in the rendered attributed string.
    public let characterOffset: Int

    public init(level: Int, title: String, anchor: String, sourceOffset: Int, characterOffset: Int) {
        self.level = level
        self.title = title
        self.anchor = anchor
        self.sourceOffset = sourceOffset
        self.characterOffset = characterOffset
    }
}

/// The product of rendering: styled text, its outline, and the mapping back
/// to source that search, bookmarks and the source toggle all rely on.
public final class RenderedDocument {
    public let attributedString: NSAttributedString
    public let outline: [OutlineEntry]
    public let lineIndex: LineIndex
    public let source: String
    public let frontmatter: String?

    init(attributedString: NSAttributedString, outline: [OutlineEntry],
         lineIndex: LineIndex, source: String, frontmatter: String?) {
        self.attributedString = attributedString
        self.outline = outline
        self.lineIndex = lineIndex
        self.source = source
        self.frontmatter = frontmatter
    }

    public static let empty = RenderedDocument(
        attributedString: NSAttributedString(),
        outline: [], lineIndex: LineIndex(source: ""), source: "", frontmatter: nil
    )

    /// Rendered character offset closest to a given source byte offset.
    /// Used to hold scroll position across the rendered/source toggle.
    public func characterOffset(forSourceOffset target: Int) -> Int {
        var best = 0
        var bestDelta = Int.max
        let full = NSRange(location: 0, length: attributedString.length)
        attributedString.enumerateAttribute(.sourceOffset, in: full) { value, range, stop in
            guard let offset = value as? Int else { return }
            let delta = abs(offset - target)
            if delta < bestDelta {
                bestDelta = delta
                best = range.location
                if delta == 0 { stop.pointee = true }
            }
        }
        return best
    }

    /// Source byte offset for a rendered character offset. The inverse of the above.
    public func sourceOffset(forCharacterOffset target: Int) -> Int {
        guard attributedString.length > 0 else { return 0 }
        let clamped = min(max(target, 0), attributedString.length - 1)
        return attributedString.attribute(.sourceOffset, at: clamped, effectiveRange: nil) as? Int ?? 0
    }
}
