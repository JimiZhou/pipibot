/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/daemon - mesh-hub.ts
 * Free, self-hosted Multi-Machine Mesh Hub:
 * - Node registration, live telemetry & NAT-friendly outbound SSE task subscription
 * - Per-task non-blocking cross-machine dispatch & live SSE progress streaming
 * - Cross-machine artifact relay for zero-workspace-switching multi-host group chats
 * - Linux systemd & macOS launchd service unit generation
 */

import type { ServerResponse } from 'node:http';
import { randomUUID } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

export interface MeshNodeAgentDescriptor {
  id: string;
  name: string;
  role: string;
  cliKinds: string[];
}

export interface MeshNodeTelemetry {
  cpuPercent?: number;
  memoryUsedGB?: number;
  memoryTotalGB?: number;
  diskFreeGB?: number;
  gpuSummary?: string;
}

export interface MeshNodeRecord {
  nodeId: string;
  name: string;
  platform: 'darwin' | 'linux' | 'win32' | string;
  arch: string;
  hostname: string;
  workspacePath: string;
  capabilities: string[];
  cliAgents: string[];
  hostedAgents: MeshNodeAgentDescriptor[];
  telemetry: MeshNodeTelemetry;
  status: 'online' | 'busy' | 'offline';
  activeTaskCount: number;
  registeredAt: string;
  lastHeartbeatAt: string;
  streamConnected: boolean;
}

export interface MeshTaskRequest {
  targetNodeId: string;
  prompt: string;
  botId?: string;
  botName?: string;
  preferredCli?: string;
  workspacePath?: string;
  groupId?: string;
  topicId?: string;
  handoffFromBot?: string;
  handoffHop?: number;
  artifactIds?: string[];
  mode?: 'readonly' | 'write';
}

export interface MeshTaskEvent {
  seq: number;
  taskId: string;
  nodeId: string;
  type: 'queued' | 'started' | 'progress' | 'delta' | 'artifact' | 'completed' | 'failed';
  text?: string;
  stepTitle?: string;
  artifactId?: string;
  error?: string;
  timestamp: string;
}

export interface MeshTaskRecord {
  taskId: string;
  targetNodeId: string;
  botId?: string;
  botName?: string;
  prompt: string;
  preferredCli?: string;
  workspacePath?: string;
  groupId?: string;
  topicId?: string;
  handoffFromBot?: string;
  handoffHop: number;
  inputArtifactIds: string[];
  outputArtifactIds: string[];
  mode: 'readonly' | 'write';
  status: 'queued' | 'running' | 'completed' | 'failed';
  outputText: string;
  error?: string;
  events: MeshTaskEvent[];
  createdAt: string;
  updatedAt: string;
}

export interface MeshArtifactMeta {
  artifactId: string;
  fileName: string;
  mimeType: string;
  byteSize: number;
  sourceNodeId: string;
  createdAt: string;
}

export interface SystemdUnitOptions {
  role: 'hub' | 'node';
  port?: number;
  hubUrl?: string;
  token?: string;
  nodeName?: string;
  workspace?: string;
  nodeBinary?: string;
  cliScriptPath?: string;
  user?: string;
}

export class MeshHubManager {
  private readonly nodes = new Map<string, MeshNodeRecord>();
  private readonly nodeStreams = new Map<string, Set<ServerResponse>>();
  private readonly tasks = new Map<string, MeshTaskRecord>();
  private readonly taskStreams = new Map<string, Set<ServerResponse>>();
  private readonly artifacts = new Map<string, MeshArtifactMeta>();
  private readonly artifactsDir: string;
  private readonly hubToken?: string;
  private readonly livenessTimeoutMs = 45_000;

  constructor(options: { storageDir: string; hubToken?: string }) {
    this.artifactsDir = join(options.storageDir, 'mesh-artifacts');
    mkdirSync(this.artifactsDir, { recursive: true });
    this.hubToken = options.hubToken?.trim() || undefined;
  }

  public verifyToken(headerAuth?: string, queryToken?: string | null): boolean {
    if (!this.hubToken) return true;
    const bearer = headerAuth?.startsWith('Bearer ') ? headerAuth.slice(7).trim() : headerAuth?.trim();
    return bearer === this.hubToken || (queryToken?.trim() ?? '') === this.hubToken;
  }

  public getHubTokenConfigured(): boolean {
    return Boolean(this.hubToken);
  }

  // -------------------------------------------------------------------------
  // Node Registry & Reverse SSE Task Streams
  // -------------------------------------------------------------------------

