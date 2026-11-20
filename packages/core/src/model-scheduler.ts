/**
 * @pipibot/core - model-scheduler.ts
 *
 * PiPiBot — Clean-room MIT implementation.
 * Architectural inspiration: simplexai-labs/linger (Model Scheduling — 7-tier priority
 * queues, interactive reserved slot, AIMD adaptive concurrency, preemptive yielding for
 * resumable sessions, and unified structured-output retry/correction;
 * https://github.com/simplexai-labs/linger — Linger Open Source License; zero source code,
 * prompts, or assets copied). See root NOTICE and LICENSE.
 *
 * Runtime dependencies: strictly Node built-ins (`node:*`) only.
 */

import { randomUUID } from 'node:crypto';
import type { SchedulerPriority } from '@pipibot/protocol';

export const SCHEDULER_PRIORITY_RANK: Record<SchedulerPriority, number> = {
  approval_review: 0,
  voice_interactive: 1,
  chat_interactive: 2,
  delegated_task: 3,
  proactive_routine: 4,
  compaction: 5,
  background_memory: 6,
};

export function isInteractivePriority(priority: SchedulerPriority): boolean {
  return SCHEDULER_PRIORITY_RANK[priority] <= SCHEDULER_PRIORITY_RANK.chat_interactive;
}

export function isPreemptiblePriority(priority: SchedulerPriority): boolean {
  return (
    priority === 'background_memory' ||
    priority === 'proactive_routine' ||
    priority === 'delegated_task'
  );
}

export class SchedulerYieldError extends Error {
  readonly runId: string;
  readonly reason: string;

  constructor(runId: string, reason = 'Yielded to higher-priority interactive request') {
    super(reason);
    this.name = 'SchedulerYieldError';
    this.runId = runId;
    this.reason = reason;
  }
}

export interface EndpointPoolConfig {
  initialLimit: number;
  maxLimit: number;
  minLimit?: number;
  /** Default 300_000ms (5m), doubling up to 1_800_000ms (30m) on repeated slowdowns. */
  baseRetryBackoffMs?: number;
  /** Default 60_000ms (1m) holdoff after 429/overload/timeout halving. */
  rateLimitHoldoffMs?: number;
  /** Latency multiple over baseline per 1k prompt tokens treated as congestion. */
  slowdownMultiplier?: number;
}

export interface EndpointPoolSnapshot {
  endpointKey: string;
  hardLimit: number;
  softLimit: number;
  maxLimit: number;
  activeCount: number;
  queuedCount: number;
  baselineMsPer1kTokens: number | null;
  totalYields: number;
  totalRateLimitBackoffs: number;
}

export interface ScheduleAcquireOptions {
  endpointKey: string;
  priority: SchedulerPriority;
  runId?: string;
  /** If true, run can be preempted cleanly once `canYield()` returns true. */
  canYield?: () => boolean;
  /** Invoked when a higher-priority interactive run requests this active run to yield. */
  onYieldRequested?: () => void;
  signal?: AbortSignal;
}

export interface ScheduledLease {
  readonly leaseId: string;
  readonly runId: string;
  readonly endpointKey: string;
  readonly priority: SchedulerPriority;
  readonly startedAtMs: number;
  wasYielded(): boolean;
  reportMetrics(metrics: LeaseCompletionMetrics): void;
  release(): void;
}

export interface LeaseCompletionMetrics {
  durationMs: number;
  promptTokens?: number;
  rateLimitedOrOverloaded?: boolean;
  timedOut?: boolean;
}

interface ActiveSlotEntry {
  leaseId: string;
  runId: string;
  priority: SchedulerPriority;
  startedAtMs: number;
  canYield: () => boolean;
  onYieldRequested?: () => void;
  yieldRequested: boolean;
  released: boolean;
}

interface QueuedWaiter {
  id: string;
  runId: string;
  priority: SchedulerPriority;
  enqueuedAtMs: number;
  canYield: () => boolean;
  onYieldRequested?: () => void;
  resolve: (lease: ScheduledLease) => void;
  reject: (err: Error) => void;
  cleanupAbort?: () => void;
}

