import UIKit
import SwiftUI
import XCTest
@testable import BilibiliFocus

@MainActor
final class FocusDynamicScrollRestorationTests: XCTestCase {
    func testMaterializationPointPreservesUnboundedSavedPositionsWithoutUsingCardHeight() throws {
        for y: CGFloat in [-1200, -1, 0, 311.6667, 619.3333, 740, 1200] {
            let point = try XCTUnwrap(FocusDynamicFeedVisualAnchor.materializationPoint(viewportY: y, viewportHeight: 740))
            XCTAssertEqual(point.y * (740 - 1), y, accuracy: 0.0001)
        }
        XCTAssertGreaterThan(try XCTUnwrap(FocusDynamicFeedVisualAnchor.materializationPoint(viewportY: 740, viewportHeight: 740)).y, 1)
        XCTAssertNil(FocusDynamicFeedVisualAnchor.materializationPoint(viewportY: 0, viewportHeight: 1))
    }
    func testLateGeometryFromDisappearedRowCannotReRegisterAnInactiveOwner() {
        let anchor = FocusDynamicFeedVisualAnchor()
        let owner = UUID()
        let frame = CGRect(x: 0, y: 800, width: 390, height: 120)
        anchor.registerFrame(frame, id: "retained", owner: owner)
        anchor.removeFrame(id: "retained", owner: owner)
        anchor.updateFrame(frame, id: "retained", owner: owner)
        XCTAssertNil(anchor.frame(for: "retained"), "A retained platform view is not an active lazy row")
        anchor.registerFrame(frame, id: "retained", owner: owner)
        XCTAssertEqual(anchor.frame(for: "retained"), frame, "Only a real new appearance may re-register the row")
    }

    func testFrameworkRebasesContentAndOffsetTogetherWithoutFightingTheLayout() async throws {
        let harness = makeUIKitHarness()
        defer { harness.coordinator.detach(); harness.window.isHidden = true }
        let scroll = harness.scrollView, anchor = harness.anchor, coordinator = harness.coordinator
        var saved: CGFloat = 700
        anchor.scrollView = scroll
        harness.card.frame.origin.y = 1000
        scroll.setContentOffset(CGPoint(x: 0, y: saved), animated: false)
        anchor.updateFrame(harness.card.frame, id: "selected")
        anchor.capture(preferredID: "selected")
        func activate(_ active: Bool) {
            coordinator.update(probe: harness.probe, offsetY: saved, restorationRevision: 0,
                isActive: active, visualAnchor: anchor, onOffsetChange: { saved = $0 })
        }
        activate(true)
        let attached = await eventually { coordinator.fullRestorationCount == 1 }
        XCTAssertTrue(attached)
        activate(false)
        var outcome: FocusDynamicReturnOutcome?
        coordinator.prepareForReturn { outcome = $0 }
        XCTAssertEqual(outcome, .preserved)
        activate(true)
        let frames = TextSizingFrameEvents()
        defer { frames.stop() }
        await frames.next()
        let corrections = coordinator.offsetCorrectionCount
        // Simulate the framework's two notifications within one render cycle:
        // estimated content coordinates and offset move by the same amount.
        scroll.setContentOffset(CGPoint(x: 0, y: 740), animated: false)
        DispatchQueue.main.async {
            harness.card.frame.origin.y += 40
            anchor.updateFrame(harness.card.frame, id: "selected")
        }
        await frames.next(); await frames.next()
        XCTAssertEqual(harness.card.convert(harness.card.bounds, to: harness.window).minY, 300, accuracy: 1)
        XCTAssertEqual(coordinator.offsetCorrectionCount, corrections,
                       "Do not fight an in-progress framework rebase that preserves the physical viewport")
    }

    func testPreservedReturnIgnoresGeometryNotificationsWhenTheActualCardHasNotMoved() async throws {
        let harness = makeUIKitHarness()
        defer { harness.coordinator.detach(); harness.window.isHidden = true }
        let scroll = harness.scrollView, anchor = harness.anchor, coordinator = harness.coordinator
        var saved: CGFloat = 700
        anchor.scrollView = scroll
        scroll.setContentOffset(CGPoint(x: 0, y: saved), animated: false)
        anchor.updateFrame(harness.card.frame, id: "selected")
        anchor.capture(preferredID: "selected")
        func activate(_ active: Bool) {
            coordinator.update(probe: harness.probe, offsetY: saved, restorationRevision: 0,
                isActive: active, visualAnchor: anchor, onOffsetChange: { saved = $0 })
        }
        activate(true)
        let attached = await eventually { coordinator.fullRestorationCount == 1 }
        XCTAssertTrue(attached)
        activate(false); activate(true)
        await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
        let compensations = coordinator.layoutCompensationCount
        let corrections = coordinator.offsetCorrectionCount
        let y = harness.card.convert(harness.card.bounds, to: harness.window).minY
        // Pagination below the viewport and repeated layout notices are not a
        // movement of the reading anchor. No compensation pass should be run.
        for _ in 0..<4 {
            scroll.contentSize.height += 120
            anchor.updateFrame(harness.card.frame, id: "selected")
            await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
            await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
        }
        XCTAssertEqual(harness.card.convert(harness.card.bounds, to: harness.window).minY, y, accuracy: 1)
        XCTAssertEqual(coordinator.offsetCorrectionCount, corrections)
        XCTAssertEqual(coordinator.layoutCompensationCount, compensations,
                       "Geometry observation alone is not a reason to run another compensating layout")
    }

