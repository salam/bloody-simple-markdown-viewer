import AppKit

/// Remembers which lines another program changed while the document was open.
///
/// The point is to make an external edit visible rather than silent. A file
/// being rewritten underneath you — by an editor, a formatter, an agent — is
/// otherwise indistinguishable from the file you were already reading, and the
/// paragraph you were halfway through has quietly become a different one.
///
/// Marks are kept per line of the *current* source and carried forward through
/// later edits, so a change high in the file does not drag every earlier
/// highlight out of place. They live for as long as the document stays open and
/// are gone when it is opened again, which is the whole of their lifetime.
public struct ChangeTracker: Equatable, Sendable {
    /// When the change that produced each line arrived, by zero-based line
    /// index into the current source. Untouched lines are absent.
    public private(set) var changedLines: [Int: Date] = [:]

    public init() {}

    public var isEmpty: Bool { changedLines.isEmpty }

    /// Records an external edit.
    ///
    /// Lines that survived the edit keep the time they were last changed;
    /// lines that are new or different are stamped with `time`.
    public mutating func record(from oldSource: String, to newSource: String, at time: Date = Date()) {
        guard oldSource != newSource else { return }
        apply(from: oldSource, to: newSource, stamping: time)
    }

    /// Carries existing marks through an edit made *here*, without adding any.
    ///
    /// The highlights are a record of what another program did; the reader
    /// typing in source mode is not that. But their edit still moves the lines
    /// underneath, and a mark left on its old line number would drift onto
    /// whatever happens to be there now.
    public mutating func remap(from oldSource: String, to newSource: String) {
        guard !changedLines.isEmpty, oldSource != newSource else { return }
        apply(from: oldSource, to: newSource, stamping: nil)
    }

    private mutating func apply(from oldSource: String, to newSource: String, stamping time: Date?) {
        let old = oldSource.split(separator: "\n", omittingEmptySubsequences: false)
        let new = newSource.split(separator: "\n", omittingEmptySubsequences: false)
        let result = Self.diff(old: old, new: new)

        var carried: [Int: Date] = [:]
        for (oldIndex, newIndex) in result.carried {
            if let existing = changedLines[oldIndex] { carried[newIndex] = existing }
        }
        if let time {
            for index in result.changed { carried[index] = time }
        }
        changedLines = carried
    }

    /// Byte ranges of the highlighted lines in the current source, with the
    /// time each was changed. Adjacent lines from the same edit merge into one
    /// range, so a rewritten paragraph reads as one block rather than stripes.
    public func highlights(in source: String) -> [(range: Range<Int>, time: Date)] {
        guard !changedLines.isEmpty else { return [] }
        let bounds = Self.lineByteRanges(in: source)

        var result: [(range: Range<Int>, time: Date)] = []
        for index in changedLines.keys.sorted() {
            guard index < bounds.count, let time = changedLines[index] else { continue }
            let line = bounds[index]
            if var last = result.last, last.time == time, last.range.upperBound + 1 >= line.lowerBound {
                last.range = last.range.lowerBound..<line.upperBound
                result[result.count - 1] = last
            } else {
                result.append((line, time))
            }
        }
        return result
    }

    // MARK: Colour

    /// Hue for a change, derived from the clock time it happened.
    ///
    /// Same `hh:mm`, same colour: one save shows as a single colour across
    /// every line it touched, and a later one is visibly a different edit.
    /// The golden ratio spreads consecutive minutes to opposite sides of the
    /// wheel, so two edits a minute apart do not look like the same one.
    public static func hue(for time: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        let minuteOfDay = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return (Double(minuteOfDay) * 0.61803398875).truncatingRemainder(dividingBy: 1)
    }

    /// The tint drawn behind a changed line. Saturated enough to tell two edits
    /// apart, faint enough to read the text through.
    public static func color(for time: Date, isDark: Bool) -> NSColor {
        NSColor(hue: CGFloat(hue(for: time)),
                saturation: isDark ? 0.60 : 0.80,
                brightness: isDark ? 0.75 : 1.0,
                alpha: 1)
    }

    /// `hh:mm` of a change, for the tooltip that says which edit this was.
    public static func label(for time: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    // MARK: Diff

    /// Byte range of every line, including an empty last line.
    static func lineByteRanges(in source: String) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start = 0
        var offset = 0
        for byte in source.utf8 {
            offset += 1
            if byte == 0x0A {
                ranges.append(start..<(offset - 1))
                start = offset
            }
        }
        ranges.append(start..<offset)
        return ranges
    }

