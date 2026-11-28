/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/daemon - cloud-runtime.ts
 * 24/7 Cloud Teammate Brigade Runtime:
 * - Coordinates the always-on AI teammate org chart (`reportsToBotId`, `runtimeMode`),
 *   stacked subscription account pool, and per-teammate isolated cloud browsers.
 * - Exposes Brigade overview snapshots and self-hosted 24/7 cloud deployment templates
 *   (Docker / Compose / Fly.io / systemd).
 *
 * Runtime dependencies: strictly Node built-ins (`node:*`) only.
 */

import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';

import type {
  CloudTeammateDescriptor,
  SubscriptionProviderKind,
  TeammateBrowserProfile,
  TeammateRuntimeMode,
} from '@pipibot/protocol';
import type { PipiSubscriptionAccountPool, SubscriptionPoolSnapshot } from '../../core/src/subscription-pool.ts';
import type { PipiCloudBrowserManager } from './cloud-browser.ts';

export interface UpsertCloudTeammateInput {
  botId: string;
  name: string;
  role: string;
  runtimeMode?: TeammateRuntimeMode;
  reportsToBotId?: string;
  subscriptionProvider?: SubscriptionProviderKind;
  subscriptionAccountId?: string;
  modelId?: string;
  browserEnabled?: boolean;
  browserPlatforms?: string[];
  proxyUrl?: string;
  requireApprovalBeforePost?: boolean;
}

export interface BrigadeOverviewSnapshot {
  cloudModeActive: boolean;
  uptimeSeconds: number;
  teammates: CloudTeammateDescriptor[];
  orgRoots: string[];
  subscriptionPool: SubscriptionPoolSnapshot;
  cloudBrowsers: TeammateBrowserProfile[];
  updatedAt: string;
}

export class PipiCloudBrigadeRuntime {
  private readonly dataDir: string;
  private readonly statePath: string;
  private readonly startedAtMs: number;
  private readonly teammates = new Map<string, CloudTeammateDescriptor>();
  private readonly subscriptionPool: PipiSubscriptionAccountPool;
  private readonly cloudBrowsers: PipiCloudBrowserManager;

  constructor(options: {
    dataDir?: string;
    subscriptionPool: PipiSubscriptionAccountPool;
    cloudBrowsers: PipiCloudBrowserManager;
    persist?: boolean;
    seedDefaults?: boolean;
  }) {
    this.dataDir = options.dataDir ?? join(homedir(), '.pipibot');
    this.statePath = options.persist === false ? '' : join(this.dataDir, 'cloud-brigade.json');
    this.startedAtMs = Date.now();
    this.subscriptionPool = options.subscriptionPool;
    this.cloudBrowsers = options.cloudBrowsers;
    this.load();

    if (options.seedDefaults && this.teammates.size === 0) {
      this.seedDefaultBrigade();
    }
  }

  private seedDefaultBrigade(): void {
    const now = new Date().toISOString();
    const defaults: UpsertCloudTeammateInput[] = [
      {
        botId: 'bot_pipi_general',
        name: 'PiPi · Team Lead',
        role: 'Chief coordinator, triage, and Needs-You escalations',
        runtimeMode: 'hybrid_failover',
        subscriptionProvider: 'claude_subscription',
        modelId: 'claude-sonnet-4-6',
        browserEnabled: false,
      },
      {
        botId: 'bot_pipi_coder',
        name: 'Coder · Engineer',
        role: 'Full-stack coding, PR review, and automated tests',
        runtimeMode: 'cloud_24x7',
        reportsToBotId: 'bot_pipi_general',
        subscriptionProvider: 'claude_subscription',
        modelId: 'claude-opus-4-6',
        browserEnabled: true,
        browserPlatforms: ['github'],
      },
      {
        botId: 'bot_pipi_growth',
        name: 'Growth · Social Operator',
        role: '24/7 LinkedIn, X, and Reddit monitoring, research & draft replies',
        runtimeMode: 'cloud_24x7',
        reportsToBotId: 'bot_pipi_general',
        subscriptionProvider: 'chatgpt_subscription',
        modelId: 'gpt-5.3-codex',
        browserEnabled: true,
        browserPlatforms: ['x', 'linkedin', 'reddit'],
        requireApprovalBeforePost: true,
      },
    ];
    for (const item of defaults) {
      const desc = this.upsertTeammate(item);
      desc.lastHeartbeatAt = now;
    }
  }

