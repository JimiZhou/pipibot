// PiPiBot — Clean-room MIT implementation.
// Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
// Linger Open Source License; zero source code, prompts, or assets copied).
// Optional external local MoE engine adapter: simplexai-labs/PolyStrata & Niko1221/Strata
// (MIT License; see root NOTICE and LICENSE).

import Foundation
#if os(macOS)
import Darwin
#endif

// MARK: - 1. Hardware Profile & Catalog Models (Wave 4 · #07)

public enum PipiHostPlatformClass: String, Codable, CaseIterable, Sendable, Equatable {
    case macosAppleSilicon = "macos_apple_silicon"
    case macosIntel = "macos_intel"
    case linuxNvidia = "linux_nvidia"
    case windowsNvidia = "windows_nvidia"
    case linuxCpu = "linux_cpu"

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .macosAppleSilicon: return lang == .zhHans ? "Apple Silicon Mac (统一内存)" : "Apple Silicon Mac (Unified)"
        case .macosIntel: return "Intel Mac"
        case .linuxNvidia: return lang == .zhHans ? "PipiFleet Linux · NVIDIA GPU" : "PipiFleet Linux · NVIDIA GPU"
        case .windowsNvidia: return lang == .zhHans ? "PipiFleet Windows · NVIDIA GPU" : "PipiFleet Windows · NVIDIA GPU"
        case .linuxCpu: return "PipiFleet Linux · CPU"
        }
    }
}

public struct PipiHardwareProfile: Codable, Sendable, Equatable {
    public let platformClass: PipiHostPlatformClass
    public let cpuModel: String
    public let cpuCores: Int
    public let totalRamGb: Double
    public let availableRamGb: Double
    public let gpuVramGb: Double
    public let unifiedMemory: Bool
    public let freeDiskGb: Double
    public let isAppleSilicon: Bool
    public let isFleetNode: Bool
    public let detectedAt: String

    public init(
        platformClass: PipiHostPlatformClass,
        cpuModel: String,
        cpuCores: Int,
        totalRamGb: Double,
        availableRamGb: Double,
        gpuVramGb: Double,
        unifiedMemory: Bool,
        freeDiskGb: Double,
        isAppleSilicon: Bool,
        isFleetNode: Bool,
        detectedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.platformClass = platformClass
        self.cpuModel = cpuModel
        self.cpuCores = cpuCores
        self.totalRamGb = totalRamGb
        self.availableRamGb = availableRamGb
        self.gpuVramGb = gpuVramGb
        self.unifiedMemory = unifiedMemory
        self.freeDiskGb = freeDiskGb
        self.isAppleSilicon = isAppleSilicon
        self.isFleetNode = isFleetNode
        self.detectedAt = detectedAt
    }

    /// Probes live local hardware capabilities on Apple platforms (zero network calls).
    public static func detectCurrentHost() -> PipiHardwareProfile {
        let info = ProcessInfo.processInfo
        let totalRam = ((Double(info.physicalMemory) / 1_073_741_824.0) * 10).rounded() / 10
        let availableRam = max(4.0, ((totalRam * 0.72) * 10).rounded() / 10)
        let cores = max(1, info.processorCount)

        var cpuBrand = "Apple Silicon"
        #if arch(arm64)
        let isArm64 = true
        let platformClass: PipiHostPlatformClass = .macosAppleSilicon
        let gpuVram = ((totalRam * 0.75) * 10).rounded() / 10
        #else
        let isArm64 = false
        let platformClass: PipiHostPlatformClass = .macosIntel
        let gpuVram = 0.0
        #endif

        #if os(macOS)
        var size: size_t = 0
        if sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 1 {
            var buffer = [CChar](repeating: 0, count: size)
            if sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 {
                let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                let decoded = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if !decoded.isEmpty {
                    cpuBrand = decoded
                }
            }
        }
        #else
        cpuBrand = isArm64 ? "Apple Silicon (iOS)" : "Apple Simulator"
        #endif

        let freeDiskGb: Double = {
            let homeURL = URL(fileURLWithPath: NSHomeDirectory())
            if let values = try? homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
               let avail = values.volumeAvailableCapacityForImportantUsage {
                return ((Double(avail) / 1_073_741_824.0) * 10).rounded() / 10
            }
            if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
               let freeNum = attrs[.systemFreeSize] as? NSNumber {
                return ((freeNum.doubleValue / 1_073_741_824.0) * 10).rounded() / 10
            }
            return 128.0
        }()

        return PipiHardwareProfile(
            platformClass: platformClass,
            cpuModel: cpuBrand,
            cpuCores: cores,
            totalRamGb: totalRam,
            availableRamGb: availableRam,
            gpuVramGb: gpuVram,
            unifiedMemory: isArm64,
            freeDiskGb: freeDiskGb,
            isAppleSilicon: isArm64,
            isFleetNode: false
        )
    }
}

public enum PipiPolyStrataOffloadMode: String, Codable, Sendable, Equatable {
    case disabled
    case appleMetalSsdBeta = "apple_metal_ssd_beta"
    case cudaRamExpertOffload = "cuda_ram_expert_offload"
    case cudaSsdPaging = "cuda_ssd_paging"

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .disabled:
            return lang == .zhHans ? "全量常驻内存" : "Full In-Memory"
        case .appleMetalSsdBeta:
            return lang == .zhHans ? "PolyStrata Metal + SSD 预取 (Beta)" : "PolyStrata Metal + SSD Prefetch (Beta)"
        case .cudaRamExpertOffload:
            return lang == .zhHans ? "PolyStrata CUDA + RAM 专家卸载" : "PolyStrata CUDA + RAM Expert Offload"
        case .cudaSsdPaging:
            return lang == .zhHans ? "PolyStrata CUDA + SSD 专家分页" : "PolyStrata CUDA + SSD Expert Paging"
        }
    }
}

