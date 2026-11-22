// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// Native macOS Remote Control PWA Server + Cloudflare Quick Tunnel (`cloudflared`) Manager.

import Foundation
#if canImport(Network)
import Network
#endif

// MARK: - 1. Remote Control State & Bridge Contracts

public enum PipiRemoteTunnelState: Sendable, Equatable {
    case stopped
    case starting
    case running(publicBaseURL: String, accessURL: String, localPort: Int, startedAt: Date)
    case missingCloudflared
    case error(String)

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    public var isStarting: Bool {
        if case .starting = self { return true }
        return false
    }

    public var accessURL: String? {
        if case .running(_, let url, _, _) = self { return url }
        return nil
    }

    public var publicBaseURL: String? {
        if case .running(let base, _, _, _) = self { return base }
        return nil
    }

    public var localPort: Int? {
        if case .running(_, _, let port, _) = self { return port }
        return nil
    }

    public var startedAt: Date? {
        if case .running(_, _, _, let started) = self { return started }
        return nil
    }

    public var errorMessage: String? {
        if case .error(let msg) = self { return msg }
        return nil
    }
}

public struct PipiRemoteBotDTO: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let role: String
    public let isRunning: Bool
    public let skillCount: Int

    public init(id: String, name: String, role: String, isRunning: Bool, skillCount: Int) {
        self.id = id
        self.name = name
        self.role = role
        self.isRunning = isRunning
        self.skillCount = skillCount
    }
}

public struct PipiRemoteConversationDTO: Codable, Sendable, Equatable {
    public let id: String
    public let personaId: String
    public let personaName: String
    public let title: String
    public let messageCount: Int
    public let updatedAt: String
    public let isRunning: Bool

    public init(
        id: String,
        personaId: String,
        personaName: String,
        title: String,
        messageCount: Int,
        updatedAt: String,
        isRunning: Bool
    ) {
        self.id = id
        self.personaId = personaId
        self.personaName = personaName
        self.title = title
        self.messageCount = messageCount
        self.updatedAt = updatedAt
        self.isRunning = isRunning
    }
}

public struct PipiRemoteDeliverableDTO: Codable, Sendable, Equatable {
    public let id: String
    public let kind: String // "image", "audio", "video", "file"
    public let fileName: String
    public let mimeType: String
    public let byteSize: Int64

    public init(id: String, kind: String, fileName: String, mimeType: String, byteSize: Int64) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.mimeType = mimeType
        self.byteSize = byteSize
    }
}

public struct PipiRemoteMessageDTO: Codable, Sendable, Equatable {
    public let id: String
    public let role: String
    public let content: String
    public let createdAt: String
    public let engineLabel: String?
    public let isError: Bool
    public let deliverables: [PipiRemoteDeliverableDTO]

    public init(
        id: String,
        role: String,
        content: String,
        createdAt: String,
        engineLabel: String?,
        isError: Bool,
        deliverables: [PipiRemoteDeliverableDTO] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.engineLabel = engineLabel
        self.isError = isError
        self.deliverables = deliverables
    }
}

public struct PipiRemotePendingOptionDTO: Codable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let isPrimary: Bool
    public let isDestructive: Bool

    public init(id: String, label: String, isPrimary: Bool, isDestructive: Bool) {
        self.id = id
        self.label = label
        self.isPrimary = isPrimary
        self.isDestructive = isDestructive
    }
}

public struct PipiRemotePendingItemDTO: Codable, Sendable, Equatable {
    public let kind: String // "decision" or "approval"
    public let id: String
    public let title: String
    public let summary: String
    public let severity: String
    public let options: [PipiRemotePendingOptionDTO]

    public init(
        kind: String,
        id: String,
        title: String,
        summary: String,
        severity: String,
        options: [PipiRemotePendingOptionDTO]
    ) {
        self.kind = kind
        self.id = id
        self.title = title
        self.summary = summary
        self.severity = severity
        self.options = options
    }
}

public struct PipiRemoteControlSnapshot: Codable, Sendable, Equatable {
    public let hostName: String
    public let appVersion: String
    public let activeModelLabel: String
    public let language: String
    public let bots: [PipiRemoteBotDTO]
    public let conversations: [PipiRemoteConversationDTO]
    public let selectedConversationId: String?
    public let messages: [PipiRemoteMessageDTO]
    public let isSelectedConversationRunning: Bool
    public let pendingItems: [PipiRemotePendingItemDTO]

    public init(
        hostName: String,
        appVersion: String,
        activeModelLabel: String,
        language: String,
        bots: [PipiRemoteBotDTO],
        conversations: [PipiRemoteConversationDTO],
        selectedConversationId: String?,
        messages: [PipiRemoteMessageDTO],
        isSelectedConversationRunning: Bool,
        pendingItems: [PipiRemotePendingItemDTO]
    ) {
        self.hostName = hostName
        self.appVersion = appVersion
        self.activeModelLabel = activeModelLabel
        self.language = language
        self.bots = bots
        self.conversations = conversations
        self.selectedConversationId = selectedConversationId
        self.messages = messages
        self.isSelectedConversationRunning = isSelectedConversationRunning
        self.pendingItems = pendingItems
    }
}

