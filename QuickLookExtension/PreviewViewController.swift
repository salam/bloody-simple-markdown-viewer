import AppKit
import MarkdownCore
import QuickLookUI

/// Renders Markdown in Finder's Quick Look, the preview pane, gallery view,
/// Spotlight results and Open panels.
///
/// This is the closest achievable thing to the original goal of teaching
/// Preview.app to show Markdown. Preview cannot be extended: its document types
/// are a fixed list in its own Info.plist, it has no PlugIns directory, and it
/// consumes no extension point. A Quick Look extension serves every other
/// system preview surface.
final class PreviewViewController: NSViewController, QLPreviewingController {
    private var scrollView: MarkdownScrollView!

    /// Previews are meant to be immediate. Very large files are rendered only
    /// up to this many bytes, with a note, rather than making Finder wait.
    private static let previewByteLimit = 512 * 1024

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scrollView = MarkdownScrollView(theme: .system)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        view = container
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        var truncated = false
        var slice = data
        if data.count > Self.previewByteLimit {
            slice = data.prefix(Self.previewByteLimit)
            truncated = true
        }

        guard var source = String(data: slice, encoding: .utf8)
            ?? String(data: slice, encoding: .isoLatin1) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if truncated {
            // Cut at the last complete line so a half-written construct does
            // not produce nonsense.
            if let lastBreak = source.lastIndex(of: "\n") {
                source = String(source[source.startIndex..<lastBreak])
            }
            source += "\n\n---\n\n*Preview truncated. Open the file to see all of it.*\n"
        }

        var theme = Theme.system
        theme.isDarkBackground =
            view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua

        let rendered = DocumentRenderer(theme: theme, baseURL: url).render(source: source)
        await MainActor.run {
            scrollView.markdownTextView.theme = theme
            scrollView.markdownTextView.display(rendered)
        }
    }
}
