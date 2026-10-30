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
        let view = Probe(frame: .zero)
        view.onAttach = { [weak coordinator = context.coordinator] view in coordinator?.attach(from: view) }
        return view
    }
    func updateUIView(_ view: Probe, context: Context) {
        context.coordinator.parent = self
        view.scheduleAttachment()
    }
    static func dismantleUIView(_ view: Probe, coordinator: Coordinator) {
        view.invalidate()
        coordinator.invalidate()
    }

    final class Probe: UIView {
        var onAttach: ((Probe) -> Void)?
        private var attachmentScheduled = false
        private var attachmentGeneration = 0
        private var isInvalidated = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachmentChanged()
        }
        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            attachmentChanged()
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            scheduleAttachment()
        }
        private func attachmentChanged() {
            if window == nil {
                cancelAttachment()
                if !isInvalidated { onAttach?(self) }
            } else {
                scheduleAttachment()
            }
        }
        func scheduleAttachment() {
            guard !isInvalidated, window != nil, !attachmentScheduled else { return }
            attachmentScheduled = true
            let generation = attachmentGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isInvalidated, self.attachmentGeneration == generation else { return }
                self.attachmentScheduled = false
                self.onAttach?(self)
            }
        }
        private func cancelAttachment() {
            attachmentGeneration &+= 1
            attachmentScheduled = false
        }
        func invalidate() {
            isInvalidated = true
            cancelAttachment()
            onAttach = nil
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: AppLegacySidebarPan
        private weak var probe: Probe?
        private weak var host: UIView?
        private weak var drawerRoot: UIView?
        private weak var drawerController: UIViewController?
        private var isInvalidated = false
        private var isPanning = false
        private let pan = UIPanGestureRecognizer()

        init(parent: AppLegacySidebarPan) {
            self.parent = parent
            super.init()
            pan.addTarget(self, action: #selector(changed(_:)))
            pan.cancelsTouchesInView = true
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
        }

        func attach(from view: Probe) {
            guard !isInvalidated else { return }
            guard let window = view.window, view.bounds.width > 0, view.bounds.height > 0,
                  let initialController = owningController(of: view),
                  let initialRoot = initialController.viewIfLoaded,
                  view.isDescendant(of: initialRoot) else {
                detach()
                return
            }
            // Layout/update callbacks can run during a drag. Moving a live
            // recognizer would cancel it; resolve again once that drag ends.
            guard !isPanning else { return }
            var controller = initialController
            var root = initialRoot

            // A SwiftUI background can have a separate UIKit host from its
            // foreground. Find a common ancestor with the actual hit views,
            // rather than installing on the background's immediate superview.
            var candidate: UIView = view
            let bounds = view.bounds.insetBy(dx: min(1, view.bounds.width / 2),
                                             dy: min(1, view.bounds.height / 2))
            var foundHit = false
            for x in [bounds.minX, bounds.midX, bounds.maxX] {
                for y in [bounds.minY, bounds.midY, bounds.maxY] {
                    let point = view.convert(CGPoint(x: x, y: y), to: window)
                    guard window.bounds.contains(point), let hit = window.hitTest(point, with: nil),
                          let hitController = owningController(of: hit),
                          let sharedController = commonController(controller, hitController),
                          let sharedRoot = sharedController.viewIfLoaded,
                          view.isDescendant(of: sharedRoot), hit.isDescendant(of: sharedRoot) else { continue }
                    controller = sharedController
                    root = sharedRoot
                    foundHit = true
                    while !hit.isDescendant(of: candidate), let ancestor = candidate.superview {
                        candidate = ancestor
                    }
                }
            }
            if !foundHit { candidate = root }
            // Keep the recognizer above the whole drawer even if a background
            // wrapper or the currently visible card occupies only part of it.
            while !candidate.isUserInteractionEnabled
                || !candidate.bounds.contains(view.convert(view.bounds, to: candidate)) {
                guard let ancestor = candidate.superview else { break }
                candidate = ancestor
            }
            if !candidate.isDescendant(of: root) { candidate = window }
            probe = view
            drawerRoot = root
            drawerController = controller
            guard host !== candidate else { return }
            detach()
            probe = view
            drawerRoot = root
            drawerController = controller
            host = candidate
            candidate.addGestureRecognizer(pan)
        }

        private func detach() {
            if isPanning, !isInvalidated, let probe {
                isPanning = false
                parent.onEnded(pan.translation(in: probe).x, pan.velocity(in: probe).x, true)
            }
            pan.isEnabled = false
            host?.removeGestureRecognizer(pan)
            host = nil
            probe = nil
            drawerRoot = nil
            drawerController = nil
            isPanning = false
            pan.isEnabled = true
        }
        func invalidate() {
            isInvalidated = true
            detach()
            pan.delegate = nil
            pan.removeTarget(self, action: #selector(changed(_:)))
        }

        private func owningController(of view: UIView) -> UIViewController? {
            var responder: UIResponder? = view
            while let current = responder {
                if let controller = current as? UIViewController { return controller }
                responder = current.next
            }
            return nil
        }
        private func commonController(_ first: UIViewController, _ second: UIViewController) -> UIViewController? {
            var ancestor: UIViewController? = first
            while let candidate = ancestor {
                var controller: UIViewController? = second
                while let current = controller {
                    if current === candidate { return candidate }
                    controller = current.parent
                }
                ancestor = candidate.parent
            }
            return nil
        }
        private func belongsToDrawer(_ view: UIView) -> Bool {
            guard let root = drawerRoot, view.isDescendant(of: root),
                  let owner = drawerController else { return false }
            // Presented controllers are not children of their presenter. This
            // also excludes modal content if UIKit places it under a shared host.
            var controller = owningController(of: view)
            while let current = controller {
                if current === owner { return true }
                controller = current.parent
            }
            return false
        }
        private func visibleProbe() -> Probe? {
            guard !isInvalidated, let probe, let window = probe.window, let host,
                  host === window || host.window === window, let root = drawerRoot,
                  probe.isDescendant(of: root) else { return nil }
            var ancestor: UIView? = probe
            while let view = ancestor {
                guard !view.isHidden, view.alpha > 0.01 else { return nil }
                if view === window { return probe }
                ancestor = view.superview
            }
            return nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard gestureRecognizer === pan, let probe = visibleProbe(),
                  touch.window === probe.window, let hit = touch.view,
                  belongsToDrawer(hit) else { return false }
            // Even a window fallback only observes hits in this drawer's actual
            // rectangle and controller subtree, never a sheet or another window.
            return probe.bounds.contains(touch.location(in: probe))
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === pan, let probe = visibleProbe() else { return false }
            let velocity = pan.velocity(in: probe)
            guard abs(velocity.x) > abs(velocity.y) else { return false }
            let location = pan.location(in: probe)
            let translation = pan.translation(in: probe)
            let initial = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
            guard probe.bounds.contains(initial) else { return false }
            if parent.progress <= 0.001 {
                return initial.x - probe.bounds.minX <= max(parent.edgeWidth, 0) && velocity.x > 0
            }
            if parent.progress >= 0.999 { return velocity.x < 0 }
            return true
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === pan, visibleProbe() != nil,
                  let scrollView = otherGestureRecognizer.view as? UIScrollView,
                  otherGestureRecognizer === scrollView.panGestureRecognizer else { return false }
            // A descendant scroll pan must not win before the ancestor drawer
            // can establish horizontal intent. Vertical motion fails our own
            // shouldBegin, and tap recognizers retain normal cancellation.
            return belongsToDrawer(scrollView)
        }

        @objc private func changed(_ recognizer: UIPanGestureRecognizer) {
            guard !isInvalidated, let probe else { return }
            let x = recognizer.translation(in: probe).x
            let velocity = recognizer.velocity(in: probe).x
            switch recognizer.state {
            case .began:
                isPanning = true
                parent.onBegan()
            case .changed:
                if isPanning { parent.onChanged(x) }
            case .ended, .cancelled:
                guard isPanning else { return }
                isPanning = false
                parent.onEnded(x, velocity, recognizer.state == .cancelled)
                probe.scheduleAttachment()
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
