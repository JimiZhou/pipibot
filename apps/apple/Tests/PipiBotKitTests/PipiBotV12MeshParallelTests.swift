// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// Tests for v0.12.0 Multi-Machine Mesh Hub, Per-Task True Parallel Group Chat,
// Cross-Machine @Agent Handoff, Host-Bound Personas, and MCP + SKILL.md Ecosystem.

import Foundation
import Testing
@testable import PipiBotKit

private final class LockedExecutionCounter: @unchecked Sendable {
    private let lock = NSLock()
    var inFlight = 0
    var maxConcurrent = 0
    var completedPrompts: [String] = []

    func enter() {
        lock.lock()
        inFlight += 1
        if inFlight > maxConcurrent { maxConcurrent = inFlight }
        lock.unlock()
    }

    func leave(prompt: String) {
        lock.lock()
        inFlight -= 1
        completedPrompts.append(prompt)
        lock.unlock()
    }
}

@Suite("v0.12.0 Multi-Machine Mesh, True Parallel Group Lanes, Cross-Host Handoff & MCP/SKILL.md Ecosystem")
struct PipiBotV12MeshParallelTests {

    @Test("Per-task parallel group lanes execute two concurrent @mentions in the same group without cancelling or blocking each other")
    @MainActor
    func testTrueParallelNonBlockingGroupLanes() async {
        let counter = LockedExecutionCounter()
        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            secretStore: PipiInMemorySecretStore(),
            inferenceExecutor: { _, _, _, history, _, _ in
                counter.enter()
                try? await Task.sleep(for: .milliseconds(160))
                let last = history.last?.content ?? ""
                counter.leave(prompt: last)
                return PipiInferenceResult(text: "Done: \(last)", engineLabel: "TestMock")
            }
        )
        store.upsertLLMProvider(
            PipiLLMProviderConfig(
                id: "llm_par",
                name: "Mock",
                kind: .customOpenAI,
                baseURL: "https://api.example.com/v1",
                apiKey: "sk-par",
                modelId: "mock-model"
            ),
            setAsDefault: true
        )

        let group = store.createGroupChat(
            title: "Multi-Host Parallel Test",
            participantPersonaIds: ["bot_pipi_coder", "bot_pipi_writer"],
            swarmMode: .mentionOnly
        )

        // Fire two group messages back-to-back in the SAME group while the first is still running!
        let task1 = Task { @MainActor in
            await store.sendGroupMessage("@Coder 检查 CUDA 内存", toGroupId: group.id)
        }
        try? await Task.sleep(for: .milliseconds(30))
        let task2 = Task { @MainActor in
            await store.sendGroupMessage("@Writer 整理周报摘要", toGroupId: group.id)
        }

        await task1.value
        await task2.value

        // Both lanes must have overlapped concurrently (maxConcurrent >= 2) and BOTH must have completed!
        #expect(counter.maxConcurrent >= 2)
        #expect(counter.completedPrompts.count == 2)

