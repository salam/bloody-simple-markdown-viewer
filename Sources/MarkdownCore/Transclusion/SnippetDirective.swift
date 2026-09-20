import Foundation

/// A line that asks for another file's contents to be pulled in here.
///
/// Three spellings, because three tools people actually use spell it three
/// ways and a viewer that only understands one of them is a viewer that
/// silently drops content:
///
/// - `![[notes.md]]` and `![[notes.md#Heading]]` — Obsidian and most note apps
/// - `@Snippet(notes.md)` and `@Snippet(notes.md#Heading)`
/// - `--8<-- "notes.md"` — the MkDocs snippets convention
///
/// A directive is only recognised on a line of its own. Inline, `![[x]]` is
/// far more likely to be someone writing about the syntax than using it.
public struct SnippetDirective: Equatable, Sendable {
    /// The path as written, always relative to the including document.
    public let path: String
    /// The section to pull in, if the directive named one.
    public let heading: String?
    /// Leading whitespace on the directive's line, reapplied to the included
    /// text so a snippet inside a list stays inside it.
    public let indent: String

    public init(path: String, heading: String?, indent: String) {
        self.path = path
        self.heading = heading
        self.indent = indent
    }

    /// Reads a directive from one line, or nil if the line is ordinary text.
    public static func parse(line: String) -> SnippetDirective? {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        let body = line.dropFirst(indent.count).trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }

        for (open, close) in [("![[", "]]"), ("@Snippet(", ")"), ("--8<--", "")] {
            guard body.hasPrefix(open) else { continue }
            var inner = String(body.dropFirst(open.count))
            if close.isEmpty {
                // MkDocs quotes the path and has no closing token.
                inner = inner.trimmingCharacters(in: .whitespaces)
                guard inner.hasPrefix("\""), inner.hasSuffix("\""), inner.count >= 2 else { return nil }
                inner = String(inner.dropFirst().dropLast())
            } else {
                guard inner.hasSuffix(close) else { return nil }
                inner = String(inner.dropLast(close.count))
            }
            return make(from: inner, indent: indent)
        }
        return nil
    }

    private static func make(from inner: String, indent: String) -> SnippetDirective? {
        let trimmed = inner.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // Split on the last `#`, so a file with a hash in its name still works.
        if let hash = trimmed.lastIndex(of: "#") {
            let path = String(trimmed[trimmed.startIndex..<hash]).trimmingCharacters(in: .whitespaces)
            let heading = String(trimmed[trimmed.index(after: hash)...])
                .trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty, !heading.isEmpty else { return nil }
            return SnippetDirective(path: path, heading: heading, indent: indent)
        }
        return SnippetDirective(path: trimmed, heading: nil, indent: indent)
    }

    /// A document's section: the heading itself and everything under it, down
    /// to the next heading at the same or a higher level.
    ///
    /// The heading is included, as Obsidian does it. A transcluded section that
    /// arrived without its title would lose its place in the outline and read
    /// as though it belonged to whatever came before.
    public static func section(_ heading: String, in source: String) -> String? {
        let lines = source.components(separatedBy: "\n")
        let wanted = heading.lowercased()

        var start: Int?
        var level = 0
        for (index, line) in lines.enumerated() {
            let hashes = line.prefix { $0 == "#" }.count
            guard hashes > 0, hashes <= 6 else { continue }
            let title = line.dropFirst(hashes).trimmingCharacters(in: .whitespaces).lowercased()
            if start == nil {
                if title == wanted { start = index; level = hashes }
            } else if hashes <= level {
                return lines[start!..<index].joined(separator: "\n")
                    .trimmingCharacters(in: .newlines)
            }
        }
        guard let start else { return nil }
        return lines[start...].joined(separator: "\n").trimmingCharacters(in: .newlines)
    }
}
