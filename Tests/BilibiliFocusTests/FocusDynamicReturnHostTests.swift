import FocusCore
import SwiftUI
import UIKit
import WebKit
import XCTest
@testable import BilibiliFocus

/// These regressions use the real root, router, safe areas and production lazy cards.
/// The independent UIKit probes never provide the geometry used by recovery.
@MainActor
final class FocusDynamicReturnHostTests: XCTestCase {
    func testTallCardWithNegativeTopRematerializesAtTheSavedPosition() async throws {
        let fixture = try await HostFixture.make()
        defer { fixture.close() }
        try await fixture.scroll(toID: "host-9")
        let card = try XCTUnwrap(fixture.cards.first { $0.id == "host-9" })
        let scroll = try XCTUnwrap(fixture.anchor.scrollView)
        let contentY = try fixture.frame(card.id, relativeTo: scroll).minY
        try await fixture.scroll(to: contentY + 180)
        let before = try fixture.frame(card.id)
        XCTAssertLessThan(before.minY, scroll.convert(scroll.bounds, to: fixture.window).minY)
        XCTAssertGreaterThan(before.height, scroll.bounds.height)
        fixture.anchor.capture(preferredID: card.id)
        fixture.app.open(card: card)
        await fixture.frames.next()
        let interiorLimit = scroll.contentSize.height - 2 * scroll.bounds.height + scroll.adjustedContentInset.bottom
        scroll.setContentOffset(CGPoint(x: 0, y: min(22000, interiorLimit)), animated: false)
        try await fixture.until { (try? fixture.frame(card.id)) == nil }
        fixture.back()
        assertContinuous(try await fixture.sampleReturn(id: card.id, expectedY: before.minY, duration: 0.3))
        XCTAssertEqual(fixture.anchor.fixtureCoordinator?.lastReturnOutcome, .aligned)
    }
    func testFetchedUpdatesKeepDeepReadingInPlaceAndApplyAutomaticallyAtTheTop() async throws {
        let fixture = try await HostFixture.make()
        defer { fixture.close() }
        try await fixture.scroll(to: 3200)
        let card = try fixture.visibleCard()
        let before = try fixture.frame(card.id)
        let revision = fixture.graph.dynamicFeedViewModel.dataRevision
        let prefix = (0..<2).map { index in
            DynamicCard(id: "new-head-\(index)", kind: .video,
                        author: card.author, publishTime: "new", text: "新动态 \(index)",
                        coverURLs: [], targetURL: card.targetURL, videoURL: card.videoURL)
        }
        fixture.graph.dynamicFeedViewModel.installFixturePendingPage(prefix + fixture.cards)
        XCTAssertTrue(fixture.graph.dynamicFeedViewModel.hasPendingUpdates)
        // No settle step: the independently observed real card must retain its
        // screen coordinate from the first rendered opportunity after publish.
        let deadline = CACurrentMediaTime() + 0.6
        repeat {
            await fixture.frames.next()
            XCTAssertEqual(try fixture.frame(card.id).minY, before.minY, accuracy: 2)
        } while CACurrentMediaTime() < deadline
        XCTAssertEqual(fixture.graph.dynamicFeedViewModel.dataRevision, revision)
        try await fixture.scroll(to: 0)
        try await fixture.until { !fixture.graph.dynamicFeedViewModel.hasPendingUpdates }
        let scroll = try XCTUnwrap(fixture.anchor.scrollView)
        let viewport = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: fixture.window)
        XCTAssertTrue(try fixture.frame(prefix[0].id).intersects(viewport))
    }

    func testAutomaticPrependAtTheTopShowsTheNewHeadWithoutAnchoringTheOldOne() async throws {
        let fixture = try await HostFixture.make()
        defer { fixture.close() }
        let scroll = try XCTUnwrap(fixture.anchor.scrollView)
        let card = fixture.cards[1]
        let head = DynamicCard(id: "new-top", kind: .video, author: card.author,
                               publishTime: "new", text: "最新动态", coverURLs: [],
                               targetURL: card.targetURL, videoURL: card.videoURL)
        fixture.graph.dynamicFeedViewModel.installFixturePendingPage([head] + fixture.cards)
        try await fixture.until { (try? fixture.frame(head.id)) != nil }
        let viewport = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: fixture.window)
        XCTAssertTrue(try fixture.frame(head.id).intersects(viewport))
        XCTAssertEqual(scroll.contentOffset.y + scroll.adjustedContentInset.top, 0, accuracy: 1)
        XCTAssertNil(fixture.anchor.snapshot)
        let image = UIGraphicsImageRenderer(size: fixture.window.bounds.size).image { _ in
            fixture.window.drawHierarchy(in: fixture.window.bounds, afterScreenUpdates: false)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "dynamic-top-after-automatic-refresh"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCollapsedTextAndImagesRematerializeWithoutFirstVisibleHeightChanges() async throws {
        let fixture = try await HostFixture.make(expandImageCards: false)
        defer { fixture.close() }
        for id in ["host-8", "host-9", "host-16"] {
            try await fixture.scroll(toID: id)
            let card = try XCTUnwrap(fixture.cards.first { $0.id == id })
            let before = try fixture.frame(id)
            XCTAssertFalse(fixture.graph.dynamicFeedViewModel.expansionBinding(for: card, images: false).wrappedValue)
            fixture.anchor.capture(preferredID: id)
            fixture.app.open(card: card)
            if let video = fixture.app.activeNativeVideoViewModel { video.installFixtureDetail(try Self.videoDetail()) }
            await fixture.frames.next()
            let scroll = try XCTUnwrap(fixture.anchor.scrollView)
            scroll.setContentOffset(CGPoint(x: 0, y: 22000), animated: false)
            try await fixture.until { (try? fixture.frame(id)) == nil }
            fixture.back()
            assertContinuous(try await fixture.sampleReturn(id: id, expectedY: before.minY))
            XCTAssertEqual(try fixture.frame(id).height, before.height, accuracy: 1,
                           "An unexpanded replacement card must not gain a fold button after its initial layout")
            XCTAssertEqual(fixture.anchor.fixtureCoordinator?.lastReturnOutcome, .aligned)
        }
    }

    func testOrdinaryVideoAndOpusReturnsPreserveViewportFromFirstVisibleFrame() async throws {
        let fixture = try await HostFixture.make()
        defer { fixture.close() }
        for (index, offset) in [1500.0, 3200, 4900, 6600].enumerated() {
            try await fixture.scroll(to: offset)
            let card = try fixture.visibleCard()
            let before = try fixture.frame(card.id)
            let scroll = try XCTUnwrap(fixture.anchor.scrollView)
            let size = scroll.bounds.size, inset = scroll.adjustedContentInset
            let restores = fixture.anchor.fixtureCoordinator?.fullRestorationCount
            let corrections = fixture.anchor.fixtureCoordinator?.offsetCorrectionCount
            let revision = fixture.graph.dynamicFeedViewModel.dataRevision
            fixture.anchor.capture(preferredID: card.id)
            fixture.app.open(card: card)
            if index.isMultiple(of: 2), let video = fixture.app.activeNativeVideoViewModel {
                video.installFixtureDetail(try Self.videoDetail())
            }
            try await fixture.until { !fixture.app.isDynamicFeedActive }
            await fixture.frames.next()
            XCTAssertEqual(scroll.bounds.size, size, "Detail layout must not resize the retained feed")
            XCTAssertEqual(scroll.adjustedContentInset, inset, "Detail chrome must not change feed insets")
            fixture.back()
            let samples = try await fixture.sampleReturn(id: card.id, expectedY: before.minY)
            XCTAssertTrue(fixture.anchor.scrollView === scroll)
            XCTAssertEqual(fixture.graph.dynamicFeedViewModel.dataRevision, revision)
            XCTAssertEqual(fixture.anchor.fixtureCoordinator?.fullRestorationCount, restores,
                           "Ordinary return must not start a full scroll restoration")
            XCTAssertEqual(fixture.anchor.fixtureCoordinator?.offsetCorrectionCount, corrections,
                           "Normal return must not issue compensating setContentOffset calls")
            assertContinuous(samples)
        }
    }

    func testUserExpansionAfterVisibleReturnCancelsTheOldReadingAnchor() async throws {
        for expandsImages in [false, true] {
            // This interaction needs an expandable row and its following video,
            // not an unmeasured long prefix. Deep lazy recovery is covered by
            // the separate eviction/width/continuous-navigation regressions.
            let fixture = try await HostFixture.make(expandImageCards: false, cardIndices: 9..<11)
            defer { fixture.close() }
            try await fixture.scroll(toID: "host-10")
            let scroll = try XCTUnwrap(fixture.anchor.scrollView)
            let preceding = fixture.cards[0]
            let card = fixture.cards[1]
            // Identity materialization intentionally has no top-alignment
            // contract. Position this setup from the live content coordinate,
            // then establish both rows needed by the user expansion scenario.
            try await fixture.until { (try? fixture.frame(card.id)) != nil }
            let contentY = try fixture.frame(card.id, relativeTo: scroll).minY
            let viewportHeight = scroll.bounds.height - scroll.adjustedContentInset.top - scroll.adjustedContentInset.bottom
            let videoViewportY = viewportHeight - 160
            try await fixture.scroll(to: max(0, contentY - scroll.adjustedContentInset.top - videoViewportY))
            try await fixture.until {
                guard let selectedFrame = try? fixture.frame(card.id),
                      let precedingFrame = try? fixture.frame(preceding.id) else { return false }
                let viewport = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: fixture.window)
                return selectedFrame.intersects(viewport) && precedingFrame.intersects(viewport)
            }
            let before = try fixture.frame(card.id)
            let precedingBefore = try fixture.frame(preceding.id)
            fixture.anchor.capture(preferredID: card.id)
            fixture.app.open(card: card)
            fixture.app.activeNativeVideoViewModel?.installFixtureDetail(try Self.videoDetail())
            await fixture.frames.next()
            fixture.back()
            assertContinuous(try await fixture.sampleReturn(id: card.id, expectedY: before.minY, duration: 0.15))
            let corrections = fixture.anchor.fixtureCoordinator?.offsetCorrectionCount

            // The detail has actually left the hierarchy. An explicit expand
            // action now selects a new reading layout; it is not a late image
            // download and must not pull the previously opened card back up.
            fixture.graph.dynamicFeedViewModel.expansionBinding(for: preceding, images: expandsImages).wrappedValue = true
            XCTAssertNil(fixture.anchor.snapshot, "User layout actions must revoke the old return anchor before resizing")
            assertContinuous(try await fixture.sampleReturn(id: preceding.id, expectedY: precedingBefore.minY, duration: 0.4))
            XCTAssertGreaterThan(try fixture.frame(preceding.id).height, precedingBefore.height + 20)
            XCTAssertEqual(fixture.anchor.fixtureCoordinator?.offsetCorrectionCount, corrections,
                           "The previous detail return must not fight a new text/image expansion")
        }
    }

    func testChangedSafeAreaAndWidthReturnNeverExposesUnresolvedCard() async throws {
        let fixture = try await HostFixture.make()
        defer { fixture.close() }
        for (index, offset) in [3200.0, 6600].enumerated() {
            try await fixture.scroll(to: offset)
            let card = try fixture.visibleCard()
            let before = try fixture.frame(card.id)
            fixture.anchor.capture(preferredID: card.id)
            fixture.app.open(card: card)
            await fixture.frames.next()
            if index == 0 { fixture.host.additionalSafeAreaInsets.top = 32 }
            else { fixture.host.view.bounds.size.width *= 0.8 }
            fixture.host.view.setNeedsLayout()
            fixture.host.view.layoutIfNeeded()
            await fixture.frames.next()
            fixture.host.additionalSafeAreaInsets = .zero
            fixture.host.view.frame = fixture.window.bounds
            fixture.host.view.setNeedsLayout()
            fixture.host.view.layoutIfNeeded()
            fixture.back()
            assertContinuous(try await fixture.sampleReturn(id: card.id, expectedY: before.minY))
        }
    }

    func testExpandedOpusAndPaginationKeepTheSamePhysicalCard() async throws {
        let fixture = try await HostFixture.make()
        defer { fixture.close() }
        try await fixture.scroll(toID: "host-9")
        let card = fixture.cards[9]
        let before = try fixture.frame(card.id)
        let feed = fixture.graph.dynamicFeedViewModel
        XCTAssertTrue(feed.expansionBinding(for: card, images: true).wrappedValue)
        XCTAssertTrue(feed.expansionBinding(for: card, images: false).wrappedValue)
        fixture.anchor.capture(preferredID: card.id)
        fixture.app.open(card: card)
        guard case let .opus(routeID, _) = fixture.app.route else {
            return XCTFail("An image card must enter the actual opus route")
        }
        let detail = fixture.app.opusDetailViewModel(for: routeID)
        detail.installFixtureDetail(FocusOpusDetailPage(
            id: card.id, author: .init(name: "Fixture", mid: 42, avatarURL: nil), publishTime: "fixture",
            paragraphs: [
                .init(blocks: [.text([.text(value: String(repeating: card.text, count: 4))])]),
                .init(blocks: [.image(card.coverURLs.enumerated().map { index, url in
                    FocusOpusImage(id: "image-\(index)", url: url, width: 380, height: index == 5 ? 980 : 260)
                })])
            ], comments: []))
        guard case .loaded = detail.state else { return XCTFail("The rich-detail test must not substitute an error screen") }
        await fixture.frames.next()
        // Publish a new tail while keeping the existing IDs/expanded state, as pagination does.
        let tail = DynamicCard(id: "page-tail", kind: .text, author: card.author, publishTime: "fixture",
                               text: "New page", coverURLs: [], targetURL: card.targetURL, videoURL: nil)
        feed.installFixtureCards(fixture.cards + [tail])
        await fixture.frames.next()
        fixture.back()
        assertContinuous(try await fixture.sampleReturn(id: card.id, expectedY: before.minY))
        XCTAssertEqual(try fixture.frame(card.id).height, before.height, accuracy: 2)
        XCTAssertTrue(feed.expansionBinding(for: card, images: true).wrappedValue)
        XCTAssertTrue(feed.expansionBinding(for: card, images: false).wrappedValue)
    }

    func testMissingLazyCardIsMaterializedUnderDetailBeforeItBecomesVisible() async throws {
        let fixture = try await HostFixture.make()
        defer { fixture.close() }
        let (card, y) = try await fixture.coverAndEvictCard()
        let coordinator = try XCTUnwrap(fixture.anchor.fixtureCoordinator)
        let before = coordinator.materializationCount
        fixture.back()
        XCTAssertFalse(fixture.app.isDynamicFeedActive, "Unresolved rows must remain covered by the actual detail")
        assertContinuous(try await fixture.sampleReturn(id: card.id, expectedY: y))
        XCTAssertEqual(coordinator.lastReturnOutcome, .aligned)
        XCTAssertGreaterThan(coordinator.materializationCount, before)
        XCTAssertLessThanOrEqual(coordinator.materializationCount - before, 3)
    }

    func testUncooperativeMaterializationTimesOutWithoutReportingSuccessOrTrappingBack() async throws {
        let fixture = try await HostFixture.make()
        defer { fixture.close() }
        _ = try await fixture.coverAndEvictCard()
        let coordinator = try XCTUnwrap(fixture.anchor.fixtureCoordinator)
        var requests = 0
        fixture.anchor.materialize = { _, _ in requests += 1 }
        BiliPerformanceStore.shared.clear()
        let began = CACurrentMediaTime()
        fixture.back()
        try await fixture.until { fixture.app.isDynamicFeedActive }
        XCTAssertLessThan(CACurrentMediaTime() - began, 1.3, "The maximum budget must release a stuck renderer")
        XCTAssertEqual(coordinator.lastReturnOutcome, .timedOut)
        XCTAssertGreaterThan(requests, 0)
        XCTAssertLessThanOrEqual(requests, 3)
        let events = BiliPerformanceStore.shared.snapshot()
        XCTAssertTrue(events.contains { $0.stage == .scrollReturn && $0.outcome == .timedOut })
        XCTAssertFalse(events.contains { $0.stage == .scrollRestore && $0.outcome == .success },
                       "A legal numeric offset cannot certify a missing target")
        let corrections = coordinator.offsetCorrectionCount
        await fixture.frames.next(); await fixture.frames.next()
        XCTAssertEqual(coordinator.offsetCorrectionCount, corrections, "Timeout must not expose then restart restoration")
    }

    func testNewNavigationRevokesOldReturnButKeepsRootReadingIdentity() async throws {
        let fixture = try await HostFixture.make()
        defer { fixture.close() }
        let (card, y) = try await fixture.coverAndEvictCard()
        let materialize = fixture.anchor.materialize
        fixture.anchor.materialize = { _, _ in }
        fixture.back()
        XCTAssertTrue(fixture.anchor.fixtureCoordinator?.hasPendingReturn == true)
        fixture.app.openNativeVideo(URL(string: "https://www.bilibili.com/video/BV1Q541167Qg/")!)
        XCTAssertEqual(fixture.app.routeStack.count, 3)
        XCTAssertFalse(fixture.anchor.fixtureCoordinator?.hasPendingReturn == true)
        XCTAssertEqual(fixture.anchor.snapshot?.id, card.id)
        fixture.anchor.materialize = materialize
        await fixture.frames.next()
        XCTAssertEqual(fixture.app.routeStack.count, 3, "An old completion must not pop a new detail")
        fixture.back()
        fixture.back()
        assertContinuous(try await fixture.sampleReturn(id: card.id, expectedY: y))
    }

    func testDeletedTargetUsesExplicitFallbackAndFilterChangeRevokesRecovery() async throws {
        let fixture = try await HostFixture.make()
        defer { fixture.close() }
        let (card, _) = try await fixture.coverAndEvictCard()
        fixture.graph.dynamicFeedViewModel.installFixtureCards(fixture.cards.filter { $0.id != card.id })
        await fixture.frames.next()
        fixture.back()
        try await fixture.until { fixture.app.isDynamicFeedActive }
        XCTAssertEqual(fixture.anchor.fixtureCoordinator?.lastReturnOutcome, .anchorMissing)
        XCTAssertNil(fixture.anchor.snapshot)

        _ = try await fixture.coverAndEvictCard()
        fixture.anchor.materialize = { _, _ in }
        fixture.back()
        fixture.graph.dynamicFeedViewModel.selectFilter(.video)
        try await fixture.until { fixture.app.isDynamicFeedActive }
        XCTAssertFalse(fixture.anchor.fixtureCoordinator?.hasPendingReturn == true)
        XCTAssertEqual(fixture.anchor.fixtureCoordinator?.lastReturnOutcome, .scopeChanged)
        XCTAssertNil(fixture.anchor.snapshot)
        XCTAssertEqual(fixture.graph.dynamicFeedViewModel.selectedFilter, .video)
    }

    func testRepeatedBackAndImmediateUserScrollCannotBeOverruledByOldWork() async throws {
        let fixture = try await HostFixture.make()
        defer { fixture.close() }
        _ = try await fixture.coverAndEvictCard()
        fixture.anchor.materialize = { _, _ in }
        let coordinator = try XCTUnwrap(fixture.anchor.fixtureCoordinator)
        fixture.back()
        fixture.back()
        XCTAssertTrue(fixture.app.isDynamicFeedActive)
        XCTAssertEqual(coordinator.lastReturnOutcome, .userOverride)
        let scroll = try XCTUnwrap(fixture.anchor.scrollView)
        let userOffset = scroll.contentOffset.y + 40
        scroll.setContentOffset(CGPoint(x: 0, y: userOffset), animated: false)
        coordinator.observeOffset(contentOffsetY: userOffset, isUserDriven: true)
        let corrections = coordinator.offsetCorrectionCount
        fixture.anchor.geometryDidChange()
        await fixture.frames.next(); await fixture.frames.next()
        XCTAssertNil(fixture.anchor.snapshot)
        XCTAssertEqual(coordinator.offsetCorrectionCount, corrections)
        XCTAssertEqual(scroll.contentOffset.y, userOffset, accuracy: 2)
    }

    func testImmediateUserScrollPreservesPhysicalCardWhenPendingReturnIsOverridden() async throws {
        let fixture = try await HostFixture.make()
        defer { fixture.close() }
        _ = try await fixture.coverAndEvictCard()
        // Establish the independent reading surface while still covered. The
        // eviction helper only waits for the former row to disappear, which can
        // precede registration of the newly visible lazy rows.
        try await fixture.until { (try? fixture.visibleCard()) != nil }
        let userCard = try fixture.visibleCard()
        fixture.anchor.materialize = { _, _ in }
        let coordinator = try XCTUnwrap(fixture.anchor.fixtureCoordinator)
        fixture.back()
        fixture.back()
        XCTAssertTrue(fixture.app.isDynamicFeedActive)
        XCTAssertEqual(coordinator.lastReturnOutcome, .userOverride)
        let scroll = try XCTUnwrap(fixture.anchor.scrollView)
        let userOffset = scroll.contentOffset.y + 40
        scroll.setContentOffset(CGPoint(x: 0, y: userOffset), animated: false)
        coordinator.observeOffset(contentOffsetY: userOffset, isUserDriven: true)
        let userCardY = try fixture.frame(userCard.id).minY
        func readingSample() throws -> [String: Double] {
            ["offsetY": Double(scroll.contentOffset.y),
             "windowY": Double(try fixture.frame(userCard.id).minY),
             "contentY": Double(try fixture.frame(userCard.id, relativeTo: scroll).minY),
             "contentHeight": Double(scroll.contentSize.height),
             "viewportHeight": Double(scroll.bounds.height),
             "insetTop": Double(scroll.adjustedContentInset.top),
             "insetBottom": Double(scroll.adjustedContentInset.bottom),
             "sameScroll": fixture.anchor.scrollView === scroll ? 1 : 0,
             "sameCoordinator": fixture.anchor.fixtureCoordinator === coordinator ? 1 : 0]
        }
        var userSamples = [try readingSample()]
        let corrections = coordinator.offsetCorrectionCount
        fixture.anchor.geometryDidChange()
        await fixture.frames.next(); userSamples.append(try readingSample())
        await fixture.frames.next(); userSamples.append(try readingSample())
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: userSamples),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "user-scroll-coordinate-and-physical-position"
        attachment.lifetime = .keepAlways
        add(attachment)
        for sample in userSamples.dropFirst() {
            XCTAssertEqual(try XCTUnwrap(sample["windowY"]), Double(userCardY), accuracy: 2,
                           "The real user-selected card must stay in the same physical position")
        }
        XCTAssertNil(fixture.anchor.snapshot)
        XCTAssertEqual(coordinator.offsetCorrectionCount, corrections)
        XCTAssertEqual(scroll.contentOffset.y, userOffset, accuracy: 2)
    }

    func testBottomInsetAndDynamicTypeReflowAreAlignedBeforeRootTabReturn() async throws {
        let fixture = try await HostFixture.make()
        defer { fixture.close() }
        try await fixture.scroll(toID: "host-8")
        let card = fixture.cards[8]
        let y = try fixture.frame(card.id).minY
        fixture.anchor.capture(preferredID: card.id)
        fixture.app.open(card: card)
        await fixture.frames.next()
        fixture.host.additionalSafeAreaInsets.bottom = 44
        if #available(iOS 17.0, *) { fixture.host.traitOverrides.preferredContentSizeCategory = .extraExtraExtraLarge }
        fixture.host.view.setNeedsLayout(); fixture.host.view.layoutIfNeeded()
        await fixture.frames.next()
        fixture.returnToDynamic() // The bottom tab must use the same guarded return path.
        assertContinuous(try await fixture.sampleReturn(id: card.id, expectedY: y))
        XCTAssertEqual(fixture.app.routeStack.count, 1)
    }

    func testFullscreenPresentationAndDismissalPreserveFeedReadingPosition() async throws {
        let fixture = try await HostFixture.make()
        defer { fixture.close() }
        try await fixture.scroll(toID: "host-8")
        let card = fixture.cards[8]
        let before = try fixture.frame(card.id)
        fixture.anchor.capture(preferredID: card.id)
        fixture.app.open(card: card)
        let video = try XCTUnwrap(fixture.app.activeNativeVideoViewModel)
        video.installFixtureDetail(try Self.videoDetail())
        await fixture.frames.next()
        video.isFullscreen = true
        try await fixture.until { fixture.host.presentedViewController != nil }
        video.isFullscreen = false
        try await fixture.until { fixture.host.presentedViewController == nil }
        fixture.back()
        assertContinuous(try await fixture.sampleReturn(id: card.id, expectedY: before.minY))
    }

    func testLandscapeFullscreenWhileFeedIsCoveredDoesNotDriftAnchorOnReturn() async throws {
        let fixture = try await HostFixture.make()
        defer { fixture.close() }
        try await fixture.scroll(toID: "host-8")
        let card = fixture.cards[8]
        let before = try fixture.frame(card.id)
        let scroll = try XCTUnwrap(fixture.anchor.scrollView)
        let readingViewport = scroll.bounds.size
        let readingInsets = scroll.adjustedContentInset
        fixture.anchor.capture(preferredID: card.id)
        fixture.app.open(card: card)
        await fixture.frames.next()
        // Landscape fullscreen rotates the window scene while the feed is covered.
        let portrait = fixture.host.view.frame
        fixture.host.view.frame = CGRect(origin: .zero, size: CGSize(width: portrait.height, height: portrait.width))
        fixture.host.view.setNeedsLayout(); fixture.host.view.layoutIfNeeded()
        await fixture.frames.next(); await fixture.frames.next()
        XCTAssertEqual(scroll.bounds.size, readingViewport,
                       "A detail's landscape scene must not resize the covered list; host=\(fixture.host.view.bounds.size), hostSafeArea=\(fixture.host.view.safeAreaInsets), scrollSafeArea=\(scroll.safeAreaInsets)")
        XCTAssertEqual(scroll.adjustedContentInset, readingInsets,
                       "The covered list must not consume the resized scene's safe areas again")
        fixture.host.view.frame = portrait
        fixture.host.view.setNeedsLayout(); fixture.host.view.layoutIfNeeded()
        fixture.back()
        assertContinuous(try await fixture.sampleReturn(id: card.id, expectedY: before.minY))
        XCTAssertEqual(fixture.app.routeStack.count, 1)
    }

    func testRepeatedFastReturnsAndInFlightWidthChangesNeverExposeMissingCards() async throws {
        let fixture = try await HostFixture.make()
        defer { fixture.close() }
        for pass in 0..<4 {
            let (card, y) = try await fixture.coverAndEvictCard()
            let originalWidth = fixture.host.view.bounds.width
            fixture.host.view.bounds.size.width = originalWidth * 0.85
            fixture.host.view.setNeedsLayout(); fixture.host.view.layoutIfNeeded()
            fixture.back()
            XCTAssertFalse(fixture.app.isDynamicFeedActive)
            // A second real layout arrives while identity recovery is pending.
            fixture.host.view.frame = fixture.window.bounds
            fixture.host.view.setNeedsLayout(); fixture.host.view.layoutIfNeeded()
            let samples = try await fixture.sampleReturn(id: card.id, expectedY: y, duration: 0.2)
            assertContinuous(samples)
            XCTAssertEqual(fixture.app.routeStack.count, 1, "Return \(pass) must terminate")
        }
    }

    func testOpenAndBackWithinOneRenderTransactionDoNotLeaveAnOldFreeze() async throws {
        let fixture = try await HostFixture.make()
        defer { fixture.close() }
        try await fixture.scroll(to: 3200)
        let card = try fixture.visibleCard()
        let y = try fixture.frame(card.id).minY
        let coordinator = try XCTUnwrap(fixture.anchor.fixtureCoordinator)
        let corrections = coordinator.offsetCorrectionCount
        let restores = coordinator.fullRestorationCount
        for _ in 0..<6 {
            fixture.anchor.capture(preferredID: card.id)
            fixture.app.open(card: card)
            fixture.back() // Deliberately no rendering opportunity between these calls.
            XCTAssertTrue(fixture.app.isDynamicFeedActive)
        }
        assertContinuous(try await fixture.sampleReturn(id: card.id, expectedY: y))
        XCTAssertEqual(coordinator.offsetCorrectionCount, corrections)
        XCTAssertEqual(coordinator.fullRestorationCount, restores)
        fixture.app.open(card: card)
        await fixture.frames.next()
        fixture.back()
        assertContinuous(try await fixture.sampleReturn(id: card.id, expectedY: y))
    }

    func testGeometryBurstCannotExhaustIdentityRequestsBeforeRenderingCatchesUp() async throws {
        let fixture = try await HostFixture.make()
        defer { fixture.close() }
        let (card, y) = try await fixture.coverAndEvictCard()
        let materialize = try XCTUnwrap(fixture.anchor.materialize)
        var rendererReady = false
        var requests = 0
        fixture.anchor.materialize = { id, point in
            requests += 1
            if rendererReady { materialize(id, point) }
        }
        fixture.back()
        // Deliver several layout notifications before the next rendered
        // layout is able to consume a ScrollViewReader request.
        for _ in 0..<6 {
            fixture.anchor.geometryDidChange()
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        await fixture.frames.next(); await fixture.frames.next()
        rendererReady = true
        assertContinuous(try await fixture.sampleReturn(id: card.id, expectedY: y))
        XCTAssertEqual(fixture.anchor.fixtureCoordinator?.lastReturnOutcome, .aligned)
        XCTAssertLessThanOrEqual(requests, 3, "Do not solve scheduling by increasing the request budget")
    }

    private func assertContinuous(_ samples: [ReturnSample], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(samples.isEmpty, "A real visible event must be observed", file: file, line: line)
        XCTAssertTrue(samples.allSatisfy { $0.y != nil }, "Target card missing during visible return", file: file, line: line)
        let errors = samples.compactMap(\.error)
        XCTAssertLessThanOrEqual(errors.map(abs).max() ?? .infinity, 2,
                                 "The whole visible return, not just its last frame, must be correct", file: file, line: line)
        if let last = errors.last { XCTAssertEqual(last, 0, accuracy: 2, file: file, line: line) }
    }

    private static func videoDetail() throws -> FocusVideoDetail {
        let data = try JSONSerialization.data(withJSONObject: ["code": 0, "data": [
            "bvid": "BV1xx411c7mD", "aid": 1, "cid": 11, "title": "Fixture detail", "duration": 120,
            "desc": String(repeating: "Synthetic description. ", count: 40),
            "owner": ["mid": 10, "name": "Fixture", "face": ""],
            "pages": [["cid": 11, "page": 1, "duration": 120, "part": "Part 1"]]
        ]])
        return try FocusVideoDetailService.decodeDetailResponse(data)
    }
}

