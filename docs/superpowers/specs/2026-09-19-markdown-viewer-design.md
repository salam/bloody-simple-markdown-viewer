# A Bloody Simple Markdown Viewer — Design

**Status:** Approved 2026-09-19
**Date:** 2026-09-19

## 1. Goal

A native macOS Markdown viewer that opens instantly, stays small in memory, renders the
Markdown that GitHub, Claude and ChatGPT actually produce, and can edit the file it is
showing. It registers as the default handler for Markdown files and extends Finder's
Quick Look so Markdown previews render rather than showing raw source.

Non-goals: a full Markdown IDE, live collaborative editing, publishing/export pipelines,
iOS. These are explicitly out of scope.

### Success criteria

| Metric | Target |
|---|---|
| Cold launch to first paint, 100 KB document | < 200 ms |
| Warm open, 100 KB document | < 50 ms |
| Resident memory, one 100 KB document open | < 80 MB |
| Parse time, 1 MB document | < 100 ms |
| 10 MB document | Opens without beachball; scrolling need not be perfectly smooth |
| Helper processes spawned | Zero |

**Measured against these on 2026-09-19**, with the Showcase document open in the
installed build: memory footprint 43 MB against a budget of 80 MB, zero helper
processes, and a 16 MB file loaded and scrolled end to end in 130 ms at 95 MB
peak. The large-document spike removed the need for chunked parsing entirely:
TextKit 2's lazy viewport layout handles it unaided.

## 2. Key findings that shaped this design

These were established by measurement and probe on macOS 15.7.3 / Xcode 26.3 / Swift 6.2.4,
not assumed. They are recorded because they are the load-bearing constraints.

**Preview.app cannot be extended.** Its `Info.plist` carries a closed, hardcoded
`CFBundleDocumentTypes` list, it has no `PlugIns` directory, and it consumes no extension
point. No supported mechanism adds a document type to it. The achievable equivalent is a
Quick Look Preview Extension, which serves Finder's spacebar preview, the Finder preview
pane, gallery view, Spotlight results and Open/Save panels. It does not serve Preview.app.
Markdown already maps to the UTI `net.daringfireball.markdown`, which several shipping
third-party extensions claim successfully on this OS build.

**WKWebView is disqualified for the document view.** Measured on this machine: a single
web view spawns three helper processes (WebContent, GPU, Networking) and costs ~138 MB
idle. On an ~800 KB document it reached ~184 MB across four processes, against ~70 MB in
one process for a native text view, and was ~2.7x slower to first paint. This conflicts
directly with the stated performance and footprint goals.

**`NSTextTable` does not work under TextKit 2.** Verified by probe: a table built with
`NSTextTableBlock` in a text view genuinely running `NSTextLayoutManager` silently
collapses into plain sequential paragraphs. No crash, no data loss, no automatic fallback.
Reading `.layoutManager` anywhere flips the view permanently to TextKit 1, where the table
then lays out correctly, but that forfeits lazy viewport layout for the whole document.
Therefore tables must not use `NSTextTable`.

**Hosting a view inside a text attachment does work under TextKit 2.** Verified by probe:
an `NSTextAttachmentViewProvider` renders its view inline at the correct position and size,
and `textLayoutManager` stays non-nil. This is the escape hatch for every construct TextKit
cannot lay out natively.

**Native math is production quality; native diagrams are partial.** SwaTex passes 129/130
common KaTeX commands (the single miss, `\sideset`, is unsupported by KaTeX itself),
renders in ~0.1 ms per formula, adds ~2.0 MB, and exposes exact baseline metrics.
swift-mermaid covers flowchart, sequence, state, class, ER and pie, and throws a typed
error for the rest. Full details in sections 4.4 and 4.5.

## 3. Architecture

