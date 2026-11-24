/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/core - board-engine.ts
 * Harness-Agnostic Multi-Agent Coordination Board (`PipiBoardEngine`):
 * - Unified Channel -> Thread -> Task primitive inspired by Vercel Board
 * - Atomic task claiming with TTL leases, heartbeat renewal, and automatic `claim_lost` expiry recovery
 * - Lightweight task dependency DAG (`blockedBy`) with automatic downstream unlocking on completion
 * - Thread-scoped scheduled follow-ups and live `inspect` event ring buffer for SSE/CLI streaming
 * - Zero external dependencies; atomic JSON persistence (`board.json`)
 */

import { randomBytes, randomUUID } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

import type {
  BoardActivityEvent,
  BoardActorRef,
  BoardChannel,
  BoardEventKind,
  BoardMessage,
  BoardScheduledFollowUp,
  BoardSnapshot,
  BoardTaskClaim,
  BoardTaskPriority,
  BoardTaskStatus,
  BoardThread,
  BoardThreadKind,
} from '@pipibot/protocol';

export const DEFAULT_BOARD_LEASE_MS = 15 * 60 * 1000; // 15 minutes
export const MIN_BOARD_LEASE_MS = 5 * 1000; // 5 seconds
export const MAX_BOARD_LEASE_MS = 2 * 60 * 60 * 1000; // 2 hours
export const DEFAULT_MAX_CLAIM_RETRIES = 3;
const MAX_RECENT_EVENTS = 500;

const PRIORITY_RANK: Record<BoardTaskPriority, number> = {
  urgent: 0,
  high: 1,
  normal: 2,
  low: 3,
};

const SYSTEM_ACTOR: BoardActorRef = {
  id: 'system:board',
  name: 'Board',
  kind: 'system',
};

export interface PipiBoardEngineOptions {
  dataDir?: string;
  fileName?: string;
  nowFn?: () => number;
  seedDefaultChannels?: boolean;
}

export interface CreateBoardThreadInput {
  channelSlug?: string;
  title: string;
  body?: string;
  kind?: BoardThreadKind;
  priority?: BoardTaskPriority;
  labels?: string[];
  blockedBy?: string[];
  maxClaimRetries?: number;
  author: BoardActorRef;
  linkedConversationId?: string;
  linkedWorktreeId?: string;
  linkedDecisionId?: string;
}

export interface PostBoardMessageInput {
  author: BoardActorRef;
  body: string;
  artifactRef?: string;
  metadata?: Record<string, string>;
}

export interface ClaimBoardTaskInput {
  actor: BoardActorRef;
  leaseMs?: number;
  note?: string;
}

export interface ClaimBoardTaskResult {
  ok: boolean;
  reason?: 'not_found' | 'blocked' | 'already_claimed' | 'terminal_status' | 'no_open_tasks';
  thread?: BoardThread;
  claim?: BoardTaskClaim;
  conflictClaim?: BoardTaskClaim;
  unresolvedBlockers?: string[];
  renewed?: boolean;
}

export interface RenewBoardLeaseInput {
  actorId: string;
  leaseToken: string;
  leaseMs?: number;
}

export interface RenewBoardLeaseResult {
  ok: boolean;
  reason?: 'not_found' | 'not_claimed' | 'actor_mismatch' | 'token_mismatch' | 'lease_expired';
  thread?: BoardThread;
  claim?: BoardTaskClaim;
}

export interface ReleaseBoardClaimInput {
  actorId: string;
  leaseToken?: string;
  force?: boolean;
  reason?: string;
}

export interface CompleteBoardTaskInput {
  actor: BoardActorRef;
  summary?: string;
  deliverableRef?: string;
  leaseToken?: string;
}

export interface CompleteBoardTaskResult {
  ok: boolean;
  reason?: 'not_found' | 'token_mismatch' | 'already_terminal';
  thread?: BoardThread;
  unblockedThreadIds: string[];
}

export interface ScheduleBoardFollowUpInput {
  actor: BoardActorRef;
  prompt: string;
  dueAt?: string;
  inMs?: number;
}

export interface BoardListThreadsFilter {
  channelSlug?: string;
  status?: BoardTaskStatus;
  kind?: BoardThreadKind;
  label?: string;
  claimedByActorId?: string;
}

