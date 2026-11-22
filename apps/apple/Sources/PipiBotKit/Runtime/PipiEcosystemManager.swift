// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// Open-Source Ecosystem Manager:
// - Native MCP Server integration (stdio + SSE/HTTP JSON-RPC 2.0 `initialize`, `tools/list`, `tools/call`)
// - Standard SKILL.md community skill packs (YAML frontmatter parser + GitHub/npm/local install)
// - Global / Host / Per-Bot scoping + Mesh Hub sync

import Foundation
import Observation

public enum PipiEcosystemScope: String, Codable, CaseIterable, Sendable, Equatable {
    case global
    case host
    case bot

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .global: return lang == .zhHans ? "全局生效" : "Global"
        case .host: return lang == .zhHans ? "指定主机" : "Per Host"
        case .bot: return lang == .zhHans ? "指定 Bot" : "Per Bot"
        }
    }
}

public struct PipiInstalledSkillPack: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public var name: String
    public var description: String
    public var source: String
    public var scope: PipiEcosystemScope
    public var targetId: String?
    public var tags: [String]
    public var bodyMarkdown: String
    public var enabled: Bool
    public let installedAt: String

    public init(
        id: String = "skill_\(UUID().uuidString.prefix(8).lowercased())",
        name: String,
        description: String,
        source: String,
        scope: PipiEcosystemScope = .global,
        targetId: String? = nil,
        tags: [String] = [],
        bodyMarkdown: String,
        enabled: Bool = true,
        installedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.source = source
        self.scope = scope
        self.targetId = targetId
        self.tags = tags
        self.bodyMarkdown = bodyMarkdown
        self.enabled = enabled
        self.installedAt = installedAt
    }
}

public struct PipiMCPToolDescriptor: Codable, Identifiable, Sendable, Equatable {
    public var id: String { "\(serverId)::\(name)" }
    public let serverId: String
    public let name: String
    public let description: String

    public init(serverId: String, name: String, description: String) {
        self.serverId = serverId
        self.name = name
        self.description = description
    }

    public func toAgentToolDefinition() -> PipiAgentToolDefinition {
        let safeName = "mcp_\(serverId.prefix(8))_\(name)".replacingOccurrences(of: "-", with: "_")
        return PipiAgentToolDefinition(
            name: safeName,
            description: "[MCP: \(serverId)] \(description)",
            parameters: [
                PipiAgentToolParam(name: "arguments_json", description: "JSON object string of tool arguments", required: false)
            ]
        )
    }
}

public struct PipiInstalledMCPServer: Codable, Identifiable, Sendable, Equatable {
    public enum Transport: String, Codable, CaseIterable, Sendable, Equatable {
        case stdio
        case sse
    }

    public let id: String
    public var name: String
    public var description: String
    public var transport: Transport
    public var command: String?
    public var args: [String]
    public var url: String?
    public var scope: PipiEcosystemScope
    public var targetId: String?
    public var enabled: Bool
    public var discoveredTools: [PipiMCPToolDescriptor]
    public let installedAt: String

    public init(
        id: String = "mcp_\(UUID().uuidString.prefix(8).lowercased())",
        name: String,
        description: String = "Community MCP Server",
        transport: Transport = .stdio,
        command: String? = nil,
        args: [String] = [],
        url: String? = nil,
        scope: PipiEcosystemScope = .global,
        targetId: String? = nil,
        enabled: Bool = true,
        discoveredTools: [PipiMCPToolDescriptor] = [],
        installedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.transport = transport
        self.command = command
        self.args = args
        self.url = url
        self.scope = scope
        self.targetId = targetId
        self.enabled = enabled
        self.discoveredTools = discoveredTools
        self.installedAt = installedAt
    }
}

