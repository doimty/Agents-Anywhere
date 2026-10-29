import SwiftUI

/// Small block-level Markdown renderer for the iOS 15 client.
///
/// Foundation's `AttributedString(markdown:)` only styles inline syntax, so
/// headings, lists, quotes, rules and tables would otherwise appear with their
/// raw markers. This parser keeps those blocks, and delegates inline styling
/// (emphasis, inline code, links) back to Foundation.
enum LegacyMarkdown {
    enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(String)
        case numbered(index: Int, text: String)
        case quote(String)
        case code(String)
        case table(header: [String], rows: [[String]])
        case rule
    }

    struct IdentifiedBlock: Identifiable {
        let id: Int
        let block: Block
    }

    private static let options: AttributedString.MarkdownParsingOptions = {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.allowsExtendedAttributes = false
        return options
    }()

    static func blocks(for text: String) -> [IdentifiedBlock] {
        var builder = Parser()
        builder.consume(text)
        return builder.finish()
    }

    static func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private struct Parser {
        private var raw: [Block] = []
        private var paragraph: [String] = []
        private var code: [String] = []
        private var inCode = false

        mutating func consume(_ text: String) {
            let lines = text.components(separatedBy: "\n")
            var index = 0
            while index < lines.count {
                let line = lines[index]
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if trimmed.hasPrefix("```") {
                    if inCode {
                        raw.append(.code(code.joined(separator: "\n")))
                        code.removeAll(keepingCapacity: true)
                    } else {
                        flushParagraph()
                    }
                    inCode.toggle()
                    index += 1
                    continue
                }
                if inCode {
                    code.append(line)
                    index += 1
                    continue
                }

                if trimmed.isEmpty {
                    flushParagraph()
                    index += 1
                    continue
                }

                if let level = headingLevel(trimmed) {
                    flushParagraph()
                    raw.append(.heading(level: level, text: String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)))
                    index += 1
                    continue
                }

                if isRule(trimmed) {
                    flushParagraph()
                    raw.append(.rule)
                    index += 1
                    continue
                }

                if index + 1 < lines.count, isTableSeparator(lines[index + 1]), trimmed.contains("|") {
                    flushParagraph()
                    let header = cells(trimmed)
                    var rows: [[String]] = []
                    index += 2
                    while index < lines.count {
                        let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                        guard candidate.contains("|"), !candidate.isEmpty else { break }
                        rows.append(cells(candidate))
                        index += 1
                    }
                    raw.append(.table(header: header, rows: rows))
                    continue
                }

                if trimmed.hasPrefix(">") {
                    flushParagraph()
                    raw.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
                    index += 1
                    continue
                }

                if let item = bulletItem(trimmed) {
                    flushParagraph()
                    raw.append(.bullet(item))
                    index += 1
                    continue
                }

                if let item = numberedItem(trimmed) {
                    flushParagraph()
                    raw.append(.numbered(index: item.0, text: item.1))
                    index += 1
                    continue
                }

                paragraph.append(line)
                index += 1
            }

            if inCode {
                raw.append(.code(code.joined(separator: "\n")))
                code.removeAll(keepingCapacity: true)
            }
            flushParagraph()
        }

        mutating func finish() -> [IdentifiedBlock] {
            raw.enumerated().map { IdentifiedBlock(id: $0.offset, block: $0.element) }
        }

        private mutating func flushParagraph() {
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .newlines)
            paragraph.removeAll(keepingCapacity: true)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            raw.append(.paragraph(text))
        }

        private func headingLevel(_ line: String) -> Int? {
            let hashes = line.prefix { $0 == "#" }.count
            guard (1 ... 6).contains(hashes) else { return nil }
            let rest = line.dropFirst(hashes)
            guard rest.first == " " else { return nil }
            return hashes
        }

        private func isRule(_ line: String) -> Bool {
            let compact = line.replacingOccurrences(of: " ", with: "")
            guard compact.count >= 3 else { return false }
            return compact.allSatisfy { $0 == "-" || $0 == "*" || $0 == "_" }
        }

        private func isTableSeparator(_ line: String) -> Bool {
            let compact = line.trimmingCharacters(in: .whitespaces)
            guard compact.contains("-"), compact.contains("|") else { return false }
            return compact.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }
        }

        private func cells(_ line: String) -> [String] {
            var value = line.trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("|") { value.removeFirst() }
            if value.hasSuffix("|") { value.removeLast() }
            return value.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }

        private func bulletItem(_ line: String) -> String? {
            for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
                return String(line.dropFirst(marker.count))
            }
            return nil
        }

        private func numberedItem(_ line: String) -> (Int, String)? {
            let digits = line.prefix { $0.isNumber }
            guard !digits.isEmpty, let number = Int(digits) else { return nil }
            let rest = line.dropFirst(digits.count)
            guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
            return (number, String(rest.dropFirst(2)))
        }
    }
}

struct LegacyMarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(LegacyMarkdown.blocks(for: text)) { item in
                block(item.block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func block(_ block: LegacyMarkdown.Block) -> some View {
        switch block {
        case let .heading(level, text):
            Text(LegacyMarkdown.attributed(text))
                .font(headingFont(level))
                .fontWeight(.semibold)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case let .paragraph(text):
            Text(LegacyMarkdown.attributed(text))
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case let .bullet(text):
            HStack(alignment: .top, spacing: 6) {
                Text("•").font(.body).foregroundColor(.secondary)
                Text(LegacyMarkdown.attributed(text))
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case let .numbered(index, text):
            HStack(alignment: .top, spacing: 6) {
                Text("\(index).").font(.body.monospacedDigit()).foregroundColor(.secondary)
                Text(LegacyMarkdown.attributed(text))
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case let .quote(text):
            HStack(alignment: .top, spacing: 8) {
                Capsule().fill(Color.primary.opacity(0.18)).frame(width: 3)
                Text(LegacyMarkdown.attributed(text))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case let .code(code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code.isEmpty ? " " : code)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(Color(uiColor: .tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        case let .table(header, rows):
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    tableRow(header, isHeader: true)
                    Divider()
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        tableRow(row, isHeader: false)
                    }
                }
                .padding(10)
            }
            .background(Color(uiColor: .tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .rule:
            Divider()
        }
    }

    private func tableRow(_ cells: [String], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(LegacyMarkdown.attributed(cell))
                    .font(isHeader ? .footnote.weight(.semibold) : .footnote)
                    .frame(minWidth: 48, alignment: .leading)
            }
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .subheadline
        }
    }
}
