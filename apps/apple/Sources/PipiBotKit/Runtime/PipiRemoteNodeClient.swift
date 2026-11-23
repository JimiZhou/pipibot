// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// Primary Control Plane -> Remote Enrolled Node E2EE RPC Client:
// Connects over `wss://pipibot.jimizhou.com/ws` as a same-account E2EE peer to any
// enrolled remote device (CLI daemon `pipibot up` or another PiPiBot desktop),
// enabling automatic remote agent harness invocation and direct troubleshooting/dev actions.

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

public struct PipiRemoteNodeLiveTelemetry: Sendable, Equatable {
    public let hostId: String
    public let hostname: String
    public let platform: String
    public let arch: String
    public let cpuCount: Int
    public let totalMemoryMB: Int
    public let freeMemoryMB: Int
    public let uptimeSeconds: Int
    public let workspacePath: String
    public let gitBranch: String?
    public let gitDirtyCount: Int?
    public let activeSessions: Int
    public let installedAgentNames: [String]
    public let refreshedAt: Date

    public var usedMemoryMB: Int { max(0, totalMemoryMB - freeMemoryMB) }
    public var memoryUsageRatio: Double {
        guard totalMemoryMB > 0 else { return 0 }
        return min(1.0, max(0.0, Double(usedMemoryMB) / Double(totalMemoryMB)))
    }
    public var formattedUptime: String {
        let days = uptimeSeconds / 86400
        let hours = (uptimeSeconds % 86400) / 3600
        let mins = (uptimeSeconds % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(max(1, mins))m"
    }
}

public struct PipiRemoteNodeRPCResult: Sendable {
    public let ok: Bool
    public let status: Int
    public let bodyData: Data
    public let rawText: String
    public let errorMessage: String?

    public var body: [String: Any] {
        (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] ?? [:]
    }

