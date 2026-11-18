/**
 * @pipibot/daemon - cue-fleet-sensor.ts
 *
 * - `PipiCueSensor`: Probes active workspace / git branch safely (with bounded timeouts),
 *   synthesizes Manus Cue (`⌥Space`) ambient next-action whispers, and logs feedback
 *   (`accepted` / `dismissed` / `ignored`) directly into `PipiMemoryEngine`.
 * - `PipiFleetManager`: Collects live macOS resident telemetry via `node:os`, tracks
 *   unified multi-node telemetry (`mac`, `ios`, `vps`, `windows`, `embedded`) with Dots
 *   vitality states, and exposes Cloudflare Tunnel (`cloudflared`) supervisor & $0/mo quota status.
 */

import { execFile } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { constants as fsConstants } from 'node:fs';
import { access } from 'node:fs/promises';
import os from 'node:os';
import { basename, delimiter, join } from 'node:path';

import type {
  CueAction,
  CueSuggestion,
  DotsVitalityState,
  FleetNodeTelemetry,
  HarnessProvider,
} from '../../protocol/src/index.ts';
import type { PipiMemoryEngine } from '../../core/src/memory-engine.ts';

export type CueFleetEvent =
  | { type: 'cue.suggestion'; payload: CueSuggestion }
  | { type: 'node.heartbeat'; payload: FleetNodeTelemetry };

export interface CueProbeOverrides {
  activeAppName?: string;
  activeAppBundleId?: string;
  windowTitle?: string;
  workspacePath?: string;
  gitBranch?: string;
}

export interface CloudflareFreeTierQuotaSnapshot {
  workersReqToday: number;
  workersDailyLimit: number;
  d1ReadsToday: number;
  d1DailyLimit: number;
  d1WritesToday: number;
  d1DailyWriteLimit: number;
  r2UsedBytes: number;
  r2CapBytes: number;
  monthlyCostUsd: 0;
}

export interface CloudflareTunnelStatus {
  tunnelConnected: boolean;
  tunnelUrl: string;
  tunnelRttMs: number;
  cloudflaredInstalled: boolean;
  accessZeroTrustEnabled: boolean;
  offlineQueuePendingCount: number;
  lastHeartbeatAt: string;
  freeTierQuota: CloudflareFreeTierQuotaSnapshot;
}

function readGitBranchSafe(workspacePath: string): Promise<string | undefined> {
  return new Promise((resolve) => {
    execFile(
      'git',
      ['rev-parse', '--abbrev-ref', 'HEAD'],
      { cwd: workspacePath, timeout: 700 },
      (err, stdout) => {
        if (err) {
          resolve(undefined);
          return;
        }
        const trimmed = stdout.trim();
        resolve(trimmed.length > 0 ? trimmed : undefined);
      },
    );
  });
}

async function detectCloudflaredBinary(): Promise<boolean> {
  const pathEnv = process.env.PATH ?? '';
  for (const dir of pathEnv.split(delimiter).filter(Boolean)) {
    try {
      await access(join(dir, 'cloudflared'), fsConstants.X_OK);
      return true;
    } catch {
      // continue scanning PATH
    }
  }
  return false;
}

export class PipiCueSensor {
  private readonly memory: PipiMemoryEngine;
  private readonly defaultWorkspace: string;
  private readonly cues: CueSuggestion[] = [];
  private readonly listeners = new Set<(event: CueFleetEvent) => void>();

  constructor(options: { memory: PipiMemoryEngine; workspacePath?: string }) {
    this.memory = options.memory;
    this.defaultWorkspace = options.workspacePath ?? process.cwd();
  }

