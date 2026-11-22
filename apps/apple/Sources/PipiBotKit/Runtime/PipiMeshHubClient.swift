// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// Multi-Machine Mesh Hub Client & Cross-Machine Handoff Protocol:
// - Connects Mac/iOS clients to local built-in Hub or remote 24h Linux VPS Hub
// - Lists all online Linux/Mac/GPU/VPS nodes & hosted Agents (zero workspace switching)
// - Dispatches non-blocking cross-machine tasks with live SSE progress & artifact relay
// - Parses `<pipi_handoff target="@agent" artifact="path">...</pipi_handoff>` for group handoffs

import Foundation
import Observation

public struct PipiMeshNodeTelemetry: Codable, Sendable, Equatable {
    public let cpuPercent: Double?
    public let memoryUsedGB: Double?
    public let memoryTotalGB: Double?
    public let diskFreeGB: Double?
    public let gpuSummary: String?

    public init(
        cpuPercent: Double? = nil,
        memoryUsedGB: Double? = nil,
        memoryTotalGB: Double? = nil,
        diskFreeGB: Double? = nil,
        gpuSummary: String? = nil
    ) {
        self.cpuPercent = cpuPercent
        self.memoryUsedGB = memoryUsedGB
        self.memoryTotalGB = memoryTotalGB
        self.diskFreeGB = diskFreeGB
        self.gpuSummary = gpuSummary
    }
}

public struct PipiMeshHostedAgent: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let role: String
    public let cliKinds: [String]

    public init(id: String, name: String, role: String, cliKinds: [String] = []) {
        self.id = id
        self.name = name
        self.role = role
        self.cliKinds = cliKinds
    }
}

public struct PipiMeshNodeInfo: Codable, Identifiable, Sendable, Equatable {
    public var id: String { nodeId }
    public let nodeId: String
    public let name: String
    public let platform: String
    public let arch: String
    public let hostname: String
    public let workspacePath: String
    public let capabilities: [String]
    public let cliAgents: [String]
    public let hostedAgents: [PipiMeshHostedAgent]
    public let telemetry: PipiMeshNodeTelemetry
    public let status: String
    public let activeTaskCount: Int
    public let lastHeartbeatAt: String
    public let streamConnected: Bool

    public var isOnline: Bool {
        status == "online" || status == "busy"
    }

    public var platformBadge: String {
        switch platform.lowercased() {
        case "darwin": return "macOS"
        case "linux": return "Linux"
        case "win32": return "Windows"
        default: return platform
        }
    }

    public init(
        nodeId: String,
        name: String,
        platform: String,
        arch: String,
        hostname: String,
        workspacePath: String = ".",
        capabilities: [String] = [],
        cliAgents: [String] = [],
        hostedAgents: [PipiMeshHostedAgent] = [],
        telemetry: PipiMeshNodeTelemetry = PipiMeshNodeTelemetry(),
        status: String = "online",
        activeTaskCount: Int = 0,
        lastHeartbeatAt: String = "",
        streamConnected: Bool = true
    ) {
        self.nodeId = nodeId
        self.name = name
        self.platform = platform
        self.arch = arch
        self.hostname = hostname
        self.workspacePath = workspacePath
        self.capabilities = capabilities
        self.cliAgents = cliAgents
        self.hostedAgents = hostedAgents
        self.telemetry = telemetry
        self.status = status
        self.activeTaskCount = activeTaskCount
        self.lastHeartbeatAt = lastHeartbeatAt
        self.streamConnected = streamConnected
    }
}

public struct PipiHandoffDirective: Sendable, Equatable {
    public let targetQuery: String
    public let artifactPath: String?
    public let instruction: String

    public init(targetQuery: String, artifactPath: String?, instruction: String) {
        self.targetQuery = targetQuery
        self.artifactPath = artifactPath
        self.instruction = instruction
    }
}

