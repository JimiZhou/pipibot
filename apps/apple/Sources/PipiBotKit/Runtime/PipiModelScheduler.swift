// PiPiBot — Clean-room MIT implementation.
// Architectural inspiration: simplexai-labs/linger (Model Scheduling — 7-tier priority
// queues, interactive reserved slot, AIMD adaptive concurrency, preemptive yielding for
// resumable CLI/background sessions, and unified structured-output retry/correction;
// https://github.com/simplexai-labs/linger — Linger Open Source License; zero source code,
// prompts, or assets copied). See root NOTICE and LICENSE.

import Foundation

public struct PipiSchedulerYieldError: Error, Sendable, Equatable {
    public let runId: String
    public let reason: String

    public init(runId: String, reason: String = "Yielded to higher-priority interactive request") {
        self.runId = runId
        self.reason = reason
    }
}

public struct PipiEndpointPoolConfig: Sendable, Equatable {
    public var initialLimit: Int
    public var maxLimit: Int
    public var minLimit: Int
    /// Initial backoff after slowing down at a concurrency level (default 5 minutes, doubles up to 30m).
    public var baseRetryBackoffSeconds: TimeInterval
    /// Holdoff after halving concurrency due to 429/overload/timeout (default 60 seconds).
    public var rateLimitHoldoffSeconds: TimeInterval
    /// Latency multiplier over baseline per 1k prompt tokens considered congested.
    public var slowdownMultiplier: Double

    public init(
        initialLimit: Int,
        maxLimit: Int,
        minLimit: Int = 1,
        baseRetryBackoffSeconds: TimeInterval = 300,
        rateLimitHoldoffSeconds: TimeInterval = 60,
        slowdownMultiplier: Double = 1.85
    ) {
        self.minLimit = max(1, minLimit)
        self.maxLimit = max(self.minLimit, maxLimit)
        self.initialLimit = max(self.minLimit, min(self.maxLimit, initialLimit))
        self.baseRetryBackoffSeconds = max(0, baseRetryBackoffSeconds)
        self.rateLimitHoldoffSeconds = max(0, rateLimitHoldoffSeconds)
        self.slowdownMultiplier = max(1.1, slowdownMultiplier)
    }

    public static let cloudLLMDefault = PipiEndpointPoolConfig(initialLimit: 4, maxLimit: 8)
    public static let localAgentDefault = PipiEndpointPoolConfig(initialLimit: 2, maxLimit: 4)
    public static let localModelDefault = PipiEndpointPoolConfig(initialLimit: 1, maxLimit: 2)
}

public struct PipiEndpointPoolSnapshot: Sendable, Equatable {
    public let endpointKey: String
    public let hardLimit: Int
    public let softLimit: Int
    public let maxLimit: Int
    public let activeCount: Int
    public let queuedCount: Int
    public let baselineMsPer1kTokens: Double?
    public let totalYields: Int
    public let totalRateLimitBackoffs: Int
}

public struct PipiLeaseCompletionMetrics: Sendable, Equatable {
    public let durationMs: Double
    public let promptTokens: Int
    public let rateLimitedOrOverloaded: Bool
    public let timedOut: Bool

    public init(
        durationMs: Double,
        promptTokens: Int = 1000,
        rateLimitedOrOverloaded: Bool = false,
        timedOut: Bool = false
    ) {
        self.durationMs = max(1, durationMs)
        self.promptTokens = max(1, promptTokens)
        self.rateLimitedOrOverloaded = rateLimitedOrOverloaded
        self.timedOut = timedOut
    }
}

@MainActor
public final class PipiScheduledLease {
    public let leaseId: String
    public let runId: String
    public let endpointKey: String
    public let priority: PipiSchedulerPriority
    public let startedAt: Date

    private weak var scheduler: PipiModelScheduler?
    private var metricsReported: Bool = false
    private var released: Bool = false

    fileprivate init(
        leaseId: String,
        runId: String,
        endpointKey: String,
        priority: PipiSchedulerPriority,
        startedAt: Date,
        scheduler: PipiModelScheduler
    ) {
        self.leaseId = leaseId
        self.runId = runId
        self.endpointKey = endpointKey
        self.priority = priority
        self.startedAt = startedAt
        self.scheduler = scheduler
    }

    public var wasYielded: Bool {
        scheduler?.wasLeaseYielded(endpointKey: endpointKey, leaseId: leaseId) ?? false
    }

    public func reportMetrics(_ metrics: PipiLeaseCompletionMetrics) {
        guard !metricsReported else { return }
        metricsReported = true
        scheduler?.applyAimdFeedback(endpointKey: endpointKey, metrics: metrics)
    }

    public func release() {
        guard !released else { return }
        released = true
        scheduler?.releaseLease(endpointKey: endpointKey, leaseId: leaseId)
    }
}

