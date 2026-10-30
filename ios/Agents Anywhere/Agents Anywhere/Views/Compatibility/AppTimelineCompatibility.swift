import SwiftUI
import UIKit

/// A local adapter for the original SwiftUI transcript. It observes the enclosing
/// scroll view without replacing SwiftUI's delegate or hosting the whole history.
@MainActor final class AppTimelineScrollDriver: NSObject {
    struct Sample {
        let viewport: TimelineViewport
        let phase: TimelineScrollState.Phase
        let nearTail: Bool
        let atTail: Bool
    }
    struct GroupAnchor: Equatable {
        let id: String
        let rowIDs: [String]
        let usesTrailingEdge: Bool
    }

    private weak var scrollView: UIScrollView?
    private weak var contentProbe: AppTimelineProbeView?
    private var observations: [NSKeyValueObservation] = []
    private var markers: [ObjectIdentifier: WeakMarker] = [:]
    private var delivery: DispatchWorkItem?
    private var bottomDelivery: DispatchWorkItem?
    private var pendingBottom: (() -> Void)?
    private var settlement: DispatchWorkItem?
    private var deliveryGeneration = 0
    private var bottomGeneration = 0
    private var historyGeneration = 0
    private var isActive = false
    private var firstRowID: String?
    private var groups: [GroupAnchor] = []
    private var onSample: ((Sample) -> Void)?
    private var revealAnchor: ((String) -> Void)?
    private var restoration: TimelineHistoryPosition?
    private var hasRevealedAnchor = false
    private var receivedAt: TimeInterval?
    private(set) var sample: Sample?

