import Foundation
import Testing
@testable import FocusCore

@Suite("bilibili-api contract catalog")
struct BiliAPIContractTests {
    @Test("loads the endpoint contract catalog")
    func loadsSnapshot() {
        let snapshot = BiliAPIContractCatalog.snapshot

        #expect(snapshot.schemaVersion == 1)
        #expect(snapshot.endpoints.count >= 40)
    }

    @Test("exposes local endpoint metadata")
    func exposesEndpointMetadata() {
        let endpoint = BiliAPIContractCatalog.require("video.info.get_player_info")

        #expect(endpoint.url.absoluteString == "https://api.bilibili.com/x/player/wbi/v2")
        #expect(endpoint.method == "GET")
        #expect(endpoint.requiresAuthentication)
        #expect(endpoint.usesWBI)
    }

    @Test("includes authenticated content management contracts")
    func includesManagementContracts() {
        #expect(BiliAPIContractCatalog.require("common.comment.send").usesWBI)
        #expect(BiliAPIContractCatalog.require("common.comment.del").requiresAuthentication)
        #expect(BiliAPIContractCatalog.require("favorite-list.operate.content_move").method == "POST")
    }
}