    func testOpeningDetailDuringDecelerationStopsMomentumWithoutMovingTheCard() async throws {
        let harness = makeUIKitHarness()
        defer { harness.coordinator.detach(); harness.window.isHidden = true }
        let scroll = harness.scrollView, anchor = harness.anchor, coordinator = harness.coordinator
        var saved: CGFloat = 700
        anchor.scrollView = scroll
        scroll.setContentOffset(CGPoint(x: 0, y: saved), animated: false)
        anchor.updateFrame(harness.card.frame, id: "selected")
        anchor.capture(preferredID: "selected")
        func activate(_ active: Bool) {
            coordinator.update(probe: harness.probe, offsetY: saved, restorationRevision: 0,
                               isActive: active, visualAnchor: anchor, onOffsetChange: { saved = $0 })
        }
        activate(true)
        let attached = await eventually { coordinator.fullRestorationCount == 1 }
        XCTAssertTrue(attached)
        let y = harness.card.convert(harness.card.bounds, to: harness.window).minY
        let calls = scroll.programmaticSetCount
        scroll.testIsDecelerating = true
        anchor.freezeForDetails?()
        XCTAssertFalse(scroll.testIsDecelerating)
        XCTAssertEqual(scroll.programmaticSetCount, calls + 1, "Only stop the real residual momentum")
        activate(false)
        activate(true)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        XCTAssertEqual(harness.card.convert(harness.card.bounds, to: harness.window).minY, y, accuracy: 1)
        XCTAssertEqual(scroll.programmaticSetCount, calls + 1, "Return itself must not move the retained list")
    }

    func testUnreachablePhysicalAnchorFinishesAsClampedNotSuccessful() async throws {
        let harness = makeUIKitHarness()
        defer { harness.coordinator.detach(); harness.window.isHidden = true }
        let scroll = harness.scrollView, anchor = harness.anchor, coordinator = harness.coordinator
        var saved: CGFloat = 700
        anchor.scrollView = scroll
        scroll.setContentOffset(CGPoint(x: 0, y: saved), animated: false)
        anchor.updateFrame(harness.card.frame, id: "selected")
        anchor.capture(preferredID: "selected")
        func activate(_ active: Bool) {
            coordinator.update(probe: harness.probe, offsetY: saved, restorationRevision: 0,
                               isActive: active, visualAnchor: anchor, onOffsetChange: { saved = $0 })
        }
        activate(true)
        let attached = await eventually { coordinator.fullRestorationCount == 1 }
        XCTAssertTrue(attached)
        activate(false)
        harness.card.frame.origin.y = 60
        anchor.updateFrame(harness.card.frame, id: "selected")
        let outcome = await withCheckedContinuation { continuation in
            coordinator.prepareForReturn { continuation.resume(returning: $0) }
        }
        XCTAssertEqual(outcome, .clamped, "A shortened list cannot reach a now-negative requested offset")
        XCTAssertEqual(coordinator.lastReturnOutcome, .clamped)
        XCTAssertNil(anchor.snapshot)
        XCTAssertEqual(scroll.contentOffset.y, 0, accuracy: 1)
    }

