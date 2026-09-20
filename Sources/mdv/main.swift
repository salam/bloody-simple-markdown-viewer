import Foundation

// A command line for the viewer, shaped for programs rather than people.
//
// Agents are a large part of who writes Markdown now, and a checklist an agent
// maintains is exactly the kind of file this viewer is for. Everything here is
// scriptable, every command takes --json, and the exit code says what happened
// without anyone having to read the output.
//
// No argument-parsing dependency: the whole grammar is `mdv <command> <file>
// [options]`, and a package for that would be larger than the thing it parses.

let usage = """
mdv — a command line for A Bloody Simple Markdown Viewer

USAGE
  mdv <command> [arguments] [--json]

COMMANDS
  open <file>...              Open in the viewer. Several files share one window.
  outline <file>              Headings, with their line numbers.
  tasks <file> [--state S]    Task items. S is open, done, in-progress or all.
  check <file> <text>         Tick the task whose text matches.
  uncheck <file> <text>       Untick it.
  start <file> <text>         Mark it in progress.
  text <file>                 The document as the viewer renders it, in plain text.
  search <file> <pattern>     Find matches. Add --regex for a pattern.
  pdf <file> [-o out.pdf]     Render to PDF.
  png <file> [-o out.png]     Render to a PNG, as the window would show it.

OPTIONS
  --json                      Machine-readable output. Available on every command.
  --state <s>                 open | done | in-progress | all   (default: all)
  --regex                     Treat the search pattern as a regular expression.
  --case                      Match case when searching.
  -o, --output <path>         Where to write, for pdf and png.
  --dark                      Render dark, for png.
  --width N, --height N       Pixel size, for png. Defaults to 920x1500.

EXIT CODES
  0  did what was asked          2  nothing matched
  1  could not do it             3  usage was wrong

The matching commands take a substring of the task's text, case-insensitive.
It has to match exactly one task, so a script cannot tick the wrong box.
"""

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    print(usage)
    exit(3)
}
arguments.removeFirst()

var options = Options(arguments: &arguments)

do {
    switch command {
    case "open":            try Commands.open(arguments, options)
    case "outline":         try Commands.outline(arguments, options)
    case "tasks":           try Commands.tasks(arguments, options)
    case "check":           try Commands.setTask(arguments, options, to: .checked)
    case "uncheck":         try Commands.setTask(arguments, options, to: .unchecked)
    case "start":           try Commands.setTask(arguments, options, to: .inProgress)
    case "text":            try Commands.text(arguments, options)
    case "search":          try Commands.search(arguments, options)
    case "pdf":             try Commands.pdf(arguments, options)
    case "png":             try Commands.png(arguments, options)
    case "-h", "--help", "help":
        print(usage)
    case "--version", "version":
        print("mdv 0.1.0")
    default:
        throw CommandError.usage("unknown command “\(command)”")
    }
} catch let error as CommandError {
    error.report(json: options.json)
    exit(error.code)
} catch {
    FileHandle.standardError.write(Data(("mdv: \(error.localizedDescription)\n").utf8))
    exit(1)
}
