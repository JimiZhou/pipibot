// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// Zero-Knowledge E2EE Relay Client (`wss://pipibot.jimizhou.com/ws`),
// Four-Platform Interoperable P-256 ECDH + HKDF-SHA256 + AES-256-GCM Crypto,
// and Universal Pairing Link (`https://pipibot.jimizhou.com/c/<hostId>#t=...&k=...`) + Device Registry.

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

public struct PipiE2EEEnvelope: Codable, Sendable, Equatable {
    public let type: String
    public let v: Int
    public let hostId: String
    public let clientId: String
    public let sid: String
    public let clientPubKey: String?
    public let dir: String // "c2h" | "h2c"
    public let seq: Int
    public let nonce: String
    public let ct: String

    public init(
        type: String = "envelope",
        v: Int = 1,
        hostId: String,
        clientId: String,
        sid: String,
        clientPubKey: String? = nil,
        dir: String,
        seq: Int,
        nonce: String,
        ct: String
    ) {
        self.type = type
        self.v = v
        self.hostId = hostId
        self.clientId = clientId
        self.sid = sid
        self.clientPubKey = clientPubKey
        self.dir = dir
        self.seq = seq
        self.nonce = nonce
        self.ct = ct
    }
}

public enum PipiE2EECryptoError: Error, LocalizedError, Sendable {
    case cryptoUnavailable
    case invalidPublicKey
    case invalidEnvelope
    case replayDetected(Int, Int)
    case decryptFailed

    public var errorDescription: String? {
        switch self {
        case .cryptoUnavailable: return "CryptoKit unavailable on this platform"
        case .invalidPublicKey: return "Invalid P-256 uncompressed public key (expected 65 bytes)"
        case .invalidEnvelope: return "Malformed E2EE envelope"
        case .replayDetected(let got, let last): return "E2EE replay detected (seq \(got) <= \(last))"
        case .decryptFailed: return "E2EE authentication or decryption failed"
        }
    }
}

/// Bit-for-bit interoperable with `packages/relay/src/e2e.ts` (Node.js) and `pwa-bundle.ts` (Safari/Chrome WebCrypto).
public enum PipiE2EECrypto {
    public static func base64UrlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func base64UrlDecode(_ input: String) -> Data? {
        var normalized = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: normalized)
    }

    public static func sha256Hex(_ data: Data) -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        return data.prefix(16).map { String(format: "%02x", $0) }.joined()
        #endif
    }

    #if canImport(CryptoKit)
    public static func generateIdentity() -> (privateKeyRaw: Data, publicKeyB64Url: String, hostId: String) {
        let priv = P256.KeyAgreement.PrivateKey()
        let pubRaw65 = priv.publicKey.x963Representation
        let pubB64Url = base64UrlEncode(pubRaw65)
        let hostId = String(sha256Hex(pubRaw65).prefix(16))
        return (priv.rawRepresentation, pubB64Url, hostId)
    }

    public static func deriveSessionKey(
        ownPrivateKeyRaw: Data,
        peerPublicKeyB64Url: String,
        hostId: String,
        sessionId: String
    ) throws -> SymmetricKey {
        guard let peerRaw = base64UrlDecode(peerPublicKeyB64Url),
              peerRaw.count == 65,
              peerRaw.first == 0x04 else {
            throw PipiE2EECryptoError.invalidPublicKey
        }
        let ownPriv = try P256.KeyAgreement.PrivateKey(rawRepresentation: ownPrivateKeyRaw)
        let peerPub = try P256.KeyAgreement.PublicKey(x963Representation: peerRaw)
        let shared = try ownPriv.sharedSecretFromKeyAgreement(with: peerPub)
        let salt = Data("pipibot-e2ee-v1:\(hostId)".utf8)
        let info = Data("pipibot-aes256gcm-session:\(sessionId)".utf8)
        return shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: info,
            outputByteCount: 32
        )
    }

    public static func sealEnvelope(
        sessionKey: SymmetricKey,
        hostId: String,
        clientId: String,
        sid: String,
        dir: String,
        seq: Int,
        plaintextData: Data,
        clientPubKey: String? = nil
    ) throws -> PipiE2EEEnvelope {
        let nonce = AES.GCM.Nonce()
        let aad = Data("v1|\(sid)|\(dir)|\(seq)".utf8)
        let sealed = try AES.GCM.seal(plaintextData, using: sessionKey, nonce: nonce, authenticating: aad)
        var combined = Data()
        combined.append(sealed.ciphertext)
        combined.append(sealed.tag)
        return PipiE2EEEnvelope(
            hostId: hostId,
            clientId: clientId,
            sid: sid,
            clientPubKey: clientPubKey,
            dir: dir,
            seq: seq,
            nonce: base64UrlEncode(Data(nonce)),
            ct: base64UrlEncode(combined)
        )
    }

    public static func openEnvelope(
        sessionKey: SymmetricKey,
        envelope: PipiE2EEEnvelope,
        lastAcceptedSeq: Int? = nil
    ) throws -> Data {
        guard envelope.v == 1, envelope.seq > 0 else {
            throw PipiE2EECryptoError.invalidEnvelope
        }
        if let last = lastAcceptedSeq, envelope.seq <= last {
            throw PipiE2EECryptoError.replayDetected(envelope.seq, last)
        }
        guard let nonceData = base64UrlDecode(envelope.nonce),
              nonceData.count == 12,
              let combined = base64UrlDecode(envelope.ct),
              combined.count >= 16 else {
            throw PipiE2EECryptoError.invalidEnvelope
        }
        let ciphertext = combined.prefix(combined.count - 16)
        let tag = combined.suffix(16)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let aad = Data("v1|\(envelope.sid)|\(envelope.dir)|\(envelope.seq)".utf8)
        do {
            return try AES.GCM.open(box, using: sessionKey, authenticating: aad)
        } catch {
            throw PipiE2EECryptoError.decryptFailed
        }
    }
    #endif
}

