/**
 * @pipibot/core - bot-memory.ts
 *
 * Wave 2 (#02): Per-Bot Isolated Experiential Memory + Prompt-Cache-Safe Recall.
 * - Strict per-bot isolation: `<rootDir>/bots/<botId>/memory/{summary.md, candidates.json, state.json}`
 * - Extraction cadence: every 5 successful runs (configurable) -> candidate lessons
 * - Consolidation cadence: 6h idle OR explicit compaction OR >64KB unconsolidated OR >=30 chats
 * - Prompt-Cache-Safe injection: NEVER mutates System Prompt; injects `summary.md` as a hidden
 *   outbound user-message note ONLY on the first message of a session or immediately after compaction
 *
 * PiPiBot — Clean-room MIT implementation.
 * Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
 * Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.
 */

import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';

import type { BotMemoryLifecycleStage } from '@pipibot/protocol';
import { scrubSensitiveContent } from './memory-engine.ts';

// ---------------------------------------------------------------------------
// 1. Public Contracts & Default Cadence Constants
// ---------------------------------------------------------------------------

export const DEFAULT_EXTRACT_EVERY_RUNS = 5;
export const DEFAULT_IDLE_CONSOLIDATION_HOURS = 6;
export const DEFAULT_MAX_UNCONSOLIDATED_BYTES = 64 * 1024; // 64 KB
export const DEFAULT_MAX_CHATS_BEFORE_CONSOLIDATION = 30;
export const DEFAULT_MAX_SUMMARY_BYTES = 8 * 1024; // 8 KB

export interface BotMemoryCadenceConfig {
  extractEveryRuns: number;
  idleConsolidationHours: number;
  maxUnconsolidatedBytes: number;
  maxChatsBeforeConsolidation: number;
  maxSummaryBytes: number;
}

export interface BotMemoryCandidate {
  id: string;
  botId: string;
  sessionId: string;
  lesson: string;
  stage: BotMemoryLifecycleStage;
  fingerprint: string;
  createdAt: string;
}

export interface BotMemoryState {
  botId: string;
  revision: number;
  totalSuccessfulRuns: number;
  successfulRunsSinceLastExtract: number;
  chatsSinceLastConsolidation: number;
  lastActivityAt?: string;
  lastExtractedAt?: string;
  lastConsolidatedAt?: string;
  summaryByteSize: number;
  candidateByteSize: number;
}

export interface BotRunRecordInput {
  botId: string;
  sessionId: string;
  userPrompt: string;
  assistantReply: string;
  toolSummary?: string;
  nowMs?: number;
}

export type BotMemoryLessonExtractor = (input: {
  botId: string;
  recentRuns: Array<{ userPrompt: string; assistantReply: string; toolSummary?: string }>;
  existingSummary: string;
}) => Promise<string[]> | string[];

export type BotMemoryConsolidator = (input: {
  botId: string;
  existingSummary: string;
  candidates: BotMemoryCandidate[];
  maxSummaryBytes: number;
}) => Promise<string> | string;

export interface RecordBotRunResult {
  state: BotMemoryState;
  extractedCandidates: BotMemoryCandidate[];
  consolidated: boolean;
  consolidationReason?: 'idle_timeout' | 'compaction' | 'byte_limit' | 'chat_count' | 'manual';
}

export interface PromptCacheSafeRecallInput {
  botId: string;
  sessionId: string;
  compactionGeneration: number;
  wikiRecallSnippets?: string[];
}

export interface PromptCacheSafeRecallResult {
  injected: boolean;
  reason: 'first_turn' | 'post_compaction' | 'skipped_cache_preserved' | 'empty_memory';
  hiddenNote: string | null;
  memoryRevision: number;
}

// ---------------------------------------------------------------------------
// 2. Helpers
// ---------------------------------------------------------------------------

function sanitizeBotId(botId: string): string {
  const safe = botId.trim().replace(/[^a-zA-Z0-9_-]/g, '_');
  return safe || 'default_bot';
}

