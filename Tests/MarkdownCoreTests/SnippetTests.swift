import Foundation
import Testing
@testable import MarkdownCore

@Suite("Snippets")
struct SnippetTests {
    private let base = URL(fileURLWithPath: "/notes/doc.md")

    /// A fake filesystem, so these never touch the disk and never need the
    /// sandbox to have granted anything.
    private func reader(_ files: [String: String]) -> (URL) -> String? {
        { url in files[url.lastPathComponent] }
    }

    private func expand(_ source: String, _ files: [String: String] = [:]) -> SnippetResolver.Resolved {
        SnippetResolver.expand(source: source, baseURL: base, read: reader(files))
    }

    // MARK: Recognising directives

    @Test func readsAllThreeSpellings() {
        #expect(SnippetDirective.parse(line: "![[install.md]]")?.path == "install.md")
        #expect(SnippetDirective.parse(line: "@Snippet(install.md)")?.path == "install.md")
        #expect(SnippetDirective.parse(line: "--8<-- \"install.md\"")?.path == "install.md")
    }

    @Test func readsAHeadingAnchor() {
        let directive = SnippetDirective.parse(line: "![[guide.md#Getting Started]]")
        #expect(directive?.path == "guide.md")
        #expect(directive?.heading == "Getting Started")
        #expect(SnippetDirective.parse(line: "@Snippet(guide.md#Ziel)")?.heading == "Ziel")
    }

    @Test func keepsTheIndentSoASnippetStaysInsideItsList() {
        #expect(SnippetDirective.parse(line: "    ![[install.md]]")?.indent == "    ")
    }

    /// Inline, this syntax is far more likely to be someone writing *about* it.
    @Test func ignoresDirectivesThatAreNotOnTheirOwnLine() {
        #expect(SnippetDirective.parse(line: "Write ![[file.md]] to include a file.") == nil)
        #expect(SnippetDirective.parse(line: "The `@Snippet(x.md)` form also works.") == nil)
    }

    @Test func ignoresOrdinaryMarkdown() {
        #expect(SnippetDirective.parse(line: "![alt](image.png)") == nil)
        #expect(SnippetDirective.parse(line: "# Heading") == nil)
        #expect(SnippetDirective.parse(line: "") == nil)
        #expect(SnippetDirective.parse(line: "--8<-- install.md") == nil, "MkDocs quotes the path")
    }

    // MARK: Expanding

    @Test func pullsInTheFile() {
        let result = expand("# Doc\n\n![[install.md]]\n\nAfter.\n",
                            ["install.md": "Run `make install`."])
        #expect(result.text == "# Doc\n\nRun `make install`.\n\nAfter.\n")
        #expect(result.referenced.map(\.lastPathComponent) == ["install.md"])
        #expect(result.hasDirectives)
    }

    @Test func pullsInOneSection() {
        let guide = "# Guide\n\n## Setup\n\nStep one.\n\n## Teardown\n\nStep two.\n"
        let result = expand("![[guide.md#Setup]]\n", ["guide.md": guide])
        #expect(result.text.contains("Step one."))
        #expect(!result.text.contains("Step two."))
        #expect(!result.text.contains("## Teardown"))
    }

    @Test func nestsSnippets() {
        let result = expand("![[a.md]]\n", ["a.md": "A then:\n\n![[b.md]]\n", "b.md": "B."])
        #expect(result.text.contains("A then:"))
        #expect(result.text.contains("B."))
    }

    @Test func reindentsASnippetInsideAList() {
        let result = expand("- Steps:\n\n  ![[steps.md]]\n", ["steps.md": "1. First\n2. Second"])
        #expect(result.text.contains("  1. First"))
        #expect(result.text.contains("  2. Second"))
    }

    @Test func aDocumentWithNoDirectivesIsUntouched() {
        let source = "# Title\n\nJust prose, with an ![image](x.png).\n"
        let result = expand(source)
        #expect(result.text == source)
        #expect(!result.hasDirectives)
        #expect(!SnippetResolver.containsDirectives(source))
    }

