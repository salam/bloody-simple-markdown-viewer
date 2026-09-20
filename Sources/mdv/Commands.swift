import AppKit
import MarkdownCore

/// Flags, pulled out of the argument list before the positional arguments are
/// read, so `mdv tasks --json notes.md` and `mdv tasks notes.md --json` are the
/// same command. Scripts should not have to remember an order.
struct Options {
    var json = false
    var regex = false
    var caseSensitive = false
    var state: String?
    var output: String?
    var dark = false
    var width: Int?
    var height: Int?

    init(arguments: inout [String]) {
        var rest: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--json": json = true
            case "--regex": regex = true
            case "--case": caseSensitive = true
            case "--state":
                index += 1
                state = index < arguments.count ? arguments[index] : nil
            case "--dark": dark = true
            case "--width":
                index += 1
                width = index < arguments.count ? Int(arguments[index]) : nil
            case "--height":
                index += 1
                height = index < arguments.count ? Int(arguments[index]) : nil
            case "-o", "--output":
                index += 1
                output = index < arguments.count ? arguments[index] : nil
            default: rest.append(argument)
            }
            index += 1
        }
        arguments = rest
    }
}

enum CommandError: Error {
    case usage(String)
    case cannotRead(String)
    case noMatch(String)
    case ambiguous(String)
    case failed(String)

    var code: Int32 {
        switch self {
        case .usage: 3
        case .noMatch, .ambiguous: 2
        case .cannotRead, .failed: 1
        }
    }

    var message: String {
        switch self {
        case .usage(let text), .cannotRead(let text), .noMatch(let text),
             .ambiguous(let text), .failed(let text): text
        }
    }

    func report(json: Bool) {
        let text = json
            ? (Output.encode(["ok": false, "error": message]) ?? "{\"ok\":false}") + "\n"
            : "mdv: \(message)\n"
        FileHandle.standardError.write(Data(text.utf8))
    }
}

enum Output {
    static func encode(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value,
                                                     options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    static func emit(_ value: Any) {
        print(encode(value) ?? "{}")
    }
}

enum Commands {
    // MARK: Loading

    private static func url(_ arguments: [String]) throws -> URL {
        guard let path = arguments.first else { throw CommandError.usage("a file is required") }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CommandError.cannotRead("no such file: \(url.path)")
        }
        return url
    }