public struct PipiRemoteControlBridge: Sendable {
    public let fetchSnapshot: @Sendable (_ requestedConversationId: String?) async -> PipiRemoteControlSnapshot
    public let sendMessage: @Sendable (_ conversationId: String?, _ personaId: String?, _ text: String) async -> String
    public let createConversation: @Sendable (_ personaId: String?) async -> String
    public let stopGeneration: @Sendable (_ conversationId: String?) async -> Void
    public let resolvePending: @Sendable (_ kind: String, _ id: String, _ optionId: String, _ note: String?) async -> Bool
    public let loadDeliverableData: @Sendable (_ artifactId: String) async -> (data: Data, mimeType: String, fileName: String)?
    public let handleWebhook: @Sendable (_ routineId: String, _ authHeader: String?, _ signatureHeader: String?, _ body: Data) async -> (status: Int, message: String)

    public init(
        fetchSnapshot: @escaping @Sendable (_ requestedConversationId: String?) async -> PipiRemoteControlSnapshot,
        sendMessage: @escaping @Sendable (_ conversationId: String?, _ personaId: String?, _ text: String) async -> String,
        createConversation: @escaping @Sendable (_ personaId: String?) async -> String,
        stopGeneration: @escaping @Sendable (_ conversationId: String?) async -> Void,
        resolvePending: @escaping @Sendable (_ kind: String, _ id: String, _ optionId: String, _ note: String?) async -> Bool,
        loadDeliverableData: @escaping @Sendable (_ artifactId: String) async -> (data: Data, mimeType: String, fileName: String)? = { _ in nil },
        handleWebhook: @escaping @Sendable (_ routineId: String, _ authHeader: String?, _ signatureHeader: String?, _ body: Data) async -> (status: Int, message: String) = { _, _, _, _ in (404, "Webhook handler not connected") }
    ) {
        self.fetchSnapshot = fetchSnapshot
        self.sendMessage = sendMessage
        self.createConversation = createConversation
        self.stopGeneration = stopGeneration
        self.resolvePending = resolvePending
        self.loadDeliverableData = loadDeliverableData
        self.handleWebhook = handleWebhook
    }
}

// MARK: - 2. Native Loopback PWA HTTP Server (`127.0.0.1` via Network.framework)

