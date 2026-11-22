// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// Local Credential Broker & Environment Scrubber:
// - Never exposes raw provider API keys to spawned CLI/ACP child processes.
// - Issues ephemeral per-process proxy tokens (`pipi_brk_...`) revoked immediately on exit.
// - Strips unrelated provider secrets and internal PiPiBot tokens from child environment.

import Foundation
#if canImport(Network)
import Network
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

public struct PipiBrokerUpstreamBinding: Sendable, Equatable {
    public let provider: String // "openai" | "anthropic" | "gemini"
    public let upstreamBaseURL: URL
    public let realSecret: String
    public let authHeaderName: String
    public let authHeaderPrefix: String

    public init(
        provider: String,
        upstreamBaseURL: URL,
        realSecret: String,
        authHeaderName: String = "Authorization",
        authHeaderPrefix: String = "Bearer "
    ) {
        self.provider = provider
        self.upstreamBaseURL = upstreamBaseURL
        self.realSecret = realSecret
        self.authHeaderName = authHeaderName
        self.authHeaderPrefix = authHeaderPrefix
    }
}

public struct PipiCredentialBrokerLease: Sendable, Equatable {
    public let token: String
    public let provider: String
    public let proxyBaseURL: String
    public let expiresAt: Date

    public init(token: String, provider: String, proxyBaseURL: String, expiresAt: Date) {
        self.token = token
        self.provider = provider
        self.proxyBaseURL = proxyBaseURL
        self.expiresAt = expiresAt
    }
}