interface EndpointPoolState {
  config: Required<EndpointPoolConfig>;
  hardLimit: number;
  active: Map<string, ActiveSlotEntry>;
  waiters: QueuedWaiter[];
  baselineMsPer1kTokens: number | null;
  holdoffUntilMs: number;
  /** Maps a previously backed-off concurrency level to next retry timestamp + backoff duration. */
  levelBackoff: Map<number, { untilMs: number; durationMs: number }>;
  totalYields: number;
  totalRateLimitBackoffs: number;
}

export interface ModelSchedulerOptions {
  nowMs?: () => number;
  defaultConfig?: EndpointPoolConfig;
}

export class PipiModelScheduler {
  private readonly pools = new Map<string, EndpointPoolState>();
  private readonly customConfigs = new Map<string, EndpointPoolConfig>();
  private readonly nowMs: () => number;
  private readonly defaultConfig: EndpointPoolConfig;

  constructor(options: ModelSchedulerOptions = {}) {
    this.nowMs = options.nowMs ?? (() => Date.now());
    this.defaultConfig = options.defaultConfig ?? {
      initialLimit: 2,
      maxLimit: 8,
      minLimit: 1,
      baseRetryBackoffMs: 5 * 60_000,
      rateLimitHoldoffMs: 60_000,
      slowdownMultiplier: 1.85,
    };
  }

  configureEndpoint(endpointKey: string, config: EndpointPoolConfig): void {
    this.customConfigs.set(endpointKey, config);
    const existing = this.pools.get(endpointKey);
    if (existing) {
      const normalized = this.normalizeConfig(config);
      existing.config = normalized;
      existing.hardLimit = Math.max(normalized.minLimit, Math.min(normalized.maxLimit, normalized.initialLimit));
      this.drain(endpointKey);
    }
  }

  resetEndpointLearning(endpointKey: string): void {
    const pool = this.pools.get(endpointKey);
    if (!pool) return;
    pool.hardLimit = pool.config.initialLimit;
    pool.baselineMsPer1kTokens = null;
    pool.holdoffUntilMs = 0;
    pool.levelBackoff.clear();
  }

  getSnapshot(endpointKey: string): EndpointPoolSnapshot {
    const pool = this.ensurePool(endpointKey);
    return {
      endpointKey,
      hardLimit: pool.hardLimit,
      softLimit: this.softLimitFor(pool),
      maxLimit: pool.config.maxLimit,
      activeCount: pool.active.size,
      queuedCount: pool.waiters.length,
      baselineMsPer1kTokens: pool.baselineMsPer1kTokens,
      totalYields: pool.totalYields,
      totalRateLimitBackoffs: pool.totalRateLimitBackoffs,
    };
  }

  acquire(options: ScheduleAcquireOptions): Promise<ScheduledLease> {
    if (options.signal?.aborted) {
      return Promise.reject(new Error('Aborted before acquiring scheduler slot'));
    }

    const pool = this.ensurePool(options.endpointKey);
    const runId = options.runId ?? `run_${randomUUID().slice(0, 8)}`;
    const canYield = options.canYield ?? (() => isPreemptiblePriority(options.priority));

    if (this.canAdmit(pool, options.priority, false)) {
      return Promise.resolve(this.createLease(options.endpointKey, pool, runId, options.priority, canYield, options.onYieldRequested));
    }

    // Attempt preemption if an interactive/higher-priority request is waiting behind lower-priority work
    if (isInteractivePriority(options.priority)) {
      this.tryRequestYield(pool, options.priority);
    }

    return new Promise<ScheduledLease>((resolve, reject) => {
      const waiterId = `wait_${randomUUID().slice(0, 8)}`;
      const waiter: QueuedWaiter = {
        id: waiterId,
        runId,
        priority: options.priority,
        enqueuedAtMs: this.nowMs(),
        canYield,
        onYieldRequested: options.onYieldRequested,
        resolve,
        reject,
      };

      if (options.signal) {
        const onAbort = () => {
          const idx = pool.waiters.findIndex((w) => w.id === waiterId);
          if (idx >= 0) {
            pool.waiters.splice(idx, 1);
            reject(new Error('Aborted while queued in model scheduler'));
          }
        };
        options.signal.addEventListener('abort', onAbort, { once: true });
        waiter.cleanupAbort = () => options.signal?.removeEventListener('abort', onAbort);
      }

      pool.waiters.push(waiter);
      this.sortWaiters(pool);
    });
  }

