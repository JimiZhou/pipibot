/**
 * @pipibot/core - alter-ego.ts
 *
 * PiPiBot — Clean-room MIT implementation.
 * Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
 * Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.
 *
 * Wave 3 (#05): Meta / AlterEgo In-Chat Autonomous Background Delegation.
 * - Autonomous delegation detection + structured `<pipibot_delegate>` directive parsing
 * - Isolated writable `sessions/<sessionId>/playground/<taskId>/` per delegated task
 * - Same-session read-only artifact sharing across sibling tasks; strict cross-session denial
 * - Mid-flight steer instructions, live step timeline, per-task cancel & resume
 * - Runs through `PipiModelScheduler` at `delegated_task` priority so foreground chat stays snappy
 */

import { randomBytes, randomUUID } from 'node:crypto';
import { mkdir, readdir, readFile, rename, stat, writeFile } from 'node:fs/promises';
import { dirname, isAbsolute, join, relative, resolve } from 'node:path';

import type { DelegationTaskStatus } from '@pipibot/protocol';
import type { PipiModelScheduler } from './model-scheduler.ts';

// ---------------------------------------------------------------------------
// 1. Public Contracts
// ---------------------------------------------------------------------------

export interface DelegationStep {
  id: string;
  title: string;
  status: 'running' | 'succeeded' | 'failed';
  detail?: string;
  timestamp: string;
}

export interface DelegationDirective {
  title: string;
  goal: string;
  expectedArtifacts?: string[];
  reason?: string;
}

export interface AlterEgoTask {
  id: string;
  sessionId: string;
  botId: string;
  title: string;
  goal: string;
  status: DelegationTaskStatus;
  playgroundDir: string;
  steps: DelegationStep[];
  steerInstructions: string[];
  artifacts: string[];
  resultSummary?: string;
  errorMessage?: string;
  createdAt: string;
  updatedAt: string;
}

export interface AlterEgoRunnerContext {
  task: AlterEgoTask;
  signal: AbortSignal;
  consumeSteerInstructions: () => string[];
  reportStep: (title: string, status: DelegationStep['status'], detail?: string) => void;
  writeArtifact: (relativePath: string, content: string) => Promise<string>;
  readSessionArtifact: (sourceTaskId: string, relativePath: string) => Promise<string>;
  listSessionArtifacts: () => Promise<Array<{ taskId: string; path: string }>>;
}

export type AlterEgoTaskRunner = (ctx: AlterEgoRunnerContext) => Promise<{
  summary: string;
}>;

// ---------------------------------------------------------------------------
// 2. Structured Autonomous Delegation Detection
// ---------------------------------------------------------------------------

const DELEGATE_TAG_RE = /<pipibot_delegate>([\s\S]*?)<\/pipibot_delegate>/i;

const AUTONOMOUS_LONG_TASK_SIGNALS = [
  /\b(?:deep\s+research|comprehensive\s+report|full\s+audit|compare\s+all|benchmark\s+across|background\s+task|parallel\s+draft)\b/i,
  /(?:深度调研|全面审计|批量重构|后台并行|系统对比报告|完整竞品分析|整理全部文件)/u,
];

/**
 * Extracts a structured `<pipibot_delegate>{...}</pipibot_delegate>` block emitted by Meta.
 */
export function extractDelegationDirective(text: string): DelegationDirective | null {
  const match = text.match(DELEGATE_TAG_RE);
  if (!match?.[1]) return null;
  try {
    const parsed = JSON.parse(match[1].trim()) as Partial<DelegationDirective>;
    if (!parsed || typeof parsed.title !== 'string' || typeof parsed.goal !== 'string') {
      return null;
    }
    const title = parsed.title.trim();
    const goal = parsed.goal.trim();
    if (!title || !goal) return null;
    return {
      title,
      goal,
      expectedArtifacts: Array.isArray(parsed.expectedArtifacts)
        ? parsed.expectedArtifacts.filter((x): x is string => typeof x === 'string')
        : undefined,
      reason: typeof parsed.reason === 'string' ? parsed.reason : undefined,
    };
  } catch {
    return null;
  }
}