A SwiftPM package holds all rendering logic and is buildable and testable with
`swift build` / `swift test`, with no Xcode involvement. An XcodeGen-generated Xcode
project builds the app and the two extensions, because SwiftPM cannot produce a `.app`
bundle or an embedded `.appex`. `project.yml` is the committed source of truth; the
generated `.xcodeproj` is not committed.

```
bloody-simple-markdown-viewer/
├── Package.swift                  # core library: swift build / swift test, no Xcode
├── Sources/
│   └── MarkdownCore/
│       ├── Parsing/               # frontmatter, math/mermaid prescan, cmark-gfm, post-walk
│       ├── Model/                 # document IR, every node carrying a source range
│       ├── Render/                # IR -> NSAttributedString, theming, typography
│       ├── Attachments/           # table, math, mermaid, image view providers
│       ├── Highlight/             # hand-rolled code lexer
│       └── Search/                # literal and regex search over source
├── Tests/MarkdownCoreTests/
├── App/                           # AppKit application
├── QuickLookExtension/
├── ThumbnailExtension/
├── project.yml                    # XcodeGen
└── Makefile                       # bootstrap, build, test, release
```

The app is AppKit, built programmatically. No SwiftUI and no storyboards, both of which
add measurable launch cost for no benefit here.

### 3.1 Rendering pipeline

```
file bytes
  -> frontmatter strip (YAML --- / TOML +++ at offset 0)
  -> math + mermaid prescan (record spans, replace with placeholders)
  -> swift-markdown (cmark-gfm) -> Document AST with source ranges
  -> post-walk: GitHub alerts, emoji shortcodes, heading anchor IDs
  -> document IR (blocks + inlines, every node keeps its source range)
  -> NSAttributedString + attachment placeholders
  -> NSTextView (TextKit 2)
```

The source range on every node is what makes scroll-position preservation across the
rendered/source toggle, search highlighting in both modes, and bookmark anchoring all work
off one mechanism.

### 3.2 The single text view

One `NSTextView` created with `usingTextLayoutManager: true`. Two attributed-string
payloads are swapped into it: the rendered document, and the syntax-highlighted source.
Toggling swaps the payload and maps scroll position through source ranges. Source mode
sets `isEditable = true`.

`.layoutManager` is never read, anywhere, because reading it silently and permanently
drops the view to TextKit 1. A debug-build observer on `willSwitchToNSLayoutManager`
asserts if any code or dependency triggers this. This is a standing constraint on all
future contributions and belongs in CONTRIBUTING.md.

## 4. Components

### 4.1 Tables

Rendered as an `NSGridView` hosted in an `NSTextAttachmentViewProvider`, because
`NSTextTable` does not lay out under TextKit 2 (section 2). Column alignment comes from the
GFM delimiter row. The grid sizes to its content up to the available width, then
proportionally compresses columns. Selection and copy of table contents is handled by the
host view rather than inherited from the text view, which is a known limitation.

### 4.2 Lists, quotes, callouts

Native, no attachments. Lists use `NSTextList`, which is TextKit 2's supported construct.
Task list checkboxes are SF Symbol glyphs, not controls, in v1. Block quotes and GitHub
alerts use a custom paragraph attribute carrying quote depth and alert kind; the left
border and tinted background are drawn by the host view during the viewport layout pass.
The five alert kinds are NOTE, TIP, IMPORTANT, WARNING and CAUTION.

### 4.3 Code blocks

A hand-rolled lexer covering the languages that dominate LLM output: Swift, Python,
JavaScript, TypeScript, JSON, Bash, Go, Rust, C, C++, Java, SQL, HTML, CSS, YAML and
Markdown. Keyword sets plus string, comment and number rules. Unknown languages render
unhighlighted in monospace, which is a correct and unembarrassing fallback.

This is deliberately not highlight.js via JavaScriptCore. A viewer's code blocks need to
look right, not be compiler-accurate, and embedding a JavaScript engine contradicts the
footprint goal. If per-language accuracy later proves insufficient, Highlightr is the
documented escape hatch behind the same protocol.

