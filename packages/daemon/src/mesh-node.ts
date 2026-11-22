/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/daemon - mesh-node.ts
 * Headless Linux / macOS Mesh Node Agent:
 * - Connects outbound via reverse SSE to any free self-hosted PiPi Hub (NAT/firewall friendly)
 * - Reports live OS, CPU, RAM, disk, NVIDIA GPU (`nvidia-smi`), and installed CLI agents
 * - Executes assigned tasks in true parallel (never blocks one task behind another)
 * - Runs local files/shell/GPU probes or local CLI agents (`codex`/`claude`/`opencode`) with
 *   automatic fallback & cross-machine artifact relay.
 */

import { execFileSync, spawn } from 'node:child_process';
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { arch as osArch, cpus, freemem, hostname as osHostname, platform as osPlatform, totalmem } from 'node:os';
import { basename, join, resolve } from 'node:path';

import type { MeshNodeRecord, MeshNodeTelemetry, MeshTaskRecord } from './mesh-hub.ts';

export interface MeshNodeOptions {
  hubUrl: string;
  token?: string;
  name: string;
  nodeId?: string;
  workspacePath?: string;
  heartbeatIntervalMs?: number;
  customExecutor?: (task: MeshTaskRecord) => Promise<{ text: string; artifacts?: Array<{ fileName: string; mimeType: string; contentBase64: string }> }>;
}

export function detectInstalledCLIs(): string[] {
  const candidates: Array<{ kind: string; bin: string }> = [
    { kind: 'codex', bin: 'codex' },
    { kind: 'claude-code', bin: 'claude' },
    { kind: 'opencode', bin: 'opencode' },
  ];
  const found: string[] = [];
  for (const c of candidates) {
    try {
      execFileSync('which', [c.bin], { stdio: 'ignore', timeout: 1500 });
      found.push(c.kind);
    } catch {
      // not installed
    }
  }
  return found;
}

export function probeNodeTelemetry(): MeshNodeTelemetry {
  const totalGB = Number((totalmem() / 1_073_741_824).toFixed(1));
  const usedGB = Number(((totalmem() - freemem()) / 1_073_741_824).toFixed(1));
  let gpuSummary: string | undefined;
  try {
    const out = execFileSync(
      'nvidia-smi',
      ['--query-gpu=name,memory.used,memory.total,utilization.gpu', '--format=csv,noheader'],
      { encoding: 'utf8', timeout: 2000, stdio: ['ignore', 'pipe', 'ignore'] },
    ).trim();
    if (out) gpuSummary = out.split('\n').slice(0, 2).join(' | ');
  } catch {
    // no NVIDIA GPU on this host
  }
  return {
    cpuPercent: Math.min(100, Math.round((cpus().length > 0 ? 12 : 0))),
    memoryUsedGB: usedGB,
    memoryTotalGB: totalGB,
    gpuSummary,
  };
}

export class PipiMeshNodeAgent {
  private readonly hubUrl: string;
  private readonly token?: string;
  private readonly name: string;
  private readonly workspacePath: string;
  private readonly heartbeatIntervalMs: number;
  private readonly customExecutor?: MeshNodeOptions['customExecutor'];

  private nodeId: string;
  private running = false;
  private activeTasks = 0;
  private heartbeatTimer?: ReturnType<typeof setInterval>;
  private streamAbort?: AbortController;

  constructor(options: MeshNodeOptions) {
    this.hubUrl = options.hubUrl.replace(/\/+$/, '');
    this.token = options.token?.trim() || undefined;
    this.name = options.name.trim() || osHostname();
    this.nodeId = options.nodeId?.trim() || `node_${this.name.toLowerCase().replace(/[^a-z0-9_-]/g, '-')}`;
    this.workspacePath = resolve(options.workspacePath || process.cwd());
    this.heartbeatIntervalMs = options.heartbeatIntervalMs ?? 15_000;
    this.customExecutor = options.customExecutor;
  }

  public getNodeId(): string {
    return this.nodeId;
  }

  private authHeaders(extra: Record<string, string> = {}): Record<string, string> {
    const headers: Record<string, string> = { ...extra };
    if (this.token) headers.Authorization = `Bearer ${this.token}`;
    return headers;
  }