public actor PipiRemotePWAServer {
    public nonisolated let accessToken: String
    private let bridge: PipiRemoteControlBridge
    private var boundPort: UInt16 = 0

    #if canImport(Network)
    private var listener: NWListener?
    private let listenerQueue = DispatchQueue(label: "ai.pipibot.remote-pwa-server", qos: .userInitiated)
    #endif

    public init(bridge: PipiRemoteControlBridge, accessToken: String? = nil) {
        self.bridge = bridge
        self.accessToken = accessToken ?? PipiCloudflareTunnelManager.generateAccessToken()
    }

    public func currentPort() -> Int {
        Int(boundPort)
    }

    public func start(port: UInt16 = 0) async throws -> Int {
        #if canImport(Network)
        if listener != nil, boundPort > 0 {
            return Int(boundPort)
        }

        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: port == 0 ? .any : (NWEndpoint.Port(rawValue: port) ?? .any)
        )
        let nwListener = try NWListener(using: params)

        let assignedPort: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let flag = RemoteLockedFlag()
            nwListener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if flag.markOnce() {
                        continuation.resume(returning: nwListener.port?.rawValue ?? port)
                    }
                case .failed(let error):
                    if flag.markOnce() {
                        continuation.resume(throwing: error)
                    }
                case .cancelled:
                    if flag.markOnce() {
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
        return Int(assignedPort)
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
            if Self.isCompleteHTTPRequest(next) || isComplete || error != nil || next.count > 1_048_576 {
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
            return httpJSON(status: 400, payload: ["error": "Malformed HTTP request"])
        }
        let headerString = String(decoding: raw[..<headerRange.lowerBound], as: UTF8.self)
        let bodyData = Data(raw[headerRange.upperBound...])
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return httpJSON(status: 400, payload: ["error": "Empty request line"])
        }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            return httpJSON(status: 400, payload: ["error": "Invalid request line"])
        }
        let method = String(parts[0]).uppercased()
        let rawTarget = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colon = line.firstIndex(of: ":") {
                let k = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let v = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                headers[k] = v
            }
        }

        if method == "OPTIONS" {
            return httpResponse(status: 204, contentType: "text/plain; charset=utf-8", body: Data())
        }

        let components = URLComponents(string: "http://127.0.0.1\(rawTarget)")
        let path = components?.path ?? rawTarget
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }

        // Public PWA static assets
        switch (method, path) {
        case ("GET", "/"), ("GET", "/index.html"):
            return httpResponse(
                status: 200,
                contentType: "text/html; charset=utf-8",
                body: Data(Self.remotePWAHTML.utf8)
            )
        case ("GET", "/manifest.webmanifest"), ("GET", "/manifest.json"):
            return httpResponse(
                status: 200,
                contentType: "application/manifest+json; charset=utf-8",
                body: Data(Self.remotePWAManifest.utf8)
            )
        case ("GET", "/icon-192.png"):
            return serveIcon(named: "icon-192.png")
        case ("GET", "/icon-512.png"):
            return serveIcon(named: "icon-512.png")
        case ("GET", "/apple-touch-icon.png"):
            return serveIcon(named: "apple-touch-icon.png")
        case ("GET", "/icon.svg"):
            return httpResponse(
                status: 200,
                contentType: "image/svg+xml; charset=utf-8",
                body: Data(Self.fallbackIconSVG.utf8)
            )
        case ("GET", "/health"):
            return httpJSON(status: 200, payload: ["status": "ok"])
        default:
            break
        }

        // Event-Driven Routine Webhooks (authenticated per-routine via HMAC-SHA256 or Bearer secret)
        if method == "POST", path.hasPrefix("/api/v1/webhooks/") {
            let routineId = String(path.dropFirst("/api/v1/webhooks/".count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !routineId.isEmpty else {
                return httpJSON(status: 400, payload: ["error": "Missing routine ID"])
            }
            let sigHeader = headers["x-pipibot-signature"] ?? headers["x-hub-signature-256"]
            let res = await bridge.handleWebhook(routineId, headers["authorization"], sigHeader, bodyData)
            return httpJSON(status: res.status, payload: ["ok": res.status < 400, "message": res.message, "routineId": routineId])
        }

        // Token authentication for all /api/* routes
        if path.hasPrefix("/api/") {
            let providedToken = headers["x-pipibot-token"]
                ?? query["token"]
                ?? extractBearerToken(headers["authorization"])
            guard let providedToken, providedToken == accessToken else {
                return httpJSON(status: 401, payload: ["error": "Unauthorized remote session token"])
            }
        }

        if method == "GET", path.hasPrefix("/api/media/") {
            let artifactId = String(path.dropFirst("/api/media/".count))
            if !artifactId.isEmpty, let media = await bridge.loadDeliverableData(artifactId) {
                return httpResponse(
                    status: 200,
                    contentType: media.mimeType,
                    body: media.data,
                    extraHeaders: ["Content-Disposition": "inline; filename=\"\(media.fileName)\""]
                )
            }
            return httpJSON(status: 404, payload: ["error": "Deliverable not found"])
        }

        switch (method, path) {
        case ("GET", "/api/state"):
            let requestedConv = query["conversationId"].flatMap { $0.isEmpty ? nil : $0 }
            let snapshot = await bridge.fetchSnapshot(requestedConv)
            return httpCodableJSON(status: 200, value: snapshot)

        case ("POST", "/api/chat/send"):
            guard let obj = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any],
                  let text = (obj["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                return httpJSON(status: 400, payload: ["error": "Missing message text"])
            }
            let convId = (obj["conversationId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let personaId = (obj["personaId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let resolvedConvId = await bridge.sendMessage(convId, personaId, text)
            return httpJSON(status: 200, payload: ["status": "ok", "conversationId": resolvedConvId])

        case ("POST", "/api/chat/new"):
            let obj = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any]
            let personaId = (obj?["personaId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let convId = await bridge.createConversation(personaId)
            return httpJSON(status: 200, payload: ["status": "ok", "conversationId": convId])

        case ("POST", "/api/chat/stop"):
            let obj = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any]
            let convId = (obj?["conversationId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            await bridge.stopGeneration(convId)
            return httpJSON(status: 200, payload: ["status": "ok"])

        case ("POST", "/api/pending/resolve"):
            guard let obj = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any],
                  let kind = obj["kind"] as? String,
                  let id = obj["id"] as? String,
                  let optionId = obj["optionId"] as? String else {
                return httpJSON(status: 400, payload: ["error": "Missing pending resolution fields"])
            }
            let note = obj["note"] as? String
            let ok = await bridge.resolvePending(kind, id, optionId, note)
            return httpJSON(status: ok ? 200 : 404, payload: ["status": ok ? "ok" : "not_found"])

        default:
            return httpJSON(status: 404, payload: ["error": "Route not found"])
        }
    }

    private func extractBearerToken(_ header: String?) -> String? {
        guard let header else { return nil }
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("bearer ") {
            return String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private func serveIcon(named filename: String) -> Data {
        let candidates: [URL] = [
            Bundle.main.resourceURL?.appendingPathComponent("ios-web/icons/\(filename)"),
            Bundle.main.resourceURL?.appendingPathComponent("runtime/apps/ios-web/icons/\(filename)"),
            PipiNativeMacRuntime.discoverRepoRoot().map {
                URL(fileURLWithPath: $0).appendingPathComponent("apps/ios-web/icons/\(filename)")
            }
        ].compactMap { $0 }

        for url in candidates {
            if let bytes = try? Data(contentsOf: url), !bytes.isEmpty {
                return httpResponse(status: 200, contentType: "image/png", body: bytes)
            }
        }
        return httpResponse(status: 200, contentType: "image/svg+xml; charset=utf-8", body: Data(Self.fallbackIconSVG.utf8))
    }

    private func httpCodableJSON<T: Encodable>(status: Int, value: T) -> Data {
        let encoder = JSONEncoder()
        let body = (try? encoder.encode(value)) ?? Data("{}".utf8)
        return httpResponse(status: status, contentType: "application/json; charset=utf-8", body: body)
    }

    private func httpJSON(status: Int, payload: [String: Any]) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data("{}".utf8)
        return httpResponse(status: status, contentType: "application/json; charset=utf-8", body: body)
    }

    private func httpResponse(
        status: Int,
        contentType: String,
        body: Data,
        extraHeaders: [String: String] = [:]
    ) -> Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 204: reason = "No Content"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        default: reason = "Error"
        }
        var headerLines = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type, Authorization, X-PipiBot-Token",
            "Connection: close"
        ]
        for (k, v) in extraHeaders {
            headerLines.append("\(k): \(v)")
        }
        headerLines.append("")
        headerLines.append("")
        var out = Data(headerLines.joined(separator: "\r\n").utf8)
        out.append(body)
        return out
    }

    // MARK: - Embedded Light Porcelain PWA Assets (Zero Raw Hex Literals)

    private static let remotePWAManifest: String = """
    {
      "name": "PiPiBot 远程操控",
      "short_name": "PiPiBot",
      "description": "PiPiBot macOS 远程交互 PWA（经由 Cloudflare Tunnel 临时连接）",
      "start_url": "/?pwa=1",
      "scope": "/",
      "display": "standalone",
      "orientation": "portrait",
      "background_color": "rgb(250, 249, 246)",
      "theme_color": "rgb(250, 249, 246)",
      "icons": [
        {
          "src": "/icon-192.png",
          "sizes": "192x192",
          "type": "image/png",
          "purpose": "any maskable"
        },
        {
          "src": "/icon-512.png",
          "sizes": "512x512",
          "type": "image/png",
          "purpose": "any maskable"
        }
      ]
    }
    """

    private static let fallbackIconSVG: String = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">
      <rect width="128" height="128" rx="28" fill="rgb(245,242,235)"/>
      <rect x="24" y="34" width="80" height="62" rx="18" fill="rgb(253,252,249)" stroke="rgb(212,206,196)" stroke-width="3"/>
      <rect x="34" y="46" width="60" height="32" rx="10" fill="rgb(22,30,44)"/>
      <circle cx="51" cy="62" r="6" fill="rgb(68,214,238)"/>
      <circle cx="77" cy="62" r="6" fill="rgb(68,214,238)"/>
      <line x1="64" y1="20" x2="64" y2="34" stroke="rgb(138,144,154)" stroke-width="4" stroke-linecap="round"/>
      <circle cx="64" cy="17" r="5" fill="rgb(68,214,238)"/>
    </svg>
    """

    private static let remotePWAHTML: String = """
    <!DOCTYPE html>
    <html lang="zh-CN">
    <head>
      <meta charset="UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover" />
      <meta name="apple-mobile-web-app-capable" content="yes" />
      <meta name="mobile-web-app-capable" content="yes" />
      <meta name="apple-mobile-web-app-status-bar-style" content="default" />
      <meta name="apple-mobile-web-app-title" content="PiPiBot" />
      <title>PiPiBot · 远程操控</title>
      <link rel="manifest" href="/manifest.webmanifest" />
      <link rel="apple-touch-icon" href="/apple-touch-icon.png" />
      <link rel="icon" type="image/png" href="/icon-192.png" />
      <style>
        :root {
          color-scheme: light dark;
          --bg: rgb(250, 249, 246);
          --surface: rgb(255, 255, 255);
          --surface-alt: rgb(243, 241, 236);
          --border: rgba(24, 28, 36, 0.11);
          --text: rgb(24, 26, 30);
          --text-sub: rgb(104, 108, 118);
          --accent: rgb(32, 36, 44);
          --accent-fg: rgb(255, 255, 255);
          --ok: rgb(22, 148, 84);
          --warn: rgb(206, 128, 16);
          --err: rgb(204, 52, 52);
          --bubble-user: rgb(32, 36, 44);
          --bubble-user-fg: rgb(255, 255, 255);
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --bg: rgb(15, 16, 18);
            --surface: rgb(24, 26, 30);
            --surface-alt: rgb(32, 35, 41);
            --border: rgba(255, 255, 255, 0.11);
            --text: rgb(242, 243, 246);
            --text-sub: rgb(152, 158, 170);
            --accent: rgb(242, 243, 246);
            --accent-fg: rgb(18, 20, 24);
            --ok: rgb(52, 199, 120);
            --warn: rgb(235, 168, 48);
            --err: rgb(236, 86, 86);
            --bubble-user: rgb(54, 104, 214);
            --bubble-user-fg: rgb(255, 255, 255);
          }
        }
        * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
        html, body {
          margin: 0; padding: 0; height: 100%; width: 100%;
          background: var(--bg); color: var(--text);
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Helvetica Neue", sans-serif;
          overscroll-behavior: none;
        }
        .shell {
          display: flex; flex-direction: column; height: 100dvh; max-width: 720px; margin: 0 auto;
        }
        .topbar {
          display: flex; align-items: center; justify-content: space-between; gap: 10px;
          padding: calc(env(safe-area-inset-top) + 10px) 16px 10px;
          background: var(--surface); border-bottom: 1px solid var(--border);
        }
        .brand { display: flex; align-items: center; gap: 10px; min-width: 0; }
        .brand img { width: 28px; height: 28px; border-radius: 7px; border: 1px solid var(--border); }
        .brand-title { font-size: 15px; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .brand-sub { font-size: 11px; color: var(--text-sub); display: flex; align-items: center; gap: 6px; }
        .dot { width: 7px; height: 7px; border-radius: 99px; background: var(--ok); display: inline-block; flex-shrink: 0; }
        .dot.off { background: var(--err); }
        .pwa-banner {
          display: none; align-items: center; justify-content: space-between; gap: 8px;
          padding: 8px 14px; font-size: 12px; color: var(--text-sub);
          background: var(--surface-alt); border-bottom: 1px solid var(--border);
        }
        .pwa-banner.show { display: flex; }
        .pwa-banner button {
          border: 0; background: transparent; color: var(--text-sub); font-size: 12px; padding: 4px 6px; cursor: pointer;
        }
        .main {
          flex: 1; overflow-y: auto; padding: 14px 14px 16px; display: flex; flex-direction: column; gap: 10px;
          scrollbar-width: none;
        }
        .main::-webkit-scrollbar { display: none; }
        .chips {
          display: flex; gap: 6px; overflow-x: auto; padding-bottom: 4px; flex-shrink: 0; scrollbar-width: none;
        }
        .chips::-webkit-scrollbar { display: none; }
        .chip {
          border: 1px solid var(--border); background: var(--surface); color: var(--text-sub);
          border-radius: 999px; padding: 6px 12px; font-size: 12px; font-weight: 500;
          white-space: nowrap; cursor: pointer;
        }
        .chip.active { background: var(--accent); color: var(--accent-fg); border-color: transparent; }
        .msg-list { display: flex; flex-direction: column; gap: 10px; flex: 1; }
        .msg {
          max-width: 88%; padding: 10px 13px; border-radius: 14px; font-size: 14px; line-height: 1.5;
          white-space: pre-wrap; word-break: break-word;
        }
        .msg.user { align-self: flex-end; background: var(--bubble-user); color: var(--bubble-user-fg); border-bottom-right-radius: 4px; }
        .msg.assistant { align-self: flex-start; background: var(--surface); border: 1px solid var(--border); border-bottom-left-radius: 4px; }
        .msg-meta { font-size: 11px; color: var(--text-sub); margin-top: 4px; }
        .card {
          background: var(--surface); border: 1px solid var(--border); border-radius: 12px; padding: 13px 14px;
          display: flex; flex-direction: column; gap: 8px;
        }
        .card-head { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
        .card-title { font-size: 14px; font-weight: 600; }
        .card-sub { font-size: 12px; color: var(--text-sub); line-height: 1.45; }
        .badge {
          font-size: 11px; padding: 2px 8px; border-radius: 99px; background: var(--surface-alt); color: var(--text-sub);
        }
        .badge.ok { color: var(--ok); }
        .badge.warn { color: var(--warn); }
        .btn-row { display: flex; gap: 8px; flex-wrap: wrap; }
        .btn {
          border: 1px solid var(--border); background: var(--surface-alt); color: var(--text);
          border-radius: 9px; padding: 8px 13px; font-size: 13px; font-weight: 500; cursor: pointer;
        }
        .btn.primary { background: var(--accent); color: var(--accent-fg); border-color: transparent; }
        .btn.danger { color: var(--err); }
        .composer {
          display: flex; align-items: flex-end; gap: 8px; padding: 10px 12px;
          background: var(--surface); border-top: 1px solid var(--border);
        }
        .composer textarea {
          flex: 1; resize: none; min-height: 38px; max-height: 110px;
          border: 1px solid var(--border); border-radius: 11px; padding: 8px 11px;
          font-size: 14px; line-height: 1.4; background: var(--bg); color: var(--text); outline: none;
          font-family: inherit;
        }
        .tabbar {
          display: grid; grid-template-columns: repeat(3, 1fr);
          padding: 6px 8px calc(env(safe-area-inset-bottom) + 8px);
          background: var(--surface); border-top: 1px solid var(--border);
        }
        .tab {
          border: 0; background: transparent; color: var(--text-sub); font-size: 12px; font-weight: 500;
          padding: 6px 4px; border-radius: 8px; cursor: pointer; display: flex; flex-direction: column; align-items: center; gap: 2px;
        }
        .tab.active { color: var(--text); font-weight: 600; background: var(--surface-alt); }
        .empty { text-align: center; color: var(--text-sub); font-size: 13px; padding: 36px 16px; }
        .auth-box { margin: auto; max-width: 340px; width: 100%; }
      </style>
    </head>
    <body>
      <div class="shell">
        <header class="topbar">
          <div class="brand">
            <img src="/icon-192.png" alt="PiPiBot" />
            <div style="min-width:0">
              <div class="brand-title" id="host-title">PiPiBot 远程操控</div>
              <div class="brand-sub"><span class="dot" id="conn-dot"></span><span id="conn-label">正在连接 Mac...</span></div>
            </div>
          </div>
          <button class="btn" id="btn-new-chat" type="button">新对话</button>
        </header>

        <div class="pwa-banner" id="pwa-banner">
          <span>添加到主屏幕后可以 PWA 全屏模式远程控制此 Mac（临时隧道关闭后地址会变）。</span>
          <button id="btn-dismiss-pwa" type="button">关闭</button>
        </div>

        <main class="main" id="main-view"></main>

        <div class="composer" id="composer-bar">
          <textarea id="chat-input" rows="1" placeholder="输入指令发送至本台 Mac..."></textarea>
          <button class="btn primary" id="btn-send" type="button">发送</button>
        </div>

        <nav class="tabbar">
          <button class="tab active" data-tab="chat" type="button"><span>对话</span></button>
          <button class="tab" data-tab="bots" type="button"><span>智能体</span></button>
          <button class="tab" data-tab="pending" type="button"><span id="tab-pending-label">待确认</span></button>
        </nav>
      </div>

      <script>
      (function () {
        const TOKEN_KEY = 'pipibot_remote_token_v1';
        const params = new URLSearchParams(window.location.search);
        const urlToken = params.get('token');
        if (urlToken) {
          localStorage.setItem(TOKEN_KEY, urlToken);
          params.delete('token');
          const clean = window.location.pathname + (params.toString() ? '?' + params.toString() : '');
          window.history.replaceState({}, '', clean);
        }

        let token = localStorage.getItem(TOKEN_KEY) || '';
        let activeTab = 'chat';
        let selectedConvId = null;
        let selectedPersonaId = null;
        let snapshot = null;
        let authError = false;
        let pollTimer = null;

        const isStandalone = window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true;
        if (!isStandalone && !localStorage.getItem('pipibot_pwa_banner_hidden')) {
          document.getElementById('pwa-banner').classList.add('show');
        }
        document.getElementById('btn-dismiss-pwa').addEventListener('click', () => {
          document.getElementById('pwa-banner').classList.remove('show');
          localStorage.setItem('pipibot_pwa_banner_hidden', '1');
        });

        function esc(str) {
          return String(str || '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
        }

        async function api(path, options = {}) {
          const res = await fetch(path, {
            ...options,
            headers: {
              'Content-Type': 'application/json',
              'X-PipiBot-Token': token,
              ...(options.headers || {}),
            },
          });
          if (res.status === 401) {
            authError = true;
            throw new Error('UNAUTHORIZED');
          }
          if (!res.ok) throw new Error('HTTP_' + res.status);
          authError = false;
          return res.json();
        }

        async function refreshState() {
          if (!token) {
            authError = true;
            render();
            return;
          }
          try {
            const qs = selectedConvId ? '?conversationId=' + encodeURIComponent(selectedConvId) : '';
            const data = await api('/api/state' + qs);
            snapshot = data;
            if (!selectedConvId && data.selectedConversationId) {
              selectedConvId = data.selectedConversationId;
            }
            if (!selectedPersonaId && data.bots && data.bots.length > 0) {
              selectedPersonaId = data.bots[0].id;
            }
            document.getElementById('host-title').textContent = (data.hostName || 'Mac') + ' · PiPiBot';
            document.getElementById('conn-dot').classList.remove('off');
            document.getElementById('conn-label').textContent = (data.activeModelLabel || '已连接') + ' · v' + (data.appVersion || '0.11.0');
            const pCount = (data.pendingItems || []).length;
            document.getElementById('tab-pending-label').textContent = pCount > 0 ? ('待确认 (' + pCount + ')') : '待确认';
            render();
          } catch (err) {
            document.getElementById('conn-dot').classList.add('off');
            document.getElementById('conn-label').textContent = err.message === 'UNAUTHORIZED' ? '临时令牌已失效，请重新扫码' : '连接中断，正在重试...';
            render();
          } finally {
            clearTimeout(pollTimer);
            const interval = snapshot && snapshot.isSelectedConversationRunning ? 1200 : 3500;
            pollTimer = setTimeout(refreshState, interval);
          }
        }

        function render() {
          const main = document.getElementById('main-view');
          const composer = document.getElementById('composer-bar');
          const sendBtn = document.getElementById('btn-send');

          document.querySelectorAll('.tab').forEach((el) => {
            el.classList.toggle('active', el.dataset.tab === activeTab);
          });

          if (authError) {
            composer.style.display = 'none';
            main.innerHTML = '<div class="card auth-box"><div class="card-title">需要有效的临时访问链接</div><div class="card-sub">当前隧道地址或临时口令无效。请在 Mac 端「设置 → 运行与远程操控」重新扫描二维码或复制最新链接打开。</div></div>';
            return;
          }

          if (!snapshot) {
            composer.style.display = 'none';
            main.innerHTML = '<div class="empty">正在与 Mac 端建立连接...</div>';
            return;
          }

          if (activeTab === 'chat') {
            composer.style.display = 'flex';
            sendBtn.textContent = snapshot.isSelectedConversationRunning ? '停止' : '发送';
            const convs = snapshot.conversations || [];
            const chipsHtml = convs.slice(0, 8).map((c) => {
              const active = c.id === snapshot.selectedConversationId ? ' active' : '';
              return '<button class="chip' + active + '" data-conv="' + esc(c.id) + '" type="button">' + esc(c.personaName + ' · ' + c.title) + '</button>';
            }).join('');

            const quickCmdsHtml =
              '<div class="chips">' +
                '<button class="chip" data-quick="/screenshot" type="button">截屏</button>' +
                '<button class="chip" data-quick="/sms" type="button">查短信</button>' +
                '<button class="chip" data-quick="/mail" type="button">查邮件</button>' +
                '<button class="chip" data-quick="/record 5" type="button">录屏 5s</button>' +
              '</div>';

            const msgs = snapshot.messages || [];
            const msgsHtml = msgs.length === 0
              ? '<div class="empty">当前对话暂无消息，直接输入即可远程调度 Mac 上的智能体（支持 /screenshot · /sms · /mail · /build · /sendfile）。</div>'
              : msgs.map((m) => {
                  const roleCls = m.role === 'user' ? 'user' : 'assistant';
                  const meta = m.engineLabel ? '<div class="msg-meta">' + esc(m.engineLabel) + '</div>' : '';
                  const mediaHtml = (m.deliverables || []).map((d) => {
                    const src = '/api/media/' + encodeURIComponent(d.id) + '?token=' + encodeURIComponent(token);
                    if (d.kind === 'image') {
                      return '<div style="margin-top:8px;"><a href="' + src + '" target="_blank"><img src="' + src + '" alt="' + esc(d.fileName) + '" style="max-width:100%;border-radius:10px;border:1px solid var(--border);display:block;" /></a></div>';
                    }
                    if (d.kind === 'audio') {
                      return '<div style="margin-top:8px;"><audio controls src="' + src + '" style="width:100%;"></audio></div>';
                    }
                    if (d.kind === 'video') {
                      return '<div style="margin-top:8px;"><video controls playsinline src="' + src + '" style="max-width:100%;border-radius:10px;"></video></div>';
                    }
                    return '<div style="margin-top:8px;"><a class="btn" href="' + src + '" download="' + esc(d.fileName) + '" style="display:inline-block;text-decoration:none;">下载文件：' + esc(d.fileName) + '</a></div>';
                  }).join('');
                  return '<div class="msg ' + roleCls + '">' + esc(m.content) + mediaHtml + meta + '</div>';
                }).join('');

            const typingHtml = snapshot.isSelectedConversationRunning
              ? '<div class="msg assistant"><span class="card-sub">Mac 端正在执行并生成回复...</span></div>'
              : '';

            main.innerHTML = '<div class="chips">' + chipsHtml + '</div>' + quickCmdsHtml + '<div class="msg-list">' + msgsHtml + typingHtml + '</div>';
            main.querySelectorAll('[data-conv]').forEach((btn) => {
              btn.addEventListener('click', () => {
                selectedConvId = btn.dataset.conv;
                refreshState();
              });
            });
            main.querySelectorAll('[data-quick]').forEach((btn) => {
              btn.addEventListener('click', async () => {
                const cmd = btn.dataset.quick;
                const res = await api('/api/chat/send', {
                  method: 'POST',
                  body: JSON.stringify({ conversationId: selectedConvId, personaId: selectedPersonaId, text: cmd }),
                });
                if (res.conversationId) selectedConvId = res.conversationId;
                refreshState();
              });
            });
            main.scrollTop = main.scrollHeight;
            return;
          }

          composer.style.display = 'none';

          if (activeTab === 'bots') {
            const bots = snapshot.bots || [];
            main.innerHTML = bots.map((b) => (
              '<div class="card">' +
                '<div class="card-head">' +
                  '<div class="card-title">' + esc(b.name) + '</div>' +
                  '<span class="badge ' + (b.isRunning ? 'ok' : '') + '">' + (b.isRunning ? '执行中' : '就绪') + '</span>' +
                '</div>' +
                '<div class="card-sub">' + esc(b.role) + ' · 技能 ' + b.skillCount + ' 项</div>' +
                '<div class="btn-row"><button class="btn primary" data-start-bot="' + esc(b.id) + '" type="button">发起对话</button></div>' +
              '</div>'
            )).join('');
            main.querySelectorAll('[data-start-bot]').forEach((btn) => {
              btn.addEventListener('click', async () => {
                const res = await api('/api/chat/new', { method: 'POST', body: JSON.stringify({ personaId: btn.dataset.startBot }) });
                selectedConvId = res.conversationId;
                activeTab = 'chat';
                refreshState();
              });
            });
            return;
          }

          const items = snapshot.pendingItems || [];
          if (items.length === 0) {
            main.innerHTML = '<div class="empty">当前无待确认的权限审批或决策事项。</div>';
            return;
          }
          main.innerHTML = items.map((item) => (
            '<div class="card">' +
              '<div class="card-head">' +
                '<div class="card-title">' + esc(item.title) + '</div>' +
                '<span class="badge warn">' + esc(item.severity) + '</span>' +
              '</div>' +
              '<div class="card-sub">' + esc(item.summary) + '</div>' +
              '<div class="btn-row">' +
                item.options.map((o) => {
                  const cls = o.isPrimary ? 'btn primary' : (o.isDestructive ? 'btn danger' : 'btn');
                  return '<button class="' + cls + '" data-res-kind="' + esc(item.kind) + '" data-res-id="' + esc(item.id) + '" data-res-opt="' + esc(o.id) + '" type="button">' + esc(o.label) + '</button>';
                }).join('') +
              '</div>' +
            '</div>'
          )).join('');
          main.querySelectorAll('[data-res-id]').forEach((btn) => {
            btn.addEventListener('click', async () => {
              btn.disabled = true;
              await api('/api/pending/resolve', {
                method: 'POST',
                body: JSON.stringify({ kind: btn.dataset.resKind, id: btn.dataset.resId, optionId: btn.dataset.resOpt }),
              });
              refreshState();
            });
          });
        }

        async function handleSendOrStop() {
          if (snapshot && snapshot.isSelectedConversationRunning) {
            await api('/api/chat/stop', { method: 'POST', body: JSON.stringify({ conversationId: selectedConvId }) });
            refreshState();
            return;
          }
          const input = document.getElementById('chat-input');
          const text = input.value.trim();
          if (!text) return;
          input.value = '';
          const res = await api('/api/chat/send', {
            method: 'POST',
            body: JSON.stringify({ conversationId: selectedConvId, personaId: selectedPersonaId, text }),
          });
          if (res.conversationId) selectedConvId = res.conversationId;
          refreshState();
        }

        document.getElementById('btn-send').addEventListener('click', () => { void handleSendOrStop(); });
        document.getElementById('chat-input').addEventListener('keydown', (e) => {
          if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            void handleSendOrStop();
          }
        });
        document.getElementById('btn-new-chat').addEventListener('click', async () => {
          const res = await api('/api/chat/new', { method: 'POST', body: JSON.stringify({ personaId: selectedPersonaId }) });
          selectedConvId = res.conversationId;
          activeTab = 'chat';
          refreshState();
        });
        document.querySelectorAll('.tab').forEach((btn) => {
          btn.addEventListener('click', () => {
            activeTab = btn.dataset.tab;
            render();
          });
        });

        refreshState();
      })();
      </script>
    </body>
    </html>
    """
}

// MARK: - 3. Cloudflare Quick Tunnel (`cloudflared`) Lifecycle Manager

@MainActor
@Observable
public final class PipiCloudflareTunnelManager {
    public private(set) var state: PipiRemoteTunnelState = .stopped
    public private(set) var cloudflaredPath: String?

    public var isCloudflaredInstalled: Bool { cloudflaredPath != nil }

    private var pwaServer: PipiRemotePWAServer?
    #if os(macOS)
    private var tunnelProcess: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var startupTimeoutTask: Task<Void, Never>?
    private var collectedLogTail: String = ""
    #endif

    public init() {
        self.cloudflaredPath = Self.discoverCloudflaredBinary()
    }

    public func refreshCloudflaredAvailability() {
        let found = Self.discoverCloudflaredBinary()
        cloudflaredPath = found
        if found != nil, case .missingCloudflared = state {
            state = .stopped
        }
    }

    public nonisolated static func generateAccessToken() -> String {
        let a = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let b = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return String((a + b).prefix(24))
    }

    /// Parses Cloudflare Quick Tunnel output for the temporary `https://<subdomain>.trycloudflare.com` URL.
    public nonisolated static func extractTryCloudflareURL(from logText: String) -> String? {
        let pattern = #"https://[a-zA-Z0-9-]+\.trycloudflare\.com"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(logText.startIndex..<logText.endIndex, in: logText)
        guard let match = regex.firstMatch(in: logText, options: [], range: range),
              let matchRange = Range(match.range, in: logText) else {
            return nil
        }
        return String(logText[matchRange]).lowercased()
    }

    public nonisolated static func buildAuthenticatedRemoteURL(tunnelBaseURL: String, accessToken: String) -> String {
        let trimmed = tunnelBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(trimmed)/?token=\(accessToken)"
    }

    public nonisolated static func discoverCloudflaredBinary(searchPaths: [String]? = nil) -> String? {
        #if os(macOS)
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = searchPaths ?? [
            "/opt/homebrew/bin/cloudflared",
            "/usr/local/bin/cloudflared",
            "/opt/local/bin/cloudflared",
            "/usr/bin/cloudflared",
            "\(home)/.local/bin/cloudflared",
            "\(home)/bin/cloudflared"
        ]
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        return PipiNativeMacRuntime.findExecutable("cloudflared")
        #else
        _ = searchPaths
        return nil
        #endif
    }

    public func start(bridge: PipiRemoteControlBridge) async {
        stop()

        let resolvedBinary = Self.discoverCloudflaredBinary()
        cloudflaredPath = resolvedBinary
        guard let binaryPath = resolvedBinary else {
            state = .missingCloudflared
            return
        }

        state = .starting

        let server = PipiRemotePWAServer(bridge: bridge)
        let localPort: Int
        do {
            localPort = try await server.start(port: 0)
            self.pwaServer = server
        } catch {
            state = .error("本地远程服务启动失败：\(error.localizedDescription)")
            return
        }

        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = [
            "tunnel",
            "--url", "http://127.0.0.1:\(localPort)",
            "--no-autoupdate"
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        self.outputPipe = stdout
        self.errorPipe = stderr
        self.collectedLogTail = ""

        let token = server.accessToken

        let handleChunk: @Sendable (Data) -> Void = { [weak self] data in
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.collectedLogTail = String((self.collectedLogTail + chunk).suffix(4096))
                guard case .starting = self.state else { return }
                if let publicBase = Self.extractTryCloudflareURL(from: self.collectedLogTail) {
                    self.startupTimeoutTask?.cancel()
                    self.startupTimeoutTask = nil
                    let accessURL = Self.buildAuthenticatedRemoteURL(tunnelBaseURL: publicBase, accessToken: token)
                    self.state = .running(
                        publicBaseURL: publicBase,
                        accessURL: accessURL,
                        localPort: localPort,
                        startedAt: Date()
                    )
                }
            }
        }

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                handleChunk(data)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                handleChunk(data)
            }
        }

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.startupTimeoutTask?.cancel()
                self.startupTimeoutTask = nil
                self.outputPipe?.fileHandleForReading.readabilityHandler = nil
                self.errorPipe?.fileHandleForReading.readabilityHandler = nil
                if proc === self.tunnelProcess {
                    self.tunnelProcess = nil
                    switch self.state {
                    case .starting:
                        let snippet = self.collectedLogTail
                            .components(separatedBy: .newlines)
                            .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "cloudflared 异常退出"
                        self.state = .error(snippet)
                        await self.pwaServer?.stop()
                        self.pwaServer = nil
                    case .running:
                        self.state = .stopped
                        await self.pwaServer?.stop()
                        self.pwaServer = nil
                    default:
                        break
                    }
                }
            }
        }

        do {
            try process.run()
            self.tunnelProcess = process
            self.startupTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(25))
                guard let self, !Task.isCancelled else { return }
                if case .starting = self.state {
                    self.stop()
                    self.state = .error("Cloudflare Tunnel 建立超时，请检查当前网络连接后重试。")
                }
            }
        } catch {
            await server.stop()
            self.pwaServer = nil
            state = .error("无法启动 cloudflared：\(error.localizedDescription)")
        }
        #else
        await server.stop()
        self.pwaServer = nil
        state = .error("仅 macOS 端支持发布远程操控隧道。")
        #endif
    }

    public func regenerate(bridge: PipiRemoteControlBridge) async {
        await start(bridge: bridge)
    }

    public func stop() {
        #if os(macOS)
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        errorPipe = nil
        if let proc = tunnelProcess {
            tunnelProcess = nil
            if proc.isRunning {
                proc.terminate()
            }
        }
        collectedLogTail = ""
        #endif

        if let server = pwaServer {
            pwaServer = nil
            Task {
                await server.stop()
            }
        }
        state = .stopped
    }
}

private final class RemoteLockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var didMark = false

    func markOnce() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if didMark { return false }
        didMark = true
        return true
    }
}
