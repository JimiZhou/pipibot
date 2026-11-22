import Foundation

// MARK: - Token & Cost Metering Engine (Alert-Only, Non-Blocking)

public struct PipiUsageBotBreakdown: Identifiable, Equatable, Sendable {
    public var id: String { botId }
    public let botId: String
    public let botName: String
    public let totalTokens: Int
    public let estimatedCostUSD: Double
    public let runCount: Int
}

public struct PipiUsageHostBreakdown: Identifiable, Equatable, Sendable {
    public var id: String { hostId }
    public let hostId: String
    public let totalTokens: Int
    public let estimatedCostUSD: Double
    public let runCount: Int
}

public struct PipiUsageSummary: Equatable, Sendable {
    public let todayTokens: Int
    public let todayCostUSD: Double
    public let sevenDayTokens: Int
    public let sevenDayCostUSD: Double
    public let byBot: [PipiUsageBotBreakdown]
    public let byHost: [PipiUsageHostBreakdown]
}

public enum PipiUsageMeteringEngine {

    /// Rough CJK + Latin token estimator used only when a provider omits explicit usage counts.
    public static func estimateTokens(for text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var cjkCount = 0
        var otherCount = 0
        for scalar in text.unicodeScalars {
            if (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value) {
                cjkCount += 1
            } else {
                otherCount += 1
            }
        }
        return max(1, Int(ceil(Double(cjkCount) * 1.45 + Double(otherCount) / 3.8)))
    }

    /// Estimate USD cost per 1M input/output tokens. Local Ollama / MLX / LM Studio models are $0.
    public static func estimateCostUSD(
        modelId: String,
        providerKind: String,
        promptTokens: Int,
        completionTokens: Int,
        cachedTokens: Int = 0
    ) -> (usd: Double, isLocalFree: Bool) {
        let lowerModel = modelId.lowercased()
        let lowerProvider = providerKind.lowercased()
        if lowerProvider.contains("ollama")
            || lowerProvider.contains("mlx")
            || lowerProvider.contains("lmstudio")
            || lowerProvider.contains("local")
            || lowerModel.hasPrefix("mlx-")
            || lowerModel.contains(":latest") {
            return (0.0, true)
        }

        // Approximate published per-1M-token rates (USD)
        let rates: (input: Double, output: Double) = {
            if lowerModel.contains("opus") { return (15.0, 75.0) }
            if lowerModel.contains("sonnet") { return (3.0, 15.0) }
            if lowerModel.contains("haiku") { return (0.8, 4.0) }
            if lowerModel.contains("gpt-5") || lowerModel.contains("o3") || lowerModel.contains("o1") { return (5.0, 20.0) }
            if lowerModel.contains("gpt-4o-mini") || lowerModel.contains("mini") || lowerModel.contains("flash") { return (0.15, 0.60) }
            if lowerModel.contains("gpt-4") || lowerModel.contains("codex") { return (2.5, 10.0) }
            if lowerModel.contains("gemini") && lowerModel.contains("pro") { return (1.25, 10.0) }
            if lowerModel.contains("deepseek") { return (0.27, 1.10) }
            if lowerModel.contains("qwen") || lowerModel.contains("glm") || lowerModel.contains("kimi") || lowerModel.contains("minimax") {
                return (0.40, 1.20)
            }
            return (1.50, 6.00)
        }()

        let billableInput = max(0, promptTokens - cachedTokens)
        let cachedCost = (Double(max(0, cachedTokens)) / 1_000_000.0) * (rates.input * 0.25)
        let inputCost = (Double(billableInput) / 1_000_000.0) * rates.input
        let outputCost = (Double(max(0, completionTokens)) / 1_000_000.0) * rates.output
        return (inputCost + cachedCost + outputCost, false)
    }

