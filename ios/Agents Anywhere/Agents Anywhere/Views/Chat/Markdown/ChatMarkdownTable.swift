import SwiftUI
import Textual
import UIKit

struct ChatMarkdownTable: View {
    let rows: [[AttributedString]]
    let columns: [PresentationIntent.TableColumn]

    var body: some View {
        let columnCount = max(1, rows.map(\.count).max() ?? 0)
        ScrollView(.horizontal) {
            grid(columnCount: columnCount)
            // The frame hugs the grid, so a narrow table has no empty panel
            // beside it and a wide one scrolls with its border.
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.primary.opacity(0.12), lineWidth: 0.5).allowsHitTesting(false))
        }
        .appScrollBounceBasedOnSize(axes: .horizontal)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func grid(columnCount: Int) -> some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
            TableGridLayout(columns: columnCount, minWidth: 76, maxWidth: 260) {
                ForEach(rows.indices, id: \.self) { row in
                    ForEach(0..<columnCount, id: \.self) { column in
                        cell(rows[row].indices.contains(column) ? rows[row][column] : AttributedString(),
                            row: row, column: column, columnCount: columnCount)
                    }
                }
            }
        } else {
            let width = legacyColumnWidth
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(0..<columnCount, id: \.self) { column in
                            cell(rows[row].indices.contains(column) ? rows[row][column] : AttributedString(),
                                row: row, column: column, columnCount: columnCount)
                                .frame(width: width, alignment: .topLeading)
                        }
                    }
                    // Each row uses its tallest wrapped cell, not a fixed line
                    // count. All cells keep that same row height and column width.
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .fixedSize(horizontal: true, vertical: true)
        }
    }

    /// iOS 15 uses equal columns. Estimate their shared ideal width from the
    /// displayed characters, within the same 76...260 bounds; Textual still
    /// renders and wraps every cell, including rich text and attachments.
    private var legacyColumnWidth: CGFloat {
        let font = UIFont.preferredFont(forTextStyle: .callout)
        var width: CGFloat = 76
        for (row, cells) in rows.enumerated() {
            let cellFont = row == 0 ? UIFont.boldSystemFont(ofSize: font.pointSize) : font
            for content in cells {
                let text = NSAttributedString(string: String(content.characters), attributes: [.font: cellFont])
                width = max(width, text.size().width + 20)
            }
        }
        return min(260, max(76, ceil(width)))
    }

    private func cell(_ content: AttributedString, row: Int, column: Int, columnCount: Int) -> some View {
        InlineText(String(content.hashValue), parser: ParsedMarkdownText(content: content))
            .textual.textSelection(.enabled)
            .modifier(StreamingGlyphReveal())
            .appFontWeight(row == 0 ? .semibold : .regular)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: alignment(column), vertical: .top))
            .background(row == 0 ? Color.primary.opacity(0.04) : .clear)
            .overlay(alignment: .trailing) {
                if column < columnCount - 1 {
                    Rectangle().fill(.primary.opacity(0.12)).frame(width: 0.5).allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if row < rows.count - 1 {
                    Rectangle().fill(.primary.opacity(0.12)).frame(height: 0.5).allowsHitTesting(false)
                }
            }
    }

    private func alignment(_ column: Int) -> HorizontalAlignment {
        guard columns.indices.contains(column) else { return .leading }
        return switch columns[column].alignment {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        @unknown default: .leading
        }
    }
}

/// Grid measured its rows under a different width than it placed them with
/// inside the horizontal scroll view, so wrapped cells overflowed into the
/// next row and the table was cut short. This layout sizes each column once
/// (ideal width, capped so long cells wrap), gives every row its tallest
/// cell's height and places cells with exactly that size.
@available(iOS 16.0, *)
private struct TableGridLayout: Layout {
    let columns: Int
    let minWidth: CGFloat
    let maxWidth: CGFloat

    struct Metrics {
        var widths: [CGFloat] = []
        var heights: [CGFloat] = []
    }

    func makeCache(subviews: Subviews) -> Metrics? { nil }

    func updateCache(_ cache: inout Metrics?, subviews: Subviews) { cache = nil }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Metrics?) -> CGSize {
        let metrics = measure(subviews, cache: &cache)
        return CGSize(width: metrics.widths.reduce(0, +), height: metrics.heights.reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Metrics?) {
        let metrics = measure(subviews, cache: &cache)
        var y = bounds.minY
        for (row, height) in metrics.heights.enumerated() {
            var x = bounds.minX
            for (column, width) in metrics.widths.enumerated() {
                let index = row * columns + column
                guard subviews.indices.contains(index) else { break }
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(width: width, height: height))
                x += width
            }
            y += height
        }
    }

    private func measure(_ subviews: Subviews, cache: inout Metrics?) -> Metrics {
        if let cache { return cache }
        let rowCount = (subviews.count + columns - 1) / columns
        var metrics = Metrics(widths: Array(repeating: minWidth, count: columns))
        for (index, subview) in subviews.enumerated() {
            let ideal = subview.sizeThatFits(.unspecified).width
            metrics.widths[index % columns] = min(max(metrics.widths[index % columns], ideal), maxWidth)
        }
        metrics.heights = (0..<rowCount).map { row in
            (0..<columns).reduce(0) { tallest, column in
                let index = row * columns + column
                guard subviews.indices.contains(index) else { return tallest }
                let width = metrics.widths[column]
                return max(tallest, subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)).height)
            }
        }
        cache = metrics
        return metrics
    }
}

struct ParsedMarkdownText: MarkupParser {
    let content: AttributedString
    func attributedString(for input: String) throws -> AttributedString { content }
}
