import Foundation

public enum PipiDaemonClientError: Error, Sendable {
    case invalidUrl
    case httpStatus(Int, String)
    case decodingError(String)
}

public struct OutcomesEnvelope: Codable, Sendable {
    public let outcomes: [OutcomeResponsibility]
    public let subSessions: [SubSession]
}

public struct OutcomeSingleEnvelope: Codable, Sendable {
    public let outcome: OutcomeResponsibility
}

public struct EvaluateOutcomeEnvelope: Codable, Sendable {
    public let outcome: OutcomeResponsibility
    public let stage1Passed: Bool
    public let skipReason: String?
    public let subSession: SubSession?
    public let createdDecision: NeedsYouDecision?
}

public struct DecisionsEnvelope: Codable, Sendable {
    public let decisions: [NeedsYouDecision]
    public let pendingCount: Int
}

public struct DecisionSingleEnvelope: Codable, Sendable {
    public let decision: NeedsYouDecision
}

public struct CueEnvelope: Codable, Sendable {
    public let latest: CueSuggestion?
    public let cues: [CueSuggestion]
}

public struct CueSingleEnvelope: Codable, Sendable {
    public let cue: CueSuggestion
}

public struct ChatTurnResponseEnvelope: Codable, Sendable {
    public let sessionId: String?
    public let providerUsed: HarnessProvider
    public let modelId: String?
    public let text: String
    public let recalledCount: Int?
}

public struct CueExecuteEnvelope: Codable, Sendable {
    public let cue: CueSuggestion
    public let action: CueAction
    public let executed: Bool
    public let turnResult: ChatTurnResponseEnvelope
}

public struct FleetEnvelope: Codable, Sendable {
    public let nodes: [FleetNodeTelemetry]
    public let cloudflare: CloudflareTunnelStatus
}

public struct TranscriptEntryDTO: Codable, Sendable {
    public let id: String
    public let role: String
    public let provider: HarnessProvider
    public let content: String
    public let createdAt: String
}

public struct TranscriptEnvelope: Codable, Sendable {
    public let sessionId: String
    public let entries: [TranscriptEntryDTO]
}

public struct MemorySnapshotEnvelope: Codable, Sendable {
    public let episodic: [MemoryEntry]
    public let skills: [SynthesizedSkillCandidate]
    public let lastDigest: EvolutionSummary?
    public let understandingScore: UnderstandingScoreBreakdown
}

public struct DreamEnvelope: Codable, Sendable {
    public let summary: EvolutionSummary
}

public enum PipiSseEvent: Sendable {
    case connected(avatarState: AvatarState53?)
    case harnessPulse(HarnessActivityPulse)
    case outcomeUpdate(OutcomeResponsibility)
    case decisionNeedsYou(NeedsYouDecision)
    case decisionResolved(NeedsYouDecision)
    case cueSuggestion(CueSuggestion)
    case nodeHeartbeat(FleetNodeTelemetry)
    case evolutionDigestReady(EvolutionSummary)
}