    var canNavigate: Bool {
        guard isActive, let scrollView, let window = scrollView.window,
              scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return false }
        var ancestor: UIView? = scrollView
        while let view = ancestor {
            if view.isHidden || view.alpha < 0.01 { return false }
            ancestor = view.superview
        }
        return scrollView.convert(scrollView.bounds, to: window).intersects(window.bounds)
    }

    fileprivate func configure(probe: AppTimelineProbeView, active: Bool, firstRowID: String?,
                               groups: [GroupAnchor], onSample: @escaping (Sample) -> Void,
                               revealAnchor: @escaping (String) -> Void) {
        contentProbe = probe
        self.firstRowID = firstRowID
        if self.groups != groups { self.groups = groups }
        self.onSample = onSample
        self.revealAnchor = revealAnchor
        if isActive != active {
            isActive = active
            if !active { stopObserving(); return }
            if receivedAt != nil { receivedAt = ProcessInfo.processInfo.systemUptime }
        }
        connect(from: probe)
        scheduleSample()
    }

    fileprivate func connect(from probe: AppTimelineProbeView) {
        guard isActive else { return }
        var ancestor = probe.superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView {
                if scrollView !== scroll || observations.isEmpty { observe(scroll) }
                return
            }
            ancestor = view.superview
        }
    }

    private func observe(_ scroll: UIScrollView) {
        stopObserving()
        scrollView = scroll
        scroll.panGestureRecognizer.addTarget(self, action: #selector(panChanged))
        // Offset changes only update a reference sample; the caller publishes
        // dimensions, phase and visibility thresholds when they actually change.
        observations = [
            scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in self?.scheduleSample() },
            scroll.observe(\.contentSize, options: [.new]) { [weak self] _, _ in self?.scheduleSample() },
            scroll.observe(\.bounds, options: [.new]) { [weak self] _, _ in self?.scheduleSample() },
            scroll.observe(\.adjustedContentInset, options: [.new]) { [weak self] _, _ in self?.scheduleSample() },
        ]
        scheduleSample(immediate: true)
    }

    @objc private func panChanged(_ pan: UIPanGestureRecognizer) {
        if pan.state == .began { cancelBottom(); cancelHistoryRestoration() }
        scheduleSample(immediate: true)
    }

    fileprivate func register(_ marker: AppTimelineProbeView) {
        markers[ObjectIdentifier(marker)] = WeakMarker(marker)
        if marker === contentProbe { connect(from: marker) }
        scheduleSample()
    }

    fileprivate func unregister(_ marker: AppTimelineProbeView) {
        markers.removeValue(forKey: ObjectIdentifier(marker))
        scheduleSample()
    }

    fileprivate func layoutChanged(_ marker: AppTimelineProbeView) {
        if marker === contentProbe, observations.isEmpty { connect(from: marker) }
        scheduleSample()
    }

    /// Capture a visible group, including the offset *inside* a tall Markdown
    /// message. A grouped tool page retains its existing trailing boundary.
    func beginHistoryRestoration(id: Int) {
        cancelHistoryRestoration()
        guard canNavigate, let viewport = currentSample()?.viewport, let firstRowID else { return }
        let range = TimelineLegacyVisibleRange(viewport)
        let candidates = liveMarkers().compactMap { marker -> (GroupAnchor, CGRect)? in
            guard let id = marker.groupID, let group = groups.first(where: { $0.id == id }),
                  let frame = frame(of: marker), range.contains(minY: frame.minY, maxY: frame.maxY, threshold: 0) else { return nil }
            return (group, frame)
        }.sorted { $0.1.minY < $1.1.minY }
        guard let (group, frame) = candidates.first,
              let rowID = group.usesTrailingEdge ? group.rowIDs.last : group.rowIDs.first else { return }
        let layout = TimelineHistoryLayout(firstRowID: firstRowID, anchorRowID: rowID,
            edge: group.usesTrailingEdge ? .bottom : .top, y: group.usesTrailingEdge ? frame.maxY : frame.minY)
        restoration = TimelineHistoryPosition(id: id, layout: layout, offsetY: viewport.offsetY, topInset: viewport.topInset)
    }

    func receivedHistoryPage(id: Int, firstRowID: String?) {
        guard restoration?.id == id else { return }
        restoration?.receivedPage(firstRowID: firstRowID)
        receivedAt = ProcessInfo.processInfo.systemUptime
        scheduleSample()
    }

    func cancelHistoryRestoration() {
        historyGeneration &+= 1
        settlement?.cancel(); settlement = nil
        restoration = nil
        receivedAt = nil
        hasRevealedAnchor = false
    }

    /// Keep the newest intent but a fixed deadline. A continuously growing
    /// Markdown row must not starve following by resetting a debounce task.
    func coalesceBottom(_ action: @escaping () -> Void) {
        guard isActive else { return }
        pendingBottom = action
        guard bottomDelivery == nil else { return }
        let generation = bottomGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.bottomGeneration == generation else { return }
            let action = self.pendingBottom
            self.pendingBottom = nil
            self.bottomDelivery = nil
            if self.canNavigate { action?() }
        }
        bottomDelivery = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.048, execute: work)
    }

    func cancelBottom() {
        bottomGeneration &+= 1
        bottomDelivery?.cancel(); bottomDelivery = nil
        pendingBottom = nil
    }

    /// The view calls this synchronously on hiding or disappearance, before a
    /// pending SwiftUI update could otherwise deliver one more scroll command.
    func suspend() {
        isActive = false
        stopObserving()
    }

    func disconnect() {
        suspend()
        cancelHistoryRestoration()
        onSample = nil; revealAnchor = nil
        markers.removeAll()
        contentProbe = nil
        sample = nil
    }

    private func stopObserving() {
        cancelBottom()
        deliveryGeneration &+= 1
        delivery?.cancel(); delivery = nil
        settlement?.cancel(); settlement = nil
        observations.removeAll()
        scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(panChanged))
        scrollView = nil
    }

    fileprivate func scheduleSample(immediate: Bool = false) {
        guard isActive else { return }
        if immediate { delivery?.cancel(); delivery = nil; deliveryGeneration &+= 1 }
        guard delivery == nil else { return }
        let generation = deliveryGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.deliveryGeneration == generation else { return }
            self.delivery = nil
            self.deliverSample()
        }
        delivery = work
        // Throttle, rather than debounce: a continuing stream/drag cannot keep
        // pushing the delivery into the future. There is no idle polling clock.
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0 : 0.032), execute: work)
    }

    private func deliverSample() {
        guard canNavigate, let next = currentSample() else { return }
        restoreHistoryIfNeeded(phase: next.phase)
        sample = next
        onSample?(next)
        // UIScrollView has no public delegate-independent end-deceleration
        // callback. A short-lived check notices idle after the final offset.
        if next.phase == .decelerating || next.phase == .tracking || next.phase == .interacting {
            scheduleSample()
        }
    }

    private func currentSample() -> Sample? {
        guard let scroll = scrollView else { return nil }
        let inset = scroll.adjustedContentInset
        let viewport = TimelineViewport(contentHeight: scroll.contentSize.height, containerHeight: scroll.bounds.height,
            topInset: inset.top, bottomInset: inset.bottom, offsetY: scroll.contentOffset.y)
        let phase: TimelineScrollState.Phase
        if scroll.panGestureRecognizer.state == .began || scroll.isTracking && !scroll.isDragging { phase = .tracking }
        else if scroll.isDragging { phase = .interacting }
        else if scroll.isDecelerating { phase = .decelerating }
        else { phase = .idle }
        let range = TimelineLegacyVisibleRange(viewport)
        let tail = liveMarkers().first(where: \.isTail).flatMap { frame(of: $0) }
        return Sample(viewport: viewport, phase: phase,
            nearTail: tail.map { range.contains(minY: $0.maxY - 96, maxY: $0.maxY, threshold: 0.01) } ?? false,
            atTail: tail.map { range.contains(minY: $0.maxY - 2, maxY: $0.maxY) } ?? false)
    }

    private func restoreHistoryIfNeeded(phase: TimelineScrollState.Phase) {
        guard phase == .idle, receivedAt != nil, var history = restoration,
              let origin = history.origin, let firstRowID, let scroll = scrollView else { return }
        // Metadata reaches this probe with the same presented row array as the
        // lazy stack. Do not align against the repository's earlier network tick.
        guard let group = groups.first(where: { $0.rowIDs.contains(origin.anchorRowID) }) else {
            cancelHistoryRestoration(); return
        }
        if let marker = liveMarkers().first(where: { $0.groupID == group.id }), let frame = frame(of: marker) {
            let layout = TimelineHistoryLayout(firstRowID: firstRowID, anchorRowID: origin.anchorRowID,
                edge: origin.edge, y: origin.edge == .top ? frame.minY : frame.maxY)
            let correction = history.laidOut(layout, generation: history.id)
            restoration = history
            if let correction {
                let lower = -scroll.adjustedContentInset.top
                let upper = max(lower, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                let offset = max(lower, min(upper, correction))
                if abs(scroll.contentOffset.y - offset) > 0.5 {
                    scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset), animated: false)
                }
            }
            if history.isReadyToFinish {
                if correction != nil { settlement?.cancel(); settlement = nil }
                settleHistory(after: correction == nil ? 0.12 : 0.18)
            }
        } else if firstRowID != origin.firstRowID, !hasRevealedAnchor {
            // A prepend can evict the old visible group from a lazy viewport.
            // Realize that one group once, then restore its precise interior point.
            hasRevealedAnchor = true
            revealAnchor?(group.id)
            scheduleSample()
        }
        // Restoration never owns the loading indicator. A failed/disappearing
        // probe cannot leave the interface busy or run an unbounded layout loop.
        if let receivedAt, ProcessInfo.processInfo.systemUptime - receivedAt > 1 {
            cancelHistoryRestoration()
        }
    }

    private func settleHistory(after delay: TimeInterval) {
        // Repeated identical offset/layout callbacks must not postpone settlement.
        guard settlement == nil else { return }
        let generation = historyGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.historyGeneration == generation else { return }
            self.cancelHistoryRestoration()
        }
        settlement = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func liveMarkers() -> [AppTimelineProbeView] {
        markers = markers.filter { $0.value.view != nil }
        return markers.values.compactMap(\.view).filter { $0.window != nil && $0 !== contentProbe }
    }

    private func frame(of marker: UIView) -> CGRect? {
        guard let scrollView, marker.isDescendant(of: scrollView), marker.bounds.height > 0 else { return nil }
        return marker.convert(marker.bounds, to: scrollView)
    }

    private struct WeakMarker {
        weak var view: AppTimelineProbeView?
        init(_ view: AppTimelineProbeView) { self.view = view }
    }
}