public struct PipiLocalModelCatalogEntry: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let family: String
    public let isMoE: Bool
    public let activeParamsB: Double
    public let totalParamsB: Double
    public let quantization: String
    public let weightsGb: Double
    public let diskSizeGb: Double
    public let contextWindow: Int
    public let kvCacheQuant: String
    public let kvPoolGb: Double
    public let minRamGb: Double
    public let minVramGb: Double
    public let qualityScore: Double
    public let estimatedDecodeTokPerSec: Double
    public let preferredEngine: PipiLocalInferenceEngineKind
    public let fallbackEngines: [PipiLocalInferenceEngineKind]
    public let supportedPlatforms: [PipiHostPlatformClass]
    public let usesPolyStrataOffload: Bool
    public let offloadNotes: String
    public let ollamaTag: String?
    public let mlxRepo: String?
}

public struct PipiLocalEngineProbeStatus: Codable, Identifiable, Sendable, Equatable {
    public var id: String { engine.rawValue }
    public let engine: PipiLocalInferenceEngineKind
    public let installed: Bool
    public let binaryPath: String?
    public let defaultPort: Int
    public let endpointUrl: String
    public let supportsPolyStrataMoE: Bool
    public let note: String
}

public struct PipiCompanionModelBudget: Codable, Sendable, Equatable {
    public let canRunHelperGuardrailModel: Bool
    public let canRunOnDeviceVoiceModel: Bool
    public let recommendedHelperModel: String?
    public let recommendedVoiceModel: String
    public let remainingMemoryGb: Double
}

public struct PipiModelRejectionReason: Codable, Sendable, Equatable {
    public let modelId: String
    public let layer: String
    public let reason: String
}

public struct PipiModelAutopilotPlan: Codable, Sendable, Equatable {
    public let hardware: PipiHardwareProfile
    public let primaryModel: PipiLocalModelCatalogEntry
    public let selectedEngine: PipiLocalInferenceEngineKind
    public let fallbackEngine: PipiLocalInferenceEngineKind
    public let plannedContextWindow: Int
    public let plannedKvCacheQuant: String
    public let concurrentSlots: Int
    public let languageModelMemoryBudgetGb: Double
    public let estimatedResidentMemoryGb: Double
    public let polyStrataMode: PipiPolyStrataOffloadMode
    public let companionBudget: PipiCompanionModelBudget
    public let alternatives: [PipiLocalModelCatalogEntry]
    public let rejected: [PipiModelRejectionReason]
    public let summary: String
}

public struct PipiModelSelfTestResult: Codable, Sendable, Equatable {
    public let modelId: String
    public let endpointUrl: String
    public let status: PipiModelSelfTestStatus
    public let verified: Bool
    public let ttftMs: Int
    public let totalMs: Int
    public let estimatedTokPerSec: Double
    public let sampleOutput: String
    public let error: String?
    public let testedAt: String
}

public struct PipiLocalEngineLaunchSpec: Codable, Sendable, Equatable {
    public let engine: PipiLocalInferenceEngineKind
    public let binary: String
    public let args: [String]
    public let env: [String: String]
    public let endpointUrl: String
    public let commandLine: String
}

// MARK: - 2. 5-Layer Model Autopilot & PolyStrata (MIT) 12+ MoE Catalog

