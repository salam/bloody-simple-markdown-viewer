# Contributing

Thanks for looking. A few things about this codebase are load-bearing and not
obvious, so please read this before changing the rendering layer.

## Getting started

```bash
swift test                 # the rendering engine, no Xcode needed
brew install xcodegen
make build                 # the app and its Quick Look extension
make install               # into /Applications
```

The Xcode project is generated from `project.yml` and is not committed, because
a `.pbxproj` cannot be reviewed. Change `project.yml`, never the generated
project.

## Rules that are not negotiable

**Never read `NSTextView.layoutManager`.** Not once, not from a helper, not
from a dependency. Reading it silently and permanently switches the view to
TextKit 1, which disables lazy viewport layout. That layout is why a 16 MB file
opens in about 130 ms rather than hanging. A debug assertion fires if anything
triggers it. Use the `textLayoutManager` APIs.

**Never use `NSTextTable` or `NSTextList`.** Both are broken under TextKit 2 in
ways that produce no error at all. Table cells collapse into plain sequential
paragraphs. `NSTextList` overrides the indentation you set, putting every list
marker in the same column whatever its nesting depth. Both were verified by
probe. Tables are measured arithmetically and drawn; lists carry a `listDepth`
attribute and explicit indents.

**Anything hosted as an attachment view is invisible to printing.** The print
path never instantiates attachment views. If you add a construct that hosts a
view, give it a flattened branch that produces an image, or it will silently
vanish from printed output and PDFs.

**A source position is a UTF-8 byte offset, never a UTF-16 index.** That is
what cmark reports and what `.sourceOffset` carries. AppKit's text APIs count
UTF-16 units. The two are equal for as long as a document stays ASCII, so
mixing them passes every test and then puts bookmarks on the wrong line in the
first file with an umlaut in it. Convert through `SourceOffset` wherever they
meet, and write fixtures that diverge by more than one line — a handful of
multi-byte characters shifts the counts by less than that and hides the bug.

**A pull-down `NSPopUpButton` draws its first menu item's image.** Not
`button.image`. A menu that starts empty, or one built and then never assigned,
leaves a bare chevron in the toolbar that does nothing, with no warning. Both
mistakes were in this toolbar at once.

**A derived view of the document is never editable.** The task filter shows a
subset of the file. The source view writes what it holds back to the document
on every change, on the mode toggle and on close. Filtered source is therefore
read-only, gated on one `isSourceEditable` check rather than three scattered
`isShowingSource` checks, because letting any of those paths run against a
filtered view would save the subset over the file and delete every hidden line.

**XcodeGen's `info:` and `entitlements:` blocks generate files.** They will
overwrite a hand-written `Info.plist` or entitlements file, and the result is an
app with no file associations or an extension that never loads. Both are
referenced through build settings instead, and CI checks they survived.

## Testing

Model-level assertions are not enough for layout. The attributed string can
carry perfectly correct indentation that TextKit then ignores, which is exactly
what the `NSTextList` bug did. `ListLayoutTests` measures where glyphs actually
land. Add tests at that level when you change layout.

A headless test process cannot instantiate `NSTextAttachmentViewProvider`
views, so attachment rendering needs either a real window or a check of the
ingredients. Both patterns are in the test suite.

`NSView.cacheDisplay(in:to:)` needs a window-backed context. Called on a
detached view it returns a blank canvas and reports no error, so a snapshot
assertion passes against nothing. Draw through an explicit `NSGraphicsContext`
instead, and fill the bitmap opaque first: a fresh one is transparent, and text
drawn in black at varying alpha comes back with identical RGB in every pixel.
`SnapshotTests.render(_:)` does both.

`presentedItemDidChange` coalesces. Two external writes 600 ms apart arrive as
one callback; 2.5 s apart they arrive as two. Verified by probe. The change
tracker is built on that assumption — it diffs the last known text against
what is on disk now, so a coalesced burst is reported in full under a single
timestamp rather than partly lost.

`make` regenerates the Xcode project when any source file or directory changes,
not only when `project.yml` does. Without that a new file builds for whoever
added it, from their own incremental project, and is missing for everyone else.

## Style

Comments explain why, not what. If a piece of code looks strange, say what goes
wrong without it, ideally with the evidence. Most of the strange code here is
working around something that fails silently.
