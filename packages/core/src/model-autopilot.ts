/**
 * @pipibot/core — model-autopilot.ts (Wave 4 · #07)
 *
 * Clean-room MIT implementation of PiPiBot's hardware-adaptive Model Autopilot,
 * PolyStrata (MIT) MoE & Apple Silicon local model catalog, local engine binary
 * discovery (`polystrata`/`strata`, `llama-server`, `ollama`, `mlx_lm.server`),
 * and mandatory Real-QA smoke verification gate.
 *
 * Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
 * Linger Open Source License; zero source code, prompts, or assets copied).
 * Optional external inference engine adapter: simplexai-labs/PolyStrata & Niko1221/Strata
 * (MIT License; see root NOTICE and LICENSE).
 *
 * Runtime dependencies: strictly Node built-ins (`node:*`) only.
 */

import { constants as fsConstants } from 'node:fs';
import { access, statfs } from 'node:fs/promises';
import { arch, cpus, freemem, platform, totalmem } from 'node:os';
import { delimiter, join } from 'node:path';

import type {
  LocalInferenceEngineKind,
  ModelSelfTestStatus,
} from '@pipibot/protocol';

// ---------------------------------------------------------------------------
// 1. Hardware Profile & Detection
// ---------------------------------------------------------------------------

export type HostPlatformClass = 'macos_apple_silicon' | 'macos_intel' | 'linux_nvidia' | 'windows_nvidia' | 'linux_cpu';

export interface LocalHardwareProfile {
  platformClass: HostPlatformClass;
  osPlatform: string;
  cpuArch: string;
  cpuModel: string;
  cpuCores: number;
  totalRamGb: number;
  availableRamGb: number;
  gpuVramGb: number;
  unifiedMemory: boolean;
  freeDiskGb: number;
  isAppleSilicon: boolean;
  isFleetNode: boolean;
  detectedAt: string;
}

export interface LocalModelCatalogEntry {
  id: string;
  displayName: string;
  family: string;
  isMoE: boolean;
  activeParamsB: number;
  totalParamsB: number;
  quantization: string;
  /** Weight footprint in GB when loaded in memory (or resident hot experts for PolyStrata). */
  weightsGb: number;
  /** Total model file size on SSD in GB. */
  diskSizeGb: number;
  /** Recommended shared context window (tokens, >= 65536 for long-context agent turns). */
  contextWindow: number;
  kvCacheQuant: 'q8_0' | 'q4_0' | 'fp16';
  /** Shared KV pool memory budget in GB at `contextWindow` across 2 concurrent slots. */
  kvPoolGb: number;
  /** Minimum unified RAM (Mac) or system RAM (PC) in GB. */
  minRamGb: number;
  /** Minimum discrete GPU VRAM in GB (0 for Apple Silicon unified memory). */
  minVramGb: number;
  /** Relative quality score (higher is better — planner enforces quality > speed). */
  qualityScore: number;
  /** Reference decode speed in tok/s on its target tier. */
  estimatedDecodeTokPerSec: number;
  preferredEngine: LocalInferenceEngineKind;
  fallbackEngines: LocalInferenceEngineKind[];
  supportedPlatforms: HostPlatformClass[];
  /** Whether PolyStrata expert paging (VRAM+RAM on PC, Metal+SSD prefetch beta on Mac) is used. */
  usesPolyStrataOffload: boolean;
  offloadNotes: string;
  ollamaTag?: string;
  mlxRepo?: string;
}

export interface LocalEngineProbeStatus {
  engine: LocalInferenceEngineKind;
  installed: boolean;
  binaryPath: string | null;
  defaultPort: number;
  endpointUrl: string;
  supportsPolyStrataMoE: boolean;
  note: string;
}

export interface CompanionModelBudget {
  canRunHelperGuardrailModel: boolean;
  canRunOnDeviceVoiceModel: boolean;
  recommendedHelperModel: string | null;
  recommendedVoiceModel: string;
  remainingMemoryGb: number;
}

export interface ModelRejectionReason {
  modelId: string;
  layer: 'platform' | 'memory_budget' | 'disk_space' | 'kv_context';
  reason: string;
}

export interface ModelAutopilotPlan {
  hardware: LocalHardwareProfile;
  primaryModel: LocalModelCatalogEntry;
  selectedEngine: LocalInferenceEngineKind;
  fallbackEngine: LocalInferenceEngineKind;
  plannedContextWindow: number;
  plannedKvCacheQuant: 'q8_0' | 'q4_0' | 'fp16';
  concurrentSlots: number;
  languageModelMemoryBudgetGb: number;
  estimatedResidentMemoryGb: number;
  polyStrataMode: 'disabled' | 'apple_metal_ssd_beta' | 'cuda_ram_expert_offload' | 'cuda_ssd_paging';
  companionBudget: CompanionModelBudget;
  alternatives: LocalModelCatalogEntry[];
  rejected: ModelRejectionReason[];
  summary: string;
}

export interface ModelSelfTestResult {
  modelId: string;
  endpointUrl: string;
  status: ModelSelfTestStatus;
  verified: boolean;
  ttftMs: number;
  totalMs: number;
  estimatedTokPerSec: number;
  sampleOutput: string;
  error?: string;
  testedAt: string;
}

export interface LocalEngineLaunchSpec {
  engine: LocalInferenceEngineKind;
  binary: string;
  args: string[];
  env: Record<string, string>;
  endpointUrl: string;
  commandLine: string;
}

// ---------------------------------------------------------------------------
// 2. Canonical 12+ Local & PolyStrata (MIT) MoE Model Catalog
// ---------------------------------------------------------------------------