  listTeammates(): CloudTeammateDescriptor[] {
    const uptimeSeconds = Math.floor((Date.now() - this.startedAtMs) / 1000);
    return Array.from(this.teammates.values())
      .map((t) => ({
        ...t,
        uptimeSeconds: t.runtimeMode === 'local' ? 0 : uptimeSeconds,
        browserPlatforms: [...t.browserPlatforms],
      }))
      .sort((a, b) => a.botId.localeCompare(b.botId));
  }

  upsertTeammate(input: UpsertCloudTeammateInput): CloudTeammateDescriptor {
    const existing = this.teammates.get(input.botId);
    const now = new Date().toISOString();
    const browserEnabled = input.browserEnabled ?? existing?.browserEnabled ?? false;
    const browserPlatforms = input.browserPlatforms ?? existing?.browserPlatforms ?? ['x', 'linkedin', 'reddit'];

    const descriptor: CloudTeammateDescriptor = {
      botId: input.botId,
      name: input.name.trim() || existing?.name || input.botId,
      role: input.role.trim() || existing?.role || 'AI Teammate',
      runtimeMode: input.runtimeMode ?? existing?.runtimeMode ?? 'local',
      reportsToBotId: input.reportsToBotId !== undefined ? (input.reportsToBotId.trim() || undefined) : existing?.reportsToBotId,
      subscriptionProvider: input.subscriptionProvider ?? existing?.subscriptionProvider,
      subscriptionAccountId: input.subscriptionAccountId ?? existing?.subscriptionAccountId,
      modelId: input.modelId ?? existing?.modelId,
      browserEnabled,
      browserPlatforms: Array.from(new Set(browserPlatforms)),
      status: existing?.status ?? 'idle',
      uptimeSeconds: existing?.uptimeSeconds ?? 0,
      lastHeartbeatAt: now,
    };

    this.teammates.set(input.botId, descriptor);
    if (browserEnabled) {
      this.cloudBrowsers.configureProfile({
        botId: descriptor.botId,
        botName: descriptor.name,
        enabled: true,
        platforms: descriptor.browserPlatforms,
        proxyUrl: input.proxyUrl,
        requireApprovalBeforePost: input.requireApprovalBeforePost ?? true,
      });
    }
    this.save();
    return { ...descriptor, browserPlatforms: [...descriptor.browserPlatforms] };
  }

  removeTeammate(botId: string): boolean {
    const removed = this.teammates.delete(botId);
    if (removed) this.save();
    return removed;
  }

  updateTeammateStatus(botId: string, status: CloudTeammateDescriptor['status']): CloudTeammateDescriptor | null {
    const t = this.teammates.get(botId);
    if (!t) return null;
    t.status = status;
    t.lastHeartbeatAt = new Date().toISOString();
    this.save();
    return { ...t, browserPlatforms: [...t.browserPlatforms] };
  }

  getOverview(): BrigadeOverviewSnapshot {
    const teammates = this.listTeammates();
    const knownIds = new Set(teammates.map((t) => t.botId));
    const orgRoots = teammates
      .filter((t) => !t.reportsToBotId || !knownIds.has(t.reportsToBotId))
      .map((t) => t.botId);

    const cloudModeActive = teammates.some((t) => t.runtimeMode === 'cloud_24x7' || t.runtimeMode === 'hybrid_failover');
    return {
      cloudModeActive,
      uptimeSeconds: Math.floor((Date.now() - this.startedAtMs) / 1000),
      teammates,
      orgRoots,
      subscriptionPool: this.subscriptionPool.getSnapshot(),
      cloudBrowsers: this.cloudBrowsers.listProfiles(),
      updatedAt: new Date().toISOString(),
    };
  }

  private load(): void {
    if (!this.statePath || !existsSync(this.statePath)) return;
    try {
      const raw = readFileSync(this.statePath, 'utf8');
      const parsed = JSON.parse(raw) as { teammates?: CloudTeammateDescriptor[] };
      if (Array.isArray(parsed.teammates)) {
        for (const t of parsed.teammates) {
          this.teammates.set(t.botId, t);
        }
      }
    } catch {
      // ignore
    }
  }

  private save(): void {
    if (!this.statePath) return;
    try {
      mkdirSync(dirname(this.statePath), { recursive: true, mode: 0o700 });
      const tmp = `${this.statePath}.tmp-${process.pid}`;
      writeFileSync(
        tmp,
        `${JSON.stringify({ version: 1, teammates: Array.from(this.teammates.values()), updatedAt: new Date().toISOString() }, null, 2)}\n`,
        { mode: 0o600 },
      );
      renameSync(tmp, this.statePath);
    } catch {
      // ignore
    }
  }
}
