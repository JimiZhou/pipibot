// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// Three-Tier Fast Group Auto-Router (Decision Model):
//   L1: Zero-latency explicit `@Mention` & deterministic rule pre-check (0ms)
//   L2: Fast lightweight Decision Model (Local Ollama/MLX -> Cloudflare Workers AI -> Custom OpenAI-compat, 1.5s timeout)
//   L3: Fail-open fallback to Lead bot whenever unconfigured, timed out, or confidence < minConfidence (0.6).

import Foundation

public struct PipiGroupRouterCandidate: Sendable, Equatable {
    public let id: String
    public let name: String
    public let roleTitle: String
    public let keywords: [String]

    public init(id: String, name: String, roleTitle: String, keywords: [String] = []) {
        self.id = id
        self.name = name
        self.roleTitle = roleTitle
        self.keywords = keywords
    }
}

public typealias PipiDecisionModelHTTPExecutor = @Sendable (URLRequest) async throws -> (Data, Int)

public enum PipiGroupAutoRouter {
    /// Routes an un-mentioned or mentioned group message across 3 tiers with strict fail-open guarantee.
    public static func route(
        message: String,
        candidates: [PipiGroupRouterCandidate],
        leadBotId: String,
        config: PipiDecisionModelConfig,
        apiKey: String? = nil,
        executor: PipiDecisionModelHTTPExecutor? = nil
    ) async -> PipiGroupRouteDecision {
        let start = Date()
        guard !candidates.isEmpty else {
            return PipiGroupRouteDecision(tier: .leadFallback, picks: [], latencyMs: 0, note: "No candidates")
        }

        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // Tier 1A: Explicit `@BotName` mention
        let explicitMatches = candidates.filter { cand in
            lower.contains("@\(cand.name.lowercased())") || lower.contains("@\(cand.id.lowercased())")
        }
        if !explicitMatches.isEmpty {
            let picks = explicitMatches.map {
                PipiGroupRoutePick(botId: $0.id, confidence: 1.0, reason: "Explicit @mention")
            }
            return PipiGroupRouteDecision(tier: .explicitMention, picks: picks, latencyMs: elapsedMs(since: start), note: "Explicit @mention")
        }

        // Tier 1B: Deterministic strong keyword rule match (0ms)
        var scoredRules: [(PipiGroupRouterCandidate, Int)] = []
        for cand in candidates {
            let hits = cand.keywords.filter { !$0.isEmpty && lower.contains($0.lowercased()) }.count
            if hits > 0 {
                scoredRules.append((cand, hits))
            }
        }
        scoredRules.sort { $0.1 > $1.1 }
        if let top = scoredRules.first, top.1 >= 2 {
            let selected = Array(scoredRules.prefix(config.maxAutoParallel)).map {
                PipiGroupRoutePick(botId: $0.0.id, confidence: 0.88, reason: "Matched \($0.1) domain rules")
            }
            return PipiGroupRouteDecision(tier: .deterministicRule, picks: selected, latencyMs: elapsedMs(since: start), note: "Deterministic rule match")
        }

        // Tier 2: Fast Decision Model (if enabled & configured)
        if config.enabled && config.providerKind != .disabled {
            if let modelPicks = await queryDecisionModel(
                message: trimmed,
                candidates: candidates,
                config: config,
                apiKey: apiKey,
                executor: executor
            ), !modelPicks.isEmpty {
                let valid = modelPicks
                    .filter { pick in
                        pick.confidence >= config.minConfidence && candidates.contains(where: { $0.id == pick.botId })
                    }
                    .sorted { $0.confidence > $1.confidence }
                let capped = Array(valid.prefix(config.maxAutoParallel))
                if !capped.isEmpty {
                    let ms = elapsedMs(since: start)
                    return PipiGroupRouteDecision(
                        tier: .decisionModel,
                        picks: capped,
                        latencyMs: ms,
                        note: "Auto-routed · \(ms)ms · \(String(format: "%.2f", capped[0].confidence))"
                    )
                }
            }
        }

        // Tier 3: Fail-open safe fallback to Lead bot
        let fallbackId = candidates.first(where: { $0.id == leadBotId })?.id ?? candidates[0].id
        return PipiGroupRouteDecision(
            tier: .leadFallback,
            picks: [PipiGroupRoutePick(botId: fallbackId, confidence: 0.5, reason: "Fail-open to room lead")],
            latencyMs: elapsedMs(since: start),
            note: "Lead fallback"
        )
    }

