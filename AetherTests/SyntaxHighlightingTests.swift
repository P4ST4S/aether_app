import SwiftUI
import Testing
@testable import Aether

struct SyntaxHighlightingTests {
    @Test func colorsCCodeWithoutChangingItsContents() throws {
        let code = "#include <stddef.h>\nsize_t my_strlen(const char *str) { return 42; } // comment"
        let highlighted = SyntaxHighlighting.highlight(code, language: "c", colorScheme: .dark)
        #expect(String(highlighted.characters) == code)
        for token in ["#include", "size_t", "my_strlen", "const", "char", "return", "42", "// comment"] {
            let range = try #require(highlighted.range(of: token))
            #expect(highlighted[range].foregroundColor != nil)
        }
        let keyword = try #require(highlighted.range(of: "return"))
        let number = try #require(highlighted.range(of: "42"))
        let comment = try #require(highlighted.range(of: "// comment"))
        #expect(highlighted[keyword].foregroundColor != highlighted[number].foregroundColor)
        #expect(highlighted[keyword].foregroundColor != highlighted[comment].foregroundColor)
    }

    @Test func stringsProtectURLsAndCommentMarkers() throws {
        let code = #"const url = "https://example.com/#anchor"; // return 42"#
        let highlighted = SyntaxHighlighting.highlight(code, language: "typescript", colorScheme: .dark)
        let string = try #require(highlighted.range(of: #""https://example.com/#anchor""#))
        let comment = try #require(highlighted.range(of: "// return 42"))
        #expect(highlighted[string].foregroundColor != nil)
        #expect(highlighted[comment].foregroundColor != nil)
        #expect(highlighted[string].foregroundColor != highlighted[comment].foregroundColor)
    }

    @Test func multilineCommentsKeepOneColorAndStreamingStringsRemainColored() throws {
        let code = "/* return 42;\n\"not a string\" */\nconst char *name = \"Bonjour 🧠"
        let highlighted = SyntaxHighlighting.highlight(code, language: "c", colorScheme: .dark)
        let comment = try #require(highlighted.range(of: "/* return 42;\n\"not a string\" */"))
        let string = try #require(highlighted.range(of: "\"Bonjour 🧠"))
        #expect(highlighted[comment].foregroundColor != nil)
        #expect(highlighted[string].foregroundColor != nil)
        #expect(highlighted[comment].foregroundColor != highlighted[string].foregroundColor)
    }

    @Test func handlesLanguageAliasesAndBothAppearances() throws {
        for language in ["C++", "cpp", "csharp", "cs", "javascript", "js", "python", "py", "swift", "rust", "go", "sql"] {
            let code = "return 42"
            let dark = SyntaxHighlighting.highlight(code, language: language, colorScheme: .dark)
            let light = SyntaxHighlighting.highlight(code, language: language, colorScheme: .light)
            let darkRange = try #require(dark.range(of: "42"))
            let lightRange = try #require(light.range(of: "42"))
            #expect(dark[darkRange].foregroundColor != nil)
            #expect(light[lightRange].foregroundColor != nil)
            #expect(dark[darkRange].foregroundColor != light[lightRange].foregroundColor)
        }
    }

    @Test func unsupportedLanguagesAndLargeBlocksRemainReadable() {
        let code = "return 42"
        let unsupported = SyntaxHighlighting.highlight(code, language: "plain", colorScheme: .dark)
        #expect(String(unsupported.characters) == code)
        #expect(unsupported.foregroundColor == nil)
        let large = String(repeating: "return 42;\n", count: 10_000)
        let highlighted = SyntaxHighlighting.highlight(large, language: "c", colorScheme: .dark)
        #expect(String(highlighted.characters) == large)
        #expect(highlighted.foregroundColor == nil)
    }
}