function normalizeLessonFingerprint(lesson: string): string {
  const normalized = lesson
    .toLowerCase()
    .replace(/^[-*•\d.)\s]+/, '')
    .replace(/\s+/g, ' ')
    .trim();
  return createHash('sha256').update(normalized).digest('hex').slice(0, 16);
}

async function atomicWrite(filePath: string, content: string): Promise<void> {
  await mkdir(dirname(filePath), { recursive: true });
  const tmpPath = `${filePath}.tmp.${process.pid}.${randomBytes(6).toString('hex')}`;
  await writeFile(tmpPath, content, 'utf8');
  await rename(tmpPath, filePath);
}

function defaultDeterministicExtract(input: {
  recentRuns: Array<{ userPrompt: string; assistantReply: string; toolSummary?: string }>;
}): string[] {
  const lessons: string[] = [];
  for (const run of input.recentRuns) {
    const prompt = scrubSensitiveContent(run.userPrompt.trim()).sanitized;
    const reply = scrubSensitiveContent(run.assistantReply.trim()).sanitized;
    if (!prompt && !reply) continue;
    const compactPrompt = prompt.replace(/\s+/g, ' ').slice(0, 120);
    const firstSentence = reply
      .split(/[\n。!?]+/)
      .map((s) => s.trim())
      .find((s) => s.length >= 6);
    if (firstSentence) {
      lessons.push(`When handling "${compactPrompt}": ${firstSentence.slice(0, 180)}`);
    } else if (compactPrompt) {
      lessons.push(`Recurring user topic: ${compactPrompt}`);
    }
  }
  return lessons.slice(0, 6);
}

function defaultDeterministicConsolidate(input: {
  existingSummary: string;
  candidates: BotMemoryCandidate[];
  maxSummaryBytes: number;
}): string {
  const seen = new Set<string>();
  const bullets: string[] = [];

  const pushBullet = (raw: string): void => {
    const cleaned = scrubSensitiveContent(raw.replace(/^[-*•]\s*/, '').trim()).sanitized;
    if (!cleaned) return;
    const fp = normalizeLessonFingerprint(cleaned);
    if (seen.has(fp)) return;
    seen.add(fp);
    bullets.push(`- ${cleaned}`);
  };

  for (const line of input.existingSummary.split('\n')) {
    const trimmed = line.trim();
    if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
      pushBullet(trimmed);
    }
  }
  for (const cand of input.candidates) {
    if (cand.stage === 'candidate') {
      pushBullet(cand.lesson);
    }
  }

  // Keep most recent / bounded within maxSummaryBytes
  const header = '# Bot Experiential Memory\n\n';
  const kept: string[] = [];
  let bytes = Buffer.byteLength(header, 'utf8');
  for (let i = bullets.length - 1; i >= 0; i -= 1) {
    const line = `${bullets[i]}\n`;
    const lineBytes = Buffer.byteLength(line, 'utf8');
    if (bytes + lineBytes > input.maxSummaryBytes) break;
    kept.unshift(line);
    bytes += lineBytes;
  }

  return kept.length > 0 ? header + kept.join('') : '';
}

// ---------------------------------------------------------------------------
// 3. PipiBotMemoryEngine
// ---------------------------------------------------------------------------

export interface PipiBotMemoryEngineOptions {
  rootDir: string;
  cadence?: Partial<BotMemoryCadenceConfig>;
  extractor?: BotMemoryLessonExtractor;
  consolidator?: BotMemoryConsolidator;
}

export class PipiBotMemoryEngine {
  readonly rootDir: string;
  readonly cadence: BotMemoryCadenceConfig;
  private readonly extractor: BotMemoryLessonExtractor;
  private readonly consolidator: BotMemoryConsolidator;

  private readonly pendingRunBuffers = new Map<
    string,
    Array<{ sessionId: string; userPrompt: string; assistantReply: string; toolSummary?: string }>
  >();

  // Tracks (botId::sessionId) -> last injected compactionGeneration so repeated turns preserve Prompt Cache!
  private readonly injectedSessionCompactionGen = new Map<string, number>();