  public registerNode(input: {
    nodeId?: string;
    name: string;
    platform: string;
    arch: string;
    hostname: string;
    workspacePath?: string;
    capabilities?: string[];
    cliAgents?: string[];
    hostedAgents?: MeshNodeAgentDescriptor[];
    telemetry?: MeshNodeTelemetry;
  }): MeshNodeRecord {
    const now = new Date().toISOString();
    const nodeId = input.nodeId?.trim() || `node_${input.name.toLowerCase().replace(/[^a-z0-9_-]/g, '-')}_${randomUUID().slice(0, 6)}`;
    const existing = this.nodes.get(nodeId);
    const streamConnected = (this.nodeStreams.get(nodeId)?.size ?? 0) > 0;
    const record: MeshNodeRecord = {
      nodeId,
      name: input.name.trim() || input.hostname || nodeId,
      platform: input.platform || 'linux',
      arch: input.arch || 'x64',
      hostname: input.hostname || input.name,
      workspacePath: input.workspacePath || '.',
      capabilities: input.capabilities ?? ['shell', 'files', 'jarvis'],
      cliAgents: input.cliAgents ?? [],
      hostedAgents: input.hostedAgents ?? [],
      telemetry: input.telemetry ?? {},
      status: 'online',
      activeTaskCount: existing?.activeTaskCount ?? 0,
      registeredAt: existing?.registeredAt ?? now,
      lastHeartbeatAt: now,
      streamConnected,
    };
    this.nodes.set(nodeId, record);
    return record;
  }

  public heartbeatNode(input: {
    nodeId: string;
    telemetry?: MeshNodeTelemetry;
    cliAgents?: string[];
    activeTaskCount?: number;
  }): MeshNodeRecord | null {
    const node = this.nodes.get(input.nodeId);
    if (!node) return null;
    node.lastHeartbeatAt = new Date().toISOString();
    if (input.telemetry) node.telemetry = { ...node.telemetry, ...input.telemetry };
    if (input.cliAgents) node.cliAgents = input.cliAgents;
    if (typeof input.activeTaskCount === 'number') node.activeTaskCount = input.activeTaskCount;
    node.streamConnected = (this.nodeStreams.get(node.nodeId)?.size ?? 0) > 0;
    node.status = node.activeTaskCount > 0 ? 'busy' : 'online';
    return node;
  }

  public listNodes(nowMs = Date.now()): MeshNodeRecord[] {
    const out: MeshNodeRecord[] = [];
    for (const node of this.nodes.values()) {
      const lastMs = Date.parse(node.lastHeartbeatAt);
      const streamAlive = (this.nodeStreams.get(node.nodeId)?.size ?? 0) > 0;
      const isFresh = Number.isFinite(lastMs) && nowMs - lastMs <= this.livenessTimeoutMs;
      node.streamConnected = streamAlive;
      if (!streamAlive && !isFresh) {
        node.status = 'offline';
      } else if (node.activeTaskCount > 0) {
        node.status = 'busy';
      } else {
        node.status = 'online';
      }
      out.push({ ...node });
    }
    return out.sort((a, b) => a.name.localeCompare(b.name));
  }

  public findNode(idOrName: string): MeshNodeRecord | undefined {
    const direct = this.nodes.get(idOrName);
    if (direct) return direct;
    const lower = idOrName.trim().toLowerCase();
    for (const node of this.nodes.values()) {
      if (node.name.toLowerCase() === lower || node.hostname.toLowerCase() === lower) {
        return node;
      }
    }
    return undefined;
  }

  public attachNodeStream(nodeId: string, res: ServerResponse): void {
    let set = this.nodeStreams.get(nodeId);
    if (!set) {
      set = new Set();
      this.nodeStreams.set(nodeId, set);
    }
    set.add(res);
    const node = this.nodes.get(nodeId);
    if (node) {
      node.streamConnected = true;
      node.lastHeartbeatAt = new Date().toISOString();
      if (node.status === 'offline') node.status = 'online';
    }

    // Flush any queued tasks for this node immediately
    for (const task of this.tasks.values()) {
      if (task.targetNodeId === nodeId && task.status === 'queued') {
        this.writeSse(res, 'task.assigned', task);
      }
    }
  }

  public detachNodeStream(nodeId: string, res: ServerResponse): void {
    const set = this.nodeStreams.get(nodeId);
    if (!set) return;
    set.delete(res);
    if (set.size === 0) {
      this.nodeStreams.delete(nodeId);
      const node = this.nodes.get(nodeId);
      if (node) node.streamConnected = false;
    }
  }

