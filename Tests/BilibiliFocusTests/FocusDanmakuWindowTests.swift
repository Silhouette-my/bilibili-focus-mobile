import FocusCore
import CoreGraphics
import XCTest
@testable import BilibiliFocus

final class FocusDanmakuWindowTests: XCTestCase {
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
