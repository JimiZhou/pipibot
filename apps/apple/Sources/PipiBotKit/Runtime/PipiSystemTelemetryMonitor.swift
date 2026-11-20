// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// Lightweight Native System & Inference Telemetry Monitor
// Samples real macOS CPU %, Memory, Metal Unified VRAM budget/usage, and Live Inference Input/Output Latency.

import Foundation
#if os(macOS)
import Darwin
import Metal
#endif

public struct PipiInferenceLatencyMetrics: Codable, Sendable, Equatable {
    public let engineLabel: String
    public let inputLatencyMs: Int?   // TTFT: dispatch -> first output token
    public let outputLatencyMs: Int?  // First token (or dispatch) -> completion
    public let totalLatencyMs: Int?
    public let tokensPerSecond: Double?
    public let inputTokensEstimate: Int
    public let outputTokensEstimate: Int
    public let succeeded: Bool
    public let recordedAt: Date

    public init(
        engineLabel: String,
        inputLatencyMs: Int?,
        outputLatencyMs: Int?,
        totalLatencyMs: Int?,
        tokensPerSecond: Double?,
        inputTokensEstimate: Int,
        outputTokensEstimate: Int,
        succeeded: Bool,
        recordedAt: Date = Date()
    ) {
        self.engineLabel = engineLabel
        self.inputLatencyMs = inputLatencyMs
        self.outputLatencyMs = outputLatencyMs
        self.totalLatencyMs = totalLatencyMs
        self.tokensPerSecond = tokensPerSecond
        self.inputTokensEstimate = inputTokensEstimate
        self.outputTokensEstimate = outputTokensEstimate
        self.succeeded = succeeded
        self.recordedAt = recordedAt
    }
}

public struct PipiSystemTelemetrySnapshot: Sendable, Equatable {
    public let cpuUsagePercent: Double
    public let memoryUsedGB: Double
    public let memoryTotalGB: Double
    public let gpuName: String
    public let vramUsedGB: Double
    public let vramBudgetGB: Double
    public let isUnifiedMemory: Bool
    public let sampledAt: Date

    public var memoryUsagePercent: Double {
        guard memoryTotalGB > 0 else { return 0 }
        return min(100, max(0, (memoryUsedGB / memoryTotalGB) * 100.0))
    }

    public var vramUsagePercent: Double {
        guard vramBudgetGB > 0 else { return 0 }
        return min(100, max(0, (vramUsedGB / vramBudgetGB) * 100.0))
    }

    public static let initial = PipiSystemTelemetrySnapshot(
        cpuUsagePercent: 0,
        memoryUsedGB: 0,
        memoryTotalGB: max(1, Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0),
        gpuName: "Apple GPU",
        vramUsedGB: 0,
        vramBudgetGB: 0,
        isUnifiedMemory: true,
        sampledAt: Date()
    )
}

@MainActor
@Observable
public final class PipiSystemTelemetryMonitor {
    public private(set) var snapshot: PipiSystemTelemetrySnapshot = .initial
    public private(set) var cpuHistory: [Double] = []
    public private(set) var lastInference: PipiInferenceLatencyMetrics? = nil
    public private(set) var isInferenceActive: Bool = false

    private struct ActiveInferenceTracker {
        let runId: String
        let engineLabel: String
        let startedAt: Date
        var firstTokenAt: Date?
        let inputTokensEstimate: Int
    }

    private var activeTrackers: [String: ActiveInferenceTracker] = [:]
    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var pollTask: Task<Void, Never>?
    private var activeFastPollConsumers: Int = 0

    public init() {
        sampleNow()
    }

    // MARK: Polling Lifecycle (Ultra-low overhead)

    public func beginFastPolling() {
        activeFastPollConsumers += 1
        sampleNow()
        restartPollLoop(intervalSeconds: 2.0)
    }

    public func endFastPolling() {
        activeFastPollConsumers = max(0, activeFastPollConsumers - 1)
        if activeFastPollConsumers == 0 {
            restartPollLoop(intervalSeconds: 6.0)
        }
    }

