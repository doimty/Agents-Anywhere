import SwiftUI
import UIKit

/// Switch only implementation backends, never the app's pages or visual styles.
/// The launch argument exercises the iOS 15 paths on a current simulator too.
enum AppCompatibility {
    static var useNativeUI: Bool {
        !ProcessInfo.processInfo.arguments.contains("--force-ios15-paths")
    }
}

enum AppGlassStyle {
    case regular
    case interactive

    @available(iOS 26.0, *)
    var native: Glass {
        switch self {
        case .regular: .regular
        case .interactive: .regular.interactive()
        }
    }
}

enum AppScrollEdgeEffect {
    case soft
    case hard

    @available(iOS 26.0, *)
    var native: ScrollEdgeEffectStyle {
        switch self {
        case .soft: .soft
        case .hard: .hard
        }
    }
}

enum AppSheetDetent: Hashable {
    case medium
    case large
    case fraction(CGFloat)
    case height(CGFloat)

    @available(iOS 16.0, *)
    var native: PresentationDetent {
        switch self {
        case .medium: .medium
        case .large: .large
        case let .fraction(value): .fraction(value)
        case let .height(value): .height(value)
        }
    }
}

enum AppImpactFeedback {
    case light
    case rigid
}

extension View {
    @ViewBuilder
    func appGlassEffect(_ style: AppGlassStyle = .regular, in shape: some Shape) -> some View {
        if #available(iOS 26.0, *), AppCompatibility.useNativeUI {
            glassEffect(style.native, in: shape)
        } else {
            // The same rounded geometry, hit regions and content stay in place.
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    func appGlassEffectID<ID: Hashable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *), AppCompatibility.useNativeUI {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func appGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *), AppCompatibility.useNativeUI {
            if prominent { buttonStyle(.glassProminent) }
            else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) }
            else { buttonStyle(.bordered) }
        }
    }

    @ViewBuilder
    func appCircularButtonShape(_ circular: Bool) -> some View {
        if #available(iOS 17.0, *), AppCompatibility.useNativeUI {
            buttonBorderShape(circular ? .circle : .capsule)
        } else {
            buttonBorderShape(.capsule)
        }
    }

    @ViewBuilder
    func appScrollEdgeEffect(_ style: AppScrollEdgeEffect, for edges: Edge.Set) -> some View {
        if #available(iOS 26.0, *), AppCompatibility.useNativeUI {
            scrollEdgeEffectStyle(style.native, for: edges)
        } else {
            self
        }
    }

    @ViewBuilder
    func appSafeAreaBar<Bar: View>(edge: VerticalEdge, spacing: CGFloat = 0,
                                 @ViewBuilder content: () -> Bar) -> some View {
        if #available(iOS 26.0, *), AppCompatibility.useNativeUI {
            safeAreaBar(edge: edge, spacing: spacing, content: content)
        } else {
            safeAreaInset(edge: edge, spacing: spacing, content: content)
        }
    }

    @ViewBuilder
    func appHiddenScrollBackground() -> some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
            scrollContentBackground(.hidden)
        } else {
            background(AppScrollConfiguration(clearBackground: true))
        }
    }

    @ViewBuilder
    func appHiddenScrollIndicators() -> some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
            scrollIndicators(.hidden)
        } else {
            background(AppScrollConfiguration(hideIndicators: true))
        }
    }

    @ViewBuilder
    func appScrollDismissesKeyboardInteractively() -> some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
            scrollDismissesKeyboard(.interactively)
        } else {
            background(AppScrollConfiguration(interactiveKeyboardDismissal: true))
        }
    }

    @ViewBuilder
    func appScrollBounceBasedOnSize(axes: Axis.Set = .vertical) -> some View {
        if #available(iOS 16.4, *), AppCompatibility.useNativeUI {
            scrollBounceBehavior(.basedOnSize, axes: axes)
        } else {
            self
        }
    }

    @ViewBuilder
    func appAlwaysVerticalBounce() -> some View {
        if #available(iOS 16.4, *), AppCompatibility.useNativeUI {
            scrollBounceBehavior(.always, axes: .vertical)
        } else {
            background(AppScrollConfiguration(alwaysBounceVertical: true))
        }
    }

    @ViewBuilder
    func appHiddenNavigationBarBackground() -> some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
            toolbarBackground(.hidden, for: .navigationBar)
        } else {
            self
        }
    }

    @ViewBuilder
    func appNavigationBarHidden(_ hidden: Bool) -> some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
            toolbar(hidden ? .hidden : .visible, for: .navigationBar)
        } else {
            navigationBarHidden(hidden)
        }
    }

    @ViewBuilder
    func appRemoveSidebarToggle() -> some View {
        if #available(iOS 17.0, *), AppCompatibility.useNativeUI {
            toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }

    /// View `tracking` is iOS 16; older systems keep the same text without the
    /// extra letter spacing instead of dropping the label.
    @ViewBuilder
    func appTracking(_ value: CGFloat) -> some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI { tracking(value) }
        else { self }
    }

    @ViewBuilder
    func appLineLimit(_ range: ClosedRange<Int>) -> some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI { lineLimit(range) }
        else { lineLimit(range.upperBound) }
    }

    @ViewBuilder
    func appLineLimit(_ range: PartialRangeFrom<Int>) -> some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI { lineLimit(range) }
        else { self }
    }

    @ViewBuilder
    func appFontWeight(_ weight: Font.Weight) -> some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI { fontWeight(weight) }
        else { modifier(AppInheritedFontWeight(weight: weight)) }
    }

    @ViewBuilder
    func appMonospaced() -> some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI { monospaced() }
        else { modifier(AppInheritedFontDesign()) }
    }

    @ViewBuilder
    func appSymbolReplaceTransition() -> some View {
        if #available(iOS 17.0, *), AppCompatibility.useNativeUI {
            contentTransition(.symbolEffect(.replace))
        } else {
            self
        }
    }

    @ViewBuilder
    func appPresentationDetents(_ detents: Set<AppSheetDetent>, selection: Binding<AppSheetDetent>? = nil) -> some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
            if let selection {
                presentationDetents(Set(detents.map(\.native)), selection: Binding(
                    get: { selection.wrappedValue.native },
                    set: { value in
                        if let match = detents.first(where: { $0.native == value }) {
                            selection.wrappedValue = match
                        }
                    }))
            } else {
                presentationDetents(Set(detents.map(\.native)))
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func appSheetDragIndicator() -> some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI { presentationDragIndicator(.visible) }
        else { self }
    }

    @ViewBuilder
    func appSheetScrollContentInteraction() -> some View {
        if #available(iOS 16.4, *), AppCompatibility.useNativeUI { presentationContentInteraction(.scrolls) }
        else { self }
    }

    @ViewBuilder
    func appImpactFeedback<Value: Equatable>(_ impact: AppImpactFeedback, trigger: Value) -> some View {
        if #available(iOS 17.0, *), AppCompatibility.useNativeUI {
            if impact == .light { sensoryFeedback(.impact(weight: .light, intensity: 1), trigger: trigger) }
            else { sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.65), trigger: trigger) }
        } else {
            onChange(of: trigger) { _ in
                UIImpactFeedbackGenerator(style: impact == .light ? .light : .rigid).impactOccurred(intensity: impact == .light ? 1 : 0.65)
            }
        }
    }

    @ViewBuilder
    func appOnChange<Value: Equatable>(of value: Value, initial: Bool = false,
                                      perform action: @escaping (Value, Value) -> Void) -> some View {
        if #available(iOS 17.0, *), AppCompatibility.useNativeUI {
            onChange(of: value, initial: initial, action)
        } else {
            modifier(AppLegacyOnChange(value: value, initial: initial, action: action))
        }
    }

    @ViewBuilder
    func appOnGeometryChange<Value: Equatable>(for type: Value.Type,
                                              of transform: @escaping (GeometryProxy) -> Value,
                                              action: @escaping (Value) -> Void) -> some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
            onGeometryChange(for: type, of: transform, action: action)
        } else {
            modifier(AppGeometryMeasurement(transform: transform, action: { _, value in action(value) }))
        }
    }

    @ViewBuilder
    func appOnGeometryChange<Value: Equatable>(for type: Value.Type,
                                              of transform: @escaping (GeometryProxy) -> Value,
                                              action: @escaping (Value, Value) -> Void) -> some View {
        if #available(iOS 18.0, *), AppCompatibility.useNativeUI {
            onGeometryChange(for: type, of: transform, action: action)
        } else {
            modifier(AppGeometryMeasurement(transform: transform, action: action))
        }
    }
}

