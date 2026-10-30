import SwiftUI

/// Measures and places Textual with the same column width in one layout pass.
/// No geometry callback writes into View state or schedules a second layout.
@available(iOS 16.0, *)
struct MarkdownBlockLayout: Layout {
    let dynamicType: DynamicTypeSize
    let displayScale: CGFloat
    let direction: LayoutDirection

    struct Cache {
        var dynamicType: DynamicTypeSize
        var displayScale: CGFloat
        var direction: LayoutDirection
        var sizing = MarkdownBlockSizing()
        var measurements = MarkdownMeasurementCache()
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(dynamicType: dynamicType, displayScale: displayScale, direction: direction)
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        if cache.dynamicType != dynamicType || cache.displayScale != displayScale || cache.direction != direction {
            cache = makeCache(subviews: subviews)
        }
        // A subview change (including asynchronous attachments/highlighting)
        // invalidates actual measurements, while scroll/translation alone does not.
        cache.measurements.invalidate()
        // Appends and Textual's asynchronous highlighter/attachment updates
        // retain the last real height. Authoritative replacements recreate the
        // enclosing row's layout generation, and therefore this cache as well.
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil }
        let natural = cache.measurements.size(proposedWidth: width) {
            content.sizeThatFits(.init(width: width, height: nil))
        }
        return cache.sizing.size(proposedWidth: width, naturalSize: natural, displayScale: displayScale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
            proposal: .init(width: bounds.width, height: nil))
    }
}

/// iOS 15 lets the very same Textual content measure itself at the parent's
/// column width. Reserve the same pixel-rounded, per-width nonshrinking height.
/// Unlike Layout, the reservation arrives after the first layout pass.
struct MarkdownBlockLayoutLegacy<Content: View>: View {
    let dynamicType: DynamicTypeSize
    let displayScale: CGFloat
    let direction: LayoutDirection
    private let content: Content
    @State private var sizing = MarkdownBlockSizing()
    @State private var reservation: CGSize?
    @State private var lastNatural = CGSize.zero
    @State private var measuredEnvironment: MarkdownLegacyEnvironment?

    init(dynamicType: DynamicTypeSize, displayScale: CGFloat, direction: LayoutDirection,
        @ViewBuilder content: () -> Content) {
        self.dynamicType = dynamicType
        self.displayScale = displayScale
        self.direction = direction
        self.content = content()
    }

    private var environment: MarkdownLegacyEnvironment {
        .init(dynamicType: dynamicType, displayScale: displayScale, direction: direction)
    }

    var body: some View {
        let environment = environment
        content
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: MarkdownLegacyNaturalSize.self, value: geometry.size)
                }
            }
            .frame(minHeight: reservation?.height, alignment: .topLeading)
            .onPreferenceChange(MarkdownLegacyNaturalSize.self) { size in
                DispatchQueue.main.async {
                    guard measuredEnvironment == nil || measuredEnvironment == environment else { return }
                    measuredEnvironment = environment
                    reserve(size)
                }
            }
            .appOnChange(of: environment, initial: true) { _, next in
                guard measuredEnvironment != next else { return }
                measuredEnvironment = next
                sizing = MarkdownBlockSizing()
                reservation = nil
                if lastNatural.width > 0 { reserve(lastNatural) }
            }
    }

    private func reserve(_ natural: CGSize) {
        guard natural.width.isFinite, natural.height.isFinite else { return }
        lastNatural = natural
        var next = sizing
        let size = next.size(proposedWidth: natural.width, naturalSize: natural, displayScale: displayScale)
        sizing = next
        if reservation != size { reservation = size }
    }
}

private struct MarkdownLegacyEnvironment: Equatable {
    let dynamicType: DynamicTypeSize
    let displayScale: CGFloat
    let direction: LayoutDirection
}
private struct MarkdownLegacyNaturalSize: PreferenceKey {
    nonisolated static var defaultValue: CGSize { .zero }
    nonisolated static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