public actor PipiDaemonClient {
    public private(set) var baseUrlString: String
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseUrlString: String = "http://127.0.0.1:4242") {
        self.baseUrlString = baseUrlString
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6.0
        config.timeoutIntervalForResource = 60.0
        self.session = URLSession(configuration: config)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func updateBaseUrl(_ urlString: String) {
        self.baseUrlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func fetchStatus() async throws -> DaemonStatusSnapshot {
        try await request(path: "/api/v1/status", method: "GET")
    }

    public func fetchOutcomes() async throws -> OutcomesEnvelope {
        try await request(path: "/api/v1/outcomes", method: "GET")
    }

    public func createOutcome(
        title: String,
        domain: OutcomeDomain,
        goal: String,
        preferredHarness: HarnessProvider,
        dailyBudgetUsd: Double
    ) async throws -> OutcomeSingleEnvelope {
        struct Body: Encodable {
            let title: String
            let domain: OutcomeDomain
            let goal: String
            let preferredHarness: HarnessProvider
            let dailyBudgetUsd: Double
        }
        return try await request(
            path: "/api/v1/outcomes",
            method: "POST",
            body: Body(
                title: title,
                domain: domain,
                goal: goal,
                preferredHarness: preferredHarness,
                dailyBudgetUsd: dailyBudgetUsd
            )
        )
    }

    public func evaluateOutcome(id: String, requireHumanSignOff: Bool = false) async throws -> EvaluateOutcomeEnvelope {
        struct Body: Encodable {
            let requireHumanSignOff: Bool
            let useLiveHarness: Bool
        }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await request(
            path: "/api/v1/outcomes/\(encoded)/evaluate",
            method: "POST",
            body: Body(requireHumanSignOff: requireHumanSignOff, useLiveHarness: false)
        )
    }

    public func fetchDecisions() async throws -> DecisionsEnvelope {
        try await request(path: "/api/v1/decisions?status=all", method: "GET")
    }

    public func resolveDecision(
        id: String,
        chosenOptionId: String,
        userNote: String? = nil,
        resolvedBy: String = "apple-app"
    ) async throws -> DecisionSingleEnvelope {
        struct Body: Encodable {
            let chosenOptionId: String
            let userNote: String?
            let resolvedBy: String
        }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await request(
            path: "/api/v1/decisions/\(encoded)/resolve",
            method: "POST",
            body: Body(chosenOptionId: chosenOptionId, userNote: userNote, resolvedBy: resolvedBy)
        )
    }

    public func fetchCue() async throws -> CueEnvelope {
        try await request(path: "/api/v1/cue", method: "GET")
    }

    public func refreshCue(
        activeAppName: String? = nil,
        windowTitle: String? = nil,
        workspacePath: String? = nil,
        gitBranch: String? = nil
    ) async throws -> CueSingleEnvelope {
        struct Body: Encodable {
            let activeAppName: String?
            let windowTitle: String?
            let workspacePath: String?
            let gitBranch: String?
        }
        return try await request(
            path: "/api/v1/cue/refresh",
            method: "POST",
            body: Body(
                activeAppName: activeAppName,
                windowTitle: windowTitle,
                workspacePath: workspacePath,
                gitBranch: gitBranch
            )
        )
    }

    public func executeCueAction(cueId: String, actionId: String) async throws -> CueExecuteEnvelope {
        struct Body: Encodable {
            let actionId: String
        }
        let encoded = cueId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cueId
        return try await request(
            path: "/api/v1/cue/\(encoded)/execute",
            method: "POST",
            body: Body(actionId: actionId)
        )
    }

    public func sendCueFeedback(cueId: String, feedback: CueSuggestion.Feedback) async throws -> CueSingleEnvelope {
        struct Body: Encodable {
            let feedback: CueSuggestion.Feedback
        }
        let encoded = cueId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cueId
        return try await request(
            path: "/api/v1/cue/\(encoded)/feedback",
            method: "POST",
            body: Body(feedback: feedback)
        )
    }

    public func fetchFleet() async throws -> FleetEnvelope {
        try await request(path: "/api/v1/fleet", method: "GET")
    }

    public func fetchTranscript() async throws -> TranscriptEnvelope {
        try await request(path: "/api/v1/chat/transcript", method: "GET")
    }

    public func sendChatTurn(
        prompt: String,
        provider: HarnessProvider
    ) async throws -> ChatTurnResponseEnvelope {
        struct Body: Encodable {
            let prompt: String
            let provider: HarnessProvider
            let useLiveHarness: Bool
        }
        return try await request(
            path: "/api/v1/chat/turn",
            method: "POST",
            body: Body(prompt: prompt, provider: provider, useLiveHarness: false)
        )
    }

    public func fetchMemory() async throws -> MemorySnapshotEnvelope {
        try await request(path: "/api/v1/memory", method: "GET")
    }

    public func runDreamCycle() async throws -> DreamEnvelope {
        struct Empty: Encodable {}
        return try await request(path: "/api/v1/memory/dream", method: "POST", body: Empty())
    }

    public func reviewEvolutionDiff(
        diffId: String,
        action: String,
        editedValue: String? = nil
    ) async throws -> DreamEnvelope {
        struct Body: Encodable {
            let action: String
            let editedValue: String?
        }
        let encoded = diffId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? diffId
        return try await request(
            path: "/api/v1/memory/diffs/\(encoded)/review",
            method: "POST",
            body: Body(action: action, editedValue: editedValue)
        )
    }

    public func fetchSoulDocuments() async throws -> SoulDocumentPreview {
        try await request(path: "/api/v1/memory/soul", method: "GET")
    }

    public func streamEvents() -> AsyncThrowingStream<PipiSseEvent, Error> {
        let currentBase = baseUrlString
        let urlSession = session
        let jsonDecoder = decoder

        return AsyncThrowingStream { continuation in
            let task = Task {
                guard let url = URL(string: currentBase + "/api/v1/events") else {
                    continuation.finish(throwing: PipiDaemonClientError.invalidUrl)
                    return
                }
                var req = URLRequest(url: url)
                req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                req.timeoutInterval = 300

                do {
                    let (bytes, response) = try await urlSession.bytes(for: req)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        continuation.finish(throwing: PipiDaemonClientError.httpStatus(http.statusCode, "SSE failed"))
                        return
                    }

                    var eventName = "message"
                    var dataLines: [String] = []

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if line.isEmpty {
                            if !dataLines.isEmpty {
                                let rawData = dataLines.joined(separator: "\n")
                                if let parsed = Self.decodeSseEvent(name: eventName, jsonString: rawData, decoder: jsonDecoder) {
                                    continuation.yield(parsed)
                                }
                            }
                            eventName = "message"
                            dataLines = []
                            continue
                        }
                        if line.hasPrefix("event:") {
                            eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func decodeSseEvent(
        name: String,
        jsonString: String,
        decoder: JSONDecoder
    ) -> PipiSseEvent? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        switch name {
        case "connected":
            struct ConnectedPayload: Decodable { let avatarState: AvatarState53? }
            let p = try? decoder.decode(ConnectedPayload.self, from: data)
            return .connected(avatarState: p?.avatarState)
        case "harness.pulse":
            guard let p = try? decoder.decode(HarnessActivityPulse.self, from: data) else { return nil }
            return .harnessPulse(p)
        case "outcome.update":
            guard let p = try? decoder.decode(OutcomeResponsibility.self, from: data) else { return nil }
            return .outcomeUpdate(p)
        case "decision.needs_you":
            guard let p = try? decoder.decode(NeedsYouDecision.self, from: data) else { return nil }
            return .decisionNeedsYou(p)
        case "decision.resolved":
            guard let p = try? decoder.decode(NeedsYouDecision.self, from: data) else { return nil }
            return .decisionResolved(p)
        case "cue.suggestion":
            guard let p = try? decoder.decode(CueSuggestion.self, from: data) else { return nil }
            return .cueSuggestion(p)
        case "node.heartbeat":
            guard let p = try? decoder.decode(FleetNodeTelemetry.self, from: data) else { return nil }
            return .nodeHeartbeat(p)
        case "evolution.digest_ready":
            guard let p = try? decoder.decode(EvolutionSummary.self, from: data) else { return nil }
            return .evolutionDigestReady(p)
        default:
            return nil
        }
    }

    private func request<Response: Decodable>(
        path: String,
        method: String
    ) async throws -> Response {
        guard let url = URL(string: baseUrlString + path) else {
            throw PipiDaemonClientError.invalidUrl
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await execute(req)
    }

    private func request<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body
    ) async throws -> Response {
        guard let url = URL(string: baseUrlString + path) else {
            throw PipiDaemonClientError.invalidUrl
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try encoder.encode(body)
        return try await execute(req)
    }

    private func execute<Response: Decodable>(_ req: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw PipiDaemonClientError.httpStatus(http.statusCode, text)
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw PipiDaemonClientError.decodingError(error.localizedDescription)
        }
    }
}
