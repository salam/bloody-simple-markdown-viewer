import AppKit

public extension NSAttributedString.Key {
    /// UTF-8 byte offset of this run in the original source document.
    /// Search, bookmarks and the rendered/source toggle all read this.
    static let sourceOffset = NSAttributedString.Key("MarkdownCore.sourceOffset")
    /// Block quote nesting depth, 1 or greater. Drives the drawn left bar.
    static let quoteDepth = NSAttributedString.Key("MarkdownCore.quoteDepth")
    /// Raw value of an `AlertKind` when this quote is a GitHub alert.
    static let alertKind = NSAttributedString.Key("MarkdownCore.alertKind")
    /// Heading level, 1 to 6. Used by the outline and by section navigation.
    static let headingLevel = NSAttributedString.Key("MarkdownCore.headingLevel")
    /// Marks a run as being inside a fenced or indented code block.
    static let codeBlock = NSAttributedString.Key("MarkdownCore.codeBlock")
}