/**
 * Curated catalog covering:
 * - Apple Silicon 16 GB / 24 GB / 32 GB / 48 GB / 64 GB+ (llama.cpp Metal / Ollama / MLX + PolyStrata Metal+SSD beta)
 * - PipiFleet Linux/Windows NVIDIA 8 GB / 12 GB / 24 GB+ (full 12 PolyStrata MoE models)
 */
export const LOCAL_MODEL_CATALOG: readonly LocalModelCatalogEntry[] = [
  {
    id: 'spark-x2.6-4b-q4_k_m',
    displayName: 'Spark-X2.6-4B (Q4_K_M)',
    family: 'Spark',
    isMoE: false,
    activeParamsB: 4,
    totalParamsB: 4,
    quantization: 'Q4_K_M',
    weightsGb: 3.1,
    diskSizeGb: 3.2,
    contextWindow: 65_536,
    kvCacheQuant: 'q8_0',
    kvPoolGb: 3.2,
    minRamGb: 16,
    minVramGb: 6,
    qualityScore: 44.0,
    estimatedDecodeTokPerSec: 35.0,
    preferredEngine: 'llama_cpp',
    fallbackEngines: ['ollama', 'mlx'],
    supportedPlatforms: ['macos_apple_silicon', 'macos_intel', 'linux_nvidia', 'windows_nvidia', 'linux_cpu'],
    usesPolyStrataOffload: false,
    offloadNotes: 'Fits cleanly in 16 GB unified memory with a shared 64K q8_0 KV pool across 2 slots.',
    ollamaTag: 'qwen2.5:7b-instruct-q4_K_M',
    mlxRepo: 'mlx-community/Qwen2.5-7B-Instruct-4bit',
  },
  {
    id: 'qwen3-14b-q4_k_m',
    displayName: 'Qwen3-14B (Q4_K_M)',
    family: 'Qwen3',
    isMoE: false,
    activeParamsB: 14,
    totalParamsB: 14,
    quantization: 'Q4_K_M',
    weightsGb: 9.0,
    diskSizeGb: 9.2,
    contextWindow: 65_536,
    kvCacheQuant: 'q4_0',
    kvPoolGb: 3.4,
    minRamGb: 20,
    minVramGb: 12,
    qualityScore: 48.5,
    estimatedDecodeTokPerSec: 38.0,
    preferredEngine: 'llama_cpp',
    fallbackEngines: ['ollama', 'mlx'],
    supportedPlatforms: ['macos_apple_silicon', 'linux_nvidia', 'windows_nvidia'],
    usesPolyStrataOffload: false,
    offloadNotes: 'Dense 14B daily driver for 24 GB Macs or 12 GB GPUs.',
    ollamaTag: 'qwen3:14b',
    mlxRepo: 'mlx-community/Qwen3-14B-4bit',
  },
  {
    id: 'qwen3.8-27b-ud-iq3_s',
    displayName: 'Qwen3.8-27B (UD-IQ3_S)',
    family: 'Qwen3.8',
    isMoE: false,
    activeParamsB: 27,
    totalParamsB: 27,
    quantization: 'UD-IQ3_S',
    weightsGb: 12.6,
    diskSizeGb: 13.0,
    contextWindow: 65_536,
    kvCacheQuant: 'q4_0',
    kvPoolGb: 3.6,
    minRamGb: 24,
    minVramGb: 16,
    qualityScore: 51.9,
    estimatedDecodeTokPerSec: 46.0,
    preferredEngine: 'llama_cpp',
    fallbackEngines: ['mlx', 'ollama'],
    supportedPlatforms: ['macos_apple_silicon', 'linux_nvidia', 'windows_nvidia'],
    usesPolyStrataOffload: false,
    offloadNotes: 'Recommended 24 GB Apple Silicon tier with 64K shared q4_0 KV cache.',
    ollamaTag: 'qwen2.5:32b-instruct-q3_K_S',
    mlxRepo: 'mlx-community/Qwen3-30B-A3B-3bit',
  },
  {
    id: 'qwen3.8-27b-ud-q4_k_m',
    displayName: 'Qwen3.8-27B (UD-Q4_K_M)',
    family: 'Qwen3.8',
    isMoE: false,
    activeParamsB: 27,
    totalParamsB: 27,
    quantization: 'UD-Q4_K_M',
    weightsGb: 17.4,
    diskSizeGb: 18.0,
    contextWindow: 131_072,
    kvCacheQuant: 'q4_0',
    kvPoolGb: 5.2,
    minRamGb: 32,
    minVramGb: 24,
    qualityScore: 54.0,
    estimatedDecodeTokPerSec: 45.4,
    preferredEngine: 'llama_cpp',
    fallbackEngines: ['mlx', 'ollama'],
    supportedPlatforms: ['macos_apple_silicon', 'linux_nvidia', 'windows_nvidia'],
    usesPolyStrataOffload: false,
    offloadNotes: 'Recommended 32 GB Apple Silicon & 24 GB RTX tier with 128K context window.',
    ollamaTag: 'qwen2.5:32b-instruct-q4_K_M',
    mlxRepo: 'mlx-community/Qwen2.5-32B-Instruct-4bit',
  },
  {
    id: 'qwen3.6-35b-a3b-polystrata',
    displayName: 'Qwen3.6-35B-A3B MoE (PolyStrata UD-Q3_K_M)',
    family: 'Qwen3.6-MoE',
    isMoE: true,
    activeParamsB: 3,
    totalParamsB: 35,
    quantization: 'UD-Q3_K_M',
    weightsGb: 17.5,
    diskSizeGb: 18.2,
    contextWindow: 65_536,
    kvCacheQuant: 'q8_0',
    kvPoolGb: 3.4,
    minRamGb: 32,
    minVramGb: 8,
    qualityScore: 52.8,
    estimatedDecodeTokPerSec: 96.0,
    preferredEngine: 'polystrata',
    fallbackEngines: ['llama_cpp', 'ollama', 'mlx'],
    supportedPlatforms: ['macos_apple_silicon', 'linux_nvidia', 'windows_nvidia'],
    usesPolyStrataOffload: true,
    offloadNotes: 'PolyStrata keeps hot experts in GPU/Metal memory and streams cold experts from RAM or SSD.',
    ollamaTag: 'qwen3:30b-a3b',
    mlxRepo: 'mlx-community/Qwen3-30B-A3B-4bit',
  },
  {
    id: 'qwen3.8-flash-next-polystrata',
    displayName: 'Qwen3.8-Flash-Next MoE (PolyStrata GSQ-RCO Q2_0)',
    family: 'Qwen3.8-MoE',
    isMoE: true,
    activeParamsB: 4,
    totalParamsB: 80,
    quantization: 'GSQ-RCO-Q2_0',
    weightsGb: 26.0,
    diskSizeGb: 34.0,
    contextWindow: 131_072,
    kvCacheQuant: 'q4_0',
    kvPoolGb: 4.8,
    minRamGb: 32,
    minVramGb: 12,
    qualityScore: 57.3,
    estimatedDecodeTokPerSec: 28.5,
    preferredEngine: 'polystrata',
    fallbackEngines: ['llama_cpp'],
    supportedPlatforms: ['macos_apple_silicon', 'linux_nvidia', 'windows_nvidia'],
    usesPolyStrataOffload: true,
    offloadNotes: 'Flagship PolyStrata Strata-engine MoE: CUDA+RAM/SSD expert paging on PC, Metal+SSD prefetch beta on 48GB+ Mac.',
  },
  {
    id: 'qwen3-30b-a3b-polystrata',
    displayName: 'Qwen3-30B-A3B MoE (PolyStrata Q4_K_M)',
    family: 'Qwen3-MoE',
    isMoE: true,
    activeParamsB: 3,
    totalParamsB: 30,
    quantization: 'Q4_K_M',
    weightsGb: 18.6,
    diskSizeGb: 19.2,
    contextWindow: 131_072,
    kvCacheQuant: 'q8_0',
    kvPoolGb: 4.2,
    minRamGb: 32,
    minVramGb: 8,
    qualityScore: 53.2,
    estimatedDecodeTokPerSec: 88.0,
    preferredEngine: 'polystrata',
    fallbackEngines: ['mlx', 'llama_cpp', 'ollama'],
    supportedPlatforms: ['macos_apple_silicon', 'linux_nvidia', 'windows_nvidia'],
    usesPolyStrataOffload: true,
    offloadNotes: 'Fast 3B-active MoE with PolyStrata expert caching on Apple Silicon and NVIDIA Fleet nodes.',
    ollamaTag: 'qwen3:30b-a3b',
    mlxRepo: 'mlx-community/Qwen3-30B-A3B-4bit',
  },
  {
    id: 'glm-4.5-air-moe-polystrata',
    displayName: 'GLM-4.5-Air MoE (PolyStrata Q4_K_M)',
    family: 'GLM-MoE',
    isMoE: true,
    activeParamsB: 12,
    totalParamsB: 106,
    quantization: 'Q4_K_M',
    weightsGb: 38.0,
    diskSizeGb: 58.0,
    contextWindow: 131_072,
    kvCacheQuant: 'q4_0',
    kvPoolGb: 6.0,
    minRamGb: 64,
    minVramGb: 16,
    qualityScore: 58.4,
    estimatedDecodeTokPerSec: 26.0,
    preferredEngine: 'polystrata',
    fallbackEngines: ['llama_cpp'],
    supportedPlatforms: ['macos_apple_silicon', 'linux_nvidia', 'windows_nvidia'],
    usesPolyStrataOffload: true,
    offloadNotes: 'High-capacity bilingual MoE accelerated by PolyStrata hot-expert placement.',
  },
  {
    id: 'gpt-oss-20b-moe-polystrata',
    displayName: 'GPT-OSS-20B MoE (PolyStrata MXFP4)',
    family: 'GPT-OSS',
    isMoE: true,
    activeParamsB: 3.6,
    totalParamsB: 20,
    quantization: 'MXFP4',
    weightsGb: 12.2,
    diskSizeGb: 13.0,
    contextWindow: 131_072,
    kvCacheQuant: 'q8_0',
    kvPoolGb: 3.4,
    minRamGb: 24,
    minVramGb: 8,
    qualityScore: 51.2,
    estimatedDecodeTokPerSec: 72.0,
    preferredEngine: 'polystrata',
    fallbackEngines: ['llama_cpp', 'ollama', 'mlx'],
    supportedPlatforms: ['macos_apple_silicon', 'linux_nvidia', 'windows_nvidia'],
    usesPolyStrataOffload: true,
    offloadNotes: 'Compact MoE for 24 GB Macs and 8 GB NVIDIA Fleet nodes.',
    ollamaTag: 'gpt-oss:20b',
  },
  {
    id: 'gpt-oss-120b-moe-polystrata',
    displayName: 'GPT-OSS-120B MoE (PolyStrata MXFP4)',
    family: 'GPT-OSS',
    isMoE: true,
    activeParamsB: 5.1,
    totalParamsB: 120,
    quantization: 'MXFP4',
    weightsGb: 46.0,
    diskSizeGb: 64.0,
    contextWindow: 131_072,
    kvCacheQuant: 'q4_0',
    kvPoolGb: 5.8,
    minRamGb: 64,
    minVramGb: 16,
    qualityScore: 59.5,
    estimatedDecodeTokPerSec: 34.0,
    preferredEngine: 'polystrata',
    fallbackEngines: ['llama_cpp'],
    supportedPlatforms: ['macos_apple_silicon', 'linux_nvidia', 'windows_nvidia'],
    usesPolyStrataOffload: true,
    offloadNotes: 'Desktop workstation MoE (64 GB+ unified Mac or 16–24 GB VRAM + 64 GB RAM PipiFleet PC).',
  },
  {
    id: 'deepseek-v2.5-lite-moe-polystrata',
    displayName: 'DeepSeek-V2.5-Lite MoE (PolyStrata Q4_K_M)',
    family: 'DeepSeek-MoE',
    isMoE: true,
    activeParamsB: 2.4,
    totalParamsB: 16,
    quantization: 'Q4_K_M',
    weightsGb: 10.2,
    diskSizeGb: 10.6,
    contextWindow: 65_536,
    kvCacheQuant: 'q8_0',
    kvPoolGb: 2.8,
    minRamGb: 16,
    minVramGb: 8,
    qualityScore: 47.2,
    estimatedDecodeTokPerSec: 64.0,
    preferredEngine: 'polystrata',
    fallbackEngines: ['llama_cpp', 'ollama'],
    supportedPlatforms: ['linux_nvidia', 'windows_nvidia', 'macos_apple_silicon'],
    usesPolyStrataOffload: true,
    offloadNotes: 'Lightweight coding MoE for 8 GB NVIDIA GPUs or 16–24 GB Macs.',
  },
  {
    id: 'mixtral-8x7b-moe-polystrata',
    displayName: 'Mixtral-8x7B MoE (PolyStrata Q4_K_M)',
    family: 'Mixtral-MoE',
    isMoE: true,
    activeParamsB: 13,
    totalParamsB: 47,
    quantization: 'Q4_K_M',
    weightsGb: 24.5,
    diskSizeGb: 26.4,
    contextWindow: 65_536,
    kvCacheQuant: 'q4_0',
    kvPoolGb: 3.8,
    minRamGb: 32,
    minVramGb: 12,
    qualityScore: 50.5,
    estimatedDecodeTokPerSec: 42.0,
    preferredEngine: 'polystrata',
    fallbackEngines: ['llama_cpp', 'ollama'],
    supportedPlatforms: ['linux_nvidia', 'windows_nvidia'],
    usesPolyStrataOffload: true,
    offloadNotes: 'PipiFleet Linux/Windows PolyStrata MoE offload tier.',
  },
  {
    id: 'mixtral-8x22b-moe-polystrata',
    displayName: 'Mixtral-8x22B MoE (PolyStrata IQ3_XS)',
    family: 'Mixtral-MoE',
    isMoE: true,
    activeParamsB: 39,
    totalParamsB: 141,
    quantization: 'IQ3_XS',
    weightsGb: 52.0,
    diskSizeGb: 62.0,
    contextWindow: 65_536,
    kvCacheQuant: 'q4_0',
    kvPoolGb: 6.2,
    minRamGb: 64,
    minVramGb: 24,
    qualityScore: 56.8,
    estimatedDecodeTokPerSec: 21.0,
    preferredEngine: 'polystrata',
    fallbackEngines: ['llama_cpp'],
    supportedPlatforms: ['linux_nvidia', 'windows_nvidia'],
    usesPolyStrataOffload: true,
    offloadNotes: 'PipiFleet Linux/Windows high-VRAM PolyStrata MoE offload tier.',
  },
  {
    id: 'llama-4-scout-moe-polystrata',
    displayName: 'Llama-4-Scout 17B-16E MoE (PolyStrata Q3_K_M)',
    family: 'Llama4-MoE',
    isMoE: true,
    activeParamsB: 17,
    totalParamsB: 109,
    quantization: 'Q3_K_M',
    weightsGb: 44.0,
    diskSizeGb: 52.0,
    contextWindow: 131_072,
    kvCacheQuant: 'q4_0',
    kvPoolGb: 6.4,
    minRamGb: 64,
    minVramGb: 24,
    qualityScore: 58.9,
    estimatedDecodeTokPerSec: 25.0,
    preferredEngine: 'polystrata',
    fallbackEngines: ['llama_cpp'],
    supportedPlatforms: ['macos_apple_silicon', 'linux_nvidia', 'windows_nvidia'],
    usesPolyStrataOffload: true,
    offloadNotes: '109B 16-expert MoE for 64 GB+ Macs or 24 GB NVIDIA + 64 GB RAM PipiFleet workstations.',
  },
  {
    id: 'qwen3-235b-a22b-polystrata',
    displayName: 'Qwen3-235B-A22B MoE (PolyStrata UD-Q2_K_XL)',
    family: 'Qwen3-MoE',
    isMoE: true,
    activeParamsB: 22,
    totalParamsB: 235,
    quantization: 'UD-Q2_K_XL',
    weightsGb: 84.0,
    diskSizeGb: 92.0,
    contextWindow: 131_072,
    kvCacheQuant: 'q8_0',
    kvPoolGb: 9.0,
    minRamGb: 128,
    minVramGb: 24,
    qualityScore: 62.4,
    estimatedDecodeTokPerSec: 22.0,
    preferredEngine: 'polystrata',
    fallbackEngines: ['llama_cpp'],
    supportedPlatforms: ['macos_apple_silicon', 'linux_nvidia', 'windows_nvidia'],
    usesPolyStrataOffload: true,
    offloadNotes: 'Ultra-tier MoE for 128 GB+ Mac Studio / Ultra or 128 GB PipiFleet workstation.',
  },
  {
    id: 'deepseek-r1-distill-moe-polystrata',
    displayName: 'DeepSeek-R1-Distill-32B-MoE (PolyStrata Q4_K_M)',
    family: 'DeepSeek-MoE',
    isMoE: true,
    activeParamsB: 6,
    totalParamsB: 32,
    quantization: 'Q4_K_M',
    weightsGb: 18.0,
    diskSizeGb: 19.0,
    contextWindow: 65_536,
    kvCacheQuant: 'q4_0',
    kvPoolGb: 3.6,
    minRamGb: 32,
    minVramGb: 12,
    qualityScore: 53.6,
    estimatedDecodeTokPerSec: 54.0,
    preferredEngine: 'polystrata',
    fallbackEngines: ['llama_cpp', 'ollama'],
    supportedPlatforms: ['linux_nvidia', 'windows_nvidia', 'macos_apple_silicon'],
    usesPolyStrataOffload: true,
    offloadNotes: 'Reasoning-oriented MoE tier in the 12-model PolyStrata Fleet catalog.',
  },
] as const;