    public func ensureBackgroundPolling() {
        if pollTask == nil {
            restartPollLoop(intervalSeconds: 6.0)
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func restartPollLoop(intervalSeconds: Double) {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int(intervalSeconds * 1000)))
                guard let self, !Task.isCancelled else { return }
                self.sampleNow()
            }
        }
    }

    // MARK: Inference I/O Latency Tracking

    public func beginInference(runId: String, engineLabel: String, inputTokensEstimate: Int) {
        activeTrackers[runId] = ActiveInferenceTracker(
            runId: runId,
            engineLabel: engineLabel,
            startedAt: Date(),
            firstTokenAt: nil,
            inputTokensEstimate: max(1, inputTokensEstimate)
        )
        isInferenceActive = !activeTrackers.isEmpty
    }

    public func markFirstToken(runId: String) {
        guard var tracker = activeTrackers[runId], tracker.firstTokenAt == nil else { return }
        tracker.firstTokenAt = Date()
        activeTrackers[runId] = tracker
    }

    public func finishInference(runId: String, outputTokensEstimate: Int, succeeded: Bool) {
        guard let tracker = activeTrackers.removeValue(forKey: runId) else {
            isInferenceActive = !activeTrackers.isEmpty
            return
        }
        isInferenceActive = !activeTrackers.isEmpty
        let now = Date()
        let metrics = Self.computeMetrics(
            engineLabel: tracker.engineLabel,
            startedAt: tracker.startedAt,
            firstTokenAt: tracker.firstTokenAt,
            finishedAt: now,
            inputTokensEstimate: tracker.inputTokensEstimate,
            outputTokensEstimate: max(0, outputTokensEstimate),
            succeeded: succeeded
        )
        lastInference = metrics
    }

    public nonisolated static func computeMetrics(
        engineLabel: String,
        startedAt: Date,
        firstTokenAt: Date?,
        finishedAt: Date,
        inputTokensEstimate: Int,
        outputTokensEstimate: Int,
        succeeded: Bool
    ) -> PipiInferenceLatencyMetrics {
        let totalMs = max(1, Int((finishedAt.timeIntervalSince(startedAt) * 1000.0).rounded()))
        let inputMs: Int
        let outputMs: Int
        if let first = firstTokenAt {
            inputMs = max(1, Int((first.timeIntervalSince(startedAt) * 1000.0).rounded()))
            outputMs = max(1, Int((finishedAt.timeIntervalSince(first) * 1000.0).rounded()))
        } else {
            inputMs = totalMs
            outputMs = 0
        }
        let genSeconds = max(0.05, Double(max(outputMs, 50)) / 1000.0)
        let tps: Double? = outputTokensEstimate > 0
            ? ((Double(outputTokensEstimate) / genSeconds) * 10.0).rounded() / 10.0
            : nil

        return PipiInferenceLatencyMetrics(
            engineLabel: engineLabel,
            inputLatencyMs: inputMs,
            outputLatencyMs: outputMs > 0 ? outputMs : totalMs,
            totalLatencyMs: totalMs,
            tokensPerSecond: tps,
            inputTokensEstimate: inputTokensEstimate,
            outputTokensEstimate: outputTokensEstimate,
            succeeded: succeeded,
            recordedAt: finishedAt
        )
    }

    // MARK: Native Hardware Sampling (CPU / RAM / Metal VRAM)

    public func sampleNow() {
        let totalGB = max(1.0, Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0)
        #if os(macOS)
        let cpuPct = sampleCPUUsagePercent()
        let memUsedGB = sampleMemoryUsedGB(totalGB: totalGB)
        let gpuInfo = sampleMetalVRAM(memoryUsedGB: memUsedGB, totalGB: totalGB)
        snapshot = PipiSystemTelemetrySnapshot(
            cpuUsagePercent: cpuPct,
            memoryUsedGB: memUsedGB,
            memoryTotalGB: totalGB,
            gpuName: gpuInfo.name,
            vramUsedGB: gpuInfo.usedGB,
            vramBudgetGB: gpuInfo.budgetGB,
            isUnifiedMemory: gpuInfo.unified,
            sampledAt: Date()
        )
        #else
        snapshot = PipiSystemTelemetrySnapshot(
            cpuUsagePercent: 0,
            memoryUsedGB: 0,
            memoryTotalGB: totalGB,
            gpuName: "Apple GPU",
            vramUsedGB: 0,
            vramBudgetGB: totalGB * 0.6,
            isUnifiedMemory: true,
            sampledAt: Date()
        )
        #endif

        cpuHistory.append(snapshot.cpuUsagePercent)
        if cpuHistory.count > 16 {
            cpuHistory.removeFirst(cpuHistory.count - 16)
        }
    }

    #if os(macOS)
    private func sampleCPUUsagePercent() -> Double {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &load) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return snapshot.cpuUsagePercent }

        let user = UInt64(load.cpu_ticks.0)
        let system = UInt64(load.cpu_ticks.1)
        let idle = UInt64(load.cpu_ticks.2)
        let nice = UInt64(load.cpu_ticks.3)

        defer { previousCPUTicks = (user, system, idle, nice) }

        guard let prev = previousCPUTicks else {
            let total = Double(user + system + idle + nice)
            guard total > 0 else { return 0 }
            return min(100, max(0, (Double(user + system + nice) / total) * 100.0))
        }

        let dUser = user >= prev.user ? user - prev.user : 0
        let dSys = system >= prev.system ? system - prev.system : 0
        let dIdle = idle >= prev.idle ? idle - prev.idle : 0
        let dNice = nice >= prev.nice ? nice - prev.nice : 0
        let total = Double(dUser + dSys + dIdle + dNice)
        guard total > 0 else { return snapshot.cpuUsagePercent }
        return min(100, max(0, (Double(dUser + dSys + dNice) / total) * 100.0))
    }

    private func sampleMemoryUsedGB(totalGB: Double) -> Double {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return totalGB * 0.5 }
        let pageSize = UInt64(max(4096, sysconf(_SC_PAGESIZE)))
        let active = UInt64(vmStats.active_count) * pageSize
        let wired = UInt64(vmStats.wire_count) * pageSize
        let compressed = UInt64(vmStats.compressor_page_count) * pageSize
        let usedBytes = active + wired + compressed
        return min(totalGB, Double(usedBytes) / 1_073_741_824.0)
    }

    private func sampleMetalVRAM(memoryUsedGB: Double, totalGB: Double) -> (name: String, usedGB: Double, budgetGB: Double, unified: Bool) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return ("Apple GPU", memoryUsedGB, totalGB * 0.75, true)
        }
        let budget = Double(device.recommendedMaxWorkingSetSize) / 1_073_741_824.0
        let metalAllocated = Double(device.currentAllocatedSize) / 1_073_741_824.0
        let unified = device.hasUnifiedMemory
        // On Apple Silicon unified memory, system active+wired RAM reflects the real shared GPU/VRAM footprint across local engines (Ollama/MLX/llama.cpp/PolyStrata).
        let effectiveUsed = unified ? min(budget > 0 ? budget : totalGB, max(metalAllocated, memoryUsedGB)) : metalAllocated
        return (device.name, effectiveUsed, budget > 0 ? budget : totalGB * 0.75, unified)
    }
    #endif
}
