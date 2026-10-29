import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Shared presentation adapters for the iOS 15 compatibility floor.
///
/// Each adapter keeps the native iOS 16+/17+/26+ implementation and provides a
/// bounded legacy rendering for iOS 15. Adapters never shadow an Apple type,
/// never hide interactive content, and never change the semantics of the
/// values they receive. Call sites keep their existing layout and state
/// ownership; only the unavailable visual modifier is replaced.
enum AppGlassStyle {
    case regular
    case interactive

    @available(iOS 26.0, *)
    fileprivate var native: Glass {
        switch self {
        case .regular: .regular
        case .interactive: .regular.interactive()
        }
    }
}

enum AppScrollEdgeEffect: Equatable {
    case soft
    case hard

    @available(iOS 26.0, *)
    fileprivate var native: ScrollEdgeEffectStyle {
        switch self {
        case .soft: .soft
        case .hard: .hard
        }
    }
}

enum AppHapticFeedback {
    case impactLight
    case impactRigid
    case success
    case warning
}

enum AppSheetDetent: Hashable {
    case medium
    case large
    case fraction(CGFloat)
    case height(CGFloat)

    @available(iOS 16.0, *)
    fileprivate var native: PresentationDetent {
        switch self {
        case .medium: .medium
        case .large: .large
        case .fraction(let value): .fraction(value)
        case .height(let value): .height(value)
        }
    }
}

extension View {
    /// Native Liquid Glass on iOS 26; a material card with the same corner
    /// geometry on iOS 15. Interactive glass cannot be reproduced below 26, so
    /// the legacy card keeps the same hit area without the light response.
    @ViewBuilder
    func appGlassEffect(_ style: AppGlassStyle = .regular, in shape: some Shape) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(style.native, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }

