# Core Viewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A runnable, installable macOS app that is the default handler for Markdown files, renders GFM natively with no web view, and supports tabs, drag and drop, and a source/rendered toggle.

**Architecture:** A SwiftPM library (`MarkdownCore`) parses with swift-markdown and walks the resulting tree straight into an `NSAttributedString`, with an `NSTextAttachmentViewProvider` for anything TextKit 2 cannot lay out natively. An XcodeGen-generated Xcode project wraps it in an AppKit document-based app.

**Tech Stack:** Swift 6.2, AppKit, TextKit 2, swift-markdown (cmark-gfm), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-19-markdown-viewer-design.md`

## Global Constraints

- Platform floor is **macOS 15**. SwaTex requires it, and the app targets it uniformly.
- **Never read `NSTextView.layoutManager`**, directly or transitively. It silently and permanently drops the view to TextKit 1, forfeiting lazy viewport layout. A debug observer on `willSwitchToNSLayoutManager` asserts if this happens.
- **Never use `NSTextTable` / `NSTextTableBlock`.** Verified not to lay out under TextKit 2. Tables are hosted `NSGridView`s in attachments.
- **No `WKWebView`, no JavaScript engine, anywhere.** Measured at ~138 MB and three helper processes.
- Dependencies are limited to **swift-markdown, SwaTex and swift-mermaid**. Exact versions pinned via committed `Package.resolved`.
- Bundle identifier `ch.sala.BloodySimpleMarkdownViewer`; `CFBundleName` is `Markdown`; `CFBundleDisplayName` is `A Bloody Simple Markdown Viewer`. Licence MIT.
- Performance budget: cold launch to first paint under 200 ms for a 100 KB document; resident memory under 80 MB with one such document open; zero helper processes.

**Refinement of spec §3.1:** the spec described a separate document IR. Building one duplicates swift-markdown's tree for no gain, so the renderer is a `MarkupVisitor` that walks swift-markdown's own tree directly into an attributed string, collecting the outline and attachments as it goes. This is strictly less code for the same result.

---

### Task 0: Spike — confirm TextKit 2 survives a large document

Throwaway. Nothing here is kept.

**Files:** Create `/tmp/.../spike/main.swift` (scratchpad only)

- [ ] **Step 1: Generate a 10 MB Markdown file**

```bash
python3 -c "
import random
w='lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod'.split()
out=[]
for i in range(60000):
    if i%50==0: out.append('## Section %d\n'%i)
    out.append(' '.join(random.choice(w) for _ in range(40))+'\n\n')
open('/tmp/big.md','w').write(''.join(out))
"
ls -lh /tmp/big.md
```

- [ ] **Step 2: Load it into a TextKit 2 text view and time it**

Build a minimal AppKit program that creates `NSTextView(usingTextLayoutManager: true)`, loads the file as a plain attributed string, forces layout, scrolls to the end, and prints elapsed time plus whether `textLayoutManager` is still non-nil.

- [ ] **Step 3: Record the result**

Expected: opens without hanging, `textLayoutManager` stays non-nil. If it hangs, the spec's large-document strategy needs chunked parsing before Phase 1 proceeds.

---

### Task 1: Package skeleton and the byte-offset line index

**Files:**
- Create: `Package.swift`, `Sources/MarkdownCore/LineIndex.swift`
- Test: `Tests/MarkdownCoreTests/LineIndexTests.swift`

**Interfaces:**
- Produces: `LineIndex(source: String)`, `func utf8Offset(line: Int, column: Int) -> Int` — converts swift-markdown's 1-based line/column `SourceLocation` into a UTF-8 byte offset. Every later task that maps rendered text back to source uses this.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import MarkdownCore

@Test func lineIndexMapsLineAndColumnToByteOffset() {
    let index = LineIndex(source: "abc\ndefg\nhi")
    #expect(index.utf8Offset(line: 1, column: 1) == 0)
    #expect(index.utf8Offset(line: 2, column: 1) == 4)
    #expect(index.utf8Offset(line: 3, column: 2) == 10)
}

@Test func lineIndexHandlesMultibyteCharacters() {
    // "é" is 2 UTF-8 bytes, "🎉" is 4
    let index = LineIndex(source: "é🎉\nx")
    #expect(index.utf8Offset(line: 2, column: 1) == 7)
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --filter LineIndexTests`
Expected: FAIL, `LineIndex` not found.