        let finalGroup = store.groupChats.first(where: { $0.id == group.id })
        let botReplies = finalGroup?.messages.filter {
            if case .bot = $0.senderKind { return true }
            return false
        } ?? []
        #expect(botReplies.count == 2)
        #expect(botReplies.contains(where: { $0.content.contains("检查 CUDA 内存") }))
        #expect(botReplies.contains(where: { $0.content.contains("整理周报摘要") }))
    }

    @Test("Cross-machine @Agent handoff parser and group handoff execution trigger target teammate on another host seamlessly")
    @MainActor
    func testCrossMachineHandoffParserAndGroupExecution() async {
        let raw = "Linux-4090 检查完成，发现 OOM。<pipi_handoff target=\"@Coder\" artifact=\"logs/oom.txt\">请把 batch_size 从 64 调小到 32</pipi_handoff>"
        let parsed = PipiHandoffParser.extract(from: raw)
        #expect(parsed != nil)
        #expect(parsed?.directive.targetQuery == "Coder")
        #expect(parsed?.directive.artifactPath == "logs/oom.txt")
        #expect(parsed?.directive.instruction == "请把 batch_size 从 64 调小到 32")
        #expect(parsed?.cleanedText == "Linux-4090 检查完成，发现 OOM。")

        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            secretStore: PipiInMemorySecretStore(),
            inferenceExecutor: { _, _, _, history, _, _ in
                let last = history.last?.content ?? ""
                if last.contains("触发跨机接力") {
                    return PipiInferenceResult(
                        text: "GPU 节点已完成诊断。<pipi_handoff target=\"@Coder\">请修改训练脚本 batch_size=32</pipi_handoff>",
                        engineLabel: "Linux-4090"
                    )
                }
                return PipiInferenceResult(text: "Mac-Coder 已接手并修复 batch_size=32 ✅", engineLabel: "MacBook")
            }
        )
        store.upsertLLMProvider(
            PipiLLMProviderConfig(
                id: "llm_ho",
                name: "Mock",
                kind: .customOpenAI,
                baseURL: "https://api.example.com/v1",
                apiKey: "sk-ho",
                modelId: "mock-model"
            ),
            setAsDefault: true
        )

        let remoteNode = PipiMeshNodeInfo(
            nodeId: "node_linux_4090",
            name: "linux-4090",
            platform: "linux",
            arch: "x64",
            hostname: "gpu-box",
            workspacePath: "/workspace/train",
            cliAgents: ["codex"],
            telemetry: PipiMeshNodeTelemetry(gpuSummary: "RTX 4090 24GB")
        )
        let remoteBot = store.ensurePersonaForMeshNode(remoteNode)
        #expect(remoteBot.isRemoteHost)
        #expect(remoteBot.hostBadgeLabel(.zhHans) == "linux-4090")

        let group = store.createGroupChat(
            title: "跨机协作测试群",
            participantPersonaIds: [remoteBot.id, "bot_pipi_coder"],
            swarmMode: .mentionOnly
        )
        await store.sendGroupMessage("@\(remoteBot.nameZh) 触发跨机接力", toGroupId: group.id)
        try? await Task.sleep(for: .milliseconds(150))

        let msgs = store.groupChats.first(where: { $0.id == group.id })?.messages ?? []
        #expect(msgs.contains(where: { $0.content.contains("已跨机交接给") }))
        #expect(msgs.contains(where: { $0.content.contains("Mac-Coder 已接手并修复 batch_size=32") }))
    }

    @Test("Open-source SKILL.md frontmatter parser, host/bot scoping, and MCP tool schema bridging")
    @MainActor
    func testEcosystemSkillsAndMCPBridging() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipi-eco-test-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let md = """
        ---
        name: CUDA Profiler
        description: Profile PyTorch kernels on Linux GPUs
        tags: [cuda, gpu, linux]
        ---
        # CUDA Skill
        Always run `nsys profile` before guessing kernel bottlenecks.
        """
        let parsed = PipiSkillMarkdownParser.parse(md)
        #expect(parsed.name == "CUDA Profiler")
        #expect(parsed.tags == ["cuda", "gpu", "linux"])
        #expect(parsed.body.contains("nsys profile"))

        let skillFile = tmpDir.appendingPathComponent("SKILL.md")
        try md.write(to: skillFile, atomically: true, encoding: .utf8)

        let manager = PipiEcosystemManager(storageRootURL: tmpDir)
        let installed = await manager.installSkill(source: skillFile.path, scope: .host, targetId: "node_linux_4090")
        #expect(installed.name == "CUDA Profiler")

        // Scoped to node_linux_4090 -> present for that host, absent for local host
        let promptForLinux = manager.activeSkillsPromptSection(forPersonaId: "bot_1", hostId: "node_linux_4090")
        let promptForLocal = manager.activeSkillsPromptSection(forPersonaId: "bot_1", hostId: PipiHostDescriptor.localHostId)
        #expect(promptForLinux.contains("CUDA Profiler"))
        #expect(promptForLocal.isEmpty)

        // MCP tool descriptor bridges cleanly to PipiAgentToolDefinition
        let toolDesc = PipiMCPToolDescriptor(serverId: "mcp-fetch", name: "fetch_markdown", description: "Fetch URL as Markdown")
        let agentTool = toolDesc.toAgentToolDefinition()
        #expect(agentTool.name.contains("fetch_markdown"))
        #expect(agentTool.description.contains("MCP"))
    }
}