@MainActor
public final class PipiModelScheduler {
    private final class ActiveEntry {
        let leaseId: String
        let runId: String
        let priority: PipiSchedulerPriority
        let startedAt: Date
        let canYield: @MainActor () -> Bool
        let onYieldRequested: (@MainActor () -> Void)?
        var yieldRequested: Bool = false

        init(
            leaseId: String,
            runId: String,
            priority: PipiSchedulerPriority,
            startedAt: Date,
            canYield: @escaping @MainActor () -> Bool,
            onYieldRequested: (@MainActor () -> Void)?
        ) {
            self.leaseId = leaseId
            self.runId = runId
            self.priority = priority
            self.startedAt = startedAt
            self.canYield = canYield
            self.onYieldRequested = onYieldRequested
        }
    }

    private struct QueuedWaiter {
        let id: UUID
        let runId: String
        let priority: PipiSchedulerPriority
        let enqueuedAt: Date
        let canYield: @MainActor () -> Bool
        let onYieldRequested: (@MainActor () -> Void)?
        let continuation: CheckedContinuation<PipiScheduledLease, Error>
    }

    private struct LevelBackoff {
        let until: Date
        let durationSeconds: TimeInterval
    }

    private final class EndpointPool {
        var config: PipiEndpointPoolConfig
        var hardLimit: Int
        var active: [String: ActiveEntry] = [:]
        var waiters: [QueuedWaiter] = []
        var baselineMsPer1kTokens: Double?
        var holdoffUntil: Date = .distantPast
        var levelBackoffs: [Int: LevelBackoff] = [:]
        var totalYields: Int = 0
        var totalRateLimitBackoffs: Int = 0

        init(config: PipiEndpointPoolConfig) {
            self.config = config
            self.hardLimit = config.initialLimit
        }

        var softLimit: Int {
            max(1, hardLimit - 1)
        }
    }

    private var pools: [String: EndpointPool] = [:]
    private var customConfigs: [String: PipiEndpointPoolConfig] = [:]
    private let defaultConfig: PipiEndpointPoolConfig
    private let clock: @Sendable () -> Date

    public init(
        defaultConfig: PipiEndpointPoolConfig = .cloudLLMDefault,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.defaultConfig = defaultConfig
        self.clock = clock
    }

    public func configureEndpoint(_ endpointKey: String, config: PipiEndpointPoolConfig) {
        customConfigs[endpointKey] = config
        if let pool = pools[endpointKey] {
            pool.config = config
            pool.hardLimit = max(config.minLimit, min(config.maxLimit, config.initialLimit))
            drain(endpointKey: endpointKey)
        }
    }

    /// Sets an endpoint pool's default configuration only if no custom configuration has been registered yet.
    public func ensureDefaultEndpointConfig(_ endpointKey: String, config: PipiEndpointPoolConfig) {
        guard customConfigs[endpointKey] == nil else { return }
        configureEndpoint(endpointKey, config: config)
    }

    public func resetEndpointLearning(_ endpointKey: String) {
        guard let pool = pools[endpointKey] else { return }
        pool.hardLimit = pool.config.initialLimit
        pool.baselineMsPer1kTokens = nil
        pool.holdoffUntil = .distantPast
        pool.levelBackoffs.removeAll()
    }

    public func snapshot(for endpointKey: String) -> PipiEndpointPoolSnapshot {
        let pool = ensurePool(for: endpointKey)
        return PipiEndpointPoolSnapshot(
            endpointKey: endpointKey,
            hardLimit: pool.hardLimit,
            softLimit: pool.softLimit,
            maxLimit: pool.config.maxLimit,
            activeCount: pool.active.count,
            queuedCount: pool.waiters.count,
            baselineMsPer1kTokens: pool.baselineMsPer1kTokens,
            totalYields: pool.totalYields,
            totalRateLimitBackoffs: pool.totalRateLimitBackoffs
        )
    }

    public func cancelQueued(runId: String) {
        for (_, pool) in pools {
            while let idx = pool.waiters.firstIndex(where: { $0.runId == runId }) {
                let waiter = pool.waiters.remove(at: idx)
                waiter.continuation.resume(throwing: CancellationError())
            }
        }
    }