private struct AppLegacyOnChange<Value: Equatable>: ViewModifier {
    let value: Value
    let initial: Bool
    let action: (Value, Value) -> Void
    @State private var previous: Value
    @State private var appeared = false

    init(value: Value, initial: Bool, action: @escaping (Value, Value) -> Void) {
        self.value = value; self.initial = initial; self.action = action
        _previous = State(initialValue: value)
    }

    func body(content: Content) -> some View {
        content.onAppear {
            guard !appeared else { return }
            appeared = true
            previous = value
            if initial { action(value, value) }
        }.onChange(of: value) { next in
            let old = previous
            previous = next
            action(old, next)
        }
    }
}

private struct AppGeometryKey<Value: Equatable>: PreferenceKey {
    nonisolated static var defaultValue: Value? { nil }
    nonisolated static func reduce(value: inout Value?, nextValue: () -> Value?) {
        value = nextValue() ?? value
    }
}

private struct AppGeometryMeasurement<Value: Equatable>: ViewModifier {
    let transform: (GeometryProxy) -> Value
    let action: (Value, Value) -> Void
    @State private var previous: Value?

    func body(content: Content) -> some View {
        content.background(GeometryReader { geometry in
            Color.clear.preference(key: AppGeometryKey<Value>.self, value: transform(geometry))
        }).onPreferenceChange(AppGeometryKey<Value>.self) { sample in
            guard let sample, previous != sample else { return }
            // Never mutate the observed model during the measuring layout pass.
            DispatchQueue.main.async {
                guard previous != sample else { return }
                let old = previous ?? sample
                previous = sample
                action(old, sample)
            }
        }
    }
}

