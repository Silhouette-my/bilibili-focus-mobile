import Foundation
import Testing
@testable import FocusCore

struct PerformanceDiagnosticsTests {
    @Test func ringIsBoundedAndSpansDeduplicate() {
        let store = BiliPerformanceStore(capacity: 2)
        let correlation = UUID()
        let first = store.begin(.videoDetail, correlationID: correlation)
        store.end(first)
        store.end(first)
        #expect(store.snapshot().count == 1)
        store.end(store.begin(.playerReady, correlationID: correlation))
        store.end(store.begin(.firstFrame, correlationID: correlation), count: -1, positionErrorPoints: .infinity)
        let events = store.snapshot()
        #expect(events.map(\.stage) == [.playerReady, .firstFrame])
        #expect(events.allSatisfy { $0.correlationID == correlation && $0.durationMilliseconds >= 0 })
        #expect(events.last?.count == 0)
        #expect(events.last?.positionErrorPoints == nil)
    }

    @Test func diagnosticsExportIncludesDistinctPhasesWithoutUserFields() async throws {
        let store = BiliPerformanceStore()
        let correlation = UUID()
        for stage in [BiliPerformanceStage.dynamicFirstPage, .dynamicDisplayed, .playerReady, .firstFrame] {
            store.end(store.begin(stage, correlationID: correlation))
        }
        let snapshot = await BiliDiagnostics.snapshot(
            loginHealth: .unknown, eventStore: BiliNetworkEventStore(), performanceStore: store
        )
        #expect(snapshot.performanceEvents.count == 4)
        let data = try snapshot.jsonData()
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("Cookie"))
        #expect(!text.contains("query"))
        #expect(try JSONDecoder().decode(BiliDiagnosticSnapshot.self, from: data) == snapshot)
    }
}