public enum PipiHandoffParser {
    /// Parses `<pipi_handoff target="@name" artifact="optional/path">instruction</pipi_handoff>`
    /// emitted by an Agent in a multi-machine group chat to hand off work to another Bot on any host.
    public static func extract(from rawText: String) -> (directive: PipiHandoffDirective, cleanedText: String)? {
        let pattern = #"<pipi_handoff\b([^>]*)>([\s\S]*?)</pipi_handoff>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsRange = NSRange(rawText.startIndex..<rawText.endIndex, in: rawText)
        guard let match = regex.firstMatch(in: rawText, options: [], range: nsRange),
              let fullRange = Range(match.range, in: rawText),
              let attrRange = Range(match.range(at: 1), in: rawText),
              let bodyRange = Range(match.range(at: 2), in: rawText) else {
            return nil
        }

        let attrs = String(rawText[attrRange])
        let body = String(rawText[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        let targetRaw = extractAttr("target", from: attrs) ?? ""
        let target = targetRaw.trimmingCharacters(in: CharacterSet(charactersIn: "@ \t\n"))
        guard !target.isEmpty else { return nil }
        let artifact = extractAttr("artifact", from: attrs)

        var cleaned = rawText
        cleaned.removeSubrange(fullRange)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return (PipiHandoffDirective(targetQuery: target, artifactPath: artifact, instruction: body), cleaned)
    }

    private static func extractAttr(_ name: String, from attrs: String) -> String? {
        let pattern = "\(name)\\s*=\\s*\"([^\"]+)\""
        guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = rx.firstMatch(in: attrs, range: NSRange(attrs.startIndex..<attrs.endIndex, in: attrs)),
              m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: attrs) else {
            return nil
        }
        let v = String(attrs[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }
}

public enum PipiMeshClientError: LocalizedError, Sendable {
    case invalidHubURL(String)
    case httpError(Int, String)
    case remoteTaskFailed(String)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .invalidHubURL(let u): return "无效的 Mesh Hub 地址：\(u)"
        case .httpError(let code, let body): return "Mesh Hub 返回错误 (HTTP \(code))：\(body)"
        case .remoteTaskFailed(let msg): return "远程节点执行失败：\(msg)"
        case .timedOut: return "等待远程节点返回超时"
        }
    }
}

@MainActor
@Observable
public final class PipiMeshHubClient {
    public var hubURLString: String = "http://127.0.0.1:4242"
    public var hubToken: String = ""
    public private(set) var nodes: [PipiMeshNodeInfo] = []
    public private(set) var isConnected: Bool = false
    public private(set) var lastSyncAt: Date? = nil
    public private(set) var lastError: String? = nil

    private let session: URLSession

    public init(hubURLString: String = "http://127.0.0.1:4242", hubToken: String = "", session: URLSession = .shared) {
        self.hubURLString = hubURLString
        self.hubToken = hubToken
        self.session = session
    }

    private var cleanBaseURL: String {
        hubURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }

    private func authorizedRequest(url: URL, method: String = "GET", body: Data? = nil, timeout: TimeInterval = 15) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = timeout
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let tok = hubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tok.isEmpty {
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    public func buildNodeJoinCommand(nodeName: String = "linux-gpu-1") -> String {
        let base = cleanBaseURL.isEmpty ? "http://<your-hub-ip>:4242" : cleanBaseURL
        let tok = hubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokFlag = tok.isEmpty ? "" : " --token \(tok)"
        return "node --experimental-strip-types packages/daemon/src/cli.ts node join --hub \(base) --name \(nodeName)\(tokFlag)"
    }

    @discardableResult
    public func refreshNodes() async -> [PipiMeshNodeInfo] {
        guard let url = URL(string: "\(cleanBaseURL)/api/v1/mesh/nodes") else {
            isConnected = false
            lastError = "Hub 地址无效"
            return []
        }
        do {
            let (data, resp) = try await session.data(for: authorizedRequest(url: url, timeout: 6))
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                isConnected = false
                lastError = "Hub 连接失败 (HTTP \(code))"
                return nodes
            }
            struct Envelope: Decodable { let nodes: [PipiMeshNodeInfo] }
            let decoded = try JSONDecoder().decode(Envelope.self, from: data)
            self.nodes = decoded.nodes
            self.isConnected = true
            self.lastSyncAt = Date()
            self.lastError = nil
            return decoded.nodes
        } catch {
            self.isConnected = false
            self.lastError = error.localizedDescription
            return nodes
        }
    }