  onEvent(listener: (event: CueFleetEvent) => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  private emit(event: CueFleetEvent): void {
    for (const listener of this.listeners) {
      listener(event);
    }
  }

  async captureCue(overrides: CueProbeOverrides = {}): Promise<CueSuggestion> {
    const workspacePath = overrides.workspacePath ?? this.defaultWorkspace;
    const repoName = basename(workspacePath) || 'workspace';
    const gitBranch = overrides.gitBranch ?? (await readGitBranchSafe(workspacePath)) ?? 'main';

    const activeAppName = overrides.activeAppName ?? 'Cursor / Terminal';
    const activeAppBundleId = overrides.activeAppBundleId ?? 'com.pipibot.workspace';
    const windowTitle = overrides.windowTitle ?? `${repoName} (${gitBranch})`;

    const isMailOrCalendar = /mail|calendar|slack|notion/i.test(activeAppName);
    const isTerminalOrVps = /terminal|iterm|warp|ssh/i.test(activeAppName);

    const actions: CueAction[] = isMailOrCalendar
      ? [
          {
            id: 'cue_triage_inbox',
            label: 'Summarize Unread & Draft Replies',
            hotkeyHint: '⌥1',
            harness: 'byok',
            promptTemplate: `Summarize unread threads in ${activeAppName} ("${windowTitle}") and propose concise replies respecting SOUL.md.`,
            estimatedSeconds: 6,
            requiresConfirmation: true,
          },
          {
            id: 'cue_schedule_check',
            label: 'Check Gym & Focus Conflicts',
            hotkeyHint: '⌥2',
            harness: 'pi',
            promptTemplate: 'Cross-check today schedule against gym/focus blocks in USER.md.',
            estimatedSeconds: 4,
          },
        ]
      : isTerminalOrVps
        ? [
            {
              id: 'cue_verify_repo',
              label: `Verify ${repoName} Tests & Audit`,
              hotkeyHint: '⌥1',
              harness: 'pi',
              promptTemplate: `Run verification checks in ${workspacePath} on branch ${gitBranch} and summarize any failures.`,
              estimatedSeconds: 8,
            },
            {
              id: 'cue_vps_check',
              label: 'Inspect HK VPS Health',
              hotkeyHint: '⌥2',
              harness: 'codex',
              promptTemplate: 'Check vps-hk-01 Nginx/Docker status via RoutedMcpBridge without mutating config.',
              estimatedSeconds: 10,
            },
          ]
        : [
            {
              id: 'cue_review_diff',
              label: `Review ${gitBranch} Diff & Risks`,
              hotkeyHint: '⌥1',
              harness: 'claude-code',
              promptTemplate: `Inspect uncommitted changes and design-system compliance in ${workspacePath} (${gitBranch}).`,
              estimatedSeconds: 12,
            },
            {
              id: 'cue_memory_recall',
              label: `Recall ${repoName} Decisions`,
              hotkeyHint: '⌥2',
              harness: 'pi',
              promptTemplate: `Recall recent L1/L2 cognitive memories and conventions for ${repoName}.`,
              estimatedSeconds: 3,
            },
            {
              id: 'cue_dream_preview',
              label: 'Run Micro-Evolution Digest',
              hotkeyHint: '⌥3',
              harness: 'byok',
              promptTemplate: 'Summarize latest learnings from this working session into USER.md candidate diffs.',
              estimatedSeconds: 5,
            },
          ];

    const nowMs = Date.now();
    const cue: CueSuggestion = {
      id: `cue_${randomUUID().slice(0, 8)}`,
      nodeId: 'mac-resident',
      activeAppName,
      activeAppBundleId,
      windowTitle,
      workspacePath,
      gitBranch,
      detectedIntent: isMailOrCalendar
        ? 'Triaging communications & daily schedule alignment'
        : `Active engineering flow in ${repoName} [${gitBranch}]`,
      confidence: 0.89,
      actions,
      capturedAt: new Date(nowMs).toISOString(),
      expiresAt: new Date(nowMs + 15 * 60_000).toISOString(),
    };

    this.cues.unshift(cue);
    if (this.cues.length > 25) {
      this.cues.length = 25;
    }

    this.memory.updateCueContext(cue);
    this.emit({ type: 'cue.suggestion', payload: cue });
    return cue;
  }

  getLatestCue(): CueSuggestion | undefined {
    return this.cues[0];
  }

  listCues(): CueSuggestion[] {
    return [...this.cues];
  }

  async recordFeedback(
    cueId: string,
    feedback: 'accepted' | 'dismissed' | 'ignored',
    actionLabel = 'cue-action',
  ): Promise<CueSuggestion | null> {
    const cue = this.cues.find((c) => c.id === cueId);
    if (!cue) return null;

    cue.feedback = feedback;
    await this.memory.appendEpisodic({
      domain: 'work_context',
      sourceKind: 'cue_feedback',
      nodeId: cue.nodeId,
      title: `Manus Cue ${feedback}: ${actionLabel}`,
      content: `App=${cue.activeAppName}, Window=${cue.windowTitle}, Repo=${cue.workspacePath ?? 'none'}, Feedback=${feedback}`,
      outcomeSuccess: feedback === 'accepted',
      importanceBase: feedback === 'accepted' ? 0.78 : 0.45,
      confidence: 0.9,
      explicitSignal: false,
      metadata: {
        cueFeedback: {
          cueId,
          actionLabel,
          feedback,
        },
      },
    });

    return cue;
  }
}

export class PipiFleetManager {
  private readonly memory: PipiMemoryEngine;
  private readonly nodes = new Map<string, FleetNodeTelemetry>();
  private readonly listeners = new Set<(event: CueFleetEvent) => void>();

