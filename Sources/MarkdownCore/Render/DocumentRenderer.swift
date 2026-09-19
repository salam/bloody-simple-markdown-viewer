import AppKit
import Markdown

/// Turns Markdown source into styled text for a TextKit 2 view.
///
/// The spec originally described building a separate document IR. Walking
/// swift-markdown's own tree straight into an attributed string does the same
/// job with strictly less code, so there is no second tree.
public final class DocumentRenderer {
    public let theme: Theme
    public let baseURL: URL?
    public let attachmentRendering: AttachmentRendering

    public init(theme: Theme = .system, baseURL: URL? = nil,
                attachmentRendering: AttachmentRendering = .interactive) {
        self.theme = theme
        self.baseURL = baseURL
        self.attachmentRendering = attachmentRendering
    }

    public func render(source: String) -> RenderedDocument {
        let split = Frontmatter.split(source)
        let lineIndex = LineIndex(source: source)
        // Math comes out before cmark sees the text: it has no idea what a
        // formula is and would turn the underscores in `$a_i b_j$` into
        // emphasis, corrupting it.
        let math = MathExtractor.extract(from: split.body)
        // Source locations come back relative to the body, so shift them past
        // any frontmatter we removed.
        let bodyStartByte = LineIndex(source: source).utf8Offset(line: split.bodyLineOffset + 1, column: 1)

        let document = Document(parsing: math.text, options: [])
        var visitor = AttributedStringVisitor(
            theme: theme,
            baseURL: baseURL,
            bodyLineOffset: split.bodyLineOffset,
            bodyStartByte: bodyStartByte,
            lineIndex: lineIndex,
            mathSpans: math.spans,
            attachmentRendering: attachmentRendering
        )
        let text = visitor.visit(document)
        let trimmed = NSMutableAttributedString(attributedString: text)
        trimTrailingNewlines(trimmed)

        return RenderedDocument(
            attributedString: trimmed,
            outline: resolveCharacterOffsets(visitor.outline, in: trimmed),
            lineIndex: lineIndex,
            source: source,
            frontmatter: split.frontmatter
        )
    }

    /// Walks the finished string and pins each outline entry to where its
    /// heading actually landed, matching entries to heading runs in order.
    private func resolveCharacterOffsets(_ outline: [OutlineEntry],
                                         in string: NSAttributedString) -> [OutlineEntry] {
        guard !outline.isEmpty else { return [] }
        var starts: [Int] = []
        var lastEnd = -1
        string.enumerateAttribute(.headingLevel,
                                  in: NSRange(location: 0, length: string.length)) { value, range, _ in
            guard value != nil else { return }
            if range.location != lastEnd { starts.append(range.location) }
            lastEnd = range.location + range.length
        }
        return outline.enumerated().map { index, entry in
            OutlineEntry(level: entry.level, title: entry.title, anchor: entry.anchor,
                         sourceOffset: entry.sourceOffset,
                         characterOffset: index < starts.count ? starts[index] : 0)
        }
    }

    private func trimTrailingNewlines(_ s: NSMutableAttributedString) {
        while s.length > 0, s.string.hasSuffix("\n") {
            s.deleteCharacters(in: NSRange(location: s.length - 1, length: 1))
        }
    }
}

// MARK: - The visitor

struct AttributedStringVisitor: MarkupVisitor {
    typealias Result = NSAttributedString

    let theme: Theme
    let baseURL: URL?
    let bodyLineOffset: Int
    let bodyStartByte: Int
    let lineIndex: LineIndex
    let mathSpans: [MathSpan]
    let attachmentRendering: AttachmentRendering

    var outline: [OutlineEntry] = []
    private var usedAnchors: Set<String> = []
    private var quoteDepth = 0
    private var listDepth = 0

    init(theme: Theme, baseURL: URL?, bodyLineOffset: Int, bodyStartByte: Int,
         lineIndex: LineIndex, mathSpans: [MathSpan],
         attachmentRendering: AttachmentRendering) {
        self.theme = theme
        self.baseURL = baseURL
        self.bodyLineOffset = bodyLineOffset
        self.bodyStartByte = bodyStartByte
        self.lineIndex = lineIndex
        self.mathSpans = mathSpans
        self.attachmentRendering = attachmentRendering
    }

