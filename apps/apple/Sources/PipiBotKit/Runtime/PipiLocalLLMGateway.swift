// PiPiBot — Clean-room MIT implementation.
// Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
// Linger Open Source License; zero source code, prompts, or assets copied).
// Optional MIT local MoE target: simplexai-labs/PolyStrata (MIT License). See root NOTICE.

import Foundation
#if canImport(Network)
import Network
#endif

// MARK: - 1. Gateway Configuration & Isolated CLI Reverse-Injection Contracts (Wave 4 · #07)

public enum PipiGatewayUpstreamDialect: String, Codable, Sendable, Equatable {
    case openai
    case anthropic

    public static func detect(baseURL: String) -> PipiGatewayUpstreamDialect {
        let lower = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.contains("api.anthropic.com") || lower.hasSuffix("/anthropic") || lower.contains("/anthropic/") {
            return .anthropic
        }
        return .openai
    }
}

public struct PipiLocalGatewayConfig: Codable, Sendable, Equatable {
    public var sourceMode: PipiModelSourceMode
    public var reverseInjectCLIAgents: Bool
    public var enableMacPolyStrataBeta: Bool
    public var selectedLocalEngine: PipiLocalInferenceEngineKind
    public var selectedLocalModelId: String
    public var localUpstreamBaseURL: String
    public var gatewayPort: Int
    public var byokProviderId: String?

    public init(
        sourceMode: PipiModelSourceMode = .subscription,
        reverseInjectCLIAgents: Bool = false,
        enableMacPolyStrataBeta: Bool = true,
        selectedLocalEngine: PipiLocalInferenceEngineKind = .polystrata,
        selectedLocalModelId: String = "qwen3.8-27b-ud-q4_k_m",
        localUpstreamBaseURL: String = "http://127.0.0.1:11438/v1",
        gatewayPort: Int = 18432,
        byokProviderId: String? = nil
    ) {
        self.sourceMode = sourceMode
        self.reverseInjectCLIAgents = reverseInjectCLIAgents
        self.enableMacPolyStrataBeta = enableMacPolyStrataBeta
        self.selectedLocalEngine = selectedLocalEngine
        self.selectedLocalModelId = selectedLocalModelId
        self.localUpstreamBaseURL = localUpstreamBaseURL
        self.gatewayPort = gatewayPort
        self.byokProviderId = byokProviderId
    }
}

public struct PipiGatewayUpstreamTarget: Sendable, Equatable {
    public let sourceMode: PipiModelSourceMode
    public let dialect: PipiGatewayUpstreamDialect
    public let baseURL: String
    public let modelId: String
    public let apiKey: String?
    public let contextWindow: Int

    public init(
        sourceMode: PipiModelSourceMode,
        dialect: PipiGatewayUpstreamDialect,
        baseURL: String,
        modelId: String,
        apiKey: String? = nil,
        contextWindow: Int = 65_536
    ) {
        self.sourceMode = sourceMode
        self.dialect = dialect
        self.baseURL = baseURL
        self.modelId = modelId
        self.apiKey = apiKey
        self.contextWindow = contextWindow
    }
}

public struct PipiGatewayRuntimeStatus: Sendable, Equatable {
    public let isRunning: Bool
    public let origin: String
    public let port: Int
    public let modelId: String
    public let sourceMode: PipiModelSourceMode
    public let requestsServed: Int

    public static let stopped = PipiGatewayRuntimeStatus(
        isRunning: false,
        origin: "",
        port: 0,
        modelId: "",
        sourceMode: .subscription,
        requestsServed: 0
    )
}

public enum PipiReverseInjectedCLITarget: String, CaseIterable, Sendable, Equatable {
    case claudeCode = "claude-code"
    case codex
    case pi
    case opencode

    public init(localAgentKind: PipiLocalAgentKind) {
        switch localAgentKind {
        case .claudeCode: self = .claudeCode
        case .codex: self = .codex
        case .opencode: self = .opencode
        }
    }
}