/// Mounted behind the lazy content, so scroll-view discovery only walks its own
/// ancestors and cannot accidentally attach to the composer or an adjacent page.
struct AppTimelineScrollProbe: UIViewRepresentable {
    let driver: AppTimelineScrollDriver
    let isActive: Bool
    let firstRowID: String?
    let groups: [AppTimelineScrollDriver.GroupAnchor]
    let onSample: (AppTimelineScrollDriver.Sample) -> Void
    let revealAnchor: (String) -> Void

    func makeUIView(context: Context) -> AppTimelineProbeView { AppTimelineProbeView(driver: driver) }
    func updateUIView(_ view: AppTimelineProbeView, context: Context) {
        driver.configure(probe: view, active: isActive, firstRowID: firstRowID, groups: groups,
            onSample: onSample, revealAnchor: revealAnchor)
    }
    static func dismantleUIView(_ view: AppTimelineProbeView, coordinator: ()) { view.driver?.disconnect() }
}

struct AppTimelineAnchorProbe: UIViewRepresentable {
    let driver: AppTimelineScrollDriver
    var groupID: String?
    var isTail = false
    func makeUIView(context: Context) -> AppTimelineProbeView { AppTimelineProbeView(driver: driver) }
    func updateUIView(_ view: AppTimelineProbeView, context: Context) {
        if view.groupID != groupID || view.isTail != isTail {
            view.groupID = groupID; view.isTail = isTail
            driver.layoutChanged(view)
        }
    }
    static func dismantleUIView(_ view: AppTimelineProbeView, coordinator: ()) { view.driver?.unregister(view) }
}

final class AppTimelineProbeView: UIView {
    fileprivate weak var driver: AppTimelineScrollDriver?
    fileprivate var groupID: String?
    fileprivate var isTail = false
    init(driver: AppTimelineScrollDriver) {
        self.driver = driver
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { driver?.unregister(self) }
        else { driver?.register(self) }
    }
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview != nil { driver?.register(self) }
    }
    override func layoutSubviews() { super.layoutSubviews(); driver?.layoutChanged(self) }
}