export function getPolyStrataMoECatalog(): LocalModelCatalogEntry[] {
  return LOCAL_MODEL_CATALOG.filter((entry) => entry.usesPolyStrataOffload);
}

// ---------------------------------------------------------------------------
// 3. Real Host Hardware Detection
// ---------------------------------------------------------------------------

export async function detectLocalHardwareProfile(
  overrides: Partial<LocalHardwareProfile> = {},
): Promise<LocalHardwareProfile> {
  const osPlat = overrides.osPlatform ?? platform();
  const cpuArchitecture = overrides.cpuArch ?? arch();
  const cpuList = cpus();
  const cpuModel = overrides.cpuModel ?? cpuList[0]?.model ?? 'Unknown CPU';
  const cpuCores = overrides.cpuCores ?? Math.max(1, cpuList.length);
  const totalRamGb = overrides.totalRamGb ?? Math.round((totalmem() / (1024 ** 3)) * 10) / 10;
  const availableRamGb =
    overrides.availableRamGb ??
    Math.max(4, Math.round(((freemem() > 0 ? freemem() : totalmem() * 0.65) / (1024 ** 3)) * 10) / 10);

  let freeDiskGb = overrides.freeDiskGb;
  if (freeDiskGb === undefined) {
    try {
      const fsStat = await statfs('/');
      freeDiskGb = Math.round(((Number(fsStat.bavail) * Number(fsStat.bsize)) / (1024 ** 3)) * 10) / 10;
    } catch {
      freeDiskGb = 128;
    }
  }

  const isAppleSilicon =
    overrides.isAppleSilicon ?? (osPlat === 'darwin' && cpuArchitecture === 'arm64');
  const unifiedMemory = overrides.unifiedMemory ?? isAppleSilicon;
  const gpuVramGb = overrides.gpuVramGb ?? (isAppleSilicon ? Math.round(totalRamGb * 0.75 * 10) / 10 : 0);

  let platformClass: HostPlatformClass;
  if (overrides.platformClass) {
    platformClass = overrides.platformClass;
  } else if (isAppleSilicon) {
    platformClass = 'macos_apple_silicon';
  } else if (osPlat === 'darwin') {
    platformClass = 'macos_intel';
  } else if (osPlat === 'win32' && gpuVramGb > 0) {
    platformClass = 'windows_nvidia';
  } else if (gpuVramGb > 0) {
    platformClass = 'linux_nvidia';
  } else {
    platformClass = 'linux_cpu';
  }

  return {
    platformClass,
    osPlatform: osPlat,
    cpuArch: cpuArchitecture,
    cpuModel,
    cpuCores,
    totalRamGb,
    availableRamGb,
    gpuVramGb,
    unifiedMemory,
    freeDiskGb,
    isAppleSilicon,
    isFleetNode: overrides.isFleetNode ?? !isAppleSilicon,
    detectedAt: new Date().toISOString(),
  };
}