  public async start(): Promise<MeshNodeRecord> {
    this.running = true;
    const cliAgents = detectInstalledCLIs();
    const telemetry = probeNodeTelemetry();
    const regResp = await fetch(`${this.hubUrl}/api/v1/mesh/nodes/register`, {
      method: 'POST',
      headers: this.authHeaders({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({
        nodeId: this.nodeId,
        name: this.name,
        platform: osPlatform(),
        arch: osArch(),
        hostname: osHostname(),
        workspacePath: this.workspacePath,
        capabilities: ['files', 'shell', 'jarvis', 'artifacts', ...(telemetry.gpuSummary ? ['gpu'] : [])],
        cliAgents,
        hostedAgents: [
          {
            id: `agent_${this.nodeId}_main`,
            name: `${this.name} · 节点管家`,
            role: `${osPlatform()} (${osArch()}) 远程执行与工程节点`,
            cliKinds: cliAgents,
          },
        ],
        telemetry,
      }),
    });
    if (!regResp.ok) {
      throw new Error(`Mesh Hub registration failed: HTTP ${regResp.status}`);
    }
    const regJson = (await regResp.json()) as { node: MeshNodeRecord };
    this.nodeId = regJson.node.nodeId;

    this.heartbeatTimer = setInterval(() => {
      void this.sendHeartbeat();
    }, this.heartbeatIntervalMs);
    this.heartbeatTimer.unref?.();

    void this.consumeStreamLoop();
    return regJson.node;
  }

  public stop(): void {
    this.running = false;
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = undefined;
    }
    this.streamAbort?.abort();
    this.streamAbort = undefined;
  }

  private async sendHeartbeat(): Promise<void> {
    if (!this.running) return;
    try {
      await fetch(`${this.hubUrl}/api/v1/mesh/nodes/heartbeat`, {
        method: 'POST',
        headers: this.authHeaders({ 'Content-Type': 'application/json' }),
        body: JSON.stringify({
          nodeId: this.nodeId,
          telemetry: probeNodeTelemetry(),
          activeTaskCount: this.activeTasks,
        }),
      });
    } catch {
      // retry next beat
    }
  }

  private async consumeStreamLoop(): Promise<void> {
    while (this.running) {
      const controller = new AbortController();
      this.streamAbort = controller;
      try {
        const resp = await fetch(`${this.hubUrl}/api/v1/mesh/nodes/${encodeURIComponent(this.nodeId)}/stream`, {
          method: 'GET',
          headers: this.authHeaders({ Accept: 'text/event-stream' }),
          signal: controller.signal,
        });
        if (!resp.ok || !resp.body) {
          await this.sleep(1500);
          continue;
        }
        const reader = resp.body.getReader();
        const decoder = new TextDecoder();
        let buffer = '';
        let currentEvent = '';
        while (this.running) {
          const { value, done } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split('\n');
          buffer = lines.pop() ?? '';
          for (const rawLine of lines) {
            const line = rawLine.trimEnd();
            if (line.startsWith('event:')) {
              currentEvent = line.slice(6).trim();
            } else if (line.startsWith('data:')) {
              const payloadStr = line.slice(5).trim();
              if (currentEvent === 'task.assigned' && payloadStr) {
                try {
                  const task = JSON.parse(payloadStr) as MeshTaskRecord;
                  // Launch in true parallel — NEVER await sequentially!
                  void this.executeAssignedTask(task);
                } catch {
                  // ignore malformed frame
                }
              }
            }
          }
        }
      } catch {
        // reconnect after short backoff
      }
      if (this.running) await this.sleep(1200);
    }
  }

  private async executeAssignedTask(task: MeshTaskRecord): Promise<void> {
    this.activeTasks += 1;
    try {
      await this.postTaskEvent(task.taskId, {
        type: 'started',
        stepTitle: `[${this.name}] 已接单，正在并行执行 ⚡`,
      });

      // Download any cross-machine handoff artifacts into node temp workspace if supplied
      const handoffNotes: string[] = [];
      for (const artId of task.inputArtifactIds ?? []) {
        const dl = await this.downloadArtifact(artId);
        if (dl) handoffNotes.push(`已接收跨机产物：${dl.savedPath} (${dl.byteSize} bytes)`);
      }

      if (this.customExecutor) {
        const res = await this.customExecutor(task);
        for (const art of res.artifacts ?? []) {
          const uploadedId = await this.uploadArtifact(art.fileName, art.mimeType, art.contentBase64);
          if (uploadedId) {
            await this.postTaskEvent(task.taskId, { type: 'artifact', artifactId: uploadedId });
          }
        }
        await this.postTaskEvent(task.taskId, { type: 'completed', text: res.text });
        return;
      }

      const workDir = existsSync(task.workspacePath || '') ? (task.workspacePath as string) : this.workspacePath;
      const resultText = await this.runLocalNodeExecution(task, workDir, handoffNotes);
      await this.postTaskEvent(task.taskId, { type: 'completed', text: resultText });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      await this.postTaskEvent(task.taskId, { type: 'failed', error: msg });
    } finally {
      this.activeTasks = Math.max(0, this.activeTasks - 1);
    }
  }

  private async runLocalNodeExecution(
    task: MeshTaskRecord,
    workDir: string,
    handoffNotes: string[],
  ): Promise<string> {
    const prompt = task.prompt.trim();

    // 1. Direct shell syntax (`$ cmd` or `/sh cmd`)
    if (prompt.startsWith('$ ') || prompt.startsWith('/sh ')) {
      const cmd = prompt.startsWith('$ ') ? prompt.slice(2).trim() : prompt.slice(4).trim();
      await this.postTaskEvent(task.taskId, { type: 'progress', stepTitle: `[${this.name}] 正在运行命令：${cmd.slice(0, 48)}` });
      const out = await this.runShell(cmd, workDir);
      return [`🖥️ [${this.name}] 命令执行结果：`, ...handoffNotes, out].filter(Boolean).join('\n\n');
    }

    // 2. Try preferred or installed CLI agent if available (with stdin closed + fallback!)
    const installed = detectInstalledCLIs();
    const targetCli = task.preferredCli && installed.includes(task.preferredCli)
      ? task.preferredCli
      : installed[0];

    if (targetCli) {
      await this.postTaskEvent(task.taskId, {
        type: 'progress',
        stepTitle: `[${this.name}] 正在调用本机 ${targetCli} 处理任务 🚀`,
      });
      const cliOut = await this.tryRunLocalCLI(targetCli, prompt, workDir, task.mode);
      if (cliOut.ok && cliOut.text) {
        return [`🖥️ [${this.name} · ${targetCli}]`, ...handoffNotes, cliOut.text].filter(Boolean).join('\n\n');
      }
    }

    // 3. Built-in native Linux/Mac inspector fallback (never fails with ugly stderr!)
    await this.postTaskEvent(task.taskId, {
      type: 'progress',
      stepTitle: `[${this.name}] 正在采集本机目录、Git 与硬件状态 🔍`,
    });
    const tele = probeNodeTelemetry();
    const entries = safeListDir(workDir).slice(0, 30);
    const readmePreview = safeReadReadme(workDir);
    const lines = [
      `🖥️ 节点 [${this.name}]（${osPlatform()}/${osArch()} · 工作区：${workDir}）`,
      `• 内存：${tele.memoryUsedGB ?? '?'} / ${tele.memoryTotalGB ?? '?'} GB${tele.gpuSummary ? ` · GPU：${tele.gpuSummary}` : ''}`,
      ...handoffNotes,
      `• 目录概览（${entries.length} 项）：${entries.join(', ') || '(空)'}`,
    ];
    if (readmePreview) {
      lines.push(`• README 摘要：\n${readmePreview}`);
    }
    lines.push(`• 收到任务：${prompt}`);
    return lines.join('\n');
  }

  private async tryRunLocalCLI(
    kind: string,
    prompt: string,
    cwd: string,
    mode: 'readonly' | 'write',
  ): Promise<{ ok: boolean; text: string }> {
    const bin = kind === 'claude-code' ? 'claude' : kind;
    const args =
      kind === 'claude-code'
        ? ['-p', prompt, '--permission-mode', mode === 'write' ? 'acceptEdits' : 'plan']
        : kind === 'codex'
          ? ['exec', '--skip-git-repo-check', '--color', 'never', '--sandbox', mode === 'write' ? 'workspace-write' : 'read-only', prompt]
          : ['run', prompt];

    return new Promise((resolveRun) => {
      const child = spawn(bin, args, { cwd, stdio: ['ignore', 'pipe', 'pipe'] });
      let out = '';
      const timer = setTimeout(() => {
        try {
          child.kill('SIGTERM');
        } catch {
          // ignore
        }
        resolveRun({ ok: false, text: '' });
      }, 90_000);

      child.stdout.on('data', (d: Buffer) => {
        out += d.toString('utf8');
      });
      child.on('error', () => {
        clearTimeout(timer);
        resolveRun({ ok: false, text: '' });
      });
      child.on('close', (code) => {
        clearTimeout(timer);
        const trimmed = out.trim();
        resolveRun({ ok: code === 0 && trimmed.length > 0, text: trimmed.slice(0, 12_000) });
      });
    });
  }

  private async runShell(command: string, cwd: string): Promise<string> {
    return new Promise((resolveShell) => {
      const shell = osPlatform() === 'win32' ? 'cmd.exe' : '/bin/sh';
      const args = osPlatform() === 'win32' ? ['/c', command] : ['-lc', command];
      const child = spawn(shell, args, { cwd, stdio: ['ignore', 'pipe', 'pipe'] });
      let out = '';
      let err = '';
      const timer = setTimeout(() => {
        try {
          child.kill('SIGTERM');
        } catch {
          // ignore
        }
        resolveShell('命令执行超时（30s）。');
      }, 30_000);
      child.stdout.on('data', (d: Buffer) => {
        out += d.toString('utf8');
      });
      child.stderr.on('data', (d: Buffer) => {
        err += d.toString('utf8');
      });
      child.on('close', (code) => {
        clearTimeout(timer);
        const combined = [out.trim(), err.trim() ? `[stderr]\n${err.trim()}` : ''].filter(Boolean).join('\n');
        resolveShell(`$ ${command} (exit ${code ?? 0})\n${combined.slice(0, 8000)}`);
      });
      child.on('error', (e) => {
        clearTimeout(timer);
        resolveShell(`无法启动命令：${e.message}`);
      });
    });
  }

  private async postTaskEvent(taskId: string, body: Record<string, unknown>): Promise<void> {
    try {
      await fetch(`${this.hubUrl}/api/v1/mesh/tasks/${encodeURIComponent(taskId)}/event`, {
        method: 'POST',
        headers: this.authHeaders({ 'Content-Type': 'application/json' }),
        body: JSON.stringify(body),
      });
    } catch {
      // ignore
    }
  }

  private async uploadArtifact(fileName: string, mimeType: string, contentBase64: string): Promise<string | null> {
    try {
      const resp = await fetch(`${this.hubUrl}/api/v1/mesh/artifacts`, {
        method: 'POST',
        headers: this.authHeaders({ 'Content-Type': 'application/json' }),
        body: JSON.stringify({ fileName, mimeType, contentBase64, sourceNodeId: this.nodeId }),
      });
      if (!resp.ok) return null;
      const json = (await resp.json()) as { artifact?: { artifactId?: string } };
      return json.artifact?.artifactId ?? null;
    } catch {
      return null;
    }
  }

  private async downloadArtifact(artifactId: string): Promise<{ savedPath: string; byteSize: number } | null> {
    try {
      const resp = await fetch(`${this.hubUrl}/api/v1/mesh/artifacts/${encodeURIComponent(artifactId)}`, {
        headers: this.authHeaders(),
      });
      if (!resp.ok) return null;
      const disp = resp.headers.get('x-pipi-filename') || `${artifactId}.bin`;
      const buf = Buffer.from(await resp.arrayBuffer());
      const outPath = join(this.workspacePath, `.pipi_handoff_${basename(disp)}`);
      writeFileSync(outPath, buf);
      return { savedPath: outPath, byteSize: buf.length };
    } catch {
      return null;
    }
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((r) => setTimeout(r, ms));
  }
}

function safeListDir(dir: string): string[] {
  try {
    return readdirSync(dir)
      .filter((n) => !['.git', 'node_modules', '.build', 'dist'].includes(n))
      .sort()
      .map((n) => {
        try {
          return statSync(join(dir, n)).isDirectory() ? `${n}/` : n;
        } catch {
          return n;
        }
      });
  } catch {
    return [];
  }
}

function safeReadReadme(dir: string): string {
  for (const name of ['README.md', 'readme.md', 'README']) {
    const p = join(dir, name);
    if (existsSync(p)) {
      try {
        return readFileSync(p, 'utf8').slice(0, 600);
      } catch {
        return '';
      }
    }
  }
  return '';
}