public struct PipiIsolatedCLIOverlay: Sendable, Equatable {
    public let cli: PipiReverseInjectedCLITarget
    public let overlayDir: URL
    public let configFilesWritten: [URL]
    public let environment: [String: String]
    public let gatewayBaseURL: String
    public let modelId: String
    public let untouchedGlobalHomes: [String]
}

// MARK: - 2. Isolated CLI Environment Overlay Manager (Zero Global Home Pollution)

public struct PipiCLIGatewayOverlayManager: Sendable {
    public static func prepareOverlay(
        dataRootURL: URL,
        cli: PipiReverseInjectedCLITarget,
        profileId: String = "default",
        gatewayOrigin: String,
        gatewayToken: String,
        modelId: String,
        contextWindow: Int = 65_536
    ) throws -> PipiIsolatedCLIOverlay {
        let safeProfile = profileId.replacingOccurrences(
            of: "[^a-zA-Z0-9._-]",
            with: "_",
            options: .regularExpression
        )
        let overlayDir = dataRootURL
            .appendingPathComponent("cli-overlays", isDirectory: true)
            .appendingPathComponent(cli.rawValue, isDirectory: true)
            .appendingPathComponent(safeProfile, isDirectory: true)

        let fm = FileManager.default
        try fm.createDirectory(at: overlayDir, withIntermediateDirectories: true)
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: overlayDir.path)

        let origin = gatewayOrigin.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        var written: [URL] = []
        var env: [String: String] = [:]

