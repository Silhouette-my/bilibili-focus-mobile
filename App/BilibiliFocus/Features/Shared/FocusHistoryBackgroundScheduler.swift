#if canImport(BackgroundTasks) && canImport(UIKit)
import BackgroundTasks
import FocusCore
import Foundation
import UIKit

enum FocusHistoryBackgroundSchedulingPolicy {
    static func shouldSubmit(
        hasAuthenticatedPendingReports: Bool,
        hasPendingRequest: Bool
    ) -> Bool {
        hasAuthenticatedPendingReports && !hasPendingRequest
    }

    static func shouldReschedule(
        requiresRetry: Bool,
        remainingCount: Int
    ) -> Bool {
        requiresRetry && remainingCount > 0
    }
}

@MainActor
final class FocusHistoryBackgroundScheduler {
    typealias WorkAvailability = @Sendable () async -> Bool
    typealias OutboxDrain = @Sendable () async -> FocusHistoryOutboxDrainOutcome

    static let shared = FocusHistoryBackgroundScheduler()

    static let processingTaskIdentifier = "org.bilibilifocus.history-outbox.processing"

    private let scheduler: BGTaskScheduler
    private var hasWork: WorkAvailability?
    private var drain: OutboxDrain?
    private var hasRegisteredProcessingTask = false
    private var hasPendingProcessingRequest = false
    private var scheduleEvaluationTask: Task<Void, Never>?
    private var scheduleEvaluationGeneration: UInt64 = 0
    private var activeTask: BGProcessingTask?
    private var activeOperation: Task<Void, Never>?
    private var activeTaskGeneration: UInt64 = 0

    init(scheduler: BGTaskScheduler = .shared) {
        self.scheduler = scheduler
    }

    func configure(
        hasWork: @escaping WorkAvailability,
        drain: @escaping OutboxDrain
    ) {
        cancelScheduleEvaluation()
        self.hasWork = hasWork
        self.drain = drain
    }

    @discardableResult
    func register() -> Bool {
        guard !hasRegisteredProcessingTask else {
            return true
        }

        hasRegisteredProcessingTask = scheduler.register(
            forTaskWithIdentifier: Self.processingTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor [weak self] in
                self?.handle(processingTask)
            }
        }
        return hasRegisteredProcessingTask
    }

    func schedule() {
        guard
            hasRegisteredProcessingTask,
            scheduleEvaluationTask == nil,
            let hasWork,
            FocusHistoryBackgroundSchedulingPolicy.shouldSubmit(
                hasAuthenticatedPendingReports: true,
                hasPendingRequest: hasPendingProcessingRequest
            )
        else {
            return
        }

        scheduleEvaluationGeneration &+= 1
        let generation = scheduleEvaluationGeneration
        scheduleEvaluationTask = Task { @MainActor [weak self] in
            let hasAuthenticatedPendingReports = await hasWork()
            guard let self, !Task.isCancelled else {
                return
            }
            self.finishScheduleEvaluation(
                generation: generation,
                hasAuthenticatedPendingReports: hasAuthenticatedPendingReports
            )
        }
    }

    private func finishScheduleEvaluation(
        generation: UInt64,
        hasAuthenticatedPendingReports: Bool
    ) {
        guard scheduleEvaluationGeneration == generation else {
            return
        }
        scheduleEvaluationTask = nil
        guard FocusHistoryBackgroundSchedulingPolicy.shouldSubmit(
            hasAuthenticatedPendingReports: hasAuthenticatedPendingReports,
            hasPendingRequest: hasPendingProcessingRequest
        ) else {
            return
        }

        let request = BGProcessingTaskRequest(identifier: Self.processingTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        do {
            try scheduler.submit(request)
            hasPendingProcessingRequest = true
        } catch {
            hasPendingProcessingRequest = false
        }
    }

    private func handle(_ task: BGProcessingTask) {
        hasPendingProcessingRequest = false
        cancelScheduleEvaluation()

        guard activeTask == nil, let drain else {
            task.setTaskCompleted(success: false)
            return
        }

        activeTaskGeneration &+= 1
        let generation = activeTaskGeneration
        activeTask = task
        let operation = Task { @MainActor [weak self] in
            let outcome = await drain()
            let wasCancelled = Task.isCancelled
            guard let self else {
                return
            }
            self.completeActiveTask(
                generation: generation,
                outcome: outcome,
                wasCancelled: wasCancelled
            )
        }
        activeOperation = operation
        task.expirationHandler = {
            Task { @MainActor [weak self] in
                self?.expireActiveTask(generation: generation)
            }
        }
    }

    private func expireActiveTask(generation: UInt64) {
        guard activeTaskGeneration == generation, activeTask != nil else {
            return
        }
        activeOperation?.cancel()
        completeActiveTask(
            generation: generation,
            outcome: FocusHistoryOutboxDrainOutcome(remainingCount: 1),
            wasCancelled: true
        )
    }

    private func completeActiveTask(
        generation: UInt64,
        outcome: FocusHistoryOutboxDrainOutcome,
        wasCancelled: Bool
    ) {
        guard activeTaskGeneration == generation, let task = activeTask else {
            return
        }

        activeOperation = nil
        activeTask = nil
        task.expirationHandler = nil

        let shouldReschedule = wasCancelled
            || FocusHistoryBackgroundSchedulingPolicy.shouldReschedule(
                requiresRetry: outcome.requiresRetry,
                remainingCount: outcome.remainingCount
            )
        if shouldReschedule {
            schedule()
        }
        task.setTaskCompleted(success: !wasCancelled && !outcome.requiresRetry)
    }

    private func cancelScheduleEvaluation() {
        scheduleEvaluationGeneration &+= 1
        scheduleEvaluationTask?.cancel()
        scheduleEvaluationTask = nil
    }
}
#endif