    private static func queryDecisionModel(
        message: String,
        candidates: [PipiGroupRouterCandidate],
        config: PipiDecisionModelConfig,
        apiKey: String?,
        executor: PipiDecisionModelHTTPExecutor?
    ) async -> [PipiGroupRoutePick]? {
        let rosterLines = candidates.map { c in
            let tags = c.keywords.prefix(3).joined(separator: ",")
            return "- \(c.id) | \(c.name): \(c.roleTitle)\(tags.isEmpty ? "" : " [\(tags)]")"
        }.joined(separator: "\n")

        let systemPrompt = """
        You are an ultra-fast group chat router. Pick 1 to \(config.maxAutoParallel) best bot IDs for the user message.
        Reply ONLY strict JSON: {"picks":[{"botId":"...","confidence":0.0,"reason":"short"}]}
        Bots:
        \(rosterLines)
        """

        let endpointURL: URL?
        var headers: [String: String] = ["Content-Type": "application/json"]
        var payloadObj: [String: Any]

        switch config.providerKind {
        case .cloudflareWorkersAI:
            let acct = config.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !acct.isEmpty, !key.isEmpty else { return nil }
            let model = config.modelId.isEmpty ? "@cf/meta/llama-3.2-3b-instruct" : config.modelId
            endpointURL = URL(string: "https://api.cloudflare.com/client/v4/accounts/\(acct)/ai/run/\(model)")
            headers["Authorization"] = "Bearer \(key)"
            payloadObj = [
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": String(message.prefix(500))]
                ],
                "max_tokens": 120,
                "temperature": 0.0
            ]
        case .localFast, .customOpenAICompat:
            let urlStr = config.endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !urlStr.isEmpty else { return nil }
            endpointURL = URL(string: urlStr)
            if let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                headers["Authorization"] = "Bearer \(key)"
            }
            payloadObj = [
                "model": config.modelId.isEmpty ? "qwen2.5:1.5b" : config.modelId,
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": String(message.prefix(500))]
                ],
                "max_tokens": 120,
                "temperature": 0.0
            ]
        case .disabled:
            return nil
        }

        guard let url = endpointURL,
              let body = try? JSONSerialization.data(withJSONObject: payloadObj) else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = Double(config.timeoutMs) / 1000.0
        req.httpBody = body
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        do {
            let (data, status): (Data, Int)
            if let executor {
                (data, status) = try await executor(req)
            } else {
                let (respData, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 200
                (data, status) = (respData, code)
            }
            guard (200...299).contains(status) else { return nil }
            return parseModelResponse(data)
        } catch {
            return nil
        }
    }

    public static func parseModelResponse(_ data: Data) -> [PipiGroupRoutePick]? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var contentText: String? = nil

        // OpenAI / Ollama / OpenRouter shape
        if let choices = root["choices"] as? [[String: Any]],
           let first = choices.first,
           let msg = first["message"] as? [String: Any],
           let text = msg["content"] as? String {
            contentText = text
        }
        // Cloudflare Workers AI shape
        if contentText == nil,
           let result = root["result"] as? [String: Any],
           let text = result["response"] as? String {
            contentText = text
        }
        // Direct JSON shape (for tests / custom classifiers)
        if contentText == nil, root["picks"] != nil {
            contentText = String(data: data, encoding: .utf8)
        }

        guard let rawText = contentText,
              let jsonStart = rawText.firstIndex(of: "{"),
              let jsonEnd = rawText.lastIndex(of: "}") else {
            return nil
        }
        let slice = String(rawText[jsonStart...jsonEnd])
        guard let sliceData = slice.data(using: .utf8),
              let parsed = (try? JSONSerialization.jsonObject(with: sliceData)) as? [String: Any],
              let picksArr = parsed["picks"] as? [[String: Any]] else {
            return nil
        }

        return picksArr.compactMap { item in
            guard let botId = item["botId"] as? String, !botId.isEmpty else { return nil }
            let conf = (item["confidence"] as? Double) ?? Double(item["confidence"] as? Int ?? 0)
            let reason = (item["reason"] as? String) ?? "Decision model pick"
            return PipiGroupRoutePick(botId: botId, confidence: conf, reason: reason)
        }
    }

    private static func elapsedMs(since start: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(start) * 1000))
    }
}
