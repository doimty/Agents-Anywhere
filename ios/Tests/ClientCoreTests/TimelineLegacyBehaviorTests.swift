import Foundation
import Testing
@testable import ClientCore

@Suite struct TimelineLegacyBehaviorTests {
    private func streamingItem(_ text: String) throws -> V2TimelineItem {
        var object = try itemObject(id: "reply", text: text)
        object["type"] = "message"; object["role"] = "assistant"; object["status"] = "running"
        return try decode(object)
    }

    @Test func aHistoryTaskOwnsOnlyItsOwnDirectionalIndicator() throws {
        for direction in [TimelineHistoryLoadState.Direction.older, .latest] {
            var loads = TimelineHistoryLoadState()
            // A session may be doing background history work before this view
            // makes a request. That is never a local loading indicator.
            #expect(!loads.isLoadingOlder && !loads.isLoadingLatest)
            let request = try #require(loads.begin(direction, generation: 4))
            #expect(loads.isLoadingOlder == (direction == .older))
            #expect(loads.isLoadingLatest == (direction == .latest))
            #expect(loads.begin(.older, generation: 5) == nil)
            #expect(loads.begin(.latest, generation: 5) == nil)
            let finished = loads.finish(request)
            #expect(finished && !loads.isLoadingOlder && !loads.isLoadingLatest)
        }
    }

    @Test func lateCompletionAfterDisappearanceCannotClearANewerRequest() throws {
        var loads = TimelineHistoryLoadState()
        let old = try #require(loads.begin(.older, generation: 7))
        loads.cancel()
        let replacement = try #require(loads.begin(.latest, generation: 7))
        #expect(old.id != replacement.id)
        let staleCompletion = loads.finish(old)
        #expect(!staleCompletion && loads.request == replacement && loads.isLoadingLatest)
        let completed = loads.finish(replacement)
        #expect(completed && loads.request == nil)
    }

    @Test func networkCompletionReleasesTheSpinnerEvenWhenALazyAnchorHasNotLaidOut() throws {
        var loads = TimelineHistoryLoadState()
        let request = try #require(loads.begin(.older, generation: 9))
        let origin = TimelineHistoryLayout(firstRowID: "old", anchorRowID: "old", edge: .top, y: 100)
        var history = TimelineHistoryPosition(id: request.id, layout: origin, offsetY: 320, topInset: 80)
        history.receivedPage(firstRowID: "earlier")
        #expect(!history.isReadyToFinish)
        let finished = loads.finish(request)
        #expect(finished && !loads.isLoadingOlder)
        // Layout can still restore the interior of the message afterwards. Its
        // lifetime has no authority to keep an already-finished task spinning.
        let correction = history.laidOut(.init(firstRowID: "earlier", anchorRowID: "old", edge: .top, y: 1100), generation: request.id)
        #expect(correction == 1320 && history.isReadyToFinish)
    }

    @Test func mountedOffscreenTailCannotResumeFollowing() throws {
        let viewport = TimelineViewport(contentHeight: 3000, containerHeight: 800,
            topInset: 80, bottomInset: 120, offsetY: 1000)
        let range = TimelineLegacyVisibleRange(viewport)
        #expect(!range.contains(minY: 2998, maxY: 3000))
        #expect(!range.contains(minY: 2904, maxY: 3000, threshold: 0.01))
        var scroll = TimelineScrollState()
        scroll.geometryChanged(viewport)
        scroll.open()
        let opening = try #require(scroll.pendingBottomRequest)
        let command = try #require(scroll.begin(opening))
        _ = scroll.complete(command)
        scroll.phaseChanged(.interacting, viewport: viewport)
        scroll.tailVisibilityChanged(.near, visible: false)
        scroll.tailVisibilityChanged(.end, visible: range.contains(minY: 2998, maxY: 3000))
        scroll.phaseChanged(.idle, viewport: viewport)
        scroll.settleUserScroll()
        #expect(scroll.mode == .reading && scroll.pendingBottomRequest == nil && scroll.showsBottomButton())
    }

