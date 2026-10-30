import SwiftUI

/// The same styled children and margin preferences as BlockVStackLayout, using
/// SwiftUI's pre-Layout child collection on iOS 15. Parsing/block identity stays shared.
struct PortableBlockStackRoot: _VariadicView.MultiViewRoot {
  let textAlignment: TextAlignment
  func body(children: _VariadicView.Children) -> some View {
    PortableBlockStackChildren(children: children, textAlignment: textAlignment)
  }
}

private struct PortableBlockStackChildren: View {
  let children: _VariadicView.Children
  let textAlignment: TextAlignment
  @Environment(\.listItemSpacingEnabled) private var listSpacingEnabled
  @Environment(\.resolvedListItemSpacing) private var listSpacing
  @State private var spacings: [AnyHashable: StructuredText.BlockSpacing] = [:]
  @State private var alignments: [AnyHashable: TextAlignment] = [:]

  var body: some View {
    let values = Array(children)
    VStack(alignment: horizontal(textAlignment), spacing: 0) {
      ForEach(values.indices, id: \.self) { index in
        let child = values[index]
        child
          .frame(maxWidth: .infinity, alignment: Alignment(horizontal: horizontal(alignments[child.id] ?? textAlignment), vertical: .top))
          .padding(.top, gap(before: index, values: values))
          .onPreferenceChange(StructuredText.BlockSpacingKey.self) { value in
            let spacing = listSpacingEnabled ? listSpacing : value
            if spacings[child.id] != spacing { spacings[child.id] = spacing }
          }
          .onPreferenceChange(StructuredText.BlockAlignmentKey.self) { value in
            if alignments[child.id] != value { alignments[child.id] = value }
          }
      }
    }
  }

  private func gap(before index: Int, values: [_VariadicView.Children.Element]) -> CGFloat {
    guard index > 0 else { return 0 }
    let previous = spacings[values[index - 1].id]?.bottom
    let current = spacings[values[index].id]?.top
    return [previous, current].compactMap { $0 }.max() ?? 8
  }

  private func horizontal(_ alignment: TextAlignment) -> HorizontalAlignment {
    switch alignment {
    case .leading: return .leading
    case .center: return .center
    case .trailing: return .trailing
    }
  }
}

extension View {
  @ViewBuilder
  func textualBlockAlignment(_ alignment: TextAlignment) -> some View {
    if #available(iOS 16, macOS 13, tvOS 16, watchOS 9, *) {
      layoutValue(key: StructuredText.BlockAlignmentKey.self, value: alignment)
    } else {
      preference(key: StructuredText.BlockAlignmentKey.self, value: alignment)
    }
  }
}

/// A pre-Grid label for the original table styles. Cell styles, bounds anchors,
/// alignment and equal column widths are shared with the modern table label.
extension StructuredText {
  struct PortableTableLabel: View {
    let rows: [[AttributedString]]
    let columns: [PresentationIntent.TableColumn]
    let spacing: TableCell.Spacing
    @State private var widths: [Int: CGFloat] = [:]
    @State private var heights: [Int: CGFloat] = [:]

    var body: some View {
      VStack(alignment: .leading, spacing: spacing.vertical ?? 8) {
        ForEach(rows.indices, id: \.self) { row in
          HStack(alignment: .top, spacing: spacing.horizontal ?? 8) {
            ForEach(rows[row].indices, id: \.self) { column in
              cell(row: row, column: column)
            }
          }
        }
      }
    }

    private func cell(row: Int, column: Int) -> some View {
      // `[...]` on AttributedString resolves to the unbounded-range overload,
      // which is not a RangeExpression here; slice with explicit indices.
      let source = rows[row][column]
      let content: AttributedSubstring = source[source.startIndex..<source.endIndex]
      let label = TableCell(content, row: row, column: column)
      let columnWidth: CGFloat? = widths[column]
      let rowHeight: CGFloat? = heights[row]
      return label
        .frame(width: columnWidth, alignment: cellAlignment(column))
        .frame(minHeight: rowHeight, alignment: .top)
        .background { sizeProbe(content: content, row: row, column: column) }
    }

    private func sizeProbe(content: AttributedSubstring, row: Int, column: Int) -> some View {
      let label = TableCell(content, row: row, column: column)
        .fixedSize(horizontal: true, vertical: true)
        .hidden()
        .allowsHitTesting(false)
      return label
        .textualIsolateLayouts()
        .transformPreference(TableCell.BoundsKey.self) { $0 = [:] }
        .textualReadSize { size in
          recordSize(size, row: row, column: column)
        }
    }

    private func recordSize(_ size: CGSize, row: Int, column: Int) {
      let previousWidth: CGFloat = widths[column] ?? 0
      let previousHeight: CGFloat = heights[row] ?? 0
      if size.width > previousWidth { widths[column] = size.width }
      if size.height > previousHeight { heights[row] = size.height }
    }

    private func cellAlignment(_ column: Int) -> Alignment {
      guard columns.indices.contains(column) else { return .topLeading }
      switch columns[column].alignment {
      case .left: return .topLeading
      case .center: return .top
      case .right: return .topTrailing
      @unknown default: return .topLeading
      }
    }
  }
}