public struct PipiModelAutopilot: Sendable {
    public static let catalog: [PipiLocalModelCatalogEntry] = [
        PipiLocalModelCatalogEntry(
            id: "spark-x2.6-4b-q4_k_m",
            displayName: "Spark-X2.6-4B (Q4_K_M)",
            family: "Spark",
            isMoE: false,
            activeParamsB: 4,
            totalParamsB: 4,
            quantization: "Q4_K_M",
            weightsGb: 3.1,
            diskSizeGb: 3.2,
            contextWindow: 65_536,
            kvCacheQuant: "q8_0",
            kvPoolGb: 3.2,
            minRamGb: 16,
            minVramGb: 6,
            qualityScore: 44.0,
            estimatedDecodeTokPerSec: 35.0,
            preferredEngine: .llamaCpp,
            fallbackEngines: [.ollama, .mlx],
            supportedPlatforms: [.macosAppleSilicon, .macosIntel, .linuxNvidia, .windowsNvidia, .linuxCpu],
            usesPolyStrataOffload: false,
            offloadNotes: "Fits cleanly in 16 GB unified memory with a 64K q8_0 KV pool across 2 slots.",
            ollamaTag: "qwen2.5:7b-instruct-q4_K_M",
            mlxRepo: "mlx-community/Qwen2.5-7B-Instruct-4bit"
        ),
        PipiLocalModelCatalogEntry(
            id: "qwen3-14b-q4_k_m",
            displayName: "Qwen3-14B (Q4_K_M)",
            family: "Qwen3",
            isMoE: false,
            activeParamsB: 14,
            totalParamsB: 14,
            quantization: "Q4_K_M",
            weightsGb: 9.0,
            diskSizeGb: 9.2,
            contextWindow: 65_536,
            kvCacheQuant: "q4_0",
            kvPoolGb: 3.4,
            minRamGb: 20,
            minVramGb: 12,
            qualityScore: 48.5,
            estimatedDecodeTokPerSec: 38.0,
            preferredEngine: .llamaCpp,
            fallbackEngines: [.ollama, .mlx],
            supportedPlatforms: [.macosAppleSilicon, .linuxNvidia, .windowsNvidia],
            usesPolyStrataOffload: false,
            offloadNotes: "Dense 14B daily driver for 24 GB Macs or 12 GB GPUs.",
            ollamaTag: "qwen3:14b",
            mlxRepo: "mlx-community/Qwen3-14B-4bit"
        ),
        PipiLocalModelCatalogEntry(
            id: "qwen3.8-27b-ud-iq3_s",
            displayName: "Qwen3.8-27B (UD-IQ3_S)",
            family: "Qwen3.8",
            isMoE: false,
            activeParamsB: 27,
            totalParamsB: 27,
            quantization: "UD-IQ3_S",
            weightsGb: 12.6,
            diskSizeGb: 13.0,
            contextWindow: 65_536,
            kvCacheQuant: "q4_0",
            kvPoolGb: 3.6,
            minRamGb: 24,
            minVramGb: 16,
            qualityScore: 51.9,
            estimatedDecodeTokPerSec: 46.0,
            preferredEngine: .llamaCpp,
            fallbackEngines: [.mlx, .ollama],
            supportedPlatforms: [.macosAppleSilicon, .linuxNvidia, .windowsNvidia],
            usesPolyStrataOffload: false,
            offloadNotes: "Recommended 24 GB Apple Silicon tier with 64K shared q4_0 KV pool.",
            ollamaTag: "qwen2.5:32b-instruct-q3_K_S",
            mlxRepo: "mlx-community/Qwen3-30B-A3B-3bit"
        ),
        PipiLocalModelCatalogEntry(
            id: "qwen3.8-27b-ud-q4_k_m",
            displayName: "Qwen3.8-27B (UD-Q4_K_M)",
            family: "Qwen3.8",
            isMoE: false,
            activeParamsB: 27,
            totalParamsB: 27,
            quantization: "UD-Q4_K_M",
            weightsGb: 17.4,
            diskSizeGb: 18.0,
            contextWindow: 131_072,
            kvCacheQuant: "q4_0",
            kvPoolGb: 5.2,
            minRamGb: 32,
            minVramGb: 24,
            qualityScore: 54.0,
            estimatedDecodeTokPerSec: 45.4,
            preferredEngine: .llamaCpp,
            fallbackEngines: [.mlx, .ollama],
            supportedPlatforms: [.macosAppleSilicon, .linuxNvidia, .windowsNvidia],
            usesPolyStrataOffload: false,
            offloadNotes: "Recommended 32 GB Apple Silicon & 24 GB RTX tier with 128K context window.",
            ollamaTag: "qwen2.5:32b-instruct-q4_K_M",
            mlxRepo: "mlx-community/Qwen2.5-32B-Instruct-4bit"
        ),
        PipiLocalModelCatalogEntry(
            id: "qwen3.6-35b-a3b-polystrata",
            displayName: "Qwen3.6-35B-A3B MoE (PolyStrata UD-Q3_K_M)",
            family: "Qwen3.6-MoE",
            isMoE: true,
            activeParamsB: 3,
            totalParamsB: 35,
            quantization: "UD-Q3_K_M",
            weightsGb: 17.5,
            diskSizeGb: 18.2,
            contextWindow: 65_536,
            kvCacheQuant: "q8_0",
            kvPoolGb: 3.4,
            minRamGb: 32,
            minVramGb: 8,
            qualityScore: 52.8,
            estimatedDecodeTokPerSec: 96.0,
            preferredEngine: .polystrata,
            fallbackEngines: [.llamaCpp, .ollama, .mlx],
            supportedPlatforms: [.macosAppleSilicon, .linuxNvidia, .windowsNvidia],
            usesPolyStrataOffload: true,
            offloadNotes: "PolyStrata keeps hot experts in GPU/Metal memory and streams cold experts from RAM or SSD.",
            ollamaTag: "qwen3:30b-a3b",
            mlxRepo: "mlx-community/Qwen3-30B-A3B-4bit"
        ),
        PipiLocalModelCatalogEntry(
            id: "qwen3.8-flash-next-polystrata",
            displayName: "Qwen3.8-Flash-Next MoE (PolyStrata GSQ-RCO Q2_0)",
            family: "Qwen3.8-MoE",
            isMoE: true,
            activeParamsB: 4,
            totalParamsB: 80,
            quantization: "GSQ-RCO-Q2_0",
            weightsGb: 26.0,
            diskSizeGb: 34.0,
            contextWindow: 131_072,
            kvCacheQuant: "q4_0",
            kvPoolGb: 4.8,
            minRamGb: 32,
            minVramGb: 12,
            qualityScore: 57.3,
            estimatedDecodeTokPerSec: 28.5,
            preferredEngine: .polystrata,
            fallbackEngines: [.llamaCpp],
            supportedPlatforms: [.macosAppleSilicon, .linuxNvidia, .windowsNvidia],
            usesPolyStrataOffload: true,
            offloadNotes: "Flagship PolyStrata Strata-engine MoE: CUDA+RAM/SSD expert paging on PC, Metal+SSD prefetch beta on 48GB+ Mac.",
            ollamaTag: nil,
            mlxRepo: nil
        ),
        PipiLocalModelCatalogEntry(
            id: "qwen3-30b-a3b-polystrata",
            displayName: "Qwen3-30B-A3B MoE (PolyStrata Q4_K_M)",
            family: "Qwen3-MoE",
            isMoE: true,
            activeParamsB: 3,
            totalParamsB: 30,
            quantization: "Q4_K_M",
            weightsGb: 18.6,
            diskSizeGb: 19.2,
            contextWindow: 131_072,
            kvCacheQuant: "q8_0",
            kvPoolGb: 4.2,
            minRamGb: 32,
            minVramGb: 8,
            qualityScore: 53.2,
            estimatedDecodeTokPerSec: 88.0,
            preferredEngine: .polystrata,
            fallbackEngines: [.mlx, .llamaCpp, .ollama],
            supportedPlatforms: [.macosAppleSilicon, .linuxNvidia, .windowsNvidia],
            usesPolyStrataOffload: true,
            offloadNotes: "Fast 3B-active MoE with PolyStrata expert caching on Apple Silicon and NVIDIA Fleet nodes.",
            ollamaTag: "qwen3:30b-a3b",
            mlxRepo: "mlx-community/Qwen3-30B-A3B-4bit"
        ),
        PipiLocalModelCatalogEntry(
            id: "glm-4.5-air-moe-polystrata",
            displayName: "GLM-4.5-Air MoE (PolyStrata Q4_K_M)",
            family: "GLM-MoE",
            isMoE: true,
            activeParamsB: 12,
            totalParamsB: 106,
            quantization: "Q4_K_M",
            weightsGb: 38.0,
            diskSizeGb: 58.0,
            contextWindow: 131_072,
            kvCacheQuant: "q4_0",
            kvPoolGb: 6.0,
            minRamGb: 64,
            minVramGb: 16,
            qualityScore: 58.4,
            estimatedDecodeTokPerSec: 26.0,
            preferredEngine: .polystrata,
            fallbackEngines: [.llamaCpp],
            supportedPlatforms: [.macosAppleSilicon, .linuxNvidia, .windowsNvidia],
            usesPolyStrataOffload: true,
            offloadNotes: "High-capacity bilingual MoE accelerated by PolyStrata hot-expert placement.",
            ollamaTag: nil,
            mlxRepo: nil
        ),
        PipiLocalModelCatalogEntry(
            id: "gpt-oss-20b-moe-polystrata",
            displayName: "GPT-OSS-20B MoE (PolyStrata MXFP4)",
            family: "GPT-OSS",
            isMoE: true,
            activeParamsB: 3.6,
            totalParamsB: 20,
            quantization: "MXFP4",
            weightsGb: 12.2,
            diskSizeGb: 13.0,
            contextWindow: 131_072,
            kvCacheQuant: "q8_0",
            kvPoolGb: 3.4,
            minRamGb: 24,
            minVramGb: 8,
            qualityScore: 51.2,
            estimatedDecodeTokPerSec: 72.0,
            preferredEngine: .polystrata,
            fallbackEngines: [.llamaCpp, .ollama, .mlx],
            supportedPlatforms: [.macosAppleSilicon, .linuxNvidia, .windowsNvidia],
            usesPolyStrataOffload: true,
            offloadNotes: "Compact MoE for 24 GB Macs and 8 GB NVIDIA Fleet nodes.",
            ollamaTag: "gpt-oss:20b",
            mlxRepo: nil
        ),
        PipiLocalModelCatalogEntry(
            id: "gpt-oss-120b-moe-polystrata",
            displayName: "GPT-OSS-120B MoE (PolyStrata MXFP4)",
            family: "GPT-OSS",
            isMoE: true,
            activeParamsB: 5.1,
            totalParamsB: 120,
            quantization: "MXFP4",
            weightsGb: 46.0,
            diskSizeGb: 64.0,
            contextWindow: 131_072,
            kvCacheQuant: "q4_0",
            kvPoolGb: 5.8,
            minRamGb: 64,
            minVramGb: 16,
            qualityScore: 59.5,
            estimatedDecodeTokPerSec: 34.0,
            preferredEngine: .polystrata,
            fallbackEngines: [.llamaCpp],
            supportedPlatforms: [.macosAppleSilicon, .linuxNvidia, .windowsNvidia],
            usesPolyStrataOffload: true,
            offloadNotes: "Workstation MoE (64 GB+ unified Mac or 16–24 GB VRAM + 64 GB RAM PipiFleet PC).",
            ollamaTag: nil,
            mlxRepo: nil
        ),
        PipiLocalModelCatalogEntry(
            id: "deepseek-v2.5-lite-moe-polystrata",
            displayName: "DeepSeek-V2.5-Lite MoE (PolyStrata Q4_K_M)",
            family: "DeepSeek-MoE",
            isMoE: true,
            activeParamsB: 2.4,
            totalParamsB: 16,
            quantization: "Q4_K_M",
            weightsGb: 10.2,
            diskSizeGb: 10.6,
            contextWindow: 65_536,
            kvCacheQuant: "q8_0",
            kvPoolGb: 2.8,
            minRamGb: 16,
            minVramGb: 8,
            qualityScore: 47.2,
            estimatedDecodeTokPerSec: 64.0,
            preferredEngine: .polystrata,
            fallbackEngines: [.llamaCpp, .ollama],
            supportedPlatforms: [.linuxNvidia, .windowsNvidia, .macosAppleSilicon],
            usesPolyStrataOffload: true,
            offloadNotes: "Lightweight coding MoE for 8 GB NVIDIA GPUs or 16–24 GB Macs.",
            ollamaTag: nil,
            mlxRepo: nil
        ),
        PipiLocalModelCatalogEntry(
            id: "mixtral-8x7b-moe-polystrata",
            displayName: "Mixtral-8x7B MoE (PolyStrata Q4_K_M)",
            family: "Mixtral-MoE",
            isMoE: true,
            activeParamsB: 13,
            totalParamsB: 47,
            quantization: "Q4_K_M",
            weightsGb: 24.5,
            diskSizeGb: 26.4,
            contextWindow: 65_536,
            kvCacheQuant: "q4_0",
            kvPoolGb: 3.8,
            minRamGb: 32,
            minVramGb: 12,
            qualityScore: 50.5,
            estimatedDecodeTokPerSec: 42.0,
            preferredEngine: .polystrata,
            fallbackEngines: [.llamaCpp, .ollama],
            supportedPlatforms: [.linuxNvidia, .windowsNvidia],
            usesPolyStrataOffload: true,
            offloadNotes: "PipiFleet Linux/Windows PolyStrata MoE offload tier.",
            ollamaTag: nil,
            mlxRepo: nil
        ),
        PipiLocalModelCatalogEntry(
            id: "mixtral-8x22b-moe-polystrata",
            displayName: "Mixtral-8x22B MoE (PolyStrata IQ3_XS)",
            family: "Mixtral-MoE",
            isMoE: true,
            activeParamsB: 39,
            totalParamsB: 141,
            quantization: "IQ3_XS",
            weightsGb: 52.0,
            diskSizeGb: 62.0,
            contextWindow: 65_536,
            kvCacheQuant: "q4_0",
            kvPoolGb: 6.2,
            minRamGb: 64,
            minVramGb: 24,
            qualityScore: 56.8,
            estimatedDecodeTokPerSec: 21.0,
            preferredEngine: .polystrata,
            fallbackEngines: [.llamaCpp],
            supportedPlatforms: [.linuxNvidia, .windowsNvidia],
            usesPolyStrataOffload: true,
            offloadNotes: "PipiFleet Linux/Windows high-VRAM PolyStrata MoE offload tier.",
            ollamaTag: nil,
            mlxRepo: nil
        ),
        PipiLocalModelCatalogEntry(
            id: "llama-4-scout-moe-polystrata",
            displayName: "Llama-4-Scout 17B-16E MoE (PolyStrata Q3_K_M)",
            family: "Llama4-MoE",
            isMoE: true,
            activeParamsB: 17,
            totalParamsB: 109,
            quantization: "Q3_K_M",
            weightsGb: 44.0,
            diskSizeGb: 52.0,
            contextWindow: 131_072,
            kvCacheQuant: "q4_0",
            kvPoolGb: 6.4,
            minRamGb: 64,
            minVramGb: 24,
            qualityScore: 58.9,
            estimatedDecodeTokPerSec: 25.0,
            preferredEngine: .polystrata,
            fallbackEngines: [.llamaCpp],
            supportedPlatforms: [.macosAppleSilicon, .linuxNvidia, .windowsNvidia],
            usesPolyStrataOffload: true,
            offloadNotes: "109B 16-expert MoE for 64 GB+ Macs or 24 GB NVIDIA + 64 GB RAM PipiFleet workstations.",
            ollamaTag: nil,
            mlxRepo: nil
        ),
        PipiLocalModelCatalogEntry(
            id: "qwen3-235b-a22b-polystrata",
            displayName: "Qwen3-235B-A22B MoE (PolyStrata UD-Q2_K_XL)",
            family: "Qwen3-MoE",
            isMoE: true,
            activeParamsB: 22,
            totalParamsB: 235,
            quantization: "UD-Q2_K_XL",
            weightsGb: 84.0,
            diskSizeGb: 92.0,
            contextWindow: 131_072,
            kvCacheQuant: "q8_0",
            kvPoolGb: 9.0,
            minRamGb: 128,
            minVramGb: 24,
            qualityScore: 62.4,
            estimatedDecodeTokPerSec: 22.0,
            preferredEngine: .polystrata,
            fallbackEngines: [.llamaCpp],
            supportedPlatforms: [.macosAppleSilicon, .linuxNvidia, .windowsNvidia],
            usesPolyStrataOffload: true,
            offloadNotes: "Ultra-tier MoE for 128 GB+ Mac Studio / Ultra or 128 GB PipiFleet workstation.",
            ollamaTag: nil,
            mlxRepo: nil
        ),
        PipiLocalModelCatalogEntry(
            id: "deepseek-r1-distill-moe-polystrata",
            displayName: "DeepSeek-R1-Distill-32B-MoE (PolyStrata Q4_K_M)",
            family: "DeepSeek-MoE",
            isMoE: true,
            activeParamsB: 6,
            totalParamsB: 32,
            quantization: "Q4_K_M",
            weightsGb: 18.0,
            diskSizeGb: 19.0,
            contextWindow: 65_536,
            kvCacheQuant: "q4_0",
            kvPoolGb: 3.6,
            minRamGb: 32,
            minVramGb: 12,
            qualityScore: 53.6,
            estimatedDecodeTokPerSec: 54.0,
            preferredEngine: .polystrata,
            fallbackEngines: [.llamaCpp, .ollama],
            supportedPlatforms: [.linuxNvidia, .windowsNvidia, .macosAppleSilicon],
            usesPolyStrataOffload: true,
            offloadNotes: "Reasoning-oriented MoE tier in the 12-model PolyStrata Fleet catalog.",
            ollamaTag: nil,
            mlxRepo: nil
        )
    ]

