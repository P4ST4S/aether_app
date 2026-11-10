import SwiftUI

// A single lexical pass keeps comment markers inside strings from overriding string colors.
enum SyntaxHighlighting {
    private enum Style: Int, CaseIterable, Sendable {
        case comment, string, directive, number, keyword, type, function

        func color(in scheme: ColorScheme) -> Color {
            switch (self, scheme == .dark) {
            case (.comment, true): Color(red: 0.55, green: 0.69, blue: 0.59)
            case (.comment, false): Color(red: 0.28, green: 0.40, blue: 0.32)
            case (.string, true): Color(red: 1.00, green: 0.69, blue: 0.51)
            case (.string, false): Color(red: 0.64, green: 0.25, blue: 0.09)
            case (.directive, true): Color(red: 0.80, green: 0.65, blue: 1.00)
            case (.directive, false): Color(red: 0.44, green: 0.24, blue: 0.65)
            case (.number, true): Color(red: 0.95, green: 0.79, blue: 0.46)
            case (.number, false): Color(red: 0.54, green: 0.34, blue: 0.05)
            case (.keyword, true): Color(red: 1.00, green: 0.47, blue: 0.74)
            case (.keyword, false): Color(red: 0.57, green: 0.14, blue: 0.49)
            case (.type, true): Color(red: 0.49, green: 0.86, blue: 0.88)
            case (.type, false): Color(red: 0.02, green: 0.40, blue: 0.45)
            case (.function, true): Color(red: 0.55, green: 0.74, blue: 1.00)
            case (.function, false): Color(red: 0.15, green: 0.32, blue: 0.70)
            }
        }
    }

    private struct Grammar: Sendable {
        let expression: NSRegularExpression
        let styles: [Style]
    }

    private static let aliases = [
        "c++": "cpp", "cc": "cpp", "cxx": "cpp", "h": "c", "hpp": "cpp",
        "c#": "csharp", "cs": "csharp", "objc": "objective-c", "objectivec": "objective-c",
        "js": "javascript", "jsx": "javascript", "ts": "typescript", "tsx": "typescript",
        "py": "python", "rs": "rust", "kt": "kotlin", "kts": "kotlin",
        "sh": "shell", "bash": "shell", "zsh": "shell", "shellscript": "shell",
        "yml": "yaml", "rb": "ruby", "html": "xml"
    ]

    private static let languages = [
        "", "c", "cpp", "csharp", "objective-c", "swift", "javascript", "typescript",
        "python", "rust", "go", "kotlin", "java", "json", "shell", "sql", "xml", "css",
        "ruby", "yaml", "toml"
    ]

    private static let keywords = "actor|and|as|asm|assert|async|await|auto|begin|break|case|catch|class|const|constexpr|continue|crate|defer|def|default|delete|do|dyn|elif|else|end|enum|except|export|extends|extern|false|False|final|finally|fn|for|foreach|from|func|function|global|goto|guard|if|impl|import|in|include|inline|instanceof|interface|internal|is|lambda|let|match|mod|module|mut|namespace|new|nil|None|nonisolated|not|null|nullptr|of|operator|or|override|package|pass|private|protected|protocol|pub|public|raise|readonly|ref|register|repeat|requires|return|self|sizeof|some|static|struct|super|switch|template|then|this|throw|throws|trait|true|True|try|type|typedef|typename|union|unsafe|use|using|val|var|virtual|volatile|when|where|while|with|yield"
    private static let sqlKeywords = "select|from|where|join|left|right|inner|outer|on|as|and|or|not|in|is|null|true|false|insert|into|values|update|set|delete|create|alter|drop|table|index|primary|key|foreign|references|unique|default|order|by|group|having|limit|offset|distinct|union|all|case|when|then|else|end|with|returning|asc|desc|begin|commit|rollback|return"
    private static let types = "bool|boolean|byte|char|double|float|int|long|short|signed|unsigned|void|size_t|ssize_t|ptrdiff_t|wchar_t|int8_t|int16_t|int32_t|int64_t|uint8_t|uint16_t|uint32_t|uint64_t|u8|u16|u32|u64|usize|i8|i16|i32|i64|isize|f32|f64|str|string|String|Int|Double|Float|Bool|Character|Array|Dictionary|Set|Optional|Self|Any|AnyObject"

    // Compile once per language, rather than once for every streamed text update.
    private static let grammars: [String: Grammar] = Dictionary(uniqueKeysWithValues: languages.compactMap { language in
        var patterns: [(Style, String)] = []
        if ["python", "shell", "ruby", "yaml", "toml"].contains(language) {
            patterns.append((.comment, #"#[^\n]*"#))
        } else if language == "sql" {
            patterns.append((.comment, #"--[^\n]*|/\*[\s\S]*?(?:\*/|\z)"#))
        } else if language == "xml" {
            patterns.append((.comment, #"<!--[\s\S]*?(?:-->|\z)"#))
        } else if language != "json" {
            patterns.append((.comment, #"//[^\n]*|/\*[\s\S]*?(?:\*/|\z)"#))
        }
        let strings = #""""[\s\S]*?(?:"""|\z)|'''[\s\S]*?(?:'''|\z)|"(?:\\[\s\S]|[^"\\])*(?:"|\z)|'(?:\\[^\n]|[^'\\\n])*'|`(?:\\[\s\S]|[^`\\])*(?:`|\z)"#
        patterns.append((.string, strings))
        if ["", "c", "cpp", "csharp", "objective-c", "swift"].contains(language) {
            patterns.append((.directive, #"(?m)^[\t ]*#[\t ]*[A-Za-z_]\w*"#))
        } else if language == "xml" {
            patterns.append((.directive, #"</?[A-Za-z][\w:.-]*|/?>"#))
        }
        patterns.append((.number, #"\b(?:0[xX][0-9a-fA-F]+|0[bB][01]+|[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)[uUlLfF]*\b"#))
        patterns.append((.keyword, language == "sql" ? "(?i:\\b(?:\(sqlKeywords))\\b)" : "\\b(?:\(keywords))\\b"))
        patterns.append((.type, "\\b(?:\(types))\\b"))
        patterns.append((.function, #"\b[A-Za-z_]\w*(?=\s*\()"#))
        let combined = patterns.map { "(\($0.1))" }.joined(separator: "|")
        guard let expression = try? NSRegularExpression(pattern: combined) else {
            assertionFailure("Invalid built-in syntax grammar: \(language)")
            return nil
        }
        return (language, Grammar(expression: expression, styles: patterns.map(\.0)))
    })

    static func highlight(_ code: String, language: String, colorScheme: ColorScheme) -> AttributedString {
        var result = AttributedString(code)
        let label = language.split(whereSeparator: \.isWhitespace).first.map(String.init)?.lowercased() ?? ""
        let normalized = aliases[label] ?? label
        // Large snippets remain selectable/copyable without running a lexer on every token update.
        guard code.utf8.count < 100_000, let grammar = grammars[normalized] else { return result }
        for match in grammar.expression.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
            guard let group = (1..<match.numberOfRanges).first(where: { match.range(at: $0).location != NSNotFound }),
                  let range = Range(match.range, in: code),
                  let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[lower..<upper].foregroundColor = grammar.styles[group - 1].color(in: colorScheme)
        }
        return result
    }
}
