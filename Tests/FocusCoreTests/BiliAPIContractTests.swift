import Foundation
import Testing
@testable import FocusCore

@Suite("bilibili-api contract catalog")
struct BiliAPIContractTests {
    @Test("loads the independently maintained endpoint subset")
    func loadsSnapshot() {
        let snapshot = BiliAPIContractCatalog.snapshot

        #expect(snapshot.schemaVersion == 1)
        #expect(snapshot.endpoints.count >= 40)
        #expect(snapshot.source.validatedCommit.count == 40)
        #expect(snapshot.source.repository.host == "github.com")
    }

    @Test("exposes local endpoint metadata")
    func exposesEndpointMetadata() {
        let endpoint = BiliAPIContractCatalog.require("video.info.get_player_info")

        #expect(endpoint.url.absoluteString == "https://api.bilibili.com/x/player/wbi/v2")
        #expect(endpoint.method == "GET")
        #expect(endpoint.requiresAuthentication)
        #expect(endpoint.usesWBI)
    }

    @Test("includes watch-later read and write contracts")
    func includesWatchLaterContracts() {
        #expect(
            BiliAPIContractCatalog.require("toview.info.list").url.path ==
                "/x/v2/history/toview"
        )
        #expect(BiliAPIContractCatalog.require("toview.operate.add").method == "POST")
        #expect(BiliAPIContractCatalog.require("toview.operate.del").requiresAuthentication)
    }
}