private struct ReturnSample: Codable {
    let milliseconds: Double
    let y: Double?
    let error: Double?
}

private struct ReturnTraceSummary: Codable {
    let requestToVisibleMilliseconds: Double?
    let requestToAlignedVisibleMilliseconds: Double?
    let visibleSamples: Int
    let missingFrames: Int
    let maximumVisibleErrorPoints: Double?
    let fullRestorations: Int
    let offsetCorrections: Int
    let materializationRequests: Int
    let returnOutcome: String
}

@MainActor
private final class HostFixture {
    let graph: FocusAppGraph
    let app: FocusAppViewModel
    let host: UIHostingController<FocusBrowserView>
    let window: UIWindow
    let cards: [DynamicCard]
    let frames = FrameEvents()
    private var returnRequestedAt: CFTimeInterval?
    private var correctionsBeforeReturn = 0
    private var restoresBeforeReturn = 0
    private var materializationsBeforeReturn = 0

    private func beginReturnMeasurement() {
        guard anchor.fixtureCoordinator?.hasPendingReturn != true else { return }
        returnRequestedAt = CACurrentMediaTime()
        correctionsBeforeReturn = anchor.fixtureCoordinator?.offsetCorrectionCount ?? 0
        restoresBeforeReturn = anchor.fixtureCoordinator?.fullRestorationCount ?? 0
        materializationsBeforeReturn = anchor.fixtureCoordinator?.materializationCount ?? 0
    }