  /**
   * Executes a work unit under scheduler admission with automatic re-queuing if preempted.
   * For resumable CLI sessions, the `work` callback can persist its `cliSessionId` and
   * automatically resume on the next turn without counting the yield as an error.
   */
  async runWithPreemption<T>(
    options: Omit<ScheduleAcquireOptions, 'onYieldRequested'>,
    work: (ctx: {
      attempt: number;
      yieldCount: number;
      lease: ScheduledLease;
      yieldSignal: AbortSignal;
    }) => Promise<{ value: T; promptTokens?: number }>,
  ): Promise<{ value: T; yieldCount: number; attempts: number }> {
    let yieldCount = 0;
    let attempts = 0;

    while (true) {
      attempts += 1;
      const yieldController = new AbortController();
      const lease = await this.acquire({
        ...options,
        onYieldRequested: () => {
          yieldController.abort(new SchedulerYieldError(options.runId ?? 'unknown'));
        },
      });

      const started = this.nowMs();
      try {
        const output = await work({
          attempt: attempts,
          yieldCount,
          lease,
          yieldSignal: yieldController.signal,
        });
        lease.reportMetrics({
          durationMs: Math.max(1, this.nowMs() - started),
          promptTokens: output.promptTokens,
        });
        lease.release();
        return { value: output.value, yieldCount, attempts };
      } catch (err) {
        const isYield = err instanceof SchedulerYieldError || lease.wasYielded();
        if (isYield && !options.signal?.aborted) {
          yieldCount += 1;
          lease.release();
          continue;
        }
        const msg = err instanceof Error ? err.message : String(err);
        const rateLimited = /\b(429|503|529|rate.?limit|overloaded)\b/i.test(msg);
        const timedOut = /\b(timeout|timed out|ETIMEDOUT)\b/i.test(msg);
        lease.reportMetrics({
          durationMs: Math.max(1, this.nowMs() - started),
          rateLimitedOrOverloaded: rateLimited,
          timedOut,
        });
        lease.release();
        throw err;
      }
    }
  }

  private normalizeConfig(cfg: EndpointPoolConfig): Required<EndpointPoolConfig> {
    const minLimit = Math.max(1, cfg.minLimit ?? 1);
    const maxLimit = Math.max(minLimit, cfg.maxLimit);
    const initialLimit = Math.max(minLimit, Math.min(maxLimit, cfg.initialLimit));
    return {
      initialLimit,
      maxLimit,
      minLimit,
      baseRetryBackoffMs: cfg.baseRetryBackoffMs ?? 5 * 60_000,
      rateLimitHoldoffMs: cfg.rateLimitHoldoffMs ?? 60_000,
      slowdownMultiplier: cfg.slowdownMultiplier ?? 1.85,
    };
  }

  private ensurePool(endpointKey: string): EndpointPoolState {
    let pool = this.pools.get(endpointKey);
    if (!pool) {
      const cfg = this.normalizeConfig(this.customConfigs.get(endpointKey) ?? this.defaultConfig);
      pool = {
        config: cfg,
        hardLimit: cfg.initialLimit,
        active: new Map(),
        waiters: [],
        baselineMsPer1kTokens: null,
        holdoffUntilMs: 0,
        levelBackoff: new Map(),
        totalYields: 0,
        totalRateLimitBackoffs: 0,
      };
      this.pools.set(endpointKey, pool);
    }
    return pool;
  }

  private softLimitFor(pool: EndpointPoolState): number {
    return Math.max(1, pool.hardLimit - 1);
  }