    func testOffsetOnlyFrameworkMovementAfterPreservedReturnIsLocallyCompensated() async throws {
        let harness = makeUIKitHarness()
        defer { harness.coordinator.detach(); harness.window.isHidden = true }
        let scroll = harness.scrollView, anchor = harness.anchor, coordinator = harness.coordinator
        var saved: CGFloat = 700
        anchor.scrollView = scroll
        harness.card.frame.origin.y = 1000
        scroll.setContentOffset(CGPoint(x: 0, y: saved), animated: false)
        anchor.updateFrame(harness.card.frame, id: "selected")
        anchor.capture(preferredID: "selected")
        func activate(_ active: Bool) {
            coordinator.update(probe: harness.probe, offsetY: saved, restorationRevision: 0,
                               isActive: active, visualAnchor: anchor, onOffsetChange: { saved = $0 })
        }
        activate(true)
        let attached = await eventually { coordinator.fullRestorationCount == 1 }
        XCTAssertTrue(attached)
        activate(false)
        activate(true)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        let restores = coordinator.fullRestorationCount
        scroll.setContentOffset(CGPoint(x: 0, y: 740), animated: false)
        let aligned = await eventually { abs(harness.card.convert(harness.card.bounds, to: harness.window).minY - 300) <= 1 }
        XCTAssertTrue(aligned)
        XCTAssertEqual(coordinator.fullRestorationCount, restores, "Offset-only change needs one local correction, not a new full restore")
        XCTAssertLessThanOrEqual(coordinator.offsetCorrectionCount, 2)
    }

    func testReplacedRowCannotRemoveOrOverwriteNewMeasurementForSameStableID() {
        let anchor = FocusDynamicFeedVisualAnchor()
        let oldOwner = UUID(), newOwner = UUID()
        let oldFrame = CGRect(x: 0, y: 100, width: 390, height: 200)
        let newFrame = CGRect(x: 0, y: 122, width: 390, height: 400)
        anchor.registerFrame(oldFrame, id: "fixture", owner: oldOwner)
        anchor.registerFrame(newFrame, id: "fixture", owner: newOwner)
        anchor.removeFrame(id: "fixture", owner: oldOwner)
        anchor.updateFrame(oldFrame, id: "fixture", owner: oldOwner)
        XCTAssertEqual(anchor.frame(for: "fixture"), newFrame)
        anchor.removeFrame(id: "fixture", owner: newOwner)
        XCTAssertNil(anchor.frame(for: "fixture"))
    }

    func testGeometryCoalescesWithoutRestartingFullRestoreAndGestureCancelsCompensation() async {
        let harness = makeUIKitHarness()
        defer { harness.coordinator.detach(); harness.window.isHidden = true }
        let scroll = harness.scrollView
        let anchor = harness.anchor
        let card = harness.card
        let coordinator = harness.coordinator
        anchor.scrollView = scroll
        scroll.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
        anchor.updateFrame(card.frame, id: "selected")
        anchor.capture(preferredID: "selected")
        let originalY = card.convert(card.bounds, to: harness.window).minY
        coordinator.update(probe: harness.probe, offsetY: 500, restorationRevision: 0,
                           isActive: true, visualAnchor: anchor, onOffsetChange: { _ in })
        let started = await eventually { coordinator.fullRestorationCount == 1 }
        XCTAssertTrue(started)
        for _ in 0..<10 {
            card.frame.origin.y += 1
            anchor.updateFrame(card.frame, id: "selected")
            scroll.contentSize.height += 1
        }
        let compensated = await eventually {
            abs(card.convert(card.bounds, to: harness.window).minY - originalY) < 1
        }
        XCTAssertTrue(compensated)
        XCTAssertEqual(coordinator.fullRestorationCount, 1)
        XCTAssertGreaterThan(coordinator.layoutCompensationCount, 0)
        XCTAssertLessThan(coordinator.layoutCompensationCount, 10, "Same-turn geometry should be coalesced")
        scroll.testIsTracking = true
        scroll.setContentOffset(CGPoint(x: 0, y: 650), animated: false)
        XCTAssertNil(anchor.snapshot)
        card.frame.origin.y += 40
        anchor.updateFrame(card.frame, id: "selected")
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        XCTAssertEqual(scroll.contentOffset.y, 650, accuracy: 1)
        XCTAssertEqual(coordinator.fullRestorationCount, 1)
    }

    func testFirstReturnWaitsForLateContentHeightWithoutLosingSavedPosition() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let scrollView = UIScrollView(frame: window.bounds)
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentSize = CGSize(width: 390, height: 2400)
        let probe = FocusDynamicFeedScrollProbeView(frame: .zero)
        scrollView.addSubview(probe)
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(scrollView)
        window.makeKeyAndVisible()
        let coordinator = FocusDynamicFeedScrollBridge.Coordinator()
        defer { coordinator.detach(); window.isHidden = true }
        var savedOffset: CGFloat = 420
        func update(_ active: Bool) {
            coordinator.update(probe: probe, offsetY: savedOffset, restorationRevision: 0, isActive: active) {
                savedOffset = $0
            }
        }
        update(true)
        try await Task.sleep(for: .milliseconds(100))
        update(false)
        // First-entry lazy layout initially exposes only a short content height.
        scrollView.contentSize.height = 600
        scrollView.setContentOffset(.zero, animated: false)
        update(true)
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(savedOffset, 420, accuracy: 1)
        scrollView.contentSize.height = 2400
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(scrollView.contentOffset.y, 420, accuracy: 1)

