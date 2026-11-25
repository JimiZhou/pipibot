import XCTest
@testable import PipiBotKit

final class PipiDiagramAndOrchestratorTests: XCTestCase {

    func testMarkdownParserExtractsFencedDiagramsAndRawInlineSvg() {
        let md = """
        ## ② 一帧怎么流过它

        ```mermaid title="稳定流水线"
        flowchart LR
          A["VPSS chn2"] -->|Y 平面| B["路径滤波"]:::warn
        ```

        | 子步 | 产出 |
        | --- | --- |
        | 切块 | 12 窗口 |

        <svg viewBox="0 0 200 60" onload="alert(1)"><title>波形图</title><script>bad()</script><path d="M0 30 L200 30"/></svg>
        """

        let blocks = PipiMarkdownParser.parseBlocks(md)
        let diagrams = blocks.compactMap { block -> (PipiDiagramKind, String, String?, Bool)? in
            if case .diagram(_, let kind, let source, let title, let isComplete) = block {
                return (kind, source, title, isComplete)
            }
            return nil
        }

        XCTAssertEqual(diagrams.count, 2)
        XCTAssertEqual(diagrams[0].0, .mermaid)
        XCTAssertEqual(diagrams[0].2, "稳定流水线")
        XCTAssertTrue(diagrams[0].3)

        XCTAssertEqual(diagrams[1].0, .svg)
        XCTAssertEqual(diagrams[1].2, "波形图")
        XCTAssertFalse(diagrams[1].1.contains("<script>"))
        XCTAssertFalse(diagrams[1].1.contains("onload="))
    }

    func testMarkdownParserHandlesUnclosedStreamingSvgGracefully() {
        let streaming = "正在分析：\n<svg viewBox=\"0 0 400 120\"><rect x=\"0\" y=\"0\""
        let blocks = PipiMarkdownParser.parseBlocks(streaming)
        guard let last = blocks.last,
              case .diagram(_, let kind, _, _, let isComplete) = last else {
            XCTFail("Expected trailing incomplete diagram block")
            return
        }
        XCTAssertEqual(kind, .svg)
        XCTAssertFalse(isComplete)
    }

    func testAgentOrchestratorValidatesWavesAndAutoWorktreeIsolation() {
        let plan = PipiOrchestrationPlan(
            goal: "Parallel refactor",
            supervisorId: "bot_lead",
            nodes: [
                PipiOrchestrationTaskNode(id: "scout", title: "Scout", prompt: "Inspect", rolePreset: .scout),
                PipiOrchestrationTaskNode(id: "c1", title: "Module A", prompt: "Edit A", rolePreset: .coder, harness: "codex", dependsOn: ["scout"]),
                PipiOrchestrationTaskNode(id: "c2", title: "Module B", prompt: "Edit B", rolePreset: .coder, harness: "claude-code", dependsOn: ["scout"]),
                PipiOrchestrationTaskNode(id: "rev", title: "Review", prompt: "Check", rolePreset: .reviewer, dependsOn: ["c1", "c2"])
            ]
        )

        let validation = PipiAgentOrchestrator.validate(plan)
        XCTAssertTrue(validation.valid)
        XCTAssertEqual(validation.waves, [["scout"], ["c1", "c2"], ["rev"]])
        XCTAssertEqual(Set(validation.autoIsolatedNodeIds), Set(["c1", "c2"]))
    }

    func testAgentOrchestratorExecutesDAGWithFallbackRetryVerifierAndSynthesis() async {
        let plan = PipiOrchestrationPlan(
            goal: "Ship inline diagrams",
            supervisorId: "bot_lead",
            nodes: [
                PipiOrchestrationTaskNode(id: "t1", title: "Inspect", prompt: "Read parser", rolePreset: .scout, actorId: "bot_scout"),
                PipiOrchestrationTaskNode(
                    id: "t2",
                    title: "Implement",
                    prompt: "Add diagram block",
                    rolePreset: .coder,
                    actorId: "bot_coder",
                    harness: "codex",
                    dependsOn: ["t1"],
                    maxRetries: 2,
                    fallbackHarnesses: ["claude-code"],
                    verifyWithActorId: "bot_verifier"
                )
            ],
            synthesizeFinal: true
        )

        actor Counter {
            var coderRuns = 0
            func nextCoderRun() -> Int {
                coderRuns += 1
                return coderRuns
            }
        }
        let counter = Counter()

        let result = await PipiAgentOrchestrator.execute(
            plan: plan,
            runNode: { req in
                if req.node.id == "t1" {
                    return PipiOrchestrationNodeResponse(output: "Parser located", succeeded: true, harnessUsed: "pi")
                }
                if req.node.id == "t2" {
                    let runNo = await counter.nextCoderRun()
                    if runNo == 1 {
                        return PipiOrchestrationNodeResponse(output: "", succeeded: false, errorMessage: "codex timeout")
                    }
                    let hasUpstream = req.upstreamContext.contains(where: { $0.fromNodeId == "t1" })
                    return PipiOrchestrationNodeResponse(
                        output: "Done with \(req.effectiveHarness ?? "default") (upstream=\(hasUpstream))",
                        succeeded: hasUpstream,
                        harnessUsed: req.effectiveHarness
                    )
                }
                return PipiOrchestrationNodeResponse(output: "All checks pass. VERDICT: APPROVE", succeeded: true)
            },
            synthesize: { goal, outcomes, _ in
                "Synthesis for \(goal): \(outcomes.count) tasks done"
            }
        )

        XCTAssertTrue(result.completed)
        XCTAssertEqual(result.wavesExecuted, 2)
        XCTAssertEqual(result.nodeOutcomes[1].harnessUsed, "claude-code")
        XCTAssertEqual(result.nodeOutcomes[1].verifiedApproved, true)
        XCTAssertTrue(result.finalOutput.contains("Synthesis for Ship inline diagrams: 2 tasks done"))
    }

