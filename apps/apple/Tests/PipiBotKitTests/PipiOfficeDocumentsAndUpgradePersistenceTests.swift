import Foundation
import Testing
@testable import PipiBotKit

@Suite("Office Document Extractor (.wps/.docx/.xlsx/GB18030) & Zero-Loss Upgrade Persistence")
struct PipiOfficeDocumentsAndUpgradePersistenceTests {

    @Test("Extracts Chinese text from OLE2 .wps, RTF .wps, OOXML .wps, .xlsx tables, .eml, and GB18030 .txt")
    func testOfficeDocumentExtraction() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-doc-tests-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // 1. OLE2 Binary .wps containing UTF-16LE Chinese regulation text
        let ole2WPS = tmpDir.appendingPathComponent("1沈阳蓝柯洗涤厂岗位管理及违规处理规定_修订版.wps")
        var ole2Bytes = Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        let chinesePolicy = "沈阳蓝柯洗涤厂岗位管理及违规处理规定\r\n第一条 员工须严格遵守安全生产操作规程，严禁迟到早退。\r\n第二条 违规处理应遵循公平公正原则。"
        if let utf16Data = chinesePolicy.data(using: .utf16LittleEndian) {
            ole2Bytes.append(utf16Data)
        }
        try ole2Bytes.write(to: ole2WPS)

        let ole2Attachment = PipiChatAttachment.fromFileURL(ole2WPS)
        #expect(ole2Attachment.textContent != nil)
        #expect(ole2Attachment.textContent?.contains("沈阳蓝柯洗涤厂岗位管理及违规处理规定") == true)
        #expect(ole2Attachment.textContent?.contains("安全生产操作规程") == true)

        // 2. RTF-backed .wps
        let rtfWPS = tmpDir.appendingPathComponent("notice.wps")
        let rtfContent = #"{\rtf1\ansi{\fonttbl\f0 Helvetica;}\f0 Quarterly Office Policy Review 2026}"#
        try rtfContent.write(to: rtfWPS, atomically: true, encoding: .utf8)
        let rtfText = PipiDocumentExtractor.extractText(from: rtfWPS)
        #expect(rtfText?.contains("Quarterly Office Policy Review 2026") == true)

        // 3. GB18030 Chinese .txt file (non-UTF-8)
        #if canImport(CoreFoundation)
        let gbURL = tmpDir.appendingPathComponent("考勤记录.txt")
        let gbEncoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        ))
        let gbSample = "姓名,部门,出勤天数\n张伟,洗涤车间,22"
        if let gbData = gbSample.data(using: gbEncoding) {
            try gbData.write(to: gbURL)
            let extracted = PipiDocumentExtractor.extractText(from: gbURL)
            #expect(extracted?.contains("洗涤车间") == true)
        }
        #endif

        // 4. Email .eml file
        let emlURL = tmpDir.appendingPathComponent("report.eml")
        let emlSample = "From: boss@example.com\r\nSubject: Q4 Budget\r\n\r\n<html><body><p>请于周五前提交第四季度预算表。</p></body></html>"
        try emlSample.write(to: emlURL, atomically: true, encoding: .utf8)
        let emlText = PipiDocumentExtractor.extractText(from: emlURL)
        #expect(emlText?.contains("Q4 Budget") == true)
        #expect(emlText?.contains("第四季度预算表") == true)
    }

    @Test("Fault-isolated decoding preserves conversations and settings even when a nested subsystem or single item drifts across upgrades")
    func testFaultIsolatedUpgradeDecoding() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-upgrade-tests-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let stateURL = tmpDir.appendingPathComponent("resident-state.json")

        // Simulate a state JSON from another app version where:
        // - `voiceConfig` has an incompatible type ("broken_schema")
        // - `conversations` has 1 valid conversation AND 1 malformed legacy entry
        // - `llmProviders` has 1 valid provider
        let rawJSON = """
        {
          "themeModeRaw": "dark",
          "keepAwakeEnabled": true,
          "hasCompletedOnboarding": true,
          "languageRaw": "zhHans",
          "voiceConfig": "incompatible_future_schema",
          "computerUseConfig": 12345,
          "llmProviders": [
            {
              "id": "prov_ollama",
              "name": "Ollama",
              "kind": "ollama",
              "baseURL": "http://127.0.0.1:11434/v1",
              "modelId": "qwen3.5:9b",
              "apiKey": ""
            }
          ],
          "conversations": [
            {
              "id": "conv_keep_me",
              "personaId": "bot_pipi_general",
              "title": "制度审查记录",
              "messages": [
                {
                  "id": "msg_1",
                  "role": "user",
                  "content": "帮我审查这份规定",
                  "createdAt": "2026-11-23T04:00:00Z"
                }
              ],
              "createdAt": "2026-11-23T04:00:00Z",
              "updatedAt": "2026-11-23T04:00:00Z"
            },
            {
              "corrupted_entry": true
            }
          ]
        }
        """
        try rawJSON.write(to: stateURL, atomically: true, encoding: .utf8)

        let result = PipiNativeMacRuntime.loadResidentStateDetailed(from: stateURL)
        guard case .loaded(let decoded) = result else {
            Issue.record("Expected fault-isolated decode to succeed, got \(result)")
            return
        }
        #expect(decoded.themeModeRaw == "dark")
        #expect(decoded.hasCompletedOnboarding == true)
        #expect(decoded.voiceConfig == nil)
        #expect(decoded.computerUseConfig == nil)
        #expect(decoded.llmProviders?.count == 1)
        #expect(decoded.llmProviders?.first?.modelId == "qwen3.5:9b")
        #expect(decoded.conversations?.count == 1)
        #expect(decoded.conversations?.first?.title == "制度审查记录")
    }

    @Test("Pre-update backup recovers settings and conversations if primary state file is corrupted during upgrade")
    @MainActor
    func testPreUpdateBackupRecovery() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-backup-tests-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let stateURL = tmpDir.appendingPathComponent("resident-state.json")
        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            enableEmbeddedBridge: false,
            stateFileUrl: stateURL,
            seedDemoData: false,
            secretStore: PipiInMemorySecretStore()
        )
        store.hasCompletedOnboarding = true
        let conv = store.createConversation(title: "重要办公对话")
        store.prepareForAppUpgrade()

        let preUpdateURL = PipiNativeMacRuntime.preUpdateBackupUrl(for: stateURL)
        #expect(FileManager.default.fileExists(atPath: preUpdateURL.path))

        // Simulate primary file truncation during an interrupted update
        try Data("{truncated".utf8).write(to: stateURL, options: .atomic)

        let reloaded = PipiNativeMacRuntime.loadResidentStateDetailed(from: stateURL)
        guard case .loaded(let recovered) = reloaded else {
            Issue.record("Expected automatic recovery from last-good / pre-update backup")
            return
        }
        #expect(recovered.hasCompletedOnboarding == true)
        #expect(recovered.conversations?.contains(where: { $0.id == conv.id && $0.title == "重要办公对话" }) == true)
    }
}
