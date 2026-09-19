import AppKit
import Mermaid

/// A rendered Mermaid diagram.
///
/// On screen the diagram hosts a view that redraws at the window's backing
/// scale, so it stays sharp when moved between displays. For print it becomes a
/// PDF-backed image, which stays vector on the page.
///
/// When the library cannot draw a diagram, which covers gantt, mindmap,
/// timeline and the rest of the long tail, `failed` is set and the caller shows
/// the diagram source instead. Nothing in the document is ever silently lost.
public final class MermaidTextAttachment: NSTextAttachment {
    public let source: String
    public let theme: Theme
    public let rendering: AttachmentRendering
    public private(set) var failed = false
    public private(set) var failureReason: String?

    private var scene: MermaidScene?

    /// Diagrams are scaled down to fit the reading column rather than running
    /// off the side of the page.
    private static let maxWidth: CGFloat = 660
    private static let maxHeight: CGFloat = 2400

    public init(source: String, theme: Theme, rendering: AttachmentRendering = .interactive) {
        self.source = source
        self.theme = theme
        self.rendering = rendering
        super.init(data: nil, ofType: nil)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func build() {
        do {
            let scene = try MermaidRenderer.scene(from: source, darkMode: theme.isDarkBackground)
            self.scene = scene

            let natural = scene.size
            let scale = min(1, Self.maxWidth / natural.width)
            let size = CGSize(width: (natural.width * scale).rounded(),
                              height: min((natural.height * scale).rounded(), Self.maxHeight))
            bounds = CGRect(origin: .zero, size: size)

            if rendering == .flattened {
                // PDF data keeps the diagram vector on the printed page.
                let data = scene.pdfData()
                image = NSImage(data: data)
                image?.size = size
            } else {
                allowsTextAttachmentView = true
            }
        } catch {
            failed = true
            failureReason = Self.describe(error)
            bounds = .zero
        }
    }

    private static func describe(_ error: any Error) -> String {
        guard let failure = error as? MermaidRenderer.Failure else { return "\(error)" }
        switch failure {
        case .unsupportedType(let type): return "\(type) diagrams are not supported yet"
        case .invalidSyntax(let detail): return detail
        case .wouldCrash(let reason): return reason
        case .empty: return "the diagram is empty"
        }
    }

    public override func viewProvider(for parentView: NSView?,
                                      location: any NSTextLocation,
                                      textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? {
        guard rendering == .interactive, !failed, scene != nil else { return nil }
        let provider = MermaidViewProvider(
            textAttachment: self,
            parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager,
            location: location
        )
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }

    func makeDiagramView() -> NSView {
        guard let scene else { return NSView() }
        let view = MermaidDiagramView(scene: scene)
        view.frame = CGRect(origin: .zero, size: bounds.size)
        return view
    }
}

public final class MermaidViewProvider: NSTextAttachmentViewProvider {
    public override func loadView() {
        guard let attachment = textAttachment as? MermaidTextAttachment else {
            view = NSView()
            return
        }
        view = attachment.makeDiagramView()
    }

    public override func attachmentBounds(for attributes: [NSAttributedString.Key: Any],
                                          location: any NSTextLocation,
                                          textContainer: NSTextContainer?,
                                          proposedLineFragment: CGRect,
                                          position: CGPoint) -> CGRect {
        guard let attachment = textAttachment as? MermaidTextAttachment else { return .zero }
        return CGRect(origin: .zero, size: attachment.bounds.size)
    }
}

/// Draws the diagram, re-rasterising when the backing scale changes so it stays
/// sharp if the window moves to a different display.
final class MermaidDiagramView: NSView {
    private let scene: MermaidScene
    private var cached: CGImage?
    private var cachedScale: CGFloat = 0

    init(scene: MermaidScene) {
        self.scene = scene
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        cached = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = window?.backingScaleFactor ?? 2
        if cached == nil || cachedScale != scale {
            // Rasterise at the natural size times the backing scale, then draw
            // it into whatever box the text has given us.
            let renderScale = scale * (bounds.width / max(scene.size.width, 1))
            cached = scene.cgImage(scale: max(renderScale, 0.1))
            cachedScale = scale
        }
        guard let image = cached else { return }
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(image, in: bounds)
        context.restoreGState()
    }
}