/// Manages one-time pairing codes, paired remote devices, revocation, and bounded MCP scope enforcement.
public final class PipiDevicePairingRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var challenges: [String: PipiPairingChallenge] = [:]
    private var devices: [String: PipiPairedDevice] = [:]

    public init(initialDevices: [PipiPairedDevice] = []) {
        for d in initialDevices {
            devices[d.id] = d
        }
    }

    public func createChallenge(scope: PipiPairingScope = .owner, ttlSeconds: TimeInterval = 300) -> PipiPairingChallenge {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let part1 = String((0..<4).map { _ in alphabet.randomElement()! })
        let part2 = String((0..<4).map { _ in alphabet.randomElement()! })
        let code = "\(part1)-\(part2)"
        let challenge = PipiPairingChallenge(code: code, scope: scope, ttlSeconds: ttlSeconds)
        lock.lock()
        challenges[Self.normalizeCode(code)] = challenge
        lock.unlock()
        return challenge
    }

    public func redeemChallenge(
        code: String,
        label: String,
        clientPublicKeyB64: String? = nil,
        now: Date = Date()
    ) -> (device: PipiPairedDevice, rawToken: String)? {
        let norm = Self.normalizeCode(code)
        lock.lock()
        defer { lock.unlock() }
        guard var challenge = challenges[norm], challenge.isValid(at: now) else {
            return nil
        }
        challenge.consumed = true
        challenges[norm] = challenge

        let rawToken = "pipi_dev_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let tokenHash = PipiE2EECrypto.sha256Hex(Data(rawToken.utf8))
        let device = PipiPairedDevice(
            label: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Remote Device" : label,
            scope: challenge.scope,
            tokenHash: tokenHash,
            clientPublicKeyB64: clientPublicKeyB64,
            createdAt: now,
            lastSeenAt: now,
            revoked: false
        )
        devices[device.id] = device
        return (device, rawToken)
    }

    public func authorize(rawToken: String, requiredAction: String = "read") -> PipiPairedDevice? {
        let hash = PipiE2EECrypto.sha256Hex(Data(rawToken.utf8))
        lock.lock()
        defer { lock.unlock() }
        guard let matchedId = devices.first(where: { $0.value.tokenHash == hash && !$0.value.revoked })?.key,
              var dev = devices[matchedId] else {
            return nil
        }
        // Hard bounded MCP enforcement: mcp_bounded NEVER approves, merges, deletes, or reads secrets
        let privilegedActions: Set<String> = ["approve", "deny", "draft-approve", "evo-approve", "worktree-merge", "delete", "secret"]
        if privilegedActions.contains(requiredAction) && !dev.scope.allowsApprovalsAndMerge {
            return nil
        }
        if requiredAction == "mutate" && !dev.scope.allowsMutations {
            return nil
        }
        dev.lastSeenAt = Date()
        devices[matchedId] = dev
        return dev
    }

    public func listDevices() -> [PipiPairedDevice] {
        lock.lock()
        defer { lock.unlock() }
        return Array(devices.values).sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    public func revokeDevice(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard var dev = devices[id] else { return false }
        dev.revoked = true
        devices[id] = dev
        return true
    }

    private static func normalizeCode(_ code: String) -> String {
        code.uppercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
    }
}