        // A later layout pass can still clamp the offset after the first success.
        scrollView.contentSize.height = 600
        scrollView.setContentOffset(.zero, animated: false)
        try await Task.sleep(for: .milliseconds(100))
        update(false)
        XCTAssertEqual(savedOffset, 420, accuracy: 1)
        scrollView.contentSize.height = 2400
        update(true)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(scrollView.contentOffset.y, 420, accuracy: 1)

        // Once the user scrolls, later content growth must not undo their input.
        scrollView.setContentOffset(CGPoint(x: 0, y: 80), animated: false)
        coordinator.observeOffset(contentOffsetY: 80, isUserDriven: true)
        scrollView.contentSize.height = 3000
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(savedOffset, 80, accuracy: 1)
        XCTAssertEqual(scrollView.contentOffset.y, 80, accuracy: 1)
    }

    func testReactivationRestoresSavedOffsetAfterInactiveLayoutMovement() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let scrollView = UIScrollView(frame: window.bounds)
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentSize = CGSize(width: 390, height: 2400)
        let probe = FocusDynamicFeedScrollProbeView(frame: .zero)
        scrollView.addSubview(probe)
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(scrollView)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        window.rootViewController?.view.layoutIfNeeded()

        let coordinator = FocusDynamicFeedScrollBridge.Coordinator()
        var savedOffset: CGFloat = 420
        coordinator.update(
            probe: probe,
            offsetY: 420,
            restorationRevision: 0,
            isActive: true,
            onOffsetChange: { savedOffset = $0 }
        )
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(scrollView.contentOffset.y, 420, accuracy: 1)

        coordinator.update(
            probe: probe,
            offsetY: savedOffset,
            restorationRevision: 0,
            isActive: false,
            onOffsetChange: { savedOffset = $0 }
        )
        coordinator.update(
            probe: probe,
            offsetY: savedOffset,
            restorationRevision: 1,
            isActive: false,
            onOffsetChange: { savedOffset = $0 }
        )
        scrollView.setContentOffset(CGPoint(x: 0, y: 170), animated: false)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(savedOffset, 420, accuracy: 1)

        coordinator.update(
            probe: probe,
            offsetY: savedOffset,
            restorationRevision: 1,
            isActive: true,
            onOffsetChange: { savedOffset = $0 }
        )
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(scrollView.contentOffset.y, 420, accuracy: 1)

        scrollView.setContentOffset(CGPoint(x: 0, y: 615), animated: false)
        coordinator.observeOffset(contentOffsetY: 615, isUserDriven: true)
        XCTAssertEqual(savedOffset, 615, accuracy: 1)

        coordinator.update(
            probe: probe,
            offsetY: savedOffset,
            restorationRevision: 1,
            isActive: false,
            onOffsetChange: { savedOffset = $0 }
        )
        scrollView.setContentOffset(CGPoint(x: 0, y: 170), animated: false)
        coordinator.update(
            probe: probe,
            offsetY: savedOffset,
            restorationRevision: 1,
            isActive: true,
            onOffsetChange: { savedOffset = $0 }
        )
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(scrollView.contentOffset.y, 615, accuracy: 1)
    }

    func testVisualAnchorKeepsCardInPlaceAcrossMaterializedHeightChanges() async throws {
        let model = ScrollAnchorDiagnosticModel(usesLazyStack: true)
        let (window, host) = try makeHostedHarness(model: model)
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        let layoutReady = await eventually {
            (self.findScrollView(in: host.view)?.contentSize.height ?? 0) > 1_000
        }
        XCTAssertTrue(layoutReady, "SwiftUI LazyVStack did not produce measurable cards")
        guard let scrollView = findScrollView(in: host.view) else {
            XCTFail("Hosted SwiftUI ScrollView was not found")
            return
        }

        model.offsetY = 950
        model.revision += 1
        let restored = await eventually {
            abs(scrollView.contentOffset.y - 950) < 1 && model.frames[10] != nil
        }
        XCTAssertTrue(restored, "Bridge did not restore the requested offset")
        let anchorFrameReady = await eventually { model.anchor.frame(for: "10") != nil }
        XCTAssertTrue(anchorFrameReady, "Card 10 SwiftUI anchor frame was not recorded")
        guard anchorFrameReady else { return }
        XCTAssertTrue(model.anchor.scrollView === scrollView, "The visual anchor should observe this feed scroll view")
        model.anchor.capture(preferredID: "10")
        XCTAssertEqual(model.anchor.snapshot?.id, "10")
        let originalViewportY = try viewportY(for: 10, model: model, scrollView: scrollView)
        let originalOffset = scrollView.contentOffset.y

        // Row 9 is materialized above card 10, so this models a layout correction
        // that occurs while the feed is inactive.
        model.isActive = false
        await settleLayout()
        model.rowHeights[9] = 164
        await settleLayout()
        let inactiveViewportY = try viewportY(for: 10, model: model, scrollView: scrollView)
        XCTAssertEqual(inactiveViewportY - originalViewportY, 44, accuracy: 2)

        model.isActive = true
        let returned = await eventually {
            guard let frame = model.frames[10] else { return false }
            return abs(self.viewportY(frame: frame, scrollView: scrollView) - originalViewportY) < 1
        }
        XCTAssertTrue(returned, "Visual anchor did not return card 10 to its prior viewport position")
        XCTAssertEqual(scrollView.contentOffset.y, originalOffset + 44, accuracy: 2)

        // A later row-height correction while active must keep the same card fixed.
        XCTAssertNotNil(model.frames[12], "The compensating row should be materialized")
        var compensatedHeights = model.rowHeights
        compensatedHeights[9] = 184
        compensatedHeights[12] = 100
        model.rowHeights = compensatedHeights
        let compensatedLayoutApplied = await eventually {
            abs((model.frames[9]?.height ?? 0) - 184) < 1
                && abs((model.frames[12]?.height ?? 0) - 100) < 1
        }
        XCTAssertTrue(compensatedLayoutApplied, "The simultaneous row-height changes did not reach layout")
        let corrected = await eventually {
            guard let frame = model.frames[10] else { return false }
            return abs(self.viewportY(frame: frame, scrollView: scrollView) - originalViewportY) < 1
        }
        XCTAssertTrue(corrected, "A later row-height correction displaced the anchored card")
        XCTAssertEqual(scrollView.contentOffset.y, originalOffset + 64, accuracy: 3)
    }

    func testEagerStackKeepsAnchorWhenCompensatingRowsPreserveContentHeight() async throws {
        let model = ScrollAnchorDiagnosticModel(usesLazyStack: false)
        let (window, host) = try makeHostedHarness(model: model)
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        let layoutReady = await eventually {
            (self.findScrollView(in: host.view)?.contentSize.height ?? 0) > 1_000
        }
        XCTAssertTrue(layoutReady, "SwiftUI VStack did not produce measurable cards")
        guard let scrollView = findScrollView(in: host.view) else {
            XCTFail("Hosted SwiftUI ScrollView was not found")
            return
        }

        model.offsetY = 950
        model.revision += 1
        let restored = await eventually {
            abs(scrollView.contentOffset.y - 950) < 1 && model.frames[10] != nil
        }
        XCTAssertTrue(restored, "Bridge did not restore the requested offset")
        let anchorFrameReady = await eventually { model.anchor.frame(for: "10") != nil }
        XCTAssertTrue(anchorFrameReady, "Card 10 SwiftUI anchor frame was not recorded")
        guard anchorFrameReady else { return }
        model.anchor.capture(preferredID: "10")
        XCTAssertEqual(model.anchor.snapshot?.id, "10")
        let originalViewportY = try viewportY(for: 10, model: model, scrollView: scrollView)

        model.isActive = false
        await settleLayout()
        model.rowHeights[9] = 164
        await settleLayout()
        XCTAssertEqual(
            try viewportY(for: 10, model: model, scrollView: scrollView) - originalViewportY,
            44,
            accuracy: 2
        )

        model.isActive = true
        let returned = await eventually {
            guard let frame = model.frames[10] else { return false }
            return abs(self.viewportY(frame: frame, scrollView: scrollView) - originalViewportY) < 1
        }
        XCTAssertTrue(returned, "Visual anchor did not restore the eager-stack card position")

        let contentHeightBeforeChange = scrollView.contentSize.height
        var compensatedHeights = model.rowHeights
        compensatedHeights[9] = 184
        compensatedHeights[12] = 100
        model.rowHeights = compensatedHeights
        let compensatedLayoutApplied = await eventually {
            abs((model.frames[9]?.height ?? 0) - 184) < 1
                && abs((model.frames[12]?.height ?? 0) - 100) < 1
        }
        XCTAssertTrue(compensatedLayoutApplied, "The simultaneous row-height changes did not reach layout")
        let stableAnchor = await eventually {
            guard let frame = model.frames[10] else { return false }
            return abs(self.viewportY(frame: frame, scrollView: scrollView) - originalViewportY) < 1
        }
        XCTAssertTrue(stableAnchor, "Compensating row changes displaced the eager-stack anchor")
        XCTAssertEqual(scrollView.contentSize.height, contentHeightBeforeChange, accuracy: 1)
    }

    func testLazyCardAnchorCanBeRemovedAndRegisteredAgainAfterScrollingAway() async throws {
        let model = ScrollAnchorDiagnosticModel(usesLazyStack: true)
        let (window, host) = try makeHostedHarness(model: model)
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        let layoutReady = await eventually {
            (self.findScrollView(in: host.view)?.contentSize.height ?? 0) > 1_000
        }
        XCTAssertTrue(layoutReady, "SwiftUI LazyVStack did not produce measurable cards")
        guard findScrollView(in: host.view) != nil else {
            XCTFail("Hosted SwiftUI ScrollView was not found")
            return
        }

        model.offsetY = 950
        model.revision += 1
        let initiallyRegistered = await eventually {
            model.anchor.frame(for: "10") != nil
        }
        XCTAssertTrue(initiallyRegistered, "Card 10 did not register at the initial offset")

        // Move well past card 10 so LazyVStack must remove it from the hierarchy.
        model.offsetY = 2_500
        model.revision += 1
        let removed = await eventually {
            model.anchor.frame(for: "10") == nil
        }
        if !removed {
            let owners = Mirror(reflecting: model.anchor).children.first { $0.label == "frameOwners" }?.value as? [String: UUID]
            var view = model.surfaces[10]?.view
            var hierarchy: [String] = []
            while let current = view {
                hierarchy.append("\(type(of: current)): hidden=\(current.isHidden), alpha=\(current.alpha), frame=\(current.frame)")
                view = current.superview
            }
            let evidence = "ownerPresent=\(owners?["10"] != nil), preferencePresent=\(model.frames[10] != nil)\n" + hierarchy.joined(separator: "\n")
            let attachment = XCTAttachment(string: evidence)
            attachment.name = "Retained lazy surface lifecycle"; attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertTrue(removed, "Card 10 remained registered after scrolling far outside the lazy window")
        guard removed else { return }

        model.offsetY = 950
        model.revision += 1
        let registeredAgain = await eventually {
            model.anchor.frame(for: "10") != nil
        }
        XCTAssertTrue(registeredAgain, "Card 10 did not register after returning to its lazy window")
        guard registeredAgain else { return }

        model.anchor.capture(preferredID: "10")
        XCTAssertEqual(model.anchor.snapshot?.id, "10")
    }

    func testUserScrollClearsPendingVisualAnchorRestoration() async throws {
        let harness = makeUIKitHarness()
        defer {
            harness.coordinator.detach()
            harness.window.isHidden = true
        }
        let (window, scrollView, probe, card, anchor, coordinator) = harness
        window.rootViewController?.view.layoutIfNeeded()
        anchor.scrollView = scrollView
        anchor.updateFrame(card.frame, id: "selected")
        scrollView.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
        coordinator.update(
            probe: probe,
            offsetY: 500,
            restorationRevision: 1,
            isActive: false,
            visualAnchor: anchor,
            onOffsetChange: { _ in }
        )
        try await Task.sleep(for: .milliseconds(50))
        anchor.capture(preferredID: "selected")
        XCTAssertEqual(anchor.snapshot?.id, "selected")

        card.frame.origin.y += 44
        anchor.updateFrame(card.frame, id: "selected")
        coordinator.update(
            probe: probe,
            offsetY: 500,
            restorationRevision: 1,
            isActive: true,
            visualAnchor: anchor,
            onOffsetChange: { _ in }
        )
        scrollView.setContentOffset(CGPoint(x: 0, y: 650), animated: false)
        coordinator.observeOffset(contentOffsetY: 650, isUserDriven: true)
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertNil(anchor.snapshot, "A user gesture should discard the previous card anchor")
        XCTAssertEqual(scrollView.contentOffset.y, 650, accuracy: 1)
    }

    func testTrackingGestureCancelsGeometryTriggeredAnchorRestoreWithoutOffsetKVO() async throws {
        let harness = makeUIKitHarness()
        defer {
            harness.coordinator.detach()
            harness.window.isHidden = true
        }
        let (window, scrollView, probe, card, anchor, coordinator) = harness
        window.rootViewController?.view.layoutIfNeeded()
        anchor.scrollView = scrollView
        anchor.updateFrame(card.frame, id: "selected")
        scrollView.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
        coordinator.update(
            probe: probe,
            offsetY: 500,
            restorationRevision: 1,
            isActive: true,
            visualAnchor: anchor,
            onOffsetChange: { _ in }
        )
        try await Task.sleep(for: .milliseconds(100))
        anchor.capture(preferredID: "selected")
        XCTAssertEqual(anchor.snapshot?.id, "selected")
        let offsetBeforeGesture = scrollView.contentOffset.y

        // Tracking begins before any pan changes contentOffset and therefore
        // before there is an offset KVO event to cancel restoration.
        scrollView.testIsTracking = true
        card.frame.origin.y += 44
        anchor.updateFrame(card.frame, id: "selected")
        let gestureWon = await eventually {
            anchor.snapshot == nil
        }
        XCTAssertTrue(gestureWon, "A tracked gesture should cancel geometry-driven restoration")
        XCTAssertEqual(scrollView.contentOffset.y, offsetBeforeGesture, accuracy: 1)
    }

    func testRestorationRevisionClearsOldVisualAnchorAndUsesNewOffset() async throws {
        let harness = makeUIKitHarness()
        defer {
            harness.coordinator.detach()
            harness.window.isHidden = true
        }
        let (window, scrollView, probe, card, anchor, coordinator) = harness
        window.rootViewController?.view.layoutIfNeeded()
        anchor.scrollView = scrollView
        anchor.updateFrame(card.frame, id: "selected")
        scrollView.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
        coordinator.update(
            probe: probe,
            offsetY: 500,
            restorationRevision: 1,
            isActive: false,
            visualAnchor: anchor,
            onOffsetChange: { _ in }
        )
        try await Task.sleep(for: .milliseconds(50))
        anchor.capture(preferredID: "selected")
        XCTAssertNotNil(anchor.snapshot)

        coordinator.update(
            probe: probe,
            offsetY: 300,
            restorationRevision: 2,
            isActive: false,
            visualAnchor: anchor,
            onOffsetChange: { _ in }
        )
        XCTAssertNil(anchor.snapshot)
        coordinator.update(
            probe: probe,
            offsetY: 300,
            restorationRevision: 2,
            isActive: true,
            visualAnchor: anchor,
            onOffsetChange: { _ in }
        )
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertNil(anchor.snapshot)
        XCTAssertEqual(scrollView.contentOffset.y, 300, accuracy: 1)
    }

    func testVisualAnchorUsesNormalizedOffsetWhenAdjustedInsetChanges() throws {
        let harness = makeUIKitHarness()
        defer {
            harness.coordinator.detach()
            harness.window.isHidden = true
        }
        let scrollView = harness.scrollView
        let card = harness.card
        let anchor = harness.anchor
        scrollView.contentInset.top = 20
        scrollView.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
        anchor.scrollView = scrollView
        anchor.updateFrame(card.frame, id: "selected")
        anchor.capture(preferredID: "selected")
        XCTAssertEqual(anchor.targetNormalizedOffset ?? -1, 520, accuracy: 1)

        scrollView.contentInset.top = 35

        XCTAssertEqual(anchor.targetNormalizedOffset ?? -1, 520, accuracy: 1)
        let placement = FocusDynamicFeedScrollRestorationPolicy.placement(
            requestedOffsetY: try XCTUnwrap(anchor.targetNormalizedOffset),
            minimumY: -scrollView.adjustedContentInset.top,
            maximumY: scrollView.contentSize.height - scrollView.bounds.height
        )
        XCTAssertEqual(placement.contentOffsetY, 485, accuracy: 1)
        XCTAssertEqual(
            FocusDynamicFeedScrollRestorationPolicy.normalizedOffset(
                contentOffsetY: placement.contentOffsetY,
                minimumY: -scrollView.adjustedContentInset.top
            ),
            520,
            accuracy: 1
        )
    }

    private func eventually(
        timeout: Duration = .seconds(3),
        condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return condition()
    }

    private func settleLayout() async {
        try? await Task.sleep(for: .milliseconds(120))
    }

    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        for child in view.subviews {
            if let result = findScrollView(in: child) { return result }
        }
        return nil
    }

    private func makeHostedHarness(
        model: ScrollAnchorDiagnosticModel
    ) throws -> (window: UIWindow, host: UIHostingController<ScrollAnchorDiagnosticFeed>) {
        let host = UIHostingController(rootView: ScrollAnchorDiagnosticFeed(model: model))
        if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
        let windowScene = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first,
            "A connected UIWindowScene is required for hosted SwiftUI marker layout"
        )
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        window.layoutIfNeeded()
        return (window, host)
    }

    private func viewportY(for id: Int, model: ScrollAnchorDiagnosticModel, scrollView: UIScrollView) throws -> CGFloat {
        // contentOffset KVO can precede the global SwiftUI preference update.
        // Capture the baseline from an independent live test surface, never
        // yesterday's preference or the geometry supplied to recovery itself.
        let surface = try XCTUnwrap(model.surfaces[id]?.view)
        XCTAssertNotNil(surface.window)
        return viewportY(frame: surface.convert(surface.bounds, to: nil), scrollView: scrollView)
    }

    private func viewportY(frame: CGRect, scrollView: UIScrollView) -> CGFloat {
        let viewportTop = scrollView.convert(
            CGPoint(x: 0, y: scrollView.bounds.minY + scrollView.adjustedContentInset.top),
            to: nil
        ).y
        return frame.minY - viewportTop
    }

    private func makeUIKitHarness() -> (
        window: UIWindow,
        scrollView: TrackingOverrideScrollView,
        probe: FocusDynamicFeedScrollProbeView,
        card: UIView,
        anchor: FocusDynamicFeedVisualAnchor,
        coordinator: FocusDynamicFeedScrollBridge.Coordinator
    ) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let root = UIViewController()
        let scrollView = TrackingOverrideScrollView(frame: window.bounds)
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentSize = CGSize(width: 390, height: 2400)
        let probe = FocusDynamicFeedScrollProbeView(frame: .zero)
        let card = UIView(frame: CGRect(x: 0, y: 900, width: 390, height: 120))
        scrollView.addSubview(probe)
        scrollView.addSubview(card)
        root.view.addSubview(scrollView)
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.view.layoutIfNeeded()
        return (
            window,
            scrollView,
            probe,
            card,
            FocusDynamicFeedVisualAnchor(),
            FocusDynamicFeedScrollBridge.Coordinator()
        )
    }
}

