import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct PipiInferenceResult: Sendable, Equatable {
    public let text: String
    public let engineLabel: String
    public let cliSessionId: String?
    public let steps: [PipiStepEvent]
    public let planItems: [PipiPlanItem]
    public let fileChanges: [PipiFileChange]
    public let summaryInfo: PipiSessionSummaryInfo?

    public init(
        text: String,
        engineLabel: String,
        cliSessionId: String? = nil,
        steps: [PipiStepEvent] = [],
        planItems: [PipiPlanItem] = [],
        fileChanges: [PipiFileChange] = [],
        summaryInfo: PipiSessionSummaryInfo? = nil
    ) {
        self.text = text
        self.engineLabel = engineLabel
        self.cliSessionId = cliSessionId
        self.steps = steps
        self.planItems = planItems
        self.fileChanges = fileChanges
        self.summaryInfo = summaryInfo
    }
}

public enum PipiInferenceError: LocalizedError, Sendable {
    case invalidEndpoint(String)
    case missingApiKey(String)
    case httpError(Int, String)
    case emptyResponse
    case localAgentNotFound(String)
    case localAgentFailed(Int32, String)
    case unsupportedPlatform

    public func localizedMessage(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .invalidEndpoint(let url):
            return lang == .zhHans ? "接口地址无效：\(url)" : "Invalid endpoint URL: \(url)"
        case .missingApiKey(let name):
            return lang == .zhHans ? "请先为 \(name) 填写 API Key" : "API key is required for \(name)"
        case .httpError(let code, let detail):
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            let short = trimmed.count > 240 ? String(trimmed.prefix(240)) + "…" : trimmed
            return lang == .zhHans ? "模型接口返回错误 (HTTP \(code))：\(short)" : "Model API error (HTTP \(code)): \(short)"
        case .emptyResponse:
            return lang == .zhHans ? "模型未返回有效内容，请检查模型名称或稍后重试。" : "The model returned an empty response. Please check the model name and try again."
        case .localAgentNotFound(let name):
            return lang == .zhHans ? "未在本机找到 \(name) 可执行文件，请先安装并在终端完成登录。" : "Could not find \(name) binary on this Mac. Install it and sign in via Terminal first."
        case .localAgentFailed(let code, let stderr):
            let trimmed = PipiInferenceEngine.stripAnsiEscapeCodes(stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            let short = trimmed.count > 280 ? String(trimmed.prefix(280)) + "…" : trimmed
            return lang == .zhHans ? "本地 Agent 执行失败 (exit \(code))：\(short)" : "Local agent exited with code \(code): \(short)"
        case .unsupportedPlatform:
            return lang == .zhHans ? "本地命令行 Agent 仅支持在 macOS 上直接运行，iOS 端请使用云端 LLM 或开启多端同步。" : "Local CLI agents run on macOS. On iOS, connect an LLM API or enable Companion Sync."
        }
    }

    public var errorDescription: String? {
        localizedMessage(PipiAppLanguage.system.resolved)
    }
}

public struct PipiInferenceEngine: Sendable {

    // MARK: - Test LLM Connection

    public static func testLLMConnection(
        config: PipiLLMProviderConfig,
        language: PipiResolvedLanguage
    ) async -> (ok: Bool, message: String) {
        if config.kind.requiresApiKey && config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (false, PipiInferenceError.missingApiKey(config.name).localizedMessage(language))
        }