/// Live WebSocket E2EE Relay Host Client connecting Mac App / Daemon to `https://pipibot.jimizhou.com`.
@MainActor
@Observable
public final class PipiE2EERelayClient {
    public static let defaultRelayOrigin = "https://pipibot.jimizhou.com"
    private static let identitySecretKey = "pipibot_e2ee_host_identity_v1"

    public private(set) var state: PipiRelayConnectionState = .disabled
    public private(set) var relayOrigin: String
    public private(set) var hostId: String = ""
    public private(set) var hostPublicKeyB64Url: String = ""
    public private(set) var lastPairingLink: PipiUniversalPairingLink?
    public private(set) var connectedClientCount: Int = 0
    public private(set) var lastStatusMessage: String?

    /// Optional unified-account metadata sent during `host_register` so this Mac appears in the user's Device Registry.
    public var accountAccessToken: String? = nil
    public var accountDeviceName: String? = nil
    public var accountCapabilities: [String] = []
    public var accountWorkspacePath: String? = nil

    public let pairingRegistry = PipiDevicePairingRegistry()

    private var privateKeyRaw: Data = Data()
    private let secretStore: any PipiSecretStore
    private var wsTask: URLSessionWebSocketTask?
    private var receiveLoopTask: Task<Void, Never>?
    private var session: URLSession = .shared
    #if canImport(CryptoKit)
    private var clientSessions: [String: (key: SymmetricKey, rxSeq: Int, txSeq: Int)] = [:]
    #endif
    private var requestHandler: (@Sendable (String, String, String?, Data?) async -> Data)?

    public init(
        relayOrigin: String = PipiE2EERelayClient.defaultRelayOrigin,
        secretStore: any PipiSecretStore = PipiLocalEncryptedSecretStore()
    ) {
        self.relayOrigin = relayOrigin.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.secretStore = secretStore
        loadOrCreateHostIdentity()
    }

    public func loadOrCreateHostIdentity() {
        #if canImport(CryptoKit)
        if let savedHex = secretStore.secret(for: Self.identitySecretKey),
           let raw = Data(base64Encoded: savedHex),
           let priv = try? P256.KeyAgreement.PrivateKey(rawRepresentation: raw) {
            let pubRaw = priv.publicKey.x963Representation
            self.privateKeyRaw = priv.rawRepresentation
            self.hostPublicKeyB64Url = PipiE2EECrypto.base64UrlEncode(pubRaw)
            self.hostId = String(PipiE2EECrypto.sha256Hex(pubRaw).prefix(16))
            return
        }
        let gen = PipiE2EECrypto.generateIdentity()
        self.privateKeyRaw = gen.privateKeyRaw
        self.hostPublicKeyB64Url = gen.publicKeyB64Url
        self.hostId = gen.hostId
        secretStore.setSecret(gen.privateKeyRaw.base64EncodedString(), for: Self.identitySecretKey)
        #endif
    }