    /// Uploads a local file to the Hub artifact relay so another host/node can consume it.
    public func uploadArtifact(fileURL: URL, sourceNodeId: String = "local-mac") async -> String? {
        guard let url = URL(string: "\(cleanBaseURL)/api/v1/mesh/artifacts"),
              let raw = try? Data(contentsOf: fileURL), !raw.isEmpty else {
            return nil
        }
        let (_, mime) = PipiDeliverableArtifact.inferKindAndMime(for: fileURL.path)
        let payload: [String: Any] = [
            "fileName": fileURL.lastPathComponent,
            "mimeType": mime,
            "contentBase64": raw.base64EncodedString(),
            "sourceNodeId": sourceNodeId
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        guard let (data, resp) = try? await session.data(for: authorizedRequest(url: url, method: "POST", body: body, timeout: 25)),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let art = root["artifact"] as? [String: Any],
              let artId = art["artifactId"] as? String else {
            return nil
        }
        return artId
    }

    /// Downloads a relayed artifact from Hub into the local deliverables folder.
    public func downloadArtifact(artifactId: String, deliverablesDir: URL) async -> PipiDeliverableArtifact? {
        guard let url = URL(string: "\(cleanBaseURL)/api/v1/mesh/artifacts/\(artifactId)") else { return nil }
        guard let (data, resp) = try? await session.data(for: authorizedRequest(url: url, timeout: 25)),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              !data.isEmpty else {
            return nil
        }
        let fileName = http.value(forHTTPHeaderField: "X-Pipi-Filename") ?? "\(artifactId).bin"
        try? FileManager.default.createDirectory(at: deliverablesDir, withIntermediateDirectories: true)
        let dest = deliverablesDir.appendingPathComponent("mesh_\(artifactId)_\(fileName)")
        do {
            try data.write(to: dest, options: [.atomic])
            let (kind, mime) = PipiDeliverableArtifact.inferKindAndMime(for: dest.path)
            return PipiDeliverableArtifact(
                id: artifactId,
                kind: kind,
                fileName: fileName,
                filePath: dest.path,
                mimeType: mime,
                byteSize: Int64(data.count)
            )
        } catch {
            return nil
        }
    }

    /// Dispatches a task to a remote Linux/Mac node and awaits completion while streaming step progress.
    public func dispatchAndAwaitTask(
        targetNodeId: String,
        prompt: String,
        botId: String?,
        botName: String?,
        groupId: String? = nil,
        topicId: String? = nil,
        handoffFromBot: String? = nil,
        handoffHop: Int = 0,
        artifactIds: [String] = [],
        onProgress: (@Sendable (String) async -> Void)? = nil
    ) async throws -> (text: String, artifactIds: [String]) {
        guard let dispatchURL = URL(string: "\(cleanBaseURL)/api/v1/mesh/dispatch") else {
            throw PipiMeshClientError.invalidHubURL(hubURLString)
        }
        var payload: [String: Any] = [
            "targetNodeId": targetNodeId,
            "prompt": prompt,
            "handoffHop": handoffHop,
            "artifactIds": artifactIds,
            "mode": "write"
        ]
        if let botId { payload["botId"] = botId }
        if let botName { payload["botName"] = botName }
        if let groupId { payload["groupId"] = groupId }
        if let topicId { payload["topicId"] = topicId }
        if let handoffFromBot { payload["handoffFromBot"] = handoffFromBot }

        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, resp) = try await session.data(for: authorizedRequest(url: dispatchURL, method: "POST", body: body, timeout: 15))
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let errText = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw PipiMeshClientError.httpError(http.statusCode, errText)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let taskObj = root["task"] as? [String: Any],
              let taskId = taskObj["taskId"] as? String else {
            throw PipiMeshClientError.remoteTaskFailed("未获取到远程任务 ID")
        }

        // Poll task state & emit unseen step events cleanly until completed/failed (works reliably across proxies & tunnels)
        var seenEventSeq = 0
        for _ in 0..<240 {
            if Task.isCancelled { throw CancellationError() }
            try? await Task.sleep(for: .milliseconds(450))
            guard let statusURL = URL(string: "\(cleanBaseURL)/api/v1/mesh/tasks/\(taskId)") else { continue }
            guard let (tData, tResp) = try? await session.data(for: authorizedRequest(url: statusURL, timeout: 10)),
                  let http = tResp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let tRoot = try? JSONSerialization.jsonObject(with: tData) as? [String: Any],
                  let tObj = tRoot["task"] as? [String: Any] else {
                continue
            }

            if let events = tObj["events"] as? [[String: Any]] {
                for ev in events {
                    let seq = (ev["seq"] as? Int) ?? 0
                    if seq > seenEventSeq {
                        seenEventSeq = seq
                        if let stepTitle = ev["stepTitle"] as? String, !stepTitle.isEmpty {
                            await onProgress?(stepTitle)
                        }
                    }
                }
            }

            let status = (tObj["status"] as? String) ?? "queued"
            if status == "completed" {
                let text = (tObj["outputText"] as? String) ?? "远程节点已完成执行。"
                let arts = (tObj["outputArtifactIds"] as? [String]) ?? []
                return (text, arts)
            } else if status == "failed" {
                let err = (tObj["error"] as? String) ?? "远程节点返回错误"
                throw PipiMeshClientError.remoteTaskFailed(err)
            }
        }
        throw PipiMeshClientError.timedOut
    }
}
