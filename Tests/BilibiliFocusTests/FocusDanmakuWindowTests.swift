import FocusCore
import CoreGraphics
import XCTest
@testable import BilibiliFocus

final class FocusDanmakuWindowTests: XCTestCase {
    private func segment(_ index: Int, count: Int = 1_000) -> FocusNativeDanmakuSegment {
        let baseTimestamp = Int64(index - 1) * 360_000
        var comments: [FocusVideoDanmaku] = []
        for offset in 0..<count {
            let identifier = Int64(index) * 10_000 + Int64(offset)
            let timestamp = baseTimestamp + Int64(offset) * 359
            let mode: FocusVideoDanmakuMode = offset % 3 == 0 ? .top : .scrolling
            comments.append(FocusVideoDanmaku(id: identifier, progressMilliseconds: timestamp,
                mode: mode, fontSize: 25, colorRGB: nil, content: "fixture", weight: 0, pool: 0))
        }
        return FocusNativeDanmakuSegment(index: index, danmakus: comments)
    }

    func testSegmentAppendProcessesOnlyNewCommentsAndKeepsSeekWindowIdentical() {
        var cache = FocusNativeDanmakuLayout.SegmentCache()
        var segments: [FocusNativeDanmakuSegment] = []
        let source = (1...30).map { segment($0) }
        var originalProcessingCount = 0
        let incrementalStart = Date()
        for index in 1...30 {
            segments.append(source[index - 1])
            originalProcessingCount += segments.reduce(0) { $0 + $1.danmakus.count }
            cache.update(segments, laneCount: 8)
        }
        XCTAssertEqual(cache.processedCommentCount, 30_000)
        XCTAssertEqual(originalProcessingCount, 465_000)
        let incrementalSeconds = Date().timeIntervalSince(incrementalStart)
        let baselineStart = Date()
        for count in 1...segments.count {
            let history = segments.prefix(count).flatMap(\.danmakus).sorted {
                if $0.progressMilliseconds != $1.progressMilliseconds {
                    return $0.progressMilliseconds < $1.progressMilliseconds
                }
                return $0.weight > $1.weight
            }
            _ = FocusNativeDanmakuLayout.placements(for: history, laneCount: 8)
        }
        print("danmaku-segments=30 comments=30000 incrementalSeconds=\(incrementalSeconds) baselineSeconds=\(Date().timeIntervalSince(baselineStart)) incrementalVisits=30000 baselineVisits=465000")
        let reference = FocusNativeDanmakuLayout.placements(for: segments.flatMap(\.danmakus), laneCount: 8)
        XCTAssertEqual(cache.segments.flatMap(\.placements).map(\.lane), reference.map(\.lane))
        for time: Int64 in [0, 359_999, 360_000, 360_001, 10_450_000, 5_000, 720_001] {
            XCTAssertEqual(cache.segments.flatMap {
                FocusNativeDanmakuLayout.activePlacements(in: $0.placements, at: time)
            }.map(\.danmaku.id), FocusNativeDanmakuLayout.activePlacements(in: reference, at: time).map(\.danmaku.id))
        }
        cache.update(segments, laneCount: 8)
        XCTAssertEqual(cache.processedCommentCount, 30_000, "cached seek/re-render must not relayout")
    }

    func testOutOfOrderSegmentsAndRotationMatchChronologicalLayout() {
        let segments = (1...3).map { segment($0) }
        var cache = FocusNativeDanmakuLayout.SegmentCache()
        cache.update([segments[0], segments[2]], laneCount: 3)
        cache.update(segments, laneCount: 3)
        for lanes in [3, 9, 1] {
            cache.update(segments, laneCount: lanes)
            let reference = FocusNativeDanmakuLayout.placements(for: segments.flatMap(\.danmakus), laneCount: lanes)
            XCTAssertEqual(cache.segments.flatMap(\.placements).map(\.danmaku.id), reference.map(\.danmaku.id))
            XCTAssertEqual(cache.segments.flatMap(\.placements).map(\.lane), reference.map(\.lane))
        }
        cache.update([], laneCount: 3)
        XCTAssertTrue(cache.segments.isEmpty)
    }

    func testScrollingPositionUsesMediaTimeAtHighRefreshRatesAndAfterSeek() {
        let width: CGFloat = 874, textWidth: CGFloat = 180
        for framesPerSecond in [60, 120] {
            for rate in [1, 3] {
                let positions = (0...framesPerSecond).map { frame in
                    FocusNativeDanmakuLayout.horizontalPosition(
                        mode: .scrolling,
                        elapsedMilliseconds: Int64(frame * rate * 1_000 / framesPerSecond),
                        viewportWidth: width, textWidth: textWidth
                    )
                }
                let expectedStep = (width + textWidth) * CGFloat(rate) / (5 * CGFloat(framesPerSecond))
                for (before, after) in zip(positions, positions.dropFirst()) {
                    XCTAssertEqual(before - after, expectedStep, accuracy: 0.22)
                }
            }
        }
        // Seeking or pausing changes the sampled media time, not an accumulated
        // per-frame travel counter. Re-reading the same time must be identical.
        let position: (Int64) -> CGFloat = {
            FocusNativeDanmakuLayout.horizontalPosition(mode: .scrolling, elapsedMilliseconds: $0,
                                                       viewportWidth: width, textWidth: textWidth)
        }
        XCTAssertEqual(position(0), width)
        XCTAssertEqual(position(5_000), -textWidth)
        XCTAssertEqual(position(1_000), width - (width + textWidth) / 5)
        XCTAssertGreaterThan(position(1_000), position(4_000))
        for mode in [FocusVideoDanmakuMode.top, .bottom] {
            XCTAssertEqual(FocusNativeDanmakuLayout.horizontalPosition(mode: mode, elapsedMilliseconds: 2_000,
                                                                     viewportWidth: width, textWidth: textWidth),
                           (width - textWidth) / 2)
        }
    }

    func testWindowMatchesOriginalScanAcrossSeeksAndRepeatedTimestamps() {
        let comments = (0..<10_000).map { index in
            FocusVideoDanmaku(id: Int64(index), progressMilliseconds: Int64(index / 2) * 100,
                mode: .scrolling, fontSize: 25, colorRGB: nil, content: "fixture", weight: 0, pool: 0)
        }
        let placements = FocusNativeDanmakuLayout.placements(for: comments, laneCount: 100)
        for position: Int64 in [0, 1, 4_999, 5_000, 5_001, 125_000, 499_900, 600_000, 12_345, 0] {
            let reference = placements.filter {
                let elapsed = position - $0.danmaku.progressMilliseconds
                return elapsed >= 0 && elapsed < FocusNativeDanmakuLayout.displayMilliseconds
            }
            XCTAssertEqual(FocusNativeDanmakuLayout.activePlacements(in: placements, at: position).map(\.danmaku.id),
                           reference.map(\.danmaku.id), "position=\(position)")
        }
        XCTAssertTrue(FocusNativeDanmakuLayout.activePlacements(in: [], at: 0).isEmpty)
    }
}
