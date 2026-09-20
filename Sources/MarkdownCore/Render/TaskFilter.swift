import AppKit

/// Reduces a rendered document to just its task items.
///
/// Long checklists are often the reason a document is open at all. Filtering to
/// the states that matter turns a sprawling document into the list of what is
/// still open, without editing anything.
///
/// Filtered lines keep their `sourceOffset`, so double-clicking one still jumps
/// to the right place in the real document.
public enum TaskFilter {
    /// Every task state present in the document, in a stable order.
    public static func statesPresent(in document: RenderedDocument) -> [Checkbox.State] {
        var seen = Set<String>()
        let full = NSRange(location: 0, length: document.attributedString.length)
        document.attributedString.enumerateAttribute(.taskState, in: full) { value, _, _ in
            if let raw = value as? String { seen.insert(raw) }
        }
        return Checkbox.State.allCases.filter { seen.contains($0.rawValue) }
    }

    public static func taskCount(in document: RenderedDocument, state: Checkbox.State) -> Int {
        paragraphs(in: document, states: [state]).count
    }

    /// How many lines a filter would show. The window asks before filtering so
    /// it can put up an empty state instead of an empty page.
    public static func matchCount(in document: RenderedDocument,
                                  states: Set<Checkbox.State>) -> Int {
        paragraphs(in: document, states: states).count
    }

    /// The document reduced to task lines in the given states.
    ///
    /// An empty state set yields an empty document rather than everything, and
    /// no matches yields an empty one too. Saying so in body text would read
    /// like a line the file actually contains, so the window draws that message
    /// as chrome instead.
    public static func filtered(_ document: RenderedDocument,
                                states: Set<Checkbox.State>,
                                theme: Theme = .system) -> NSAttributedString {
        let ranges = paragraphs(in: document, states: states)
        guard !ranges.isEmpty else { return NSAttributedString() }

        let out = NSMutableAttributedString()
        let source = document.attributedString
        for range in ranges {
            let line = NSMutableAttributedString(attributedString: source.attributedSubstring(from: range))
            // Flatten the indentation: a filtered list is one flat list, not a
            // reconstruction of where each item sat in the original hierarchy.
            let style = NSMutableParagraphStyle()
            style.firstLineHeadIndent = 0
            style.headIndent = 26
            style.paragraphSpacing = 5
            style.lineHeightMultiple = 1.25
            style.tabStops = [NSTextTab(textAlignment: .left, location: 26)]
            line.addAttribute(.paragraphStyle, value: style,
                              range: NSRange(location: 0, length: line.length))
            out.append(line)
            if !line.string.hasSuffix("\n") {
                out.append(NSAttributedString(string: "\n", attributes: [.font: theme.bodyFont]))
            }
        }
        return out
    }

    /// One task item, as a caller outside the view layer wants it.
    public struct Item: Sendable, Equatable {
        public let state: Checkbox.State
        /// The item's text, with the checkbox glyph and its tab removed.
        public let text: String
        /// UTF-8 byte offset of the item in the source.
        public let sourceOffset: Int
    }

    /// Task items in document order.
    ///
    /// Read off the rendered document rather than the source, so the spellings
    /// people actually write — `[OK]`, `[DONE]`, `[~]`, `[✅]` — are already
    /// resolved to a state and stripped from the text.
    public static func items(in document: RenderedDocument,
                             states: Set<Checkbox.State> = Set(Checkbox.State.allCases)) -> [Item] {
        let attributed = document.attributedString
        let text = attributed.string as NSString
        return paragraphs(in: document, states: states).compactMap { paragraph in
            guard let raw = attributed.attribute(.taskState, at: paragraph.location,
                                                 effectiveRange: nil) as? String,
                  let state = Checkbox.State(rawValue: raw),
                  let offset = attributed.attribute(.sourceOffset, at: paragraph.location,
                                                    effectiveRange: nil) as? Int
            else { return nil }
            // The rendered line opens with the glyph and a tab.
            let body = text.substring(with: paragraph)
                .drop { $0 != "\t" }.dropFirst()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            return Item(state: state, text: body, sourceOffset: offset)
        }
    }

    /// The same filter applied to the Markdown source rather than the render.
    ///
    /// Lines come back verbatim, indentation and marker spelling included,
    /// because the point of source mode is to show what the file actually says.
    /// Each line keeps the `sourceOffset` of its real position, so the window
    /// can still jump from a filtered line to the unfiltered one.
    public static func filteredSource(_ document: RenderedDocument,
                                      states: Set<Checkbox.State>,
                                      theme: Theme = .system) -> NSAttributedString {
        let ranges = paragraphs(in: document, states: states)
        guard !ranges.isEmpty else { return NSAttributedString() }

        let bytes = Array(document.source.utf8)
        let rendered = document.attributedString
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.3
        let attributes: [NSAttributedString.Key: Any] = [
            .font: theme.monoFont,
            .foregroundColor: theme.textColor,
            .paragraphStyle: style
        ]

        let out = NSMutableAttributedString()
        for range in ranges {
            guard let offset = rendered.attribute(.sourceOffset, at: range.location,
                                                  effectiveRange: nil) as? Int,
                  let line = SourceOffset.line(atByte: offset, in: bytes) else { continue }
            let piece = NSMutableAttributedString(string: line.text + "\n", attributes: attributes)
            piece.addAttribute(.sourceOffset, value: line.range.lowerBound,
                               range: NSRange(location: 0, length: piece.length))
            out.append(piece)
        }
        return out
    }

    /// Paragraph ranges carrying one of the requested task states.
    ///
    /// Walks paragraph by paragraph rather than by attribute run.
    /// `enumerateAttribute` coalesces adjacent runs that share a value, so two
    /// consecutive `[x]` items come back as a single range and the second one
    /// would be silently dropped.
    private static func paragraphs(in document: RenderedDocument,
                                   states: Set<Checkbox.State>) -> [NSRange] {
        guard !states.isEmpty, document.attributedString.length > 0 else { return [] }
        let wanted = Set(states.map(\.rawValue))
        let attributed = document.attributedString
        let text = attributed.string as NSString

        var ranges: [NSRange] = []
        var location = 0
        while location < text.length {
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            guard paragraph.length > 0 else { break }

            var state: String?
            attributed.enumerateAttribute(.taskState, in: paragraph) { value, _, stop in
                if let raw = value as? String { state = raw; stop.pointee = true }
            }
            if let state, wanted.contains(state) { ranges.append(paragraph) }

            location = paragraph.location + paragraph.length
        }
        return ranges
    }
}
