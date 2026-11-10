import SwiftUI

struct MarkdownBlock: Identifiable {
    let id: Int
    let text: String
    let language: String?
}

enum MarkdownParser {
    static func blocks(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var lines: [String] = []
        var language: String?
        var start = 0
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if !lines.isEmpty { blocks.append(MarkdownBlock(id: start, text: lines.joined(separator: "\n"), language: language)) }
                lines = []
                language = language == nil ? String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces) : nil
                start = index + 1
            } else {
                if lines.isEmpty { start = index }
                lines.append(line)
            }
        }
        if !lines.isEmpty { blocks.append(MarkdownBlock(id: start, text: lines.joined(separator: "\n"), language: language)) }
        return blocks
    }
}

struct MarkdownContent: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(MarkdownParser.blocks(text)) { block in
                if let language = block.language {
                    CodeBlock(code: block.text, language: language)
                } else {
                    MarkdownProse(text: block.text)
                }
            }
        }
    }
}

private struct ProseLine: Identifiable {
    let id: Int
    let text: String
}

private struct MarkdownProse: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(text.components(separatedBy: "\n").enumerated().map { ProseLine(id: $0.offset, text: $0.element) }) { line in
                let trimmed = line.text.trimmingCharacters(in: .whitespaces)
                let headingCount = trimmed.prefix { $0 == "#" }.count
                if trimmed.isEmpty {
                    Spacer().frame(height: 5)
                } else if (1...6).contains(headingCount), trimmed.dropFirst(headingCount).hasPrefix(" ") {
                    inline(String(trimmed.dropFirst(headingCount + 1)))
                        .font(headingCount == 1 ? .title2 : headingCount == 2 ? .title3 : .headline)
                        .fontWeight(.semibold).padding(.top, 5)
                        .accessibilityAddTraits(.isHeader)
                } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("•").foregroundStyle(.secondary)
                        inline(String(trimmed.dropFirst(2)))
                    }.padding(.leading, 4)
                } else if trimmed.hasPrefix("> ") {
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2).fill(.indigo.opacity(0.5)).frame(width: 3)
                        inline(String(trimmed.dropFirst(2))).foregroundStyle(.secondary)
                    }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 3)
                } else if ["---", "***", "___"].contains(trimmed) {
                    Divider().padding(.vertical, 5)
                } else {
                    inline(line.text)
                }
            }
        }.textSelection(.enabled).lineSpacing(4)
    }
    private func inline(_ text: String) -> Text {
        Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
    }
}

struct CodeBlock: View {
    let code: String
    let language: String
    @State private var copied = false
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "Code" : language).font(.caption)
                Spacer()
                Button {
                    Clipboard.copy(code)
                    copied = true
                } label: { Label(copied ? "Copied" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(.borderless).font(.caption)
            }.foregroundStyle(.secondary).padding(10)
            Divider()
            ScrollView(.horizontal) {
                Text(SyntaxHighlighting.highlight(code, language: language, colorScheme: colorScheme))
                    .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(.primary.opacity(0.045), in: .rect(cornerRadius: 12))
        .onChange(of: code) { copied = false }
    }
}