  // -------------------------------------------------------------------------
  // Cross-Machine Non-Blocking Task Dispatch & Live Streaming
  // -------------------------------------------------------------------------

  public dispatchTask(req: MeshTaskRequest): { ok: true; task: MeshTaskRecord } | { ok: false; error: string } {
    const node = this.findNode(req.targetNodeId);
    if (!node) {
      return { ok: false, error: `Unknown mesh node: ${req.targetNodeId}` };
    }
    const hop = req.handoffHop ?? 0;
    if (hop > 3) {
      return { ok: false, error: 'Cross-machine handoff hop limit (3) exceeded to prevent loops.' };
    }

    const now = new Date().toISOString();
    const taskId = `mtask_${randomUUID().slice(0, 10)}`;
    const queuedEvent: MeshTaskEvent = {
      seq: 1,
      taskId,
      nodeId: node.nodeId,
      type: 'queued',
      text: `已派发至节点 [${node.name}]`,
      timestamp: now,
    };

    const task: MeshTaskRecord = {
      taskId,
      targetNodeId: node.nodeId,
      botId: req.botId,
      botName: req.botName,
      prompt: req.prompt,
      preferredCli: req.preferredCli,
      workspacePath: req.workspacePath ?? node.workspacePath,
      groupId: req.groupId,
      topicId: req.topicId,
      handoffFromBot: req.handoffFromBot,
      handoffHop: hop,
      inputArtifactIds: req.artifactIds ?? [],
      outputArtifactIds: [],
      mode: req.mode ?? 'write',
      status: 'queued',
      outputText: '',
      events: [queuedEvent],
      createdAt: now,
      updatedAt: now,
    };
    this.tasks.set(taskId, task);

    // Push immediately to connected node streams
    const streams = this.nodeStreams.get(node.nodeId);
    if (streams && streams.size > 0) {
      for (const s of streams) {
        this.writeSse(s, 'task.assigned', task);
      }
    }

    return { ok: true, task };
  }

  public ingestTaskEvent(
    taskId: string,
    payload: {
      type: MeshTaskEvent['type'];
      text?: string;
      stepTitle?: string;
      artifactId?: string;
      error?: string;
    },
  ): MeshTaskRecord | null {
    const task = this.tasks.get(taskId);
    if (!task) return null;

    const now = new Date().toISOString();
    const event: MeshTaskEvent = {
      seq: task.events.length + 1,
      taskId,
      nodeId: task.targetNodeId,
      type: payload.type,
      text: payload.text,
      stepTitle: payload.stepTitle,
      artifactId: payload.artifactId,
      error: payload.error,
      timestamp: now,
    };
    task.events.push(event);
    task.updatedAt = now;

    const node = this.nodes.get(task.targetNodeId);
    if (payload.type === 'started') {
      task.status = 'running';
      if (node) {
        node.activeTaskCount += 1;
        node.status = 'busy';
      }
    } else if (payload.type === 'delta' && payload.text) {
      task.outputText += payload.text;
    } else if (payload.type === 'artifact' && payload.artifactId) {
      if (!task.outputArtifactIds.includes(payload.artifactId)) {
        task.outputArtifactIds.push(payload.artifactId);
      }
    } else if (payload.type === 'completed') {
      task.status = 'completed';
      if (payload.text && payload.text.trim()) {
        task.outputText = payload.text;
      }
      if (node) {
        node.activeTaskCount = Math.max(0, node.activeTaskCount - 1);
        node.status = node.activeTaskCount > 0 ? 'busy' : 'online';
      }
    } else if (payload.type === 'failed') {
      task.status = 'failed';
      task.error = payload.error ?? payload.text ?? 'Remote execution failed';
      if (node) {
        node.activeTaskCount = Math.max(0, node.activeTaskCount - 1);
        node.status = node.activeTaskCount > 0 ? 'busy' : 'online';
      }
    }

    const listeners = this.taskStreams.get(taskId);
    if (listeners && listeners.size > 0) {
      for (const res of listeners) {
        this.writeSse(res, 'task.event', event);
        if (payload.type === 'completed' || payload.type === 'failed') {
          this.writeSse(res, 'task.done', task);
          try {
            res.end();
          } catch {
            // ignore
          }
          listeners.delete(res);
        }
      }
    }

    return task;
  }

  public getTask(taskId: string): MeshTaskRecord | undefined {
    return this.tasks.get(taskId);
  }