/**
 * Evaluates whether Meta should autonomously offload a heavy/multi-step request
 * to an AlterEgo background worker while keeping foreground chat responsive.
 */
export function shouldAutoDelegatePrompt(prompt: string): { delegate: boolean; reason?: string } {
  const trimmed = prompt.trim();
  if (trimmed.length < 12) return { delegate: false };
  for (const re of AUTONOMOUS_LONG_TASK_SIGNALS) {
    if (re.test(trimmed)) {
      return {
        delegate: true,
        reason: 'Detected multi-step background workload suitable for autonomous AlterEgo delegation.',
      };
    }
  }
  return { delegate: false };
}

// ---------------------------------------------------------------------------
// 3. Path Safety Helpers
// ---------------------------------------------------------------------------

function sanitizeSegment(id: string): string {
  const clean = id.trim().replace(/[^a-zA-Z0-9_-]/g, '_');
  if (!clean || clean === '.' || clean === '..') {
    throw new Error(`Invalid identifier segment: "${id}"`);
  }
  return clean;
}

function resolveConfinedPath(baseDir: string, relativePath: string): string {
  const trimmed = relativePath.trim();
  if (!trimmed || isAbsolute(trimmed)) {
    throw new Error(`Artifact path must be relative: "${relativePath}"`);
  }
  const absBase = resolve(baseDir);
  const absTarget = resolve(absBase, trimmed);
  const rel = relative(absBase, absTarget);
  if (!rel || rel.startsWith('..') || isAbsolute(rel)) {
    throw new Error(`Path traversal rejected outside playground: "${relativePath}"`);
  }
  return absTarget;
}

async function atomicWrite(filePath: string, content: string): Promise<void> {
  await mkdir(dirname(filePath), { recursive: true });
  const tmpPath = `${filePath}.tmp.${process.pid}.${randomBytes(6).toString('hex')}`;
  await writeFile(tmpPath, content, 'utf8');
  await rename(tmpPath, filePath);
}

async function listFilesRecursively(rootDir: string, prefix = ''): Promise<string[]> {
  let entries;
  try {
    entries = await readdir(rootDir, { withFileTypes: true });
  } catch {
    return [];
  }
  const out: string[] = [];
  for (const entry of entries) {
    const relPath = prefix ? `${prefix}/${entry.name}` : entry.name;
    const full = join(rootDir, entry.name);
    if (entry.isDirectory()) {
      out.push(...(await listFilesRecursively(full, relPath)));
    } else if (entry.isFile()) {
      out.push(relPath);
    }
  }
  return out.sort();
}

// ---------------------------------------------------------------------------
// 4. PipiAlterEgoCoordinator
// ---------------------------------------------------------------------------

export interface AlterEgoCoordinatorOptions {
  rootDir: string;
  scheduler?: PipiModelScheduler;
  defaultRunner?: AlterEgoTaskRunner;
}

export class PipiAlterEgoCoordinator {
  readonly rootDir: string;
  private readonly scheduler?: PipiModelScheduler;
  private readonly defaultRunner: AlterEgoTaskRunner;

  private readonly tasks = new Map<string, AlterEgoTask>();
  private readonly pendingSteerQueues = new Map<string, string[]>();
  private readonly activeControllers = new Map<string, AbortController>();
  private readonly activePromises = new Map<string, Promise<AlterEgoTask>>();

  constructor(options: AlterEgoCoordinatorOptions) {
    this.rootDir = options.rootDir;
    this.scheduler = options.scheduler;
    this.defaultRunner =
      options.defaultRunner ??
      (async (ctx) => {
        ctx.reportStep('Analyzing delegated task', 'running');
        const steers = ctx.consumeSteerInstructions();
        const body = [
          `# ${ctx.task.title}`,
          '',
          `Goal: ${ctx.task.goal}`,
          steers.length > 0 ? `\n## Mid-flight Steer Notes\n${steers.map((s) => `- ${s}`).join('\n')}` : '',
        ]
          .filter(Boolean)
          .join('\n');
        await ctx.writeArtifact('result.md', body);
        ctx.reportStep('Saved output to playground/result.md', 'succeeded');
        return { summary: `Completed "${ctx.task.title}" with artifact result.md.` };
      });
  }