  private canAdmit(pool: EndpointPoolState, priority: SchedulerPriority, hasHigherWaiter: boolean): boolean {
    if (hasHigherWaiter) return false;
    const activeCount = pool.active.size;
    if (activeCount >= pool.hardLimit) return false;

    // Reserve the final slot for interactive/approval work whenever hardLimit > 1
    if (!isInteractivePriority(priority) && pool.hardLimit > 1) {
      const soft = this.softLimitFor(pool);
      return activeCount < soft;
    }
    return true;
  }

  private createLease(
    endpointKey: string,
    pool: EndpointPoolState,
    runId: string,
    priority: SchedulerPriority,
    canYield: () => boolean,
    onYieldRequested?: () => void,
  ): ScheduledLease {
    const leaseId = `lease_${randomUUID().slice(0, 8)}`;
    const entry: ActiveSlotEntry = {
      leaseId,
      runId,
      priority,
      startedAtMs: this.nowMs(),
      canYield,
      onYieldRequested,
      yieldRequested: false,
      released: false,
    };
    pool.active.set(leaseId, entry);

    let metricsReported = false;
    return {
      leaseId,
      runId,
      endpointKey,
      priority,
      startedAtMs: entry.startedAtMs,
      wasYielded: () => entry.yieldRequested,
      reportMetrics: (metrics: LeaseCompletionMetrics) => {
        if (metricsReported) return;
        metricsReported = true;
        this.applyAimdFeedback(pool, metrics);
      },
      release: () => {
        if (entry.released) return;
        entry.released = true;
        pool.active.delete(leaseId);
        this.drain(endpointKey);
      },
    };
  }

  private tryRequestYield(pool: EndpointPoolState, incomingPriority: SchedulerPriority): boolean {
    const incomingRank = SCHEDULER_PRIORITY_RANK[incomingPriority];
    const candidates = Array.from(pool.active.values())
      .filter((entry) => {
        if (entry.yieldRequested || entry.released) return false;
        const rank = SCHEDULER_PRIORITY_RANK[entry.priority];
        if (rank <= incomingRank) return false;
        if (!isPreemptiblePriority(entry.priority)) return false;
        return entry.canYield();
      })
      // Lowest priority (highest rank) yields first; newest started yields before older work
      .sort((a, b) => {
        const rankDiff = SCHEDULER_PRIORITY_RANK[b.priority] - SCHEDULER_PRIORITY_RANK[a.priority];
        if (rankDiff !== 0) return rankDiff;
        return b.startedAtMs - a.startedAtMs;
      });

    const victim = candidates[0];
    if (!victim) return false;
    victim.yieldRequested = true;
    pool.totalYields += 1;
    victim.onYieldRequested?.();
    return true;
  }

  private applyAimdFeedback(pool: EndpointPoolState, metrics: LeaseCompletionMetrics): void {
    const now = this.nowMs();

    if (metrics.rateLimitedOrOverloaded || metrics.timedOut) {
      pool.totalRateLimitBackoffs += 1;
      const previous = pool.hardLimit;
      const next = Math.max(pool.config.minLimit, Math.floor(previous / 2));
      pool.hardLimit = next;
      pool.holdoffUntilMs = now + pool.config.rateLimitHoldoffMs;
      this.recordLevelBackoff(pool, previous, now);
      return;
    }

    const tokenUnits = Math.max(1, (metrics.promptTokens ?? 1000) / 1000);
    const msPer1k = metrics.durationMs / tokenUnits;

    if (pool.baselineMsPer1kTokens === null || pool.active.size <= 1) {
      pool.baselineMsPer1kTokens =
        pool.baselineMsPer1kTokens === null
          ? msPer1k
          : pool.baselineMsPer1kTokens * 0.7 + msPer1k * 0.3;
    }

    const baseline = pool.baselineMsPer1kTokens;
    if (pool.hardLimit > pool.config.minLimit && msPer1k > baseline * pool.config.slowdownMultiplier) {
      const rejected = pool.hardLimit;
      pool.hardLimit = Math.max(pool.config.minLimit, rejected - 1);
      this.recordLevelBackoff(pool, rejected, now);
      return;
    }

    // Additive increase only when work is queued, response stays fast, and backoff expired
    if (
      pool.waiters.length > 0 &&
      pool.hardLimit < pool.config.maxLimit &&
      now >= pool.holdoffUntilMs &&
      msPer1k <= baseline * 1.35
    ) {
      const candidate = pool.hardLimit + 1;
      const backoff = pool.levelBackoff.get(candidate);
      if (!backoff || now >= backoff.untilMs) {
        pool.hardLimit = candidate;
      }
    }
  }

