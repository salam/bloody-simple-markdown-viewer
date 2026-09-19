import Foundation

/// A deliberately small description of a language: enough to colour a code
/// block convincingly, not enough to compile one.
///
/// This exists instead of embedding highlight.js in a JavaScript engine. A
/// viewer's code blocks need to look right, not be compiler-accurate, and a JS
/// engine would cost more than the rest of the app put together.
struct LanguageGrammar: Sendable {
    var keywords: Set<String> = []
    var types: Set<String> = []
    var lineComments: [String] = []
    var blockComment: (open: String, close: String)? = nil
    var stringDelimiters: Set<Character> = ["\"", "'"]
    var supportsNumbers = true
    /// SQL is conventionally written in either case; other languages are not.
    var caseInsensitiveKeywords = false

    static let swift = LanguageGrammar(
        keywords: ["associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init", "inout", "internal", "let", "open", "operator", "private", "protocol", "public", "rethrows", "static", "struct", "subscript", "typealias", "var", "break", "case", "continue", "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return", "switch", "where", "while", "as", "catch", "false", "is", "nil", "super", "self", "Self", "throw", "throws", "true", "try", "async", "await", "actor", "some", "any", "lazy", "weak", "unowned", "mutating", "nonmutating", "override", "final", "indirect", "package", "consuming", "borrowing"],
        types: ["Int", "String", "Double", "Float", "Bool", "Array", "Dictionary", "Set", "Optional", "Result", "Error", "Void", "Character", "Data", "Date", "URL", "Task", "Sendable", "Codable", "Equatable", "Hashable", "Comparable", "Identifiable"],
        lineComments: ["//"], blockComment: ("/*", "*/")
    )

    static let python = LanguageGrammar(
        keywords: ["and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while", "with", "yield", "True", "False", "None", "self", "match", "case"],
        types: ["int", "str", "float", "bool", "list", "dict", "set", "tuple", "bytes", "object", "type", "Any", "Optional", "List", "Dict"],
        lineComments: ["#"]
    )