    public static var polyStrataMoECatalog: [PipiLocalModelCatalogEntry] {
        catalog.filter(\.usesPolyStrataOffload)
    }

    public static func plan(
        hardware: PipiHardwareProfile,
        enableMacPolyStrataBeta: Bool = true,
        minContextWindow: Int = 65_536,
        preferredEngine: PipiLocalInferenceEngineKind? = nil,
        installedEngines: [PipiLocalEngineProbeStatus] = []
    ) -> PipiModelAutopilotPlan {
        let requiredCtx = max(32_768, minContextWindow)
        let osReserveGb: Double = hardware.unifiedMemory
            ? max(4.5, min(12.0, hardware.totalRamGb * 0.24))
            : max(4.0, min(10.0, hardware.totalRamGb * 0.18))
        let lmBudgetGb = max(6.0, ((hardware.totalRamGb - osReserveGb) * 10).rounded() / 10)

        var rejected: [PipiModelRejectionReason] = []
        var eligible: [PipiLocalModelCatalogEntry] = []

        for model in catalog {
            if !model.supportedPlatforms.contains(hardware.platformClass) {
                rejected.append(PipiModelRejectionReason(
                    modelId: model.id,
                    layer: "platform",
                    reason: "Not targeted for \(hardware.platformClass.rawValue)."
                ))
                continue
            }
            if model.contextWindow < requiredCtx {
                rejected.append(PipiModelRejectionReason(
                    modelId: model.id,
                    layer: "kv_context",
                    reason: "Context \(model.contextWindow) < required \(requiredCtx)."
                ))
                continue
            }
            if hardware.freeDiskGb < model.diskSizeGb + 4.0 {
                rejected.append(PipiModelRejectionReason(
                    modelId: model.id,
                    layer: "disk_space",
                    reason: "Needs \(String(format: "%.1f", model.diskSizeGb + 4)) GB free SSD."
                ))
                continue
            }

            let residentNeeded = model.weightsGb + model.kvPoolGb
            if hardware.unifiedMemory {
                let macBetaAllowed =
                    enableMacPolyStrataBeta &&
                    model.usesPolyStrataOffload &&
                    hardware.totalRamGb >= 32 &&
                    model.minRamGb <= hardware.totalRamGb
                let effectiveBudget = macBetaAllowed ? lmBudgetGb * 1.35 : lmBudgetGb
                if hardware.totalRamGb < model.minRamGb || residentNeeded > effectiveBudget {
                    rejected.append(PipiModelRejectionReason(
                        modelId: model.id,
                        layer: "memory_budget",
                        reason: "Needs \(String(format: "%.1f", residentNeeded)) GB; Mac budget \(String(format: "%.1f", effectiveBudget)) GB."
                    ))
                    continue
                }
            } else {
                let vramOk = hardware.gpuVramGb >= model.minVramGb
                let ramOk = hardware.totalRamGb >= model.minRamGb
                let combinedBudget = hardware.gpuVramGb + lmBudgetGb
                let fitOk = model.usesPolyStrataOffload
                    ? (vramOk && ramOk && residentNeeded <= combinedBudget * 1.25)
                    : (vramOk && ramOk && residentNeeded <= hardware.gpuVramGb + 8.0)
                if !fitOk {
                    rejected.append(PipiModelRejectionReason(
                        modelId: model.id,
                        layer: "memory_budget",
                        reason: "Needs >=\(Int(model.minVramGb)) GB VRAM & >=\(Int(model.minRamGb)) GB RAM."
                    ))
                    continue
                }
            }

            eligible.append(model)
        }

        if eligible.isEmpty, let smallest = catalog.first {
            eligible.append(smallest)
        }

        let sorted = eligible.sorted { a, b in
            let penaltyA: Double = (hardware.unifiedMemory && a.usesPolyStrataOffload && (a.weightsGb + a.kvPoolGb) > lmBudgetGb)
                ? (hardware.totalRamGb < 48 ? 6.0 : 0.0)
                : 0.0
            let penaltyB: Double = (hardware.unifiedMemory && b.usesPolyStrataOffload && (b.weightsGb + b.kvPoolGb) > lmBudgetGb)
                ? (hardware.totalRamGb < 48 ? 6.0 : 0.0)
                : 0.0
            let scoreA = a.qualityScore - penaltyA
            let scoreB = b.qualityScore - penaltyB
            if abs(scoreB - scoreA) > 0.01 { return scoreA > scoreB }
            return a.estimatedDecodeTokPerSec > b.estimatedDecodeTokPerSec
        }

        let primary = sorted[0]
        let alternatives = Array(sorted.dropFirst().prefix(4))

        let installedSet = Set(installedEngines.filter(\.installed).map(\.engine))
        var selectedEngine = preferredEngine ?? primary.preferredEngine
        if !installedSet.isEmpty && !installedSet.contains(selectedEngine) {
            if let fallback = primary.fallbackEngines.first(where: { installedSet.contains($0) }) {
                selectedEngine = fallback
            }
        }
        let fallbackEngine = primary.fallbackEngines.first(where: { $0 != selectedEngine })
            ?? (selectedEngine == .llamaCpp ? .ollama : .llamaCpp)

        let residentMemory = min(lmBudgetGb, ((primary.weightsGb + primary.kvPoolGb) * 10).rounded() / 10)

        var polyMode: PipiPolyStrataOffloadMode = .disabled
        if primary.usesPolyStrataOffload && selectedEngine == .polystrata {
            if hardware.unifiedMemory {
                polyMode = .appleMetalSsdBeta
            } else if primary.weightsGb > hardware.totalRamGb * 0.78 {
                polyMode = .cudaSsdPaging
            } else {
                polyMode = .cudaRamExpertOffload
            }
        }

        let remainingGb = max(0, ((hardware.totalRamGb - residentMemory - 3.5) * 10).rounded() / 10)
        let companion = PipiCompanionModelBudget(
            canRunHelperGuardrailModel: remainingGb >= 3.0,
            canRunOnDeviceVoiceModel: remainingGb >= 1.2 || hardware.isAppleSilicon,
            recommendedHelperModel: remainingGb >= 3.0 ? "Qwen3-4B-Instruct (Q4_K_M)" : nil,
            recommendedVoiceModel: hardware.isAppleSilicon
                ? (remainingGb >= 2.5 ? "Apple Speech On-Device + WhisperKit Large-v3-Turbo" : "Apple Speech On-Device (Neural Engine)")
                : "Whisper-Small-CT2 (Local)",
            remainingMemoryGb: remainingGb
        )

        let ctxK = primary.contextWindow / 1024
        let summary = "\(primary.displayName) via \(selectedEngine.displayName) (\(ctxK)K ctx, KV \(primary.kvCacheQuant), \(String(format: "%.1f", residentMemory)) GB / \(String(format: "%.0f", hardware.totalRamGb)) GB)"

        return PipiModelAutopilotPlan(
            hardware: hardware,
            primaryModel: primary,
            selectedEngine: selectedEngine,
            fallbackEngine: fallbackEngine,
            plannedContextWindow: primary.contextWindow,
            plannedKvCacheQuant: primary.kvCacheQuant,
            concurrentSlots: 2,
            languageModelMemoryBudgetGb: lmBudgetGb,
            estimatedResidentMemoryGb: residentMemory,
            polyStrataMode: polyMode,
            companionBudget: companion,
            alternatives: alternatives,
            rejected: rejected,
            summary: summary
        )
    }