  private recordLevelBackoff(pool: EndpointPoolState, level: number, now: number): void {
    if (level <= pool.config.minLimit) return;
    const prev = pool.levelBackoff.get(level);
    const maxBackoffMs = 30 * 60_000;
    const durationMs = prev ? Math.min(maxBackoffMs, prev.durationMs * 2) : pool.config.baseRetryBackoffMs;
    pool.levelBackoff.set(level, { untilMs: now + durationMs, durationMs });
  }

  private sortWaiters(pool: EndpointPoolState): void {
    pool.waiters.sort((a, b) => {
      const rankDiff = SCHEDULER_PRIORITY_RANK[a.priority] - SCHEDULER_PRIORITY_RANK[b.priority];
      if (rankDiff !== 0) return rankDiff;
      return a.enqueuedAtMs - b.enqueuedAtMs;
    });
  }

  private drain(endpointKey: string): void {
    const pool = this.pools.get(endpointKey);
    if (!pool || pool.waiters.length === 0) return;
    this.sortWaiters(pool);

    let idx = 0;
    while (idx < pool.waiters.length) {
      const waiter = pool.waiters[idx]!;
      const hasInteractiveAhead = pool.waiters
        .slice(0, idx)
        .some((earlier) => isInteractivePriority(earlier.priority));

      if (this.canAdmit(pool, waiter.priority, hasInteractiveAhead)) {
        pool.waiters.splice(idx, 1);
        waiter.cleanupAbort?.();
        const lease = this.createLease(
          endpointKey,
          pool,
          waiter.runId,
          waiter.priority,
          waiter.canYield,
          waiter.onYieldRequested,
        );
        waiter.resolve(lease);
        continue;
      }

      if (isInteractivePriority(waiter.priority)) {
        this.tryRequestYield(pool, waiter.priority);
      }
      idx += 1;
    }
  }
}

// ---------------------------------------------------------------------------
// Unified Structured-Output Retry & Schema Self-Correction Helper
// ---------------------------------------------------------------------------

export interface StructuredRetryOptions<T> {
  maxAttempts?: number;
  baseDelayMs?: number;
  sleep?: (ms: number) => Promise<void>;
  invoke: (correctionFeedback: string | null, attempt: number) => Promise<string>;
  validate: (rawText: string) => { ok: true; value: T } | { ok: false; error: string };
}

export async function executeWithStructuredCorrection<T>(
  options: StructuredRetryOptions<T>,
): Promise<{ value: T; attempts: number }> {
  const maxAttempts = Math.max(1, options.maxAttempts ?? 3);
  const baseDelayMs = options.baseDelayMs ?? 150;
  const sleep = options.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));

  let feedback: string | null = null;
  let lastError = 'Unknown structured output error';

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      const raw = await options.invoke(feedback, attempt);
      const checked = options.validate(raw);
      if (checked.ok) {
        return { value: checked.value, attempts: attempt };
      }
      lastError = checked.error;
      feedback = `Previous response failed schema validation: ${checked.error}. Return ONLY valid JSON matching the required schema.`;
    } catch (err) {
      lastError = err instanceof Error ? err.message : String(err);
      feedback = `Previous call failed (${lastError}). Retry cleanly and return valid JSON.`;
      if (attempt < maxAttempts && baseDelayMs > 0) {
        await sleep(baseDelayMs * attempt);
      }
    }
  }

  throw new Error(`Structured output failed after ${maxAttempts} attempt(s): ${lastError}`);
}
