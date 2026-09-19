import AppKit
import Testing
@testable import MarkdownCore

@Suite("Math rendering")
struct MathRenderingTests {
    private func render(_ src: String) -> RenderedDocument {
        DocumentRenderer(theme: .system).render(source: src)
    }

    private func attachments(in doc: RenderedDocument) -> [MathTextAttachment] {
        var found: [MathTextAttachment] = []
        let full = NSRange(location: 0, length: doc.attributedString.length)
        doc.attributedString.enumerateAttribute(.attachment, in: full) { value, _, _ in
            if let math = value as? MathTextAttachment { found.append(math) }
        }
        return found
    }

    @Test func rendersInlineMath() {
        let doc = render("Einstein wrote $E = mc^2$ here.")
        let math = attachments(in: doc)
        #expect(math.count == 1)
        #expect(math[0].isDisplay == false)
        #expect(math[0].failed == false)
        #expect(math[0].bounds.width > 0)
    }

    /// Inline math must sit on the surrounding baseline, not float above it.
    @Test func inlineMathIsBaselineAligned() {
        let doc = render("text $\\frac{a}{b}$ text")
        let math = attachments(in: doc)
        #expect(math.count == 1)
        #expect(math[0].bounds.origin.y < 0, "a formula with depth must be pushed below the baseline")
    }

    @Test func rendersDisplayMath() {
        let doc = render("$$\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}$$")
        let math = attachments(in: doc)
        #expect(math.count == 1)
        #expect(math[0].isDisplay)
        #expect(math[0].bounds.height > 0)
    }

    @Test func rendersFencedMathBlocks() {
        let doc = render("```math\nE = mc^2\n```\n")
        #expect(attachments(in: doc).count == 1)
    }

    @Test func rendersBackslashDelimitedMath() {
        #expect(attachments(in: render("value \\(x^2\\) here")).count == 1)
        #expect(attachments(in: render("\\[\\int_0^1 x\\,dx\\]")).count == 1)
    }

    @Test func handlesRealisticLLMMath() {
        let source = """
        The gradient step is $\\theta \\leftarrow \\theta - \\eta \\nabla_\\theta \\mathcal{L}$
        with $\\hat{y} = \\sigma(W^\\top x + b)$ over $\\mathbb{R}^{n \\times d}$.

        $$
        \\mathcal{L}(\\theta) = -\\frac{1}{N} \\sum_i \\log p_\\theta(y_i)
        $$
        """
        let math = attachments(in: render(source))
        #expect(math.count == 4)
        #expect(math.allSatisfy { !$0.failed })
    }

    /// A formula that will not parse must show its source, never vanish.
    @Test func brokenFormulaFallsBackToItsSource() {
        let doc = render("broken $\\frac{1}{$ here")
        // Either it parsed, or the source survives as visible text.
        let text = doc.attributedString.string
        #expect(text.contains("frac") || attachments(in: doc).count == 1)
    }

    @Test func doesNotTurnCurrencyIntoMath() {
        #expect(attachments(in: render("It costs $5 and $6 today.")).isEmpty)
    }

    @Test func carriesSpokenDescriptionForScreenReaders() {
        let doc = render("$E = mc^2$")
        var found: String?
        let full = NSRange(location: 0, length: doc.attributedString.length)
        doc.attributedString.enumerateAttribute(.spokenDescription, in: full) { value, _, _ in
            if let text = value as? String { found = text }
        }
        #expect(found == "E = mc^2")
    }
}

@Suite("Checkbox markers")
struct CheckboxTests {
    private func render(_ src: String) -> RenderedDocument {
        DocumentRenderer(theme: .system).render(source: src)
    }

    @Test func recognisesStandardGFMTasks() {
        let text = render("- [x] done\n- [ ] todo\n").attributedString.string
        #expect(text.contains("\u{2611}"))
        #expect(text.contains("\u{2610}"))
    }

    /// GFM defines only [ ] and [x]; these all arrive as plain text.
    @Test func recognisesExtendedCheckedMarkers() {
        for marker in ["[x]", "[X]", "[✅]", "[✔️]", "[✔]", "[☑]", "[✓]", "[OK]", "[ok]", "[DONE]", "[done]", "[y]", "[yes]"] {
            let doc = render("- \(marker) item text\n")
            let text = doc.attributedString.string
            #expect(text.contains("\u{2611}"), "\(marker) was not treated as checked")
            #expect(!text.contains(marker), "\(marker) was left in the visible text")
            #expect(text.contains("item text"))
        }
    }

    /// Started but not finished: not a GFM concept, but widely written.
    @Test func recognisesInProgressMarkers() {
        for marker in ["[~]", "[/]", "[>]", "[WIP]", "[wip]", "[doing]", "[in progress]", "[in Arbeit]"] {
            let doc = render("- \(marker) still going\n")
            let text = doc.attributedString.string
            #expect(text.contains("\u{25E7}"), "\(marker) was not treated as in progress")
            #expect(!text.contains(marker), "\(marker) was left in the visible text")
            #expect(text.contains("still going"))
        }
    }

    @Test func threeStatesAreDistinctGlyphs() {
        let text = render("- [x] done\n- [~] doing\n- [ ] todo\n").attributedString.string
        #expect(text.contains("\u{2611}"))
        #expect(text.contains("\u{25E7}"))
        #expect(text.contains("\u{2610}"))
    }

    @Test func recognisesExtendedUncheckedMarkers() {
        for marker in ["[ ]", "[]", "[-]", "[?]", "[TODO]", "[todo]", "[no]"] {
            let doc = render("- \(marker) item text\n")
            let text = doc.attributedString.string
            #expect(text.contains("\u{2610}"), "\(marker) was not treated as unchecked")
            #expect(text.contains("item text"))
        }
    }

    @Test func leavesOrdinaryBracketsAlone() {
        // A citation-style bracket is not a checkbox.
        let doc = render("- [Apple](https://apple.com) is a link\n")
        #expect(!doc.attributedString.string.contains("\u{2611}"))
        #expect(doc.attributedString.string.contains("Apple"))
    }

    @Test func unknownMarkerIsNotACheckbox() {
        let doc = render("- [maybe later] something\n")
        #expect(!doc.attributedString.string.contains("\u{2611}"))
        #expect(!doc.attributedString.string.contains("\u{2610}"))
    }

    @Test func handlesTheUsersExactList() {
        let source = """
        - [x] Some
        - [✅] Other
        - [✔️] Bullet
        - [X] Point
        - [OK] Such
        - [DONE] as those
        """
        let text = render(source).attributedString.string
        for word in ["Some", "Other", "Bullet", "Point", "Such", "as those"] {
            #expect(text.contains(word))
        }
        // Six checked boxes, no leftover bracket markers.
        #expect(text.filter { $0 == "\u{2611}" }.count == 6)
        #expect(!text.contains("["))
    }
}
