// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// Mainstream Local LLM Platform Auto-Detection & One-Click Model Launcher
// Supports Ollama, LM Studio, llama.cpp, MLX (Apple Silicon), vLLM, and PolyStrata.

import Foundation

public enum PipiLocalModelPlatformKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case ollama
    case lmStudio = "lm_studio"
    case llamaCpp = "llama_cpp"
    case mlx
    case vllm
    case polystrata

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .lmStudio: return "LM Studio"
        case .llamaCpp: return "llama.cpp"
        case .mlx: return "MLX (Apple Silicon)"
        case .vllm: return "vLLM"
        case .polystrata: return "PolyStrata"
        }
    }

    public var defaultPort: Int {
        switch self {
        case .ollama: return 11434
        case .lmStudio: return 1234
        case .llamaCpp: return 8080
        case .mlx: return 8085
        case .vllm: return 8000
        case .polystrata: return 11438
        }
    }

    public var openAIBaseURL: String {
        switch self {
        case .ollama: return "http://127.0.0.1:\(defaultPort)"
        default: return "http://127.0.0.1:\(defaultPort)/v1"
        }
    }

    public var providerKind: PipiLLMProviderKind {
        switch self {
        case .ollama: return .ollama
        default: return .customOpenAI
        }
    }

    public var defaultFallbackModelId: String {
        switch self {
        case .ollama: return "qwen2.5:14b"
        case .lmStudio: return "local-model"
        case .llamaCpp: return "local-gguf"
        case .mlx: return "mlx-community/Qwen2.5-7B-Instruct-4bit"
        case .vllm: return "Qwen/Qwen2.5-7B-Instruct"
        case .polystrata: return "qwen3.8-27b-ud-q4_k_m"
        }
    }

    public var installHint: String {
        switch self {
        case .ollama: return "brew install ollama"
        case .lmStudio: return "lmstudio.ai"
        case .llamaCpp: return "brew install llama.cpp"
        case .mlx: return "pip install mlx-lm"
        case .vllm: return "pip install vllm"
        case .polystrata: return "github.com/simplexai-labs/PolyStrata"
        }
    }
}

public struct PipiLocalPlatformStatus: Identifiable, Sendable, Equatable {
    public let kind: PipiLocalModelPlatformKind
    public let installed: Bool
    public let running: Bool
    public let binaryPath: String?
    public let appBundlePath: String?
    public let baseURL: String
    public let availableModels: [String]
    public let activeModelId: String?
    public let managedByPipiBot: Bool

    public var id: String { kind.rawValue }

    public init(
        kind: PipiLocalModelPlatformKind,
        installed: Bool,
        running: Bool,
        binaryPath: String? = nil,
        appBundlePath: String? = nil,
        baseURL: String,
        availableModels: [String] = [],
        activeModelId: String? = nil,
        managedByPipiBot: Bool = false
    ) {
        self.kind = kind
        self.installed = installed
        self.running = running
        self.binaryPath = binaryPath
        self.appBundlePath = appBundlePath
        self.baseURL = baseURL
        self.availableModels = availableModels
        self.activeModelId = activeModelId
        self.managedByPipiBot = managedByPipiBot
    }
}

public struct PipiLocalLaunchResult: Sendable, Equatable {
    public let succeeded: Bool
    public let platform: PipiLocalModelPlatformKind
    public let modelId: String
    public let baseURL: String
    public let message: String

    public init(
        succeeded: Bool,
        platform: PipiLocalModelPlatformKind,
        modelId: String,
        baseURL: String,
        message: String
    ) {
        self.succeeded = succeeded
        self.platform = platform
        self.modelId = modelId
        self.baseURL = baseURL
        self.message = message
    }
}

@MainActor
@Observable
public final class PipiLocalModelPlatformManager {
    public private(set) var platforms: [PipiLocalPlatformStatus] = []
    public private(set) var isScanning: Bool = false
    public private(set) var launchingPlatform: PipiLocalModelPlatformKind? = nil
    public private(set) var lastLaunchNote: String? = nil

