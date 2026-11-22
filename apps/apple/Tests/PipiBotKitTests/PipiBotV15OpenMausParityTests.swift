// PiPiBot — Clean-room MIT implementation.
// v0.15.0 OpenMausBot Parity + Zero-Knowledge E2EE Relay + Bug Fixes Test Suite.

import Foundation
import Testing
@testable import PipiBotKit

@Suite("PiPiBot v0.15.0 OpenMausBot Parity & E2EE Relay")
struct PipiBotV15OpenMausParityTests {

    @Test("Zero-Knowledge E2EE P-256 ECDH + HKDF-SHA256 + AES-256-GCM round-trip, anti-replay & universal link")
    func testE2EECryptoAndUniversalPairingLink() throws {
        #if canImport(CryptoKit)
        let host = PipiE2EECrypto.generateIdentity()
        let client = PipiE2EECrypto.generateIdentity()
        let sid = "sess_swift_01"

        let cKey = try PipiE2EECrypto.deriveSessionKey(
            ownPrivateKeyRaw: client.privateKeyRaw,
            peerPublicKeyB64Url: host.publicKeyB64Url,
            hostId: host.hostId,
            sessionId: sid
        )
        let hKey = try PipiE2EECrypto.deriveSessionKey(
            ownPrivateKeyRaw: host.privateKeyRaw,
            peerPublicKeyB64Url: client.publicKeyB64Url,
            hostId: host.hostId,
            sessionId: sid
        )

        let payload = Data("{\"msg\":\"jarvis-e2ee-secret\"}".utf8)
        let env = try PipiE2EECrypto.sealEnvelope(
            sessionKey: cKey,
            hostId: host.hostId,
            clientId: "ios_1",
            sid: sid,
            dir: "c2h",
            seq: 1,
            plaintextData: payload,
            clientPubKey: client.publicKeyB64Url
        )
        #expect(!env.ct.contains("jarvis-e2ee-secret"))

        let opened = try PipiE2EECrypto.openEnvelope(sessionKey: hKey, envelope: env, lastAcceptedSeq: 0)
        #expect(opened == payload)

        // Replay must throw
        var replayBlocked = false
        do {
            _ = try PipiE2EECrypto.openEnvelope(sessionKey: hKey, envelope: env, lastAcceptedSeq: 1)
        } catch {
            replayBlocked = true
        }
        #expect(replayBlocked)

        // Universal link places one-time token & pubkey strictly in #fragment
        let link = PipiUniversalPairingLink(
            relayOrigin: "https://pipibot.jimizhou.com",
            hostId: host.hostId,
            hostPublicKeyB64Url: host.publicKeyB64Url,
            oneTimeToken: "QWER-7890",
            lanHintURL: "http://192.168.1.22:4242"
        )
        let urlStr = link.urlString
        #expect(urlStr.hasPrefix("https://pipibot.jimizhou.com/c/\(host.hostId)#"))
        let parsed = PipiUniversalPairingLink.parse(urlStr)
        #expect(parsed?.hostId == host.hostId)
        #expect(parsed?.oneTimeToken == "QWER-7890")
        #expect(parsed?.hostPublicKeyB64Url == host.publicKeyB64Url)
        #endif
    }

    @Test("Device Pairing Registry enforces one-time codes, revocation, and hard bounded MCP scope")
    func testDevicePairingAndBoundedMCPScope() {
        let registry = PipiDevicePairingRegistry()

        // Bounded MCP scope cannot approve/merge/delete
        let mcpChallenge = registry.createChallenge(scope: .mcpBounded)
        let mcpRedeem = registry.redeemChallenge(code: mcpChallenge.code, label: "Cursor MCP")
        #expect(mcpRedeem != nil)
        // Second redeem of same one-time code must fail
        #expect(registry.redeemChallenge(code: mcpChallenge.code, label: "Attacker") == nil)

        let mcpToken = mcpRedeem!.rawToken
        #expect(registry.authorize(rawToken: mcpToken, requiredAction: "read") != nil)
        #expect(registry.authorize(rawToken: mcpToken, requiredAction: "approve") == nil)
        #expect(registry.authorize(rawToken: mcpToken, requiredAction: "worktree-merge") == nil)
        #expect(registry.authorize(rawToken: mcpToken, requiredAction: "delete") == nil)

        // Owner scope can approve until revoked
        let ownerChallenge = registry.createChallenge(scope: .owner)
        let ownerRedeem = registry.redeemChallenge(code: ownerChallenge.code, label: "iPhone PWA")!
        #expect(registry.authorize(rawToken: ownerRedeem.rawToken, requiredAction: "approve") != nil)
        #expect(registry.revokeDevice(id: ownerRedeem.device.id) == true)
        #expect(registry.authorize(rawToken: ownerRedeem.rawToken, requiredAction: "read") == nil)
    }