    func back() {
        beginReturnMeasurement()
        app.handleTopLevelBack()
    }

    func returnToDynamic() {
        beginReturnMeasurement()
        app.open(.dynamic)
    }
    var anchor: FocusDynamicFeedVisualAnchor { graph.dynamicFeedViewModel.fixtureAnchor! }

    private init(graph: FocusAppGraph, app: FocusAppViewModel, host: UIHostingController<FocusBrowserView>, window: UIWindow, cards: [DynamicCard]) {
        self.graph = graph; self.app = app; self.host = host; self.window = window; self.cards = cards
    }

    static func make(expandImageCards: Bool = true, cardIndices: Range<Int> = 0..<80) async throws -> HostFixture {
        XCTAssertTrue(FocusTestRuntime.isRunningFixtures)
        let store = WKWebsiteDataStore.nonPersistent()
        for (name, value) in [("SESSDATA", "synthetic-scroll-only"), ("DedeUserID", "42")] {
            let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: ".bilibili.com", .path: "/", .name: name, .value: value]))
            await store.httpCookieStore.setCookie(cookie)
        }
        let cookies = WebViewCookieSnapshotProvider(websiteDataStore: store, performsLoginWarmup: false)
        _ = await cookies.loadSnapshot()
        let defaults = UserDefaults(suiteName: "scroll-fixture-" + UUID().uuidString)!
        let settings = FocusSettingsStore(userDefaults: defaults)
        let graph = FocusAppGraph(settingsStore: settings, cookieProvider: cookies)
        let app = graph.makeAppViewModel()
        let cards: [DynamicCard] = cardIndices.map { index in
            let video = URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
            let opus = URL(string: "https://www.bilibili.com/opus/\(1000 + index)")!
            return DynamicCard(id: "host-\(index)", kind: index.isMultiple(of: 3) ? .image : .video,
                author: .init(name: "Fixture", avatarURL: nil), publishTime: "fixture",
                text: String(repeating: "真实组件长文本布局，仅合成测试。\n", count: 4 + (index % 7) * 3),
                coverURLs: (0..<(index.isMultiple(of: 3) ? 6 : 1)).map { URL(string: "https://focus-image.test/\($0).png")! },
                targetURL: index.isMultiple(of: 3) ? opus : video,
                videoURL: index.isMultiple(of: 3) ? nil : video)
        }
        graph.dynamicFeedViewModel.installFixtureCards(cards)
        for card in cards where expandImageCards && card.kind == .image {
            graph.dynamicFeedViewModel.expansionBinding(for: card, images: true).wrappedValue = true
            graph.dynamicFeedViewModel.expansionBinding(for: card, images: false).wrappedValue = true
        }
        let host = UIHostingController(rootView: FocusBrowserView(appGraph: graph, appViewModel: app))
        // Deliberately keep default safeAreaRegions and the actual navigation bar.
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        window.layoutIfNeeded()
        let fixture = HostFixture(graph: graph, app: app, host: host, window: window, cards: cards)
        do {
            try await fixture.until { graph.dynamicFeedViewModel.fixtureAnchor?.scrollView?.window != nil }
            // Establish the initial rendered user viewport before test actions.
            // Return sampling deliberately has no corresponding settle step.
            try await fixture.scroll(to: 0)
            return fixture
        } catch {
            fixture.close()
            throw error
        }
    }

    func close() {
        graph.dynamicFeedViewModel.cancelDetailReturn()
        graph.dynamicFeedViewModel.suspend()
        app.activeNativeVideoViewModel?.suspend()
        frames.stop()
        window.isHidden = true
        window.rootViewController = nil
    }

    func until(file: StaticString = #filePath, line: UInt = #line, _ predicate: () -> Bool) async throws {
        let deadline = CACurrentMediaTime() + 5
        while !predicate(), CACurrentMediaTime() < deadline { await frames.next() }
        guard predicate() else {
            throw NSError(domain: "HostFixture", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Expected layout event not received at \(file):\(line); routeDepth=\(app.routeStack.count), offset=\(anchor.scrollView?.contentOffset.y ?? -1), pending=\(anchor.fixtureCoordinator?.hasPendingReturn == true)"])
        }
    }

    func scroll(to y: CGFloat) async throws {
        let scroll = try XCTUnwrap(anchor.scrollView)
        scroll.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        anchor.fixtureCoordinator?.observeOffset(contentOffsetY: y, isUserDriven: true)
        var previous: CGRect?
        var stable = 0
        try await until {
            guard let card = try? self.visibleCard(), let frame = try? self.frame(card.id) else { return false }
            stable = frame == previous ? stable + 1 : 0; previous = frame
            return stable >= 2
        }
    }

    func scroll(toID id: String) async throws {
        try await until { self.anchor.materialize != nil }
        let initialScroll = try XCTUnwrap(anchor.scrollView)
        // This is user-directed setup, not return recovery. Cancel the initial
        // top-of-feed restoration before asking the real reader to scroll.
        anchor.fixtureCoordinator?.observeOffset(contentOffsetY: initialScroll.contentOffset.y, isUserDriven: true)
        // User-directed initial navigation may need another identity request
        // after a never-seen lazy row replaces its estimated height. This is
        // bounded setup; the production return budget is tested separately.
        for _ in 0..<3 {
            anchor.materialize?(id, .top)
            await frames.next(); await frames.next()
            if (try? frame(id)) != nil { break }
        }
        try await until { (try? self.frame(id)) != nil }
        await frames.next(); await frames.next()
        let scroll = try XCTUnwrap(anchor.scrollView)
        anchor.fixtureCoordinator?.observeOffset(contentOffsetY: scroll.contentOffset.y, isUserDriven: true)
    }

    func coverAndEvictCard() async throws -> (DynamicCard, CGFloat) {
        try await scroll(to: 3200)
        let card = try visibleCard()
        let y = try frame(card.id).minY
        anchor.capture(preferredID: card.id)
        app.open(card: card)
        await frames.next()
        let scroll = try XCTUnwrap(anchor.scrollView)
        // Evict the old identity at a legal interior position. A hard-coded
        // 22000 can overscroll this estimated lazy content; UIKit then clamps
        // it when the tail estimate shrinks, independently of return recovery.
        // Leave one viewport of tail room for the immediate +40 user input.
        let interiorLimit = scroll.contentSize.height - 2 * scroll.bounds.height + scroll.adjustedContentInset.bottom
        scroll.setContentOffset(CGPoint(x: 0, y: min(22000, interiorLimit)), animated: false)
        try await until { (try? self.frame(card.id)) == nil }
        return (card, y)
    }

    func allViews(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(allViews) }
    func frame(_ id: String, relativeTo target: UIView? = nil,
               file: StaticString = #filePath, line: UInt = #line) throws -> CGRect {
        // A reused UIView can stay window-attached after its lazy row leaves
        // layout. Measure only the independently observed, non-hidden subtree.
        guard let scroll = anchor.scrollView,
              let marker = allViews(host.view).first(where: { view in
                  guard view.accessibilityIdentifier == "focus-fixture-card:" + id, view.window != nil else { return false }
                  var current: UIView? = view
                  while let node = current, node !== scroll {
                      if node.isHidden || node.alpha == 0 { return false }
                      current = node.superview
                  }
                  return current === scroll
              }) else {
            throw NSError(domain: "HostFixture.missingCard", code: 2, userInfo: [NSLocalizedDescriptionKey:
                "Missing active card \(id) at \(file):\(line)"])
        }
        return marker.convert(marker.bounds, to: target ?? window)
    }
    func visibleCard() throws -> DynamicCard {
        let scroll = try XCTUnwrap(anchor.scrollView)
        let viewport = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: window)
        let visible = cards.compactMap { card -> (DynamicCard, CGRect)? in
            guard let frame = try? self.frame(card.id), frame.height > 0,
                  frame.maxY > viewport.minY, frame.minY < viewport.maxY else { return nil }
            return (card, frame)
        }
        guard let selected = visible.first(where: { $0.1.minY >= viewport.minY }) ?? visible.first else {
            throw NSError(domain: "HostFixture.noVisibleCard", code: 3)
        }
        return selected.0
    }

    func sampleReturn(id: String, expectedY: CGFloat, duration: TimeInterval = 1.6) async throws -> [ReturnSample] {
        let start = CACurrentMediaTime()
        var visibleStart: CFTimeInterval?
        var samples: [ReturnSample] = []
        repeat {
            await frames.next()
            let detailIsMounted = allViews(host.view).contains {
                $0.accessibilityIdentifier == "focus-fixture-detail-cover" && $0.window != nil
            }
            guard app.isDynamicFeedActive, !detailIsMounted else {
                if CACurrentMediaTime() - start > 5 { XCTFail("Return never completed"); break }
                continue
            }
            if visibleStart == nil { visibleStart = CACurrentMediaTime() }
            let y = try? frame(id).minY
            samples.append(ReturnSample(milliseconds: (CACurrentMediaTime() - visibleStart!) * 1000,
                                        y: y.map(Double.init), error: y.map { Double($0 - expectedY) }))
        } while visibleStart == nil || CACurrentMediaTime() - visibleStart! < duration
        let attachment = XCTAttachment(data: try JSONEncoder().encode(samples), uniformTypeIdentifier: "public.json")
        attachment.name = "visible-return-" + id; attachment.lifetime = .keepAlways
        let reveal = visibleStart.map { ($0 - (returnRequestedAt ?? start)) * 1000 }
        let summary = ReturnTraceSummary(
            requestToVisibleMilliseconds: reveal,
            requestToAlignedVisibleMilliseconds: reveal.flatMap { offset in
                samples.first(where: { $0.error.map { abs($0) <= 2 } ?? false }).map { offset + $0.milliseconds }
            },
            visibleSamples: samples.count,
            missingFrames: samples.filter { $0.y == nil }.count,
            maximumVisibleErrorPoints: samples.compactMap(\.error).map(abs).max(),
            fullRestorations: (anchor.fixtureCoordinator?.fullRestorationCount ?? 0) - restoresBeforeReturn,
            offsetCorrections: (anchor.fixtureCoordinator?.offsetCorrectionCount ?? 0) - correctionsBeforeReturn,
            materializationRequests: (anchor.fixtureCoordinator?.materializationCount ?? 0) - materializationsBeforeReturn,
            returnOutcome: String(describing: anchor.fixtureCoordinator?.lastReturnOutcome))
        let metadata = XCTAttachment(data: try JSONEncoder().encode(summary), uniformTypeIdentifier: "public.json")
        metadata.name = "return-metrics-" + id; metadata.lifetime = .keepAlways
        XCTContext.runActivity(named: "Return continuity") { $0.add(attachment); $0.add(metadata) }
        return samples
    }
}

@MainActor
private final class FrameEvents: NSObject {
    private var link: CADisplayLink?
    private var waiting: CheckedContinuation<Void, Never>?
    func next() async {
        if link == nil {
            link = CADisplayLink(target: self, selector: #selector(tick))
            link?.add(to: .main, forMode: .common)
        }
        await withCheckedContinuation { waiting = $0 }
    }
    @objc private func tick() { let continuation = waiting; waiting = nil; continuation?.resume() }
    func stop() { link?.invalidate(); link = nil; let continuation = waiting; waiting = nil; continuation?.resume() }
}
