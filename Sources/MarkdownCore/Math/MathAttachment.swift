import AppKit
import SwaTex
import SwaTexRender

/// A rendered LaTeX formula.
///
/// Inline formulas become a rasterised image whose bounds are offset by the
/// formula's depth, so it sits on the surrounding text's baseline instead of
/// floating. Display formulas host a `SwaTexView`, which resizes crisply.
///
/// The LaTeX source is attached as the accessibility description: a drawn
/// formula is otherwise completely invisible to VoiceOver, which is the one
/// real thing this approach gives up against MathJax.
public final class MathTextAttachment: NSTextAttachment {
    public let latex: String
    public let isDisplay: Bool
    public let theme: Theme
    /// Set when the formula could not be parsed, so the host can fall back to
    /// showing the source rather than a blank space.
    public private(set) var failed = false

    /// Formulas are clamped before rasterising. A pathological `\rule` can
    /// otherwise produce a display list millions of points wide.
    private static let maxDimension: CGFloat = 4000

    public init(latex: String, isDisplay: Bool, theme: Theme) {
        // `\operatorname*` renders in math italic instead of upright roman,
        // a known upstream defect. Rewriting to the unstarred form is correct
        // for everything except limit placement, which is a fair trade.
        self.latex = latex.replacingOccurrences(of: "\\operatorname*", with: "\\operatorname")
        self.isDisplay = isDisplay
        self.theme = theme
        super.init(data: nil, ofType: nil)
        allowsTextAttachmentView = isDisplay
        render()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func render() {
        let fontSize = isDisplay ? theme.baseFontSize + 3 : theme.baseFontSize
        // No padding: the formula must sit in the text flow, not in a box.
        let options = RenderOptions(fontSize: fontSize, padding: isDisplay ? 2 : 0)

        guard let list = try? SwaTexEngine.displayList(
            for: latex,
            style: isDisplay ? .display : .text,
            color: theme.textColor.swaTexColor
        ) else {
            failed = true
            bounds = .zero
            return
        }

        let metrics = DisplayListRenderer.metrics(for: list, options: options)
        guard metrics.width.isFinite, metrics.height.isFinite,
              metrics.width > 0, metrics.height > 0,
              metrics.width < Self.maxDimension, metrics.height < Self.maxDimension else {
            failed = true
            bounds = .zero
            return
        }

        if isDisplay {
            bounds = CGRect(x: 0, y: 0, width: metrics.width, height: metrics.height)
        } else {
            guard let cgImage = ImageRenderer.image(for: list, options: options) else {
                failed = true
                bounds = .zero
                return
            }
            image = NSImage(cgImage: cgImage, size: NSSize(width: metrics.width, height: metrics.height))
            // Sit on the surrounding baseline rather than floating above it.
            let depth = metrics.height - metrics.baseline
            bounds = CGRect(x: 0, y: -depth, width: metrics.width, height: metrics.height)
        }
    }

    public override func viewProvider(for parentView: NSView?,
                                      location: any NSTextLocation,
                                      textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? {
        guard isDisplay, !failed else { return nil }
        let provider = MathViewProvider(
            textAttachment: self,
            parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager,
            location: location
        )
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }
}

public final class MathViewProvider: NSTextAttachmentViewProvider {
    public override func loadView() {
        guard let attachment = textAttachment as? MathTextAttachment else {
            view = NSView()
            return
        }
        let mathView = SwaTexView()
        mathView.latex = attachment.latex
        mathView.fontSize = attachment.theme.baseFontSize + 3
        mathView.mathStyle = .display
        // A dynamic NSColor keeps the formula legible when the appearance changes.
        mathView.color = attachment.theme.textColor
        mathView.frame = CGRect(origin: .zero, size: attachment.bounds.size)
        mathView.setAccessibilityLabel(attachment.latex)
        view = mathView
    }

    public override func attachmentBounds(for attributes: [NSAttributedString.Key: Any],
                                          location: any NSTextLocation,
                                          textContainer: NSTextContainer?,
                                          proposedLineFragment: CGRect,
                                          position: CGPoint) -> CGRect {
        guard let attachment = textAttachment as? MathTextAttachment else { return .zero }
        return CGRect(origin: .zero, size: attachment.bounds.size)
    }
}

private extension NSColor {
    /// Resolves a dynamic AppKit colour into the engine's own colour type.
    var swaTexColor: SwaTex.Color {
        let rgb = usingColorSpace(.deviceRGB) ?? .black
        return SwaTex.Color(r: Float(rgb.redComponent),
                            g: Float(rgb.greenComponent),
                            b: Float(rgb.blueComponent),
                            a: Float(rgb.alphaComponent))
    }
}