    /// A line diff, bounded so it cannot blow up on a large file.
    ///
    /// - Returns: the indices in `new` that are new or different, and a map
    ///   from old line index to new line index for the lines that carried over.
    static func diff(old: [Substring], new: [Substring]) -> (changed: Set<Int>, carried: [Int: Int]) {
        var carried: [Int: Int] = [:]

        // Common prefix and suffix first. A typical external edit touches a few
        // lines of a long file, which leaves almost nothing for the expensive
        // part to do.
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] {
            carried[prefix] = prefix
            prefix += 1
        }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] {
            carried[old.count - 1 - suffix] = new.count - 1 - suffix
            suffix += 1
        }

        let oldMiddle = prefix..<(old.count - suffix)
        let newMiddle = prefix..<(new.count - suffix)
        guard !newMiddle.isEmpty || !oldMiddle.isEmpty else { return ([], carried) }

        // Above this the table costs more than the answer is worth, so the
        // whole middle counts as changed. That is honest — a rewrite that large
        // is a rewrite — and it keeps a 16 MB file from allocating gigabytes.
        let budget = 1_000_000
        guard oldMiddle.count * newMiddle.count <= budget else {
            return (Set(newMiddle), carried)
        }

        let rows = oldMiddle.count
        let columns = newMiddle.count
        var table = [Int32](repeating: 0, count: (rows + 1) * (columns + 1))
        for i in stride(from: rows - 1, through: 0, by: -1) {
            for j in stride(from: columns - 1, through: 0, by: -1) {
                let here = i * (columns + 1) + j
                table[here] = old[oldMiddle.lowerBound + i] == new[newMiddle.lowerBound + j]
                    ? table[here + columns + 2] + 1
                    : max(table[here + columns + 1], table[here + 1])
            }
        }

        var matched = Set<Int>()
        var i = 0, j = 0
        while i < rows, j < columns {
            if old[oldMiddle.lowerBound + i] == new[newMiddle.lowerBound + j] {
                carried[oldMiddle.lowerBound + i] = newMiddle.lowerBound + j
                matched.insert(newMiddle.lowerBound + j)
                i += 1
                j += 1
            } else if table[(i + 1) * (columns + 1) + j] >= table[i * (columns + 1) + j + 1] {
                i += 1
            } else {
                j += 1
            }
        }

        return (Set(newMiddle).subtracting(matched), carried)
    }
}

// MARK: - Marking up the text

public extension ChangeTracker {
    /// Marks every run of a rendered document that came from a changed line.
    ///
    /// Reads the `sourceOffset` each run already carries, so it works just as
    /// well on a derived view such as the task filter's output, where the
    /// character offsets bear no relation to the source at all.
    ///
    /// A run is matched on the *span* it covers, not on its start offset alone.
    /// Some constructs report one offset for a whole region — a fenced code
    /// block reports the fence for all of its lines — and matching the start
    /// only would leave a change inside one of them the single place that never
    /// lights up.
    func markRuns(in text: NSMutableAttributedString, source: String) {
        let ranges = highlights(in: source)
        guard !ranges.isEmpty, text.length > 0 else { return }

        // `enumerateAttribute` coalesces adjacent runs sharing a value, so this
        // yields one run per distinct source position, in order. The next one's
        // offset is therefore where this one's span ends.
        var runs: [(range: NSRange, offset: Int)] = []
        text.enumerateAttribute(.sourceOffset,
                                in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let offset = value as? Int { runs.append((range, offset)) }
        }

        let end = source.utf8.count
        for (index, run) in runs.enumerated() {
            let next = index + 1 < runs.count ? runs[index + 1].offset : end
            let span = run.offset..<max(run.offset + 1, next)
            guard let time = Self.time(overlapping: span, in: ranges) else { continue }
            text.addAttribute(.changedAt, value: time, range: run.range)
        }
    }

    /// The same for a plain source view, where byte offsets map straight onto
    /// the text and there are no attributes to read.
    func markSourceRuns(in text: NSMutableAttributedString, source: String) {
        let length = text.length
        for highlight in highlights(in: source) {
            let start = SourceOffset.utf16(forByte: highlight.range.lowerBound, in: source)
            let end = SourceOffset.utf16(forByte: highlight.range.upperBound, in: source)
            guard start < end, end <= length else { continue }
            text.addAttribute(.changedAt, value: highlight.time,
                              range: NSRange(location: start, length: end - start))
        }
    }

    /// Time of the first highlight overlapping a span, by binary search: this
    /// runs once per attribute run of the whole document.
    private static func time(overlapping span: Range<Int>,
                             in ranges: [(range: Range<Int>, time: Date)]) -> Date? {
        var low = 0
        var high = ranges.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let candidate = ranges[middle].range
            if candidate.lowerBound < span.upperBound, span.lowerBound < candidate.upperBound {
                return ranges[middle].time
            }
            if span.upperBound <= candidate.lowerBound { high = middle - 1 } else { low = middle + 1 }
        }
        return nil
    }
}
