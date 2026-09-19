import AppKit
import Testing
@testable import MarkdownCore

/// Layout-level tests, measuring where glyphs actually land rather than what
/// the attributed string claims.
///
/// These exist because the attributed string can carry perfectly correct
/// indentation that TextKit then ignores. Setting `NSParagraphStyle.textLists`
/// made TextKit 2 substitute its own automatic list indentation, putting every
/// marker in the same column no matter how deeply nested, while the model still
/// reported the right values. Only a real layout catches that.
@MainActor
@Suite("List layout")
struct ListLayoutTests {
    private func positions(_ source: String, of needles: [String]) -> [(marker: CGFloat, text: CGFloat)] {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 900))
        view.textContainerInset = .zero
        view.textContainer?.size = CGSize(width: 700, height: CGFloat.greatestFiniteMagnitude)
        let doc = DocumentRenderer(theme: .system).render(source: source)
        view.display(doc)
        guard let lm = view.textLayoutManager, let cm = lm.textContentManager else { return [] }
        lm.ensureLayout(for: lm.documentRange)

        func x(at index: Int) -> CGFloat {
            guard index >= 0,
                  let loc = cm.location(cm.documentRange.location, offsetBy: index),
                  let end = cm.location(loc, offsetBy: 1),
                  let range = NSTextRange(location: loc, end: end) else { return -1 }
            var result: CGFloat = -1
            lm.enumerateTextSegments(in: range, type: .standard) { _, frame, _, _ in
                result = frame.origin.x
                return false
            }
            return result
        }

        let ns = doc.attributedString.string as NSString
        return needles.map { needle in
            let r = ns.range(of: needle)
            guard r.location != NSNotFound else { return (-1, -1) }
            return (x(at: r.location - 2), x(at: r.location))
        }
    }

    @Test func markersStepRightWithEachNestingLevel() {
        let p = positions("""
        - level one
          - level two
            - level three
        """, of: ["level one", "level two", "level three"])
        #expect(p.count == 3)
        #expect(p[1].marker > p[0].marker)
        #expect(p[2].marker > p[1].marker)
        // Evenly stepped, not merely increasing.
        let firstStep = p[1].marker - p[0].marker
        let secondStep = p[2].marker - p[1].marker
        #expect(abs(firstStep - secondStep) < 1)
    }

    @Test func textStepsRightWithEachNestingLevel() {
        let p = positions("""
        - level one
          - level two
            - level three
        """, of: ["level one", "level two", "level three"])
        #expect(p[1].text > p[0].text)
        #expect(p[2].text > p[1].text)
    }

    @Test func textAlwaysSitsRightOfItsMarker() {
        let p = positions("""
        - level one
          - level two
        """, of: ["level one", "level two"])
        for entry in p { #expect(entry.text > entry.marker) }
    }

    /// Every item in one list starts its text in the same column, whatever the
    /// width of its marker.
    @Test func orderedItemsShareOneTextColumn() {
        let p = positions("1. first\n2. second\n10. tenth\n", of: ["first", "second", "tenth"])
        #expect(p[0].text == p[1].text)
        #expect(p[1].text == p[2].text)
    }

    @Test func taskListItemsShareOneTextColumn() {
        let p = positions("- [x] done\n- [ ] todo\n", of: ["done", "todo"])
        #expect(p[0].text == p[1].text)
    }
}
