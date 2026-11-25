/**
 * @pipibot/core - stream-topic-context.ts
 *
 * PiPiBot — Clean-room MIT implementation.
 * Infinite-Stream Conversation Auto-Topic Segmentation & Bounded Context Engine.
 * - Preserves full visible chat stream non-destructively while strictly bounding LLM context.
 * - Detects topic boundaries via time gap (>= 25 min), explicit cues, new URL domain, or low CJK/Latin overlap.
 * - Compacts older active-topic turns into a rolling capsule and indexes up to 3 recent archived topics.
 */

export interface StreamChatMessage {
  role: 'user' | 'assistant';
  content: string;
  createdAt: string;
  isError?: boolean;
}

export interface StreamTopicSegment {
  id: string;
  title: string;
  summary: string;
  startMessageIndex: number;
  endMessageIndex: number;
  startedAt: string;
  endedAt: string;
  messageCount: number;
}

export type TopicBoundaryReason = 'none' | 'time_gap' | 'explicit_cue' | 'url_topic_shift' | 'semantic_shift';

export interface TopicShiftDecision {
  shouldSplit: boolean;
  reason: TopicBoundaryReason;
  newTopicTitle: string;
}

export interface BoundedStreamContextResult {
  messages: StreamChatMessage[];
  archivedSegmentCount: number;
  foldedActiveMessageCount: number;
  estimatedChars: number;
}

export const DEFAULT_TOPIC_TIME_GAP_MS = 25 * 60 * 1000;
export const DEFAULT_MAX_VERBATIM_ACTIVE = 12;
export const DEFAULT_MAX_PROMPT_CHARS = 10_000;

const EXPLICIT_SWITCH_CUES = [
  '换个话题', '说个别的', '聊点别的', '顺便问', '另外问', '对了帮我', '对了，帮我',
  '新话题', '插一句', '另外一件事', 'by the way', 'new topic', 'change topic', 'switching gears',
];

const FOLLOW_UP_CUES = [
  '为什么', '为啥', '怎么', '原理', '继续', '展开', '详细', '具体', '还有呢', '然后呢',
  '那它', '那他', '这个', '那个', '上面', '刚才', '不对', '改吧', '修一下', '回滚',
  'why', 'how', 'continue', 'more detail', 'fix it', 'go ahead',
];

function extractFirstUrlHost(text: string): string | null {
  const m = text.match(/https?:\/\/[^\s)\]]+/i);
  if (!m?.[0]) return null;
  try {
    const host = new URL(m[0]).hostname.toLowerCase();
    return host.startsWith('www.') ? host.slice(4) : host;
  } catch {
    return null;
  }
}

function deriveTopicTitle(text: string): string {
  const cleaned = text.replace(/\s+/g, ' ').trim();
  if (!cleaned) return '新话题';
  const host = extractFirstUrlHost(cleaned);
  if (host && cleaned.startsWith('http')) return host;
  return cleaned.length > 26 ? `${cleaned.slice(0, 26)}…` : cleaned;
}

function extractSalientTokens(text: string): Set<string> {
  const lower = text.toLowerCase();
  const tokens = new Set<string>();
  const stop = new Set(['the', 'and', 'for', 'with', 'that', 'this', 'from', 'have', 'http', 'https', 'www', 'com']);

  for (const w of lower.split(/[^a-z0-9]+/)) {
    if (w.length >= 3 && !stop.has(w)) tokens.add(w);
  }
  const cjk = Array.from(lower).filter((ch) => {
    const code = ch.codePointAt(0) ?? 0;
    return code >= 0x4e00 && code <= 0x9fff;
  });
  for (let i = 0; i + 1 < cjk.length; i += 1) {
    tokens.add(`${cjk[i]}${cjk[i + 1]}`);
  }
  return tokens;
}

function jaccardOverlap(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 || b.size === 0) return 0;
  let inter = 0;
  for (const t of a) if (b.has(t)) inter += 1;
  const union = a.size + b.size - inter;
  return union > 0 ? inter / union : 0;
}

function compactSnippet(msg: StreamChatMessage, maxLen = 95): string {
  const tag = msg.role === 'user' ? 'U' : 'A';
  const single = msg.content.replace(/\s+/g, ' ').trim();
  return `${tag}: ${single.length > maxLen ? `${single.slice(0, maxLen)}…` : single}`;
}