    #if os(macOS)
    private var managedProcesses: [PipiLocalModelPlatformKind: Process] = [:]
    #endif
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public var installedPlatforms: [PipiLocalPlatformStatus] {
        platforms.filter { $0.installed || $0.running }
    }

    public var runningPlatforms: [PipiLocalPlatformStatus] {
        platforms.filter { $0.running }
    }

    // MARK: Pure Response & Disk Scanners (Unit-Testable)

    public nonisolated static func parseOllamaTagsJSON(_ data: Data) -> [String] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let models = root["models"] as? [[String: Any]] else {
            return []
        }
        return models.compactMap { item in
            (item["name"] as? String) ?? (item["model"] as? String)
        }.filter { !$0.isEmpty }
    }

    public nonisolated static func parseOpenAIModelsJSON(_ data: Data) -> [String] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = root["data"] as? [[String: Any]] else {
            return []
        }
        return list.compactMap { $0["id"] as? String }.filter { !$0.isEmpty }
    }

    public nonisolated static func scanLocalGGUFModels(in directories: [URL], limit: Int = 20) -> [String] {
        let fm = FileManager.default
        var found: [String] = []
        for dir in directories {
            guard fm.fileExists(atPath: dir.path) else { continue }
            guard let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension.lowercased() == "gguf" {
                    found.append(fileURL.path)
                    if found.count >= limit { return found }
                }
            }
        }
        return found
    }

    public nonisolated static func scanLocalMLXModels(in cacheHubDir: URL, limit: Int = 20) -> [String] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: cacheHubDir.path) else { return [] }
        var out: [String] = []
        for entry in entries where entry.hasPrefix("models--") {
            let stripped = String(entry.dropFirst("models--".count))
            let repoId = stripped.replacingOccurrences(of: "--", with: "/")
            if repoId.lowercased().contains("mlx") {
                out.append(repoId)
                if out.count >= limit { break }
            }
        }
        return out.sorted()
    }

    // MARK: Discovery

    @discardableResult
    public func scanInstalledPlatforms() async -> [PipiLocalPlatformStatus] {
        isScanning = true
        defer { isScanning = false }

        var results: [PipiLocalPlatformStatus] = []
        for kind in PipiLocalModelPlatformKind.allCases {
            let status = await probePlatform(kind)
            results.append(status)
        }
        self.platforms = results
        return results
    }

    private func probePlatform(_ kind: PipiLocalModelPlatformKind) async -> PipiLocalPlatformStatus {
        #if os(macOS)
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        let binaryPath: String?
        let appBundlePath: String?
        switch kind {
        case .ollama:
            binaryPath = PipiNativeMacRuntime.findExecutable("ollama")
            appBundlePath = fm.fileExists(atPath: "/Applications/Ollama.app") ? "/Applications/Ollama.app" : nil
        case .lmStudio:
            let lmsCandidates = [
                home.appendingPathComponent(".lmstudio/bin/lms").path,
                home.appendingPathComponent(".cache/lm-studio/bin/lms").path
            ]
            binaryPath = PipiNativeMacRuntime.findExecutable("lms")
                ?? lmsCandidates.first(where: { fm.isExecutableFile(atPath: $0) })
            appBundlePath = fm.fileExists(atPath: "/Applications/LM Studio.app") ? "/Applications/LM Studio.app" : nil
        case .llamaCpp:
            binaryPath = PipiNativeMacRuntime.findExecutable("llama-server")
                ?? PipiNativeMacRuntime.findExecutable("llama-cli")
            appBundlePath = nil
        case .mlx:
            binaryPath = PipiNativeMacRuntime.findExecutable("mlx_lm.server")
                ?? PipiNativeMacRuntime.findExecutable("mlx_lm.generate")
            appBundlePath = nil
        case .vllm:
            binaryPath = PipiNativeMacRuntime.findExecutable("vllm")
            appBundlePath = nil
        case .polystrata:
            binaryPath = PipiNativeMacRuntime.findExecutable("polystrata")
                ?? PipiNativeMacRuntime.findExecutable("strata")
            appBundlePath = nil
        }

        // Probe HTTP health + live model list
        var running = false
        var models: [String] = []
        if kind == .ollama {
            if let data = await quickHTTPGet("http://127.0.0.1:\(kind.defaultPort)/api/tags") {
                running = true
                models = Self.parseOllamaTagsJSON(data)
            }
        } else {
            if let data = await quickHTTPGet("http://127.0.0.1:\(kind.defaultPort)/v1/models") {
                running = true
                models = Self.parseOpenAIModelsJSON(data)
            }
        }

        // Fallback local disk model discovery if engine isn't serving models yet
        if models.isEmpty {
            switch kind {
            case .llamaCpp:
                let dirs = [
                    home.appendingPathComponent("models"),
                    home.appendingPathComponent(".lmstudio/models"),
                    home.appendingPathComponent(".cache/huggingface")
                ]
                models = Self.scanLocalGGUFModels(in: dirs, limit: 12)
            case .mlx:
                let hub = home.appendingPathComponent(".cache/huggingface/hub")
                models = Self.scanLocalMLXModels(in: hub, limit: 12)
            case .polystrata:
                models = PipiModelAutopilot.catalog.prefix(6).map(\.id)
            default:
                break
            }
        }

        let isManaged = managedProcesses[kind]?.isRunning == true
        let installed = binaryPath != nil || appBundlePath != nil || running

        return PipiLocalPlatformStatus(
            kind: kind,
            installed: installed,
            running: running,
            binaryPath: binaryPath,
            appBundlePath: appBundlePath,
            baseURL: kind.openAIBaseURL,
            availableModels: models,
            activeModelId: models.first,
            managedByPipiBot: isManaged
        )
        #else
        return PipiLocalPlatformStatus(
            kind: kind,
            installed: false,
            running: false,
            baseURL: kind.openAIBaseURL
        )
        #endif
    }

    // MARK: One-Click Engine Launch & Model Warmup

    public func launchModel(platform kind: PipiLocalModelPlatformKind, modelId rawModelId: String?) async -> PipiLocalLaunchResult {
        launchingPlatform = kind
        defer { launchingPlatform = nil }

        let current = await probePlatform(kind)
        let chosenModel = (rawModelId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? rawModelId!.trimmingCharacters(in: .whitespacesAndNewlines)
            : (current.availableModels.first ?? kind.defaultFallbackModelId)

        #if os(macOS)
        // 1. Start engine server if not currently running
        if !current.running {
            let started = await startEngineServer(kind: kind, status: current, modelId: chosenModel)
            if !started.ok {
                lastLaunchNote = started.message
                return PipiLocalLaunchResult(
                    succeeded: false,
                    platform: kind,
                    modelId: chosenModel,
                    baseURL: kind.openAIBaseURL,
                    message: started.message
                )
            }
        }

        // 2. Warmup / load model when supported
        if kind == .ollama {
            if !current.availableModels.contains(where: { $0.lowercased() == chosenModel.lowercased() }),
               let bin = current.binaryPath {
                _ = runQuickProcess(executable: bin, arguments: ["pull", chosenModel])
            }
            await warmupOllamaModel(chosenModel, port: kind.defaultPort)
        } else if kind == .lmStudio, let lmsPath = current.binaryPath {
            _ = runQuickProcess(executable: lmsPath, arguments: ["load", chosenModel])
        }

        _ = await scanInstalledPlatforms()
        let msg = "已部署并启用 \(kind.displayName) · \(chosenModel)"
        lastLaunchNote = msg
        return PipiLocalLaunchResult(
            succeeded: true,
            platform: kind,
            modelId: chosenModel,
            baseURL: kind.openAIBaseURL,
            message: msg
        )
        #else
        return PipiLocalLaunchResult(
            succeeded: false,
            platform: kind,
            modelId: chosenModel,
            baseURL: kind.openAIBaseURL,
            message: "仅 macOS 端支持拉起本地推理引擎。"
        )
        #endif
    }

    /// Maps a hardware-planned catalog entry to the best installed local platform and model identifier.
    public nonisolated static func resolveDeploymentTarget(
        for entry: PipiLocalModelCatalogEntry,
        preferredPlatform: PipiLocalModelPlatformKind? = nil,
        installed: [PipiLocalPlatformStatus]
    ) -> (platform: PipiLocalModelPlatformKind, modelTag: String) {
        let installedKinds = Set(installed.filter { $0.installed || $0.running }.map(\.kind))
        let chosenPlatform: PipiLocalModelPlatformKind = {
            if let preferredPlatform {
                return preferredPlatform
            }
            if entry.usesPolyStrataOffload, installedKinds.contains(.polystrata) {
                return .polystrata
            }
            for order: PipiLocalModelPlatformKind in [.ollama, .lmStudio, .mlx, .llamaCpp, .polystrata, .vllm] {
                if installedKinds.contains(order) {
                    return order
                }
            }
            return entry.usesPolyStrataOffload ? .polystrata : .ollama
        }()

        let modelTag: String
        switch chosenPlatform {
        case .ollama:
            modelTag = Self.ollamaTag(for: entry)
        case .mlx:
            let lower = entry.id.lowercased()
            if lower.contains("qwen") {
                modelTag = "mlx-community/Qwen2.5-7B-Instruct-4bit"
            } else if lower.contains("deepseek") {
                modelTag = "mlx-community/DeepSeek-R1-Distill-Qwen-14B-4bit"
            } else {
                modelTag = entry.id
            }
        case .llamaCpp:
            if let gguf = installed.first(where: { $0.kind == .llamaCpp })?.availableModels.first {
                modelTag = gguf
            } else {
                modelTag = entry.id
            }
        case .polystrata, .lmStudio, .vllm:
            modelTag = entry.id
        }
        return (chosenPlatform, modelTag)
    }

    private nonisolated static func ollamaTag(for entry: PipiLocalModelCatalogEntry) -> String {
        let lower = entry.id.lowercased()
        if lower.contains("qwen3") && entry.totalParamsB >= 24 { return "qwen3:30b" }
        if lower.contains("qwen3") { return "qwen3:8b" }
        if lower.contains("deepseek") { return "deepseek-r1:14b" }
        if lower.contains("llama") { return "llama3.3" }
        if lower.contains("gemma") { return "gemma3:12b" }
        if entry.totalParamsB <= 6 { return "qwen2.5:7b" }
        return "qwen2.5:14b"
    }

    /// Immediately deploys a hardware-planned model on the target local inference platform.
    public func deployPlannedModel(
        entry: PipiLocalModelCatalogEntry,
        preferredPlatform: PipiLocalModelPlatformKind? = nil
    ) async -> PipiLocalLaunchResult {
        let scanned = await scanInstalledPlatforms()
        let resolved = Self.resolveDeploymentTarget(
            for: entry,
            preferredPlatform: preferredPlatform,
            installed: scanned
        )
        let targetStatus = scanned.first(where: { $0.kind == resolved.platform })
        guard targetStatus?.installed == true || targetStatus?.running == true else {
            let hint = resolved.platform.installHint
            let msg = "未检测到 \(resolved.platform.displayName)，请先安装（\(hint)）后再点击立即部署。"
            lastLaunchNote = msg
            return PipiLocalLaunchResult(
                succeeded: false,
                platform: resolved.platform,
                modelId: resolved.modelTag,
                baseURL: resolved.platform.openAIBaseURL,
                message: msg
            )
        }
        return await launchModel(platform: resolved.platform, modelId: resolved.modelTag)
    }

    public func stopManagedServer(for kind: PipiLocalModelPlatformKind) {
        #if os(macOS)
        if let proc = managedProcesses.removeValue(forKey: kind), proc.isRunning {
            proc.terminate()
        }
        #endif
    }

    public func stopAllManagedServers() {
        #if os(macOS)
        for (_, proc) in managedProcesses where proc.isRunning {
            proc.terminate()
        }
        managedProcesses.removeAll()
        #endif
    }

    #if os(macOS)
    private func startEngineServer(
        kind: PipiLocalModelPlatformKind,
        status: PipiLocalPlatformStatus,
        modelId: String
    ) async -> (ok: Bool, message: String) {
        switch kind {
        case .ollama:
            if let bin = status.binaryPath {
                spawnManaged(kind: kind, executable: bin, arguments: ["serve"])
            } else if let appPath = status.appBundlePath {
                _ = runQuickProcess(executable: "/usr/bin/open", arguments: ["-g", appPath])
            } else {
                return (false, "未检测到 Ollama 可执行程序。")
            }

        case .lmStudio:
            if let lms = status.binaryPath {
                _ = runQuickProcess(executable: lms, arguments: ["server", "start", "--port", String(kind.defaultPort)])
            } else if let appPath = status.appBundlePath {
                _ = runQuickProcess(executable: "/usr/bin/open", arguments: ["-g", appPath])
            } else {
                return (false, "未检测到 LM Studio。")
            }

        case .llamaCpp:
            guard let bin = status.binaryPath, bin.hasSuffix("llama-server") else {
                return (false, "未检测到 llama-server，请确认已通过 brew install llama.cpp 安装。")
            }
            guard FileManager.default.fileExists(atPath: modelId) else {
                return (false, "llama-server 需要指定本机 .gguf 模型文件路径。")
            }
            spawnManaged(kind: kind, executable: bin, arguments: [
                "-m", modelId,
                "--host", "127.0.0.1",
                "--port", String(kind.defaultPort)
            ])

        case .mlx:
            guard let bin = status.binaryPath else {
                return (false, "未检测到 mlx_lm.server。")
            }
            spawnManaged(kind: kind, executable: bin, arguments: [
                "--model", modelId,
                "--host", "127.0.0.1",
                "--port", String(kind.defaultPort)
            ])

        case .vllm:
            guard let bin = status.binaryPath else {
                return (false, "未检测到 vllm。")
            }
            spawnManaged(kind: kind, executable: bin, arguments: [
                "serve", modelId,
                "--host", "127.0.0.1",
                "--port", String(kind.defaultPort)
            ])

        case .polystrata:
            guard let bin = status.binaryPath else {
                return (false, "未检测到 PolyStrata 本地引擎。")
            }
            spawnManaged(kind: kind, executable: bin, arguments: [
                "serve", "--model", modelId,
                "--host", "127.0.0.1",
                "--port", String(kind.defaultPort)
            ])
        }

        // Wait up to ~8 seconds for loopback endpoint readiness
        let probeURL = kind == .ollama
            ? "http://127.0.0.1:\(kind.defaultPort)/api/tags"
            : "http://127.0.0.1:\(kind.defaultPort)/v1/models"
        for _ in 0..<20 {
            if await quickHTTPGet(probeURL) != nil {
                return (true, "\(kind.displayName) 已就绪")
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        return (false, "\(kind.displayName) 启动超时，请确认本机服务端口 :\(kind.defaultPort) 未被占用。")
    }

    private func spawnManaged(kind: PipiLocalModelPlatformKind, executable: String, arguments: [String]) {
        stopManagedServer(for: kind)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        proc.environment = env
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            managedProcesses[kind] = proc
        } catch {
            // Ignored; readiness probe reports failure cleanly
        }
    }

    private func runQuickProcess(executable: String, arguments: [String]) -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus
        } catch {
            return -1
        }
    }

    private func warmupOllamaModel(_ modelId: String, port: Int) async {
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/generate") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["model": modelId, "prompt": "", "keep_alive": "15m", "stream": false]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await session.data(for: req)
    }
    #endif

    private func quickHTTPGet(_ urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.2
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return data
            }
            return nil
        } catch {
            return nil
        }
    }
}
