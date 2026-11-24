// PiPiBot — Clean-room MIT implementation.
// Tests for Tier 1 + Tier 2 Native Mobile Sandbox Shell & JavaScriptCore Script Engine.

import Foundation
import Testing
@testable import PipiBotKit

@Suite("PipiBot Mobile Sandbox Shell & JavaScriptCore Tests")
struct PipiBotMobileSandboxTests {

    private func makeTempWorkspace() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipi-mobile-sandbox-test-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("POSIX file operations, redirection, and chaining work inside jailed workspace")
    func testPosixFilesAndChaining() async throws {
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let shell = PipiMobileSandboxShell(rootDirectory: root)

        let r1 = await shell.execute("mkdir docs && cd docs && echo 'hello world' > note.txt && echo 'second line' >> note.txt && pwd", recordTranscript: false)
        #expect(r1.exitCode == 0)
        #expect(r1.stdout.contains("~/PipiWorkspace/docs"))

        let r2 = await shell.execute("cat note.txt", recordTranscript: false)
        #expect(r2.exitCode == 0)
        #expect(r2.stdout.contains("hello world"))
        #expect(r2.stdout.contains("second line"))

        let r3 = await shell.execute("cp note.txt copy.txt && mv copy.txt renamed.txt && ls", recordTranscript: false)
        #expect(r3.exitCode == 0)
        #expect(r3.stdout.contains("note.txt"))
        #expect(r3.stdout.contains("renamed.txt"))

        let r4 = await shell.execute("rm renamed.txt && ls", recordTranscript: false)
        #expect(r4.exitCode == 0)
        #expect(!r4.stdout.contains("renamed.txt"))
    }

    @Test("Multi-stage pipes (cat | grep | sort -u | wc -l) work accurately")
    func testMultiStagePipes() async throws {
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let data = "apple\nbanana\napple\napricot\ncherry\n"
        try data.write(to: root.appendingPathComponent("fruits.txt"), atomically: true, encoding: .utf8)

        let shell = PipiMobileSandboxShell(rootDirectory: root)
        let res = await shell.execute("cat fruits.txt | grep ap | sort -u | wc -l", recordTranscript: false)
        #expect(res.exitCode == 0)
        #expect(res.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "2")
    }

    @Test("Strict workspace jail blocks ../ traversal, absolute /etc paths, and JS fs escapes")
    func testSandboxPathJail() async throws {
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let shell = PipiMobileSandboxShell(rootDirectory: root)

        let r1 = await shell.execute("cat ../../etc/passwd", recordTranscript: false)
        #expect(r1.exitCode != 0)

        let r2 = await shell.execute("cd /etc", recordTranscript: false)
        #expect(r2.exitCode != 0)
        let cwd = await shell.displayCwd()
        #expect(cwd == "~/PipiWorkspace")

        let r3 = await shell.runJavaScript("fs.read('../../etc/passwd')", recordTranscript: false)
        #expect(r3.exitCode != 0)
    }

    @Test("Apple JavaScriptCore executes scripts with console.log and workspace-jailed fs bridge")
    func testJavaScriptCoreRuntime() async throws {
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let shell = PipiMobileSandboxShell(rootDirectory: root)
        let code = """
        const items = [10, 20, 30, 40];
        const sum = items.reduce((a, b) => a + b, 0);
        fs.write('sum.json', JSON.stringify({ total: sum, count: items.length }));
        const readBack = JSON.parse(fs.read('sum.json'));
        console.log('total=' + readBack.total);
        readBack.count;
        """
        let ok = await shell.runJavaScript(code, recordTranscript: false)
        #expect(ok.exitCode == 0)
        #expect(ok.stdout.contains("total=100"))
        #expect(ok.stdout.contains("4"))

        let bad = await shell.runJavaScript("function broken( {", recordTranscript: false)
        #expect(bad.exitCode != 0)
        #expect(!bad.stderr.isEmpty)
    }

    @Test("Desktop heavy-toolchain relay classifier distinguishes local vs Mac/Linux binaries")
    func testDesktopHostRelayClassification() {
        #expect(PipiMobileSandboxShell.requiresDesktopHostRelay(command: "python3 analyze.py"))
        #expect(PipiMobileSandboxShell.requiresDesktopHostRelay(command: "git status"))
        #expect(PipiMobileSandboxShell.requiresDesktopHostRelay(command: "swift test"))
        #expect(PipiMobileSandboxShell.requiresDesktopHostRelay(command: "npm run verify"))
        #expect(PipiMobileSandboxShell.requiresDesktopHostRelay(command: "ffmpeg -i a.mp4 b.gif"))

        #expect(!PipiMobileSandboxShell.requiresDesktopHostRelay(command: "ls -la"))
        #expect(!PipiMobileSandboxShell.requiresDesktopHostRelay(command: "cat README.md | grep PiPi"))
        #expect(!PipiMobileSandboxShell.requiresDesktopHostRelay(command: "js \"2 ** 16\""))
        #expect(!PipiMobileSandboxShell.requiresDesktopHostRelay(command: "wc -l notes.txt"))
    }

    @Test("PipiAgentToolbox run_script tool auto-allows and executes cleanly")
    func testToolboxRunScriptIntegration() async throws {
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let call = PipiLLMToolCall(
            id: "call_js_1",
            name: "run_script",
            argumentsJSON: #"{"code":"const x = 6 * 7; console.log('answer=' + x); x;"}"#
        )
        let risk = PipiJarvisToolRiskEvaluator.evaluate(toolCall: call, workspaceDirectory: root.path)
        #expect(!risk.requiresApproval)
        #expect(!risk.isHardDenied)

        let stubResult = PipiMacOmnipotentCommandResult(succeeded: true, summary: "stub")
        let callbacks = PipiAgentHostCallbacks(
            captureScreenshot: { stubResult },
            recordScreen: { _ in stubResult },
            synthesizeVoice: { _ in stubResult },
            prepareLocalFile: { _ in stubResult },
            registerArtifact: { _ in },
            delegateCLIAgent: { _, _, _, _ in (true, "stub") },
            readCalendarAndReminders: { "stub" },
            createRoutineOrReminder: { _, _, _, _ in "stub" },
            readMailOrSMS: { _, _ in "stub" },
            sendMailOrSMS: { _, _, _, _ in stubResult },
            showControlMenu: { "stub" },
            listOrSwitchBot: { _ in "stub" },
            createBot: { _, _, _ in "stub" },
            switchSessionOrProject: { _, _ in "stub" },
            configureGroupMode: { _, _ in "stub" },
            updateSettings: { _, _ in "stub" },
            checkUpdates: { "stub" }
        )

        let res = await PipiAgentToolbox.execute(
            toolCall: call,
            workspaceDirectory: root.path,
            llmConfig: nil,
            deliverablesDirectory: root,
            callbacks: callbacks
        )
        #expect(!res.isError)
        #expect(res.output.contains("answer=42"))
    }
}
