import Foundation
import Testing
@testable import MarkdownCore

@Suite("MathExtractor")
struct MathExtractorTests {
    @Test func extractsInlineDollarMath() {
        let result = MathExtractor.extract(from: "Einstein said $E = mc^2$ once.")
        #expect(result.spans.count == 1)
        #expect(result.spans[0].latex == "E = mc^2")
        #expect(result.spans[0].isDisplay == false)
        #expect(!result.text.contains("$"))
    }

    @Test func extractsDisplayDollarMath() {
        let result = MathExtractor.extract(from: "$$\\int_0^\\infty e^{-x^2}dx$$")
        #expect(result.spans.count == 1)
        #expect(result.spans[0].isDisplay)
    }

    @Test func extractsGitHubBacktickForm() {
        let result = MathExtractor.extract(from: "inline $`a + b`$ here")
        #expect(result.spans.count == 1)
        #expect(result.spans[0].latex == "a + b")
    }

    /// ChatGPT commonly emits these instead of dollar signs.
    @Test func extractsBackslashDelimiters() {
        let inline = MathExtractor.extract(from: "value \\(x^2\\) here")
        #expect(inline.spans.count == 1)
        #expect(inline.spans[0].latex == "x^2")
        #expect(inline.spans[0].isDisplay == false)

        let display = MathExtractor.extract(from: "\\[\\frac{a}{b}\\]")
        #expect(display.spans.count == 1)
        #expect(display.spans[0].isDisplay)
    }

    /// The reason extraction must happen before parsing: cmark would turn the
    /// two underscores into emphasis and corrupt the formula.
    @Test func protectsUnderscoresFromEmphasis() {
        let source = "$a_i b_j$"
        let result = MathExtractor.extract(from: source)
        #expect(result.spans[0].latex == "a_i b_j")
        let doc = DocumentRenderer(theme: .system).render(source: source)
        // The rendered output must not contain a stray italic run from "_i b_".
        #expect(!doc.attributedString.string.contains("_"))
    }

    @Test func leavesCurrencyAlone() {
        for prose in ["costs $5 and $6 today", "a $ b", "price: $ 100"] {
            let result = MathExtractor.extract(from: prose)
            #expect(result.spans.isEmpty, "treated \(prose) as math")
        }
    }

    @Test func respectsEscapedDollars() {
        let result = MathExtractor.extract(from: "\\$100 and \\$200")
        #expect(result.spans.isEmpty)
    }

    @Test func handlesSeveralFormulasInOneLine() {
        let result = MathExtractor.extract(from: "$a$ then $b$ then $c$")
        #expect(result.spans.count == 3)
        #expect(result.spans.map(\.latex) == ["a", "b", "c"])
    }

    @Test func unterminatedDelimiterIsLeftAsText() {
        let result = MathExtractor.extract(from: "an unclosed $formula here")
        #expect(result.spans.isEmpty)
        #expect(result.text.contains("$formula here"))
    }

    @Test func splitsPlaceholdersBackOut() {
        let result = MathExtractor.extract(from: "before $x$ after")
        let pieces = MathExtractor.split(result.text)
        #expect(pieces == [.text("before "), .math(0), .text(" after")])
    }

    @Test func splitReturnsPlainTextUntouched() {
        #expect(MathExtractor.split("no math here") == [.text("no math here")])
        #expect(MathExtractor.split("").isEmpty)
    }

    @Test func recordsSourceOffsets() {
        let result = MathExtractor.extract(from: "0123456789 $x$")
        #expect(result.spans[0].sourceOffset == 11)
    }
}