    public func acquire(
        endpointKey: String,
        priority: PipiSchedulerPriority,
        runId: String = "run_\(UUID().uuidString.prefix(8).lowercased())",
        onQueued: (@MainActor () -> Void)? = nil,
        canYield: (@MainActor () -> Bool)? = nil,
        onYieldRequested: (@MainActor () -> Void)? = nil
    ) async throws -> PipiScheduledLease {
        if Task.isCancelled {
            throw CancellationError()
        }

        let pool = ensurePool(for: endpointKey)
        let resolvedCanYield = canYield ?? { priority.isPreemptible }

        if canAdmit(pool: pool, priority: priority, hasHigherWaiterAhead: false) {
            return createLease(
                endpointKey: endpointKey,
                pool: pool,
                runId: runId,
                priority: priority,
                canYield: resolvedCanYield,
                onYieldRequested: onYieldRequested
            )
        }

        // Notify caller before suspending so UI transitions immediately to .queued
        onQueued?()

        // If interactive or approval work is waiting behind lower-priority work, request yield
        if priority.isInteractiveOrHigher {
            _ = tryRequestYield(pool: pool, incomingPriority: priority)
        }

        let waiterId = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<PipiScheduledLease, Error>) in
                if Task.isCancelled {
                    cont.resume(throwing: CancellationError())
                    return
                }
                let waiter = QueuedWaiter(
                    id: waiterId,
                    runId: runId,
                    priority: priority,
                    enqueuedAt: clock(),
                    canYield: resolvedCanYield,
                    onYieldRequested: onYieldRequested,
                    continuation: cont
                )
                pool.waiters.append(waiter)
                sortWaiters(pool: pool)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelWaiter(id: waiterId, endpointKey: endpointKey)
            }
        }
    }

    fileprivate func wasLeaseYielded(endpointKey: String, leaseId: String) -> Bool {
        pools[endpointKey]?.active[leaseId]?.yieldRequested ?? false
    }

    fileprivate func releaseLease(endpointKey: String, leaseId: String) {
        guard let pool = pools[endpointKey] else { return }
        pool.active.removeValue(forKey: leaseId)
        drain(endpointKey: endpointKey)
    }

    fileprivate func applyAimdFeedback(endpointKey: String, metrics: PipiLeaseCompletionMetrics) {
        guard let pool = pools[endpointKey] else { return }
        let now = clock()

        if metrics.rateLimitedOrOverloaded || metrics.timedOut {
            pool.totalRateLimitBackoffs += 1
            let previous = pool.hardLimit
            pool.hardLimit = max(pool.config.minLimit, previous / 2)
            pool.holdoffUntil = now.addingTimeInterval(pool.config.rateLimitHoldoffSeconds)
            recordLevelBackoff(pool: pool, level: previous, now: now)
            return
        }

        let tokenUnits = max(1.0, Double(metrics.promptTokens) / 1000.0)
        let msPer1k = metrics.durationMs / tokenUnits

        if pool.baselineMsPer1kTokens == nil || pool.active.count <= 1 {
            if let existing = pool.baselineMsPer1kTokens {
                pool.baselineMsPer1kTokens = existing * 0.7 + msPer1k * 0.3
            } else {
                pool.baselineMsPer1kTokens = msPer1k
            }
        }

        let baseline = pool.baselineMsPer1kTokens ?? msPer1k
        if pool.hardLimit > pool.config.minLimit && msPer1k > baseline * pool.config.slowdownMultiplier {
            let rejected = pool.hardLimit
            pool.hardLimit = max(pool.config.minLimit, rejected - 1)
            recordLevelBackoff(pool: pool, level: rejected, now: now)
            return
        }

        if !pool.waiters.isEmpty,
           pool.hardLimit < pool.config.maxLimit,
           now >= pool.holdoffUntil,
           msPer1k <= baseline * 1.35 {
            let candidate = pool.hardLimit + 1
            if let backoff = pool.levelBackoffs[candidate], now < backoff.until {
                return
            }
            pool.hardLimit = candidate
        }
    }

    private func ensurePool(for endpointKey: String) -> EndpointPool {
        if let existing = pools[endpointKey] {
            return existing
        }
        let cfg = customConfigs[endpointKey] ?? defaultConfig
        let created = EndpointPool(config: cfg)
        pools[endpointKey] = created
        return created
    }

    private func canAdmit(
        pool: EndpointPool,
        priority: PipiSchedulerPriority,
        hasHigherWaiterAhead: Bool
    ) -> Bool {
        if hasHigherWaiterAhead { return false }
        let activeCount = pool.active.count
        if activeCount >= pool.hardLimit { return false }

        // Reserve the final slot for interactive/approval work when hardLimit > 1
        if !priority.isInteractiveOrHigher && pool.hardLimit > 1 {
            return activeCount < pool.softLimit
        }
        return true
    }

    private func createLease(
        endpointKey: String,
        pool: EndpointPool,
        runId: String,
        priority: PipiSchedulerPriority,
        canYield: @escaping @MainActor () -> Bool,
        onYieldRequested: (@MainActor () -> Void)?
    ) -> PipiScheduledLease {
        let leaseId = "lease_\(UUID().uuidString.prefix(8).lowercased())"
        let startedAt = clock()
        let entry = ActiveEntry(
            leaseId: leaseId,
            runId: runId,
            priority: priority,
            startedAt: startedAt,
            canYield: canYield,
            onYieldRequested: onYieldRequested
        )
        pool.active[leaseId] = entry
        return PipiScheduledLease(
            leaseId: leaseId,
            runId: runId,
            endpointKey: endpointKey,
            priority: priority,
            startedAt: startedAt,
            scheduler: self
        )
    }

    private func tryRequestYield(pool: EndpointPool, incomingPriority: PipiSchedulerPriority) -> Bool {
        let candidates = pool.active.values
            .filter { entry in
                !entry.yieldRequested &&
                entry.priority.rank > incomingPriority.rank &&
                entry.priority.isPreemptible &&
                entry.canYield()
            }
            .sorted { lhs, rhs in
                if lhs.priority.rank != rhs.priority.rank {
                    return lhs.priority.rank > rhs.priority.rank
                }
                return lhs.startedAt > rhs.startedAt
            }

        guard let victim = candidates.first else { return false }
        victim.yieldRequested = true
        pool.totalYields += 1
        victim.onYieldRequested?()
        return true
    }

    private func recordLevelBackoff(pool: EndpointPool, level: Int, now: Date) {
        guard level > pool.config.minLimit else { return }
        let maxBackoff: TimeInterval = 1800 // 30 minutes
        let nextDuration: TimeInterval
        if let prev = pool.levelBackoffs[level] {
            nextDuration = min(maxBackoff, prev.durationSeconds * 2)
        } else {
            nextDuration = pool.config.baseRetryBackoffSeconds
        }
        pool.levelBackoffs[level] = LevelBackoff(
            until: now.addingTimeInterval(nextDuration),
            durationSeconds: nextDuration
        )
    }

    private func sortWaiters(pool: EndpointPool) {
        pool.waiters.sort { lhs, rhs in
            if lhs.priority.rank != rhs.priority.rank {
                return lhs.priority.rank < rhs.priority.rank
            }
            return lhs.enqueuedAt < rhs.enqueuedAt
        }
    }

    private func cancelWaiter(id: UUID, endpointKey: String) {
        guard let pool = pools[endpointKey],
              let idx = pool.waiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        let waiter = pool.waiters.remove(at: idx)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func drain(endpointKey: String) {
        guard let pool = pools[endpointKey], !pool.waiters.isEmpty else { return }
        sortWaiters(pool: pool)

        var idx = 0
        while idx < pool.waiters.count {
            let waiter = pool.waiters[idx]
            let hasInteractiveAhead = pool.waiters[..<idx].contains { $0.priority.isInteractiveOrHigher }
            if canAdmit(pool: pool, priority: waiter.priority, hasHigherWaiterAhead: hasInteractiveAhead) {
                pool.waiters.remove(at: idx)
                let lease = createLease(
                    endpointKey: endpointKey,
                    pool: pool,
                    runId: waiter.runId,
                    priority: waiter.priority,
                    canYield: waiter.canYield,
                    onYieldRequested: waiter.onYieldRequested
                )
                waiter.continuation.resume(returning: lease)
                continue
            }

            if waiter.priority.isInteractiveOrHigher {
                _ = tryRequestYield(pool: pool, incomingPriority: waiter.priority)
            }
            idx += 1
        }
    }
}