- [ ] **Step 3: Implement**

```swift
public struct LineIndex: Sendable {
    private let lineStarts: [Int]
    private let utf8Count: Int

    public init(source: String) {
        var starts = [0]
        var offset = 0
        for byte in source.utf8 {
            offset += 1
            if byte == 0x0A { starts.append(offset) }
        }
        self.lineStarts = starts
        self.utf8Count = offset
    }

    /// swift-markdown reports 1-based line and column in UTF-8 code units.
    public func utf8Offset(line: Int, column: Int) -> Int {
        guard line >= 1, line <= lineStarts.count else { return utf8Count }
        return min(lineStarts[line - 1] + max(0, column - 1), utf8Count)
    }
}
```

- [ ] **Step 4: Run it and watch it pass**

Run: `swift test --filter LineIndexTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources Tests && git commit -m "feat: package skeleton and byte-offset line index"
```

---

### Task 2: Frontmatter stripping

**Files:**
- Create: `Sources/MarkdownCore/Frontmatter.swift`
- Test: `Tests/MarkdownCoreTests/FrontmatterTests.swift`

**Interfaces:**
- Produces: `Frontmatter.split(_ source: String) -> (frontmatter: String?, body: String, bodyLineOffset: Int)`. `bodyLineOffset` is how many lines were removed, so source ranges from the parser can be shifted back onto the original file.

- [ ] **Step 1: Write the failing test**

```swift
@Test func splitsYAMLFrontmatter() {
    let (fm, body, offset) = Frontmatter.split("---\ntitle: Hi\n---\n# Heading\n")
    #expect(fm == "title: Hi")
    #expect(body == "# Heading\n")
    #expect(offset == 3)
}

@Test func splitsTOMLFrontmatter() {
    let (fm, _, _) = Frontmatter.split("+++\ntitle = \"Hi\"\n+++\ntext\n")
    #expect(fm == "title = \"Hi\"")
}

@Test func leavesThematicBreakAlone() {
    // A --- that is not at offset 0 with a closing fence is not frontmatter
    let (fm, body, offset) = Frontmatter.split("# Heading\n\n---\n\ntext\n")
    #expect(fm == nil)
    #expect(body == "# Heading\n\n---\n\ntext\n")
    #expect(offset == 0)
}

@Test func unterminatedFenceIsNotFrontmatter() {
    let (fm, _, _) = Frontmatter.split("---\ntitle: Hi\nno closing fence\n")
    #expect(fm == nil)
}
```

- [ ] **Step 2: Run it and watch it fail.** `swift test --filter FrontmatterTests`

- [ ] **Step 3: Implement**

```swift
public enum Frontmatter {
    public static func split(_ source: String) -> (frontmatter: String?, body: String, bodyLineOffset: Int) {
        for fence in ["---", "+++"] where source.hasPrefix(fence + "\n") {
            let lines = source.components(separatedBy: "\n")
            guard let close = lines.dropFirst().firstIndex(of: fence) else { continue }
            let content = lines[1..<close].joined(separator: "\n")
            let body = lines[(close + 1)...].joined(separator: "\n")
            return (content, body, close + 1)
        }
        return (nil, source, 0)
    }
}
```

- [ ] **Step 4: Run it and watch it pass.**

- [ ] **Step 5: Commit.** `git commit -m "feat: strip YAML and TOML frontmatter"`

---

### Task 3: Theme

**Files:**
- Create: `Sources/MarkdownCore/Theme.swift`
- Test: `Tests/MarkdownCoreTests/ThemeTests.swift`

**Interfaces:**
- Produces: `struct Theme` with `bodyFont`, `monoFont`, `headingFont(level:)`, `textColor`, `secondaryTextColor`, `linkColor`, `codeBackground`, `quoteBarColor`, `alertTint(for:)`, `readingWidth`. `Theme.system` is the default. All colours are dynamic `NSColor`s so dark mode needs no second theme.

- [ ] **Step 1: Write the failing test**