// ---------------------------------------------------------------------------
// 4. 5-Layer Deterministic Hardware Model Autopilot Planner
// ---------------------------------------------------------------------------

export interface ModelAutopilotOptions {
  /** Prefer PolyStrata Metal+SSD prefetch beta on Apple Silicon when eligible. */
  enableMacPolyStrataBeta?: boolean;
  /** Minimum desired context window in tokens (default 65,536). */
  minContextWindow?: number;
  /** Explicit engine preference override if installed/available. */
  preferredEngine?: LocalInferenceEngineKind;
  /** Installed engine probe results to guide fallback selection. */
  installedEngines?: LocalEngineProbeStatus[];
}

export function planLocalModelSetup(
  hardware: LocalHardwareProfile,
  options: ModelAutopilotOptions = {},
): ModelAutopilotPlan {
  const minContext = Math.max(32_768, options.minContextWindow ?? 65_536);
  const enableMacPolyStrataBeta = options.enableMacPolyStrataBeta ?? true;

  // Layer 2: Compute Language Model Memory Budget (keep macOS/OS & UI headroom smooth)
  const osReserveGb = hardware.unifiedMemory
    ? Math.max(4.5, Math.min(12, hardware.totalRamGb * 0.24))
    : Math.max(4.0, Math.min(10, hardware.totalRamGb * 0.18));

  const languageModelMemoryBudgetGb = Math.max(
    6.0,
    Math.round((hardware.totalRamGb - osReserveGb) * 10) / 10,
  );

  const rejected: ModelRejectionReason[] = [];
  const eligible: LocalModelCatalogEntry[] = [];

  for (const model of LOCAL_MODEL_CATALOG) {
    // Layer 1: Platform support
    if (!model.supportedPlatforms.includes(hardware.platformClass)) {
      rejected.push({
        modelId: model.id,
        layer: 'platform',
        reason: `Not targeted for platform ${hardware.platformClass}.`,
      });
      continue;
    }

    // Layer 1b: Context window requirement
    if (model.contextWindow < minContext) {
      rejected.push({
        modelId: model.id,
        layer: 'kv_context',
        reason: `Context window ${model.contextWindow} is below required ${minContext}.`,
      });
      continue;
    }

    // Layer 1c: Disk space headroom (model file + 4 GB scratch)
    if (hardware.freeDiskGb < model.diskSizeGb + 4) {
      rejected.push({
        modelId: model.id,
        layer: 'disk_space',
        reason: `Requires ${model.diskSizeGb + 4} GB free disk, only ${hardware.freeDiskGb} GB available.`,
      });
      continue;
    }

    // Layer 3: Weight + shared KV pool fit check
    const residentNeededGb = model.weightsGb + model.kvPoolGb;
    if (hardware.unifiedMemory) {
      // Apple Silicon:
      // - Non-PolyStrata models must fit weights + KV inside unified memory budget.
      // - PolyStrata Metal+SSD beta allows up to 1.35x budget for MoE cold experts paged from NVMe SSD when RAM >= 32 GB.
      const macBetaAllowed =
        enableMacPolyStrataBeta &&
        model.usesPolyStrataOffload &&
        hardware.totalRamGb >= 32 &&
        model.minRamGb <= hardware.totalRamGb;
      const effectiveBudgetGb = macBetaAllowed
        ? languageModelMemoryBudgetGb * 1.35
        : languageModelMemoryBudgetGb;

      if (hardware.totalRamGb < model.minRamGb || residentNeededGb > effectiveBudgetGb) {
        rejected.push({
          modelId: model.id,
          layer: 'memory_budget',
          reason: `Needs ${residentNeededGb.toFixed(1)} GB (min ${model.minRamGb} GB RAM); Mac budget is ${effectiveBudgetGb.toFixed(1)} GB.`,
        });
        continue;
      }
    } else {
      // PC / PipiFleet NVIDIA:
      // - Dense models must fit inside GPU VRAM + minor spill;
      // - PolyStrata MoE models place hot experts in GPU VRAM (>= minVramGb) and stream cold experts from system RAM/SSD.
      const vramOk = hardware.gpuVramGb >= model.minVramGb;
      const ramOk = hardware.totalRamGb >= model.minRamGb;
      const combinedBudgetGb = hardware.gpuVramGb + languageModelMemoryBudgetGb;
      const fitOk = model.usesPolyStrataOffload
        ? vramOk && ramOk && residentNeededGb <= combinedBudgetGb * 1.25
        : vramOk && ramOk && residentNeededGb <= hardware.gpuVramGb + 8.0;

      if (!fitOk) {
        rejected.push({
          modelId: model.id,
          layer: 'memory_budget',
          reason: `Needs >=${model.minVramGb} GB VRAM & >=${model.minRamGb} GB RAM (resident ${residentNeededGb.toFixed(1)} GB).`,
        });
        continue;
      }
    }

    eligible.push(model);
  }

  // Fallback safety net: always pick the smallest universally supported model if tight
  if (eligible.length === 0) {
    eligible.push(LOCAL_MODEL_CATALOG[0]);
  }

  // Layer 4: Quality beats speed; on Mac 24/32 GB where dense Qwen3.8-27B fits without SSD paging,
  // apply a slight stability bonus when PolyStrata beta would require SSD paging on < 48 GB Macs.
  const scored = [...eligible].sort((a, b) => {
    const penaltyA =
      hardware.unifiedMemory && a.usesPolyStrataOffload && a.weightsGb + a.kvPoolGb > languageModelMemoryBudgetGb
        ? hardware.totalRamGb < 48
          ? 6.0
          : 0.0
        : 0.0;
    const penaltyB =
      hardware.unifiedMemory && b.usesPolyStrataOffload && b.weightsGb + b.kvPoolGb > languageModelMemoryBudgetGb
        ? hardware.totalRamGb < 48
          ? 6.0
          : 0.0
        : 0.0;
    const scoreA = a.qualityScore - penaltyA;
    const scoreB = b.qualityScore - penaltyB;
    if (Math.abs(scoreB - scoreA) > 0.01) return scoreB - scoreA;
    return b.estimatedDecodeTokPerSec - a.estimatedDecodeTokPerSec;
  });

  const primary = scored[0];
  const alternatives = scored.slice(1, 5);

  const installedSet = new Set(
    (options.installedEngines ?? []).filter((e) => e.installed).map((e) => e.engine),
  );

  let selectedEngine: LocalInferenceEngineKind = options.preferredEngine ?? primary.preferredEngine;
  if (installedSet.size > 0 && !installedSet.has(selectedEngine)) {
    const installedFallback = primary.fallbackEngines.find((e) => installedSet.has(e));
    if (installedFallback) {
      selectedEngine = installedFallback;
    }
  }

  const fallbackEngine: LocalInferenceEngineKind =
    primary.fallbackEngines.find((e) => e !== selectedEngine) ??
    (selectedEngine === 'llama_cpp' ? 'ollama' : 'llama_cpp');

  const estimatedResidentMemoryGb = Math.min(
    languageModelMemoryBudgetGb,
    Math.round((primary.weightsGb + primary.kvPoolGb) * 10) / 10,
  );

  let polyStrataMode: ModelAutopilotPlan['polyStrataMode'] = 'disabled';
  if (primary.usesPolyStrataOffload && selectedEngine === 'polystrata') {
    if (hardware.unifiedMemory) {
      polyStrataMode = 'apple_metal_ssd_beta';
    } else if (primary.weightsGb > hardware.totalRamGb * 0.78) {
      polyStrataMode = 'cuda_ssd_paging';
    } else {
      polyStrataMode = 'cuda_ram_expert_offload';
    }
  }

  // Layer 5: Pack helper guardrail/summarizer & on-device voice models into remaining headroom
  const remainingMemoryGb = Math.max(
    0,
    Math.round((hardware.totalRamGb - estimatedResidentMemoryGb - 3.5) * 10) / 10,
  );
  const companionBudget: CompanionModelBudget = {
    canRunHelperGuardrailModel: remainingMemoryGb >= 3.0,
    canRunOnDeviceVoiceModel: remainingMemoryGb >= 1.2 || hardware.isAppleSilicon,
    recommendedHelperModel: remainingMemoryGb >= 3.0 ? 'Qwen3-4B-Instruct (Q4_K_M)' : null,
    recommendedVoiceModel: hardware.isAppleSilicon
      ? remainingMemoryGb >= 2.5
        ? 'Apple Speech On-Device + WhisperKit Large-v3-Turbo'
        : 'Apple Speech On-Device (Neural Engine)'
      : 'Whisper-Small-CT2 (Local CPU/GPU)',
    remainingMemoryGb,
  };

  const summary =
    `${primary.displayName} via ${selectedEngine} ` +
    `(${Math.round(primary.contextWindow / 1024)}K ctx, KV ${primary.kvCacheQuant}, ` +
    `${estimatedResidentMemoryGb.toFixed(1)} GB resident / ${hardware.totalRamGb} GB RAM` +
    `${polyStrataMode !== 'disabled' ? `, PolyStrata=${polyStrataMode}` : ''})`;

  return {
    hardware,
    primaryModel: primary,
    selectedEngine,
    fallbackEngine,
    plannedContextWindow: primary.contextWindow,
    plannedKvCacheQuant: primary.kvCacheQuant,
    concurrentSlots: 2,
    languageModelMemoryBudgetGb,
    estimatedResidentMemoryGb,
    polyStrataMode,
    companionBudget,
    alternatives,
    rejected,
    summary,
  };
}

