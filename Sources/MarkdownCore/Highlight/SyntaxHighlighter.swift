import AppKit

/// A single-pass lexer that colours code blocks.
///
/// Token kinds are recognised in priority order (comment, string, number,
/// identifier) so a keyword appearing inside a string or comment is never
/// recoloured. An unrecognised language returns plain monospace text rather
/// than an error: a viewer must always show the code.
public enum SyntaxHighlighter {
    public static func highlight(_ code: String, language: String?, theme: Theme) -> NSAttributedString {
        let base: [NSAttributedString.Key: Any] = [
            .font: theme.monoFont,
            .foregroundColor: theme.codePlainColor
        ]
        let out = NSMutableAttributedString(string: code, attributes: base)
        guard let grammar = LanguageGrammar.named(language) else { return out }

        let chars = Array(code)
        var i = 0
        let n = chars.count

        func colour(_ from: Int, _ to: Int, _ c: NSColor) {
            guard to > from, from >= 0, to <= n else { return }
            // Attribute ranges are in UTF-16 units; convert from character indices.
            let prefix = String(chars[0..<from]).utf16.count
            let length = String(chars[from..<to]).utf16.count
            out.addAttribute(.foregroundColor, value: c, range: NSRange(location: prefix, length: length))
        }

        func matches(_ token: String, at idx: Int) -> Bool {
            let t = Array(token)
            guard idx + t.count <= n else { return false }
            for (k, ch) in t.enumerated() where chars[idx + k] != ch { return false }
            return true
        }

        while i < n {
            let ch = chars[i]

            // 1. Comments.
            var consumed = false
            for marker in grammar.lineComments where matches(marker, at: i) {
                var j = i
                while j < n && chars[j] != "\n" { j += 1 }
                colour(i, j, theme.codeCommentColor)
                i = j
                consumed = true
                break
            }
            if consumed { continue }

            if let block = grammar.blockComment, matches(block.open, at: i) {
                var j = i + block.open.count
                while j < n && !matches(block.close, at: j) { j += 1 }
                j = min(j + block.close.count, n)
                colour(i, j, theme.codeCommentColor)
                i = j
                continue
            }

            // 2. Strings, honouring backslash escapes.
            if grammar.stringDelimiters.contains(ch) {
                var j = i + 1
                while j < n {
                    if chars[j] == "\\" { j += 2; continue }
                    if chars[j] == ch { j += 1; break }
                    if chars[j] == "\n" && ch != "`" { break }
                    j += 1
                }
                colour(i, min(j, n), theme.codeStringColor)
                i = min(j, n)
                continue
            }

            // 3. Numbers.
            if grammar.supportsNumbers, ch.isNumber {
                var j = i
                while j < n, chars[j].isHexDigit || chars[j] == "." || chars[j] == "x"
                        || chars[j] == "_" || chars[j] == "b" || chars[j] == "o" { j += 1 }
                colour(i, j, theme.codeNumberColor)
                i = j
                continue
            }

            // 4. Identifiers, then keyword and type lookup.
            if ch.isLetter || ch == "_" || ch == "$" || ch == "@" || ch == "#" {
                var j = i
                while j < n, chars[j].isLetter || chars[j].isNumber || chars[j] == "_"
                        || chars[j] == "$" || (j == i && (chars[j] == "@" || chars[j] == "#")) { j += 1 }
                let word = String(chars[i..<j])
                let lookup = grammar.caseInsensitiveKeywords ? word.uppercased() : word
                if grammar.keywords.contains(lookup) {
                    colour(i, j, theme.codeKeywordColor)
                } else if grammar.types.contains(lookup) {
                    colour(i, j, theme.codeTypeColor)
                } else if word.hasPrefix("@") || word.hasPrefix("#") {
                    colour(i, j, theme.codeKeywordColor)
                }
                i = j
                continue
            }

            i += 1
        }
        return out
    }
}