  constructor(options: PipiBotMemoryEngineOptions) {
    this.rootDir = options.rootDir;
    this.cadence = {
      extractEveryRuns: Math.max(1, options.cadence?.extractEveryRuns ?? DEFAULT_EXTRACT_EVERY_RUNS),
      idleConsolidationHours: Math.max(0.01, options.cadence?.idleConsolidationHours ?? DEFAULT_IDLE_CONSOLIDATION_HOURS),
      maxUnconsolidatedBytes: Math.max(256, options.cadence?.maxUnconsolidatedBytes ?? DEFAULT_MAX_UNCONSOLIDATED_BYTES),
      maxChatsBeforeConsolidation: Math.max(1, options.cadence?.maxChatsBeforeConsolidation ?? DEFAULT_MAX_CHATS_BEFORE_CONSOLIDATION),
      maxSummaryBytes: Math.max(512, options.cadence?.maxSummaryBytes ?? DEFAULT_MAX_SUMMARY_BYTES),
    };
    this.extractor = options.extractor ?? defaultDeterministicExtract;
    this.consolidator = options.consolidator ?? defaultDeterministicConsolidate;
  }

  botMemoryDir(botId: string): string {
    return join(this.rootDir, 'bots', sanitizeBotId(botId), 'memory');
  }

  private summaryPath(botId: string): string {
    return join(this.botMemoryDir(botId), 'summary.md');
  }

  private candidatesPath(botId: string): string {
    return join(this.botMemoryDir(botId), 'candidates.json');
  }

  private statePath(botId: string): string {
    return join(this.botMemoryDir(botId), 'state.json');
  }

  async readSummary(botId: string): Promise<string> {
    try {
      return await readFile(this.summaryPath(botId), 'utf8');
    } catch {
      return '';
    }
  }