  public listRecentTasks(limit = 30): MeshTaskRecord[] {
    return Array.from(this.tasks.values())
      .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))
      .slice(0, limit);
  }

  public attachTaskStream(taskId: string, res: ServerResponse): boolean {
    const task = this.tasks.get(taskId);
    if (!task) return false;
    for (const ev of task.events) {
      this.writeSse(res, 'task.event', ev);
    }
    if (task.status === 'completed' || task.status === 'failed') {
      this.writeSse(res, 'task.done', task);
      res.end();
      return true;
    }
    let set = this.taskStreams.get(taskId);
    if (!set) {
      set = new Set();
      this.taskStreams.set(taskId, set);
    }
    set.add(res);
    return true;
  }

  public detachTaskStream(taskId: string, res: ServerResponse): void {
    const set = this.taskStreams.get(taskId);
    if (!set) return;
    set.delete(res);
    if (set.size === 0) this.taskStreams.delete(taskId);
  }

  // -------------------------------------------------------------------------
  // Cross-Machine Artifact Relay
  // -------------------------------------------------------------------------

  public storeArtifact(input: {
    fileName: string;
    mimeType?: string;
    contentBase64: string;
    sourceNodeId?: string;
  }): MeshArtifactMeta {
    const artifactId = `mart_${randomUUID().slice(0, 10)}`;
    const safeName = (input.fileName || 'artifact.bin').replace(/[^a-zA-Z0-9._-]/g, '_');
    const raw = Buffer.from(input.contentBase64, 'base64');
    if (raw.length > 25 * 1024 * 1024) {
      throw new Error('Artifact exceeds 25MB mesh relay limit.');
    }
    const diskPath = join(this.artifactsDir, `${artifactId}_${safeName}`);
    writeFileSync(diskPath, raw);
    const meta: MeshArtifactMeta = {
      artifactId,
      fileName: safeName,
      mimeType: input.mimeType || 'application/octet-stream',
      byteSize: raw.length,
      sourceNodeId: input.sourceNodeId || 'local',
      createdAt: new Date().toISOString(),
    };
    this.artifacts.set(artifactId, meta);
    return meta;
  }

  public readArtifact(artifactId: string): { meta: MeshArtifactMeta; data: Buffer } | null {
    const meta = this.artifacts.get(artifactId);
    if (!meta) return null;
    const diskPath = join(this.artifactsDir, `${artifactId}_${meta.fileName}`);
    if (!existsSync(diskPath)) return null;
    return { meta, data: readFileSync(diskPath) };
  }

  public closeAllStreams(): void {
    for (const set of this.nodeStreams.values()) {
      for (const res of set) {
        try {
          res.end();
        } catch {
          // ignore
        }
      }
    }
    this.nodeStreams.clear();
    for (const set of this.taskStreams.values()) {
      for (const res of set) {
        try {
          res.end();
        } catch {
          // ignore
        }
      }
    }
    this.taskStreams.clear();
  }

  private writeSse(res: ServerResponse, event: string, data: unknown): void {
    try {
      res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    } catch {
      // client closed
    }
  }
}

export function buildLinuxSystemdService(opts: SystemdUnitOptions): string {
  const nodeBin = opts.nodeBinary || '/usr/bin/env node';
  const cliPath = opts.cliScriptPath || '/opt/pipibot/packages/daemon/src/cli.ts';
  const workDir = opts.workspace || '/opt/pipibot';
  const unitName = opts.role === 'hub' ? 'PiPiBot Mesh Hub' : `PiPiBot Mesh Node (${opts.nodeName || 'linux-node'})`;

  const args: string[] = ['--experimental-strip-types', cliPath];
  if (opts.role === 'hub') {
    args.push('hub', 'start', '--host', '0.0.0.0', '--port', String(opts.port ?? 4242));
    if (opts.token) args.push('--token', opts.token);
  } else {
    args.push(
      'node',
      'join',
      '--hub',
      opts.hubUrl || 'http://127.0.0.1:4242',
      '--name',
      opts.nodeName || 'linux-node',
      '--workspace',
      workDir,
    );
    if (opts.token) args.push('--token', opts.token);
  }

  const userLine = opts.user ? `User=${opts.user}\n` : '';
  return [
    '[Unit]',
    `Description=${unitName}`,
    'After=network-online.target',
    'Wants=network-online.target',
    '',
    '[Service]',
    'Type=simple',
    `${userLine}WorkingDirectory=${workDir}`,
    `ExecStart=${nodeBin} ${args.join(' ')}`,
    'Restart=always',
    'RestartSec=3',
    'Environment=NODE_ENV=production',
    '',
    '[Install]',
    'WantedBy=multi-user.target',
    '',
  ].join('\n');
}
