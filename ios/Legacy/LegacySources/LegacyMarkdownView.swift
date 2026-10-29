import SwiftUI

/// Minimal Markdown for the iOS 15 client.
///
/// `AttributedString(markdown:)` exists on iOS 15, so prose (emphasis, inline
/// code, links, lists as text) renders natively without Textual. Fenced code is
/// split out first and drawn in a horizontal scroller so it keeps its shape.
enum LegacyMarkdown {
    struct Block: Identifiable {
        enum Kind {
            case prose(AttributedString)
            case code(String)
        }

        let id: Int
        let kind: Kind
    }

    private static let options: AttributedString.MarkdownParsingOptions = {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.allowsExtendedAttributes = false
        return options
    }()

    static func blocks(for text: String) -> [Block] {
        var blocks: [Block] = []
        var buffer: [String] = []
        var isCode = false

        func flushProse() {
            let prose = buffer.joined(separator: "\n").trimmingCharacters(in: .newlines)
            buffer.removeAll(keepingCapacity: true)
            guard !prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            blocks.append(Block(id: blocks.count, kind: .prose(attributed(prose))))
        }

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                if isCode {
                    blocks.append(Block(id: blocks.count, kind: .code(buffer.joined(separator: "\n"))))
                    buffer.removeAll(keepingCapacity: true)
                } else {
                    flushProse()
                }
                isCode.toggle()
                continue
            }
            buffer.append(line)
        }

        if isCode {
            // An unterminated fence still shows what streamed in.
            blocks.append(Block(id: blocks.count, kind: .code(buffer.joined(separator: "\n"))))
        } else {
            flushProse()
        }
        return blocks
    }

    static func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

struct LegacyMarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(LegacyMarkdown.blocks(for: text)) { block in
                switch block.kind {
                case .prose(let attributed):
                    Text(attributed)
                        .font(.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(let code):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(code.isEmpty ? " " : code)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .background(Color(uiColor: .tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