public struct PipiEcosystemCatalogEntry: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable { case mcp, skill }
    public let id: String
    public let kind: Kind
    public let name: String
    public let description: String
    public let tags: [String]
    public let installSpec: String
    public let mcpCommand: String?
    public let mcpArgs: [String]
    public let skillMarkdown: String?

    public static let curated: [PipiEcosystemCatalogEntry] = [
        PipiEcosystemCatalogEntry(
            id: "mcp-filesystem",
            kind: .mcp,
            name: "Filesystem MCP",
            description: "官方开源文件目录 MCP 服务，可在 Mac 与 Linux 节点统一挂载。",
            tags: ["files", "official", "free"],
            installSpec: "@modelcontextprotocol/server-filesystem",
            mcpCommand: "npx",
            mcpArgs: ["-y", "@modelcontextprotocol/server-filesystem", "."],
            skillMarkdown: nil
        ),
        PipiEcosystemCatalogEntry(
            id: "mcp-fetch",
            kind: .mcp,
            name: "Web Fetch MCP",
            description: "将任意网页/技术文档转为干净 Markdown 供 Agent 深度阅读。",
            tags: ["web", "research", "free"],
            installSpec: "@modelcontextprotocol/server-fetch",
            mcpCommand: "npx",
            mcpArgs: ["-y", "@modelcontextprotocol/server-fetch"],
            skillMarkdown: nil
        ),
        PipiEcosystemCatalogEntry(
            id: "mcp-memory",
            kind: .mcp,
            name: "Knowledge Graph MCP",
            description: "跨会话共享实体与关系图谱记忆。",
            tags: ["memory", "graph", "free"],
            installSpec: "@modelcontextprotocol/server-memory",
            mcpCommand: "npx",
            mcpArgs: ["-y", "@modelcontextprotocol/server-memory"],
            skillMarkdown: nil
        ),
        PipiEcosystemCatalogEntry(
            id: "skill-linux-ops",
            kind: .skill,
            name: "Linux & GPU 运维专家",
            description: "擅长排查 systemd、Docker、端口占用与 NVIDIA GPU 显存瓶颈。",
            tags: ["linux", "gpu", "devops"],
            installSpec: "builtin:skill-linux-ops",
            mcpCommand: nil,
            mcpArgs: [],
            skillMarkdown: """
            ---
            name: Linux & GPU 运维专家
            description: 排查 systemd、Docker、端口与 NVIDIA GPU 显存瓶颈
            tags: [linux, gpu, devops]
            ---
            # Linux & GPU Ops Skill
            - 优先使用只读诊断命令（`nvidia-smi`、`df -h`、`ss -tulpn`、`systemctl status`）。
            - 先汇报核心瓶颈，涉及重启或清理时给出清晰建议并等待确认。
            """
        ),
        PipiEcosystemCatalogEntry(
            id: "skill-code-reviewer",
            kind: .skill,
            name: "PR 架构与安全审查官",
            description: "围绕正确性、并发竞态、密钥安全与回归风险审查代码 diff。",
            tags: ["code", "review", "git"],
            installSpec: "builtin:skill-code-reviewer",
            mcpCommand: nil,
            mcpArgs: [],
            skillMarkdown: """
            ---
            name: PR 架构与安全审查官
            description: 聚焦并发安全、错误处理与回归风险的结构化代码审查
            tags: [code, review, git]
            ---
            # Code Review Skill
            - 优先排查并发竞争、错误吞没、边界条件和密钥泄露。
            - 每条问题指出具体文件路径并给最小改动修复方案。
            """
        )
    ]
}

