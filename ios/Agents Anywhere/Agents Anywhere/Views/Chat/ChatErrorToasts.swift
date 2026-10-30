import Perception
import SwiftUI

/// Non-inline errors float below the header. Paging only changes the visible
/// toast; retry is always an explicit read, never a replay of the failed action.
/// iOS 17 uses the paged horizontal scroller; older systems show the same cards
/// in a horizontal ScrollView and let the reader swipe between them.
struct ChatErrorToasts: View {
    let store: ChatToastStore
    let isRetrying: Bool
    let onRetry: (String) async -> Void
    @State private var selected: String?
    @ScaledMetric(relativeTo: .footnote) private var lineHeight: CGFloat = 18
    private var height: CGFloat { min(220, max(136, lineHeight * 4 + 74)) }

    var body: some View {
        if !store.items.isEmpty {
            Group {
                if #available(iOS 17.0, *), AppCompatibility.useNativeUI {
                    pagedScroller
                } else {
                    legacyScroller
                }
            }
            .frame(height: height)
            .padding(.horizontal, ChatControlMetrics.collapsedHorizontalInset)
            .padding(.top, 4).padding(.bottom, 10)
            .frame(maxWidth: ChatControlMetrics.maximumContentWidth)
            .appOnChange(of: store.items.map(\.id)) { _, ids in
                if selected == nil || !ids.contains(selected ?? "") { selected = ids.first }
            }
            .accessibilityHint(store.items.count > 1 ? String(localized: "左右滑动查看其他提示") : "")
        }
    }

    @available(iOS 17.0, *)
    private var pagedScroller: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                    card(item, index: index)
                        .containerRelativeFrame(.horizontal)
                        .id(item.id)
                }
            }.scrollTargetLayout()
        }
        .scrollIndicators(.hidden).scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selected).scrollClipDisabled()
    }

    private var legacyScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                    card(item, index: index).frame(width: legacyCardWidth).id(item.id)
                }
            }
        }
    }

    private var legacyCardWidth: CGFloat {
        UIScreen.main.bounds.width - ChatControlMetrics.collapsedHorizontalInset * 2
    }

    private func card(_ item: ChatToast, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AppSymbol("exclamationmark.circle").foregroundStyle(.secondary)
                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Spacer(minLength: 0)
                if store.items.count > 1 {
                    Text("\(index + 1)/\(store.items.count)").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
                Button { store.dismiss(item.id) } label: {
                    AppSymbol("xmark", size: 11).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(String(localized: "关闭此提示"))
            }
            ScrollView(.vertical) {
                Text(item.message).font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }.appScrollBounceBasedOnSize()
            if item.canRetry {
                Button(isRetrying ? String(localized: "正在刷新…") : String(localized: "刷新状态")) { Task { await onRetry(item.id) } }
                    .font(.footnote.weight(.medium)).frame(minHeight: 36).disabled(isRetrying)
            }
        }
        .padding(.leading, 16).padding(.trailing, 4).padding(.bottom, 12)
        .frame(height: height)
        .appGlassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