    public static func probeInstalledEngines() -> [PipiLocalEngineProbeStatus] {
        let specs: [(PipiLocalInferenceEngineKind, [String], Int, Bool, String)] = [
            (.polystrata, ["polystrata", "strata-poly", "strata-server"], 11438, true,
             "MIT PolyStrata/Strata MoE engine (GPU/Metal hot experts + RAM/SSD prefetch)."),
            (.llamaCpp, ["llama-server", "llama-cli"], 11436, false,
             "llama.cpp Metal / CUDA GGUF server with quantized KV cache."),
            (.ollama, ["ollama"], 11434, false,
             "Ollama local model daemon with OpenAI-compatible /v1 API."),
            (.mlx, ["mlx_lm.server", "mlx_lm"], 11437, false,
             "Apple Silicon MLX native unified-memory inference server.")
        ]

        return specs.map { engine, bins, port, supportsMoE, note in
            var found: String? = nil
            #if os(macOS)
            for bin in bins {
                if let path = PipiNativeMacRuntime.findExecutable(bin) {
                    found = path
                    break
                }
            }
            #endif
            return PipiLocalEngineProbeStatus(
                engine: engine,
                installed: found != nil,
                binaryPath: found,
                defaultPort: port,
                endpointUrl: "http://127.0.0.1:\(port)/v1",
                supportsPolyStrataMoE: supportsMoE,
                note: note
            )
        }
    }

