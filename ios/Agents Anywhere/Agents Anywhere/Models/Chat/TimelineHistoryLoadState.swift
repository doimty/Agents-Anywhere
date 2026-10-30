import Foundation

/// The view owns one history task. Session-wide network activity is only a gate,
/// never a reason to display either of the two directional loading indicators.
nonisolated struct TimelineHistoryLoadState: Equatable {
    enum Direction: Equatable { case older, latest }
    struct Request: Equatable {
        let id: Int
        let direction: Direction
        let navigationGeneration: Int
    }

    private(set) var request: Request?
    private var nextID = 0
    var isLoadingOlder: Bool { request?.direction == .older }
    var isLoadingLatest: Bool { request?.direction == .latest }

    @discardableResult
    mutating func begin(_ direction: Direction, generation: Int) -> Request? {
        guard request == nil else { return nil }
        nextID &+= 1
        let value = Request(id: nextID, direction: direction, navigationGeneration: generation)
        request = value
        return value
    }

    @discardableResult
    mutating func finish(_ value: Request) -> Bool {
        guard request == value else { return false }
        request = nil
        return true
    }

    mutating func cancel() { request = nil }
}

/// UIKit supplies content coordinates on iOS 15. Probe lifetime is deliberately
/// irrelevant: a lazy stack can retain mounted rows well beyond the viewport.
nonisolated struct TimelineLegacyVisibleRange: Equatable {
    let minY: CGFloat
    let maxY: CGFloat

    init(_ viewport: TimelineViewport) {
        minY = viewport.offsetY + viewport.topInset
        maxY = max(minY, viewport.visibleBottom)
    }

    func contains(minY start: CGFloat, maxY end: CGFloat, threshold: CGFloat = 0.5) -> Bool {
        guard end > start, maxY > minY else { return false }
        let overlap = max(0, min(maxY, end) - max(minY, start))
        return overlap > 0 && overlap >= (end - start) * threshold
    }
}