    /// `.buttonStyle(.glass)` and `.glassProminent` are iOS 26 only. The legacy
    /// branch keeps a real bordered button so every action stays reachable.
    @ViewBuilder
    func appGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// `.buttonBorderShape(.circle)` is iOS 17; the legacy branch leaves the
    /// system default shape instead of forcing an unavailable capsule/circle.
    @ViewBuilder
    func appCircularButtonShape(_ isCircular: Bool) -> some View {
        if #available(iOS 17.0, *) {
            buttonBorderShape(isCircular ? .circle : .capsule)
        } else {
            self
        }
    }

    /// `.scrollEdgeEffectStyle` is iOS 26. iOS 15 keeps the standard scroll edge
    /// appearance; the content inset and background ownership are unchanged.
    @ViewBuilder
    func appScrollEdgeEffect(_ style: AppScrollEdgeEffect, for edges: Edge.Set) -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(style.native, for: edges)
        } else {
            self
        }
    }

    /// `.sensoryFeedback` is iOS 17. The legacy branch fires the equivalent
    /// UIKit generator when the trigger changes, so completion feedback keeps
    /// its meaning on older systems.
    @ViewBuilder
    func appHapticFeedback<Value: Equatable>(_ feedback: AppHapticFeedback, trigger: Value) -> some View {
        if #available(iOS 17.0, *) {
            sensoryFeedback(nativePattern(feedback), trigger: trigger)
        } else {
            #if canImport(UIKit)
            onChange(of: trigger) { _ in
                legacyHaptic(feedback)
            }
            #else
            self
            #endif
        }
    }

    /// `presentationDetents` is iOS 16. iOS 15 keeps a standard system sheet:
    /// dismissal, scrolling and all content remain available, only the chosen
    /// height is lost on the older system.
    @ViewBuilder
    func appPresentationDetents(_ detents: Set<AppSheetDetent>, selection: Binding<AppSheetDetent>? = nil) -> some View {
        if #available(iOS 16.0, *), let selection {
            presentationDetents(
                Set(detents.map(\.native)),
                selection: Binding(
                    get: { selection.wrappedValue.native },
                    set: { next in
                        if let match = detents.first(where: { $0.native == next }) {
                            selection.wrappedValue = match
                        }
                    }
                )
            )
        } else if #available(iOS 16.0, *) {
            presentationDetents(Set(detents.map(\.native)))
        } else {
            self
        }
    }

    /// `.presentationContentInteraction(.scrolls)` is iOS 16.4.
    @ViewBuilder
    func appSheetScrollContentInteraction() -> some View {
        if #available(iOS 16.4, *) {
            presentationContentInteraction(.scrolls)
        } else {
            self
        }
    }

    /// `.presentationDragIndicator(.visible)` is iOS 16.
    @ViewBuilder
    func appSheetDragIndicator() -> some View {
        if #available(iOS 16.0, *) {
            presentationDragIndicator(.visible)
        } else {
            self
        }
    }

    /// `.scrollIndicators(.hidden)` is iOS 16; hiding is the iOS 15 default for
    /// the scroll views this app uses, so the legacy branch is a no-op.
    @ViewBuilder
    func appHiddenScrollIndicators() -> some View {
        if #available(iOS 16.0, *) {
            scrollIndicators(.hidden)
        } else {
            self
        }
    }

    /// `scrollBounceBehavior` is iOS 16.4. iOS 15 keeps the system bounce.
    @ViewBuilder
    func appScrollBounceBasedOnSize(axes: Axis.Set = .vertical) -> some View {
        if #available(iOS 16.4, *) {
            scrollBounceBehavior(.basedOnSize, axes: axes)
        } else {
            self
        }
    }

    /// `.scrollDismissesKeyboard(.interactively)` is iOS 16.
    @ViewBuilder
    func appScrollDismissesKeyboardInteractively() -> some View {
        if #available(iOS 16.0, *) {
            scrollDismissesKeyboard(.interactively)
        } else {
            self
        }
    }

    /// `.toolbarBackground` is iOS 16.
    @ViewBuilder
    func appHiddenNavigationBarBackground() -> some View {
        if #available(iOS 16.0, *) {
            toolbarBackground(.hidden, for: .navigationBar)
        } else {
            self
        }
    }

    /// Two-parameter `onChange(of:initial:_:)` is iOS 17. The legacy modifier
    /// stores the previous value and forwards the same (old, new) pair, so call
    /// sites keep one closure shape on every system version.
    func appOnChange<Value: Equatable>(
        of value: Value,
        initial: Bool = false,
        perform action: @escaping (Value, Value) -> Void
    ) -> some View {
        modifier(AppOnChangeModifier(value: value, initial: initial, action: action))
    }

    /// `.contentTransition(.symbolEffect(.replace))` is iOS 17.
    @ViewBuilder
    func appSymbolReplaceTransition() -> some View {
        if #available(iOS 17.0, *) {
            contentTransition(.symbolEffect(.replace))
        } else {
            self
        }
    }

    /// `.scrollTargetLayout` / `.scrollTargetBehavior` / `.scrollPosition` are
    /// iOS 17. Callers must keep a plain-scroll fallback for iOS 15 (see the
    /// inventory in `ios/docs/ios15-compatibility.md`); this adapter exists so
    /// simple decorative carousels can opt in without a version branch.
    @ViewBuilder
    func appViewAlignedScrollTargetIfAvailable() -> some View {
        if #available(iOS 17.0, *) {
            scrollTargetLayout()
        } else {
            self
        }
    }
}

@available(iOS 17.0, *)
private func nativePattern(_ feedback: AppHapticFeedback) -> SensoryFeedback {
    switch feedback {
    case .impactLight: .impact(weight: .light)
    case .impactRigid: .impact(flexibility: .rigid, intensity: 0.65)
    case .success: .success
    case .warning: .warning
    }
}

private func legacyHaptic(_ feedback: AppHapticFeedback) {
    #if canImport(UIKit)
    switch feedback {
    case .impactLight:
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    case .impactRigid:
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    case .success:
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    case .warning:
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    #endif
}

/// Replays the iOS 17 two-parameter `onChange` contract on iOS 15.
///
/// The first observed value is never reported as a change. With `initial: true`
/// the closure receives the value paired with itself once, matching SwiftUI's
/// initial delivery. Late-attached modifiers therefore do not synthesise a
/// spurious "old" value from an unrelated predecessor.
private struct AppOnChangeModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let initial: Bool
    let action: (Value, Value) -> Void

    @State private var previous: Value?

    func body(content: Content) -> some View {
        content
            .onChange(of: value) { next in
                let old = previous ?? next
                let isFirstSample = previous == nil
                previous = next
                // Without `initial`, the first sample only seeds the baseline.
                guard !isFirstSample || initial else { return }
                action(old, next)
            }
            .onAppear {
                guard initial, previous == nil else { return }
                previous = value
                action(value, value)
            }
    }
}