```swift
@Test func headingFontsDescendInSize() {
    let t = Theme.system
    let sizes = (1...6).map { t.headingFont(level: $0).pointSize }
    #expect(sizes == sizes.sorted(by: >))
    #expect(sizes[0] > t.bodyFont.pointSize)
}

@Test func alertTintsAreDistinct() {
    let t = Theme.system
    let tints = AlertKind.allCases.map { t.alertTint(for: $0) }
    #expect(Set(tints.map(\.description)).count == AlertKind.allCases.count)
}
```

- [ ] **Step 2: Run it and watch it fail.**

- [ ] **Step 3: Implement** `Theme` plus `enum AlertKind: String, CaseIterable { case note, tip, important, warning, caution }`, using `NSFont.preferredFont(forTextStyle:)` for body and `.monospacedSystemFont` for code, and semantic colours (`.labelColor`, `.secondaryLabelColor`, `.linkColor`) so appearance changes are automatic.

- [ ] **Step 4: Run it and watch it pass.**

- [ ] **Step 5: Commit.** `git commit -m "feat: theme with dynamic colours and heading scale"`

---

### Task 4: Code syntax highlighter

**Files:**
- Create: `Sources/MarkdownCore/Highlight/SyntaxHighlighter.swift`, `Sources/MarkdownCore/Highlight/LanguageGrammar.swift`
- Test: `Tests/MarkdownCoreTests/SyntaxHighlighterTests.swift`

**Interfaces:**
- Produces: `SyntaxHighlighter.highlight(_ code: String, language: String?, theme: Theme) -> NSAttributedString`. Unknown or absent language returns plain monospace text, never an error.

Grammar covers Swift, Python, JavaScript, TypeScript, JSON, Bash, Go, Rust, C, C++, Java, SQL, HTML, CSS, YAML and Markdown, each as a keyword set plus string, comment and number rules.

- [ ] **Step 1: Write the failing test**

```swift
@Test func highlightsSwiftKeywords() {
    let out = SyntaxHighlighter.highlight("let x = 1", language: "swift", theme: .system)
    let colorAtLet = out.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    let colorAtX = out.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor
    #expect(colorAtLet != colorAtX)
}

@Test func unknownLanguageReturnsPlainMonospace() {
    let out = SyntaxHighlighter.highlight("???", language: "brainfuck", theme: .system)
    #expect(out.string == "???")
    let font = out.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    #expect(font?.isFixedPitch == true)
}

@Test func doesNotHighlightKeywordInsideString() {
    let out = SyntaxHighlighter.highlight("let s = \"let\"", language: "swift", theme: .system)
    let kw = out.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    let inString = out.attribute(.foregroundColor, at: 9, effectiveRange: nil) as? NSColor
    #expect(kw != inString)
}

@Test func handlesLanguageAliases() {
    for alias in ["js", "javascript", "JS"] {
        let out = SyntaxHighlighter.highlight("const x = 1", language: alias, theme: .system)
        #expect(out.length == 11)
    }
}
```

- [ ] **Step 2: Run it and watch it fail.**

- [ ] **Step 3: Implement** a single-pass lexer: scan for comment, string, number and identifier tokens in that priority order so a keyword inside a string is never recoloured, then look identifiers up in the grammar's keyword set.

- [ ] **Step 4: Run it and watch it pass.**

- [ ] **Step 5: Commit.** `git commit -m "feat: dependency-free syntax highlighter"`

---

### Task 5: Renderer — text, headings, inlines, outline

**Files:**
- Create: `Sources/MarkdownCore/Render/DocumentRenderer.swift`, `Sources/MarkdownCore/Render/RenderedDocument.swift`
- Test: `Tests/MarkdownCoreTests/DocumentRendererTests.swift`

**Interfaces:**
- Produces:
  - `struct RenderedDocument { let attributedString: NSAttributedString; let outline: [OutlineEntry]; let lineIndex: LineIndex }`
  - `struct OutlineEntry { let level: Int; let title: String; let anchor: String; let sourceOffset: Int; let characterOffset: Int }`
  - `DocumentRenderer(theme: Theme).render(source: String) -> RenderedDocument`
  - Custom attribute key `.sourceOffset` carrying the UTF-8 offset of every rendered run, which search, bookmarks and the source toggle all read.

- [ ] **Step 1: Write the failing test**