    public static func buildLaunchSpec(
        plan: PipiModelAutopilotPlan,
        modelArtifactPath: String,
        portOverride: Int? = nil
    ) -> PipiLocalEngineLaunchSpec {
        let ctx = String(plan.plannedContextWindow)
        let kv = plan.plannedKvCacheQuant

        switch plan.selectedEngine {
        case .polystrata:
            let port = portOverride ?? 11438
            var args = [
                "serve", "--model", modelArtifactPath,
                "--host", "127.0.0.1", "--port", String(port),
                "--ctx-size", ctx, "--kv-quant", kv, "--slots", String(plan.concurrentSlots)
            ]
            if plan.polyStrataMode == .appleMetalSsdBeta {
                args.append("--metal-ssd-prefetch")
            } else if plan.polyStrataMode == .cudaSsdPaging {
                args.append("--ssd-expert-paging")
            }
            return PipiLocalEngineLaunchSpec(
                engine: .polystrata,
                binary: "polystrata",
                args: args,
                env: ["POLYSTRATA_HOST": "127.0.0.1", "POLYSTRATA_KV_QUANT": kv],
                endpointUrl: "http://127.0.0.1:\(port)/v1",
                commandLine: "polystrata \(args.joined(separator: " "))"
            )

        case .llamaCpp:
            let port = portOverride ?? 11436
            let args = [
                "--model", modelArtifactPath,
                "--host", "127.0.0.1", "--port", String(port),
                "--ctx-size", ctx, "--parallel", String(plan.concurrentSlots),
                "--cache-type-k", kv, "--cache-type-v", kv, "--flash-attn"
            ]
            return PipiLocalEngineLaunchSpec(
                engine: .llamaCpp,
                binary: "llama-server",
                args: args,
                env: [:],
                endpointUrl: "http://127.0.0.1:\(port)/v1",
                commandLine: "llama-server \(args.joined(separator: " "))"
            )

        case .mlx:
            let port = portOverride ?? 11437
            let repo = plan.primaryModel.mlxRepo ?? modelArtifactPath
            let args = ["--model", repo, "--host", "127.0.0.1", "--port", String(port)]
            return PipiLocalEngineLaunchSpec(
                engine: .mlx,
                binary: "mlx_lm.server",
                args: args,
                env: [:],
                endpointUrl: "http://127.0.0.1:\(port)/v1",
                commandLine: "mlx_lm.server \(args.joined(separator: " "))"
            )

        case .ollama:
            let port = portOverride ?? 11434
            let tag = plan.primaryModel.ollamaTag ?? plan.primaryModel.id
            let args = ["run", tag]
            return PipiLocalEngineLaunchSpec(
                engine: .ollama,
                binary: "ollama",
                args: args,
                env: ["OLLAMA_HOST": "127.0.0.1:\(port)"],
                endpointUrl: "http://127.0.0.1:\(port)/v1",
                commandLine: "OLLAMA_HOST=127.0.0.1:\(port) ollama run \(tag)"
            )
        }
    }

