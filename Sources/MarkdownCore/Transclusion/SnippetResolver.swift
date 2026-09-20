import Foundation

/// Where a byte of the expanded text came from in the file on disk.
///
/// Expanding snippets makes the text the renderer sees different from the text
/// the reader edits, and everything else in this app — bookmarks, source mode,
/// ticking a checkbox — addresses the file. Without this map the renderer would
/// hand out offsets into a string that exists nowhere, and every one of those
/// would land in the wrong place.
public struct SourceMap: Sendable {
    struct Segment: Sendable {
        /// Byte range in the expanded text.
        let expanded: Range<Int>
        /// Byte offset in the original this segment starts at.
        let origin: Int
        /// True for the document's own text, which maps one to one. False for
        /// included text, which collapses onto the directive that asked for it:
        /// there is no position in this file for a line that lives in another.
        let passthrough: Bool
    }

    var segments: [Segment] = []

    /// The identity map, for a document with no snippets in it.
    public static let identity = SourceMap()

    public func originalOffset(for expanded: Int) -> Int {
        guard !segments.isEmpty else { return expanded }
        var low = 0
        var high = segments.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let segment = segments[middle]
            if expanded < segment.expanded.lowerBound {
                high = middle - 1
            } else if expanded >= segment.expanded.upperBound {
                low = middle + 1
            } else {
                return segment.passthrough
                    ? segment.origin + (expanded - segment.expanded.lowerBound)
                    : segment.origin
            }
        }
        return segments.last.map { $0.passthrough
            ? $0.origin + ($0.expanded.count) : $0.origin } ?? expanded
    }
}

/// Pulls the files a document asks for into its text, before anything parses it.
///
/// This has to happen before parsing for the same reason the maths does: cmark
/// has no idea what a snippet is, and by the time it has built a tree the
/// directive is an image, a paragraph or a comment, not an instruction.
public enum SnippetResolver {
    public struct Resolved: Sendable {
        public let text: String
        public let map: SourceMap
        /// Files that were pulled in, so the window can watch them too.
        public let referenced: [URL]
        /// True when the document asked for anything at all, whether or not it
        /// could be read. The host uses this to decide whether it needs to ask
        /// for folder access.
        public let hasDirectives: Bool
    }

    /// How deep a chain of snippets may go before it is treated as a mistake.
    public static let maxDepth = 4

    /// - Parameters:
    ///   - baseURL: the including document. Everything resolves relative to its
    ///     directory, and nothing outside that directory is read.
    ///   - read: how to get a file's text. Injected so the host can apply its
    ///     own access rules, and so tests never touch the disk.
    public static func expand(source: String,
                              baseURL: URL?,
                              read: @escaping (URL) -> String?) -> Resolved {
        var builder = Builder(baseURL: baseURL, read: read)
        let text = builder.expand(source: source, origin: 0, depth: 0, stack: baseURL.map { [$0.standardizedFileURL] } ?? [])
        return Resolved(text: text,
                        map: SourceMap(segments: builder.segments),
                        referenced: builder.referenced,
                        hasDirectives: builder.sawDirective)
    }

    /// True if the source asks for anything, without reading a single file.
    /// Cheap enough to run before deciding whether to prompt for access.
    public static func containsDirectives(_ source: String) -> Bool {
        source.components(separatedBy: "\n").contains { SnippetDirective.parse(line: $0) != nil }
    }

    // MARK: -

    private struct Builder {
        let baseURL: URL?
        let read: (URL) -> String?
        var segments: [SourceMap.Segment] = []
        var referenced: [URL] = []
        var sawDirective = false
        private var written = 0

        init(baseURL: URL?, read: @escaping (URL) -> String?) {
            self.baseURL = baseURL
            self.read = read
        }