        func writePrivate(_ url: URL, text: String) throws {
            try Data(text.utf8).write(to: url, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            written.append(url)
        }

        switch cli {
        case .claudeCode:
            let settingsURL = overlayDir.appendingPathComponent("settings.json")
            let settingsObj: [String: Any] = [
                "pipibotManagedOverlay": true,
                "env": [
                    "ANTHROPIC_BASE_URL": "\(origin)/anthropic",
                    "ANTHROPIC_AUTH_TOKEN": gatewayToken,
                    "ANTHROPIC_MODEL": modelId,
                    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: settingsObj, options: [.prettyPrinted, .sortedKeys])
            try writePrivate(settingsURL, text: String(decoding: data, as: UTF8.self) + "\n")
            env["CLAUDE_CONFIG_DIR"] = overlayDir.path
            env["ANTHROPIC_BASE_URL"] = "\(origin)/anthropic"
            env["ANTHROPIC_AUTH_TOKEN"] = gatewayToken
            env["ANTHROPIC_API_KEY"] = gatewayToken
            env["ANTHROPIC_MODEL"] = modelId
            env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"

        case .codex:
            let configURL = overlayDir.appendingPathComponent("config.toml")
            let toml = """
            # Auto-generated isolated Codex overlay by PiPiBot Local LLM Gateway.
            # User global ~/.codex/config.toml is never modified.
            model = "\(modelId)"
            model_provider = "pipibot_local_gateway"

            [model_providers.pipibot_local_gateway]
            name = "PiPiBot Local Gateway"
            base_url = "\(origin)/v1"
            env_key = "OPENAI_API_KEY"
            wire_api = "chat"
            """
            try writePrivate(configURL, text: toml + "\n")
            env["CODEX_HOME"] = overlayDir.path
            env["OPENAI_BASE_URL"] = "\(origin)/v1"
            env["OPENAI_API_KEY"] = gatewayToken
            env["OPENAI_MODEL"] = modelId

        case .pi:
            let modelsURL = overlayDir.appendingPathComponent("models.json")
            let modelsObj: [String: Any] = [
                "providers": [
                    "pipibot_gateway": [
                        "baseUrl": "\(origin)/v1",
                        "apiKey": gatewayToken,
                        "api": "openai-completions",
                        "models": [
                            [
                                "id": modelId,
                                "name": "\(modelId) (PiPiBot Local Gateway)",
                                "contextWindow": contextWindow,
                                "maxTokens": 8192
                            ]
                        ]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: modelsObj, options: [.prettyPrinted, .sortedKeys])
            try writePrivate(modelsURL, text: String(decoding: data, as: UTF8.self) + "\n")
            env["PI_CODING_AGENT_DIR"] = overlayDir.path
            env["OPENAI_BASE_URL"] = "\(origin)/v1"
            env["OPENAI_API_KEY"] = gatewayToken

        case .opencode:
            let configURL = overlayDir.appendingPathComponent("opencode.json")
            let configObj: [String: Any] = [
                "model": "pipibot_gateway/\(modelId)",
                "provider": [
                    "pipibot_gateway": [
                        "npm": "@ai-sdk/openai-compatible",
                        "options": [
                            "baseURL": "\(origin)/v1",
                            "apiKey": gatewayToken
                        ],
                        "models": [
                            modelId: ["name": modelId]
                        ]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: configObj, options: [.prettyPrinted, .sortedKeys])
            try writePrivate(configURL, text: String(decoding: data, as: UTF8.self) + "\n")
            env["OPENCODE_CONFIG_DIR"] = overlayDir.path
            env["OPENAI_BASE_URL"] = "\(origin)/v1"
            env["OPENAI_API_KEY"] = gatewayToken
        }

        return PipiIsolatedCLIOverlay(
            cli: cli,
            overlayDir: overlayDir,
            configFilesWritten: written,
            environment: env,
            gatewayBaseURL: cli == .claudeCode ? "\(origin)/anthropic" : "\(origin)/v1",
            modelId: modelId,
            untouchedGlobalHomes: ["~/.claude", "~/.claude.json", "~/.codex", "~/.pi", "~/.config/opencode"]
        )
    }
}

// MARK: - 3. Bidirectional OpenAI <-> Anthropic Protocol Translator

public struct PipiGatewayProtocolTranslator: Sendable {
    public static func flattenContent(_ raw: Any?) -> String {
        if let str = raw as? String { return str }
        if let blocks = raw as? [[String: Any]] {
            return blocks.compactMap { block in
                if let text = block["text"] as? String { return text }
                if let content = block["content"] as? String { return content }
                return nil
            }.joined(separator: "\n")
        }
        return ""
    }

    public static func anthropicToOpenAIRequest(_ body: [String: Any], resolvedModel: String) -> [String: Any] {
        var messages: [[String: Any]] = []
        let sys = flattenContent(body["system"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !sys.isEmpty {
            messages.append(["role": "system", "content": sys])
        }
        if let rawMsgs = body["messages"] as? [[String: Any]] {
            for msg in rawMsgs {
                let role = (msg["role"] as? String) ?? "user"
                messages.append(["role": role, "content": flattenContent(msg["content"])])
            }
        }
        var out: [String: Any] = [
            "model": resolvedModel,
            "messages": messages,
            "max_tokens": (body["max_tokens"] as? Int) ?? 2048,
            "stream": false
        ]
        if let temp = body["temperature"] as? Double {
            out["temperature"] = temp
        }
        return out
    }

    public static func openAIResponseToAnthropic(_ payload: [String: Any], fallbackModel: String) -> [String: Any] {
        let choices = (payload["choices"] as? [[String: Any]]) ?? []
        let first = choices.first ?? [:]
        let message = (first["message"] as? [String: Any]) ?? [:]
        let text = (message["content"] as? String) ?? ""
        let usage = (payload["usage"] as? [String: Any]) ?? [:]
        let finishReason = (first["finish_reason"] as? String) ?? "stop"

        return [
            "id": "msg_\((payload["id"] as? String) ?? UUID().uuidString.prefix(8).lowercased())",
            "type": "message",
            "role": "assistant",
            "model": (payload["model"] as? String) ?? fallbackModel,
            "content": [["type": "text", "text": text]],
            "stop_reason": finishReason == "length" ? "max_tokens" : "end_turn",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": (usage["prompt_tokens"] as? Int) ?? 0,
                "output_tokens": (usage["completion_tokens"] as? Int) ?? max(1, text.count / 4)
            ]
        ]
    }

    public static func openAIToAnthropicRequest(_ body: [String: Any], resolvedModel: String) -> [String: Any] {
        var systemParts: [String] = []
        var messages: [[String: Any]] = []
        if let rawMsgs = body["messages"] as? [[String: Any]] {
            for msg in rawMsgs {
                let role = (msg["role"] as? String) ?? "user"
                let text = flattenContent(msg["content"])
                if role == "system" {
                    if !text.isEmpty { systemParts.append(text) }
                } else {
                    messages.append(["role": role == "assistant" ? "assistant" : "user", "content": text])
                }
            }
        }
        var out: [String: Any] = [
            "model": resolvedModel,
            "messages": messages,
            "max_tokens": (body["max_tokens"] as? Int) ?? 2048,
            "stream": false
        ]
        if !systemParts.isEmpty {
            out["system"] = systemParts.joined(separator: "\n\n")
        }
        if let temp = body["temperature"] as? Double {
            out["temperature"] = temp
        }
        return out
    }

    public static func anthropicResponseToOpenAI(_ payload: [String: Any], fallbackModel: String) -> [String: Any] {
        let text = flattenContent(payload["content"])
        let usage = (payload["usage"] as? [String: Any]) ?? [:]
        let inputTokens = (usage["input_tokens"] as? Int) ?? 0
        let outputTokens = (usage["output_tokens"] as? Int) ?? max(1, text.count / 4)
        let stopReason = (payload["stop_reason"] as? String) ?? "end_turn"

        return [
            "id": "chatcmpl_\((payload["id"] as? String) ?? UUID().uuidString.prefix(8).lowercased())",
            "object": "chat.completion",
            "created": Int(Date().timeIntervalSince1970),
            "model": (payload["model"] as? String) ?? fallbackModel,
            "choices": [
                [
                    "index": 0,
                    "message": ["role": "assistant", "content": text],
                    "finish_reason": stopReason == "max_tokens" ? "length" : "stop"
                ]
            ],
            "usage": [
                "prompt_tokens": inputTokens,
                "completion_tokens": outputTokens,
                "total_tokens": inputTokens + outputTokens
            ]
        ]
    }
}

// MARK: - 4. Native Loopback HTTP Gateway (`127.0.0.1` via Network.framework)

public actor PipiLocalLLMGateway {
    public typealias UpstreamTransport = @Sendable (URLRequest) async throws -> (Data, Int)

    private var upstream: PipiGatewayUpstreamTarget
    public nonisolated let token: String
    private let transport: UpstreamTransport?
    private var requestsServedCount: Int = 0
    private var boundPort: UInt16 = 0
    #if canImport(Network)
    private var listener: NWListener?
    private let listenerQueue = DispatchQueue(label: "app.pipibot.local-gateway", qos: .userInitiated)
    #endif

    public init(
        upstream: PipiGatewayUpstreamTarget,
        gatewayToken: String? = nil,
        transport: UpstreamTransport? = nil
    ) {
        self.upstream = upstream
        self.token = gatewayToken ?? "pipi_gw_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        self.transport = transport
    }

    public func currentStatus() -> PipiGatewayRuntimeStatus {
        guard boundPort > 0 else { return .stopped }
        return PipiGatewayRuntimeStatus(
            isRunning: true,
            origin: "http://127.0.0.1:\(boundPort)",
            port: Int(boundPort),
            modelId: upstream.modelId,
            sourceMode: upstream.sourceMode,
            requestsServed: requestsServedCount
        )
    }

    public func updateUpstream(_ target: PipiGatewayUpstreamTarget) {
        self.upstream = target
    }

    /// Starts strictly on IPv4 loopback `127.0.0.1`. Passing `port: 0` selects an OS-assigned ephemeral port.
    public func start(port: UInt16 = 0) async throws -> PipiGatewayRuntimeStatus {
        #if canImport(Network)
        if listener != nil, boundPort > 0 {
            return currentStatus()
        }

        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: port == 0 ? .any : (NWEndpoint.Port(rawValue: port) ?? .any)
        )
        let nwListener = try NWListener(using: params)

        let assignedPort: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let resumed = LockedFlag()
            nwListener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumed.markOnce() {
                        continuation.resume(returning: nwListener.port?.rawValue ?? port)
                    }
                case .failed(let error):
                    if resumed.markOnce() {
                        continuation.resume(throwing: error)
                    }
                case .cancelled:
                    if resumed.markOnce() {
                        continuation.resume(throwing: CancellationError())
                    }
                default:
                    break
                }
            }
            nwListener.newConnectionHandler = { [weak self] connection in
                guard let self else {
                    connection.cancel()
                    return
                }
                Task {
                    await self.accept(connection: connection)
                }
            }
            nwListener.start(queue: listenerQueue)
        }

        self.listener = nwListener
        self.boundPort = assignedPort
        return currentStatus()
        #else
        throw PipiInferenceError.unsupportedPlatform
        #endif
    }

    public func stop() {
        #if canImport(Network)
        listener?.cancel()
        listener = nil
        #endif
        boundPort = 0
    }

    public func prepareOverlay(
        dataRootURL: URL,
        cli: PipiReverseInjectedCLITarget,
        profileId: String = "default"
    ) throws -> PipiIsolatedCLIOverlay {
        guard boundPort > 0 else {
            throw PipiInferenceError.invalidEndpoint("Local gateway is not started")
        }
        return try PipiCLIGatewayOverlayManager.prepareOverlay(
            dataRootURL: dataRootURL,
            cli: cli,
            profileId: profileId,
            gatewayOrigin: "http://127.0.0.1:\(boundPort)",
            gatewayToken: token,
            modelId: upstream.modelId,
            contextWindow: upstream.contextWindow
        )
    }

    #if canImport(Network)
    private func accept(connection: NWConnection) {
        connection.start(queue: listenerQueue)
        readHTTPRequest(from: connection, buffer: Data()) { [weak self] requestData in
            guard let self else {
                connection.cancel()
                return
            }
            Task {
                let responseBytes = await self.processRawHTTPRequest(requestData)
                connection.send(content: responseBytes, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private nonisolated func readHTTPRequest(
        from connection: NWConnection,
        buffer: Data,
        completion: @escaping @Sendable (Data) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
            var next = buffer
            if let data, !data.isEmpty {
                next.append(data)
            }
            if Self.isCompleteHTTPRequest(next) || isComplete || error != nil || next.count > 2_097_152 {
                completion(next)
            } else {
                self.readHTTPRequest(from: connection, buffer: next, completion: completion)
            }
        }
    }

    private nonisolated static func isCompleteHTTPRequest(_ data: Data) -> Bool {
        let sep = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: sep) else { return false }
        let headerText = String(decoding: data[..<headerRange.lowerBound], as: UTF8.self)
        var contentLength = 0
        for line in headerText.split(separator: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let raw = lower.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                contentLength = Int(raw) ?? 0
            }
        }
        let bodyBytes = data.count - headerRange.upperBound
        return bodyBytes >= contentLength
    }
    #endif

    // MARK: - HTTP Request Router (Directly Unit-Testable)

    public func processRawHTTPRequest(_ raw: Data) async -> Data {
        let sep = Data("\r\n\r\n".utf8)
        guard let headerRange = raw.range(of: sep) else {
            return httpResponse(status: 400, reason: "Bad Request", contentType: "application/json", body: Data("{\"error\":{\"code\":\"BAD_REQUEST\"}}".utf8))
        }
        let headerStr = String(decoding: raw[..<headerRange.lowerBound], as: UTF8.self)
        let lines = headerStr.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return httpResponse(status: 400, reason: "Bad Request", contentType: "application/json", body: Data("{\"error\":{\"code\":\"BAD_REQUEST\"}}".utf8))
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return httpResponse(status: 400, reason: "Bad Request", contentType: "application/json", body: Data("{\"error\":{\"code\":\"BAD_REQUEST\"}}".utf8))
        }
        let method = String(parts[0]).uppercased()
        let path = String(parts[1]).components(separatedBy: "?").first ?? "/"

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let val = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                headers[key] = val
            }
        }

        if method == "GET" && path == "/healthz" {
            let body: [String: Any] = [
                "ok": true,
                "sourceMode": upstream.sourceMode.rawValue,
                "dialect": upstream.dialect.rawValue,
                "modelId": upstream.modelId,
                "requestsServed": requestsServedCount
            ]
            return jsonResponse(status: 200, object: body)
        }

        guard isAuthorized(headers: headers) else {
            return jsonResponse(status: 401, object: ["error": ["code": "UNAUTHORIZED", "message": "Invalid local gateway token."]])
        }

        if method == "GET" && (path == "/v1/models" || path == "/anthropic/v1/models") {
            requestsServedCount += 1
            return jsonResponse(status: 200, object: [
                "object": "list",
                "data": [[
                    "id": upstream.modelId,
                    "object": "model",
                    "owned_by": "pipibot:\(upstream.sourceMode.rawValue)",
                    "context_window": upstream.contextWindow
                ]]
            ])
        }

        let bodyData = Data(raw[headerRange.upperBound...])
        let bodyJSON = (try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]) ?? [:]