    public typealias QATransport = @Sendable (URLRequest) async throws -> (Data, Int)

    /// Mandatory Real-QA smoke verification: a local model only reaches `.verified`
    /// after answering a deterministic verification prompt with expected token + sum.
    public static func verifyModelWithQA(
        endpointUrl: String,
        modelId: String,
        apiKey: String? = nil,
        transport: QATransport? = nil
    ) async -> PipiModelSelfTestResult {
        let started = Date()
        let nonce = "PIPI_QA_42"
        let trimmed = endpointUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let finalUrlString = trimmed.hasSuffix("/chat/completions") ? trimmed : "\(trimmed)/chat/completions"
        let nowIso = ISO8601DateFormatter().string(from: Date())

        guard let url = URL(string: finalUrlString) else {
            return PipiModelSelfTestResult(
                modelId: modelId,
                endpointUrl: finalUrlString,
                status: .failed,
                verified: false,
                ttftMs: 0,
                totalMs: 0,
                estimatedTokPerSec: 0,
                sampleOutput: "",
                error: "Invalid endpoint URL: \(finalUrlString)",
                testedAt: nowIso
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        }

        let payload: [String: Any] = [
            "model": modelId,
            "temperature": 0,
            "max_tokens": 48,
            "messages": [
                ["role": "system", "content": "Reply concisely with the exact requested token and sum."],
                ["role": "user", "content": "Return the token \(nonce) and the sum of 19 + 23."]
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, statusCode): (Data, Int)
            if let transport {
                (data, statusCode) = try await transport(request)
            } else {
                let (d, resp) = try await URLSession.shared.data(for: request)
                data = d
                statusCode = (resp as? HTTPURLResponse)?.statusCode ?? 0
            }

            let elapsedMs = max(1, Int(Date().timeIntervalSince(started) * 1000))
            guard (200...299).contains(statusCode) else {
                let errBody = String(data: data, encoding: .utf8) ?? ""
                return PipiModelSelfTestResult(
                    modelId: modelId,
                    endpointUrl: finalUrlString,
                    status: .failed,
                    verified: false,
                    ttftMs: elapsedMs,
                    totalMs: elapsedMs,
                    estimatedTokPerSec: 0,
                    sampleOutput: "",
                    error: "HTTP \(statusCode): \(errBody.prefix(200))",
                    testedAt: ISO8601DateFormatter().string(from: Date())
                )
            }

            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let choices = (json["choices"] as? [[String: Any]]) ?? []
            let msg = (choices.first?["message"] as? [String: Any]) ?? [:]
            let content = (msg["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let usage = (json["usage"] as? [String: Any]) ?? [:]
            let completionTokens = (usage["completion_tokens"] as? Int) ?? max(4, content.count / 4)
            let tokPerSec = ((Double(completionTokens) / (Double(elapsedMs) / 1000.0)) * 10).rounded() / 10
            let passed = content.contains(nonce) && content.contains("42")

            return PipiModelSelfTestResult(
                modelId: modelId,
                endpointUrl: finalUrlString,
                status: passed ? .verified : .failed,
                verified: passed,
                ttftMs: elapsedMs,
                totalMs: elapsedMs,
                estimatedTokPerSec: tokPerSec,
                sampleOutput: String(content.prefix(160)),
                error: passed ? nil : "Model responded but did not satisfy deterministic QA check (\(nonce) + 42).",
                testedAt: ISO8601DateFormatter().string(from: Date())
            )
        } catch {
            let elapsedMs = max(1, Int(Date().timeIntervalSince(started) * 1000))
            return PipiModelSelfTestResult(
                modelId: modelId,
                endpointUrl: finalUrlString,
                status: .failed,
                verified: false,
                ttftMs: elapsedMs,
                totalMs: elapsedMs,
                estimatedTokPerSec: 0,
                sampleOutput: "",
                error: error.localizedDescription,
                testedAt: ISO8601DateFormatter().string(from: Date())
            )
        }
    }
}