### 4.4 Math

SwaTex, pinned to an exact version, behind a `MathRenderer` protocol so it is swappable.

Display math becomes a `SwaTexView` in a view provider. Inline math becomes an
`NSTextAttachment` holding a `CGImage`, with `bounds.y` set to the negative of the
reported depth so the formula sits on the surrounding baseline. This was proven end to end
in a real `NSTextView` during evaluation.

Delimiters recognized, covering both GitHub and LLM conventions: `$...$`, `` $`...`$ ``,
`$$...$$`, `\(...\)`, `\[...\]`, and ```` ```math ```` blocks. Formula dimensions are
clamped before rasterizing, because SwaTex will happily produce a two-million-point display
list from a pathological `\rule`. The LaTeX source is attached as the accessibility label,
since a drawn formula is otherwise invisible to VoiceOver.

Known upstream defect, accepted: `\operatorname*` renders italic instead of upright. Worked
around by rewriting it to `\operatorname` during the prescan.

### 4.5 Mermaid

swift-mermaid, pinned, behind a `DiagramRenderer` protocol. Its `MermaidScene` is a
resolution-independent geometry IR, so diagrams re-rasterize crisply at the current backing
scale and on zoom.

Three defects found during evaluation must be handled by us:

1. **Trap on empty diagrams.** A source with a header but no nodes yet, such as a bare
   `graph TD`, yields a non-finite scene size and traps inside `cgImage`. Guarded by
   checking the scene size is finite and positive before rasterizing. This is not an edge
   case; streamed LLM output passes through that exact state.
2. **Uncatchable stack overflow.** A subgraph nested inside another subgraph of the same
   name recurses until the stack dies, inside `render()`, where it cannot be caught. A
   pre-flight scan rejects duplicate nested subgraph identifiers before rendering. This is
   a cheap token scan, not a reimplementation of the parser.
3. **Layout is only deterministic single-threaded.** Vendored global counters make
   concurrent renders produce differing geometry ~6% of the time. All diagram rendering is
   serialized onto one dedicated queue.

Unsupported diagram types throw `unsupportedDiagramType`, which is caught and falls back to
displaying the diagram source in a styled code block. Gantt, mindmap, timeline and
quadrant charts take this path. `classDef` and `style` directives are silently ignored by
the library; styled diagrams render with default colors.

Both crash fixes and the determinism issue have minimal reproducers and should be offered
upstream. If they are not accepted, the library is small enough to vendor.

### 4.6 Images

`NSTextAttachment` for both local relative paths and remote URLs. Remote images load
asynchronously and invalidate only the affected range. A sandboxed app cannot reach
arbitrary local paths, so images resolve relative to the document's security-scoped
directory access.

## 5. Application behaviour

### 5.1 Windows and tabs

A batch of files opened together shares one window with tabs; files opened separately get
separate windows.

`application(_:open:)` receives a single call carrying all URLs when several files are
opened together, whether from Finder, `open a.md b.md`, or a Dock drop. A custom
`NSDocumentController` opens the first URL in a new window and joins the remainder via
`addTabbedWindow(_:ordered:)`, explicitly rather than relying on the system-wide "prefer
tabs" preference, which groups by window creation time and cannot express this rule.

Native `NSWindow` tabbing is used rather than a custom tab bar. It is free, fully native,
and gives drag-reorder, merge and split for no code. The memory concern is addressed by
parsing a tab's document lazily on first display rather than by sharing one text view.
A custom tab bar with a shared view remains a documented future optimization if tab-heavy
sessions prove costly in practice.

Known ambiguity, accepted: Launch Services can coalesce genuinely separate opens that
arrive during a cold launch into one batch. Array size is the only available signal.

Drag and drop follows the same rule, that where a file lands decides what it joins:

| Gesture | Result |
|---|---|
| Drop onto an open document window | Opens as a new tab in *that* window |
| Drop onto the Dock icon | Opens a new window; several files dropped together become tabs in that one new window |
| Drop onto the Dock icon while no window is open | Opens a new window |

The window drop is served by an `NSView` drag destination on the document view accepting
`.fileURL`, filtered to the content types the app claims, which asks the document
controller to open each URL as a tab of the receiving window. The Dock drop arrives
through the ordinary `application(_:open:)` path and is indistinguishable from a Finder
open, which is why it produces a new window rather than joining an existing one.

### 5.2 Editing

`NSDocument`-based. Source mode is editable, with undo from the text view, dirty state in
the title bar, and explicit save. No autosave: silently rewriting a user's file from
something billed as a viewer is a bad default. Closing with unsaved changes prompts.

External modification is detected through `NSFilePresenter`, which `NSDocument` provides.
If the file changes on disk and the buffer is clean, it reloads; if dirty, it prompts.

The rendered view is read-only. Re-render happens on toggling back from source.

### 5.3 Search

A custom find bar, because `NSTextFinder` does not support regular expressions.

Literal and regex search via `NSRegularExpression`, with case sensitivity and whole-word
options, live match count, next/previous, and highlight-all. Search runs against the source
text, which is canonical and lets users match Markdown syntax itself, and matches are
projected into the rendered view through source ranges. It therefore works identically in
both modes. Invalid regular expressions report the parse error inline rather than silently
matching nothing.

### 5.4 Outline and bookmarks

Two distinct things, deliberately separated.

The **outline** is the heading hierarchy, derived from the AST, shown in a collapsible
sidebar. Always current, never persisted.

**Bookmarks** are user-placed named marks. Each stores a source offset plus a short snippet
of anchor text, so a bookmark can be re-located by content when the file has been edited
underneath it rather than silently pointing at the wrong line. Persisted in
`~/Library/Application Support/<bundle id>/bookmarks.json`, keyed by security-scoped
bookmark data rather than path, so they survive the file being moved or renamed.

### 5.5 File type registration

Imports `net.daringfireball.markdown` rather than exporting it, since the identifier is
already declared by several parties including Xcode. A private fallback UTI conforming to
`public.plain-text` is exported, so that on a machine with no competing Markdown app
Launch Services has a stable static type instead of a synthesized dynamic one.

| Extensions | Rank |
|---|---|
| `.md`, `.markdown`, `.mdown` | Default |
| `.mkd`, `.mkdn`, `.mdwn`, `.mdtext` | Default |
| `.mdx`, `.qmd`, `.rmd` | Alternate |

`.mdx`, `.qmd` and `.rmd` belong to the MDX, Quarto and R Markdown ecosystems, whose users
already have dedicated tools. The app appears in "Open With" for them but does not claim
them. `.text` is not claimed at all; it is the generic system plain-text type.

Becoming the default handler is an explicit, user-initiated action, a button in settings
and a dismissible first-run offer, calling `NSWorkspace.setDefaultApplication`. Never
silent, regardless of whether the API prompts.

### 5.6 Quick Look and Thumbnail extensions

Both reuse MarkdownCore, which is the main reason the rendering logic lives in a separate
package.

The preview extension implements `QLPreviewingController` and renders into the same text
view stack, capped to a leading portion of very large files for responsiveness. The
thumbnail extension renders the first screenful. Both must carry
`com.apple.security.app-sandbox` in their final signature; PlugInKit silently refuses to
register an extension whose entitlements were stripped after signing, with the rejection
visible only in `pkd`'s log. Signing is inside-out, extensions before the host app, never
a single `--deep` pass.

macOS does not auto-enable third-party Quick Look extensions. The README documents the
System Settings path, and the app offers an in-app pointer to it.

## 6. Dependencies

| Package | Purpose | Licence |
|---|---|---|
| swift-markdown (-> swift-cmark) | CommonMark + GFM parsing | Apache 2.0 |
| SwaTex | LaTeX typesetting | MIT |
| swift-mermaid | Diagram rendering | MIT |

All pinned to exact versions and wrapped behind protocols so each is swappable. Nothing
else. No JavaScript engine, no web view, no networking stack beyond remote image fetch.

Governance risk is real and acknowledged: SwaTex is two months old with one contributor,
and swift-mermaid is four months old with one contributor. Both are MIT and small enough to
vendor if they go unmaintained, and the protocol boundaries mean a replacement does not
ripple outward.

## 7. Build, test and distribution

`swift test` covers MarkdownCore with no Xcode. The CommonMark and GFM specification
example suites are the correctness baseline for the parser layer, plus golden-image tests
for the attachment renderers.

GitHub Actions on `macos-26` runners, which carry Xcode 26.3. Pull requests build and test
unsigned with ad-hoc signing, which is sufficient to compile and unit test the app and both
extensions.

Releases are signed with the existing Developer ID Application identity (team 259HA4GJSD),
notarized with `notarytool` and stapled, from a tagged release job. This matters beyond
convenience: since Homebrew 5.0.0, casks must be signed and notarized, and macOS 15 removed
the right-click Gatekeeper bypass, so an unsigned build now requires a trip through System
Settings with an admin password.

The app is sandboxed. It needs it for the extensions regardless, it keeps the App Store
open as a future option, and the security-scoped bookmark machinery it requires is the same
machinery bookmarks already need.

## 8. Build order

Each phase is independently useful and independently shippable.

0. **Spike.** TextKit 2 with a hosted attachment, and a 10 MB document opened and scrolled,
   to confirm large files do not hang. Throwaway.
1. **Core viewer.** MarkdownCore parse and render, AppKit app, one window, GFM including
   tables, lists, code, quotes, alerts, footnotes and frontmatter. Light and dark.
2. **Documents, windows, tabs.** NSDocument, batch-to-tabs rule, recent files, file type
   registration, default handler offer.
3. **Source mode and editing.** Toggle, code highlighting, editing, save, external change
   detection.
4. **Search and bookmarks.** Regex find bar, outline sidebar, persistent bookmarks.
5. **Math and diagrams.** SwaTex with baseline alignment, swift-mermaid with the three
   mitigations from 4.5.
6. **Quick Look and Thumbnail extensions.**
7. **Ship.** Notarized release, CI, README, LICENSE, Homebrew cask.

## 9. Open risks

| Risk | Mitigation |
|---|---|
| TextKit 2 viewport layout is reported to cause scrollbar jitter on very large documents | Phase 0 spike. Target is only that large files do not hang. |
| Accidental fallback to TextKit 1 via `.layoutManager` in our code or a dependency | Debug assertion on `willSwitchToNSLayoutManager`; documented in CONTRIBUTING.md |
| SwaTex and swift-mermaid each have one contributor and are a few months old | Pinned versions, protocol boundaries, both vendorable |
| Both Mermaid libraries silently render a misleading partial diagram on malformed input instead of erroring | Accepted for v1 and documented; a stricter pre-validator is possible later |
| Mermaid fidelity is behind mermaid.js on the long tail of diagram types | Typed unsupported-type error drives a clean fallback to source |
| Quick Look extension fails to register when entitlements are stripped after signing | Inside-out signing in the release script; a CI check asserting the sandbox entitlement survives |

## 10. Naming and licence

| Item | Value |
|---|---|
| Menu bar and Dock (`CFBundleName`) | Markdown |
| Full name (`CFBundleDisplayName`) | A Bloody Simple Markdown Viewer |
| Bundle identifier | `ch.sala.BloodySimpleMarkdownViewer` |
| Repository | `salam/bloody-simple-markdown-viewer` |
| Licence | MIT |

The menu bar reads "Markdown" so menus are immediately legible: Markdown > About,
Markdown > Settings. The full name carries the personality everywhere it has room to,
in the About box, the README and the repository.