```swift
@Test func rendersHeadingsIntoOutlineWithAnchors() {
    let doc = DocumentRenderer(theme: .system).render(source: "# Hello World\n\ntext\n\n## Sub Section\n")
    #expect(doc.outline.count == 2)
    #expect(doc.outline[0].title == "Hello World")
    #expect(doc.outline[0].anchor == "hello-world")
    #expect(doc.outline[1].level == 2)
    #expect(doc.outline[1].anchor == "sub-section")
}

@Test func deduplicatesRepeatedAnchors() {
    let doc = DocumentRenderer(theme: .system).render(source: "# Setup\n\n# Setup\n")
    #expect(doc.outline.map(\.anchor) == ["setup", "setup-1"])
}

@Test func everyRunCarriesASourceOffset() {
    let doc = DocumentRenderer(theme: .system).render(source: "# Hi\n\nbody\n")
    var sawOffset = false
    doc.attributedString.enumerateAttribute(.sourceOffset, in: NSRange(location: 0, length: doc.attributedString.length)) { value, _, _ in
        if value != nil { sawOffset = true }
    }
    #expect(sawOffset)
}

@Test func appliesEmphasisAndStrong() {
    let doc = DocumentRenderer(theme: .system).render(source: "*a* **b**\n")
    #expect(doc.attributedString.string.contains("a"))
    #expect(doc.attributedString.string.contains("b"))
}
```

- [ ] **Step 2: Run it and watch it fail.**

- [ ] **Step 3: Implement** a `MarkupVisitor` over swift-markdown's `Document`. Anchor slugs lowercase the title, replace spaces with hyphens, strip other punctuation, and disambiguate collisions with a numeric suffix, matching GitHub's scheme, which no parser provides.

- [ ] **Step 4: Run it and watch it pass.**

- [ ] **Step 5: Commit.** `git commit -m "feat: render headings, inlines and document outline"`

---

### Task 6: Lists, task lists, thematic breaks

**Files:**
- Modify: `Sources/MarkdownCore/Render/DocumentRenderer.swift`
- Test: `Tests/MarkdownCoreTests/ListRenderingTests.swift`

Uses `NSTextList`, TextKit 2's supported list construct. Task list checkboxes are SF Symbol glyphs, not controls.

- [ ] **Step 1: Write the failing test**

```swift
@Test func rendersNestedUnorderedLists() {
    let doc = DocumentRenderer(theme: .system).render(source: "- a\n  - b\n- c\n")
    let style = doc.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    #expect(style?.textLists.isEmpty == false)
}

@Test func rendersOrderedListMarkers() {
    let doc = DocumentRenderer(theme: .system).render(source: "1. first\n2. second\n")
    #expect(doc.attributedString.string.contains("first"))
}

@Test func rendersTaskListCheckboxes() {
    let doc = DocumentRenderer(theme: .system).render(source: "- [x] done\n- [ ] todo\n")
    let text = doc.attributedString.string
    #expect(text.contains("done") && text.contains("todo"))
    #expect(text.contains("\u{2611}") || text.contains("\u{2705}"))
}
```

- [ ] **Step 2–5:** fail, implement, pass, commit as `"feat: render lists and task lists"`.

---

### Task 7: Block quotes and GitHub alerts

**Files:**
- Create: `Sources/MarkdownCore/Render/QuoteDecoration.swift`
- Modify: `Sources/MarkdownCore/Render/DocumentRenderer.swift`
- Test: `Tests/MarkdownCoreTests/QuoteRenderingTests.swift`

A blockquote whose first inline text begins with `[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]` or `[!CAUTION]` becomes an alert; the marker is removed from the visible text and recorded as a custom attribute. The bar and tint are drawn by the view during viewport layout, not by inserting glyphs.

- [ ] **Step 1: Write the failing test**