export function evaluateTopicBoundary(input: {
  existingMessages: readonly StreamChatMessage[];
  activeTopicStartIndex: number;
  incomingUserText: string;
  nowMs?: number;
  timeGapMs?: number;
}): TopicShiftDecision {
  const trimmed = input.incomingUserText.trim();
  const newTopicTitle = deriveTopicTitle(trimmed);
  const start = Math.max(0, Math.min(input.activeTopicStartIndex, input.existingMessages.length));
  const active = input.existingMessages.slice(start);
  if (active.length === 0) {
    return { shouldSplit: false, reason: 'none', newTopicTitle };
  }

  const nowMs = input.nowMs ?? Date.now();
  const gapMs = input.timeGapMs ?? DEFAULT_TOPIC_TIME_GAP_MS;
  const lastTs = Date.parse(active[active.length - 1]!.createdAt);
  if (Number.isFinite(lastTs) && nowMs - lastTs >= gapMs) {
    return { shouldSplit: true, reason: 'time_gap', newTopicTitle };
  }

  const lower = trimmed.toLowerCase();
  if (EXPLICIT_SWITCH_CUES.some((cue) => lower.includes(cue))) {
    return { shouldSplit: true, reason: 'explicit_cue', newTopicTitle };
  }

  const isFollowUp =
    (trimmed.length <= 10 && !extractFirstUrlHost(trimmed)) ||
    FOLLOW_UP_CUES.some((cue) => lower.startsWith(cue) || (trimmed.length <= 36 && lower.includes(cue)));
  if (isFollowUp) {
    return { shouldSplit: false, reason: 'none', newTopicTitle };
  }

  const host = extractFirstUrlHost(trimmed);
  if (host && active.length >= 2) {
    const activeText = active.slice(-6).map((m) => m.content).join(' ').toLowerCase();
    if (!activeText.includes(host)) {
      return { shouldSplit: true, reason: 'url_topic_shift', newTopicTitle };
    }
  }

  if (active.length >= 4 && trimmed.length >= 12) {
    const incomingTokens = extractSalientTokens(trimmed);
    if (incomingTokens.size >= 3) {
      const activeTokens = extractSalientTokens(active.slice(-6).map((m) => m.content).join(' '));
      if (jaccardOverlap(incomingTokens, activeTokens) < 0.05) {
        return { shouldSplit: true, reason: 'semantic_shift', newTopicTitle };
      }
    }
  }

  return { shouldSplit: false, reason: 'none', newTopicTitle };
}

export function buildBoundedStreamContext(input: {
  messages: readonly StreamChatMessage[];
  topicSegments: readonly StreamTopicSegment[];
  activeTopicStartIndex: number;
  maxVerbatimMessages?: number;
  maxChars?: number;
}): BoundedStreamContextResult {
  const maxVerbatim = input.maxVerbatimMessages ?? DEFAULT_MAX_VERBATIM_ACTIVE;
  const maxChars = input.maxChars ?? DEFAULT_MAX_PROMPT_CHARS;
  const start = Math.max(0, Math.min(input.activeTopicStartIndex, input.messages.length));
  const activeAll = input.messages.slice(start);
  const lastIdx = activeAll.length - 1;

  const activeClean = activeAll.filter((m, idx) => idx === lastIdx || (!m.isError && m.content.trim().length > 0));
  let foldedCount = 0;
  let kept = [...activeClean];
  const foldedNotes: string[] = [];

  if (kept.length > maxVerbatim) {
    const cut = kept.length - maxVerbatim;
    const older = kept.slice(0, cut);
    kept = kept.slice(cut);
    foldedCount += older.length;
    for (const m of older.slice(-4)) foldedNotes.push(compactSnippet(m));
  }

  while (kept.length > 2 && kept.reduce((acc, m) => acc + m.content.length, 0) > maxChars) {
    const dropped = kept.shift()!;
    foldedCount += 1;
    foldedNotes.push(compactSnippet(dropped));
  }

  const memoryBlocks: string[] = [];
  const recentSegments = input.topicSegments.slice(-3);
  if (recentSegments.length > 0) {
    const lines = recentSegments.map((s) => `- 《${s.title}》(${s.messageCount}条): ${s.summary.slice(0, 110)}`);
    memoryBlocks.push(`[近期已归档话题摘要]\n${lines.join('\n')}`);
  }
  if (foldedNotes.length > 0) {
    memoryBlocks.push(`[当前话题早期要点（已压缩 ${foldedCount} 条）]\n${foldedNotes.slice(-6).join(' | ').slice(0, 900)}`);
  }

  const out: StreamChatMessage[] = [];
  if (memoryBlocks.length > 0) {
    out.push({
      role: 'assistant',
      content: memoryBlocks.join('\n\n'),
      createdAt: new Date().toISOString(),
    });
  }
  out.push(...kept);

  return {
    messages: out,
    archivedSegmentCount: input.topicSegments.length,
    foldedActiveMessageCount: foldedCount,
    estimatedChars: out.reduce((acc, m) => acc + m.content.length, 0),
  };
}