    func testStructuredVerdictAndLeadPlanParsing() {
        let leadText = """
        @Scout: 调研渲染架构 [id: s1] [role: scout]
        @Coder: 实现内嵌 SVG [id: c1] [depends: s1] [role: coder] [harness: codex] [worktree]
        """
        let plan = PipiAgentOrchestrator.parsePlanFromLeadReply(
            text: leadText,
            goal: "画图能力",
            supervisorId: "lead",
            candidates: [
                (id: "bot_scout", nameZh: "Scout", nameEn: "Scout"),
                (id: "bot_coder", nameZh: "Coder", nameEn: "Coder")
            ]
        )
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.nodes.count, 2)
        XCTAssertEqual(plan?.nodes[1].dependsOn, ["s1"])
        XCTAssertEqual(plan?.nodes[1].harness, "codex")
        XCTAssertEqual(plan?.nodes[1].isolateWorktree, true)

        let verdict = PipiAgentOrchestrator.parseVerdict(
            from: "Diff looks clean.\nVERDICT: APPROVE\nSTATUS: DONE\nSELECT: bot_coder",
            candidateActorIds: ["bot_scout", "bot_coder"]
        )
        XCTAssertEqual(verdict.approved, true)
        XCTAssertEqual(verdict.done, true)
        XCTAssertEqual(verdict.selectedActorId, "bot_coder")
    }

    func testRenderDiagramToolboxSanitizesAndReturnsFencedBlock() async {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pipi-diag-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let callbacks = PipiAgentHostCallbacks(
            captureScreenshot: { PipiMacOmnipotentCommandResult(succeeded: false, summary: "") },
            recordScreen: { _ in PipiMacOmnipotentCommandResult(succeeded: false, summary: "") },
            synthesizeVoice: { _ in PipiMacOmnipotentCommandResult(succeeded: false, summary: "") },
            prepareLocalFile: { _ in PipiMacOmnipotentCommandResult(succeeded: false, summary: "") },
            registerArtifact: { _ in },
            delegateCLIAgent: { _, _, _, _ in (true, "ok") },
            readCalendarAndReminders: { "" },
            createRoutineOrReminder: { _, _, _, _ in "" },
            readMailOrSMS: { _, _ in "" },
            sendMailOrSMS: { _, _, _, _ in PipiMacOmnipotentCommandResult(succeeded: false, summary: "") },
            showControlMenu: { "" },
            listOrSwitchBot: { _ in "" },
            createBot: { _, _, _ in "" },
            switchSessionOrProject: { _, _ in "" },
            configureGroupMode: { _, _ in "" },
            updateSettings: { _, _ in "" },
            checkUpdates: { "" }
        )

        let call = PipiLLMToolCall(
            id: "diag_1",
            name: "render_diagram",
            argumentsJSON: "{\"kind\":\"svg\",\"title\":\"Data Flow\",\"source\":\"<svg viewBox='0 0 100 40'><script>x()</script><rect width='100' height='40'/></svg>\"}"
        )
        let res = await PipiAgentToolbox.execute(
            toolCall: call,
            workspaceDirectory: tmpDir.path,
            llmConfig: nil,
            deliverablesDirectory: tmpDir,
            callbacks: callbacks
        )
        XCTAssertFalse(res.isError)
        XCTAssertEqual(res.artifacts.count, 1)
        XCTAssertTrue(res.output.contains("```svg title=\"Data Flow\""))
        XCTAssertFalse(res.output.contains("<script>"))
    }
}
