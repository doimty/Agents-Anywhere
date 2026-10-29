import SwiftUI
import UIKit

/// Original sidebar and detail builders, hosted by the older native split view.
/// This does not create an alternative dashboard or message hierarchy.
struct AppLegacySidebarSplit<Header: View, Sidebar: View, Detail: View>: View {
    @Binding var isOpen: Bool
    let edgeStyle: AppScrollEdgeEffect
    let header: (EdgeInsets) -> Header
    let sidebar: (EdgeInsets) -> Sidebar
    let detail: (EdgeInsets) -> Detail

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                sidebar(geometry.safeAreaInsets)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .appSafeAreaBar(edge: .top, spacing: 0) {
                        header(geometry.safeAreaInsets)
                            .padding(.top, geometry.safeAreaInsets.top)
                            .padding(.leading, geometry.safeAreaInsets.leading)
                            .padding(.trailing, geometry.safeAreaInsets.trailing)
                    }
                    .appNavigationBarHidden(true)
            }
            GeometryReader { geometry in
                detail(geometry.safeAreaInsets).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.navigationViewStyle(DoubleColumnNavigationViewStyle())
            .environment(\.sidebarDrawerPresentation, .nativeSidebar)
            .environment(\.sidebarDrawerIsTransitioning, false)
            .background(AppSplitVisibilityBridge(isOpen: $isOpen))
    }
}

private struct AppSplitVisibilityBridge: UIViewControllerRepresentable {
    @Binding var isOpen: Bool
    func makeUIViewController(context: Context) -> Probe { Probe() }
    func updateUIViewController(_ view: Probe, context: Context) {
        view.onVisibility = { isOpen = $0 }
        DispatchQueue.main.async { view.apply(open: isOpen) }
    }

    final class Probe: UIViewController {
        var onVisibility: ((Bool) -> Void)?
        private weak var observedSplit: UISplitViewController?
        private var observation: NSKeyValueObservation?
        private var requestedOpen: Bool?
        override func loadView() {
            let empty = UIView(); empty.backgroundColor = .clear; empty.isUserInteractionEnabled = false
            view = empty
        }
        func apply(open: Bool) {
            var current: UIViewController? = parent
            var split: UISplitViewController?
            while let controller = current {
                if let value = controller as? UISplitViewController { split = value; break }
                if let value = controller.splitViewController { split = value; break }
                current = controller.parent
            }
            guard let split else { return }
            if observedSplit !== split {
                observedSplit = split
                split.minimumPrimaryColumnWidth = 240
                split.maximumPrimaryColumnWidth = 360
                split.preferredPrimaryColumnWidth = 300
                observation = split.observe(\.displayMode, options: [.new]) { [weak self] value, _ in
                    DispatchQueue.main.async {
                        guard let self, !value.isCollapsed else { return }
                        switch value.displayMode {
                        case .secondaryOnly: self.onVisibility?(false)
                        case .oneBesideSecondary, .oneOverSecondary, .twoBesideSecondary, .twoOverSecondary:
                            self.onVisibility?(true)
                        default: break
                        }
                    }
                }
            }
            guard requestedOpen != open else { return }
            requestedOpen = open
            split.preferredDisplayMode = open ? .oneBesideSecondary : .secondaryOnly
        }
    }
}

extension View {
    @ViewBuilder
    func appSidebarPanGesture(progress: CGFloat, edgeActivationWidth: CGFloat,
                              onBegan: @escaping () -> Void,
                              onChanged: @escaping (CGFloat) -> Void,
                              onEnded: @escaping (CGFloat, CGFloat, Bool) -> Void) -> some View {
        if #available(iOS 18.0, *), AppCompatibility.useNativeUI {
            gesture(SidebarDrawerPanGesture(progress: progress, edgeActivationWidth: edgeActivationWidth,
                                           onBegan: onBegan, onChanged: onChanged, onEnded: onEnded))
        } else {
            background(AppLegacySidebarPan(progress: progress, edgeWidth: edgeActivationWidth,
                                           onBegan: onBegan, onChanged: onChanged, onEnded: onEnded))
        }
    }
}

/// Recognizer attachment/cleanup is owned by this bridge. Like the original
/// iOS 18 recognizer it rejects vertical motion before recognition and cancels
/// row taps only after establishing horizontal drawer intent.
private struct AppLegacySidebarPan: UIViewRepresentable {
    let progress: CGFloat
    let edgeWidth: CGFloat
    let onBegan: () -> Void
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat, Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> Probe {
        let view = Probe(); view.isUserInteractionEnabled = false
        view.didAttach = { [weak coordinator = context.coordinator] view in coordinator?.attach(from: view) }
        return view
    }
    func updateUIView(_ view: Probe, context: Context) {
        context.coordinator.parent = self
        DispatchQueue.main.async { context.coordinator.attach(from: view) }
    }
    static func dismantleUIView(_ view: Probe, coordinator: Coordinator) { coordinator.detach() }

    final class Probe: UIView {
        var didAttach: ((UIView) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { didAttach?(self) } }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: AppLegacySidebarPan
        private weak var host: UIView?
        private lazy var pan: UIPanGestureRecognizer = {
            let value = UIPanGestureRecognizer(target: self, action: #selector(changed(_:)))
            value.cancelsTouchesInView = true
            value.maximumNumberOfTouches = 1
            value.delegate = self
            return value
        }()
        init(parent: AppLegacySidebarPan) { self.parent = parent }
        func attach(from view: UIView) {
            guard view.window != nil, let candidate = view.superview else { return }
            guard host !== candidate else { return }
            detach(); host = candidate; candidate.addGestureRecognizer(pan)
        }
        func detach() { host?.removeGestureRecognizer(pan); host = nil }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let view = pan.view else { return false }
            let velocity = pan.velocity(in: view)
            guard abs(velocity.x) > abs(velocity.y) else { return false }
            if parent.progress <= 0.001 {
                let initial = pan.location(in: view).x - pan.translation(in: view).x
                return initial <= max(parent.edgeWidth, 0) && velocity.x > 0
            }
            if parent.progress >= 0.999 { return velocity.x < 0 }
            return true
        }
        @objc private func changed(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let x = recognizer.translation(in: view).x
            let velocity = recognizer.velocity(in: view).x
            switch recognizer.state {
            case .began: parent.onBegan()
            case .changed: parent.onChanged(x)
            case .ended: parent.onEnded(x, velocity, false)
            case .cancelled: parent.onEnded(x, velocity, true)
            default: break
            }
        }
    }
}

/// Same square/fullscreen and rounded/moving-card states as the original shape.
/// Concentric rounding is cosmetic and requires iOS 26, not a new page layout.
struct AppConcentricCardShape: Shape {
    var isFullyClosed: Bool
    func path(in rect: CGRect) -> Path {
        if #available(iOS 26.0, *), AppCompatibility.useNativeUI {
            return ConcentricRectangle(corners: isFullyClosed ? .fixed(0) : .concentric).path(in: rect)
        }
        return RoundedRectangle(cornerRadius: isFullyClosed ? 0 : 30, style: .continuous).path(in: rect)
    }
}