  sessionPlaygroundRoot(sessionId: string): string {
    return join(this.rootDir, 'sessions', sanitizeSegment(sessionId), 'playground');
  }

  taskPlaygroundDir(sessionId: string, taskId: string): string {
    return join(this.sessionPlaygroundRoot(sessionId), sanitizeSegment(taskId));
  }

  getTask(taskId: string): AlterEgoTask | undefined {
    return this.tasks.get(taskId);
  }

  listTasks(sessionId?: string): AlterEgoTask[] {
    const all = Array.from(this.tasks.values());
    const filtered = sessionId ? all.filter((t) => t.sessionId === sessionId) : all;
    return filtered.sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }

  async waitForTask(taskId: string): Promise<AlterEgoTask | undefined> {
    const p = this.activePromises.get(taskId);
    if (p) {
      await p;
    }
    return this.tasks.get(taskId);
  }

  // ---- Spawn, Steer, Cancel, Resume ----

  async spawnTask(input: {
    sessionId: string;
    botId: string;
    title: string;
    goal: string;
    endpointKey?: string;
    runner?: AlterEgoTaskRunner;
  }): Promise<AlterEgoTask> {
    const id = `ae_${Date.now().toString(36)}_${randomUUID().slice(0, 6)}`;
    const nowIso = new Date().toISOString();
    const playgroundDir = this.taskPlaygroundDir(input.sessionId, id);
    await mkdir(playgroundDir, { recursive: true });

    const task: AlterEgoTask = {
      id,
      sessionId: input.sessionId,
      botId: input.botId,
      title: input.title.trim(),
      goal: input.goal.trim(),
      status: 'queued',
      playgroundDir,
      steps: [],
      steerInstructions: [],
      artifacts: [],
      createdAt: nowIso,
      updatedAt: nowIso,
    };

    this.tasks.set(id, task);
    this.pendingSteerQueues.set(id, []);
    this.launchExecution(task, input.endpointKey ?? 'alter-ego', input.runner ?? this.defaultRunner);
    return task;
  }

  steerTask(taskId: string, instruction: string): boolean {
    const task = this.tasks.get(taskId);
    const trimmed = instruction.trim();
    if (!task || !trimmed) return false;
    task.steerInstructions.push(trimmed);
    task.updatedAt = new Date().toISOString();
    const queue = this.pendingSteerQueues.get(taskId) ?? [];
    queue.push(trimmed);
    this.pendingSteerQueues.set(taskId, queue);
    return true;
  }

  cancelTask(taskId: string): boolean {
    const task = this.tasks.get(taskId);
    if (!task) return false;
    const ctrl = this.activeControllers.get(taskId);
    if (ctrl) {
      ctrl.abort(new Error('AlterEgo task cancelled by user'));
    }
    if (task.status === 'queued' || task.status === 'running' || task.status === 'paused') {
      task.status = 'cancelled';
      task.updatedAt = new Date().toISOString();
      return true;
    }
    return false;
  }

  async resumeTask(
    taskId: string,
    options: { additionalInstruction?: string; endpointKey?: string; runner?: AlterEgoTaskRunner } = {},
  ): Promise<AlterEgoTask | null> {
    const task = this.tasks.get(taskId);
    if (!task) return null;
    if (task.status === 'running' || task.status === 'queued') {
      if (options.additionalInstruction) {
        this.steerTask(taskId, options.additionalInstruction);
      }
      return task;
    }
    if (options.additionalInstruction) {
      this.steerTask(taskId, options.additionalInstruction);
    }
    task.status = 'queued';
    task.errorMessage = undefined;
    task.updatedAt = new Date().toISOString();
    this.launchExecution(task, options.endpointKey ?? 'alter-ego', options.runner ?? this.defaultRunner);
    return task;
  }

  // ---- Isolated Write & Same-Session Read-Only Sharing ----