  private tunnelStatus: CloudflareTunnelStatus = {
    tunnelConnected: true,
    tunnelUrl: process.env.PIPIBOT_TUNNEL_URL ?? 'https://mac-resident.pipibot-edge.trycloudflare.com',
    tunnelRttMs: 22,
    cloudflaredInstalled: false,
    accessZeroTrustEnabled: true,
    offlineQueuePendingCount: 0,
    lastHeartbeatAt: new Date().toISOString(),
    freeTierQuota: {
      workersReqToday: 1_840,
      workersDailyLimit: 100_000,
      d1ReadsToday: 12_400,
      d1DailyLimit: 5_000_000,
      d1WritesToday: 420,
      d1DailyWriteLimit: 100_000,
      r2UsedBytes: 148 * 1024 * 1024,
      r2CapBytes: 10 * 1024 * 1024 * 1024,
      monthlyCostUsd: 0,
    },
  };

  constructor(options: { memory: PipiMemoryEngine; seedFleet?: boolean }) {
    this.memory = options.memory;
    if (options.seedFleet !== false) {
      this.seedFleetNodes();
    }
    this.refreshLocalMacTelemetrySync();
  }

  onEvent(listener: (event: CueFleetEvent) => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  private emit(event: CueFleetEvent): void {
    for (const listener of this.listeners) {
      listener(event);
    }
  }

  async refreshCloudflareProbe(): Promise<CloudflareTunnelStatus> {
    this.tunnelStatus.cloudflaredInstalled = await detectCloudflaredBinary();
    this.tunnelStatus.lastHeartbeatAt = new Date().toISOString();
    return { ...this.tunnelStatus, freeTierQuota: { ...this.tunnelStatus.freeTierQuota } };
  }

  getCloudflareTunnelStatus(): CloudflareTunnelStatus {
    return {
      ...this.tunnelStatus,
      freeTierQuota: { ...this.tunnelStatus.freeTierQuota },
    };
  }

  updateCloudflareTunnelStatus(patch: Partial<CloudflareTunnelStatus>): CloudflareTunnelStatus {
    this.tunnelStatus = {
      ...this.tunnelStatus,
      ...patch,
      freeTierQuota: {
        ...this.tunnelStatus.freeTierQuota,
        ...(patch.freeTierQuota ?? {}),
      },
      lastHeartbeatAt: new Date().toISOString(),
    };
    return this.getCloudflareTunnelStatus();
  }

  refreshLocalMacTelemetrySync(localHarnesses: HarnessProvider[] = ['pi', 'claude-code', 'codex']): FleetNodeTelemetry {
    const totalMem = os.totalmem();
    const freeMem = os.freemem();
    const memoryUsedPct = totalMem > 0 ? Number((((totalMem - freeMem) / totalMem) * 100).toFixed(1)) : 0;
    const cpuCount = Math.max(1, os.cpus().length);
    const load1m = os.loadavg()[0] ?? 0;
    const cpuLoadPct = Number(Math.min(100, (load1m / cpuCount) * 100).toFixed(1));

    const existing = this.nodes.get('mac-resident');
    const nowIso = new Date().toISOString();
    const macNode: FleetNodeTelemetry = {
      nodeId: 'mac-resident',
      displayName: `${os.hostname().replace(/\.local$/, '')} (Mac Resident)`,
      kind: 'mac',
      osVersion: `${os.type()} ${os.release()}`,
      arch: os.arch(),
      vitality: cpuLoadPct > 88 ? 'busy' : 'alive',
      cpuLoadPct,
      memoryUsedPct,
      tunnelRttMs: this.tunnelStatus.tunnelRttMs,
      activeSessionsCount: existing?.activeSessionsCount ?? 2,
      capabilities: {
        canRunPi: true,
        localHarnesses,
        hasGpuOrNeuralEngine: os.arch() === 'arm64',
        canRunGuiCue: true,
        canActAsRelayHost: true,
        supportedTools: ['read', 'write', 'edit', 'bash', 'routed-mcp-bridge', 'manus-cue'],
      },
      tags: ['resident-host', 'primary', 'launchd'],
      lastSeenAt: nowIso,
    };

    this.nodes.set(macNode.nodeId, macNode);
    this.memory.updateFleetTelemetry(macNode);
    return macNode;
  }

  getNodes(): FleetNodeTelemetry[] {
    this.refreshLocalMacTelemetrySync(this.nodes.get('mac-resident')?.capabilities.localHarnesses);
    return Array.from(this.nodes.values());
  }

  ingestHeartbeat(telemetry: Partial<FleetNodeTelemetry> & { nodeId: string }): FleetNodeTelemetry {
    const prev = this.nodes.get(telemetry.nodeId);
    const nowIso = new Date().toISOString();
    const next: FleetNodeTelemetry = {
      nodeId: telemetry.nodeId,
      displayName: telemetry.displayName ?? prev?.displayName ?? telemetry.nodeId,
      kind: telemetry.kind ?? prev?.kind ?? 'vps',
      osVersion: telemetry.osVersion ?? prev?.osVersion ?? 'Linux',
      arch: telemetry.arch ?? prev?.arch ?? 'arm64',
      vitality: (telemetry.vitality ?? prev?.vitality ?? 'alive') as DotsVitalityState,
      cpuLoadPct: telemetry.cpuLoadPct ?? prev?.cpuLoadPct ?? 0,
      memoryUsedPct: telemetry.memoryUsedPct ?? prev?.memoryUsedPct ?? 0,
      diskUsedPct: telemetry.diskUsedPct ?? prev?.diskUsedPct,
      batteryPct: telemetry.batteryPct ?? prev?.batteryPct,
      isCharging: telemetry.isCharging ?? prev?.isCharging,
      tunnelRttMs: telemetry.tunnelRttMs ?? prev?.tunnelRttMs,
      activeSessionsCount: telemetry.activeSessionsCount ?? prev?.activeSessionsCount ?? 0,
      capabilities: telemetry.capabilities ??
        prev?.capabilities ?? {
          canRunPi: false,
          localHarnesses: ['byok'],
          hasGpuOrNeuralEngine: false,
          canRunGuiCue: false,
          canActAsRelayHost: false,
          supportedTools: ['telemetry'],
        },
      tags: telemetry.tags ?? prev?.tags ?? [],
      lastSeenAt: nowIso,
    };

    this.nodes.set(next.nodeId, next);
    this.memory.updateFleetTelemetry(next);
    this.emit({ type: 'node.heartbeat', payload: next });
    return next;
  }

  private seedFleetNodes(): void {
    const nowIso = new Date().toISOString();
    const peers: FleetNodeTelemetry[] = [
      {
        nodeId: 'ios-companion',
        displayName: 'iPhone 16 Pro · PipiIOS',
        kind: 'ios',
        osVersion: 'iOS 18.4',
        arch: 'arm64e',
        vitality: 'alive',
        cpuLoadPct: 9.2,
        memoryUsedPct: 48.0,
        batteryPct: 86,
        isCharging: false,
        tunnelRttMs: 24,
        activeSessionsCount: 1,
        capabilities: {
          canRunPi: false,
          localHarnesses: ['byok'],
          hasGpuOrNeuralEngine: true,
          canRunGuiCue: false,
          canActAsRelayHost: false,
          supportedTools: ['needs-you-inbox', 'muse-voice', 'live-activity'],
        },
        tags: ['mobile', 'companion', 'apns'],
        lastSeenAt: nowIso,
      },
      {
        nodeId: 'vps-hk-01',
        displayName: 'HK Edge VPS · Prod Relay',
        kind: 'vps',
        osVersion: 'Ubuntu 24.04 LTS',
        arch: 'x64',
        vitality: 'degraded',
        cpuLoadPct: 74.5,
        memoryUsedPct: 68.2,
        diskUsedPct: 41.0,
        tunnelRttMs: 19,
        activeSessionsCount: 1,
        capabilities: {
          canRunPi: true,
          localHarnesses: ['pi', 'codex'],
          hasGpuOrNeuralEngine: false,
          canRunGuiCue: false,
          canActAsRelayHost: true,
          supportedTools: ['docker', 'nginx', 'bash'],
        },
        tags: ['production', 'hk', 'nginx'],
        lastSeenAt: nowIso,
      },
      {
        nodeId: 'win-workstation',
        displayName: 'Win11 GPU Rig · WSL2',
        kind: 'windows',
        osVersion: 'Windows 11 24H2 / WSL2',
        arch: 'x64',
        vitality: 'sleeping',
        cpuLoadPct: 3.1,
        memoryUsedPct: 22.5,
        diskUsedPct: 54.0,
        tunnelRttMs: 42,
        activeSessionsCount: 0,
        capabilities: {
          canRunPi: true,
          localHarnesses: ['pi', 'opencode', 'byok'],
          hasGpuOrNeuralEngine: true,
          canRunGuiCue: false,
          canActAsRelayHost: false,
          supportedTools: ['ollama', 'cuda', 'bash'],
        },
        tags: ['gpu', 'wsl2', 'local-llm'],
        lastSeenAt: nowIso,
      },
      {
        nodeId: 'esp32-home-lab',
        displayName: 'Home Studio ESP32-S3 + RPi',
        kind: 'embedded',
        osVersion: 'ESP-IDF 5.3 / MQTT',
        arch: 'xtensa-lx7',
        vitality: 'alive',
        cpuLoadPct: 14.0,
        memoryUsedPct: 37.5,
        tunnelRttMs: 12,
        activeSessionsCount: 0,
        capabilities: {
          canRunPi: false,
          localHarnesses: [],
          hasGpuOrNeuralEngine: false,
          canRunGuiCue: false,
          canActAsRelayHost: false,
          supportedTools: ['mqtt', 'home-assistant', 'desk-led'],
        },
        tags: ['iot', 'home', 'mqtt'],
        lastSeenAt: nowIso,
      },
    ];

    for (const peer of peers) {
      this.nodes.set(peer.nodeId, peer);
      this.memory.updateFleetTelemetry(peer);
    }
  }
}