    @Test("Portable Template Engine redacts secrets/paths, pauses routines, and parses community team.md")
    func testPortableTemplateRedactionAndParsing() {
        let leakyBot = PipiBotPersona(
            nameZh: "发布助手",
            nameEn: "Release Bot",
            roleZh: "发布运维",
            roleEn: "Release Ops",
            greetingZh: "Hi",
            greetingEn: "Hi",
            systemPrompt: "Use sk-1234567890abcdefghij at /Users/jimizhou/secret and email alice@example.com"
        )
        let rt = PipiBotRoutine(personaId: leakyBot.id, title: "Daily Check", prompt: "Run check", isEnabled: true)
        let exported = PipiPortableTemplateEngine.exportToMarkdown(
            name: "Ops Team",
            tagline: "Clean ops",
            bots: [leakyBot],
            routines: [rt]
        )

        #expect(exported.package.redactedSecretsCount >= 3)
        #expect(!exported.markdown.contains("sk-1234567890abcdefghij"))
        #expect(!exported.markdown.contains("/Users/jimizhou"))
        #expect(!exported.markdown.contains("alice@example.com"))
        #expect(exported.package.routines.allSatisfy { $0.enabled == false })

        let communityTeamMd = """
        ---
        scope: team
        name: "Launch Squad"
        tagline: "Portable team"
        bots:
          - slug: writer
            name: "Copy Writer"
            role: "Draft launch posts"
          - slug: qa
            name: "QA Auditor"
            role: "Verify release checklist"
        routines:
          - title: "Morning pulse"
            bot: qa
            trigger: schedule
            cron: "0 9 * * 1-5"
        ---
        ## Bot: Copy Writer
        Write crisp release notes.
        """
        let parsed = PipiPortableTemplateEngine.parseMarkdown(communityTeamMd)
        #expect(parsed.scope == "team")
        #expect(parsed.bots.count == 2)
        #expect(parsed.routines.count == 1)
        #expect(parsed.routines[0].enabled == false)
    }

    @Test("Three-Tier Fast Group Auto-Router handles @mention, rules, Decision Model & fail-open fallback")
    func testThreeTierGroupAutoRouter() async {
        let candidates = [
            PipiGroupRouterCandidate(id: "bot_lead", name: "PiPi", roleTitle: "General Lead", keywords: ["plan"]),
            PipiGroupRouterCandidate(id: "bot_coder", name: "Coder", roleTitle: "Swift & TS Engineer", keywords: ["swift", "build", "bug"]),
            PipiGroupRouterCandidate(id: "bot_sec", name: "Auditor", roleTitle: "Security Reviewer", keywords: ["cve", "audit", "secret"])
        ]

        // L1A: Explicit @mention
        let r1 = await PipiGroupAutoRouter.route(
            message: "@Auditor check this PR",
            candidates: candidates,
            leadBotId: "bot_lead",
            config: PipiDecisionModelConfig(enabled: false)
        )
        #expect(r1.tier == .explicitMention)
        #expect(r1.picks.first?.botId == "bot_sec")

        // L1B: Deterministic rule match (>=2 keywords)
        let r2 = await PipiGroupAutoRouter.route(
            message: "Fix the swift build bug right now",
            candidates: candidates,
            leadBotId: "bot_lead",
            config: PipiDecisionModelConfig(enabled: false)
        )
        #expect(r2.tier == .deterministicRule)
        #expect(r2.picks.first?.botId == "bot_coder")

        // L2: Fast Decision Model returning high-confidence parallel picks
        let mockExec: PipiDecisionModelHTTPExecutor = { _ in
            let json = #"{"choices":[{"message":{"content":"{\"picks\":[{\"botId\":\"bot_coder\",\"confidence\":0.91,\"reason\":\"code\"},{\"botId\":\"bot_sec\",\"confidence\":0.78,\"reason\":\"security\"}]}"}}]}"#
            return (Data(json.utf8), 200)
        }
        let r3 = await PipiGroupAutoRouter.route(
            message: "Please review authentication architecture changes",
            candidates: candidates,
            leadBotId: "bot_lead",
            config: PipiDecisionModelConfig(enabled: true, providerKind: .localFast, minConfidence: 0.6, maxAutoParallel: 2),
            executor: mockExec
        )
        #expect(r3.tier == .decisionModel)
        #expect(r3.picks.count == 2)

        // L3: Fail-open fallback when model confidence is too low
        let lowConfExec: PipiDecisionModelHTTPExecutor = { _ in
            let json = #"{"choices":[{"message":{"content":"{\"picks\":[{\"botId\":\"bot_coder\",\"confidence\":0.31,\"reason\":\"unsure\"}]}"}}]}"#
            return (Data(json.utf8), 200)
        }
        let r4 = await PipiGroupAutoRouter.route(
            message: "What should we eat for lunch?",
            candidates: candidates,
            leadBotId: "bot_lead",
            config: PipiDecisionModelConfig(enabled: true, providerKind: .localFast, minConfidence: 0.6),
            executor: lowConfExec
        )
        #expect(r4.tier == .leadFallback)
        #expect(r4.picks.first?.botId == "bot_lead")
    }