        mutating func expand(source: String, origin: Int, depth: Int, stack: [URL]) -> String {
            var out = ""
            var lineStart = 0                       // byte offset within `source`
            for line in source.components(separatedBy: "\n") {
                let lineBytes = line.utf8.count
                defer { lineStart += lineBytes + 1 }

                guard let directive = SnippetDirective.parse(line: line) else {
                    append(line + "\n", to: &out, origin: origin + lineStart, passthrough: true)
                    continue
                }
                sawDirective = true
                let replacement = resolve(directive, depth: depth, stack: stack)
                // The whole of an included block answers to the directive's own
                // line, so jumping to source lands on the `![[…]]` rather than
                // on a position this file does not have.
                append(replacement, to: &out, origin: origin + lineStart, passthrough: false)
            }
            if out.hasSuffix("\n") { out.removeLast(); trimLastSegment() }
            return out
        }

        private mutating func resolve(_ directive: SnippetDirective,
                                      depth: Int, stack: [URL]) -> String {
            guard depth < SnippetResolver.maxDepth else {
                return warning(directive, "nested more than \(SnippetResolver.maxDepth) deep")
            }
            guard let base = baseURL?.deletingLastPathComponent() else {
                return warning(directive, "is relative to a document that has not been saved")
            }
            guard let url = confined(directive.path, under: base) else {
                return warning(directive, "is outside this document's folder")
            }
            guard !stack.contains(url) else {
                return warning(directive, "includes itself")
            }
            guard var text = read(url) else {
                return warning(directive, "could not be read")
            }
            referenced.append(url)

            if let heading = directive.heading {
                guard let section = SnippetDirective.section(heading, in: text) else {
                    return warning(directive, "has no heading “\(heading)”")
                }
                text = section
            }

            var nested = Builder(baseURL: url, read: read)
            nested.sawDirective = sawDirective
            // Nested content maps to the directive too, so the inner builder's
            // own segments are thrown away rather than merged.
            let expanded = nested.expand(source: text, origin: 0, depth: depth + 1,
                                         stack: stack + [url])
            referenced.append(contentsOf: nested.referenced)

            let indented = directive.indent.isEmpty
                ? expanded
                : expanded.components(separatedBy: "\n")
                    .map { $0.isEmpty ? $0 : directive.indent + $0 }
                    .joined(separator: "\n")
            return indented + "\n"
        }

        /// Resolves a path inside the document's folder, or refuses.
        ///
        /// An absolute path or one climbing out with `..` is refused rather
        /// than read: the folder the reader granted is the boundary, and a
        /// viewer should not turn a document into a way to read the disk.
        private func confined(_ path: String, under base: URL) -> URL? {
            guard !path.hasPrefix("/"), !path.hasPrefix("~") else { return nil }
            let candidate = base.appendingPathComponent(path).standardizedFileURL
            let root = base.standardizedFileURL.path
            let target = candidate.path
            guard target == root || target.hasPrefix(root.hasSuffix("/") ? root : root + "/") else {
                return nil
            }
            return candidate
        }

        /// A failed snippet says so in the document, as a GitHub alert. Leaving
        /// the line as written would read as content the author wrote; leaving
        /// nothing would be a silent hole.
        private func warning(_ directive: SnippetDirective, _ reason: String) -> String {
            let indent = directive.indent
            let name = directive.path + (directive.heading.map { "#\($0)" } ?? "")
            return """
            \(indent)> [!WARNING]
            \(indent)> Snippet `\(name)` \(reason).

            """
        }

        private mutating func append(_ text: String, to out: inout String,
                                     origin: Int, passthrough: Bool) {
            let bytes = text.utf8.count
            guard bytes > 0 else { return }
            segments.append(SourceMap.Segment(expanded: written..<(written + bytes),
                                              origin: origin, passthrough: passthrough))
            written += bytes
            out += text
        }

        private mutating func trimLastSegment() {
            guard var last = segments.popLast() else { return }
            guard last.expanded.count > 1 else { written -= 1; return }
            last = SourceMap.Segment(expanded: last.expanded.lowerBound..<(last.expanded.upperBound - 1),
                                     origin: last.origin, passthrough: last.passthrough)
            segments.append(last)
            written -= 1
        }
    }
}