    /// Generates the unified `https://pipibot.jimizhou.com/c/<hostId>#t=...&k=...` link & QR payload.
    public func generateUniversalPairingLink(
        scope: PipiPairingScope = .owner,
        lanHintURL: String? = nil,
        ttlSeconds: TimeInterval = 300
    ) -> PipiUniversalPairingLink {
        if hostId.isEmpty { loadOrCreateHostIdentity() }
        let challenge = pairingRegistry.createChallenge(scope: scope, ttlSeconds: ttlSeconds)
        let link = PipiUniversalPairingLink(
            relayOrigin: relayOrigin,
            hostId: hostId,
            hostPublicKeyB64Url: hostPublicKeyB64Url,
            oneTimeToken: challenge.code,
            lanHintURL: lanHintURL,
            expiresAt: challenge.expiresAt
        )
        self.lastPairingLink = link
        return link
    }

    public func start(
        relayOrigin: String? = nil,
        inviteKey: String? = nil,
        requestHandler: @escaping @Sendable (String, String, String?, Data?) async -> Data
    ) {
        if let origin = relayOrigin?.trimmingCharacters(in: CharacterSet(charactersIn: "/")), !origin.isEmpty {
            self.relayOrigin = origin
        }
        self.requestHandler = requestHandler
        if hostId.isEmpty { loadOrCreateHostIdentity() }
        connectLoop(inviteKey: inviteKey)
    }

    public func stop() {
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
        state = .disabled
        connectedClientCount = 0
        lastStatusMessage = "已停止远程 E2EE 中继"
    }

    public func handleSystemWake() {
        guard state == .connected || state == .reconnecting || state == .error,
              requestHandler != nil else { return }
        connectLoop(inviteKey: nil)
    }