@MainActor
private final class ScrollAnchorDiagnosticModel: ObservableObject {
    let usesLazyStack: Bool

    init(usesLazyStack: Bool) {
        self.usesLazyStack = usesLazyStack
    }

    @Published var offsetY: CGFloat = 0
    @Published var revision = 0
    @Published var isActive = true
    @Published var rowHeights: [Int: CGFloat] = [:]
    @Published var frames: [Int: CGRect] = [:]
    struct Surface { weak var view: UIView? }
    var surfaces: [Int: Surface] = [:]
    let anchor = FocusDynamicFeedVisualAnchor()
}

@MainActor
private struct ScrollAnchorDiagnosticFeed: View {
    @ObservedObject var model: ScrollAnchorDiagnosticModel

    var body: some View {
        ScrollView {
            feedStack
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 126)
                .coordinateSpace(name: FocusDynamicFeedVisualAnchor.coordinateSpace)
                .background {
                    FocusDynamicFeedScrollBridge(
                        offsetY: model.offsetY,
                        restorationRevision: model.revision,
                        isActive: model.isActive,
                        visualAnchor: model.anchor,
                        onOffsetChange: { model.offsetY = $0 }
                    )
                    .frame(width: 0, height: 0)
                }
        }
        .onPreferenceChange(ScrollAnchorFramesPreferenceKey.self) { model.frames = $0 }
    }

    @ViewBuilder
    private var feedStack: some View {
        if model.usesLazyStack {
            LazyVStack(spacing: 8) { cards }
        } else {
            VStack(spacing: 8) { cards }
        }
    }

    private var cards: some View {
        ForEach(0..<24, id: \.self) { id in
            Text("Card \(id)")
                .frame(maxWidth: .infinity)
                .frame(height: model.rowHeights[id] ?? 120)
                .background(Color.gray.opacity(0.2))
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ScrollAnchorFramesPreferenceKey.self,
                            value: [id: geometry.frame(in: .global)]
                        )
                    }
                }
                .background(ScrollAnchorIndependentSurface(id: id, model: model))
                .focusDynamicFeedAnchor(id: "\(id)", anchor: model.anchor)
        }
    }
}

@MainActor
private struct ScrollAnchorIndependentSurface: UIViewRepresentable {
    let id: Int
    let model: ScrollAnchorDiagnosticModel
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        model.surfaces[id] = .init(view: view)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { model.surfaces[id] = .init(view: view) }
}

@MainActor
private final class TrackingOverrideScrollView: UIScrollView {
    var testIsTracking = false
    var testIsDecelerating = false
    private(set) var programmaticSetCount = 0

    override var isTracking: Bool { testIsTracking }
    override var isDecelerating: Bool { testIsDecelerating }
    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        programmaticSetCount += 1
        testIsDecelerating = false
        super.setContentOffset(contentOffset, animated: animated)
    }
}

private struct ScrollAnchorFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