```swift
@Test func detectsAllFiveAlertKinds() {
    for kind in AlertKind.allCases {
        let src = "> [!\(kind.rawValue.uppercased())]\n> body\n"
        let doc = DocumentRenderer(theme: .system).render(source: src)
        let found = doc.attributedString.attribute(.alertKind, at: 0, effectiveRange: nil) as? String
        #expect(found == kind.rawValue)
        #expect(!doc.attributedString.string.contains("[!"))
    }
}

@Test func plainQuoteHasDepthButNoAlertKind() {
    let doc = DocumentRenderer(theme: .system).render(source: "> quoted\n")
    #expect(doc.attributedString.attribute(.alertKind, at: 0, effectiveRange: nil) == nil)
    #expect(doc.attributedString.attribute(.quoteDepth, at: 0, effectiveRange: nil) as? Int == 1)
}

@Test func nestedQuotesIncreaseDepth() {
    let doc = DocumentRenderer(theme: .system).render(source: "> > deep\n")
    #expect(doc.attributedString.attribute(.quoteDepth, at: 0, effectiveRange: nil) as? Int == 2)
}
```

- [ ] **Step 2–5:** fail, implement, pass, commit as `"feat: render block quotes and GitHub alerts"`.

---

### Task 8: Code blocks

**Files:** Modify `Sources/MarkdownCore/Render/DocumentRenderer.swift`; test `Tests/MarkdownCoreTests/CodeBlockRenderingTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@Test func rendersFencedCodeWithLanguageHighlighting() {
    let doc = DocumentRenderer(theme: .system).render(source: "```swift\nlet x = 1\n```\n")
    #expect(doc.attributedString.string.contains("let x = 1"))
    let font = doc.attributedString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    #expect(font?.isFixedPitch == true)
}

@Test func rendersTildeFencesAndIndentedCode() {
    let tilde = DocumentRenderer(theme: .system).render(source: "~~~\nplain\n~~~\n")
    #expect(tilde.attributedString.string.contains("plain"))
    let indented = DocumentRenderer(theme: .system).render(source: "    indented\n")
    #expect(indented.attributedString.string.contains("indented"))
}

@Test func mathAndMermaidFencesRenderAsCodeForNow() {
    // Phase 5 replaces these with real rendering; until then they must not be lost.
    let doc = DocumentRenderer(theme: .system).render(source: "```mermaid\ngraph TD\nA-->B\n```\n")
    #expect(doc.attributedString.string.contains("graph TD"))
}
```

- [ ] **Step 2–5:** fail, implement, pass, commit as `"feat: render fenced and indented code blocks"`.

---

### Task 9: Tables as hosted grid views

**Files:**
- Create: `Sources/MarkdownCore/Attachments/TableAttachment.swift`
- Modify: `Sources/MarkdownCore/Render/DocumentRenderer.swift`
- Test: `Tests/MarkdownCoreTests/TableRenderingTests.swift`

Uses `NSGridView` inside an `NSTextAttachmentViewProvider`. **Not** `NSTextTable`, which is verified not to lay out under TextKit 2.

- [ ] **Step 1: Write the failing test**

```swift
@Test func buildsGridViewWithHeaderAndAlignment() {
    let provider = TableAttachment(
        header: ["Left", "Centre", "Right"],
        alignments: [.left, .center, .right],
        rows: [["a", "b", "c"], ["d", "e", "f"]],
        theme: .system
    )
    let grid = provider.makeGridView()
    #expect(grid.numberOfColumns == 3)
    #expect(grid.numberOfRows == 3)  // header plus two body rows
}

@Test func rendererEmitsAnAttachmentForATable() {
    let src = "| a | b |\n|---|---|\n| 1 | 2 |\n"
    let doc = DocumentRenderer(theme: .system).render(source: src)
    var found = false
    doc.attributedString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: doc.attributedString.length)) { value, _, _ in
        if value is TableTextAttachment { found = true }
    }
    #expect(found)
}
```

- [ ] **Step 2–5:** fail, implement, pass, commit as `"feat: render GFM tables as hosted grid views"`.

---

### Task 10: The document view

**Files:**
- Create: `Sources/MarkdownCore/View/MarkdownTextView.swift`, `Sources/MarkdownCore/View/MarkdownScrollView.swift`
- Test: `Tests/MarkdownCoreTests/MarkdownTextViewTests.swift`

**Interfaces:**
- Produces: `MarkdownTextView` (an `NSTextView` subclass created with `usingTextLayoutManager: true`), `MarkdownScrollView` wrapping it, `func display(_ doc: RenderedDocument)`, `var onFileDrop: (([URL]) -> Void)?`.
- Draws quote bars and alert tints during viewport layout by reading `.quoteDepth` and `.alertKind`.
- Registers as a drag destination for `.fileURL`, filtered to claimed Markdown extensions, which is how a window drop becomes a tab.