    private static func load(_ arguments: [String]) throws -> (url: URL, source: String, document: RenderedDocument) {
        let url = try url(arguments)
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            throw CommandError.cannotRead("could not read \(url.lastPathComponent) as UTF-8")
        }
        // Snippets resolve here too, and without a sandbox to negotiate with:
        // a command line tool reads what the person running it can read.
        let resolved = SnippetResolver.expand(source: source, baseURL: url) { included in
            try? String(contentsOf: included, encoding: .utf8)
        }
        // Flattened, because the interactive path hosts live views and those
        // need a run loop that a one-shot command does not have.
        let document = DocumentRenderer(theme: .system, baseURL: url,
                                        attachmentRendering: .flattened)
            .render(expanded: resolved.text, original: source, map: resolved.map)
        return (url, source, document)
    }

    /// 1-based line number for a byte offset, which is what an editor wants.
    private static func line(at offset: Int, in source: String) -> Int {
        var line = 1
        var seen = 0
        for byte in source.utf8 {
            if seen >= offset { break }
            if byte == 0x0A { line += 1 }
            seen += 1
        }
        return line
    }

    // MARK: Commands

    static func open(_ arguments: [String], _ options: Options) throws {
        guard !arguments.isEmpty else { throw CommandError.usage("at least one file is required") }
        let resolved = try arguments.map { try url([$0]) }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "Markdown"] + resolved.map(\.path)
        do { try task.run() } catch {
            throw CommandError.failed("could not launch the viewer: \(error.localizedDescription)")
        }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw CommandError.failed("the viewer is not installed; run `make install`")
        }
        if options.json {
            Output.emit(["ok": true, "opened": resolved.map(\.path)])
        }
    }

    static func outline(_ arguments: [String], _ options: Options) throws {
        let loaded = try load(arguments)
        let entries = loaded.document.outline.map { entry -> [String: Any] in
            ["level": entry.level,
             "title": entry.title,
             "anchor": entry.anchor,
             "line": line(at: entry.sourceOffset, in: loaded.source)]
        }
        if options.json {
            Output.emit(["ok": true, "file": loaded.url.path, "outline": entries])
        } else {
            for entry in loaded.document.outline {
                let indent = String(repeating: "  ", count: max(0, entry.level - 1))
                print("\(line(at: entry.sourceOffset, in: loaded.source))\t\(indent)\(entry.title)")
            }
        }
    }

    static func tasks(_ arguments: [String], _ options: Options) throws {
        let loaded = try load(arguments)
        let wanted = try states(options.state)
        let found = taskList(in: loaded.document, source: loaded.source, states: wanted)

        if options.json {
            Output.emit(["ok": true, "file": loaded.url.path,
                         "tasks": found.map { ["state": name($0.state),
                                               "text": $0.text,
                                               "line": $0.line] }])
        } else {
            for task in found {
                let mark = switch task.state {
                case .checked: "[x]"
                case .inProgress: "[~]"
                case .unchecked: "[ ]"
                }
                print("\(task.line)\t\(mark) \(task.text)")
            }
        }
    }

    static func setTask(_ arguments: [String], _ options: Options, to state: Checkbox.State) throws {
        guard arguments.count >= 2 else {
            throw CommandError.usage("a file and some text to match are required")
        }
        let loaded = try load([arguments[0]])
        let needle = arguments.dropFirst().joined(separator: " ").lowercased()

        let all = taskList(in: loaded.document, source: loaded.source,
                           states: Set(Checkbox.State.allCases))
        let matches = all.filter { $0.text.lowercased().contains(needle) }
        guard !matches.isEmpty else {
            throw CommandError.noMatch("no task matching “\(needle)”")
        }
        guard matches.count == 1 else {
            // Never guess which box to tick.
            let list = matches.map { "line \($0.line): \($0.text)" }.joined(separator: "; ")
            throw CommandError.ambiguous("“\(needle)” matches \(matches.count) tasks — \(list)")
        }

        let task = matches[0]
        guard task.state != state else {
            if options.json {
                Output.emit(["ok": true, "changed": false, "line": task.line,
                             "state": name(state), "text": task.text])
            } else {
                print("already \(name(state)): \(task.text)")
            }
            return
        }
        guard let updated = TaskToggle.apply(state, atSourceOffset: task.offset,
                                             in: loaded.source) else {
            throw CommandError.failed("line \(task.line) carries no checkbox to change")
        }
        do {
            try updated.write(to: loaded.url, atomically: true, encoding: .utf8)
        } catch {
            throw CommandError.failed("could not write \(loaded.url.lastPathComponent): \(error.localizedDescription)")
        }
        if options.json {
            Output.emit(["ok": true, "changed": true, "line": task.line,
                         "state": name(state), "text": task.text])
        } else {
            print("\(task.line): \(name(state)) — \(task.text)")
        }
    }

    static func text(_ arguments: [String], _ options: Options) throws {
        let loaded = try load(arguments)
        let rendered = loaded.document.attributedString.string
        if options.json {
            Output.emit(["ok": true, "file": loaded.url.path, "text": rendered])
        } else {
            print(rendered)
        }
    }

    static func search(_ arguments: [String], _ options: Options) throws {
        guard arguments.count >= 2 else {
            throw CommandError.usage("a file and a pattern are required")
        }
        let loaded = try load([arguments[0]])
        let pattern = arguments.dropFirst().joined(separator: " ")
        let text = loaded.document.attributedString

        let found: [NSRange]
        do {
            found = try DocumentSearch.matches(
                for: pattern, in: text.string,
                options: SearchOptions(isRegularExpression: options.regex,
                                       isCaseSensitive: options.caseSensitive))
        } catch SearchError.invalidPattern(let reason) {
            throw CommandError.usage("bad regular expression: \(reason)")
        }
        guard !found.isEmpty else { throw CommandError.noMatch("no matches for “\(pattern)”") }

        let results = found.map { range -> [String: Any] in
            let offset = text.attribute(.sourceOffset, at: range.location,
                                        effectiveRange: nil) as? Int ?? 0
            return ["line": line(at: offset, in: loaded.source),
                    "text": SourceOffset.line(atByte: offset, in: loaded.source),
                    "match": (text.string as NSString).substring(with: range)]
        }
        if options.json {
            Output.emit(["ok": true, "file": loaded.url.path, "matches": results])
        } else {
            for result in results {
                print("\(result["line"] ?? 0)\t\(result["text"] ?? "")")
            }
        }
    }

    static func pdf(_ arguments: [String], _ options: Options) throws {
        let loaded = try load(arguments)
        let destination = options.output.map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)
        } ?? loaded.url.deletingPathExtension().appendingPathExtension("pdf")

        let resolved = SnippetResolver.expand(source: loaded.source, baseURL: loaded.url) {
            try? String(contentsOf: $0, encoding: .utf8)
        }
        DocumentPrinter.writePDF(source: resolved.text,
                                 title: loaded.url.deletingPathExtension().lastPathComponent,
                                 baseURL: loaded.url,
                                 to: destination)
        guard FileManager.default.fileExists(atPath: destination.path) else {
            throw CommandError.failed("could not write \(destination.path)")
        }
        if options.json {
            Output.emit(["ok": true, "file": loaded.url.path, "pdf": destination.path])
        } else {
            print(destination.path)
        }
    }

    /// Renders to a PNG, the way the window would show it.
    ///
    /// Useful to anything that wants to look at a document rather than read it,
    /// and it is what makes the screenshots in the README reproducible rather
    /// than something somebody once took.
    static func png(_ arguments: [String], _ options: Options) throws {
        let url = try url(arguments)
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            throw CommandError.cannotRead("could not read \(url.lastPathComponent) as UTF-8")
        }
        let width = CGFloat(options.width ?? 920)
        let height = CGFloat(options.height ?? 1500)
        let destination = options.output.map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)
        } ?? url.deletingPathExtension().appendingPathExtension("png")

        var theme = Theme.system
        theme.isDarkBackground = options.dark
        let paper: NSColor = options.dark ? NSColor(white: 0.11, alpha: 1) : .white
        if options.dark {
            theme.textColor = NSColor(white: 0.92, alpha: 1)
            theme.secondaryTextColor = NSColor(white: 0.62, alpha: 1)
            theme.codeBackground = NSColor(white: 1, alpha: 0.06)
        }

        let resolved = SnippetResolver.expand(source: source, baseURL: url) {
            try? String(contentsOf: $0, encoding: .utf8)
        }
        let scroll = MarkdownScrollView(theme: theme)
        scroll.frame = NSRect(x: 0, y: 0, width: width, height: height)
        scroll.backgroundColor = paper
        let view = scroll.markdownTextView
        view.theme = theme
        view.backgroundColor = paper
        // Flattened: attachment-hosted views are never instantiated without a
        // live viewport, and a table would come out as a hole in the page.
        view.display(DocumentRenderer(theme: theme, baseURL: url,
                                      attachmentRendering: .flattened)
            .render(expanded: resolved.text, original: source, map: resolved.map))

        let window = NSWindow(contentRect: scroll.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = scroll
        scroll.layoutSubtreeIfNeeded()
        view.refreshViewport()
        scroll.layoutSubtreeIfNeeded()

        guard let rep = scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds) else {
            throw CommandError.failed("could not make a bitmap")
        }
        scroll.cacheDisplay(in: scroll.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]),
              (try? data.write(to: destination)) != nil else {
            throw CommandError.failed("could not write \(destination.path)")
        }
        if options.json {
            Output.emit(["ok": true, "file": url.path, "png": destination.path,
                         "width": Int(width), "height": Int(height)])
        } else {
            print(destination.path)
        }
    }

    // MARK: Helpers

    /// The same words `--state` accepts, so what a script reads back is what
    /// it can pass in. `Checkbox.State.rawValue` spells one of them differently.
    private static func name(_ state: Checkbox.State) -> String {
        switch state {
        case .checked: "done"
        case .inProgress: "in-progress"
        case .unchecked: "open"
        }
    }

    private struct Task {
        let state: Checkbox.State
        let text: String
        let line: Int
        let offset: Int
    }

    private static func taskList(in document: RenderedDocument, source: String,
                                 states: Set<Checkbox.State>) -> [Task] {
        TaskFilter.items(in: document, states: states).map {
            Task(state: $0.state, text: $0.text,
                 line: line(at: $0.sourceOffset, in: source), offset: $0.sourceOffset)
        }
    }

    private static func states(_ name: String?) throws -> Set<Checkbox.State> {
        switch (name ?? "all").lowercased() {
        case "all": Set(Checkbox.State.allCases)
        case "open", "unchecked", "todo": [.unchecked]
        case "done", "checked": [.checked]
        case "in-progress", "wip", "started", "inprogress": [.inProgress]
        default: throw CommandError.usage(
            "unknown state “\(name ?? "")”; use open, done, in-progress or all")
        }
    }

}