    // MARK: Refusing

    @Test func aMissingFileSaysSoInsteadOfVanishing() {
        let result = expand("![[gone.md]]\n")
        #expect(result.text.contains("[!WARNING]"))
        #expect(result.text.contains("`gone.md`"))
        #expect(result.text.contains("could not be read"))
    }

    @Test func aFileThatIncludesItselfIsRefused() {
        let result = expand("![[doc.md]]\n", ["doc.md": "anything"])
        #expect(result.text.contains("includes itself"))
    }

    @Test func aLoopBetweenTwoFilesIsRefused() {
        let result = expand("![[a.md]]\n", ["a.md": "![[b.md]]", "b.md": "![[a.md]]"])
        #expect(result.text.contains("includes itself"))
    }

    /// A viewer must not become a way to read the disk because someone sent you
    /// a document.
    @Test func pathsOutsideTheDocumentsFolderAreRefused() {
        for path in ["/etc/passwd", "../../secrets.md", "~/.ssh/id_rsa"] {
            // A sentinel that cannot appear in the warning, which quotes the
            // path back and would otherwise match on the filename itself.
            let result = expand("![[\(path)]]\n", [(path as NSString).lastPathComponent: "LEAKED"])
            #expect(result.text.contains("outside this document's folder"),
                    "\(path) should have been refused")
            #expect(!result.text.contains("LEAKED"), "\(path) was read anyway")
        }
    }

    @Test func aMissingHeadingSaysSo() {
        let result = expand("![[guide.md#Nowhere]]\n", ["guide.md": "# Guide\n\nBody.\n"])
        #expect(result.text.contains("has no heading"))
    }

    @Test func anUnsavedDocumentCannotResolveRelativePaths() {
        let result = SnippetResolver.expand(source: "![[x.md]]\n", baseURL: nil,
                                            read: { _ in "content" })
        #expect(result.text.contains("has not been saved"))
    }

    // MARK: The offset map

    @Test func textOutsideASnippetMapsToItself() {
        let source = "# Doc\n\n![[install.md]]\n\nAfter.\n"
        let result = expand(source, ["install.md": "Included."])
        let map = result.map

        // "# Doc" is before the directive, so it maps one to one.
        #expect(map.originalOffset(for: 0) == 0)
        #expect(map.originalOffset(for: 3) == 3)

        // "After." comes after a substitution that changed the text's length,
        // so its expanded offset differs from its original one.
        let expandedAfter = result.text.utf8Offset(of: "After.")
        let originalAfter = source.utf8Offset(of: "After.")
        #expect(expandedAfter != originalAfter, "the fixture must exercise the shift")
        #expect(map.originalOffset(for: expandedAfter) == originalAfter)
    }

    /// Included text has no position in this file, so all of it answers to the
    /// directive's line. That is what makes double-click-to-source land
    /// somewhere real.
    @Test func includedTextMapsToTheDirective() {
        let source = "# Doc\n\n![[install.md]]\n\nAfter.\n"
        let result = expand(source, ["install.md": "Line one.\nLine two."])
        let directive = source.utf8Offset(of: "![[install.md]]")

        for needle in ["Line one.", "Line two."] {
            let offset = result.text.utf8Offset(of: needle)
            #expect(result.map.originalOffset(for: offset) == directive,
                    "\(needle) should map back to the directive")
        }
    }

    @Test func theMapSurvivesNonASCIIText() {
        let source = "# Überschrift — eins\n\n![[teil.md]]\n\nSchluss — Ende.\n"
        let result = expand(source, ["teil.md": "Ein Absatz mit «Zitat»."])
        let expanded = result.text.utf8Offset(of: "Schluss")
        #expect(result.map.originalOffset(for: expanded) == source.utf8Offset(of: "Schluss"))
    }

    @Test func theIdentityMapIsTheIdentity() {
        #expect(SourceMap.identity.originalOffset(for: 0) == 0)
        #expect(SourceMap.identity.originalOffset(for: 1234) == 1234)
    }

    // MARK: Through the renderer

    /// The seam that matters: after expansion the renderer parses one string
    /// and reports offsets into another. Every position it hands out has to
    /// land in the file on disk, or bookmarks, source mode and ticking a
    /// checkbox all address the wrong place.
    @Test func renderedOffsetsPointIntoTheOriginalFile() {
        let original = """
        # Überschrift — mit Sonderzeichen

        ![[teil.md]]

        - [ ] Eine Aufgabe nach dem Snippet
        """
        let resolved = SnippetResolver.expand(source: original, baseURL: base,
                                              read: reader(["teil.md": "Ein längerer Absatz,\nüber zwei Zeilen."]))
        let document = DocumentRenderer(theme: .system)
            .render(expanded: resolved.text, original: original, map: resolved.map)

        // The document reports the file, not the expanded text.
        #expect(document.source == original)

        let bytes = Array(original.utf8)
        var checked = 0
        document.attributedString.enumerateAttribute(
            .sourceOffset, in: NSRange(location: 0, length: document.attributedString.length)
        ) { value, _, _ in
            guard let offset = value as? Int else { return }
            #expect(offset >= 0 && offset <= bytes.count,
                    "offset \(offset) is outside the \(bytes.count)-byte original")
            checked += 1
        }
        #expect(checked > 3)

        // The task after the snippet still resolves to its own line, which is
        // what ticking its checkbox depends on.
        let text = document.attributedString.string as NSString
        let task = text.range(of: "Eine Aufgabe nach dem Snippet")
        let offset = document.attributedString.attribute(.sourceOffset, at: task.location,
                                                         effectiveRange: nil) as? Int
        #expect(SourceOffset.line(atByte: offset ?? -1, in: original)
            == "- [ ] Eine Aufgabe nach dem Snippet")
    }

    /// Included content has no line of its own in this file, so it answers to
    /// the directive. Double-clicking it lands on the `![[…]]`.
    @Test func includedContentResolvesToTheDirectiveLine() {
        let original = "# Doc\n\n![[teil.md]]\n\nAfter.\n"
        let resolved = SnippetResolver.expand(source: original, baseURL: base,
                                              read: reader(["teil.md": "Included sentence."]))
        let document = DocumentRenderer(theme: .system)
            .render(expanded: resolved.text, original: original, map: resolved.map)

        let text = document.attributedString.string as NSString
        let included = text.range(of: "Included sentence.")
        #expect(included.location != NSNotFound, "the snippet must actually be rendered")
        let offset = document.attributedString.attribute(.sourceOffset, at: included.location,
                                                         effectiveRange: nil) as? Int
        #expect(SourceOffset.line(atByte: offset ?? -1, in: original) == "![[teil.md]]")
    }

    @Test func aWarningRendersAsAnAlertRatherThanVanishing() {
        let resolved = SnippetResolver.expand(source: "![[gone.md]]\n", baseURL: base,
                                              read: { _ in nil })
        let document = DocumentRenderer(theme: .system)
            .render(expanded: resolved.text, original: "![[gone.md]]\n", map: resolved.map)
        #expect(document.attributedString.string.contains("gone.md"))
        var sawAlert = false
        document.attributedString.enumerateAttribute(
            .alertKind, in: NSRange(location: 0, length: document.attributedString.length)
        ) { value, _, _ in if value != nil { sawAlert = true } }
        #expect(sawAlert, "a failed snippet should read as a warning, not as body text")
    }
}

private extension String {
    /// UTF-8 byte offset of a substring, for tests that speak the same unit as
    /// everything else here.
    func utf8Offset(of needle: String) -> Int {
        guard let range = range(of: needle) else { return -1 }
        return utf8.distance(from: utf8.startIndex, to: range.lowerBound.samePosition(in: utf8)!)
    }
}