- [ ] **Step 1: Write the failing test**

```swift
@Test @MainActor func staysOnTextKit2AfterDisplayingATable() {
    let view = MarkdownTextView()
    let doc = DocumentRenderer(theme: .system).render(source: "| a | b |\n|---|---|\n| 1 | 2 |\n")
    view.display(doc)
    view.layoutSubtreeIfNeeded()
    // The whole architecture depends on this staying true.
    #expect(view.textLayoutManager != nil)
}

@Test @MainActor func acceptsMarkdownFileDrags() {
    let view = MarkdownTextView()
    #expect(view.registeredDraggedTypes.contains(.fileURL))
}
```

- [ ] **Step 2–5:** fail, implement, pass, commit as `"feat: TextKit 2 document view with quote drawing and file drops"`.

---

### Task 11: App shell, bundle and file type registration

**Files:**
- Create: `project.yml`, `Makefile`, `App/AppDelegate.swift`, `App/MarkdownDocument.swift`, `App/DocumentController.swift`, `App/DocumentWindowController.swift`, `App/Info.plist`, `App/Markdown.entitlements`, `LICENSE`, `README.md`
- Test: manual, plus `make build`

**Interfaces:**
- `MarkdownDocument: NSDocument` reads the file, renders via `DocumentRenderer`, and owns the toggle between rendered and source.
- `DocumentController: NSDocumentController` implements the batch rule: the first URL of a batch opens a new window, the rest join it via `addTabbedWindow(_:ordered:)`.

- [ ] **Step 1: Write `project.yml`** declaring the app target, macOS 15 deployment, the `MarkdownCore` local package dependency, the bundle identifier, and Developer ID signing for Release.

- [ ] **Step 2: Write `Info.plist`** with `CFBundleName` = `Markdown`, `CFBundleDisplayName` = `A Bloody Simple Markdown Viewer`, `UTImportedTypeDeclarations` for `net.daringfireball.markdown`, and `CFBundleDocumentTypes` claiming `.md`/`.markdown`/`.mdown`/`.mkd`/`.mkdn`/`.mdwn`/`.mdtext` at rank `Default` and `.mdx`/`.qmd`/`.rmd` at rank `Alternate`.

- [ ] **Step 3: Implement the document and window controllers**, including `application(_:open:)` batching and the drag-to-window-becomes-tab path.

- [ ] **Step 4: Build and launch**

```bash
make build && open build/Build/Products/Debug/Markdown.app
```
Expected: the app launches with no document window and a File menu.

- [ ] **Step 5: Verify the whole point of the project**

```bash
make install            # copies to /Applications and re-registers with Launch Services
open -a Markdown ~/Desktop/some.md
```
Expected: the file opens rendered. Then double-click a `.md` file on the Desktop and confirm it opens in this app.

- [ ] **Step 6: Commit.** `git commit -m "feat: AppKit app shell, bundle, and Markdown file type registration"`

---

### Task 12: Tabs, windows and drag and drop

**Files:** Modify `App/DocumentController.swift`, `App/DocumentWindowController.swift`; test manually against the table below.

| Gesture | Expected |
|---|---|
| Double-click one `.md` in Finder | One new window |
| Select three `.md` files, press Enter | One window, three tabs |
| `open a.md b.md` | One window, two tabs |
| Drop a file on an open window | New tab in that window |
| Drop three files on an open window | Three tabs in that window |
| Drop a file on the Dock icon | New window |
| Double-click a second file later | A second, separate window |

- [ ] **Step 1: Implement** `addTabbedWindow` batching and the window drop handler wired to `MarkdownTextView.onFileDrop`.
- [ ] **Step 2: Walk the table above by hand**, recording each result.
- [ ] **Step 3: Fix anything that misbehaves.**
- [ ] **Step 4: Commit.** `git commit -m "feat: batch opens become tabs, drops follow where they land"`

---

## Later phases

Each gets its own plan once this one produces a working app: source mode and editing, search and bookmarks, math and Mermaid, the Quick Look and Thumbnail extensions, and the notarized release with CI.