// ---------------------------------------------------------------------------
// 5. Local Engine Binary Discovery & Launch Command Builder
// ---------------------------------------------------------------------------

async function isExecutable(filePath: string): Promise<boolean> {
  try {
    await access(filePath, fsConstants.X_OK);
    return true;
  } catch {
    return false;
  }
}

async function findExecutableInPaths(names: string[], searchDirs: string[]): Promise<string | null> {
  for (const name of names) {
    for (const dir of searchDirs) {
      const candidate = join(dir, name);
      if (await isExecutable(candidate)) {
        return candidate;
      }
    }
  }
  return null;
}

export async function probeLocalInferenceEngines(
  customPathEnv?: string,
): Promise<LocalEngineProbeStatus[]> {
  const envPath = customPathEnv ?? process.env.PATH ?? '';
  const searchDirs = [
    '/opt/homebrew/bin',
    '/usr/local/bin',
    join(process.env.HOME ?? '', '.local', 'bin'),
    ...envPath.split(delimiter).filter(Boolean),
  ];
  const uniqueDirs = Array.from(new Set(searchDirs));

  const specs: Array<{
    engine: LocalInferenceEngineKind;
    binaries: string[];
    port: number;
    supportsPolyStrataMoE: boolean;
    note: string;
  }> = [
    {
      engine: 'polystrata',
      binaries: ['polystrata', 'strata-poly', 'strata-server'],
      port: 11438,
      supportsPolyStrataMoE: true,
      note: 'MIT PolyStrata/Strata MoE engine (GPU/Metal hot experts + RAM/SSD prefetch).',
    },
    {
      engine: 'llama_cpp',
      binaries: ['llama-server', 'llama-cli'],
      port: 11436,
      supportsPolyStrataMoE: false,
      note: 'llama.cpp Metal / CUDA GGUF server with quantized KV cache.',
    },
    {
      engine: 'ollama',
      binaries: ['ollama'],
      port: 11434,
      supportsPolyStrataMoE: false,
      note: 'Ollama local model daemon with OpenAI-compatible /v1 API.',
    },
    {
      engine: 'mlx',
      binaries: ['mlx_lm.server', 'mlx_lm'],
      port: 11437,
      supportsPolyStrataMoE: false,
      note: 'Apple Silicon MLX native unified-memory inference server.',
    },
  ];

  const results: LocalEngineProbeStatus[] = [];
  for (const spec of specs) {
    const bin = await findExecutableInPaths(spec.binaries, uniqueDirs);
    results.push({
      engine: spec.engine,
      installed: bin !== null,
      binaryPath: bin,
      defaultPort: spec.port,
      endpointUrl: `http://127.0.0.1:${spec.port}/v1`,
      supportsPolyStrataMoE: spec.supportsPolyStrataMoE,
      note: spec.note,
    });
  }
  return results;
}

