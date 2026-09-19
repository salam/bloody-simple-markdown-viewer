import Foundation

/// A LaTeX formula found in the source.
public struct MathSpan: Equatable, Sendable {
    public let latex: String
    public let isDisplay: Bool
    /// UTF-16 offset of the formula in the original source.
    public let sourceOffset: Int
}

/// Lifts LaTeX out of the source before the Markdown parser sees it.
///
/// This has to happen before parsing, not after. cmark has no idea what math
/// is, so `$a_i b_j$` reaches it as ordinary text containing two underscores
/// and comes back with `_i b_` turned into emphasis, quietly corrupting the
/// formula. Each span is replaced by an inert placeholder built from Unicode
/// private-use characters, which no Markdown construct can claim, and the
/// renderer swaps the formulas back in when it walks the tree.
///
/// Delimiters cover both the GitHub convention and what Claude and ChatGPT
/// actually emit, which are not the same.
public enum MathExtractor {
    static let openMarker: Character = "\u{E000}"
    static let closeMarker: Character = "\u{E001}"

    public struct Result {
        public let text: String
        public let spans: [MathSpan]
    }

    public static func extract(from source: String) -> Result {
        let ns = source as NSString
        var spans: [MathSpan] = []
        var output = ""
        var index = 0

        func placeholder(for span: MathSpan) -> String {
            spans.append(span)
            return "\(openMarker)\(spans.count - 1)\(closeMarker)"
        }

        while index < ns.length {
            let character = ns.character(at: index)

            // Fenced ```math blocks are left alone; the code-block path renders them.
            if character == UInt16(UnicodeScalar("\\").value), index + 1 < ns.length {
                let next = Character(UnicodeScalar(ns.character(at: index + 1))!)
                // \( ... \) and \[ ... \], the LaTeX-standard delimiters that
                // ChatGPT commonly emits in place of dollar signs.
                if next == "(" || next == "[" {
                    let closing = next == "(" ? "\\)" : "\\]"
                    let searchRange = NSRange(location: index + 2, length: ns.length - index - 2)
                    let end = ns.range(of: closing, options: [], range: searchRange)
                    if end.location != NSNotFound {
                        let body = ns.substring(with: NSRange(location: index + 2,
                                                              length: end.location - index - 2))
                        output += placeholder(for: MathSpan(latex: body.trimmingCharacters(in: .whitespacesAndNewlines),
                                                            isDisplay: next == "[",
                                                            sourceOffset: index))
                        index = end.location + end.length
                        continue
                    }
                }
                // An escaped dollar is literal, not a delimiter.
                if next == "$" {
                    output += "\\$"
                    index += 2
                    continue
                }
            }

            if character == UInt16(UnicodeScalar("$").value) {
                let isDisplay = index + 1 < ns.length
                    && ns.character(at: index + 1) == UInt16(UnicodeScalar("$").value)
                // GitHub's $`...`$ form, which exists to avoid ambiguity with
                // a literal dollar sign.
                let isBacktickForm = !isDisplay && index + 1 < ns.length
                    && ns.character(at: index + 1) == UInt16(UnicodeScalar("`").value)

                let opener = isDisplay ? "$$" : (isBacktickForm ? "$`" : "$")
                let closer = isDisplay ? "$$" : (isBacktickForm ? "`$" : "$")
                let bodyStart = index + opener.count
                guard bodyStart < ns.length else { break }

                let searchRange = NSRange(location: bodyStart, length: ns.length - bodyStart)
                let end = ns.range(of: closer, options: [], range: searchRange)
                if end.location != NSNotFound {
                    let body = ns.substring(with: NSRange(location: bodyStart,
                                                          length: end.location - bodyStart))
                    // A lone dollar in prose ("costs $5 and $6") is not math:
                    // require non-empty content without a newline for inline.
                    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Pandoc's rule for telling math from prices: a closing
                    // delimiter immediately followed by a digit means this was
                    // currency, as in "costs $5 and $6".
                    let afterCloser = end.location + end.length
                    let followedByDigit = afterCloser < ns.length
                        && Character(UnicodeScalar(ns.character(at: afterCloser))!).isNumber

                    let plausible = !trimmed.isEmpty
                        && (isDisplay || isBacktickForm || !body.contains("\n"))
                        && (isDisplay || isBacktickForm || !body.hasPrefix(" "))
                        && (isDisplay || isBacktickForm || !body.hasSuffix(" "))
                        && (isDisplay || isBacktickForm || !followedByDigit)
                    if plausible {
                        output += placeholder(for: MathSpan(latex: trimmed,
                                                            isDisplay: isDisplay,
                                                            sourceOffset: index))
                        index = end.location + end.length
                        continue
                    }
                }
            }

            output += ns.substring(with: NSRange(location: index, length: 1))
            index += 1
        }

        return Result(text: output, spans: spans)
    }

    /// Splits text containing placeholders into literal runs and formula indices.
    public enum Piece: Equatable {
        case text(String)
        case math(Int)
    }

    public static func split(_ text: String) -> [Piece] {
        guard text.contains(openMarker) else {
            return text.isEmpty ? [] : [.text(text)]
        }
        var pieces: [Piece] = []
        var buffer = ""
        var digits = ""
        var inPlaceholder = false

        for character in text {
            if character == openMarker {
                if !buffer.isEmpty { pieces.append(.text(buffer)); buffer = "" }
                inPlaceholder = true
                digits = ""
            } else if character == closeMarker, inPlaceholder {
                if let index = Int(digits) { pieces.append(.math(index)) }
                inPlaceholder = false
            } else if inPlaceholder {
                digits.append(character)
            } else {
                buffer.append(character)
            }
        }
        if !buffer.isEmpty { pieces.append(.text(buffer)) }
        return pieces
    }
}
