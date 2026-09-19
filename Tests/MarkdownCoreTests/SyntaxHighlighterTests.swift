import AppKit
import Testing
@testable import MarkdownCore

@Suite("SyntaxHighlighter")
struct SyntaxHighlighterTests {
    private func colour(_ s: NSAttributedString, at i: Int) -> NSColor? {
        s.attribute(.foregroundColor, at: i, effectiveRange: nil) as? NSColor
    }

    @Test func highlightsSwiftKeywordsDifferentlyFromIdentifiers() {
        let out = SyntaxHighlighter.highlight("let x = 1", language: "swift", theme: .system)
        #expect(colour(out, at: 0) != colour(out, at: 4))
    }

    @Test func unknownLanguageReturnsPlainMonospace() {
        let out = SyntaxHighlighter.highlight("???", language: "brainfuck", theme: .system)
        #expect(out.string == "???")
        let font = out.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.isFixedPitch == true)
    }

    @Test func nilLanguageIsSafe() {
        let out = SyntaxHighlighter.highlight("anything", language: nil, theme: .system)
        #expect(out.string == "anything")
    }

    @Test func doesNotHighlightKeywordInsideString() {
        // "let" at 0 is a keyword; "let" inside the string at 9 must not be.
        let out = SyntaxHighlighter.highlight("let s = \"let\"", language: "swift", theme: .system)
        #expect(colour(out, at: 0) != colour(out, at: 9))
    }

    @Test func doesNotHighlightKeywordInsideComment() {
        let out = SyntaxHighlighter.highlight("// let x\nlet y = 1", language: "swift", theme: .system)
        #expect(colour(out, at: 3) == Theme.system.codeCommentColor)
    }

    @Test func handlesLanguageAliases() {
        for alias in ["js", "javascript", "JS", "jsx"] {
            let out = SyntaxHighlighter.highlight("const x = 1", language: alias, theme: .system)
            #expect(out.string == "const x = 1")
            #expect(colour(out, at: 0) == Theme.system.codeKeywordColor)
        }
    }

    @Test func preservesTextWithMultibyteCharacters() {
        let code = "# 日本語 comment\nx = \"🎉\""
        let out = SyntaxHighlighter.highlight(code, language: "python", theme: .system)
        #expect(out.string == code)
    }

    @Test func unterminatedStringDoesNotRunAway() {
        let out = SyntaxHighlighter.highlight("let s = \"oops\nlet t = 1", language: "swift", theme: .system)
        #expect(out.string.contains("let t = 1"))
    }

    @Test func handlesEveryDeclaredLanguageWithoutCrashing() {
        let samples = ["swift", "python", "js", "ts", "go", "rust", "c", "cpp", "java",
                       "bash", "sql", "json", "yaml", "css", "html"]
        for lang in samples {
            let out = SyntaxHighlighter.highlight("a b \"c\" 42 // d", language: lang, theme: .system)
            #expect(out.length > 0)
        }
    }
}

@Suite("SyntaxHighlighter case sensitivity")
struct SyntaxHighlighterCaseTests {
    private func colour(_ s: NSAttributedString, at i: Int) -> NSColor? {
        s.attribute(.foregroundColor, at: i, effectiveRange: nil) as? NSColor
    }

    @Test func sqlKeywordsMatchInEitherCase() {
        for sql in ["SELECT a FROM t", "select a from t"] {
            let out = SyntaxHighlighter.highlight(sql, language: "sql", theme: .system)
            #expect(colour(out, at: 0) == Theme.system.codeKeywordColor)
        }
    }

    @Test func swiftKeywordsStayCaseSensitive() {
        let out = SyntaxHighlighter.highlight("LET x = 1", language: "swift", theme: .system)
        #expect(colour(out, at: 0) != Theme.system.codeKeywordColor)
    }
}