export interface BoardInspectReport {
  channels: Array<BoardChannel & { openCount: number; claimedCount: number; needsYouCount: number; totalCount: number }>;
  activeLeases: Array<{
    threadId: string;
    channelSlug: string;
    title: string;
    actor: BoardActorRef;
    expiresAt: string;
    remainingMs: number;
    renewCount: number;
  }>;
  pendingFollowUps: BoardScheduledFollowUp[];
  counts: Record<BoardTaskStatus, number>;
  recentEvents: BoardActivityEvent[];
  inspectedAt: string;
}

interface PersistedBoardState {
  schemaVersion: 1;
  channels: BoardChannel[];
  threads: BoardThread[];
  recentEvents: BoardActivityEvent[];
  updatedAt: string;
}

export function normalizeChannelSlug(raw?: string): string {
  const cleaned = (raw ?? 'inbox')
    .trim()
    .replace(/^#+/, '')
    .toLowerCase()
    .split('/')
    .map((seg) =>
      seg
        .trim()
        .replace(/[^a-z0-9_-]+/g, '-')
        .replace(/-+/g, '-')
        .replace(/^-|-$/g, ''),
    )
    .filter(Boolean)
    .join('/');
  return cleaned || 'inbox';
}

function clampLeaseMs(leaseMs?: number): number {
  const val = typeof leaseMs === 'number' && Number.isFinite(leaseMs) ? Math.floor(leaseMs) : DEFAULT_BOARD_LEASE_MS;
  return Math.max(MIN_BOARD_LEASE_MS, Math.min(MAX_BOARD_LEASE_MS, val));
}

export class PipiBoardEngine {
  private readonly channels = new Map<string, BoardChannel>();
  private readonly threads = new Map<string, BoardThread>();
  private recentEvents: BoardActivityEvent[] = [];
  private readonly listeners = new Set<(event: BoardActivityEvent) => void>();
  private readonly storagePath?: string;
  private readonly nowFn: () => number;

  constructor(options: PipiBoardEngineOptions = {}) {
    this.nowFn = options.nowFn ?? (() => Date.now());
    if (options.dataDir) {
      this.storagePath = join(options.dataDir, options.fileName ?? 'board.json');
      this.loadFromDisk();
    }
    if (options.seedDefaultChannels !== false) {
      this.ensureDefaultChannels();
    }
  }

  private nowMs(): number {
    return this.nowFn();
  }

  private nowIso(): string {
    return new Date(this.nowMs()).toISOString();
  }

  onEvent(listener: (event: BoardActivityEvent) => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  private emit(
    kind: BoardEventKind,
    channelSlug: string,
    actor: BoardActorRef,
    summary: string,
    threadId?: string,
    detail?: Record<string, string>,
  ): BoardActivityEvent {
    const event: BoardActivityEvent = {
      id: `bev_${randomUUID().slice(0, 8)}`,
      kind,
      channelSlug,
      threadId,
      actor,
      summary,
      detail,
      createdAt: this.nowIso(),
    };
    this.recentEvents.push(event);
    if (this.recentEvents.length > MAX_RECENT_EVENTS) {
      this.recentEvents = this.recentEvents.slice(-MAX_RECENT_EVENTS);
    }
    for (const listener of this.listeners) {
      try {
        listener(event);
      } catch {
        // Isolate subscriber errors
      }
    }
    return event;
  }

  private loadFromDisk(): void {
    if (!this.storagePath || !existsSync(this.storagePath)) return;
    try {
      const raw = readFileSync(this.storagePath, 'utf8');
      const parsed = JSON.parse(raw) as Partial<PersistedBoardState>;
      if (Array.isArray(parsed.channels)) {
        for (const ch of parsed.channels) {
          if (ch && typeof ch.slug === 'string') {
            this.channels.set(normalizeChannelSlug(ch.slug), ch);
          }
        }
      }
      if (Array.isArray(parsed.threads)) {
        for (const th of parsed.threads) {
          if (th && typeof th.id === 'string') {
            this.threads.set(th.id, th);
          }
        }
      }
      if (Array.isArray(parsed.recentEvents)) {
        this.recentEvents = parsed.recentEvents.slice(-MAX_RECENT_EVENTS);
      }
    } catch {
      // Fall back to empty state if persisted file is unreadable
    }
  }

  private persist(): void {
    if (!this.storagePath) return;
    mkdirSync(dirname(this.storagePath), { recursive: true });
    const state: PersistedBoardState = {
      schemaVersion: 1,
      channels: this.listChannels(),
      threads: Array.from(this.threads.values()),
      recentEvents: this.recentEvents.slice(-MAX_RECENT_EVENTS),
      updatedAt: this.nowIso(),
    };
    const tmpPath = `${this.storagePath}.${process.pid}.${randomBytes(4).toString('hex')}.tmp`;
    writeFileSync(tmpPath, JSON.stringify(state, null, 2), 'utf8');
    renameSync(tmpPath, this.storagePath);
  }

  private ensureDefaultChannels(): void {
    const defaults: Array<{ slug: string; title: string; description: string }> = [
      { slug: 'inbox', title: 'Inbox', description: 'Personal capture, quick tasks, and uncategorized threads' },
      { slug: 'dev', title: 'Engineering', description: 'Code changes, worktree diffs, tests, and local CLI agent runs' },
      { slug: 'ops', title: 'Operations', description: 'Device nodes, scheduled checks, and deployment health' },
    ];
    let mutated = false;
    for (const def of defaults) {
      if (!this.channels.has(def.slug)) {
        const now = this.nowIso();
        this.channels.set(def.slug, {
          id: `ch_${def.slug}`,
          slug: def.slug,
          title: def.title,
          description: def.description,
          createdAt: now,
          updatedAt: now,
        });
        mutated = true;
      }
    }
    if (mutated) {
      this.persist();
    }
  }

  // -------------------------------------------------------------------------
  // 1. Channels
  // -------------------------------------------------------------------------

  ensureChannel(
    rawSlug: string,
    title?: string,
    description?: string,
    actor: BoardActorRef = SYSTEM_ACTOR,
  ): BoardChannel {
    const slug = normalizeChannelSlug(rawSlug);
    const existing = this.channels.get(slug);
    if (existing) {
      if (title && title.trim() && title.trim() !== existing.title) {
        existing.title = title.trim();
        existing.updatedAt = this.nowIso();
        this.persist();
      }
      if (description !== undefined && description !== existing.description) {
        existing.description = description;
        existing.updatedAt = this.nowIso();
        this.persist();
      }
      return existing;
    }

    const now = this.nowIso();
    const channel: BoardChannel = {
      id: `ch_${randomUUID().slice(0, 8)}`,
      slug,
      title: title?.trim() || slug,
      description,
      createdAt: now,
      updatedAt: now,
    };
    this.channels.set(slug, channel);
    this.emit('channel_created', slug, actor, `Created channel #${slug}`);
    this.persist();
    return channel;
  }

  listChannels(): BoardChannel[] {
    return Array.from(this.channels.values()).sort((a, b) => a.slug.localeCompare(b.slug));
  }

  // -------------------------------------------------------------------------
  // 2. Threads & Messages
  // -------------------------------------------------------------------------

  createThread(input: CreateBoardThreadInput): BoardThread {
    const channelSlug = normalizeChannelSlug(input.channelSlug);
    if (!this.channels.has(channelSlug)) {
      this.ensureChannel(channelSlug, undefined, undefined, input.author);
    }

    const now = this.nowIso();
    const threadId = `bth_${randomUUID().slice(0, 8)}`;
    const blockedBy = Array.from(new Set((input.blockedBy ?? []).map((id) => id.trim()).filter(Boolean)));
    const unresolved = this.getUnresolvedBlockers(blockedBy);
    const initialStatus: BoardTaskStatus = unresolved.length > 0 ? 'blocked' : 'open';

    const rootBody = (input.body ?? '').trim();
    const initialMessages: BoardMessage[] = rootBody
      ? [
          {
            id: `bmsg_${randomUUID().slice(0, 8)}`,
            threadId,
            author: input.author,
            body: rootBody,
            createdAt: now,
          },
        ]
      : [];

    const thread: BoardThread = {
      id: threadId,
      channelSlug,
      kind: input.kind ?? 'task',
      title: input.title.trim() || 'Untitled thread',
      status: initialStatus,
      priority: input.priority ?? 'normal',
      labels: Array.from(new Set((input.labels ?? []).map((l) => l.trim().toLowerCase()).filter(Boolean))),
      blockedBy,
      claimLostCount: 0,
      maxClaimRetries: Math.max(1, input.maxClaimRetries ?? DEFAULT_MAX_CLAIM_RETRIES),
      messages: initialMessages,
      followUps: [],
      linkedConversationId: input.linkedConversationId,
      linkedWorktreeId: input.linkedWorktreeId,
      linkedDecisionId: input.linkedDecisionId,
      createdBy: input.author,
      createdAt: now,
      updatedAt: now,
    };

    this.threads.set(threadId, thread);
    const ch = this.channels.get(channelSlug);
    if (ch) ch.updatedAt = now;

    this.emit(
      'thread_created',
      channelSlug,
      input.author,
      `${input.author.name} created ${thread.kind} "${thread.title}" in #${channelSlug}`,
      threadId,
      { status: thread.status, priority: thread.priority },
    );
    this.persist();
    return thread;
  }

  getThread(threadId: string): BoardThread | undefined {
    return this.threads.get(threadId);
  }

  listThreads(filter: BoardListThreadsFilter = {}): BoardThread[] {
    const channelSlug = filter.channelSlug ? normalizeChannelSlug(filter.channelSlug) : undefined;
    const labelFilter = filter.label?.trim().toLowerCase();
    return Array.from(this.threads.values())
      .filter((th) => {
        if (channelSlug && th.channelSlug !== channelSlug) return false;
        if (filter.status && th.status !== filter.status) return false;
        if (filter.kind && th.kind !== filter.kind) return false;
        if (labelFilter && !th.labels.includes(labelFilter)) return false;
        if (filter.claimedByActorId && th.claim?.actor.id !== filter.claimedByActorId) return false;
        return true;
      })
      .sort((a, b) => {
        const pDiff = PRIORITY_RANK[a.priority] - PRIORITY_RANK[b.priority];
        if (pDiff !== 0) return pDiff;
        return b.updatedAt.localeCompare(a.updatedAt);
      });
  }

  postMessage(threadId: string, input: PostBoardMessageInput): BoardMessage | null {
    const thread = this.threads.get(threadId);
    if (!thread) return null;

    const now = this.nowIso();
    const message: BoardMessage = {
      id: `bmsg_${randomUUID().slice(0, 8)}`,
      threadId,
      author: input.author,
      body: input.body.trim(),
      artifactRef: input.artifactRef,
      metadata: input.metadata,
      createdAt: now,
    };
    thread.messages.push(message);
    thread.updatedAt = now;
    const ch = this.channels.get(thread.channelSlug);
    if (ch) ch.updatedAt = now;

    this.emit(
      'message_posted',
      thread.channelSlug,
      input.author,
      `${input.author.name} posted in "${thread.title}"`,
      threadId,
      input.artifactRef ? { artifactRef: input.artifactRef } : undefined,
    );
    this.persist();
    return message;
  }

  // -------------------------------------------------------------------------
  // 3. Atomic Task Claims, Leases, Renewal & Expiry Recovery
  // -------------------------------------------------------------------------

  private getUnresolvedBlockers(blockedBy: string[]): string[] {
    return blockedBy.filter((depId) => {
      const dep = this.threads.get(depId);
      return !dep || dep.status !== 'done';
    });
  }

  claimTask(threadId: string, input: ClaimBoardTaskInput): ClaimBoardTaskResult {
    const thread = this.threads.get(threadId);
    if (!thread) {
      return { ok: false, reason: 'not_found' };
    }

    // Reclaim expired lease before evaluating claim state
    this.sweepSingleExpiredLease(thread);

    if (thread.status === 'done' || thread.status === 'cancelled') {
      return { ok: false, reason: 'terminal_status', thread };
    }

    const unresolved = this.getUnresolvedBlockers(thread.blockedBy);
    if (unresolved.length > 0 || thread.status === 'blocked') {
      thread.status = 'blocked';
      return { ok: false, reason: 'blocked', thread, unresolvedBlockers: unresolved };
    }

    const leaseMs = clampLeaseMs(input.leaseMs);
    const nowMs = this.nowMs();
    const nowIso = new Date(nowMs).toISOString();
    const expiresAt = new Date(nowMs + leaseMs).toISOString();

    if (thread.status === 'claimed' && thread.claim) {
      if (thread.claim.actor.id === input.actor.id) {
        // Idempotent renewal for the same actor
        thread.claim.expiresAt = expiresAt;
        thread.claim.renewCount += 1;
        if (input.note) thread.claim.note = input.note;
        thread.updatedAt = nowIso;
        this.emit(
          'lease_renewed',
          thread.channelSlug,
          input.actor,
          `${input.actor.name} renewed lease on "${thread.title}"`,
          thread.id,
          { expiresAt, renewCount: String(thread.claim.renewCount) },
        );
        this.persist();
        return { ok: true, thread, claim: thread.claim, renewed: true };
      }
      return {
        ok: false,
        reason: 'already_claimed',
        thread,
        conflictClaim: thread.claim,
      };
    }

    const claim: BoardTaskClaim = {
      actor: input.actor,
      leaseToken: `lease_${randomBytes(9).toString('hex')}`,
      claimedAt: nowIso,
      expiresAt,
      renewCount: 0,
      note: input.note,
    };

    thread.claim = claim;
    thread.status = 'claimed';
    thread.updatedAt = nowIso;

    this.emit(
      'task_claimed',
      thread.channelSlug,
      input.actor,
      `${input.actor.name} claimed "${thread.title}"`,
      thread.id,
      { expiresAt, leaseMs: String(leaseMs) },
    );
    this.persist();
    return { ok: true, thread, claim, renewed: false };
  }

  claimNextTask(input: {
    actor: BoardActorRef;
    channelSlug?: string;
    label?: string;
    leaseMs?: number;
    note?: string;
  }): ClaimBoardTaskResult {
    this.sweepExpiredLeases();

    const channelSlug = input.channelSlug ? normalizeChannelSlug(input.channelSlug) : undefined;
    const labelFilter = input.label?.trim().toLowerCase();

    const candidates = Array.from(this.threads.values())
      .filter((th) => {
        if (th.status !== 'open') return false;
        if (channelSlug && th.channelSlug !== channelSlug) return false;
        if (labelFilter && !th.labels.includes(labelFilter)) return false;
        if (this.getUnresolvedBlockers(th.blockedBy).length > 0) return false;
        return true;
      })
      .sort((a, b) => {
        const pDiff = PRIORITY_RANK[a.priority] - PRIORITY_RANK[b.priority];
        if (pDiff !== 0) return pDiff;
        return a.createdAt.localeCompare(b.createdAt); // FIFO within priority
      });

    const next = candidates[0];
    if (!next) {
      return { ok: false, reason: 'no_open_tasks' };
    }
    return this.claimTask(next.id, {
      actor: input.actor,
      leaseMs: input.leaseMs,
      note: input.note,
    });
  }

  renewLease(threadId: string, input: RenewBoardLeaseInput): RenewBoardLeaseResult {
    const thread = this.threads.get(threadId);
    if (!thread) return { ok: false, reason: 'not_found' };

    if (this.sweepSingleExpiredLease(thread)) {
      this.persist();
      return { ok: false, reason: 'lease_expired', thread };
    }

    if (thread.status !== 'claimed' || !thread.claim) {
      return { ok: false, reason: 'not_claimed', thread };
    }
    if (thread.claim.actor.id !== input.actorId) {
      return { ok: false, reason: 'actor_mismatch', thread };
    }
    if (thread.claim.leaseToken !== input.leaseToken) {
      return { ok: false, reason: 'token_mismatch', thread };
    }

    const leaseMs = clampLeaseMs(input.leaseMs);
    const nowMs = this.nowMs();
    thread.claim.expiresAt = new Date(nowMs + leaseMs).toISOString();
    thread.claim.renewCount += 1;
    thread.updatedAt = new Date(nowMs).toISOString();

    this.emit(
      'lease_renewed',
      thread.channelSlug,
      thread.claim.actor,
      `${thread.claim.actor.name} renewed lease on "${thread.title}"`,
      thread.id,
      { expiresAt: thread.claim.expiresAt, renewCount: String(thread.claim.renewCount) },
    );
    this.persist();
    return { ok: true, thread, claim: thread.claim };
  }

  releaseClaim(threadId: string, input: ReleaseBoardClaimInput): { ok: boolean; reason?: string; thread?: BoardThread } {
    const thread = this.threads.get(threadId);
    if (!thread) return { ok: false, reason: 'not_found' };
    if (thread.status !== 'claimed' || !thread.claim) {
      return { ok: false, reason: 'not_claimed', thread };
    }
    if (!input.force) {
      if (thread.claim.actor.id !== input.actorId) {
        return { ok: false, reason: 'actor_mismatch', thread };
      }
      if (input.leaseToken && thread.claim.leaseToken !== input.leaseToken) {
        return { ok: false, reason: 'token_mismatch', thread };
      }
    }

    const prevActor = thread.claim.actor;
    const now = this.nowIso();
    thread.claim = undefined;
    thread.status = 'open';
    thread.updatedAt = now;
    if (input.reason?.trim()) {
      thread.messages.push({
        id: `bmsg_${randomUUID().slice(0, 8)}`,
        threadId: thread.id,
        author: prevActor,
        body: `Released claim: ${input.reason.trim()}`,
        createdAt: now,
      });
    }
    this.emit(
      'claim_lost',
      thread.channelSlug,
      prevActor,
      `${prevActor.name} released "${thread.title}"`,
      thread.id,
      { voluntary: 'true' },
    );
    this.persist();
    return { ok: true, thread };
  }

  private sweepSingleExpiredLease(thread: BoardThread): boolean {
    if (thread.status !== 'claimed' || !thread.claim) return false;
    const expiresMs = Date.parse(thread.claim.expiresAt);
    if (!Number.isFinite(expiresMs) || expiresMs > this.nowMs()) {
      return false;
    }

    const lostActor = thread.claim.actor;
    const now = this.nowIso();
    thread.claim = undefined;
    thread.claimLostCount += 1;
    const escalated = thread.claimLostCount >= thread.maxClaimRetries;
    thread.status = escalated ? 'needs_you' : 'open';
    thread.updatedAt = now;

    thread.messages.push({
      id: `bmsg_${randomUUID().slice(0, 8)}`,
      threadId: thread.id,
      author: SYSTEM_ACTOR,
      body: escalated
        ? `Lease expired for ${lostActor.name} (${thread.claimLostCount}/${thread.maxClaimRetries}). Escalated to Needs You.`
        : `Lease expired for ${lostActor.name} (${thread.claimLostCount}/${thread.maxClaimRetries}). Returned to open queue.`,
      createdAt: now,
    });

    this.emit(
      'claim_lost',
      thread.channelSlug,
      lostActor,
      `Lease expired for ${lostActor.name} on "${thread.title}"`,
      thread.id,
      {
        escalatedToNeedsYou: String(escalated),
        claimLostCount: String(thread.claimLostCount),
      },
    );
    if (escalated) {
      this.emit(
        'task_needs_you',
        thread.channelSlug,
        SYSTEM_ACTOR,
        `Task "${thread.title}" needs human review after repeated lease expiry`,
        thread.id,
      );
    }
    return true;
  }

  sweepExpiredLeases(): BoardThread[] {
    const expired: BoardThread[] = [];
    for (const thread of this.threads.values()) {
      if (this.sweepSingleExpiredLease(thread)) {
        expired.push(thread);
      }
    }
    if (expired.length > 0) {
      this.persist();
    }
    return expired;
  }

  // -------------------------------------------------------------------------
  // 4. Needs-You Escalation, Completion & Dependency Unlocking
  // -------------------------------------------------------------------------

  requestNeedsYou(
    threadId: string,
    input: { actor: BoardActorRef; summary: string; decisionId?: string; artifactRef?: string },
  ): BoardThread | null {
    const thread = this.threads.get(threadId);
    if (!thread) return null;

    const now = this.nowIso();
    thread.status = 'needs_you';
    thread.claim = undefined;
    if (input.decisionId) thread.linkedDecisionId = input.decisionId;
    thread.updatedAt = now;

    thread.messages.push({
      id: `bmsg_${randomUUID().slice(0, 8)}`,
      threadId: thread.id,
      author: input.actor,
      body: input.summary.trim(),
      artifactRef: input.artifactRef,
      createdAt: now,
    });

    this.emit(
      'task_needs_you',
      thread.channelSlug,
      input.actor,
      `${input.actor.name} requested human input on "${thread.title}"`,
      thread.id,
      input.decisionId ? { decisionId: input.decisionId } : undefined,
    );
    this.persist();
    return thread;
  }

  completeTask(threadId: string, input: CompleteBoardTaskInput): CompleteBoardTaskResult {
    const thread = this.threads.get(threadId);
    if (!thread) {
      return { ok: false, reason: 'not_found', unblockedThreadIds: [] };
    }
    if (thread.status === 'done' || thread.status === 'cancelled') {
      return { ok: false, reason: 'already_terminal', thread, unblockedThreadIds: [] };
    }
    if (input.leaseToken && thread.claim && thread.claim.leaseToken !== input.leaseToken) {
      return { ok: false, reason: 'token_mismatch', thread, unblockedThreadIds: [] };
    }

    const now = this.nowIso();
    thread.status = 'done';
    thread.claim = undefined;
    thread.completedAt = now;
    thread.updatedAt = now;
    if (input.deliverableRef) {
      thread.deliverableRef = input.deliverableRef;
    }

    if (input.summary?.trim() || input.deliverableRef) {
      thread.messages.push({
        id: `bmsg_${randomUUID().slice(0, 8)}`,
        threadId: thread.id,
        author: input.actor,
        body: input.summary?.trim() || `Completed task with deliverable ${input.deliverableRef}`,
        artifactRef: input.deliverableRef,
        createdAt: now,
      });
    }

    this.emit(
      'task_completed',
      thread.channelSlug,
      input.actor,
      `${input.actor.name} completed "${thread.title}"`,
      thread.id,
      input.deliverableRef ? { deliverableRef: input.deliverableRef } : undefined,
    );

    // Automatically unlock downstream blocked tasks whose dependencies are all done
    const unblockedThreadIds: string[] = [];
    for (const candidate of this.threads.values()) {
      if (candidate.status !== 'blocked') continue;
      if (!candidate.blockedBy.includes(thread.id)) continue;
      if (this.getUnresolvedBlockers(candidate.blockedBy).length === 0) {
        candidate.status = 'open';
        candidate.updatedAt = now;
        candidate.messages.push({
          id: `bmsg_${randomUUID().slice(0, 8)}`,
          threadId: candidate.id,
          author: SYSTEM_ACTOR,
          body: `Unblocked after "${thread.title}" (${thread.id}) completed. Ready to claim.`,
          createdAt: now,
        });
        unblockedThreadIds.push(candidate.id);
        this.emit(
          'task_unblocked',
          candidate.channelSlug,
          SYSTEM_ACTOR,
          `Unblocked "${candidate.title}" after "${thread.title}" completed`,
          candidate.id,
          { unblockedBy: thread.id },
        );
      }
    }

    this.persist();
    return { ok: true, thread, unblockedThreadIds };
  }

  // -------------------------------------------------------------------------
  // 5. Thread-Scoped Scheduled Follow-Ups
  // -------------------------------------------------------------------------

  scheduleFollowUp(threadId: string, input: ScheduleBoardFollowUpInput): BoardScheduledFollowUp | null {
    const thread = this.threads.get(threadId);
    if (!thread) return null;

    const nowMs = this.nowMs();
    const nowIso = new Date(nowMs).toISOString();
    const dueIso =
      input.dueAt ??
      new Date(nowMs + Math.max(1000, typeof input.inMs === 'number' ? input.inMs : 5 * 60 * 1000)).toISOString();

    const followUp: BoardScheduledFollowUp = {
      id: `bfup_${randomUUID().slice(0, 8)}`,
      threadId: thread.id,
      actor: input.actor,
      prompt: input.prompt.trim(),
      dueAt: dueIso,
      status: 'pending',
      createdAt: nowIso,
    };

    thread.followUps.push(followUp);
    thread.updatedAt = nowIso;

    this.emit(
      'followup_scheduled',
      thread.channelSlug,
      input.actor,
      `${input.actor.name} scheduled follow-up on "${thread.title}" for ${dueIso}`,
      thread.id,
      { followUpId: followUp.id, dueAt: dueIso },
    );
    this.persist();
    return followUp;
  }

  collectDueFollowUps(): BoardScheduledFollowUp[] {
    const nowMs = this.nowMs();
    const nowIso = new Date(nowMs).toISOString();
    const triggered: BoardScheduledFollowUp[] = [];

    for (const thread of this.threads.values()) {
      for (const fup of thread.followUps) {
        if (fup.status !== 'pending') continue;
        const dueMs = Date.parse(fup.dueAt);
        if (Number.isFinite(dueMs) && dueMs <= nowMs) {
          fup.status = 'triggered';
          fup.triggeredAt = nowIso;
          thread.updatedAt = nowIso;
          thread.messages.push({
            id: `bmsg_${randomUUID().slice(0, 8)}`,
            threadId: thread.id,
            author: SYSTEM_ACTOR,
            body: `Scheduled follow-up due (${fup.actor.name}): ${fup.prompt}`,
            createdAt: nowIso,
          });
          triggered.push(fup);
          this.emit(
            'followup_triggered',
            thread.channelSlug,
            fup.actor,
            `Follow-up due on "${thread.title}": ${fup.prompt}`,
            thread.id,
            { followUpId: fup.id },
          );
        }
      }
    }

    if (triggered.length > 0) {
      this.persist();
    }
    return triggered;
  }

  // -------------------------------------------------------------------------
  // 6. Snapshot & Live Inspect Report
  // -------------------------------------------------------------------------

  private computeCounts(threads: BoardThread[]): Record<BoardTaskStatus, number> {
    const counts: Record<BoardTaskStatus, number> = {
      open: 0,
      blocked: 0,
      claimed: 0,
      needs_you: 0,
      done: 0,
      cancelled: 0,
    };
    for (const th of threads) {
      counts[th.status] = (counts[th.status] ?? 0) + 1;
    }
    return counts;
  }

  snapshot(filter: BoardListThreadsFilter = {}): BoardSnapshot {
    this.sweepExpiredLeases();
    const threads = this.listThreads(filter);
    const channelSlug = filter.channelSlug ? normalizeChannelSlug(filter.channelSlug) : undefined;
    const recentEvents = channelSlug
      ? this.recentEvents.filter((ev) => ev.channelSlug === channelSlug).slice(-100)
      : this.recentEvents.slice(-100);
    return {
      channels: this.listChannels(),
      threads,
      recentEvents,
      counts: this.computeCounts(threads),
      updatedAt: this.nowIso(),
    };
  }

  inspect(options: { channelSlug?: string; limit?: number } = {}): BoardInspectReport {
    this.sweepExpiredLeases();
    this.collectDueFollowUps();

    const nowMs = this.nowMs();
    const channelFilter = options.channelSlug ? normalizeChannelSlug(options.channelSlug) : undefined;
    const limit = Math.max(1, Math.min(200, options.limit ?? 40));

    const allThreads = this.listThreads(channelFilter ? { channelSlug: channelFilter } : {});
    const channels = this.listChannels()
      .filter((ch) => !channelFilter || ch.slug === channelFilter)
      .map((ch) => {
        const chThreads = allThreads.filter((th) => th.channelSlug === ch.slug);
        return {
          ...ch,
          openCount: chThreads.filter((t) => t.status === 'open').length,
          claimedCount: chThreads.filter((t) => t.status === 'claimed').length,
          needsYouCount: chThreads.filter((t) => t.status === 'needs_you').length,
          totalCount: chThreads.length,
        };
      });

    const activeLeases = allThreads
      .filter((th) => th.status === 'claimed' && th.claim)
      .map((th) => {
        const claim = th.claim!;
        const remainingMs = Math.max(0, Date.parse(claim.expiresAt) - nowMs);
        return {
          threadId: th.id,
          channelSlug: th.channelSlug,
          title: th.title,
          actor: claim.actor,
          expiresAt: claim.expiresAt,
          remainingMs,
          renewCount: claim.renewCount,
        };
      });

    const pendingFollowUps = allThreads
      .flatMap((th) => th.followUps)
      .filter((f) => f.status === 'pending')
      .sort((a, b) => a.dueAt.localeCompare(b.dueAt));

    const recentEvents = (
      channelFilter ? this.recentEvents.filter((ev) => ev.channelSlug === channelFilter) : this.recentEvents
    ).slice(-limit);

    return {
      channels,
      activeLeases,
      pendingFollowUps,
      counts: this.computeCounts(allThreads),
      recentEvents,
      inspectedAt: new Date(nowMs).toISOString(),
    };
  }
}