    // MARK: Source mapping

    private func sourceOffset(of markup: Markup) -> Int {
        guard let range = markup.range else { return bodyStartByte }
        return lineIndex.utf8Offset(line: range.lowerBound.line + bodyLineOffset,
                                    column: range.lowerBound.column)
    }

    private func baseAttributes(for markup: Markup) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: theme.bodyFont,
            .foregroundColor: theme.textColor,
            .sourceOffset: sourceOffset(of: markup)
        ]
        if quoteDepth > 0 { attrs[.quoteDepth] = quoteDepth }
        return attrs
    }

    // MARK: Paragraph styles

    private func paragraphStyle(spacingBefore: CGFloat = 0,
                                spacingAfter: CGFloat = 10,
                                indent: CGFloat = 0,
                                lineHeightMultiple: CGFloat = 1.25) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        style.lineHeightMultiple = lineHeightMultiple
        let quoteIndent = CGFloat(quoteDepth) * 18
        style.firstLineHeadIndent = indent + quoteIndent
        style.headIndent = indent + quoteIndent
        return style
    }

    private mutating func joined(_ children: some Sequence<Markup>) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        for child in children {
            out.append(visit(child))
        }
        return out
    }

    // MARK: Default

    mutating func defaultVisit(_ markup: Markup) -> NSAttributedString {
        joined(markup.children)
    }

    mutating func visitDocument(_ document: Document) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for child in document.children {
            out.append(visit(child))
        }
        return out
    }

    // MARK: Blocks

    mutating func visitHeading(_ heading: Heading) -> NSAttributedString {
        let inner = joined(heading.children)
        let out = NSMutableAttributedString(attributedString: inner)
        let full = NSRange(location: 0, length: out.length)
        out.addAttributes([
            .font: theme.headingFont(level: heading.level),
            .foregroundColor: theme.textColor,
            .headingLevel: heading.level
        ], range: full)

        let style = paragraphStyle(
            spacingBefore: heading.level <= 2 ? 24 : 18,
            spacingAfter: heading.level <= 2 ? 10 : 7,
            lineHeightMultiple: 1.1
        )
        out.addAttribute(.paragraphStyle, value: style, range: full)

        let title = heading.plainText
        let anchor = makeAnchor(from: title)
        outline.append(OutlineEntry(
            level: heading.level,
            title: title,
            anchor: anchor,
            sourceOffset: sourceOffset(of: heading),
            characterOffset: 0
        ))

        out.append(newline(after: heading))
        return out
    }

    /// GitHub's slug rules: lowercase, spaces to hyphens, drop other
    /// punctuation, disambiguate collisions with a numeric suffix. No Markdown
    /// parser does this; GitHub generates it in a separate pass.
    private mutating func makeAnchor(from title: String) -> String {
        let lowered = title.lowercased()
        var slug = ""
        for ch in lowered {
            if ch.isLetter || ch.isNumber { slug.append(ch) }
            else if ch == " " || ch == "-" || ch == "_" { slug.append("-") }
        }
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty { slug = "section" }

        var candidate = slug
        var counter = 1
        while usedAnchors.contains(candidate) {
            candidate = "\(slug)-\(counter)"
            counter += 1
        }
        usedAnchors.insert(candidate)
        return candidate
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: joined(paragraph.children))
        let style = paragraphStyle()
        out.addAttribute(.paragraphStyle, value: style,
                         range: NSRange(location: 0, length: out.length))
        out.append(newline(after: paragraph))
        return out
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> NSAttributedString {
        let alert = detectAlert(blockQuote)
        let outerDepth = quoteDepth
        quoteDepth = outerDepth + 1
        defer { quoteDepth = outerDepth }
        let inner = NSMutableAttributedString()

        if let alert {
            // Title line, e.g. a blue "NOTE" with its symbol.
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: theme.baseFontSize - 1, weight: .bold),
                .foregroundColor: theme.alertTint(for: alert.kind),
                .sourceOffset: sourceOffset(of: blockQuote),
                .quoteDepth: quoteDepth,
                .alertKind: alert.kind.rawValue,
                .paragraphStyle: paragraphStyle(spacingAfter: 4)
            ]
            inner.append(NSAttributedString(string: alert.kind.title + "\n", attributes: titleAttrs))
        }

        for child in blockQuote.children {
            inner.append(visit(child))
        }

        let full = NSRange(location: 0, length: inner.length)
        // Fill gaps only. A nested quote has already recorded its own deeper
        // level, and a blanket write here would flatten it back to ours.
        inner.fillMissing(.quoteDepth, value: quoteDepth, in: full)
        if let alert {
            inner.fillMissing(.alertKind, value: alert.kind.rawValue, in: full)
            // The marker itself is not shown; it becomes the styled title.
            removeAlertMarker(from: inner, marker: alert.marker)
        }
        return inner
    }

    private struct DetectedAlert { let kind: AlertKind; let marker: String }

    private func detectAlert(_ quote: BlockQuote) -> DetectedAlert? {
        guard let paragraph = quote.child(at: 0) as? Paragraph,
              let text = paragraph.child(at: 0) as? Text else { return nil }
        let trimmed = text.string.trimmingCharacters(in: .whitespaces)
        for kind in AlertKind.allCases {
            let marker = "[!\(kind.rawValue.uppercased())]"
            if trimmed.hasPrefix(marker) { return DetectedAlert(kind: kind, marker: marker) }
        }
        return nil
    }

    private func removeAlertMarker(from string: NSMutableAttributedString, marker: String) {
        let range = (string.string as NSString).range(of: marker)
        guard range.location != NSNotFound else { return }
        // Also swallow the newline the marker sat on, so no blank line remains.
        var toDelete = range
        let after = range.location + range.length
        let ns = string.string as NSString
        if after < ns.length, ns.character(at: after) == 10 {
            toDelete.length += 1
        }
        string.deleteCharacters(in: toDelete)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> NSAttributedString {
        var code = codeBlock.code
        if code.hasSuffix("\n") { code.removeLast() }

        // GitHub renders a ```math fence as display math.
        if codeBlock.language?.lowercased() == "math" {
            let attachment = MathTextAttachment(latex: code, isDisplay: true,
                                                theme: theme, rendering: attachmentRendering)
            if !attachment.failed {
                let out = NSMutableAttributedString(attachment: attachment)
                out.addAttributes([
                    .paragraphStyle: paragraphStyle(spacingBefore: 8, spacingAfter: 12),
                    .sourceOffset: sourceOffset(of: codeBlock),
                    .spokenDescription: code
                ], range: NSRange(location: 0, length: out.length))
                out.append(newline(after: codeBlock))
                return out
            }
        }

        let highlighted = NSMutableAttributedString(
            attributedString: SyntaxHighlighter.highlight(code, language: codeBlock.language, theme: theme)
        )

        // Every line inside the block is its own paragraph, so paragraph
        // spacing must be zero or the code ends up double-spaced. Padding above
        // and below comes from the spacer lines instead, which carry the
        // codeBlock attribute so the drawn background covers them.
        let style = paragraphStyle(spacingBefore: 0, spacingAfter: 0, indent: 12,
                                   lineHeightMultiple: 1.15)
        // Long lines wrap rather than run off the edge: a viewer must never
        // hide code, and a horizontal scroller inside flowing text is worse.
        style.lineBreakMode = .byCharWrapping

        let spacerStyle = paragraphStyle(spacingBefore: 0, spacingAfter: 0, indent: 12,
                                         lineHeightMultiple: 1.0)
        let spacer = NSAttributedString(string: "\n", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 4, weight: .regular),
            .paragraphStyle: spacerStyle,
            .sourceOffset: sourceOffset(of: codeBlock),
            .codeBlock: true
        ])

        let out = NSMutableAttributedString()
        out.append(spacer)
        out.append(highlighted)
        let bodyRange = NSRange(location: spacer.length, length: highlighted.length)
        out.addAttributes([
            .paragraphStyle: style,
            .sourceOffset: sourceOffset(of: codeBlock),
            .codeBlock: true
        ], range: bodyRange)
        out.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 4, weight: .regular),
            .paragraphStyle: spacerStyle,
            .sourceOffset: sourceOffset(of: codeBlock),
            .codeBlock: true
        ]))

        let full = NSRange(location: 0, length: out.length)
        if quoteDepth > 0 {
            out.addAttribute(.quoteDepth, value: quoteDepth, range: full)
        }
        out.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 7),
            .sourceOffset: sourceOffset(of: codeBlock),
            .paragraphStyle: paragraphStyle(spacingAfter: 6)
        ]))
        return out
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> NSAttributedString {
        let style = paragraphStyle(spacingBefore: 12, spacingAfter: 16)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: theme.bodyFont,
            .foregroundColor: theme.ruleColor,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .strikethroughColor: theme.ruleColor,
            .paragraphStyle: style,
            .sourceOffset: sourceOffset(of: thematicBreak)
        ]
        // A run of spaces struck through draws as a clean horizontal rule and,
        // unlike a border, reflows with the text width.
        let out = NSMutableAttributedString(
            string: String(repeating: "\u{00A0}", count: 200) + "\n", attributes: attrs
        )
        return out
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> NSAttributedString {
        // Raw HTML is shown as dimmed source rather than hidden, so nothing in
        // the file is silently lost.
        let attrs: [NSAttributedString.Key: Any] = [
            .font: theme.monoFont,
            .foregroundColor: theme.secondaryTextColor,
            .paragraphStyle: paragraphStyle(),
            .sourceOffset: sourceOffset(of: html)
        ]
        var raw = html.rawHTML
        if raw.hasSuffix("\n") { raw.removeLast() }
        let out = NSMutableAttributedString(string: raw + "\n", attributes: attrs)
        return out
    }

    // MARK: Lists

    mutating func visitUnorderedList(_ list: UnorderedList) -> NSAttributedString {
        renderList(list, ordered: false, start: 1)
    }

    mutating func visitOrderedList(_ list: OrderedList) -> NSAttributedString {
        renderList(list, ordered: true, start: Int(list.startIndex))
    }

    private mutating func renderList(_ list: Markup, ordered: Bool, start: Int) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let bullets = ["\u{2022}", "\u{25E6}", "\u{25AA}"]
        let outerDepth = listDepth
        var number = start

        for child in list.children {
            guard let item = child as? ListItem else { continue }
            let markerIndent = CGFloat(listDepth) * 24
            let textIndent = markerIndent + 26

            let itemBody = NSMutableAttributedString()
            listDepth = outerDepth + 1
            for grandchild in item.children {
                itemBody.append(visit(grandchild))
            }
            listDepth = outerDepth

            // cmark only reports [ ] and [x] as task items. Anything else, a
            // tick emoji, [OK], [DONE], reaches us as plain leading text, so
            // detect it here and strip the marker from what is shown.
            var extendedState: Checkbox.State?
            if item.checkbox == nil,
               let found = Checkbox.parseLeadingMarker(in: itemBody.string) {
                extendedState = found.state
                itemBody.deleteCharacters(in: NSRange(location: 0, length: found.consumed))
            }

            let marker: String
            var taskState: Checkbox.State?
            if let checkbox = item.checkbox {
                marker = Checkbox.glyph(for: checkbox == .checked ? .checked : .unchecked)
                taskState = checkbox == .checked ? .checked : .unchecked
            } else if let extendedState {
                marker = Checkbox.glyph(for: extendedState)
                taskState = extendedState
            } else if ordered {
                marker = "\(number)."
                number += 1
            } else {
                marker = bullets[min(listDepth, bullets.count - 1)]
            }

            let isTask = taskState != nil
            let style = paragraphStyle(spacingAfter: 4)
            let quoteIndent = CGFloat(quoteDepth) * 18
            style.firstLineHeadIndent = markerIndent + quoteIndent
            style.headIndent = textIndent + quoteIndent
            style.tabStops = [NSTextTab(textAlignment: .left, location: textIndent + quoteIndent)]
            style.defaultTabInterval = textIndent

            let markerAttrs: [NSAttributedString.Key: Any] = [
                .font: theme.bodyFont,
                .foregroundColor: taskState == .inProgress
                    ? theme.alertTint(for: .warning)
                    : (isTask ? theme.textColor : theme.secondaryTextColor),
                .paragraphStyle: style,
                .listDepth: listDepth + 1,
                .sourceOffset: sourceOffset(of: item)
            ]
            var taskAttributes = markerAttrs
            if let taskState { taskAttributes[.taskState] = taskState.rawValue }
            let line = NSMutableAttributedString(string: marker + "\t", attributes: taskAttributes)
            line.append(itemBody)
            // Apply to this item's own paragraphs only. Content that already
            // carries a list style belongs to a nested list and keeps its own
            // deeper indentation.
            let lineRange = NSRange(location: 0, length: line.length)
            var plainRanges: [NSRange] = []
            line.enumerateAttribute(.listDepth, in: lineRange) { value, subrange, _ in
                if value == nil { plainRanges.append(subrange) }
            }
            for plain in plainRanges {
                line.addAttribute(.paragraphStyle, value: style, range: plain)
                line.addAttribute(.listDepth, value: listDepth + 1, range: plain)
                if let taskState {
                    line.addAttribute(.taskState, value: taskState.rawValue, range: plain)
                }
            }
            out.append(line)
        }

        // A blank line after the list, so it does not collide with what follows.
        out.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 5),
            .sourceOffset: sourceOffset(of: list)
        ]))
        return out
    }

    // MARK: Tables

    mutating func visitTable(_ table: Table) -> NSAttributedString {
        var header: [NSAttributedString] = []
        for cell in table.head.cells {
            header.append(joined(cell.children))
        }

        var rows: [[NSAttributedString]] = []
        for row in table.body.rows {
            var cells: [NSAttributedString] = []
            for cell in row.cells {
                cells.append(joined(cell.children))
            }
            rows.append(cells)
        }

        let alignments: [TableModel.Alignment] = table.columnAlignments.map {
            switch $0 {
            case .left: .left
            case .center: .center
            case .right: .right
            case nil: .left
            }
        }

        let model = TableModel(header: header, alignments: alignments, rows: rows)
        let attachment = TableTextAttachment(model: model, theme: theme,
                                             rendering: attachmentRendering)
        let out = NSMutableAttributedString(attachment: attachment)
        let style = paragraphStyle(spacingBefore: 8, spacingAfter: 14)
        out.addAttributes([
            .paragraphStyle: style,
            .sourceOffset: sourceOffset(of: table)
        ], range: NSRange(location: 0, length: out.length))
        out.append(newline(after: table))
        return out
    }

    // MARK: Inlines

    mutating func visitText(_ text: Text) -> NSAttributedString {
        let attributes = baseAttributes(for: text)
        let pieces = MathExtractor.split(text.string)
        guard pieces.contains(where: { if case .math = $0 { return true }; return false }) else {
            return NSAttributedString(string: Emoji.substitute(in: text.string), attributes: attributes)
        }

        let out = NSMutableAttributedString()
        for piece in pieces {
            switch piece {
            case .text(let literal):
                out.append(NSAttributedString(string: Emoji.substitute(in: literal),
                                              attributes: attributes))
            case .math(let index):
                guard index < mathSpans.count else { continue }
                out.append(mathAttachment(for: mathSpans[index], attributes: attributes))
            }
        }
        return out
    }

    /// A formula, or its source in monospace when it will not parse. A viewer
    /// must never silently swallow something it cannot draw.
    private func mathAttachment(for span: MathSpan,
                                attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let attachment = MathTextAttachment(latex: span.latex, isDisplay: span.isDisplay,
                                            theme: theme, rendering: attachmentRendering)
        if attachment.failed {
            var fallback = attributes
            fallback[.font] = theme.monoFont
            fallback[.foregroundColor] = theme.secondaryTextColor
            fallback[.backgroundColor] = theme.codeBackground
            return NSAttributedString(string: span.latex, attributes: fallback)
        }
        let out = NSMutableAttributedString(attachment: attachment)
        let full = NSRange(location: 0, length: out.length)
        out.addAttributes(attributes, range: full)
        // VoiceOver sees a drawn formula as nothing at all; the source is the label.
        out.addAttribute(.spokenDescription, value: span.latex, range: full)
        out.addAttribute(.toolTip, value: span.latex, range: full)
        return out
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> NSAttributedString {
        applyTrait(.italic, to: joined(emphasis.children))
    }

    mutating func visitStrong(_ strong: Strong) -> NSAttributedString {
        applyTrait(.bold, to: joined(strong.children))
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: joined(strikethrough.children))
        out.addAttributes([
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: theme.secondaryTextColor
        ], range: NSRange(location: 0, length: out.length))
        return out
    }

    private func applyTrait(_ trait: NSFontDescriptor.SymbolicTraits,
                            to string: NSAttributedString) -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: string)
        let full = NSRange(location: 0, length: out.length)
        out.enumerateAttribute(.font, in: full) { value, range, _ in
            let current = (value as? NSFont) ?? theme.bodyFont
            var traits = current.fontDescriptor.symbolicTraits
            traits.insert(trait)
            let descriptor = current.fontDescriptor.withSymbolicTraits(traits)
            if let font = NSFont(descriptor: descriptor, size: current.pointSize) {
                out.addAttribute(.font, value: font, range: range)
            }
        }
        return out
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> NSAttributedString {
        var attrs = baseAttributes(for: inlineCode)
        attrs[.font] = theme.monoFont
        attrs[.backgroundColor] = theme.codeBackground
        attrs[.foregroundColor] = theme.textColor
        return NSAttributedString(string: inlineCode.code, attributes: attrs)
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> NSAttributedString {
        var attrs = baseAttributes(for: inlineHTML)
        attrs[.foregroundColor] = theme.secondaryTextColor
        attrs[.font] = theme.monoFont
        return NSAttributedString(string: inlineHTML.rawHTML, attributes: attrs)
    }

    mutating func visitLink(_ link: Link) -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: joined(link.children))
        let full = NSRange(location: 0, length: out.length)
        if let destination = link.destination, let url = resolve(destination) {
            out.addAttributes([
                .link: url,
                .foregroundColor: theme.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: theme.linkColor.withAlphaComponent(0.4)
            ], range: full)
        }
        return out
    }

    private func resolve(_ destination: String) -> URL? {
        if let url = URL(string: destination), url.scheme != nil { return url }
        if destination.hasPrefix("#") { return URL(string: destination) }
        guard let baseURL else { return URL(string: destination) }
        return URL(fileURLWithPath: destination, relativeTo: baseURL.deletingLastPathComponent())
    }

    mutating func visitImage(_ image: Image) -> NSAttributedString {
        guard let source = image.source, let url = resolve(source) else {
            return NSAttributedString(string: image.plainText, attributes: baseAttributes(for: image))
        }
        let attachment = ImageTextAttachment(url: url, theme: theme,
                                             altText: image.plainText)
        let out = NSMutableAttributedString(attachment: attachment)
        out.addAttributes([
            .sourceOffset: sourceOffset(of: image),
            .paragraphStyle: paragraphStyle(spacingBefore: 6, spacingAfter: 10)
        ], range: NSRange(location: 0, length: out.length))
        return out
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> NSAttributedString {
        NSAttributedString(string: " ", attributes: baseAttributes(for: softBreak))
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: baseAttributes(for: lineBreak))
    }

    // MARK: Helpers

    private func newline(after markup: Markup) -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: [
            .font: theme.bodyFont,
            .sourceOffset: sourceOffset(of: markup),
            .paragraphStyle: paragraphStyle()
        ])
    }
}


extension NSMutableAttributedString {
    /// Applies an attribute only where it is not already present, so an outer
    /// container never overwrites what a nested one recorded.
    func fillMissing(_ key: NSAttributedString.Key, value: Any, in range: NSRange) {
        var gaps: [NSRange] = []
        enumerateAttribute(key, in: range) { existing, subrange, _ in
            if existing == nil { gaps.append(subrange) }
        }
        for gap in gaps { addAttribute(key, value: value, range: gap) }
    }
}