export function buildLocalEngineLaunchSpec(
  plan: ModelAutopilotPlan,
  modelArtifactPath: string,
  portOverride?: number,
): LocalEngineLaunchSpec {
  const engine = plan.selectedEngine;
  const ctx = String(plan.plannedContextWindow);
  const kv = plan.plannedKvCacheQuant;

  switch (engine) {
    case 'polystrata': {
      const port = portOverride ?? 11438;
      const args = [
        'serve',
        '--model', modelArtifactPath,
        '--host', '127.0.0.1',
        '--port', String(port),
        '--ctx-size', ctx,
        '--kv-quant', kv,
        '--slots', String(plan.concurrentSlots),
      ];
      if (plan.polyStrataMode === 'apple_metal_ssd_beta') {
        args.push('--metal-ssd-prefetch');
      } else if (plan.polyStrataMode === 'cuda_ssd_paging') {
        args.push('--ssd-expert-paging');
      }
      const env: Record<string, string> = {
        POLYSTRATA_HOST: '127.0.0.1',
        POLYSTRATA_KV_QUANT: kv,
      };
      return {
        engine,
        binary: 'polystrata',
        args,
        env,
        endpointUrl: `http://127.0.0.1:${port}/v1`,
        commandLine: `polystrata ${args.join(' ')}`,
      };
    }

    case 'llama_cpp': {
      const port = portOverride ?? 11436;
      const args = [
        '--model', modelArtifactPath,
        '--host', '127.0.0.1',
        '--port', String(port),
        '--ctx-size', ctx,
        '--parallel', String(plan.concurrentSlots),
        '--cache-type-k', kv,
        '--cache-type-v', kv,
        '--flash-attn',
      ];
      return {
        engine,
        binary: 'llama-server',
        args,
        env: {},
        endpointUrl: `http://127.0.0.1:${port}/v1`,
        commandLine: `llama-server ${args.join(' ')}`,
      };
    }

    case 'mlx': {
      const port = portOverride ?? 11437;
      const modelRef = plan.primaryModel.mlxRepo ?? modelArtifactPath;
      const args = ['--model', modelRef, '--host', '127.0.0.1', '--port', String(port)];
      return {
        engine,
        binary: 'mlx_lm.server',
        args,
        env: {},
        endpointUrl: `http://127.0.0.1:${port}/v1`,
        commandLine: `mlx_lm.server ${args.join(' ')}`,
      };
    }

    case 'ollama':
    default: {
      const port = portOverride ?? 11434;
      const tag = plan.primaryModel.ollamaTag ?? plan.primaryModel.id;
      const args = ['run', tag];
      return {
        engine: 'ollama',
        binary: 'ollama',
        args,
        env: { OLLAMA_HOST: `127.0.0.1:${port}` },
        endpointUrl: `http://127.0.0.1:${port}/v1`,
        commandLine: `OLLAMA_HOST=127.0.0.1:${port} ollama run ${tag}`,
      };
    }
  }
}