    @Test("Sentinel zero-LLM scanner clusters normalized errors and synthesizes Self-Evolution proposal at >=3 hits")
    func testSentinelHealthScannerClusteringAndEvolution() {
        let samples = [
            PipiSentinelEventSample(id: "e1", kind: .toolError, toolName: "read_file", botId: "bot_coder", rawMessage: "No such file at /Users/jimizhou/app/file12.swift line 42"),
            PipiSentinelEventSample(id: "e2", kind: .toolError, toolName: "read_file", botId: "bot_coder", rawMessage: "No such file at /Users/alice/other/file99.swift line 88"),
            PipiSentinelEventSample(id: "e3", kind: .toolError, toolName: "read_file", botId: "bot_coder", rawMessage: "No such file at /Users/bob/proj/file7.swift line 3")
        ]
        var issues = PipiSentinelHealthScanner.scan(samples: samples)
        #expect(issues.count == 1)
        #expect(issues[0].count == 3)
        #expect(!issues[0].normalizedTitle.contains("jimizhou"))

        let proposals = PipiSentinelHealthScanner.synthesizeEvolutionProposals(issues: &issues, recurrenceThreshold: 3)
        #expect(proposals.count == 1)
        #expect(issues[0].promotedToEvolutionId == proposals[0].id)
    }

    @Test("Credential Broker scrubs foreign env keys, resolves pinned upstream, and macOS Bot Box self-check passes")
    func testCredentialBrokerAndBotBoxSelfCheck() async throws {
        let broker = PipiCredentialBroker()
        let lease = try await broker.issueLease(binding: PipiBrokerUpstreamBinding(
            provider: "openai",
            upstreamBaseURL: URL(string: "https://api.openai.com/v1")!,
            realSecret: "sk-real-secret-never-exposed"
        ))

        let env = PipiCredentialBroker.buildScrubbedEnvironment(
            baseEnvironment: [
                "PATH": "/usr/bin:/bin",
                "ANTHROPIC_API_KEY": "sk-ant-foreign-must-strip",
                "PIPIBOT_HUB_TOKEN": "internal-hub-secret-must-strip"
            ],
            leases: [lease]
        )
        #expect(env["OPENAI_API_KEY"] == lease.token)
        #expect(env["OPENAI_API_KEY"] != "sk-real-secret-never-exposed")
        #expect(env["ANTHROPIC_API_KEY"] == nil)
        #expect(env["PIPIBOT_HUB_TOKEN"] == nil)

        let req = await broker.resolveUpstreamRequest(
            method: "POST",
            rawPath: "/b/\(lease.token)/openai/chat/completions",
            callerHeaders: ["Authorization": "Bearer \(lease.token)", "Content-Type": "application/json"],
            body: Data("{}".utf8)
        )
        #expect(req?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-real-secret-never-exposed")
        #expect(req?.url?.absoluteString == "https://api.openai.com/v1/chat/completions")

        await broker.revokeLease(token: lease.token)
        let afterRevoke = await broker.resolveUpstreamRequest(
            method: "POST",
            rawPath: "/b/\(lease.token)/openai/chat/completions",
            callerHeaders: [:],
            body: Data()
        )
        #expect(afterRevoke == nil)
        await broker.stop()

        let boxCheck = PipiBotBoxSandbox.runSelfCheck()
        #expect(boxCheck.allPassed)
    }

    @MainActor
    @Test("Bot self-service trigger tool keeps webhook secrets strictly write-only & WeChat persists syncCursor")
    func testWriteOnlyWebhookSecretAndWeChatCursor() throws {
        let store = PipiAppStore(enableNativeRuntime: false)
        let msg = store.handleBotTriggerTool(
            action: "trigger_upsert",
            args: [
                "title": "Stripe Webhook",
                "prompt": "Process incoming event",
                "trigger_kind": "webhook"
            ],
            callerBotId: store.activePersona.id
        )
        #expect(msg.contains("/api/v1/webhooks/"))
        #expect(!msg.contains("whsec_")) // Secret NEVER leaked into LLM output!
        let created = store.routines.first(where: { $0.title == "Stripe Webhook" })
        #expect(created?.eventConfig.webhookSecret?.hasPrefix("whsec_") == true)

        // WeChat credentials round-trip syncCursor & backward-compatible decode without syncCursor
        let legacyJSON = #"{"botToken":"tok1","botId":"b1","userId":"u1","baseURL":"https://ilinkai.weixin.qq.com"}"#
        let decodedLegacy = try JSONDecoder().decode(PipiWeChatSessionCredentials.self, from: Data(legacyJSON.utf8))
        #expect(decodedLegacy.syncCursor == nil)

        var updated = decodedLegacy
        updated.syncCursor = "cursor_abc_123"
        let encoded = try JSONEncoder().encode(updated)
        let roundTripped = try JSONDecoder().decode(PipiWeChatSessionCredentials.self, from: encoded)
        #expect(roundTripped.syncCursor == "cursor_abc_123")
    }
}