  async writeArtifact(taskId: string, relativePath: string, content: string): Promise<string> {
    const task = this.tasks.get(taskId);
    if (!task) {
      throw new Error(`Unknown AlterEgo task: ${taskId}`);
    }
    const target = resolveConfinedPath(task.playgroundDir, relativePath);
    await atomicWrite(target, content);
    const normalized = relative(task.playgroundDir, target).replace(/\\/g, '/');
    if (!task.artifacts.includes(normalized)) {
      task.artifacts.push(normalized);
      task.artifacts.sort();
    }
    task.updatedAt = new Date().toISOString();
    return target;
  }

  async readSessionArtifact(readerTaskId: string, sourceTaskId: string, relativePath: string): Promise<string> {
    const reader = this.tasks.get(readerTaskId);
    const source = this.tasks.get(sourceTaskId);
    if (!reader || !source) {
      throw new Error('Unknown AlterEgo reader or source task');
    }
    if (reader.sessionId !== source.sessionId) {
      throw new Error('cross_session_denied: AlterEgo tasks may only read playgrounds within their own session');
    }
    const target = resolveConfinedPath(source.playgroundDir, relativePath);
    const info = await stat(target);
    if (!info.isFile()) {
      throw new Error(`Not a readable artifact file: ${relativePath}`);
    }
    return readFile(target, 'utf8');
  }

  async listSessionArtifacts(sessionId: string): Promise<Array<{ taskId: string; path: string }>> {
    const results: Array<{ taskId: string; path: string }> = [];
    for (const task of this.tasks.values()) {
      if (task.sessionId !== sessionId) continue;
      const files = await listFilesRecursively(task.playgroundDir);
      for (const rel of files) {
        results.push({ taskId: task.id, path: rel });
      }
    }
    return results;
  }

  // ---- Internal Scheduled Runner ----

  private launchExecution(task: AlterEgoTask, endpointKey: string, runner: AlterEgoTaskRunner): void {
    const controller = new AbortController();
    this.activeControllers.set(task.id, controller);

    const runCore = async (): Promise<AlterEgoTask> => {
      try {
        const executeWithContext = async (): Promise<void> => {
          if (controller.signal.aborted) {
            throw new Error('AlterEgo task cancelled');
          }
          task.status = 'running';
          task.updatedAt = new Date().toISOString();

          const ctx: AlterEgoRunnerContext = {
            task,
            signal: controller.signal,
            consumeSteerInstructions: () => {
              const queued = this.pendingSteerQueues.get(task.id) ?? [];
              this.pendingSteerQueues.set(task.id, []);
              return queued;
            },
            reportStep: (title, status, detail) => {
              task.steps.push({
                id: `stp_${randomUUID().slice(0, 6)}`,
                title,
                status,
                detail,
                timestamp: new Date().toISOString(),
              });
              task.updatedAt = new Date().toISOString();
            },
            writeArtifact: (relPath, content) => this.writeArtifact(task.id, relPath, content),
            readSessionArtifact: (srcTaskId, relPath) => this.readSessionArtifact(task.id, srcTaskId, relPath),
            listSessionArtifacts: () => this.listSessionArtifacts(task.sessionId),
          };

          const output = await runner(ctx);
          if (controller.signal.aborted) {
            task.status = 'cancelled';
          } else {
            task.status = 'completed';
            task.resultSummary = output.summary;
          }
          task.updatedAt = new Date().toISOString();
        };

        if (this.scheduler) {
          const lease = await this.scheduler.acquire({
            endpointKey,
            priority: 'delegated_task',
            canYield: true,
          });
          try {
            await executeWithContext();
          } finally {
            lease.release();
          }
        } else {
          await executeWithContext();
        }
      } catch (err) {
        if (controller.signal.aborted || task.status === 'cancelled') {
          task.status = 'cancelled';
        } else {
          task.status = 'failed';
          task.errorMessage = err instanceof Error ? err.message : String(err);
        }
        task.updatedAt = new Date().toISOString();
      } finally {
        this.activeControllers.delete(task.id);
        this.activePromises.delete(task.id);
      }
      return task;
    };

    const promise = runCore();
    this.activePromises.set(task.id, promise);
  }
}