    static let javascript = LanguageGrammar(
        keywords: ["async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "export", "extends", "finally", "for", "function", "if", "import", "in", "instanceof", "let", "new", "of", "return", "static", "super", "switch", "this", "throw", "try", "typeof", "var", "void", "while", "with", "yield", "true", "false", "null", "undefined", "get", "set"],
        types: ["Array", "Object", "String", "Number", "Boolean", "Promise", "Map", "Set", "Symbol", "Date", "RegExp", "JSON", "Math", "Error"],
        lineComments: ["//"], blockComment: ("/*", "*/"), stringDelimiters: ["\"", "'", "`"]
    )

    static let typescript: LanguageGrammar = {
        var g = javascript
        g.keywords.formUnion(["interface", "type", "enum", "implements", "declare", "namespace", "abstract", "readonly", "public", "private", "protected", "as", "satisfies", "keyof", "infer", "is"])
        g.types.formUnion(["string", "number", "boolean", "any", "unknown", "never", "void", "Record", "Partial", "Readonly", "Pick", "Omit"])
        return g
    }()

    static let go = LanguageGrammar(
        keywords: ["break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct", "switch", "type", "var", "nil", "true", "false", "iota"],
        types: ["string", "int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint64", "float32", "float64", "byte", "rune", "bool", "error", "any"],
        lineComments: ["//"], blockComment: ("/*", "*/"), stringDelimiters: ["\"", "'", "`"]
    )

    static let rust = LanguageGrammar(
        keywords: ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while"],
        types: ["i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "usize", "isize", "f32", "f64", "bool", "char", "str", "String", "Vec", "Option", "Result", "Box", "Arc", "Rc", "HashMap"],
        lineComments: ["//"], blockComment: ("/*", "*/")
    )

    static let clike = LanguageGrammar(
        keywords: ["auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else", "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long", "register", "return", "short", "signed", "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned", "void", "volatile", "while", "class", "public", "private", "protected", "virtual", "template", "typename", "namespace", "using", "new", "delete", "this", "true", "false", "nullptr", "constexpr", "override", "final"],
        types: ["size_t", "uint8_t", "uint32_t", "uint64_t", "int32_t", "int64_t", "bool", "string", "vector", "map", "shared_ptr", "unique_ptr"],
        lineComments: ["//"], blockComment: ("/*", "*/")
    )

    static let java = LanguageGrammar(
        keywords: ["abstract", "assert", "break", "case", "catch", "class", "const", "continue", "default", "do", "else", "enum", "extends", "final", "finally", "for", "goto", "if", "implements", "import", "instanceof", "interface", "native", "new", "package", "private", "protected", "public", "return", "static", "strictfp", "super", "switch", "synchronized", "this", "throw", "throws", "transient", "try", "void", "volatile", "while", "var", "record", "sealed", "true", "false", "null"],
        types: ["int", "long", "short", "byte", "char", "float", "double", "boolean", "String", "Object", "List", "Map", "Set", "Integer", "Double", "Boolean", "Optional", "Stream"],
        lineComments: ["//"], blockComment: ("/*", "*/")
    )

    static let bash = LanguageGrammar(
        keywords: ["if", "then", "else", "elif", "fi", "case", "esac", "for", "select", "while", "until", "do", "done", "in", "function", "time", "coproc", "local", "export", "readonly", "declare", "return", "exit", "source", "alias", "unset", "echo", "cd", "set"],
        lineComments: ["#"], stringDelimiters: ["\"", "'", "`"]
    )

    static let sql = LanguageGrammar(
        keywords: ["SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "ALTER", "DROP", "INDEX", "VIEW", "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "OUTER", "ON", "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "OFFSET", "UNION", "ALL", "DISTINCT", "AS", "AND", "OR", "NOT", "NULL", "IS", "IN", "BETWEEN", "LIKE", "EXISTS", "CASE", "WHEN", "THEN", "ELSE", "END", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "CONSTRAINT", "DEFAULT", "WITH", "RETURNING"],
        types: ["INT", "INTEGER", "BIGINT", "SMALLINT", "VARCHAR", "TEXT", "CHAR", "BOOLEAN", "DATE", "TIMESTAMP", "DECIMAL", "NUMERIC", "FLOAT", "REAL", "JSON", "JSONB", "UUID", "SERIAL"],
        lineComments: ["--"], blockComment: ("/*", "*/"), caseInsensitiveKeywords: true
    )

    static let json = LanguageGrammar(
        keywords: ["true", "false", "null"], lineComments: []
    )

    static let yaml = LanguageGrammar(
        keywords: ["true", "false", "null", "yes", "no", "on", "off"], lineComments: ["#"]
    )

    static let css = LanguageGrammar(
        keywords: ["important", "media", "import", "keyframes", "supports", "font-face", "root", "hover", "focus", "active", "before", "after"],
        lineComments: [], blockComment: ("/*", "*/")
    )

    static let markup = LanguageGrammar(lineComments: [], blockComment: ("<!--", "-->"))

    /// Language hints as they actually appear in the wild, including the
    /// aliases Claude and ChatGPT reach for.
    static func named(_ raw: String?) -> LanguageGrammar? {
        guard let raw else { return nil }
        switch raw.lowercased().trimmingCharacters(in: .whitespaces) {
        case "swift": return .swift
        case "python", "py", "python3": return .python
        case "javascript", "js", "jsx", "node", "mjs": return .javascript
        case "typescript", "ts", "tsx": return .typescript
        case "go", "golang": return .go
        case "rust", "rs": return .rust
        case "c", "h": return .clike
        case "cpp", "c++", "cc", "hpp", "objc", "objective-c", "cs", "csharp", "c#": return .clike
        case "java", "kotlin", "kt", "scala", "groovy": return .java
        case "bash", "sh", "shell", "zsh", "console", "terminal", "fish": return .bash
        case "sql", "postgres", "postgresql", "mysql", "sqlite": return .sql
        case "json", "jsonc", "json5": return .json
        case "yaml", "yml", "toml", "ini", "conf": return .yaml
        case "css", "scss", "sass", "less": return .css
        case "html", "xml", "svg", "vue", "svelte": return .markup
        default: return nil
        }
    }
}