  async readCandidates(botId: string): Promise<BotMemoryCandidate[]> {
    try {
      const raw = await readFile(this.candidatesPath(botId), 'utf8');
      const parsed = JSON.parse(raw) as BotMemoryCandidate[];
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }

  async readState(botId: string): Promise<BotMemoryState> {
    try {
      const raw = await readFile(this.statePath(botId), 'utf8');
      const parsed = JSON.parse(raw) as BotMemoryState;
      if (parsed && parsed.botId) return parsed;
    } catch {
      // fall through to fresh default state
    }
    return {
      botId,
      revision: 0,
      totalSuccessfulRuns: 0,
      successfulRunsSinceLastExtract: 0,
      chatsSinceLastConsolidation: 0,
      summaryByteSize: 0,
      candidateByteSize: 0,
    };
  }

  private async persistState(botId: string, state: BotMemoryState): Promise<void> {
    await atomicWrite(this.statePath(botId), JSON.stringify(state, null, 2));
  }

  private async persistCandidates(botId: string, candidates: BotMemoryCandidate[]): Promise<number> {
    const serialized = JSON.stringify(candidates, null, 2);
    await atomicWrite(this.candidatesPath(botId), serialized);
    return Buffer.byteLength(serialized, 'utf8');
  }

  private async persistSummary(botId: string, summary: string): Promise<number> {
    await atomicWrite(this.summaryPath(botId), summary);
    return Buffer.byteLength(summary, 'utf8');
  }

  // ---- Lifecycle: Record Successful Run -> Extract Every 5 -> Early Consolidation ----

  async recordSuccessfulRun(input: BotRunRecordInput): Promise<RecordBotRunResult> {
    const nowMs = input.nowMs ?? Date.now();
    const nowIso = new Date(nowMs).toISOString();
    const state = await this.readState(input.botId);

    state.totalSuccessfulRuns += 1;
    state.successfulRunsSinceLastExtract += 1;
    state.chatsSinceLastConsolidation += 1;
    state.lastActivityAt = nowIso;

    const buf = this.pendingRunBuffers.get(input.botId) ?? [];
    buf.push({
      sessionId: input.sessionId,
      userPrompt: input.userPrompt,
      assistantReply: input.assistantReply,
      toolSummary: input.toolSummary,
    });
    this.pendingRunBuffers.set(input.botId, buf);

    const extractedCandidates: BotMemoryCandidate[] = [];

    // Trigger candidate extraction every N (default 5) successful runs
    if (state.successfulRunsSinceLastExtract >= this.cadence.extractEveryRuns) {
      const existingSummary = await this.readSummary(input.botId);
      const existingCandidates = await this.readCandidates(input.botId);
      const knownFingerprints = new Set(existingCandidates.map((c) => c.fingerprint));

      const rawLessons = await this.extractor({
        botId: input.botId,
        recentRuns: buf,
        existingSummary,
      });

      for (const rawLesson of rawLessons) {
        const clean = scrubSensitiveContent(rawLesson.trim()).sanitized;
        if (!clean) continue;
        const fp = normalizeLessonFingerprint(clean);
        if (knownFingerprints.has(fp)) continue;
        knownFingerprints.add(fp);
        const cand: BotMemoryCandidate = {
          id: `bmc_${Date.now().toString(36)}_${randomUUID().slice(0, 8)}`,
          botId: input.botId,
          sessionId: input.sessionId,
          lesson: clean,
          stage: 'candidate',
          fingerprint: fp,
          createdAt: nowIso,
        };
        existingCandidates.push(cand);
        extractedCandidates.push(cand);
      }

      state.candidateByteSize = await this.persistCandidates(input.botId, existingCandidates);
      state.successfulRunsSinceLastExtract = 0;
      state.lastExtractedAt = nowIso;
      this.pendingRunBuffers.set(input.botId, []);
    }

    await this.persistState(input.botId, state);

    // Check early byte/chat consolidation thresholds
    const cons = await this.consolidateIfDue(input.botId, { nowMs });
    return {
      state: cons.state,
      extractedCandidates,
      consolidated: cons.consolidated,
      consolidationReason: cons.reason,
    };
  }

  async consolidateIfDue(
    botId: string,
    options: { nowMs?: number; trigger?: 'idle_check' | 'compaction' | 'manual' } = {},
  ): Promise<{
    consolidated: boolean;
    reason?: 'idle_timeout' | 'compaction' | 'byte_limit' | 'chat_count' | 'manual';
    state: BotMemoryState;
    summary: string;
  }> {
    const nowMs = options.nowMs ?? Date.now();
    const trigger = options.trigger ?? 'idle_check';
    const state = await this.readState(botId);
    const candidates = await this.readCandidates(botId);
    const pendingCandidates = candidates.filter((c) => c.stage === 'candidate');
    const existingSummary = await this.readSummary(botId);

    // Also flush any buffered runs into candidates on explicit compaction/manual consolidation
    const buffered = this.pendingRunBuffers.get(botId) ?? [];
    if ((trigger === 'compaction' || trigger === 'manual') && buffered.length > 0) {
      const nowIso = new Date(nowMs).toISOString();
      const rawLessons = await this.extractor({
        botId,
        recentRuns: buffered,
        existingSummary,
      });
      const knownFingerprints = new Set(candidates.map((c) => c.fingerprint));
      for (const rawLesson of rawLessons) {
        const clean = scrubSensitiveContent(rawLesson.trim()).sanitized;
        if (!clean) continue;
        const fp = normalizeLessonFingerprint(clean);
        if (knownFingerprints.has(fp)) continue;
        knownFingerprints.add(fp);
        const cand: BotMemoryCandidate = {
          id: `bmc_${Date.now().toString(36)}_${randomUUID().slice(0, 8)}`,
          botId,
          sessionId: buffered[buffered.length - 1]?.sessionId ?? 'manual',
          lesson: clean,
          stage: 'candidate',
          fingerprint: fp,
          createdAt: nowIso,
        };
        candidates.push(cand);
        pendingCandidates.push(cand);
      }
      this.pendingRunBuffers.set(botId, []);
      state.successfulRunsSinceLastExtract = 0;
      state.lastExtractedAt = nowIso;
    }

    if (pendingCandidates.length === 0) {
      return { consolidated: false, state, summary: existingSummary };
    }

    let reason: 'idle_timeout' | 'compaction' | 'byte_limit' | 'chat_count' | 'manual' | undefined;

    if (trigger === 'manual') {
      reason = 'manual';
    } else if (trigger === 'compaction') {
      reason = 'compaction';
    } else {
      const totalBytes = state.summaryByteSize + state.candidateByteSize;
      if (totalBytes >= this.cadence.maxUnconsolidatedBytes) {
        reason = 'byte_limit';
      } else if (state.chatsSinceLastConsolidation >= this.cadence.maxChatsBeforeConsolidation) {
        reason = 'chat_count';
      } else if (state.lastActivityAt) {
        const idleHours = (nowMs - Date.parse(state.lastActivityAt)) / 3_600_000;
        if (idleHours >= this.cadence.idleConsolidationHours) {
          reason = 'idle_timeout';
        }
      }
    }

    if (!reason) {
      return { consolidated: false, state, summary: existingSummary };
    }

    const mergedSummary = await this.consolidator({
      botId,
      existingSummary,
      candidates: pendingCandidates,
      maxSummaryBytes: this.cadence.maxSummaryBytes,
    });
    const cleanSummary = scrubSensitiveContent(mergedSummary).sanitized;

    const updatedCandidates: BotMemoryCandidate[] = candidates.map((c) =>
      c.stage === 'candidate' ? { ...c, stage: 'consolidated' } : c,
    );

    const nowIso = new Date(nowMs).toISOString();
    state.summaryByteSize = await this.persistSummary(botId, cleanSummary);
    state.candidateByteSize = await this.persistCandidates(botId, updatedCandidates);
    state.revision += 1;
    state.chatsSinceLastConsolidation = 0;
    state.lastConsolidatedAt = nowIso;
    await this.persistState(botId, state);

    return { consolidated: true, reason, state, summary: cleanSummary };
  }

  // ---- Prompt-Cache-Safe Hidden Recall Note (NEVER mutates System Prompt) ----

  async buildPromptCacheSafeRecall(input: PromptCacheSafeRecallInput): Promise<PromptCacheSafeRecallResult> {
    const key = `${sanitizeBotId(input.botId)}::${input.sessionId}`;
    const lastGen = this.injectedSessionCompactionGen.get(key);
    const state = await this.readState(input.botId);

    const isFirstTurn = lastGen === undefined;
    const isPostCompaction = !isFirstTurn && input.compactionGeneration > lastGen;

    if (!isFirstTurn && !isPostCompaction) {
      return {
        injected: false,
        reason: 'skipped_cache_preserved',
        hiddenNote: null,
        memoryRevision: state.revision,
      };
    }

    const summary = (await this.readSummary(input.botId)).trim();
    const wikiLines = (input.wikiRecallSnippets ?? []).map((s) => s.trim()).filter(Boolean);

    if (!summary && wikiLines.length === 0) {
      // Mark as checked at this compaction generation only when we actually injected something
      // so once memory exists on a later new session or compaction it will be picked up.
      return {
        injected: false,
        reason: 'empty_memory',
        hiddenNote: null,
        memoryRevision: state.revision,
      };
    }

    this.injectedSessionCompactionGen.set(key, input.compactionGeneration);

    const blocks: string[] = [
      `<pipibot_bot_memory bot="${sanitizeBotId(input.botId)}" rev="${state.revision}" mode="${isPostCompaction ? 'post_compaction' : 'session_start'}">`,
    ];
    if (summary) {
      blocks.push(summary);
    }
    if (wikiLines.length > 0) {
      blocks.push('## Related Personal Wiki Context', ...wikiLines.map((line) => `- ${line}`));
    }
    blocks.push('</pipibot_bot_memory>');

    return {
      injected: true,
      reason: isPostCompaction ? 'post_compaction' : 'first_turn',
      hiddenNote: blocks.join('\n'),
      memoryRevision: state.revision,
    };
  }

  resetSessionInjectionTracking(botId: string, sessionId: string): void {
    this.injectedSessionCompactionGen.delete(`${sanitizeBotId(botId)}::${sessionId}`);
  }
}