        do {
            if method == "POST" && path == "/v1/chat/completions" {
                requestsServedCount += 1
                let stream = (bodyJSON["stream"] as? Bool) ?? false
                let openaiObj: [String: Any]
                if upstream.dialect == .openai {
                    openaiObj = try await forwardOpenAI(bodyJSON)
                } else {
                    let antReq = PipiGatewayProtocolTranslator.openAIToAnthropicRequest(bodyJSON, resolvedModel: upstream.modelId)
                    let antResp = try await forwardAnthropic(antReq)
                    openaiObj = PipiGatewayProtocolTranslator.anthropicResponseToOpenAI(antResp, fallbackModel: upstream.modelId)
                }
                if stream {
                    return openAISSEResponse(from: openaiObj)
                }
                return jsonResponse(status: 200, object: openaiObj)
            }

            if method == "POST" && (path == "/v1/messages" || path == "/anthropic/v1/messages") {
                requestsServedCount += 1
                let stream = (bodyJSON["stream"] as? Bool) ?? false
                let antObj: [String: Any]
                if upstream.dialect == .anthropic {
                    antObj = try await forwardAnthropic(bodyJSON)
                } else {
                    let oaiReq = PipiGatewayProtocolTranslator.anthropicToOpenAIRequest(bodyJSON, resolvedModel: upstream.modelId)
                    let oaiResp = try await forwardOpenAI(oaiReq)
                    antObj = PipiGatewayProtocolTranslator.openAIResponseToAnthropic(oaiResp, fallbackModel: upstream.modelId)
                }
                if stream {
                    return anthropicSSEResponse(from: antObj)
                }
                return jsonResponse(status: 200, object: antObj)
            }

            return jsonResponse(status: 404, object: ["error": ["code": "NOT_FOUND", "message": "Unsupported route \(path)"]])
        } catch {
            return jsonResponse(status: 502, object: ["error": ["code": "UPSTREAM_ERROR", "message": error.localizedDescription]])
        }
    }

    private func isAuthorized(headers: [String: String]) -> Bool {
        if let auth = headers["authorization"], auth.hasPrefix("Bearer ") {
            let candidate = String(auth.dropFirst("Bearer ".count)).trimmingCharacters(in: .whitespaces)
            if constantTimeEquals(candidate, token) { return true }
        }
        if let key = headers["x-api-key"]?.trimmingCharacters(in: .whitespaces), !key.isEmpty {
            if constantTimeEquals(key, token) { return true }
        }
        return false
    }

    private func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let ba = Array(a.utf8)
        let bb = Array(b.utf8)
        guard ba.count == bb.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<ba.count {
            diff |= ba[i] ^ bb[i]
        }
        return diff == 0
    }

    private func forwardOpenAI(_ body: [String: Any]) async throws -> [String: Any] {
        guard let url = PipiInferenceEngine.buildOpenAIChatCompletionsURL(baseURL: upstream.baseURL) else {
            throw PipiInferenceError.invalidEndpoint(upstream.baseURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = upstream.apiKey, !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        var outBody = body
        outBody["model"] = upstream.modelId
        outBody["stream"] = false
        req.httpBody = try JSONSerialization.data(withJSONObject: outBody)

        let (data, code) = try await sendUpstream(req)
        guard (200...299).contains(code) else {
            throw PipiInferenceError.httpError(code, String(decoding: data, as: UTF8.self))
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func forwardAnthropic(_ body: [String: Any]) async throws -> [String: Any] {
        guard let url = PipiInferenceEngine.buildAnthropicMessagesURL(baseURL: upstream.baseURL) else {
            throw PipiInferenceError.invalidEndpoint(upstream.baseURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if let key = upstream.apiKey, !key.isEmpty {
            req.setValue(key, forHTTPHeaderField: "x-api-key")
        }
        var outBody = body
        outBody["model"] = upstream.modelId
        outBody["stream"] = false
        req.httpBody = try JSONSerialization.data(withJSONObject: outBody)

        let (data, code) = try await sendUpstream(req)
        guard (200...299).contains(code) else {
            throw PipiInferenceError.httpError(code, String(decoding: data, as: UTF8.self))
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func sendUpstream(_ request: URLRequest) async throws -> (Data, Int) {
        if let transport {
            return try await transport(request)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func jsonResponse(status: Int, object: [String: Any]) -> Data {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        let reason = status == 200 ? "OK" : (status == 401 ? "Unauthorized" : (status == 404 ? "Not Found" : "Error"))
        return httpResponse(status: status, reason: reason, contentType: "application/json", body: data)
    }

    private func openAISSEResponse(from openaiObj: [String: Any]) -> Data {
        let choices = (openaiObj["choices"] as? [[String: Any]]) ?? []
        let msg = (choices.first?["message"] as? [String: Any]) ?? [:]
        let text = (msg["content"] as? String) ?? ""
        let id = (openaiObj["id"] as? String) ?? "chatcmpl_local"
        let model = (openaiObj["model"] as? String) ?? upstream.modelId
        let chunk1: [String: Any] = [
            "id": id,
            "object": "chat.completion.chunk",
            "model": model,
            "choices": [["index": 0, "delta": ["role": "assistant", "content": text], "finish_reason": NSNull()]]
        ]
        let chunk2: [String: Any] = [
            "id": id,
            "object": "chat.completion.chunk",
            "model": model,
            "choices": [["index": 0, "delta": [:], "finish_reason": "stop"]]
        ]
        let s1 = String(decoding: (try? JSONSerialization.data(withJSONObject: chunk1)) ?? Data(), as: UTF8.self)
        let s2 = String(decoding: (try? JSONSerialization.data(withJSONObject: chunk2)) ?? Data(), as: UTF8.self)
        let sse = "data: \(s1)\n\ndata: \(s2)\n\ndata: [DONE]\n\n"
        return httpResponse(status: 200, reason: "OK", contentType: "text/event-stream; charset=utf-8", body: Data(sse.utf8))
    }

    private func anthropicSSEResponse(from antObj: [String: Any]) -> Data {
        let text = PipiGatewayProtocolTranslator.flattenContent(antObj["content"])
        let msgId = (antObj["id"] as? String) ?? "msg_local"
        let model = (antObj["model"] as? String) ?? upstream.modelId

        func encode(_ obj: [String: Any]) -> String {
            String(decoding: (try? JSONSerialization.data(withJSONObject: obj)) ?? Data(), as: UTF8.self)
        }
        let startEvt = encode(["type": "message_start", "message": ["id": msgId, "type": "message", "role": "assistant", "model": model, "content": []]])
        let blkStart = encode(["type": "content_block_start", "index": 0, "content_block": ["type": "text", "text": ""]])
        let blkDelta = encode(["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": text]])
        let blkStop = encode(["type": "content_block_stop", "index": 0])
        let msgDelta = encode(["type": "message_delta", "delta": ["stop_reason": "end_turn", "stop_sequence": NSNull()]])
        let msgStop = encode(["type": "message_stop"])

        let sse = """
        event: message_start
        data: \(startEvt)

        event: content_block_start
        data: \(blkStart)

        event: content_block_delta
        data: \(blkDelta)

        event: content_block_stop
        data: \(blkStop)

        event: message_delta
        data: \(msgDelta)

        event: message_stop
        data: \(msgStop)

        """
        return httpResponse(status: 200, reason: "OK", contentType: "text/event-stream; charset=utf-8", body: Data(sse.utf8))
    }

    private func httpResponse(status: Int, reason: String, contentType: String, body: Data) -> Data {
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var out = Data(header.utf8)
        out.append(body)
        return out
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func markOnce() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