    @Test func visibilityUsesAdjustedInsetsAndActualIntersectionInsteadOfMounting() {
        let viewport = TimelineViewport(contentHeight: 2000, containerHeight: 800,
            topInset: 80, bottomInset: 120, offsetY: 1000)
        let range = TimelineLegacyVisibleRange(viewport)
        #expect(range.minY == 1080 && range.maxY == 1680)
        #expect(!range.contains(minY: 1000, maxY: 1079))
        #expect(!range.contains(minY: 1680, maxY: 1682))
        #expect(range.contains(minY: 1679, maxY: 1681))
        #expect(!range.contains(minY: 1679, maxY: 1681, threshold: 0.9))
        // A tall message can own the visible reading anchor even when both of
        // its edges are outside the viewport.
        #expect(range.contains(minY: 500, maxY: 2500, threshold: 0))
        #expect(!TimelineLegacyVisibleRange(TimelineViewport()).contains(minY: 0, maxY: 2, threshold: 0))
    }

    @Test func textGrowthWithoutNewRowsFollowsOnlyAfterARealBottomArrival() throws {
        var scroll = TimelineScrollState()
        let bottom = TimelineViewport(contentHeight: 2000, containerHeight: 800, offsetY: 1200)
        scroll.geometryChanged(bottom)
        scroll.tailVisibilityChanged(.near, visible: true)
        scroll.tailVisibilityChanged(.end, visible: true)
        scroll.open()
        let opening = try #require(scroll.pendingBottomRequest)
        let command = try #require(scroll.begin(opening))
        _ = scroll.complete(command)
        #expect(scroll.mode == .following)
        // The same streamed row becomes taller. No row count/last-ID change is
        // needed to produce one coalescible follow request for the new layout.
        scroll.geometryChanged(.init(contentHeight: 2100, containerHeight: 800, offsetY: 1200))
        scroll.tailVisibilityChanged(.near, visible: false)
        scroll.tailVisibilityChanged(.end, visible: false)
        #expect(scroll.pendingBottomRequest?.contentHeight == 2100)
        scroll.phaseChanged(.tracking, viewport: bottom)
        scroll.phaseChanged(.idle, viewport: bottom)
        scroll.settleUserScroll()
        scroll.geometryChanged(.init(contentHeight: 2200, containerHeight: 800, offsetY: 1000))
        #expect(scroll.mode == .reading && scroll.pendingBottomRequest == nil)
    }

    @Test @MainActor func hiddenPresentationKeepsTheLatestFullSnapshotAndResumesWithoutReplay() throws {
        let initial = try streamingItem("Initial")
        let intermediate = try streamingItem("Initial intermediate")
        let latest = try streamingItem("Initial intermediate latest **full Markdown**")
        let earlier: V2TimelineItem = try decode(itemObject(id: "earlier", text: "Full older history"))
        let timeline = SessionTimelinePresentation()
        timeline.presentOpening([initial], pendingMessages: [])
        let row = try #require(timeline.rows.first)
        timeline.setPresentationSuspended(true)
        timeline.stage([intermediate], animate: true)
        timeline.flush(now: 1)
        #expect(row.text == "Initial" && timeline.rows.count == 1)
        timeline.stage([earlier, latest], animate: true)
        timeline.flush(now: 2)
        #expect(row.text == "Initial" && timeline.rows.count == 1)
        timeline.setPresentationSuspended(false)
        #expect(timeline.rows.map(\.id) == ["earlier", "reply"])
        #expect(timeline.rows.last === row)
        #expect(row.text == latest.displayText && !row.isRevealing)
        #expect(timeline.nextBatchAt == 0)
    }

    @Test @MainActor func suspensionStopsAnExistingRevealClockAndIsSafeToReleaseRepeatedly() throws {
        let first = try streamingItem("Start")
        let second = try streamingItem("Start and continue")
        let timeline = SessionTimelinePresentation()
        timeline.presentOpening([first], pendingMessages: [])
        timeline.stage([second], animate: true)
        timeline.flush(now: 0)
        let row = try #require(timeline.rows.first)
        #expect(row.isRevealing)
        let displayed = row.text
        timeline.setPresentationSuspended(true)
        #expect(!row.isRevealing && row.text == displayed)
        timeline.setPresentationSuspended(true)
        timeline.setPresentationSuspended(false)
        timeline.setPresentationSuspended(false)
        #expect(!row.isRevealing && row.text == second.displayText)
        timeline.stage([second], animate: false)
        timeline.flush(now: 1)
        #expect(row.text == second.displayText)
    }
}
