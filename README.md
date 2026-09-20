# A Bloody Simple Markdown Viewer

A native macOS Markdown viewer that opens instantly and stays small.

No web view. No JavaScript. No helper processes. It renders GitHub Flavored
Markdown, plus what Claude and ChatGPT actually produce, into native text, and
it can edit the file it is showing.

## Why

Most Markdown viewers on macOS are a web browser in a trench coat. A single
`WKWebView` spawns three helper processes and costs around 138 MB before it has
rendered anything.

Measured on the same machine, macOS 15.7 on Apple Silicon:

| | This app | A WKWebView |
|---|---|---|
| Memory footprint, document open | 43 MB | 138 MB idle, 184 MB with content |
| Helper processes | 0 | 3 |
| Time to first paint | about 2.7x faster | baseline |

A 16 MB Markdown file opens and scrolls end to end in about 130 ms.

## What it does

- **Instant open.** No nib, no storyboard, no browser engine.
- **GitHub Flavored Markdown**: tables, task lists, strikethrough, autolinks,
  footnotes, and the five GitHub alert kinds (`> [!NOTE]` and friends).
- **Syntax-highlighted code** for sixteen common languages, with no embedded
  JavaScript engine.
- **Emoji shortcodes**, `:rocket:` and the rest.
- **LaTeX math**, rendered natively on the text baseline. Both GitHub's dollar
  delimiters and the backslash form ChatGPT emits.
- **Mermaid diagrams**, drawn natively, following light and dark mode.
- **Task states beyond GitHub's two.** `[x]`, `[✅]`, `[OK]` and `[DONE]` all
  mean done; `[~]`, `[WIP]` and `[in progress]` mean started. Filter the
  document to just the states you care about, in the render or in the source.
- **Tick a box by clicking it.** The only edit the rendered view makes, and it
  goes straight into the Markdown. Option-click cycles open, in progress and
  done. The marker follows whatever spelling the file already uses, so a
  document written in `[✅]` stays written in `[✅]`.
- **Copy a code block** from the button that appears when you hover it.
- **See what changed underneath you.** When another program rewrites the file
  while you are reading it, the lines it touched stay highlighted, in a colour
  derived from the clock time of that save: one edit, one colour, and a later
  one is visibly a different edit. Hovering says when. The marks last until you
  close the document.
- **Share** the file to Mail, Messages or AirDrop from the system share sheet.
- **Tabs that follow intent.** Files opened together share one window with tabs.
  A file opened on its own gets its own window. Drop a file on a window and it
  joins that window; drop it on the Dock icon and it opens a new one.
- **Search**, literal or regular expression, with case and whole-word options
  and a live match count.
- **Outline** of the document's headings, and **bookmarks** that survive the
  file being edited, moved or renamed.
- **Source mode.** Toggle to the raw Markdown, edit it, and save. Double-click
  anywhere in the render to land on the matching line.
- **Finder previews.** Press space on a Markdown file and it renders.
- **Print and export to PDF.** Paginated, with a running head and page numbers,
  as selectable text rather than a picture of text. Tables, code and formulas
  all come through.
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

**Printing never instantiates attachment views.** A table or formula hosted as a
live view is simply absent from the page, with no error. Print and PDF therefore
re-render the document in a flattened mode where those become block-based images
that replay their drawing into the page context, so the output stays vector and
its text stays selectable.

**Reading `NSTextView.layoutManager` is a one-way switch.** A single read, from
anywhere including a dependency, permanently drops the view to TextKit 1. The
code never touches it, and a debug assertion fires if anything does.

The full design is in
[`docs/superpowers/specs`](docs/superpowers/specs/2026-09-19-markdown-viewer-design.md).

## Quick Look

Pressing space on a Markdown file in Finder shows it rendered, not as raw
source. The same extension serves the Finder preview pane, gallery view,
Spotlight results and Open panels.

macOS does not enable third-party Quick Look extensions automatically. If
previews still show plain text, open **System Settings > General > Login Items
& Extensions > Quick Look** and switch this one on.

Preview.app itself cannot be extended. Its document types are a fixed list in
its own Info.plist, it has no plug-ins directory, and it consumes no extension
point. A Quick Look extension is the closest achievable thing, and it covers
every system preview surface except Preview.app.

## Not yet

Mermaid covers flowchart, sequence, state, class, entity-relationship and pie
diagrams, which is most of what these tools emit. Gantt charts, mindmaps and
timelines are not supported yet and fall back to showing their source, so
nothing in your file is ever lost.

## Dependencies

Three, all permissively licensed, each behind a protocol so it can be swapped:

| Package | Purpose | Licence |
|---|---|---|
| [swift-markdown](https://github.com/swiftlang/swift-markdown) | CommonMark and GFM parsing, via cmark-gfm | Apache 2.0 |
| [SwaTex](https://github.com/PhraseHQ/SwaTex) | LaTeX typesetting, 129 of 130 common KaTeX commands | MIT |
| [swift-mermaid](https://github.com/Australware/swift-mermaid) | Diagram rendering | MIT |

Three defects in the diagram library are worked around rather than tolerated,
all found by testing it rather than reading its documentation. A diagram header
with no nodes yet produces an infinite size and crashes on rasterising, which a
streamed response hits constantly. A subgraph nested inside another of the same
name overflows the stack inside the library where it cannot be caught, so it is
refused beforehand. And its layout is only deterministic on one thread, so every
render is serialised.

## Licence

MIT. See [LICENSE](LICENSE).
