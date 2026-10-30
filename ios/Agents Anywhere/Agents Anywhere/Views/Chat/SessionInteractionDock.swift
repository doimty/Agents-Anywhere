import Perception
import SwiftUI

struct SessionInteractionDock: View {
    let chat: SessionChatModel
    let onShowAll: (String) -> Void
    @State private var selectedID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var metrics = SessionInteractionMetrics()

    private var items: [SessionNoticeModel] { chat.session.notices.notices.filter { $0.blocks(chat.session.id) } }
    private var selectedIndex: Int { items.firstIndex { $0.id == selectedID } ?? 0 }
    // Reserve the same peeking space for one or several cards, so resolving a
    // queued item does not resize the entire dock. Status text never measures it.
    private let peek: CGFloat = 12
    private var pageHeight: CGFloat {
        metrics.compactHeight
    }

    var body: some View {
        AppObservationTracking {
        let motionReduced = reduceMotion
        if !items.isEmpty {
            Group {
                if #available(iOS 17.0, *), AppCompatibility.useNativeUI {
                    nativePager(motionReduced: motionReduced)
                } else {
                    legacyPager(motionReduced: motionReduced)
                }
            }
            .frame(height: pageHeight + peek * 2).clipped()
            .appOnChange(of: items.map(\.id), initial: true) { old, next in
                if let selectedID, next.contains(selectedID) { return }
                let index = old.firstIndex(of: selectedID ?? "") ?? 0
                selectedID = next.isEmpty ? nil : next[min(index, next.count - 1)]
            }
            .padding(.horizontal, 24)
        }
        }
    }

    @available(iOS 17.0, *)
    private func nativePager(motionReduced: Bool) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    card(item, index: index, motionReduced: motionReduced)
                        .scrollTransition(.interactive, axis: .vertical) { content, phase in
                            content.scaleEffect(motionReduced ? 1 : 1 - min(abs(phase.value), 1) * 0.04)
                                .opacity(1 - min(abs(phase.value), 1) * 0.3)
                        }
                        .id(item.id)
                }
            }.scrollTargetLayout()
        }
        .contentMargins(.vertical, peek, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selectedID, anchor: .center)
        .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
    }

    /// iOS 15–16 keep every queued approval reachable: the same cards are shown
    /// in a paged vertical ScrollView with explicit previous/next paging.
    private func legacyPager(motionReduced: Bool) -> some View {
        VStack(spacing: 8) {
            if let current = items.indices.contains(selectedIndex) ? items[selectedIndex] : items.first {
                card(current, index: selectedIndex, motionReduced: true)
                    .id(current.id)
            }
            if items.count > 1 {
                HStack(spacing: 16) {
                    Button { step(-1) } label: {
                        Label(String(localized: "上一项"), appSymbol: "chevron.up")
                            .font(.caption)
                    }
                    .disabled(selectedIndex <= 0)
                    Text("\(selectedIndex + 1)/\(items.count)")
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    Button { step(1) } label: {
                        Label(String(localized: "下一项"), appSymbol: "chevron.down")
                            .font(.caption)
                    }
                    .disabled(selectedIndex >= items.count - 1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func card(_ item: SessionNoticeModel, index: Int, motionReduced: Bool) -> some View {
        SessionInteractionCard(item: item, chat: chat,
            page: items.count > 1 ? "\(index + 1)/\(items.count)" : nil,
            height: pageHeight, onExpand: { onShowAll(item.id) })
            .accessibilityAction(named: String(localized: "下一项")) { step(1) }
            .accessibilityAction(named: String(localized: "上一项")) { step(-1) }
    }

    private func step(_ delta: Int) {
        let index = selectedIndex + delta
        guard items.indices.contains(index) else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { selectedID = items[index].id }
    }
}