    private func connectLoop(inviteKey: String?) {
        receiveLoopTask?.cancel()
        state = .connecting
        lastStatusMessage = "正在连接 \(relayOrigin)…"

        receiveLoopTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var backoffSeconds = 2
            while !Task.isCancelled {
                let wsOrigin = self.relayOrigin
                    .replacingOccurrences(of: "https://", with: "wss://")
                    .replacingOccurrences(of: "http://", with: "ws://")
                guard let wsURL = URL(string: "\(wsOrigin)/ws") else {
                    self.state = .error
                    self.lastStatusMessage = "无效的中继地址"
                    return
                }

                let task = self.session.webSocketTask(with: wsURL)
                self.wsTask = task
                task.resume()

                var regObj: [String: Any] = ["type": "host_register", "hostId": self.hostId]
                if let inviteKey, !inviteKey.isEmpty {
                    regObj["inviteKey"] = inviteKey
                }
                if let token = self.accountAccessToken, !token.isEmpty {
                    regObj["accessToken"] = token
                    regObj["hostPubKey"] = self.hostPublicKeyB64Url
                    regObj["platform"] = "macos"
                    if let devName = self.accountDeviceName, !devName.isEmpty {
                        regObj["deviceName"] = devName
                    }
                    if !self.accountCapabilities.isEmpty {
                        regObj["capabilities"] = self.accountCapabilities
                    }
                    if let wsPath = self.accountWorkspacePath, !wsPath.isEmpty {
                        regObj["workspacePath"] = wsPath
                    }
                }
                if let regData = try? JSONSerialization.data(withJSONObject: regObj),
                   let regStr = String(data: regData, encoding: .utf8) {
                    try? await task.send(.string(regStr))
                }

                let pingTask = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(25))
                        guard !Task.isCancelled else { return }
                        task.sendPing { error in
                            if error != nil {
                                task.cancel(with: .goingAway, reason: nil)
                            }
                        }
                    }
                }

                do {
                    while !Task.isCancelled {
                        let message = try await task.receive()
                        backoffSeconds = 2
                        if case .string(let text) = message {
                            await self.handleRelayFrame(text, wsTask: task)
                        }
                    }
                    pingTask.cancel()
                } catch {
                    pingTask.cancel()
                    if Task.isCancelled { return }
                    self.state = .reconnecting
                    self.lastStatusMessage = "中继连接波动，\(backoffSeconds)s 后自动重连…"
                    task.cancel(with: .goingAway, reason: nil)
                    try? await Task.sleep(for: .seconds(backoffSeconds))
                    backoffSeconds = min(20, backoffSeconds * 2)
                }
            }
        }
    }

    private func handleRelayFrame(_ rawText: String, wsTask: URLSessionWebSocketTask) async {
        guard let data = rawText.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "registered":
            state = .connected
            connectedClientCount = (json["clientsOnline"] as? Int) ?? 0
            lastStatusMessage = "已连接零知识 E2EE 中继（\(hostId)）"
        case "client_status":
            let online = (json["online"] as? Bool) ?? false
            connectedClientCount = max(0, connectedClientCount + (online ? 1 : -1))
        case "envelope":
            #if canImport(CryptoKit)
            await handleEncryptedEnvelope(data, wsTask: wsTask)
            #endif
        default:
            break
        }
    }

    #if canImport(CryptoKit)
    private func handleEncryptedEnvelope(_ rawData: Data, wsTask: URLSessionWebSocketTask) async {
        guard let env = try? JSONDecoder().decode(PipiE2EEEnvelope.self, from: rawData) else { return }
        let sessionKeyKey = "\(env.clientId):\(env.sid)"
        var sess = clientSessions[sessionKeyKey]
        if sess == nil, let clientPub = env.clientPubKey {
            if let derived = try? PipiE2EECrypto.deriveSessionKey(
                ownPrivateKeyRaw: privateKeyRaw,
                peerPublicKeyB64Url: clientPub,
                hostId: hostId,
                sessionId: env.sid
            ) {
                sess = (key: derived, rxSeq: 0, txSeq: 0)
            }
        }
        guard var active = sess else { return }
        guard let plain = try? PipiE2EECrypto.openEnvelope(
            sessionKey: active.key,
            envelope: env,
            lastAcceptedSeq: active.rxSeq
        ) else { return }
        active.rxSeq = env.seq

        guard let inner = (try? JSONSerialization.jsonObject(with: plain)) as? [String: Any],
              let kind = inner["kind"] as? String else {
            clientSessions[sessionKeyKey] = active
            return
        }

        if kind == "http_req",
           let reqId = inner["reqId"] as? String,
           let method = inner["method"] as? String,
           let path = inner["path"] as? String,
           let handler = requestHandler {
            let token = inner["token"] as? String
            var bodyData: Data? = nil
            if let bodyObj = inner["body"], !(bodyObj is NSNull) {
                bodyData = try? JSONSerialization.data(withJSONObject: bodyObj)
            }
            let respBytes = await handler(method, path, token, bodyData)
            let respJSON = (try? JSONSerialization.jsonObject(with: respBytes)) ?? ["raw": String(data: respBytes, encoding: .utf8) ?? ""]
            let replyInner: [String: Any] = [
                "kind": "http_res",
                "reqId": reqId,
                "body": respJSON
            ]
            if let replyPlain = try? JSONSerialization.data(withJSONObject: replyInner) {
                active.txSeq += 1
                if let sealed = try? PipiE2EECrypto.sealEnvelope(
                    sessionKey: active.key,
                    hostId: hostId,
                    clientId: env.clientId,
                    sid: env.sid,
                    dir: "h2c",
                    seq: active.txSeq,
                    plaintextData: replyPlain
                ),
                   let wireData = try? JSONEncoder().encode(sealed),
                   let wireText = String(data: wireData, encoding: .utf8) {
                    try? await wsTask.send(.string(wireText))
                }
            }
        }
        clientSessions[sessionKeyKey] = active
    }
    #endif
}
