// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
//
// Tier 1 + Tier 2 Native Mobile Sandbox Shell & JavaScriptCore Script Engine:
// - 100% pure Swift + Apple JavaScriptCore (MIT clean-room, zero GPL/iSH contamination, 0 MB overhead)
// - Strict workspace path jail (blocks ../ and symlink escapes)
// - Native POSIX-subset commands, pipes (`|`), redirections (`>`, `>>`), chaining (`&&`, `;`), and `js` execution
// - Live terminal transcript history shared between Agent tool calls and the iOS In-App Terminal drawer
// - Smart heavy-toolchain classifier so iPhone can route `python3`/`git`/`swift`/`npm` to enrolled Mac/Linux nodes

import Foundation
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

// MARK: - 1. Models & Transcript

public struct PipiMobileShellResult: Codable, Sendable, Equatable {
    public let command: String
    public let stdout: String
    public let stderr: String
    public let exitCode: Int
    public let cwd: String
    public let durationMs: Int
    public let targetLabel: String

    public init(
        command: String,
        stdout: String,
        stderr: String,
        exitCode: Int,
        cwd: String,
        durationMs: Int,
        targetLabel: String = "iPhone Sandbox"
    ) {
        self.command = command
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.cwd = cwd
        self.durationMs = durationMs
        self.targetLabel = targetLabel
    }

    public var combinedOutput: String {
        var parts: [String] = []
        if !stdout.isEmpty { parts.append(stdout) }
        if !stderr.isEmpty { parts.append("stderr:\n\(stderr)") }
        if parts.isEmpty { return "(exit=\(exitCode), no output)" }
        return parts.joined(separator: "\n")
    }
}

public struct PipiTerminalTranscriptEntry: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let timestamp: Date
    public let source: String // "user" | "agent"
    public let targetLabel: String
    public let command: String
    public let output: String
    public let exitCode: Int
    public let durationMs: Int

    public init(
        id: String = "term_\(UUID().uuidString.prefix(8).lowercased())",
        timestamp: Date = Date(),
        source: String = "user",
        targetLabel: String = "Local Sandbox",
        command: String,
        output: String,
        exitCode: Int,
        durationMs: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.targetLabel = targetLabel
        self.command = command
        self.output = output
        self.exitCode = exitCode
        self.durationMs = durationMs
    }
}

@MainActor
@Observable
public final class PipiMobileTerminalLog {
    public static let shared = PipiMobileTerminalLog()

    public private(set) var entries: [PipiTerminalTranscriptEntry] = []

    public init() {}

    public func append(_ entry: PipiTerminalTranscriptEntry) {
        entries.append(entry)
        if entries.count > 120 {
            entries.removeFirst(entries.count - 120)
        }
    }

    public func clear() {
        entries.removeAll()
    }
}

// MARK: - 2. Native Sandboxed Mobile Shell + JavaScriptCore Runtime