    /// Build a usage record from explicit or estimated token counts.
    public static func makeRecord(
        botId: String,
        botName: String,
        hostId: String = PipiHostDescriptor.localHostId,
        conversationId: String? = nil,
        taskTitle: String,
        modelId: String,
        providerKind: String,
        promptTokens: Int?,
        completionTokens: Int?,
        cachedTokens: Int = 0,
        fallbackPromptText: String = "",
        fallbackCompletionText: String = ""
    ) -> PipiUsageRecord {
        let isEstimated = (promptTokens == nil || completionTokens == nil)
        let pTokens = promptTokens ?? estimateTokens(for: fallbackPromptText)
        let cTokens = completionTokens ?? estimateTokens(for: fallbackCompletionText)
        let pricing = estimateCostUSD(
            modelId: modelId,
            providerKind: providerKind,
            promptTokens: pTokens,
            completionTokens: cTokens,
            cachedTokens: cachedTokens
        )
        return PipiUsageRecord(
            botId: botId,
            botName: botName,
            hostId: hostId,
            conversationId: conversationId,
            taskTitle: taskTitle,
            modelId: modelId,
            providerKind: providerKind,
            promptTokens: pTokens,
            completionTokens: cTokens,
            cachedTokens: cachedTokens,
            estimatedCostUSD: pricing.usd,
            isEstimated: isEstimated,
            isLocalFree: pricing.isLocalFree
        )
    }

    /// Aggregate today / 7-day / per-Bot / per-Host usage totals.
    public static func summarize(records: [PipiUsageRecord], now: Date = Date()) -> PipiUsageSummary {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        let formatter = ISO8601DateFormatter()

        var todayTokens = 0
        var todayCost = 0.0
        var weekTokens = 0
        var weekCost = 0.0
        var botAgg: [String: (name: String, tokens: Int, cost: Double, runs: Int)] = [:]
        var hostAgg: [String: (tokens: Int, cost: Double, runs: Int)] = [:]

        for rec in records {
            let date = formatter.date(from: rec.createdAt) ?? now
            if date >= startOfToday {
                todayTokens += rec.totalTokens
                todayCost += rec.estimatedCostUSD
            }
            if date >= sevenDaysAgo {
                weekTokens += rec.totalTokens
                weekCost += rec.estimatedCostUSD
                var b = botAgg[rec.botId] ?? (rec.botName, 0, 0.0, 0)
                b.tokens += rec.totalTokens
                b.cost += rec.estimatedCostUSD
                b.runs += 1
                botAgg[rec.botId] = b

                var h = hostAgg[rec.hostId] ?? (0, 0.0, 0)
                h.tokens += rec.totalTokens
                h.cost += rec.estimatedCostUSD
                h.runs += 1
                hostAgg[rec.hostId] = h
            }
        }

        let byBot = botAgg.map { key, val in
            PipiUsageBotBreakdown(
                botId: key,
                botName: val.name,
                totalTokens: val.tokens,
                estimatedCostUSD: val.cost,
                runCount: val.runs
            )
        }.sorted { $0.totalTokens > $1.totalTokens }

        let byHost = hostAgg.map { key, val in
            PipiUsageHostBreakdown(
                hostId: key,
                totalTokens: val.tokens,
                estimatedCostUSD: val.cost,
                runCount: val.runs
            )
        }.sorted { $0.totalTokens > $1.totalTokens }

        return PipiUsageSummary(
            todayTokens: todayTokens,
            todayCostUSD: todayCost,
            sevenDayTokens: weekTokens,
            sevenDayCostUSD: weekCost,
            byBot: byBot,
            byHost: byHost
        )
    }

