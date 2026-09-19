# A Bloody Simple Markdown Viewer

A native macOS Markdown viewer that opens instantly and stays small.

No web view. No JavaScript. No helper processes. It renders GitHub Flavored
Markdown, plus what Claude and ChatGPT actually produce, into native text, and
it can edit the file it is showing.

## Why

Most Markdown viewers on macOS are a web browser in a trench coat. A single
`WKWebView` spawns three helper processes and costs around 138 MB before it has
rendered anything. Measured on the same machine, this app's text stack renders
the same document about 2.7 times faster in a single process.

A 16 MB Markdown file opens and scrolls end to end in about 130 ms.

## What it does

- **Instant open.** No nib, no storyboard, no browser engine.
- **GitHub Flavored Markdown**: tables, task lists, strikethrough, autolinks,
  footnotes, and the five GitHub alert kinds (`> [!NOTE]` and friends).
- **Syntax-highlighted code** for sixteen common languages, with no embedded
  JavaScript engine.
- **Emoji shortcodes**, `:rocket:` and the rest.
- **Tabs that follow intent.** Files opened together share one window with tabs.
  A file opened on its own gets its own window. Drop a file on a window and it
  joins that window; drop it on the Dock icon and it opens a new one.
- **Search**, literal or regular expression, with case and whole-word options
  and a live match count.
- **Outline** of the document's headings, and **bookmarks** that survive the
  file being edited, moved or renamed.
- **Source mode.** Toggle to the raw Markdown, edit it, and save.
- **Everything in the title bar.** Tools and tabs share the row with the window
  buttons, so the document gets the whole window.
- **Light and dark**, following the system, with no second theme to maintain.

## Requirements

macOS 15 or later. Apple Silicon or Intel.

## Build and install

```bash
brew install xcodegen      # only needed once
make install               # builds Release and installs to /Applications
```

Then open a Markdown file and choose **Markdown > Make Default Markdown App**.
Setting the default handler is always an explicit choice; the app never seizes
your file associations on its own.

To work on the rendering engine alone, no Xcode project is needed:

```bash
swift test
```

The engine is a plain SwiftPM package. `project.yml` describes the app target
and XcodeGen generates the Xcode project, which is not committed because a
`.pbxproj` cannot be reviewed.

## If macOS says the app cannot be opened

Builds you make yourself are signed with your own certificate and just work.
A build downloaded from elsewhere carries a quarantine flag. macOS 15 removed
the old right-click-to-open bypass, so either:

```bash
xattr -cr /Applications/Markdown.app
```

or open **System Settings > Privacy & Security**, scroll to the bottom and
click **Open Anyway**.

## Design notes

Two findings shaped this app, both established by probe rather than assumed:

**`NSTextTable` does not work under TextKit 2.** Cells silently collapse into
plain sequential paragraphs, with no crash and no warning. The only way to make
it lay out is to drop the whole view back to TextKit 1, which forfeits lazy
viewport layout for the entire document, and that lazy layout is the reason a
16 MB file opens instantly. Tables are therefore measured arithmetically and
drawn directly. `NSTextList` has the same problem: it overrides the
indentation you set, putting every list marker in the same column regardless of
nesting depth.

**Reading `NSTextView.layoutManager` is a one-way switch.** A single read, from
anywhere including a dependency, permanently drops the view to TextKit 1. The
code never touches it, and a debug assertion fires if anything does.

The full design is in
[`docs/superpowers/specs`](docs/superpowers/specs/2026-09-19-markdown-viewer-design.md).

## Not yet

LaTeX math and Mermaid diagrams currently render as styled code blocks showing
their source, so nothing in your file is lost. Both will be rendered natively,
with no web view: [SwaTex](https://github.com/PhraseHQ/SwaTex) passes 129 of
130 common KaTeX commands at roughly 0.1 ms per formula, and
[swift-mermaid](https://github.com/Australware/swift-mermaid) covers flowchart,
sequence, state, class, ER and pie diagrams, which is most of what these tools
produce. Diagram types it cannot draw will keep falling back to their source.

A Quick Look extension is also planned, so Markdown previews render in Finder.
Preview.app itself cannot be extended: its document types are a fixed list and
it consumes no extension point.

## Dependencies

One:

| Package | Purpose | Licence |
|---|---|---|
| [swift-markdown](https://github.com/swiftlang/swift-markdown) | CommonMark and GFM parsing, via cmark-gfm | Apache 2.0 |

## Licence

MIT. See [LICENSE](LICENSE).
