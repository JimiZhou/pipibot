// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// Zero-Code Custom ACP (Agent Client Protocol) Stdio Engine Adapter.
// - Spawns any configured ACP CLI (`my-agent acp`) with scrubbed env and optional Bot Box sandbox.
// - Discovers advertised models via a temporary ACP initialize/session handshake.
// - Translates ACP `session/request_permission` JSON-RPC callbacks into PiPiBot native approval decisions.

import Foundation

public struct PipiACPPermissionRequest: Sendable, Equatable {
    public let requestId: String
    public let toolName: String
    public let summary: String

    public init(requestId: String, toolName: String, summary: String) {
        self.requestId = requestId
        self.toolName = toolName
        self.summary = summary
    }
}

public enum PipiCustomACPEngine {
    /// Splits a CLI command line into executable and arguments while respecting basic quotes.
    public static func splitCommandLine(_ raw: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuote: Character? = nil
        for ch in raw.trimmingCharacters(in: .whitespacesAndNewlines) {
            if let q = inQuote {
                if ch == q {
                    inQuote = nil
                } else {
                    current.append(ch)
                }
            } else if ch == "\"" || ch == "'" {
                inQuote = ch
            } else if ch.isWhitespace {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Parses an ACP JSON-RPC 2.0 `session/request_permission` payload into a PiPiBot approval request.
    public static func parsePermissionRequest(jsonLine: String) -> PipiACPPermissionRequest? {
        guard let data = jsonLine.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (obj["method"] as? String) == "session/request_permission" else {
            return nil
        }
        let reqId: String
        if let s = obj["id"] as? String { reqId = s }
        else if let n = obj["id"] as? Int { reqId = String(n) }
        else { reqId = UUID().uuidString }

        let params = (obj["params"] as? [String: Any]) ?? [:]
        let tool = (params["tool"] as? String) ?? (params["title"] as? String) ?? "acp_tool"
        let summary = (params["description"] as? String) ?? (params["command"] as? String) ?? "ACP agent requests permission"
        return PipiACPPermissionRequest(requestId: reqId, toolName: tool, summary: summary)
    }

    /// Builds the JSON-RPC 2.0 response to answer an ACP `session/request_permission` callback.
    public static func formatPermissionResponse(requestId: String, allow: Bool) -> String {
        let outcome = allow ? "allow_once" : "deny"
        return "{\"jsonrpc\":\"2.0\",\"id\":\"\(requestId)\",\"result\":{\"outcome\":\"\(outcome)\"}}\n"
    }

    /// Starts a short-lived ACP stdio initialize handshake to discover models advertised by the CLI.
    /// Gracefully returns existing models if the CLI is not installed or does not advertise models.
    public static func discoverModels(
        config: PipiCustomACPEngineConfig,
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        isolationMode: PipiBotExecutionIsolationMode = .sandboxBox
    ) async -> [String] {
        #if os(macOS)
        let tokens = splitCommandLine(config.commandLine)
        guard let first = tokens.first else { return config.discoveredModels }
        let executable = first.hasPrefix("/") ? first : "/usr/bin/env"
        let baseArgs = first.hasPrefix("/") ? Array(tokens.dropFirst()) : tokens
        let wrapped = PipiBotBoxSandbox.wrapCommandIfBoxed(
            mode: isolationMode,
            executablePath: executable,
            arguments: baseArgs,
            spec: PipiBotBoxSpec(allowedWorkspacePath: workingDirectory)
        )
        defer {
            if let p = wrapped.profilePath { try? FileManager.default.removeItem(atPath: p) }
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: wrapped.executable)
        proc.arguments = wrapped.arguments
        proc.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        proc.environment = PipiCredentialBroker.buildScrubbedEnvironment()

        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            let initReq = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":1,\"clientInfo\":{\"name\":\"PiPiBot\",\"version\":\"0.15.0\"}}}\n"
            inPipe.fileHandleForWriting.write(Data(initReq.utf8))
            inPipe.fileHandleForWriting.closeFile()

            try? await Task.sleep(for: .milliseconds(600))
            if proc.isRunning { proc.terminate() }
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: outData, encoding: .utf8) ?? ""
            var discovered: [String] = []
            for line in text.components(separatedBy: .newlines) {
                guard let lineData = line.data(using: .utf8),
                      let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any],
                      let result = obj["result"] as? [String: Any],
                      let models = result["models"] as? [[String: Any]] else { continue }
                for m in models {
                    if let id = m["id"] as? String, !id.isEmpty {
                        discovered.append(id)
                    }
                }
            }
            return discovered.isEmpty ? config.discoveredModels : discovered
        } catch {
            return config.discoveredModels
        }
        #else
        return config.discoveredModels
        #endif
    }
}