public actor PipiMobileSandboxShell {
    public static let shared = PipiMobileSandboxShell()

    private var rootURL: URL
    private var currentRelativePath: String = ""

    public init(rootDirectory: URL? = nil) {
        let base = rootDirectory ?? Self.defaultWorkspaceURL()
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.rootURL = base.standardizedFileURL
    }

    public static func defaultWorkspaceURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return docs.appendingPathComponent("PipiWorkspace", isDirectory: true)
    }

    public func setRootDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        self.rootURL = url.standardizedFileURL
        self.currentRelativePath = ""
    }

    public func workspacePath() -> String {
        rootURL.path
    }

    public func displayCwd() -> String {
        currentRelativePath.isEmpty ? "~/PipiWorkspace" : "~/PipiWorkspace/\(currentRelativePath)"
    }

    /// Identifies heavy desktop/Linux toolchains that should automatically route to an online Mac/Linux
    /// host over E2EE when running on iPhone.
    public static func requiresDesktopHostRelay(command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let firstToken = trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)?.lowercased() ?? ""
        let heavyBinaries: Set<String> = [
            "python", "python3", "pip", "pip3", "uv",
            "git", "gh", "npm", "npx", "pnpm", "yarn", "bun", "deno",
            "swift", "xcodebuild", "cargo", "rustc", "go", "gcc", "clang", "make", "cmake",
            "docker", "kubectl", "ffmpeg", "yt-dlp", "brew", "apt", "apt-get", "apk",
            "claude", "codex", "opencode", "omp", "agy", "ssh", "rsync"
        ]
        return heavyBinaries.contains(firstToken)
    }

    // MARK: - Command Execution Entrypoint

    /// Executes a shell command line (supports `;`, `&&`, pipes `|`, redirection `>` / `>>`, and `js` scripts)
    /// strictly jailed inside `rootURL`.
    public func execute(
        _ rawCommand: String,
        source: String = "agent",
        recordTranscript: Bool = true
    ) async -> PipiMobileShellResult {
        let started = Date()
        let trimmed = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return PipiMobileShellResult(command: "", stdout: "", stderr: "", exitCode: 0, cwd: displayCwd(), durationMs: 0)
        }

        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        var accumulatedOut: [String] = []
        var accumulatedErr: [String] = []
        var lastExit = 0

        let statements = splitChainedStatements(trimmed)
        for stmt in statements {
            if stmt.requiresPreviousSuccess && lastExit != 0 {
                break
            }
            let res = await executePipeline(stmt.command)
            if !res.stdout.isEmpty { accumulatedOut.append(res.stdout) }
            if !res.stderr.isEmpty { accumulatedErr.append(res.stderr) }
            lastExit = res.exitCode
        }

        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        let finalOut = accumulatedOut.joined(separator: "\n")
        let finalErr = accumulatedErr.joined(separator: "\n")
        let result = PipiMobileShellResult(
            command: trimmed,
            stdout: finalOut,
            stderr: finalErr,
            exitCode: lastExit,
            cwd: displayCwd(),
            durationMs: elapsed
        )

        if recordTranscript {
            let entry = PipiTerminalTranscriptEntry(
                source: source,
                targetLabel: result.targetLabel,
                command: trimmed,
                output: result.combinedOutput,
                exitCode: lastExit,
                durationMs: elapsed
            )
            await MainActor.run { PipiMobileTerminalLog.shared.append(entry) }
        }

        return result
    }

    // MARK: - Apple JavaScriptCore Sandboxed Script Engine

    /// Runs a JavaScript snippet natively on Apple's JavaScriptCore engine with sandboxed `fs` workspace APIs.
    public func runJavaScript(
        _ code: String,
        source: String = "agent",
        recordTranscript: Bool = true
    ) async -> PipiMobileShellResult {
        let started = Date()
        let root = self.rootURL
        let rel = self.currentRelativePath

        #if canImport(JavaScriptCore)
        let evalOutcome: (stdout: String, stderr: String, exitCode: Int) = {
            guard let ctx = JSContext() else {
                return ("", "JavaScriptCore context unavailable", 1)
            }
            var logs: [String] = []
            var errors: [String] = []

            ctx.exceptionHandler = { _, exception in
                if let msg = exception?.toString() {
                    errors.append(msg)
                }
            }

            let logFn: @convention(block) (JSValue) -> Void = { val in
                logs.append(val.toString() ?? "")
            }
            let errFn: @convention(block) (JSValue) -> Void = { val in
                errors.append(val.toString() ?? "")
            }
            ctx.evaluateScript("var console = {};")
            ctx.objectForKeyedSubscript("console")?.setObject(logFn, forKeyedSubscript: "log" as NSString)
            ctx.objectForKeyedSubscript("console")?.setObject(errFn, forKeyedSubscript: "error" as NSString)
            ctx.objectForKeyedSubscript("console")?.setObject(logFn, forKeyedSubscript: "warn" as NSString)

            // Sandboxed `fs` bridge jailed strictly inside `root`
            let resolveJailed: (String) -> URL? = { pathArg in
                Self.resolveContainedURL(pathArg, rootURL: root, currentRelativePath: rel)
            }

            let fsRead: @convention(block) (String) -> String = { p in
                guard let u = resolveJailed(p) else {
                    errors.append("SecurityError: path escapes sandbox: \(p)")
                    return ""
                }
                return (try? String(contentsOf: u, encoding: .utf8)) ?? ""
            }
            let fsWrite: @convention(block) (String, String) -> Bool = { p, content in
                guard let u = resolveJailed(p) else {
                    errors.append("SecurityError: path escapes sandbox: \(p)")
                    return false
                }
                do {
                    try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try content.write(to: u, atomically: true, encoding: .utf8)
                    return true
                } catch {
                    errors.append("WriteError: \(error.localizedDescription)")
                    return false
                }
            }
            let fsAppend: @convention(block) (String, String) -> Bool = { p, content in
                guard let u = resolveJailed(p) else {
                    errors.append("SecurityError: path escapes sandbox: \(p)")
                    return false
                }
                let existing = (try? String(contentsOf: u, encoding: .utf8)) ?? ""
                do {
                    try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try (existing + content).write(to: u, atomically: true, encoding: .utf8)
                    return true
                } catch {
                    errors.append("AppendError: \(error.localizedDescription)")
                    return false
                }
            }
            let fsList: @convention(block) (String) -> [String] = { p in
                let target = p.isEmpty ? "." : p
                guard let u = resolveJailed(target) else {
                    errors.append("SecurityError: path escapes sandbox: \(p)")
                    return []
                }
                return ((try? FileManager.default.contentsOfDirectory(atPath: u.path)) ?? []).sorted()
            }
            let fsExists: @convention(block) (String) -> Bool = { p in
                guard let u = resolveJailed(p) else { return false }
                return FileManager.default.fileExists(atPath: u.path)
            }
            let fsRemove: @convention(block) (String) -> Bool = { p in
                guard let u = resolveJailed(p), u.path != root.path else {
                    errors.append("SecurityError: cannot remove sandbox root or outside path")
                    return false
                }
                return (try? FileManager.default.removeItem(at: u)) != nil
            }

            ctx.evaluateScript("var fs = {};")
            if let fsObj = ctx.objectForKeyedSubscript("fs") {
                fsObj.setObject(fsRead, forKeyedSubscript: "read" as NSString)
                fsObj.setObject(fsWrite, forKeyedSubscript: "write" as NSString)
                fsObj.setObject(fsAppend, forKeyedSubscript: "append" as NSString)
                fsObj.setObject(fsList, forKeyedSubscript: "list" as NSString)
                fsObj.setObject(fsExists, forKeyedSubscript: "exists" as NSString)
                fsObj.setObject(fsRemove, forKeyedSubscript: "remove" as NSString)
            }

            let val = ctx.evaluateScript(code)
            if let val, !val.isUndefined && !val.isNull {
                let str = val.toString() ?? ""
                if !str.isEmpty && logs.last != str {
                    logs.append(str)
                }
            }
            let exitCode = errors.isEmpty ? 0 : 1
            return (logs.joined(separator: "\n"), errors.joined(separator: "\n"), exitCode)
        }()
        #else
        let evalOutcome = ("", "JavaScriptCore is not available on this platform.", 1)
        #endif

        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        let result = PipiMobileShellResult(
            command: "js \(code.prefix(80))",
            stdout: evalOutcome.stdout,
            stderr: evalOutcome.stderr,
            exitCode: evalOutcome.exitCode,
            cwd: displayCwd(),
            durationMs: elapsed,
            targetLabel: "iPhone JS Sandbox"
        )

        if recordTranscript {
            let entry = PipiTerminalTranscriptEntry(
                source: source,
                targetLabel: result.targetLabel,
                command: result.command,
                output: result.combinedOutput,
                exitCode: result.exitCode,
                durationMs: elapsed
            )
            await MainActor.run { PipiMobileTerminalLog.shared.append(entry) }
        }
        return result
    }

    // MARK: - Pipeline & Built-in POSIX Subset

    private struct ChainedStatement {
        let command: String
        let requiresPreviousSuccess: Bool
    }

    private func splitChainedStatements(_ line: String) -> [ChainedStatement] {
        var result: [ChainedStatement] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        var nextRequiresSuccess = false
        let chars = Array(line)
        var i = 0

        while i < chars.count {
            let c = chars[i]
            if c == "'" && !inDouble {
                inSingle.toggle()
                current.append(c)
                i += 1
                continue
            }
            if c == "\"" && !inSingle {
                inDouble.toggle()
                current.append(c)
                i += 1
                continue
            }
            if !inSingle && !inDouble {
                if c == "&" && i + 1 < chars.count && chars[i + 1] == "&" {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        result.append(ChainedStatement(command: trimmed, requiresPreviousSuccess: nextRequiresSuccess))
                    }
                    current = ""
                    nextRequiresSuccess = true
                    i += 2
                    continue
                }
                if c == ";" {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        result.append(ChainedStatement(command: trimmed, requiresPreviousSuccess: nextRequiresSuccess))
                    }
                    current = ""
                    nextRequiresSuccess = false
                    i += 1
                    continue
                }
            }
            current.append(c)
            i += 1
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            result.append(ChainedStatement(command: tail, requiresPreviousSuccess: nextRequiresSuccess))
        }
        return result
    }

    private func splitPipes(_ line: String) -> [String] {
        var stages: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        for c in line {
            if c == "'" && !inDouble { inSingle.toggle(); current.append(c); continue }
            if c == "\"" && !inSingle { inDouble.toggle(); current.append(c); continue }
            if c == "|" && !inSingle && !inDouble {
                let t = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { stages.append(t) }
                current = ""
                continue
            }
            current.append(c)
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { stages.append(tail) }
        return stages
    }

    private func tokenize(_ stage: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        var escape = false

        for c in stage {
            if escape {
                current.append(c)
                escape = false
                continue
            }
            if c == "\\" && !inSingle {
                escape = true
                continue
            }
            if c == "'" && !inDouble {
                inSingle.toggle()
                continue
            }
            if c == "\"" && !inSingle {
                inDouble.toggle()
                continue
            }
            if c.isWhitespace && !inSingle && !inDouble {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            current.append(c)
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private func executePipeline(_ statement: String) async -> (stdout: String, stderr: String, exitCode: Int) {
        let stages = splitPipes(statement)
        guard !stages.isEmpty else { return ("", "", 0) }

        var stdinText = ""
        var stderrLines: [String] = []
        var exitCode = 0

        for stage in stages {
            var tokens = tokenize(stage)
            guard !tokens.isEmpty else { continue }

            // Check output redirection `>` or `>>`
            var redirectPath: String? = nil
            var redirectAppend = false
            if let rIdx = tokens.firstIndex(where: { $0 == ">" || $0 == ">>" }), rIdx + 1 < tokens.count {
                redirectAppend = (tokens[rIdx] == ">>")
                redirectPath = tokens[rIdx + 1]
                tokens.removeSubrange(rIdx...(rIdx + 1))
            }

            let res = await executeSingleCommand(tokens: tokens, stdin: stdinText)
            if !res.stderr.isEmpty { stderrLines.append(res.stderr) }
            exitCode = res.exitCode

            if let redirectPath {
                guard let destURL = resolveURL(redirectPath) else {
                    stderrLines.append("Sandbox denied path outside workspace: \(redirectPath)")
                    return ("", stderrLines.joined(separator: "\n"), 1)
                }
                do {
                    try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let payload = res.stdout.isEmpty ? "" : (res.stdout + "\n")
                    if redirectAppend, let existing = try? String(contentsOf: destURL, encoding: .utf8) {
                        try (existing + payload).write(to: destURL, atomically: true, encoding: .utf8)
                    } else {
                        try payload.write(to: destURL, atomically: true, encoding: .utf8)
                    }
                    stdinText = ""
                } catch {
                    stderrLines.append("Redirect failed: \(error.localizedDescription)")
                    return ("", stderrLines.joined(separator: "\n"), 1)
                }
            } else {
                stdinText = res.stdout
            }
        }

        return (stdinText, stderrLines.joined(separator: "\n"), exitCode)
    }

    private func executeSingleCommand(tokens: [String], stdin: String) async -> (stdout: String, stderr: String, exitCode: Int) {
        guard let cmd = tokens.first?.lowercased() else { return ("", "", 0) }
        let args = Array(tokens.dropFirst())
        let fm = FileManager.default

        switch cmd {
        case "help":
            return (
                """
                PiPi Mobile Sandbox Shell (MIT Native · Path-Jailed Workspace)
                Built-ins: pwd, cd, ls [-la], cat, head [-n N], tail [-n N], echo, touch, mkdir [-p], cp [-r], mv, rm [-rf], grep [-in], find, wc [-lwc], sort [-ru], uniq, date, uname, curl <url>, js <code>
                Tip: Heavy toolchains (python3, git, swift, npm) automatically bridge to your enrolled Mac/Linux host when online.
                """,
                "",
                0
            )

        case "clear":
            await MainActor.run { PipiMobileTerminalLog.shared.clear() }
            return ("", "", 0)

        case "pwd":
            return (displayCwd(), "", 0)

        case "uname":
            #if os(iOS)
            return ("iOS PipiSandbox arm64 (Apple Neural Engine)", "", 0)
            #else
            return ("macOS PipiSandbox arm64 (Apple Silicon)", "", 0)
            #endif

        case "date":
            return (ISO8601DateFormatter().string(from: Date()), "", 0)

        case "cd":
            let target = args.first ?? ""
            if target.isEmpty || target == "~" || target == "/" {
                currentRelativePath = ""
                return ("", "", 0)
            }
            guard let resolved = resolveURL(target) else {
                return ("", "cd: permission denied outside sandbox workspace: \(target)", 1)
            }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: resolved.path, isDirectory: &isDir), isDir.boolValue else {
                return ("", "cd: no such directory: \(target)", 1)
            }
            if resolved.path == rootURL.path {
                currentRelativePath = ""
            } else {
                let prefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
                currentRelativePath = String(resolved.path.dropFirst(prefix.count))
            }
            return ("", "", 0)

        case "echo":
            return (args.joined(separator: " "), "", 0)

        case "ls":
            let showAll = args.contains(where: { $0.hasPrefix("-") && $0.contains("a") })
            let longFmt = args.contains(where: { $0.hasPrefix("-") && $0.contains("l") })
            let pathArg = args.first(where: { !$0.hasPrefix("-") }) ?? "."
            guard let dirURL = resolveURL(pathArg) else {
                return ("", "ls: path escapes sandbox: \(pathArg)", 1)
            }
            guard let names = try? fm.contentsOfDirectory(atPath: dirURL.path) else {
                return ("", "ls: cannot access '\(pathArg)'", 1)
            }
            let filtered = names.filter { showAll || !$0.hasPrefix(".") }.sorted()
            if !longFmt {
                return (filtered.joined(separator: "\n"), "", 0)
            }
            let lines = filtered.map { name -> String in
                let full = dirURL.appendingPathComponent(name).path
                let attrs = try? fm.attributesOfItem(atPath: full)
                let size = (attrs?[.size] as? Int) ?? 0
                let isDir = (attrs?[.type] as? FileAttributeType) == .typeDirectory
                return "\(isDir ? "d" : "-") \(String(format: "%7d", size))  \(name)\(isDir ? "/" : "")"
            }
            return (lines.joined(separator: "\n"), "", 0)

        case "mkdir":
            let targets = args.filter { !$0.hasPrefix("-") }
            guard !targets.isEmpty else { return ("", "mkdir: missing operand", 1) }
            for t in targets {
                guard let u = resolveURL(t) else { return ("", "mkdir: path escapes sandbox: \(t)", 1) }
                do {
                    try fm.createDirectory(at: u, withIntermediateDirectories: true)
                } catch {
                    return ("", "mkdir: \(error.localizedDescription)", 1)
                }
            }
            return ("", "", 0)

        case "touch":
            let targets = args.filter { !$0.hasPrefix("-") }
            guard !targets.isEmpty else { return ("", "touch: missing file operand", 1) }
            for t in targets {
                guard let u = resolveURL(t) else { return ("", "touch: path escapes sandbox: \(t)", 1) }
                if !fm.fileExists(atPath: u.path) {
                    try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
                    fm.createFile(atPath: u.path, contents: Data())
                }
            }
            return ("", "", 0)

        case "cat":
            if args.isEmpty {
                return (stdin, "", 0)
            }
            var chunks: [String] = []
            for p in args {
                guard let u = resolveURL(p) else { return ("", "cat: path escapes sandbox: \(p)", 1) }
                guard let text = try? String(contentsOf: u, encoding: .utf8) else {
                    return ("", "cat: \(p): No such file or unreadable", 1)
                }
                chunks.append(text)
            }
            return (chunks.joined(separator: "\n"), "", 0)

        case "head", "tail":
            var count = 10
            var files: [String] = []
            var idx = 0
            while idx < args.count {
                if args[idx] == "-n", idx + 1 < args.count, let n = Int(args[idx + 1]) {
                    count = max(1, n)
                    idx += 2
                } else if args[idx].hasPrefix("-"), let n = Int(args[idx].dropFirst()) {
                    count = max(1, n)
                    idx += 1
                } else {
                    files.append(args[idx])
                    idx += 1
                }
            }
            let input: String
            if let f = files.first {
                guard let u = resolveURL(f) else { return ("", "\(cmd): path escapes sandbox: \(f)", 1) }
                guard let text = try? String(contentsOf: u, encoding: .utf8) else {
                    return ("", "\(cmd): \(f): No such file", 1)
                }
                input = text
            } else {
                input = stdin
            }
            let lines = input.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let sliced = (cmd == "head") ? Array(lines.prefix(count)) : Array(lines.suffix(count))
            return (sliced.joined(separator: "\n"), "", 0)

        case "grep":
            let ignoreCase = args.contains(where: { $0.hasPrefix("-") && $0.contains("i") })
            let lineNumbers = args.contains(where: { $0.hasPrefix("-") && $0.contains("n") })
            let positional = args.filter { !$0.hasPrefix("-") }
            guard let pattern = positional.first else { return ("", "grep: missing pattern", 1) }
            let input: String
            if positional.count >= 2 {
                guard let u = resolveURL(positional[1]) else { return ("", "grep: path escapes sandbox", 1) }
                guard let text = try? String(contentsOf: u, encoding: .utf8) else { return ("", "grep: cannot read \(positional[1])", 1) }
                input = text
            } else {
                input = stdin
            }
            let lines = input.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var matched: [String] = []
            for (idx, line) in lines.enumerated() {
                let hit = ignoreCase
                    ? line.localizedCaseInsensitiveContains(pattern)
                    : line.contains(pattern)
                if hit {
                    matched.append(lineNumbers ? "\(idx + 1):\(line)" : line)
                }
            }
            return (matched.joined(separator: "\n"), "", matched.isEmpty ? 1 : 0)

        case "wc":
            let countLines = args.contains(where: { $0.hasPrefix("-") && $0.contains("l") })
            let countWords = args.contains(where: { $0.hasPrefix("-") && $0.contains("w") })
            let countChars = args.contains(where: { $0.hasPrefix("-") && $0.contains("c") })
            let fileArg = args.first(where: { !$0.hasPrefix("-") })
            let input: String
            if let f = fileArg {
                guard let u = resolveURL(f), let text = try? String(contentsOf: u, encoding: .utf8) else {
                    return ("", "wc: cannot read \(f)", 1)
                }
                input = text
            } else {
                input = stdin
            }
            let lines = input.isEmpty ? 0 : input.split(separator: "\n", omittingEmptySubsequences: false).count
            let words = input.split(whereSeparator: { $0.isWhitespace }).count
            let bytes = input.utf8.count
            if countLines && !countWords && !countChars { return ("\(lines)", "", 0) }
            if countWords && !countLines && !countChars { return ("\(words)", "", 0) }
            if countChars && !countLines && !countWords { return ("\(bytes)", "", 0) }
            return ("\(lines) \(words) \(bytes)", "", 0)

        case "sort":
            let reverse = args.contains(where: { $0.hasPrefix("-") && $0.contains("r") })
            let unique = args.contains(where: { $0.hasPrefix("-") && $0.contains("u") })
            let fileArg = args.first(where: { !$0.hasPrefix("-") })
            let input: String
            if let f = fileArg {
                guard let u = resolveURL(f), let text = try? String(contentsOf: u, encoding: .utf8) else {
                    return ("", "sort: cannot read \(f)", 1)
                }
                input = text
            } else {
                input = stdin
            }
            var lines = input.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            lines.sort()
            if unique {
                var seen: Set<String> = []
                lines = lines.filter { seen.insert($0).inserted }
            }
            if reverse { lines.reverse() }
            return (lines.joined(separator: "\n"), "", 0)

        case "uniq":
            let lines = stdin.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var out: [String] = []
            for l in lines where out.last != l {
                out.append(l)
            }
            return (out.joined(separator: "\n"), "", 0)

        case "find":
            let rootArg = args.first(where: { !$0.hasPrefix("-") }) ?? "."
            guard let startURL = resolveURL(rootArg) else { return ("", "find: path escapes sandbox", 1) }
            var nameFilter: String? = nil
            if let nIdx = args.firstIndex(of: "-name"), nIdx + 1 < args.count {
                nameFilter = args[nIdx + 1].replacingOccurrences(of: "*", with: "")
            }
            guard let enumerator = fm.enumerator(at: startURL, includingPropertiesForKeys: nil) else {
                return ("", "find: cannot enumerate \(rootArg)", 1)
            }
            var found: [String] = []
            let prefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
            while let fileURL = enumerator.nextObject() as? URL {
                let rel = fileURL.path.hasPrefix(prefix) ? String(fileURL.path.dropFirst(prefix.count)) : fileURL.lastPathComponent
                if let nf = nameFilter, !nf.isEmpty, !fileURL.lastPathComponent.localizedCaseInsensitiveContains(nf) {
                    continue
                }
                found.append(rel)
                if found.count >= 200 { break }
            }
            return (found.sorted().joined(separator: "\n"), "", 0)

        case "cp", "mv":
            let positional = args.filter { !$0.hasPrefix("-") }
            guard positional.count >= 2 else { return ("", "\(cmd): requires source and destination", 1) }
            guard let src = resolveURL(positional[0]), let dst = resolveURL(positional[1]) else {
                return ("", "\(cmd): path escapes sandbox", 1)
            }
            do {
                try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
                if cmd == "cp" {
                    try fm.copyItem(at: src, to: dst)
                } else {
                    try fm.moveItem(at: src, to: dst)
                }
                return ("", "", 0)
            } catch {
                return ("", "\(cmd): \(error.localizedDescription)", 1)
            }

        case "rm":
            let targets = args.filter { !$0.hasPrefix("-") }
            guard !targets.isEmpty else { return ("", "rm: missing operand", 1) }
            for t in targets {
                guard let u = resolveURL(t), u.path != rootURL.path else {
                    return ("", "rm: refused to remove sandbox root or outside path: \(t)", 1)
                }
                do {
                    try fm.removeItem(at: u)
                } catch {
                    return ("", "rm: \(error.localizedDescription)", 1)
                }
            }
            return ("", "", 0)

        case "js", "eval":
            let scriptBody: String
            if let first = args.first, first.hasSuffix(".js"), let u = resolveURL(first),
               let fileScript = try? String(contentsOf: u, encoding: .utf8) {
                scriptBody = fileScript
            } else if !args.isEmpty {
                scriptBody = args.joined(separator: " ")
            } else {
                scriptBody = stdin
            }
            let jsRes = await runJavaScript(scriptBody, source: "shell", recordTranscript: false)
            return (jsRes.stdout, jsRes.stderr, jsRes.exitCode)

        case "curl":
            guard let rawURL = args.first(where: { $0.hasPrefix("http://") || $0.hasPrefix("https://") }),
                  let url = URL(string: rawURL) else {
                return ("", "curl: provide a valid http:// or https:// URL", 1)
            }
            var req = URLRequest(url: url)
            req.timeoutInterval = 15
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 200
                let body = String(data: data.prefix(12_000), encoding: .utf8) ?? "(binary \(data.count) bytes)"
                return (body, code >= 400 ? "HTTP \(code)" : "", code >= 400 ? 1 : 0)
            } catch {
                return ("", "curl: \(error.localizedDescription)", 1)
            }

        default:
            if Self.requiresDesktopHostRelay(command: cmd) {
                return (
                    "",
                    "命令 `\(cmd)` 需要桌面/Linux 环境。请使用 `remote_node_exec` 转发至已在线的 Mac 或 Linux 节点，或在 iPhone 本机改用 `js` 脚本沙箱处理。",
                    127
                )
            }
            return ("", "pipi-sh: command not found: \(cmd) (type `help` for available mobile sandbox commands)", 127)
        }
    }

    // MARK: - Strict Sandbox Path Jail

    private func resolveURL(_ rawPath: String) -> URL? {
        Self.resolveContainedURL(rawPath, rootURL: rootURL, currentRelativePath: currentRelativePath)
    }

    public static func resolveContainedURL(_ rawPath: String, rootURL: URL, currentRelativePath: String) -> URL? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let rootStd = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = rootStd.path

        let candidate: URL
        if trimmed == "~" || trimmed == "~/PipiWorkspace" {
            candidate = rootStd
        } else if trimmed.hasPrefix("~/PipiWorkspace/") {
            let sub = String(trimmed.dropFirst("~/PipiWorkspace/".count))
            candidate = rootStd.appendingPathComponent(sub)
        } else if trimmed.hasPrefix("/") {
            // Absolute path allowed ONLY if already inside rootPath
            candidate = URL(fileURLWithPath: trimmed)
        } else {
            let base = currentRelativePath.isEmpty ? rootStd : rootStd.appendingPathComponent(currentRelativePath)
            candidate = base.appendingPathComponent(trimmed)
        }

        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        let resPath = resolved.path
        if resPath == rootPath || resPath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/") {
            return resolved
        }
        return nil
    }
}
