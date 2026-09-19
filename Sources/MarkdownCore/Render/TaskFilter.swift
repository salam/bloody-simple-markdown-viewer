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

    /// The document reduced to task lines in the given states.
    /// An empty state set yields an empty document rather than everything.
    public static func filtered(_ document: RenderedDocument,
                                states: Set<Checkbox.State>,
                                theme: Theme = .system) -> NSAttributedString {
        let ranges = paragraphs(in: document, states: states)
        guard !ranges.isEmpty else {
            return NSAttributedString(string: states.isEmpty
                ? "No task states selected."
                : "No matching tasks in this document.",
                attributes: [.font: theme.bodyFont, .foregroundColor: theme.secondaryTextColor])
        }

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