// MARK: - Unified Structured-Output Retry & Schema Self-Correction

public enum PipiStructuredRetryError: LocalizedError, Sendable {
    case exhausted(attempts: Int, lastError: String)

    public var errorDescription: String? {
        switch self {
        case .exhausted(let attempts, let lastError):
            return "Structured output failed after \(attempts) attempt(s): \(lastError)"
        }
    }
}

public func executeWithStructuredCorrection<T: Sendable>(
    maxAttempts: Int = 3,
    baseDelayMilliseconds: Int = 150,
    invoke: @Sendable (_ correctionFeedback: String?, _ attempt: Int) async throws -> String,
    validate: @Sendable (_ rawText: String) -> Result<T, Error>
) async throws -> (value: T, attempts: Int) {
    let attemptsCap = max(1, maxAttempts)
    var feedback: String?
    var lastError = "Unknown structured output error"

    for attempt in 1...attemptsCap {
        do {
            let raw = try await invoke(feedback, attempt)
            switch validate(raw) {
            case .success(let value):
                return (value, attempt)
            case .failure(let validationError):
                lastError = validationError.localizedDescription
                feedback = "Previous response failed schema validation: \(lastError). Return ONLY valid JSON matching the required schema."
            }
        } catch {
            lastError = error.localizedDescription
            feedback = "Previous attempt failed (\(lastError)). Retry cleanly and return valid JSON."
            if attempt < attemptsCap && baseDelayMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(baseDelayMilliseconds * attempt))
            }
        }
    }

    throw PipiStructuredRetryError.exhausted(attempts: attemptsCap, lastError: lastError)
}
