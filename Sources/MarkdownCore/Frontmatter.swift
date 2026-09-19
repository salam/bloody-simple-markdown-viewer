import Foundation

/// Strips YAML (`---`) or TOML (`+++`) frontmatter from the head of a document.
///
/// No CommonMark parser understands frontmatter; fed in raw, a leading `---`
/// is parsed as a thematic break or a setext heading underline. So it has to
/// come off before parsing and be reported separately.
public enum Frontmatter {
    public struct Result: Sendable {
        public let frontmatter: String?
        public let body: String
        /// Lines removed from the head, so parser source locations can be
        /// shifted back onto the original file.
        public let bodyLineOffset: Int
    }

    public static func split(_ source: String) -> Result {
        for fence in ["---", "+++"] where source.hasPrefix(fence + "\n") {
            let lines = source.components(separatedBy: "\n")
            guard let close = lines.dropFirst().firstIndex(of: fence) else { continue }
            let content = lines[1..<close].joined(separator: "\n")
            let body = lines[(close + 1)...].joined(separator: "\n")
            return Result(frontmatter: content, body: body, bodyLineOffset: close + 1)
        }
        return Result(frontmatter: nil, body: source, bodyLineOffset: 0)
    }
}