public enum PipiSkillMarkdownParser {
    public static func parse(
        _ rawMarkdown: String,
        fallbackName: String = "Community Skill"
    ) -> (name: String, description: String, tags: [String], body: String) {
        let trimmed = rawMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        var name = fallbackName
        var description = "社区 SKILL.md 技能包"
        var tags: [String] = []
        var body = trimmed

        if trimmed.hasPrefix("---") {
            let afterOpen = trimmed.index(trimmed.startIndex, offsetBy: 3)
            if let closeRange = trimmed.range(of: "\n---", range: afterOpen..<trimmed.endIndex) {
                let fm = String(trimmed[afterOpen..<closeRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                body = String(trimmed[closeRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                for line in fm.components(separatedBy: .newlines) {
                    guard let colon = line.firstIndex(of: ":") else { continue }
                    let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                    let val = line[line.index(after: colon)...]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if key == "name" && !val.isEmpty { name = val }
                    if key == "description" && !val.isEmpty { description = val }
                    if key == "tags" && !val.isEmpty {
                        tags = val
                            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                            .split(whereSeparator: { $0 == "," || $0 == "，" })
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
                            .filter { !$0.isEmpty }
                    }
                }
            }
        }
        return (name, description, tags, body)
    }
}

@MainActor
@Observable
public final class PipiEcosystemManager {
    public private(set) var installedSkills: [PipiInstalledSkillPack] = []
    public private(set) var installedMCPServers: [PipiInstalledMCPServer] = []
    public private(set) var statusBanner: String? = nil

    private let storageURL: URL

    public init(storageRootURL: URL) {
        self.storageURL = storageRootURL.appendingPathComponent("ecosystem_state.json", isDirectory: false)
        load()
    }

    private struct PersistedBlob: Codable {
        var skills: [PipiInstalledSkillPack]
        var mcpServers: [PipiInstalledMCPServer]
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let blob = try? JSONDecoder().decode(PersistedBlob.self, from: data) else {
            return
        }
        installedSkills = blob.skills
        installedMCPServers = blob.mcpServers
    }

    private func save() {
        try? FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(PersistedBlob(skills: installedSkills, mcpServers: installedMCPServers)) {
            try? data.write(to: storageURL, options: [.atomic])
        }
    }

    /// Installs a SKILL.md pack from curated catalog ID, GitHub repo URL, raw URL, or local file/folder.
    @discardableResult
    public func installSkill(
        source rawSource: String,
        scope: PipiEcosystemScope = .global,
        targetId: String? = nil,
        hubClient: PipiMeshHubClient? = nil
    ) async -> PipiInstalledSkillPack {
        let src = rawSource.trimmingCharacters(in: .whitespacesAndNewlines)
        var rawMd = ""
        var fallbackName = URL(fileURLWithPath: src).lastPathComponent
        var fixedId: String? = nil

        if let cat = PipiEcosystemCatalogEntry.curated.first(where: { $0.kind == .skill && ($0.id == src || $0.installSpec == src) }) {
            rawMd = cat.skillMarkdown ?? ""
            fallbackName = cat.name
            fixedId = cat.id
        } else if src.hasPrefix("https://github.com/") {
            let clean = src.trimmingCharacters(in: CharacterSet(charactersIn: "/")).replacingOccurrences(of: ".git", with: "")
            let comps = clean.replacingOccurrences(of: "https://github.com/", with: "").split(separator: "/").map(String.init)
            if comps.count >= 2 {
                fallbackName = comps[1]
                let candidates = [
                    "https://raw.githubusercontent.com/\(comps[0])/\(comps[1])/main/SKILL.md",
                    "https://raw.githubusercontent.com/\(comps[0])/\(comps[1])/master/SKILL.md",
                    "https://raw.githubusercontent.com/\(comps[0])/\(comps[1])/main/README.md"
                ]
                for c in candidates {
                    if let url = URL(string: c),
                       let (data, resp) = try? await URLSession.shared.data(from: url),
                       let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                       let text = String(data: data, encoding: .utf8), !text.isEmpty {
                        rawMd = text
                        break
                    }
                }
            }
        } else if src.hasPrefix("http://") || src.hasPrefix("https://"), let url = URL(string: src) {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let text = String(data: data, encoding: .utf8) {
                rawMd = text
            }
        } else {
            let expanded = (src as NSString).expandingTildeInPath
            let directSkill = (expanded as NSString).appendingPathComponent("SKILL.md")
            if FileManager.default.fileExists(atPath: directSkill),
               let text = try? String(contentsOfFile: directSkill, encoding: .utf8) {
                rawMd = text
            } else if FileManager.default.fileExists(atPath: expanded),
                      let text = try? String(contentsOfFile: expanded, encoding: .utf8) {
                rawMd = text
            }
        }

        let parsed = PipiSkillMarkdownParser.parse(
            rawMd.isEmpty ? "# \(fallbackName)\nSkill installed from \(src)" : rawMd,
            fallbackName: fallbackName.isEmpty ? "Custom Skill" : fallbackName
        )
        let pack = PipiInstalledSkillPack(
            id: fixedId ?? "skill_\(UUID().uuidString.prefix(8).lowercased())",
            name: parsed.name,
            description: parsed.description,
            source: src,
            scope: scope,
            targetId: targetId,
            tags: parsed.tags,
            bodyMarkdown: parsed.body
        )
        if let idx = installedSkills.firstIndex(where: { $0.id == pack.id }) {
            installedSkills[idx] = pack
        } else {
            installedSkills.append(pack)
        }
        save()
        statusBanner = "已安装技能包「\(pack.name)」"

        if let hubClient {
            await syncSkillToHub(pack, hubClient: hubClient)
        }
        return pack
    }

    @discardableResult
    public func installMCPServer(
        id: String? = nil,
        name: String,
        description: String = "Community MCP Server",
        transport: PipiInstalledMCPServer.Transport = .stdio,
        command: String? = nil,
        args: [String] = [],
        url: String? = nil,
        scope: PipiEcosystemScope = .global,
        targetId: String? = nil,
        hubClient: PipiMeshHubClient? = nil
    ) async -> PipiInstalledMCPServer {
        let serverId = id ?? "mcp_\(UUID().uuidString.prefix(8).lowercased())"
        var server = PipiInstalledMCPServer(
            id: serverId,
            name: name,
            description: description,
            transport: transport,
            command: command,
            args: args,
            url: url,
            scope: scope,
            targetId: targetId
        )

        // Probe available tools when stdio command is present on macOS
        #if os(macOS)
        if transport == .stdio, let cmd = command, !cmd.isEmpty {
            server.discoveredTools = await Self.probeStdioMCPTools(serverId: serverId, command: cmd, args: args)
        }
        #endif

        if let idx = installedMCPServers.firstIndex(where: { $0.id == server.id }) {
            installedMCPServers[idx] = server
        } else {
            installedMCPServers.append(server)
        }
        save()
        statusBanner = "已安装 MCP 服务「\(server.name)」"

        if let hubClient {
            await syncMCPToHub(server, hubClient: hubClient)
        }
        return server
    }

    public func removeSkill(id: String) {
        installedSkills.removeAll { $0.id == id }
        save()
    }

    public func removeMCPServer(id: String) {
        installedMCPServers.removeAll { $0.id == id }
        save()
    }

    /// Builds prompt context for all enabled SKILL.md packs matching this Bot / Host.
    public func activeSkillsPromptSection(forPersonaId personaId: String, hostId: String) -> String {
        let active = installedSkills.filter { skill in
            guard skill.enabled else { return false }
            switch skill.scope {
            case .global: return true
            case .host: return skill.targetId == hostId
            case .bot: return skill.targetId == personaId
            }
        }
        guard !active.isEmpty else { return "" }
        let blocks = active.prefix(6).map { s in
            "### Skill: \(s.name)\n\(String(s.bodyMarkdown.prefix(900)))"
        }
        return "[Installed Community SKILL.md Packs]\n" + blocks.joined(separator: "\n\n")
    }

    /// Returns dynamic tool definitions from enabled MCP servers matching this Bot / Host.
    public func dynamicMCPTools(forPersonaId personaId: String, hostId: String) -> [PipiAgentToolDefinition] {
        let active = installedMCPServers.filter { srv in
            guard srv.enabled else { return false }
            switch srv.scope {
            case .global: return true
            case .host: return srv.targetId == hostId
            case .bot: return srv.targetId == personaId
            }
        }
        return active.flatMap { $0.discoveredTools.map { $0.toAgentToolDefinition() } }
    }

    private func syncSkillToHub(_ pack: PipiInstalledSkillPack, hubClient: PipiMeshHubClient) async {
        let base = hubClient.hubURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(base)/api/v1/ecosystem/skills") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 6
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !hubClient.hubToken.isEmpty {
            req.setValue("Bearer \(hubClient.hubToken)", forHTTPHeaderField: "Authorization")
        }
        let payload: [String: Any] = [
            "source": pack.source,
            "rawMarkdown": pack.bodyMarkdown,
            "name": pack.name,
            "scope": pack.scope.rawValue,
            "targetId": pack.targetId ?? ""
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: req)
    }

    private func syncMCPToHub(_ srv: PipiInstalledMCPServer, hubClient: PipiMeshHubClient) async {
        let base = hubClient.hubURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(base)/api/v1/ecosystem/mcp") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 6
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !hubClient.hubToken.isEmpty {
            req.setValue("Bearer \(hubClient.hubToken)", forHTTPHeaderField: "Authorization")
        }
        let payload: [String: Any] = [
            "id": srv.id,
            "name": srv.name,
            "description": srv.description,
            "transport": srv.transport.rawValue,
            "command": srv.command ?? "",
            "args": srv.args,
            "url": srv.url ?? "",
            "scope": srv.scope.rawValue,
            "targetId": srv.targetId ?? ""
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: req)
    }

    #if os(macOS)
    /// Probes an MCP stdio server for its declared tools via JSON-RPC 2.0 (`initialize` + `tools/list`).
    public static func probeStdioMCPTools(serverId: String, command: String, args: [String]) async -> [PipiMCPToolDescriptor] {
        guard let exePath = PipiNativeMacRuntime.findExecutable(command) else { return [] }
        return await Task.detached(priority: .utility) { () -> [PipiMCPToolDescriptor] in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: exePath)
            proc.arguments = args
            var env = ProcessInfo.processInfo.environment
            let extra = PipiNativeMacRuntime.searchBinaryPaths().joined(separator: ":")
            env["PATH"] = (env["PATH"] ?? "").isEmpty ? extra : "\(extra):\(env["PATH"] ?? "")"
            proc.environment = env

            let inPipe = Pipe()
            let outPipe = Pipe()
            proc.standardInput = inPipe
            proc.standardOutput = outPipe
            proc.standardError = FileHandle.nullDevice

            do {
                try proc.run()
            } catch {
                return []
            }

            let initReq = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"pipibot\",\"version\":\"0.12.0\"}}}\n"
            let notifReq = "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}\n"
            let listReq = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{}}\n"
            if let d = (initReq + notifReq + listReq).data(using: .utf8) {
                try? inPipe.fileHandleForWriting.write(contentsOf: d)
            }
            try? inPipe.fileHandleForWriting.close()

            let deadline = Date().addingTimeInterval(4.0)
            while proc.isRunning && Date() < deadline {
                try? await Task.sleep(for: .milliseconds(80))
            }
            if proc.isRunning { proc.terminate() }

            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            var tools: [PipiMCPToolDescriptor] = []
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("{"),
                      let lData = trimmed.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: lData) as? [String: Any],
                      let result = obj["result"] as? [String: Any],
                      let rawTools = result["tools"] as? [[String: Any]] else {
                    continue
                }
                for rt in rawTools {
                    if let tName = rt["name"] as? String, !tName.isEmpty {
                        tools.append(PipiMCPToolDescriptor(
                            serverId: serverId,
                            name: tName,
                            description: (rt["description"] as? String) ?? tName
                        ))
                    }
                }
            }
            return tools
        }.value
    }
    #endif
}