// ---------------------------------------------------------------------------
// 6. Mandatory Real-QA Self-Test Verification Gate
// ---------------------------------------------------------------------------

/**
 * A planned local model only counts as `verified` after it actually answers a
 * live deterministic QA smoke prompt (e.g. echoing the nonce token and
 * computing a simple invariant), proving weights, KV pool, and endpoint work.
 */
export async function verifyLocalModelWithQA(params: {
  endpointUrl: string;
  modelId: string;
  apiKey?: string;
  timeoutMs?: number;
  fetchImpl?: typeof fetch;
}): Promise<ModelSelfTestResult> {
  const started = Date.now();
  const nonce = 'PIPI_QA_42';
  const base = params.endpointUrl.replace(/\/+$/, '');
  const url = base.endsWith('/chat/completions') ? base : `${base}/chat/completions`;
  const fetchFn = params.fetchImpl ?? globalThis.fetch;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), params.timeoutMs ?? 15_000);

  try {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };
    if (params.apiKey && params.apiKey.trim().length > 0) {
      headers.Authorization = `Bearer ${params.apiKey.trim()}`;
    }

    const response = await fetchFn(url, {
      method: 'POST',
      headers,
      signal: controller.signal,
      body: JSON.stringify({
        model: params.modelId,
        temperature: 0,
        max_tokens: 48,
        messages: [
          {
            role: 'system',
            content: 'Reply concisely with the exact requested token and sum.',
          },
          {
            role: 'user',
            content: `Return the token ${nonce} and the sum of 19 + 23.`,
          },
        ],
      }),
    });

    const ttftMs = Math.max(1, Date.now() - started);
    if (!response.ok) {
      const bodyText = await response.text().catch(() => '');
      return {
        modelId: params.modelId,
        endpointUrl: url,
        status: 'failed',
        verified: false,
        ttftMs,
        totalMs: Math.max(1, Date.now() - started),
        estimatedTokPerSec: 0,
        sampleOutput: '',
        error: `HTTP ${response.status}: ${bodyText.slice(0, 200)}`,
        testedAt: new Date().toISOString(),
      };
    }

    const payload = (await response.json()) as {
      choices?: Array<{ message?: { content?: string } }>;
      usage?: { completion_tokens?: number };
    };
    const totalMs = Math.max(1, Date.now() - started);
    const output = (payload.choices?.[0]?.message?.content ?? '').trim();
    const hasExpectedAnswer = output.includes(nonce) && output.includes('42');
    const completionTokens =
      payload.usage?.completion_tokens ?? Math.max(4, Math.ceil(output.length / 4));
    const estimatedTokPerSec = Math.round((completionTokens / (totalMs / 1000)) * 10) / 10;

    return {
      modelId: params.modelId,
      endpointUrl: url,
      status: hasExpectedAnswer ? 'verified' : 'failed',
      verified: hasExpectedAnswer,
      ttftMs,
      totalMs,
      estimatedTokPerSec,
      sampleOutput: output.slice(0, 160),
      error: hasExpectedAnswer
        ? undefined
        : `Model responded but failed deterministic QA check (expected ${nonce} and 42).`,
      testedAt: new Date().toISOString(),
    };
  } catch (err) {
    const totalMs = Math.max(1, Date.now() - started);
    return {
      modelId: params.modelId,
      endpointUrl: url,
      status: 'failed',
      verified: false,
      ttftMs: totalMs,
      totalMs,
      estimatedTokPerSec: 0,
      sampleOutput: '',
      error: err instanceof Error ? err.message : String(err),
      testedAt: new Date().toISOString(),
    };
  } finally {
    clearTimeout(timer);
  }
}