    /// Evaluate gentle alert-only notices after a new usage record. Never blocks or interrupts execution.
    public static func evaluateAlerts(
        latestRecord: PipiUsageRecord,
        allRecords: [PipiUsageRecord],
        config: PipiUsageAlertConfig,
        existingAlerts: [PipiUsageAlertNotice],
        now: Date = Date()
    ) -> [PipiUsageAlertNotice] {
        guard config.enableAlerts else { return [] }
        var generated: [PipiUsageAlertNotice] = []
        let summary = summarize(records: allRecords, now: now)
        let dayKey = String(ISO8601DateFormatter().string(from: now).prefix(10))

        // 1. Per-task gentle alert
        if !latestRecord.isLocalFree && latestRecord.estimatedCostUSD >= config.perTaskCostAlertUSD {
            let scope = "task_cost:\(latestRecord.id)"
            if !existingAlerts.contains(where: { $0.scope == scope }) {
                generated.append(PipiUsageAlertNotice(
                    scope: scope,
                    messageZh: "用量提醒：任务「\(latestRecord.taskTitle)」本次估算消耗 $\(String(format: "%.2f", latestRecord.estimatedCostUSD))（阈值 $\(String(format: "%.2f", config.perTaskCostAlertUSD))），仅提醒不中断执行。",
                    messageEn: "Usage notice: Task \"\(latestRecord.taskTitle)\" used ~$\(String(format: "%.2f", latestRecord.estimatedCostUSD)) (alert threshold $\(String(format: "%.2f", config.perTaskCostAlertUSD))). Alert-only; execution is not blocked."
                ))
            }
        } else if latestRecord.totalTokens >= config.perTaskTokenAlert {
            let scope = "task_tokens:\(latestRecord.id)"
            if !existingAlerts.contains(where: { $0.scope == scope }) {
                generated.append(PipiUsageAlertNotice(
                    scope: scope,
                    messageZh: "用量提醒：任务「\(latestRecord.taskTitle)」消耗 \(latestRecord.totalTokens) tokens（阈值 \(config.perTaskTokenAlert)），仅提醒不拦截。",
                    messageEn: "Usage notice: Task \"\(latestRecord.taskTitle)\" used \(latestRecord.totalTokens) tokens (threshold \(config.perTaskTokenAlert)). Alert-only."
                ))
            }
        }

        // 2. Daily aggregate gentle alert (deduped per calendar day)
        if summary.todayCostUSD >= config.dailyCostAlertUSD {
            let scope = "daily_cost:\(dayKey)"
            if !existingAlerts.contains(where: { $0.scope == scope }) {
                generated.append(PipiUsageAlertNotice(
                    scope: scope,
                    messageZh: "今日用量提醒：累计估算费用已达 $\(String(format: "%.2f", summary.todayCostUSD))（阈值 $\(String(format: "%.2f", config.dailyCostAlertUSD))），所有任务仍照常运行。",
                    messageEn: "Daily usage notice: Estimated spend reached $\(String(format: "%.2f", summary.todayCostUSD)) (threshold $\(String(format: "%.2f", config.dailyCostAlertUSD))). Tasks continue uninterrupted."
                ))
            }
        } else if summary.todayTokens >= config.dailyTokenAlert {
            let scope = "daily_tokens:\(dayKey)"
            if !existingAlerts.contains(where: { $0.scope == scope }) {
                generated.append(PipiUsageAlertNotice(
                    scope: scope,
                    messageZh: "今日用量提醒：累计已消耗 \(summary.todayTokens) tokens（阈值 \(config.dailyTokenAlert)），所有任务仍照常运行。",
                    messageEn: "Daily usage notice: Total tokens reached \(summary.todayTokens) (threshold \(config.dailyTokenAlert)). Tasks continue uninterrupted."
                ))
            }
        }

        return generated
    }

    public static func defaultStorageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("PiPiBot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage-ledger.json")
    }

    public static func loadLedger(from url: URL = defaultStorageURL()) -> [PipiUsageRecord] {
        guard let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([PipiUsageRecord].self, from: data) else {
            return []
        }
        return records
    }

    public static func saveLedger(_ records: [PipiUsageRecord], to url: URL = defaultStorageURL()) {
        let capped = Array(records.suffix(1500))
        if let data = try? JSONEncoder().encode(capped) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