    public init(ok: Bool, status: Int, bodyData: Data = Data(), rawText: String, errorMessage: String? = nil) {
        self.ok = ok
        self.status = status
        self.bodyData = bodyData
        self.rawText = rawText
        self.errorMessage = errorMessage
    }
}

public enum PipiRemoteNodeClient {
    /// Sends a single end-to-end encrypted RPC request to a remote enrolled node via the zero-knowledge relay.
    public static func sendEncryptedRPC(
        relayOrigin: String,
        targetHostId: String,
        targetHostPubKey: String,
        accountAccessToken: String,
        method: String,
        path: String,
        bodyJSONData: Data? = nil,
        timeoutSeconds: TimeInterval = 30
    ) async -> PipiRemoteNodeRPCResult {
        #if canImport(CryptoKit)
        let wsOrigin = relayOrigin
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        guard let wsURL = URL(string: "\(wsOrigin)/ws") else {
            return PipiRemoteNodeRPCResult(ok: false, status: 0, rawText: "", errorMessage: "无效的中继服务地址")
        }

        let identity = PipiE2EECrypto.generateIdentity()
        let clientId = "macctrl_\(UUID().uuidString.prefix(10).lowercased())"
        let sid = "s_\(UUID().uuidString.prefix(12).lowercased())"
        let reqId = "r_\(UUID().uuidString.prefix(10).lowercased())"

        let sessionKey: SymmetricKey
        do {
            sessionKey = try PipiE2EECrypto.deriveSessionKey(
                ownPrivateKeyRaw: identity.privateKeyRaw,
                peerPublicKeyB64Url: targetHostPubKey,
                hostId: targetHostId,
                sessionId: sid
            )
        } catch {
            return PipiRemoteNodeRPCResult(
                ok: false,
                status: 0,
                rawText: "",
                errorMessage: "无法与目标节点建立端到端加密会话：\(error.localizedDescription)"
            )
        }

        let wsTask = URLSession.shared.webSocketTask(with: wsURL)
        wsTask.resume()
        defer { wsTask.cancel(with: .goingAway, reason: nil) }

        // 1. Join target host room
        let joinFrame: [String: Any] = [
            "type": "client_join",
            "hostId": targetHostId,
            "clientId": clientId
        ]
        guard let joinData = try? JSONSerialization.data(withJSONObject: joinFrame),
              let joinText = String(data: joinData, encoding: .utf8) else {
            return PipiRemoteNodeRPCResult(ok: false, status: 0, rawText: "", errorMessage: "构造握手帧失败")
        }

        do {
            try await wsTask.send(.string(joinText))
        } catch {
            return PipiRemoteNodeRPCResult(ok: false, status: 0, rawText: "", errorMessage: "连接中继失败：\(error.localizedDescription)")
        }

        // 2. Seal encrypted RPC request (compatible with both daemon `id` and Mac `reqId`)
        var reqPayload: [String: Any] = [
            "kind": "http_req",
            "id": reqId,
            "reqId": reqId,
            "method": method.uppercased(),
            "path": path,
            "token": accountAccessToken
        ]
        if let bodyJSONData,
           let parsedBody = try? JSONSerialization.jsonObject(with: bodyJSONData) {
            reqPayload["body"] = parsedBody
        }

        guard let plainData = try? JSONSerialization.data(withJSONObject: reqPayload),
              let sealed = try? PipiE2EECrypto.sealEnvelope(
                sessionKey: sessionKey,
                hostId: targetHostId,
                clientId: clientId,
                sid: sid,
                dir: "c2h",
                seq: 1,
                plaintextData: plainData,
                clientPubKey: identity.publicKeyB64Url
              ),
              let envData = try? JSONEncoder().encode(sealed),
              let envText = String(data: envData, encoding: .utf8) else {
            return PipiRemoteNodeRPCResult(ok: false, status: 0, rawText: "", errorMessage: "加密请求失败")
        }

        do {
            try await wsTask.send(.string(envText))
        } catch {
            return PipiRemoteNodeRPCResult(ok: false, status: 0, rawText: "", errorMessage: "发送加密请求失败：\(error.localizedDescription)")
        }

        // 3. Await matching encrypted response with bounded timeout
        let deadline = Date().addingTimeInterval(max(3, timeoutSeconds))
        while Date() < deadline {
            let remaining = max(0.5, deadline.timeIntervalSinceNow)
            let frameResult: Result<URLSessionWebSocketTask.Message, Error>? = await withTaskGroup(of: Result<URLSessionWebSocketTask.Message, Error>?.self) { group in
                group.addTask {
                    do {
                        return .success(try await wsTask.receive())
                    } catch {
                        return .failure(error)
                    }
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(remaining))
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }

            guard let frameResult else {
                return PipiRemoteNodeRPCResult(ok: false, status: 504, rawText: "", errorMessage: "等待远程节点响应超时（\(Int(timeoutSeconds))s）")
            }

            switch frameResult {
            case .failure(let err):
                return PipiRemoteNodeRPCResult(ok: false, status: 0, rawText: "", errorMessage: "远程连接中断：\(err.localizedDescription)")
            case .success(let message):
                guard case .string(let text) = message,
                      let data = text.data(using: .utf8),
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let type = json["type"] as? String else {
                    continue
                }
                if type == "joined" {
                    if let hostOnline = json["hostOnline"] as? Bool, !hostOnline {
                        return PipiRemoteNodeRPCResult(ok: false, status: 503, rawText: "", errorMessage: "目标节点当前不在线，请确认该机器已运行 `pipibot up` 或 PiPiBot 客户端")
                    }
                    continue
                }
                if type == "error" {
                    let msg = (json["message"] as? String) ?? (json["error"] as? String) ?? "中继返回错误"
                    return PipiRemoteNodeRPCResult(ok: false, status: 502, rawText: "", errorMessage: msg)
                }
                if type == "envelope",
                   let env = try? JSONDecoder().decode(PipiE2EEEnvelope.self, from: data),
                   env.dir == "h2c",
                   let opened = try? PipiE2EECrypto.openEnvelope(sessionKey: sessionKey, envelope: env),
                   let inner = (try? JSONSerialization.jsonObject(with: opened)) as? [String: Any] {
                    let respId = (inner["reqId"] as? String) ?? (inner["id"] as? String)
                    if let respId, respId != reqId { continue }
                    let status = (inner["status"] as? Int) ?? 200
                    let bodyDict = (inner["body"] as? [String: Any]) ?? inner
                    let bodyBytes = (try? JSONSerialization.data(withJSONObject: bodyDict)) ?? opened
                    let rawPretty: String
                    if let d = try? JSONSerialization.data(withJSONObject: bodyDict, options: [.prettyPrinted, .sortedKeys]),
                       let s = String(data: d, encoding: .utf8) {
                        rawPretty = s
                    } else {
                        rawPretty = String(data: opened, encoding: .utf8) ?? ""
                    }
                    let errMsg = (bodyDict["error"] as? String)
                    return PipiRemoteNodeRPCResult(
                        ok: status >= 200 && status < 300 && errMsg == nil,
                        status: status,
                        bodyData: bodyBytes,
                        rawText: rawPretty,
                        errorMessage: errMsg
                    )
                }
            }
        }

        return PipiRemoteNodeRPCResult(ok: false, status: 504, rawText: "", errorMessage: "等待远程节点响应超时")
        #else
        return PipiRemoteNodeRPCResult(ok: false, status: 0, rawText: "", errorMessage: "当前平台不支持 CryptoKit")
        #endif
    }
}
