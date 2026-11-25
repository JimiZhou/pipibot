import XCTest
@testable import PipiBotKit

final class PipiWeChatJarvisAndStreamContextTests: XCTestCase {

    func testQuietWeChatProgressGateSuppressesPreDeliverySpamAndAllowsSingleLongTaskCheckIn() async {
        let start = Date(timeIntervalSince1970: 1_764_000_000)
        let gate = PipiWeChatQuietProgressGate(
            startedAt: start,
            checkInDelaySeconds: 15.0,
            checkInMessage: "还在深挖核实，稍等我一下。"
        )

        // Rapid tool steps at t=0s, t=3s, t=8s, t=14s must stay completely silent on WeChat
        let m0 = await gate.messageToSend(now: start)
        let m3 = await gate.messageToSend(now: start.addingTimeInterval(3))
        let m8 = await gate.messageToSend(now: start.addingTimeInterval(8))
        let m14 = await gate.messageToSend(now: start.addingTimeInterval(14.9))
        XCTAssertNil(m0)
        XCTAssertNil(m3)
        XCTAssertNil(m8)
        XCTAssertNil(m14)

        // At t=16s (genuinely long task), emit AT MOST ONE calm human check-in
        let m16 = await gate.messageToSend(now: start.addingTimeInterval(16))
        XCTAssertEqual(m16, "还在深挖核实，稍等我一下。")

        // Subsequent steps at t=22s and t=40s must NEVER spam a second message
        let m22 = await gate.messageToSend(now: start.addingTimeInterval(22))
        let m40 = await gate.messageToSend(now: start.addingTimeInterval(40))
        XCTAssertNil(m22)
        XCTAssertNil(m40)
    }

    func testInfiniteStreamAutoTopicSegmentationReplaysTodayWeChatSession() {
        // Replays today's real conv_4c9047f5 sequence:
        // 00:11 Twitter news (HTTP 500) -> 00:57 Patreon Magic Lumix URL (46 min gap -> auto new topic!)
        // -> 01:00 background question (same topic) -> 01:02 follow-up "原理是什么" (same topic)
        // -> 01:04 explicit switch "顺便问一个问题..." (auto new topic!)
        var conv = PipiConversation(
            personaId: "bot_pipi_general",
            title: "微信 · PiPi · 全能助手",
            messages: [
                PipiChatMessage(
                    role: .user,
                    content: "帮我看看推特上面最近有什么新闻",
                    createdAt: "2026-11-25T00:11:22Z"
                ),
                PipiChatMessage(
                    role: .assistant,
                    content: "模型接口返回错误 (HTTP 500)",
                    createdAt: "2026-11-25T00:11:25Z",
                    isError: true
                )
            ]
        )

        let iso = ISO8601DateFormatter()
        let tPatreon = iso.date(from: "2026-11-25T00:57:56Z")!
        let d1 = PipiInfiniteStreamContextManager.applyAutoTopicSegmentation(
            to: &conv,
            incomingUserText: "https://www.patreon.com/MagicLumix/posts/lumix-s9-raw-and-176215797",
            now: tPatreon
        )
        XCTAssertTrue(d1.shouldSplit)
        XCTAssertEqual(d1.reason, .timeGap)
        XCTAssertEqual(conv.topicSegments.count, 1)
        XCTAssertEqual(conv.activeTopicStartIndex, 2)
        XCTAssertEqual(conv.compactionGeneration, 1)

        // Append the Patreon turn & assistant reply (visible stream stays 100% intact)
        conv.messages.append(PipiChatMessage(
            role: .user,
            content: "https://www.patreon.com/MagicLumix/posts/lumix-s9-raw-and-176215797",
            createdAt: "2026-11-25T00:57:56Z"
        ))
        conv.messages.append(PipiChatMessage(
            role: .assistant,
            content: "Magic Lumix 是 Andrew Reid 为松下 Lumix S9 做的第三方固件项目。",
            createdAt: "2026-11-25T00:58:10Z"
        ))

        // Follow-up 4 minutes later must stay in the same Magic Lumix topic!
        let tFollowUp = iso.date(from: "2026-11-25T01:02:48Z")!
        let d2 = PipiInfiniteStreamContextManager.applyAutoTopicSegmentation(
            to: &conv,
            incomingUserText: "Open gate和颜色直出，好像S9本来就有啊。然后这个第三方固件的原理是什么？他有透露吗",
            now: tFollowUp
        )
        XCTAssertFalse(d2.shouldSplit)
        XCTAssertEqual(conv.topicSegments.count, 1)

        conv.messages.append(PipiChatMessage(
            role: .user,
            content: "Open gate和颜色直出，好像S9本来就有啊。然后这个第三方固件的原理是什么？他有透露吗",
            createdAt: "2026-11-25T01:02:48Z"
        ))

        // Outbound prompt context must exclude the old Twitter HTTP 500 error turn!
        let window = PipiInfiniteStreamContextManager.buildBoundedPromptHistory(
            messages: conv.messages,
            topicSegments: conv.topicSegments,
            activeTopicStartIndex: conv.activeTopicStartIndex,
            activeTopicTitle: conv.activeTopicTitle
        )
        XCTAssertFalse(window.messages.contains(where: { $0.content.contains("HTTP 500") }))
        XCTAssertTrue(window.messages.contains(where: { $0.content.contains("MagicLumix") }))
        XCTAssertEqual(conv.messages.count, 5) // Non-destructive: all visible messages preserved!

        // Explicit topic switch phrase starts a brand new segment immediately
        let d3 = PipiInfiniteStreamContextManager.applyAutoTopicSegmentation(
            to: &conv,
            incomingUserText: "顺便问一个问题，新版 OMP 为什么把 Antigravity 登录去掉了",
            now: iso.date(from: "2026-11-25T01:04:00Z")!
        )
        XCTAssertTrue(d3.shouldSplit)
        XCTAssertEqual(d3.reason, .explicitCue)
        XCTAssertEqual(conv.topicSegments.count, 2)
    }

    func testBoundedPromptHistoryCapsInfinite72MessageStreamWithoutDeletingVisibleHistory() {
        var msgs: [PipiChatMessage] = []
        let base = Date(timeIntervalSince1970: 1_764_000_000)
        let iso = ISO8601DateFormatter()
        for i in 0..<72 {
            let role: PipiChatMessage.Role = i.isMultiple(of: 2) ? .user : .assistant
            let text = "Topic turn #\(i) " + String(repeating: "详细分析与代码上下文内容。", count: 20)
            msgs.append(PipiChatMessage(
                role: role,
                content: text,
                createdAt: iso.string(from: base.addingTimeInterval(Double(i) * 30))
            ))
        }

        let window = PipiInfiniteStreamContextManager.buildBoundedPromptHistory(
            messages: msgs,
            topicSegments: [],
            activeTopicStartIndex: 0,
            activeTopicTitle: "长流式对话",
            maxVerbatimMessages: 10,
            maxChars: 6_000
        )

        // Strictly bounded even for 72 long turns, while folding older active turns into rolling summary
        XCTAssertLessThanOrEqual(window.messages.count, 11) // 1 rolling capsule + <=10 verbatim
        XCTAssertGreaterThan(window.foldedActiveMessageCount, 50)
        XCTAssertLessThan(window.estimatedChars, 7_500)
        XCTAssertEqual(msgs.count, 72)
    }
}