private struct AppInheritedFontWeight: ViewModifier {
    @Environment(\.font) private var font
    let weight: Font.Weight
    func body(content: Content) -> some View { content.font((font ?? .body).weight(weight)) }
}

private struct AppInheritedFontDesign: ViewModifier {
    @Environment(\.font) private var font
    func body(content: Content) -> some View { content.font(.system(.body, design: .monospaced)) }
}

struct AppGlassEffectContainer<Content: View>: View {
    let spacing: CGFloat
    private let content: Content
    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing; self.content = content()
    }
    var body: some View {
        if #available(iOS 26.0, *), AppCompatibility.useNativeUI {
            GlassEffectContainer(spacing: spacing) { content }
        } else { content }
    }
}

extension Animation {
    static var appSmooth: Animation { appSmooth(duration: 0.5) }
    static func appSmooth(duration: TimeInterval) -> Animation {
        if #available(iOS 17.0, *), AppCompatibility.useNativeUI { return .smooth(duration: duration) }
        return .spring(response: max(0.1, duration), dampingFraction: 1)
    }
    static var appSnappy: Animation { appSnappy(duration: 0.5) }
    static func appSnappy(duration: TimeInterval) -> Animation {
        if #available(iOS 17.0, *), AppCompatibility.useNativeUI { return .snappy(duration: duration) }
        return .spring(response: max(0.1, duration), dampingFraction: 0.85)
    }
}

/// Preserve completion and the callers' generation fences on iOS 15 as well.
func appWithAnimation(_ animation: Animation?, completionDelay: TimeInterval,
                      _ body: () -> Void, completion: @escaping () -> Void) {
    if #available(iOS 17.0, *), AppCompatibility.useNativeUI {
        withAnimation(animation, completionCriteria: .removed, body, completion: completion)
    } else {
        withAnimation(animation, body)
        DispatchQueue.main.asyncAfter(deadline: .now() + (animation == nil ? 0 : completionDelay), execute: completion)
    }
}

/// Local, bounded introspection: no global UIAppearance changes to other pages.
private struct AppScrollConfiguration: UIViewRepresentable {
    var clearBackground = false
    var hideIndicators = false
    var interactiveKeyboardDismissal = false
    var alwaysBounceVertical = false

    func makeUIView(context: Context) -> UIView {
        let view = UIView(); view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async {
            var parent = view.superview
            for _ in 0..<5 {
                guard let candidate = parent else { break }
                if let scroll = findScroll(in: candidate, depth: 6) {
                    if clearBackground { scroll.backgroundColor = .clear }
                    if hideIndicators { scroll.showsVerticalScrollIndicator = false; scroll.showsHorizontalScrollIndicator = false }
                    if interactiveKeyboardDismissal { scroll.keyboardDismissMode = .interactive }
                    if alwaysBounceVertical { scroll.alwaysBounceVertical = true }
                    return
                }
                parent = candidate.superview
            }
        }
    }

    private func findScroll(in view: UIView, depth: Int) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        guard depth > 0 else { return nil }
        for child in view.subviews {
            if let scroll = findScroll(in: child, depth: depth - 1) { return scroll }
        }
        return nil
    }
}