        if config.kind == .ollama {
            let trimmed = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            guard let url = URL(string: "\(trimmed)/api/tags") else {
                return (false, PipiInferenceError.invalidEndpoint(config.baseURL).localizedMessage(language))
            }
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    let countHint = parseOllamaModelCount(data)
                    return (
                        true,
                        language == .zhHans
                            ? "Ollama 本地服务连接成功（检测到 \(countHint) 个模型）"
                            : "Connected to local Ollama (\(countHint) models available)"
                    )
                }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                return (false, PipiInferenceError.httpError(code, "Ollama /api/tags").localizedMessage(language))
            } catch {
                return (false, error.localizedDescription)
            }
        }

        do {
            let testMessages = [
                PipiChatMessage(role: .user, content: "Reply with OK")
            ]
            let result = try await invokeLLM(
                config: config,
                systemPrompt: "Respond briefly with OK.",
                history: testMessages,
                maxTokens: 24,
                onDelta: nil
            )
            let preview = result.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32)
            return (
                true,
                language == .zhHans
                    ? "连接成功（\(config.modelId)）：\(preview)"
                    : "Connected (\(config.modelId)): \(preview)"
            )
        } catch let err as PipiInferenceError {
            return (false, err.localizedMessage(language))
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - Invoke LLM Provider (Supports Real Token-by-Token SSE Streaming)

    public static func invokeLLM(
        config: PipiLLMProviderConfig,
        systemPrompt: String,
        history: [PipiChatMessage],
        maxTokens: Int? = nil,
        onDelta: (@Sendable (String) -> Void)? = nil
    ) async throws -> PipiInferenceResult {
        if config.kind.requiresApiKey && config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PipiInferenceError.missingApiKey(config.name)
        }

        let trimmedHistory = Array(history.suffix(24))
        let text: String
        switch config.kind {
        case .openai, .deepseek, .openrouter, .customOpenAI:
            if let onDelta {
                text = try await streamOpenAICompatible(
                    config: config,
                    systemPrompt: systemPrompt,
                    history: trimmedHistory,
                    maxTokens: maxTokens,
                    onDelta: onDelta
                )
            } else {
                text = try await callOpenAICompatible(
                    config: config,
                    systemPrompt: systemPrompt,
                    history: trimmedHistory,
                    maxTokens: maxTokens
                )
            }
        case .anthropic:
            if let onDelta {
                text = try await streamAnthropic(
                    config: config,
                    systemPrompt: systemPrompt,
                    history: trimmedHistory,
                    maxTokens: maxTokens ?? 4096,
                    onDelta: onDelta
                )
            } else {
                text = try await callAnthropic(
                    config: config,
                    systemPrompt: systemPrompt,
                    history: trimmedHistory,
                    maxTokens: maxTokens ?? 2048
                )
            }
        case .gemini:
            if let onDelta {
                text = try await streamGemini(
                    config: config,
                    systemPrompt: systemPrompt,
                    history: trimmedHistory,
                    maxTokens: maxTokens,
                    onDelta: onDelta
                )
            } else {
                text = try await callGemini(
                    config: config,
                    systemPrompt: systemPrompt,
                    history: trimmedHistory,
                    maxTokens: maxTokens
                )
            }
        case .ollama:
            if let onDelta {
                text = try await streamOllama(
                    config: config,
                    systemPrompt: systemPrompt,
                    history: trimmedHistory,
                    onDelta: onDelta
                )
            } else {
                text = try await callOllama(
                    config: config,
                    systemPrompt: systemPrompt,
                    history: trimmedHistory
                )
            }
        }

        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            throw PipiInferenceError.emptyResponse
        }
        return PipiInferenceResult(text: clean, engineLabel: "\(config.name) · \(config.modelId)")
    }

    // MARK: - Invoke Local CLI Agent (macOS — Structured JSONL Streaming + Resume + Permissions)

    public static func localAgentArguments(for kind: PipiLocalAgentKind, prompt: String) -> [String] {
        localAgentArguments(for: kind, prompt: prompt, permissionTier: .ask, cliSessionId: nil)
    }

    public static func localAgentArguments(
        for kind: PipiLocalAgentKind,
        prompt: String,
        permissionTier: PipiPermissionTier = .ask,
        cliSessionId: String? = nil
    ) -> [String] {
        let resumeId = cliSessionId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasResume = (resumeId?.isEmpty == false)

        switch kind {
        case .claudeCode:
            let mode: String
            switch permissionTier {
            case .readOnly: mode = "plan"
            case .ask: mode = "default"
            case .autoEdit: mode = "acceptEdits"
            }
            var args = [
                "-p", prompt,
                "--output-format", "stream-json",
                "--verbose",
                "--permission-mode", mode
            ]
            if hasResume, let resumeId {
                args.append(contentsOf: ["--resume", resumeId])
            }
            return args

        case .codex:
            let sandboxMode: String
            switch permissionTier {
            case .readOnly, .ask: sandboxMode = "read-only"
            case .autoEdit: sandboxMode = "workspace-write"
            }
            if hasResume, let resumeId {
                return [
                    "exec", "resume",
                    "--json",
                    "--skip-git-repo-check",
                    "-c", "sandbox_mode=\"\(sandboxMode)\"",
                    resumeId,
                    prompt
                ]
            } else {
                // `--skip-git-repo-check` lets Codex run smoothly in personal non-git directories (e.g. `~`).
                return [
                    "exec",
                    "--json",
                    "--skip-git-repo-check",
                    "--color", "never",
                    "--sandbox", sandboxMode,
                    prompt
                ]
            }

        case .opencode:
            return ["run", prompt]
        }
    }

    private final class CLIEventAccumulator: @unchecked Sendable {
        private let lock = NSLock()
        private var parser: PipiCLIAgentParser
        private var streamedText = ""
        private var finalTextOverride: String?
        private var sessionId: String?
        private var steps: [PipiStepEvent] = []
        private var planItems: [PipiPlanItem] = []
        private var fileChanges: [PipiFileChange] = []
        private var summaryInfo: PipiSessionSummaryInfo?

        init(kind: PipiLocalAgentKind) {
            self.parser = PipiCLIAgentParser(kind: kind)
        }

        func ingest(
            chunk: String,
            onDelta: (@Sendable (String) -> Void)?,
            onEvent: (@Sendable (PipiParsedCLIEvent) -> Void)?
        ) {
            let events: [PipiParsedCLIEvent]
            lock.lock()
            events = parser.feedChunk(chunk)
            apply(events)
            lock.unlock()
            dispatch(events, onDelta: onDelta, onEvent: onEvent)
        }

        func finish(
            onDelta: (@Sendable (String) -> Void)?,
            onEvent: (@Sendable (PipiParsedCLIEvent) -> Void)?
        ) {
            let events: [PipiParsedCLIEvent]
            lock.lock()
            events = parser.finish()
            apply(events)
            lock.unlock()
            dispatch(events, onDelta: onDelta, onEvent: onEvent)
        }

        private func apply(_ events: [PipiParsedCLIEvent]) {
            for ev in events {
                switch ev {
                case .sessionId(let sid):
                    sessionId = sid
                case .textDelta(let delta):
                    streamedText += delta
                case .finalText(let text):
                    finalTextOverride = text
                case .planUpdated(let items):
                    planItems = items
                case .stepStarted(let step):
                    if let idx = steps.firstIndex(where: { $0.id == step.id }) {
                        steps[idx] = step
                    } else {
                        steps.append(step)
                    }
                case .stepFinished(let id, let status, let detail, let durationMs, let exitCode):
                    if let idx = steps.firstIndex(where: { $0.id == id }) {
                        steps[idx].status = status
                        if let detail, !detail.isEmpty { steps[idx].detail = detail }
                        if let durationMs { steps[idx].durationMs = durationMs }
                        if let exitCode { steps[idx].exitCode = exitCode }
                    }
                case .fileChanged(let change):
                    if let idx = fileChanges.firstIndex(where: { $0.path == change.path }) {
                        fileChanges[idx] = change
                    } else {
                        fileChanges.append(change)
                    }
                case .summary(let info):
                    summaryInfo = info
                }
            }
        }

        private func dispatch(
            _ events: [PipiParsedCLIEvent],
            onDelta: (@Sendable (String) -> Void)?,
            onEvent: (@Sendable (PipiParsedCLIEvent) -> Void)?
        ) {
            for ev in events {
                if case .textDelta(let delta) = ev {
                    onDelta?(delta)
                }
                onEvent?(ev)
            }
        }

        func buildResult(rawFallbackOutput: String, engineLabel: String) -> PipiInferenceResult? {
            lock.lock()
            defer { lock.unlock() }
            let trimmedStreamed = streamedText.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedFinal = finalTextOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let resolvedText: String
            if !trimmedStreamed.isEmpty {
                resolvedText = trimmedStreamed
            } else if !trimmedFinal.isEmpty {
                resolvedText = trimmedFinal
            } else {
                resolvedText = rawFallbackOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if resolvedText.isEmpty && steps.isEmpty && planItems.isEmpty && fileChanges.isEmpty {
                return nil
            }
            var finalSummary = summaryInfo
            if var s = finalSummary, s.changedFilesCount == 0 && !fileChanges.isEmpty {
                s.changedFilesCount = fileChanges.count
                finalSummary = s
            }
            return PipiInferenceResult(
                text: resolvedText,
                engineLabel: engineLabel,
                cliSessionId: sessionId,
                steps: steps,
                planItems: planItems,
                fileChanges: fileChanges,
                summaryInfo: finalSummary
            )
        }
    }

    public static func invokeLocalAgent(
        kind: PipiLocalAgentKind,
        systemPrompt: String,
        history: [PipiChatMessage],
        workingDirectory: String,
        permissionTier: PipiPermissionTier = .ask,
        cliSessionId: String? = nil,
        extraEnvironment: [String: String] = [:],
        onDelta: (@Sendable (String) -> Void)? = nil,
        onEvent: (@Sendable (PipiParsedCLIEvent) -> Void)? = nil
    ) async throws -> PipiInferenceResult {
        #if os(macOS)
        guard let binaryPath = PipiNativeMacRuntime.findExecutable(kind.binaryName) else {
            throw PipiInferenceError.localAgentNotFound(kind.displayName)
        }

        let isResuming = (cliSessionId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) && kind != .opencode
        let compiledPrompt = buildLocalAgentPrompt(
            systemPrompt: systemPrompt,
            history: history,
            isResuming: isResuming
        )
        let args = localAgentArguments(
            for: kind,
            prompt: compiledPrompt,
            permissionTier: permissionTier,
            cliSessionId: cliSessionId
        )

        let cwd = FileManager.default.fileExists(atPath: workingDirectory)
            ? workingDirectory
            : NSHomeDirectory()

        let accumulator = CLIEventAccumulator(kind: kind)
        let output = try await runSubprocessStreaming(
            executablePath: binaryPath,
            arguments: args,
            workingDirectory: cwd,
            extraEnvironment: extraEnvironment,
            onDelta: { chunk in
                accumulator.ingest(chunk: chunk, onDelta: onDelta, onEvent: onEvent)
            }
        )
        accumulator.finish(onDelta: onDelta, onEvent: onEvent)

        let fallback = stripAnsiEscapeCodes(output).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let result = accumulator.buildResult(rawFallbackOutput: fallback, engineLabel: kind.displayName) else {
            throw PipiInferenceError.emptyResponse
        }
        return result
        #else
        throw PipiInferenceError.unsupportedPlatform
        #endif
    }

    // MARK: - URL Builders & Stream Parsers (Unit-Testable)

    public static func buildOpenAIChatCompletionsURL(baseURL: String) -> URL? {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if base.hasSuffix("/chat/completions") {
            return URL(string: base)
        }
        return URL(string: "\(base)/chat/completions")
    }

    public static func buildAnthropicMessagesURL(baseURL: String) -> URL? {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if base.hasSuffix("/messages") {
            return URL(string: base)
        }
        if base.hasSuffix("/v1") {
            return URL(string: "\(base)/messages")
        }
        return URL(string: "\(base)/v1/messages")
    }

    public static func buildGeminiGenerateURL(
        baseURL: String,
        modelId: String,
        apiKey: String,
        streaming: Bool = false
    ) -> URL? {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let cleanModel = modelId.hasPrefix("models/") ? String(modelId.dropFirst("models/".count)) : modelId
        let method = streaming ? "streamGenerateContent" : "generateContent"
        var comps = URLComponents(string: "\(base)/models/\(cleanModel):\(method)")
        var items = [URLQueryItem(name: "key", value: apiKey)]
        if streaming {
            items.append(URLQueryItem(name: "alt", value: "sse"))
        }
        comps?.queryItems = items
        return comps?.url
    }

    public static func parseOpenAISSEDataLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        if payload == "[DONE]" || payload.isEmpty { return nil }
        guard let data = payload.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let first = choices.first else {
            return nil
        }
        if let delta = first["delta"] as? [String: Any], let content = delta["content"] as? String {
            return content
        }
        if let msg = first["message"] as? [String: Any], let content = msg["content"] as? String {
            return content
        }
        return nil
    }

    public static func parseAnthropicSSEDataLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = payload.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["type"] as? String) == "content_block_delta",
              let delta = root["delta"] as? [String: Any],
              (delta["type"] as? String) == "text_delta",
              let text = delta["text"] as? String else {
            return nil
        }
        return text
    }

    public static func parseGeminiSSEDataLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = payload.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            return nil
        }
        let chunk = parts.compactMap { $0["text"] as? String }.joined()
        return chunk.isEmpty ? nil : chunk
    }

    public static func stripAnsiEscapeCodes(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\u{001B}\\[[0-9;]*[a-zA-Z]") else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    // MARK: - Vision Attachment Encoding & Provider Payload Builders (Size-Capped)

    public static let defaultMaxImageBytes: Int = 4 * 1024 * 1024
    public static let maxImagesPerMessage: Int = 4

    public static func encodeImageAttachmentBase64(
        _ attachment: PipiChatAttachment,
        maxBytes: Int = defaultMaxImageBytes
    ) -> (mimeType: String, base64: String)? {
        guard attachment.isImage, maxBytes > 0 else { return nil }
        let fileURL = URL(fileURLWithPath: attachment.path)
        guard let rawData = try? Data(contentsOf: fileURL), !rawData.isEmpty else { return nil }

        let ext = (attachment.name as NSString).pathExtension.lowercased()
        let directMime: String?
        switch ext {
        case "png": directMime = "image/png"
        case "jpg", "jpeg": directMime = "image/jpeg"
        case "webp": directMime = "image/webp"
        case "gif": directMime = "image/gif"
        case "heic": directMime = nil // Convert HEIC to JPEG for broad provider compatibility
        default: directMime = nil
        }

        if let directMime, rawData.count <= maxBytes {
            return (directMime, rawData.base64EncodedString())
        }

        // Downscale / recompress as JPEG via ImageIO to satisfy maxBytes or HEIC conversion
        guard let source = CGImageSourceCreateWithData(rawData as CFData, nil) else {
            return nil
        }
        let maxDims = [2048, 1536, 1024, 768]
        let qualities: [Double] = [0.85, 0.70, 0.50]

        for dim in maxDims {
            let thumbOpts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: dim
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOpts as CFDictionary) else {
                continue
            }
            for q in qualities {
                let outData = NSMutableData()
                guard let dest = CGImageDestinationCreateWithData(outData, UTType.jpeg.identifier as CFString, 1, nil) else {
                    continue
                }
                let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: q]
                CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
                if CGImageDestinationFinalize(dest), outData.length > 0, outData.length <= maxBytes {
                    return ("image/jpeg", (outData as Data).base64EncodedString())
                }
            }
        }
        return nil
    }

    private static func encodedImages(
        for msg: PipiChatMessage,
        maxImageBytes: Int
    ) -> [(mimeType: String, base64: String)] {
        guard msg.role == .user, let attachments = msg.attachments else { return [] }
        return attachments
            .filter(\.isImage)
            .prefix(maxImagesPerMessage)
            .compactMap { encodeImageAttachmentBase64($0, maxBytes: maxImageBytes) }
    }

    public static func buildOpenAIChatMessages(
        systemPrompt: String,
        history: [PipiChatMessage],
        maxImageBytes: Int = defaultMaxImageBytes
    ) -> [[String: Any]] {
        var wireMessages: [[String: Any]] = []
        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            wireMessages.append(["role": "system", "content": systemPrompt])
        }
        for msg in history where msg.role != .system && !msg.isError {
            let role = msg.role == .user ? "user" : "assistant"
            let images = encodedImages(for: msg, maxImageBytes: maxImageBytes)
            if images.isEmpty {
                wireMessages.append(["role": role, "content": msg.content])
            } else {
                var parts: [[String: Any]] = [["type": "text", "text": msg.content]]
                for img in images {
                    parts.append([
                        "type": "image_url",
                        "image_url": ["url": "data:\(img.mimeType);base64,\(img.base64)"]
                    ])
                }
                wireMessages.append(["role": role, "content": parts])
            }
        }
        return wireMessages
    }

    public static func buildAnthropicMessages(
        history: [PipiChatMessage],
        maxImageBytes: Int = defaultMaxImageBytes
    ) -> [[String: Any]] {
        var wireMessages: [[String: Any]] = []
        for msg in history where msg.role != .system && !msg.isError {
            let role = msg.role == .user ? "user" : "assistant"
            let images = encodedImages(for: msg, maxImageBytes: maxImageBytes)
            if images.isEmpty {
                wireMessages.append(["role": role, "content": msg.content])
            } else {
                var blocks: [[String: Any]] = images.map { img in
                    [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": img.mimeType,
                            "data": img.base64
                        ]
                    ]
                }
                blocks.append(["type": "text", "text": msg.content])
                wireMessages.append(["role": role, "content": blocks])
            }
        }
        return wireMessages
    }

    public static func buildGeminiContents(
        history: [PipiChatMessage],
        maxImageBytes: Int = defaultMaxImageBytes
    ) -> [[String: Any]] {
        var contents: [[String: Any]] = []
        for msg in history where msg.role != .system && !msg.isError {
            let role = msg.role == .user ? "user" : "model"
            let images = encodedImages(for: msg, maxImageBytes: maxImageBytes)
            var parts: [[String: Any]] = images.map { img in
                [
                    "inline_data": [
                        "mime_type": img.mimeType,
                        "data": img.base64
                    ]
                ]
            }
            parts.append(["text": msg.content])
            contents.append(["role": role, "parts": parts])
        }
        return contents
    }

    // MARK: - Streaming Wire Implementations

    private static func streamOpenAICompatible(
        config: PipiLLMProviderConfig,
        systemPrompt: String,
        history: [PipiChatMessage],
        maxTokens: Int?,
        onDelta: @Sendable (String) -> Void
    ) async throws -> String {
        guard let url = buildOpenAIChatCompletionsURL(baseURL: config.baseURL) else {
            throw PipiInferenceError.invalidEndpoint(config.baseURL)
        }

        let wireMessages = buildOpenAIChatMessages(systemPrompt: systemPrompt, history: history)

        var payload: [String: Any] = [
            "model": config.modelId,
            "messages": wireMessages,
            "temperature": config.temperature,
            "stream": true
        ]
        if let maxTokens { payload["max_tokens"] = maxTokens }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        if config.kind == .openrouter {
            req.setValue("https://pipibot.ai", forHTTPHeaderField: "HTTP-Referer")
            req.setValue("PipiBot", forHTTPHeaderField: "X-Title")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            var errBody = ""
            for try await line in bytes.lines {
                errBody += line + "\n"
                if errBody.count > 400 { break }
            }
            throw PipiInferenceError.httpError(http.statusCode, errBody)
        }

        var accumulated = ""
        var rawLines = ""
        for try await line in bytes.lines {
            if Task.isCancelled { throw CancellationError() }
            if let chunk = parseOpenAISSEDataLine(line) {
                accumulated += chunk
                onDelta(chunk)
            } else if accumulated.isEmpty {
                rawLines += line
            }
        }

        // Fallback if endpoint ignored `stream: true` and returned standard JSON
        if accumulated.isEmpty,
           let data = rawLines.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = root["choices"] as? [[String: Any]],
           let first = choices.first,
           let msg = first["message"] as? [String: Any],
           let text = msg["content"] as? String {
            accumulated = text
            onDelta(text)
        }

        return accumulated
    }

    private static func streamAnthropic(
        config: PipiLLMProviderConfig,
        systemPrompt: String,
        history: [PipiChatMessage],
        maxTokens: Int,
        onDelta: @Sendable (String) -> Void
    ) async throws -> String {
        guard let url = buildAnthropicMessagesURL(baseURL: config.baseURL) else {
            throw PipiInferenceError.invalidEndpoint(config.baseURL)
        }

        let wireMessages = buildAnthropicMessages(history: history)

        var payload: [String: Any] = [
            "model": config.modelId,
            "max_tokens": maxTokens,
            "messages": wireMessages,
            "stream": true
        ]
        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["system"] = systemPrompt
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            var errBody = ""
            for try await line in bytes.lines {
                errBody += line + "\n"
                if errBody.count > 400 { break }
            }
            throw PipiInferenceError.httpError(http.statusCode, errBody)
        }

        var accumulated = ""
        for try await line in bytes.lines {
            if Task.isCancelled { throw CancellationError() }
            if let chunk = parseAnthropicSSEDataLine(line) {
                accumulated += chunk
                onDelta(chunk)
            }
        }
        return accumulated
    }

    private static func streamGemini(
        config: PipiLLMProviderConfig,
        systemPrompt: String,
        history: [PipiChatMessage],
        maxTokens: Int?,
        onDelta: @Sendable (String) -> Void
    ) async throws -> String {
        guard let url = buildGeminiGenerateURL(
            baseURL: config.baseURL,
            modelId: config.modelId,
            apiKey: config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            streaming: true
        ) else {
            throw PipiInferenceError.invalidEndpoint(config.baseURL)
        }

        let contents = buildGeminiContents(history: history)

        var genConfig: [String: Any] = ["temperature": config.temperature]
        if let maxTokens { genConfig["maxOutputTokens"] = maxTokens }

        var payload: [String: Any] = [
            "contents": contents,
            "generationConfig": genConfig
        ]
        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["systemInstruction"] = ["parts": [["text": systemPrompt]]]
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            var errBody = ""
            for try await line in bytes.lines {
                errBody += line + "\n"
                if errBody.count > 400 { break }
            }
            throw PipiInferenceError.httpError(http.statusCode, errBody)
        }

        var accumulated = ""
        for try await line in bytes.lines {
            if Task.isCancelled { throw CancellationError() }
            if let chunk = parseGeminiSSEDataLine(line) {
                accumulated += chunk
                onDelta(chunk)
            }
        }
        return accumulated
    }

    private static func streamOllama(
        config: PipiLLMProviderConfig,
        systemPrompt: String,
        history: [PipiChatMessage],
        onDelta: @Sendable (String) -> Void
    ) async throws -> String {
        let base = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(base)/api/chat") else {
            throw PipiInferenceError.invalidEndpoint(config.baseURL)
        }

        var wireMessages: [[String: String]] = []
        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            wireMessages.append(["role": "system", "content": systemPrompt])
        }
        for msg in history where msg.role != .system && !msg.isError {
            wireMessages.append([
                "role": msg.role == .user ? "user" : "assistant",
                "content": msg.content
            ])
        }

        let payload: [String: Any] = [
            "model": config.modelId,
            "messages": wireMessages,
            "stream": true
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            var errBody = ""
            for try await line in bytes.lines {
                errBody += line + "\n"
                if errBody.count > 400 { break }
            }
            throw PipiInferenceError.httpError(http.statusCode, errBody)
        }

        var accumulated = ""
        for try await line in bytes.lines {
            if Task.isCancelled { throw CancellationError() }
            guard let data = line.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let msg = root["message"] as? [String: Any],
                  let chunk = msg["content"] as? String,
                  !chunk.isEmpty else {
                continue
            }
            accumulated += chunk
            onDelta(chunk)
        }
        return accumulated
    }

    // MARK: - Non-Streaming Wire Implementations (Used for Quick Connection Tests)

    private static func callOpenAICompatible(
        config: PipiLLMProviderConfig,
        systemPrompt: String,
        history: [PipiChatMessage],
        maxTokens: Int?
    ) async throws -> String {
        guard let url = buildOpenAIChatCompletionsURL(baseURL: config.baseURL) else {
            throw PipiInferenceError.invalidEndpoint(config.baseURL)
        }

        let wireMessages = buildOpenAIChatMessages(systemPrompt: systemPrompt, history: history)

        var payload: [String: Any] = [
            "model": config.modelId,
            "messages": wireMessages,
            "temperature": config.temperature
        ]
        if let maxTokens { payload["max_tokens"] = maxTokens }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        if config.kind == .openrouter {
            req.setValue("https://pipibot.ai", forHTTPHeaderField: "HTTP-Referer")
            req.setValue("PipiBot", forHTTPHeaderField: "X-Title")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        try validateHTTP(resp: resp, data: data)

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw PipiInferenceError.emptyResponse
        }
        if let contentStr = message["content"] as? String { return contentStr }
        if let parts = message["content"] as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        throw PipiInferenceError.emptyResponse
    }

    private static func callAnthropic(
        config: PipiLLMProviderConfig,
        systemPrompt: String,
        history: [PipiChatMessage],
        maxTokens: Int
    ) async throws -> String {
        guard let url = buildAnthropicMessagesURL(baseURL: config.baseURL) else {
            throw PipiInferenceError.invalidEndpoint(config.baseURL)
        }

        let wireMessages = buildAnthropicMessages(history: history)

        var payload: [String: Any] = [
            "model": config.modelId,
            "max_tokens": maxTokens,
            "messages": wireMessages
        ]
        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["system"] = systemPrompt
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        try validateHTTP(resp: resp, data: data)

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = root["content"] as? [[String: Any]] else {
            throw PipiInferenceError.emptyResponse
        }
        return blocks.compactMap { block -> String? in
            (block["type"] as? String) == "text" ? (block["text"] as? String) : nil
        }.joined(separator: "\n")
    }

    private static func callGemini(
        config: PipiLLMProviderConfig,
        systemPrompt: String,
        history: [PipiChatMessage],
        maxTokens: Int?
    ) async throws -> String {
        guard let url = buildGeminiGenerateURL(
            baseURL: config.baseURL,
            modelId: config.modelId,
            apiKey: config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            streaming: false
        ) else {
            throw PipiInferenceError.invalidEndpoint(config.baseURL)
        }

        let contents = buildGeminiContents(history: history)

        var genConfig: [String: Any] = ["temperature": config.temperature]
        if let maxTokens { genConfig["maxOutputTokens"] = maxTokens }

        var payload: [String: Any] = [
            "contents": contents,
            "generationConfig": genConfig
        ]
        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["systemInstruction"] = ["parts": [["text": systemPrompt]]]
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        try validateHTTP(resp: resp, data: data)

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw PipiInferenceError.emptyResponse
        }
        return parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    private static func callOllama(
        config: PipiLLMProviderConfig,
        systemPrompt: String,
        history: [PipiChatMessage]
    ) async throws -> String {
        let base = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(base)/api/chat") else {
            throw PipiInferenceError.invalidEndpoint(config.baseURL)
        }

        var wireMessages: [[String: String]] = []
        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            wireMessages.append(["role": "system", "content": systemPrompt])
        }
        for msg in history where msg.role != .system && !msg.isError {
            wireMessages.append([
                "role": msg.role == .user ? "user" : "assistant",
                "content": msg.content
            ])
        }

        let payload: [String: Any] = [
            "model": config.modelId,
            "messages": wireMessages,
            "stream": false
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        try validateHTTP(resp: resp, data: data)

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = root["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw PipiInferenceError.emptyResponse
        }
        return content
    }

    private static func validateHTTP(resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw PipiInferenceError.httpError(http.statusCode, body)
        }
    }

    private static func parseOllamaModelCount(_ data: Data) -> Int {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["models"] as? [[String: Any]] else {
            return 0
        }
        return models.count
    }

    public static func buildLocalAgentPrompt(
        systemPrompt: String,
        history: [PipiChatMessage],
        isResuming: Bool = false
    ) -> String {
        let recent = history.suffix(8).filter { $0.role != .system && !$0.isError }
        if isResuming {
            return recent.last?.content ?? ""
        }
        guard recent.count > 1 else {
            let latest = recent.last?.content ?? ""
            if systemPrompt.isEmpty { return latest }
            return "[Persona Instructions]\n\(systemPrompt)\n\n[User Request]\n\(latest)"
        }
        var lines: [String] = []
        if !systemPrompt.isEmpty {
            lines.append("[Persona Instructions]\n\(systemPrompt)")
        }
        lines.append("[Recent Conversation]")
        for msg in recent.dropLast() {
            let label = msg.role == .user ? "User" : "Assistant"
            lines.append("\(label): \(msg.content)")
        }
        if let latest = recent.last {
            lines.append("\n[Current User Request]\n\(latest.content)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - UTF-8-Safe Streaming Decoder

    /// Accumulates raw bytes from pipe chunks and decodes only complete UTF-8 scalar sequences,
    /// holding back any incomplete trailing multi-byte sequence until subsequent bytes arrive.
    public struct PipiUTF8StreamDecoder: Sendable {
        private var buffer = Data()

        public init() {}

        public mutating func append(_ data: Data) -> String {
            guard !data.isEmpty else { return "" }
            buffer.append(data)
            let splitIndex = completeUTF8PrefixEndIndex(in: buffer)
            guard splitIndex > 0 else { return "" }
            let completeSlice = buffer.prefix(splitIndex)
            let remainder = buffer.dropFirst(splitIndex)
            buffer = Data(remainder)
            return String(decoding: completeSlice, as: UTF8.self)
        }

        public mutating func finish() -> String {
            guard !buffer.isEmpty else { return "" }
            let decoded = String(decoding: buffer, as: UTF8.self)
            buffer.removeAll(keepingCapacity: false)
            return decoded
        }

        private func completeUTF8PrefixEndIndex(in data: Data) -> Int {
            let count = data.count
            guard count > 0 else { return 0 }

            // Inspect up to 3 trailing continuation bytes (10xxxxxx) to see if a multi-byte scalar is incomplete.
            var contCount = 0
            while contCount < 3 && contCount < count {
                let byte = data[data.index(data.endIndex, offsetBy: -(contCount + 1))]
                if (byte & 0xC0) == 0x80 {
                    contCount += 1
                } else {
                    break
                }
            }

            if contCount == 0 {
                let last = data[data.index(before: data.endIndex)]
                // Incomplete leading byte of 2, 3, or 4-byte UTF-8 sequence
                if (last & 0xE0) == 0xC0 || (last & 0xF0) == 0xE0 || (last & 0xF8) == 0xF0 {
                    return count - 1
                }
                return count
            }

            let leadOffset = contCount + 1
            guard leadOffset <= count else {
                // Only continuation bytes at start with no leading byte (invalid bytes; don't stall forever)
                return count
            }
            let leadIndex = count - leadOffset
            let lead = data[data.index(data.startIndex, offsetBy: leadIndex)]
            let expectedLength: Int?
            if (lead & 0xE0) == 0xC0 {
                expectedLength = 2
            } else if (lead & 0xF0) == 0xE0 {
                expectedLength = 3
            } else if (lead & 0xF8) == 0xF0 {
                expectedLength = 4
            } else {
                expectedLength = nil
            }

            if let expectedLength, leadOffset < expectedLength {
                return leadIndex
            }
            return count
        }
    }

    #if os(macOS)
    private final class LockedUTF8StreamBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var decoder = PipiUTF8StreamDecoder()
        private var text = ""

        func append(_ data: Data, stripAnsi: Bool) -> String {
            lock.lock()
            let decoded = decoder.append(data)
            let cleaned = stripAnsi ? PipiInferenceEngine.stripAnsiEscapeCodes(decoded) : decoded
            if !cleaned.isEmpty {
                text += cleaned
            }
            lock.unlock()
            return cleaned
        }

        func finish(trailingData: Data, stripAnsi: Bool) -> String {
            lock.lock()
            var decoded = ""
            if !trailingData.isEmpty {
                decoded += decoder.append(trailingData)
            }
            decoded += decoder.finish()
            let cleaned = stripAnsi ? PipiInferenceEngine.stripAnsiEscapeCodes(decoded) : decoded
            if !cleaned.isEmpty {
                text += cleaned
            }
            lock.unlock()
            return cleaned
        }

        func value() -> String {
            lock.lock()
            defer { lock.unlock() }
            return text
        }
    }

    static func runSubprocessStreaming(
        executablePath: String,
        arguments: [String],
        workingDirectory: String,
        extraEnvironment: [String: String] = [:],
        onDelta: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        var env = ProcessInfo.processInfo.environment
        let extraPaths = PipiNativeMacRuntime.searchBinaryPaths().joined(separator: ":")
        let existingPath = env["PATH"] ?? ""
        env["PATH"] = existingPath.isEmpty ? extraPaths : "\(extraPaths):\(existingPath)"
        env["NO_COLOR"] = "1"
        // Wave 4 (#07): Apply isolated CLI Gateway reverse-injection overlay if active
        for (key, value) in extraEnvironment {
            env[key] = value
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        let outBuf = LockedUTF8StreamBuffer()
        let errBuf = LockedUTF8StreamBuffer()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let clean = outBuf.append(data, stripAnsi: true)
            if !clean.isEmpty {
                onDelta?(clean)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            _ = errBuf.append(data, stripAnsi: false)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try process.run()
                        process.waitUntilExit()
                        stdoutPipe.fileHandleForReading.readabilityHandler = nil
                        stderrPipe.fileHandleForReading.readabilityHandler = nil

                        // Drain any remaining buffered bytes and flush incomplete trailing UTF-8 sequences
                        let tailOutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                        let tailOut = outBuf.finish(trailingData: tailOutData, stripAnsi: true)
                        if !tailOut.isEmpty {
                            onDelta?(tailOut)
                        }
                        let tailErrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        _ = errBuf.finish(trailingData: tailErrData, stripAnsi: false)

                        let outStr = outBuf.value()
                        let errStr = errBuf.value()
                        if process.terminationStatus == 0 {
                            continuation.resume(returning: outStr.isEmpty ? errStr : outStr)
                        } else {
                            let detail = errStr.isEmpty ? outStr : errStr
                            continuation.resume(throwing: PipiInferenceError.localAgentFailed(process.terminationStatus, detail))
                        }
                    } catch {
                        stdoutPipe.fileHandleForReading.readabilityHandler = nil
                        stderrPipe.fileHandleForReading.readabilityHandler = nil
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            if process.isRunning {
                process.terminate()
            }
        }
    }
    #endif
}