/// Loopback-only HTTP Credential Broker that injects real upstream API keys out-of-process.
public actor PipiCredentialBroker {
    public static let sensitiveForeignEnvKeys: Set<String> = [
        "OPENAI_API_KEY",
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_AUTH_TOKEN",
        "GEMINI_API_KEY",
        "GOOGLE_API_KEY",
        "XAI_API_KEY",
        "DEEPSEEK_API_KEY",
        "OPENROUTER_API_KEY",
        "PIPIBOT_HUB_TOKEN",
        "PIPIBOT_REMOTE_TOKEN",
        "PIPIBOT_MASTER_SECRET"
    ]

    private struct StoredLease: Sendable {
        let token: String
        let binding: PipiBrokerUpstreamBinding
        let expiresAt: Date
    }

    private var leases: [String: StoredLease] = [:]
    private var port: UInt16 = 0
    #if canImport(Network)
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "ai.pipibot.credential-broker", qos: .userInitiated)
    #endif

    public init() {}

    /// Starts the loopback-only broker on `127.0.0.1` with an OS-assigned ephemeral port.
    @discardableResult
    public func start() async throws -> UInt16 {
        if port > 0 { return port }
        #if canImport(Network)
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        let newListener = try NWListener(using: params)
        self.listener = newListener

        final class ResumeOnceGate: @unchecked Sendable {
            private let lock = NSLock()
            private var done = false
            func tryAcquire() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                if done { return false }
                done = true
                return true
            }
        }
        let gate = ResumeOnceGate()
        let boundPort: UInt16 = try await withCheckedThrowingContinuation { continuation in
            newListener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let p = newListener.port?.rawValue, p > 0, gate.tryAcquire() {
                        continuation.resume(returning: p)
                    }
                case .failed(let err):
                    if gate.tryAcquire() {
                        continuation.resume(throwing: err)
                    }
                default:
                    break
                }
            }
            newListener.newConnectionHandler = { [weak self] conn in
                guard let self else {
                    conn.cancel()
                    return
                }
                Task {
                    await self.handleConnection(conn)
                }
            }
            newListener.start(queue: self.queue)
        }
        self.port = boundPort
        return boundPort
        #else
        return 0
        #endif
    }

    public func stop() {
        #if canImport(Network)
        listener?.cancel()
        listener = nil
        #endif
        port = 0
        leases.removeAll()
    }

    public func listeningPort() -> UInt16 {
        port
    }

    /// Issues an ephemeral per-process broker token bound to a single fixed upstream URL.
    public func issueLease(
        binding: PipiBrokerUpstreamBinding,
        ttlSeconds: TimeInterval = 3600
    ) async throws -> PipiCredentialBrokerLease {
        let activePort = try await start()
        let rawToken = "pipi_brk_\(Self.randomHex(20))"
        let exp = Date().addingTimeInterval(max(60, min(86_400, ttlSeconds)))
        leases[rawToken] = StoredLease(token: rawToken, binding: binding, expiresAt: exp)
        let proxyBase = "http://127.0.0.1:\(activePort)/b/\(rawToken)/\(binding.provider)"
        return PipiCredentialBrokerLease(
            token: rawToken,
            provider: binding.provider,
            proxyBaseURL: proxyBase,
            expiresAt: exp
        )
    }

    /// Revokes an ephemeral token immediately (call on child process exit).
    public func revokeLease(token: String) {
        leases.removeValue(forKey: token)
    }

    public func activeLeaseCount() -> Int {
        let now = Date()
        leases = leases.filter { $0.value.expiresAt > now }
        return leases.count
    }

    /// Produces a scrubbed child environment that removes all foreign/internal secrets
    /// and substitutes active broker leases (proxy token + loopback base URL).
    public nonisolated static func buildScrubbedEnvironment(
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        leases: [PipiCredentialBrokerLease] = [],
        extraAllowedEnv: [String: String] = [:]
    ) -> [String: String] {
        var env: [String: String] = [:]
        for (key, value) in baseEnvironment {
            if sensitiveForeignEnvKeys.contains(key) { continue }
            if key.hasPrefix("PIPIBOT_") { continue }
            env[key] = value
        }
        for (key, value) in extraAllowedEnv {
            if sensitiveForeignEnvKeys.contains(key) { continue }
            env[key] = value
        }
        for lease in leases {
            switch lease.provider.lowercased() {
            case "openai":
                env["OPENAI_API_KEY"] = lease.token
                env["OPENAI_BASE_URL"] = lease.proxyBaseURL
            case "anthropic":
                env["ANTHROPIC_API_KEY"] = lease.token
                env["ANTHROPIC_BASE_URL"] = lease.proxyBaseURL
            case "gemini", "google":
                env["GEMINI_API_KEY"] = lease.token
                env["GOOGLE_GEMINI_BASE_URL"] = lease.proxyBaseURL
            default:
                break
            }
        }
        return env
    }

    /// Resolves a broker path `/b/<token>/<provider>/<rest...>` into a pinned upstream request,
    /// stripping caller auth headers and injecting the real secret.
    public func resolveUpstreamRequest(
        method: String,
        rawPath: String,
        callerHeaders: [String: String],
        body: Data
    ) -> URLRequest? {
        guard rawPath.hasPrefix("/b/") else { return nil }
        let suffix = String(rawPath.dropFirst(3))
        let parts = suffix.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return nil }
        let token = parts[0]
        let provider = parts[1]
        let upstreamTail = parts.count == 3 ? "/\(parts[2])" : "/"

        guard let lease = leases[token],
              lease.expiresAt > Date(),
              lease.binding.provider.lowercased() == provider.lowercased() else {
            return nil
        }

        let baseStr = lease.binding.upstreamBaseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let targetURL = URL(string: "\(baseStr)\(upstreamTail)") else { return nil }

        var req = URLRequest(url: targetURL)
        req.httpMethod = method
        req.httpBody = body.isEmpty ? nil : body
        for (k, v) in callerHeaders {
            let lower = k.lowercased()
            if lower == "host" || lower == "authorization" || lower == "x-api-key" || lower == "x-goog-api-key" || lower == "content-length" {
                continue
            }
            req.setValue(v, forHTTPHeaderField: k)
        }
        req.setValue("\(lease.binding.authHeaderPrefix)\(lease.binding.realSecret)", forHTTPHeaderField: lease.binding.authHeaderName)
        return req
    }

    #if canImport(Network)
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(connection: connection, buffer: Data())
    }

    private nonisolated func receiveHTTPRequest(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var nextBuf = buffer
            if let data { nextBuf.append(data) }
            let separator = Data("\r\n\r\n".utf8)
            if let range = nextBuf.range(of: separator) {
                let headerData = nextBuf.subdata(in: 0..<range.lowerBound)
                let bodySoFar = nextBuf.subdata(in: range.upperBound..<nextBuf.count)
                let headerText = String(data: headerData, encoding: .utf8) ?? ""
                let contentLength = Self.parseContentLength(headerText)
                if bodySoFar.count >= contentLength || isComplete {
                    let body = bodySoFar.prefix(contentLength)
                    Task {
                        await self.dispatchHTTP(headerText: headerText, body: Data(body), connection: connection)
                    }
                    return
                }
            }
            if isComplete || error != nil || nextBuf.count > 10_000_000 {
                connection.cancel()
                return
            }
            self.receiveHTTPRequest(connection: connection, buffer: nextBuf)
        }
    }

    private func dispatchHTTP(headerText: String, body: Data, connection: NWConnection) async {
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendRawResponse(connection: connection, status: 400, body: Data("Bad Request".utf8))
            return
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendRawResponse(connection: connection, status: 400, body: Data("Bad Request".utf8))
            return
        }
        let method = String(parts[0])
        let path = String(parts[1])
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let idx = line.firstIndex(of: ":") {
                let k = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
                let v = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                headers[k] = v
            }
        }

        guard let upstreamReq = resolveUpstreamRequest(method: method, rawPath: path, callerHeaders: headers, body: body) else {
            sendRawResponse(connection: connection, status: 401, body: Data("{\"error\":\"invalid_or_revoked_broker_token\"}".utf8))
            return
        }

        do {
            let (respData, response) = try await URLSession.shared.data(for: upstreamReq)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "application/json"
            sendRawResponse(connection: connection, status: status, contentType: contentType, body: respData)
        } catch {
            sendRawResponse(connection: connection, status: 502, body: Data("{\"error\":\"upstream_unreachable\"}".utf8))
        }
    }

    private func sendRawResponse(
        connection: NWConnection,
        status: Int,
        contentType: String = "application/json; charset=utf-8",
        body: Data
    ) {
        let head = "HTTP/1.1 \(status) OK\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var payload = Data(head.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private nonisolated static func parseContentLength(_ headerText: String) -> Int {
        for line in headerText.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let val = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(val) ?? 0
            }
        }
        return 0
    }
    #endif

    private static func randomHex(_ byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for i in 0..<byteCount { bytes[i] = UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
