/**
 * @pipibot/core - proactive-engine.ts
 *
 * PiPiBot — Clean-room MIT implementation.
 * Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
 * Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.
 *
 * Wave 2 (#03): Native Proactive Anti-Fatigue Guardrails + `Prepare` Pre-Briefing +
 * Nightly `Clue -> Rule` Implicit Self-Learning with Rollback.
 * - First-batch macOS native signal taxonomy (`calendar_eventkit`, `reminders_eventkit`,
 *   `git_workspace`, `device_telemetry`, `chat_pocket_note`)
 * - Anti-fatigue guardrails: quiet hours (22:00-08:00), daily notification cap,
 *   3-minute active-chat silence window, and per-day SHA-256 candidate deduplication
 * - Read-only `Prepare` pre-briefing: enriches upcoming native events with Personal Wiki (#01)
 *   context with zero external side effects
 * - Nightly `Clue -> Rule` self-learning: 14-day clue retention, `seen >= 2` promotion into
 *   specific rules (max 20, non-destructive merge), versioned snapshots with 1-click rollback
 */

import { createHash, randomUUID } from 'node:crypto';

import type {
  ProactiveActionDecision,
  ProactiveFeedbackSignal,
  ProactiveSourceKind,
} from '@pipibot/protocol';
import type { PipiPersonalWikiStore } from './personal-wiki.ts';

// ---------------------------------------------------------------------------
// 1. Public Models & Guardrail Constants
// ---------------------------------------------------------------------------

export const DEFAULT_QUIET_HOURS_START = 22;
export const DEFAULT_QUIET_HOURS_END = 8;
export const DEFAULT_MAX_DAILY_NOTIFICATIONS = 5;
export const DEFAULT_CHAT_SILENCE_SECONDS = 180; // 3 minutes
export const DEFAULT_CLUE_RETENTION_DAYS = 14;
export const DEFAULT_MAX_SPECIFIC_RULES = 20;
export const DEFAULT_MAX_CLUES = 40;
export const DEFAULT_PROMOTION_SEEN_THRESHOLD = 2;

export interface ProactiveGuardrailPolicy {
  quietHoursEnabled: boolean;
  quietHoursStart: number; // 0..23
  quietHoursEnd: number; // 0..23
  maxDailyNotifications: number;
  chatSilenceSeconds: number;
  prepareLeadMinutes: number;
  enabledSources: ProactiveSourceKind[];
}

export interface NativeProactiveSignal {
  id?: string;
  source: ProactiveSourceKind;
  kind: string; // e.g. 'upcoming_event', 'due_reminder', 'dirty_repo', 'memory_pressure', 'follow_up'
  matter: string; // concise topic key used for Clue -> Rule tracking
  title: string;
  content: string;
  dueAtIso?: string;
  workspacePath?: string;
  isUrgent?: boolean;
  supportsPrepare?: boolean;
}

export interface PreparedBriefing {
  id: string;
  signalKey: string;
  source: ProactiveSourceKind;
  matter: string;
  kind: string;
  title: string;
  summary: string;
  bulletPoints: string[];
  relatedWikiPageIds: string[];
  relatedWikiTitles: string[];
  dueAtIso?: string;
  createdAt: string;
  decision: ProactiveActionDecision;
  feedback?: ProactiveFeedbackSignal;
}

export interface ProactiveEvaluationResult {
  signalKey: string;
  decision: ProactiveActionDecision;
  deferredReason?: 'duplicate_today' | 'quiet_hours' | 'daily_cap_reached' | 'chat_active_silence' | 'source_disabled' | 'muted_by_rule';
  matchedRuleId?: string;
  notifiedUser: boolean;
  briefing?: PreparedBriefing;
}

export interface ProactiveClue {
  matter: string;
  kind: string;
  leaning: 'remind_directly' | 'track_for_follow_up' | 'stay_silent';
  seen: number;
  lastSeenDate: string; // YYYY-MM-DD
}

export interface LearnedProactiveRule {
  id: string;
  matter: string;
  kind: string;
  leaning: 'remind_directly' | 'track_for_follow_up' | 'stay_silent';
  text: string;
  enabled: boolean;
  createdAt: string;
}

export interface ProactiveGuidelineSnapshot {
  version: number;
  rules: LearnedProactiveRule[];
  clues: ProactiveClue[];
  changeNote: string;
  createdAt: string;
}

export interface ProactiveFeedbackRecord {
  id: string;
  briefingId: string;
  source: ProactiveSourceKind;
  matter: string;
  kind: string;
  signal: ProactiveFeedbackSignal;
  recordedAt: string; // ISO
}

export interface NightlyDreamResult {
  previousVersion: number;
  newVersion: number;
  promotedRules: LearnedProactiveRule[];
  activeCluesCount: number;
  totalRulesCount: number;
  changeNote: string;
}

// ---------------------------------------------------------------------------
// 2. Helpers
// ---------------------------------------------------------------------------

export function computeDailySignalKey(source: ProactiveSourceKind, content: string, localDateYmd: string): string {
  return createHash('sha256')
    .update(`${source}\u0000${content.trim()}\u0000${localDateYmd}`)
    .digest('hex')
    .slice(0, 32);
}

export function formatLocalYmd(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

export function isHourWithinQuietWindow(hour: number, start: number, end: number): boolean {
  const h = ((hour % 24) + 24) % 24;
  const s = ((start % 24) + 24) % 24;
  const e = ((end % 24) + 24) % 24;
  if (s === e) return false;
  if (s < e) {
    return h >= s && h < e;
  }
  // Overnight wraparound (e.g., 22:00 -> 08:00)
  return h >= s || h < e;
}

function feedbackToLeaning(signal: ProactiveFeedbackSignal): 'remind_directly' | 'track_for_follow_up' | 'stay_silent' {
  switch (signal) {
    case 'acted':
    case 'thanked':
      return 'remind_directly';
    case 'snoozed':
    case 'ignored':
      return 'track_for_follow_up';
    case 'dismissed':
    case 'muted_topic':
      return 'stay_silent';
  }
}

function daysBetweenYmd(earlierYmd: string, laterYmd: string): number {
  const a = Date.parse(`${earlierYmd}T00:00:00Z`);
  const b = Date.parse(`${laterYmd}T00:00:00Z`);
  if (Number.isNaN(a) || Number.isNaN(b)) return 0;
  return Math.floor((b - a) / 86_400_000);
}

// ---------------------------------------------------------------------------
// 3. PipiProactiveEngine
// ---------------------------------------------------------------------------

export class PipiProactiveEngine {
  policy: ProactiveGuardrailPolicy;
  private wikiStore?: PipiPersonalWikiStore;

  private version = 1;
  private rules: LearnedProactiveRule[] = [];
  private clues: ProactiveClue[] = [];
  private history: ProactiveGuidelineSnapshot[] = [];

  private readonly seenKeysByDay = new Map<string, Set<string>>();
  private readonly notificationsByDay = new Map<string, number>();
  private readonly briefings: PreparedBriefing[] = [];
  private readonly feedbackQueue: ProactiveFeedbackRecord[] = [];
  private lastUserChatActivityMs = 0;

  constructor(options: {
    policy?: Partial<ProactiveGuardrailPolicy>;
    wikiStore?: PipiPersonalWikiStore;
  } = {}) {
    this.policy = {
      quietHoursEnabled: options.policy?.quietHoursEnabled ?? true,
      quietHoursStart: options.policy?.quietHoursStart ?? DEFAULT_QUIET_HOURS_START,
      quietHoursEnd: options.policy?.quietHoursEnd ?? DEFAULT_QUIET_HOURS_END,
      maxDailyNotifications: Math.max(0, options.policy?.maxDailyNotifications ?? DEFAULT_MAX_DAILY_NOTIFICATIONS),
      chatSilenceSeconds: Math.max(0, options.policy?.chatSilenceSeconds ?? DEFAULT_CHAT_SILENCE_SECONDS),
      prepareLeadMinutes: Math.max(5, options.policy?.prepareLeadMinutes ?? 120),
      enabledSources: options.policy?.enabledSources ?? [
        'calendar_eventkit',
        'reminders_eventkit',
        'git_workspace',
        'device_telemetry',
        'chat_pocket_note',
      ],
    };
    this.wikiStore = options.wikiStore;
    this.history.push({
      version: 1,
      rules: [],
      clues: [],
      changeNote: 'Initial default proactive guideline',
      createdAt: new Date().toISOString(),
    });
  }

  attachWikiStore(store: PipiPersonalWikiStore): void {
    this.wikiStore = store;
  }

  recordUserChatActivity(nowMs = Date.now()): void {
    this.lastUserChatActivityMs = Math.max(this.lastUserChatActivityMs, nowMs);
  }

  getGuidelineState(): {
    version: number;
    rules: LearnedProactiveRule[];
    clues: ProactiveClue[];
    historyVersions: number[];
  } {
    return {
      version: this.version,
      rules: [...this.rules],
      clues: [...this.clues],
      historyVersions: this.history.map((h) => h.version),
    };
  }

  listBriefings(): PreparedBriefing[] {
    return [...this.briefings];
  }

  // ---- Evaluate Native Signal with Anti-Fatigue Guardrails + Prepare ----

  evaluateSignal(
    signal: NativeProactiveSignal,
    options: { now?: Date; localHourOverride?: number } = {},
  ): ProactiveEvaluationResult {
    const now = options.now ?? new Date();
    const ymd = formatLocalYmd(now);
    const localHour = options.localHourOverride ?? now.getHours();
    const signalKey = computeDailySignalKey(signal.source, `${signal.matter}::${signal.title}::${signal.content}`, ymd);

    if (!this.policy.enabledSources.includes(signal.source)) {
      return { signalKey, decision: 'stay_silent', deferredReason: 'source_disabled', notifiedUser: false };
    }

    // Daily candidate dedup
    const seenSet = this.seenKeysByDay.get(ymd) ?? new Set<string>();
    if (seenSet.has(signalKey)) {
      return { signalKey, decision: 'stay_silent', deferredReason: 'duplicate_today', notifiedUser: false };
    }

    // Check learned rules matching this matter/kind
    const matchedRule = this.findMatchingRule(signal.matter, signal.kind);
    if (matchedRule && matchedRule.leaning === 'stay_silent') {
      seenSet.add(signalKey);
      this.seenKeysByDay.set(ymd, seenSet);
      return {
        signalKey,
        decision: 'stay_silent',
        deferredReason: 'muted_by_rule',
        matchedRuleId: matchedRule.id,
        notifiedUser: false,
      };
    }

    // Check anti-fatigue guardrails before notifying the user
    const inQuietHours =
      this.policy.quietHoursEnabled &&
      isHourWithinQuietWindow(localHour, this.policy.quietHoursStart, this.policy.quietHoursEnd);
    const sentToday = this.notificationsByDay.get(ymd) ?? 0;
    const capReached = sentToday >= this.policy.maxDailyNotifications;
    const chatActiveSilence =
      this.lastUserChatActivityMs > 0 &&
      now.getTime() - this.lastUserChatActivityMs < this.policy.chatSilenceSeconds * 1000;

    // Decide whether this signal merits Prepare pre-briefing (read-only enrichment via Personal Wiki)
    const shouldPrepare = this.shouldPrepareBriefing(signal, now);

    // If user is in quiet hours / cap reached / actively chatting:
    // - Do NOT push a disruptive notification!
    // - For Prepare-worthy items during non-duplicate scans, we still silently prepare a draft briefing
    //   only when not in quiet hours? Actually even better: record deferredReason clearly and keep notifiedUser = false!
    if (inQuietHours && !signal.isUrgent) {
      return { signalKey, decision: 'stay_silent', deferredReason: 'quiet_hours', notifiedUser: false };
    }
    if (capReached) {
      return { signalKey, decision: 'track_for_follow_up', deferredReason: 'daily_cap_reached', notifiedUser: false };
    }
    if (chatActiveSilence && !signal.isUrgent) {
      return { signalKey, decision: 'track_for_follow_up', deferredReason: 'chat_active_silence', notifiedUser: false };
    }

    const decision: ProactiveActionDecision =
      matchedRule?.leaning === 'track_for_follow_up'
        ? 'track_for_follow_up'
        : shouldPrepare
          ? 'prepare_briefing'
          : 'remind_directly';

    const briefing = this.buildPreparedBriefing(signal, signalKey, decision, now);
    this.briefings.unshift(briefing);
    seenSet.add(signalKey);
    this.seenKeysByDay.set(ymd, seenSet);

    const notifiedUser = decision === 'remind_directly' || decision === 'prepare_briefing';
    if (notifiedUser) {
      this.notificationsByDay.set(ymd, sentToday + 1);
    }

    return {
      signalKey,
      decision,
      matchedRuleId: matchedRule?.id,
      notifiedUser,
      briefing,
    };
  }

  private findMatchingRule(matter: string, kind: string): LearnedProactiveRule | undefined {
    const m = matter.trim().toLowerCase();
    const k = kind.trim().toLowerCase();
    return this.rules.find(
      (r) =>
        r.enabled &&
        (r.matter.toLowerCase() === m || m.includes(r.matter.toLowerCase()) || r.matter.toLowerCase().includes(m)) &&
        (!r.kind || r.kind.toLowerCase() === k),
    );
  }

  private shouldPrepareBriefing(signal: NativeProactiveSignal, now: Date): boolean {
    if (signal.supportsPrepare === false) return false;
    if (signal.supportsPrepare === true) return true;
    if (signal.source === 'calendar_eventkit' || signal.source === 'git_workspace') {
      if (!signal.dueAtIso) return true;
      const dueMs = Date.parse(signal.dueAtIso);
      if (Number.isNaN(dueMs)) return true;
      const minsUntil = (dueMs - now.getTime()) / 60_000;
      return minsUntil >= -15 && minsUntil <= this.policy.prepareLeadMinutes;
    }
    return false;
  }

  private buildPreparedBriefing(
    signal: NativeProactiveSignal,
    signalKey: string,
    decision: ProactiveActionDecision,
    now: Date,
  ): PreparedBriefing {
    const relatedWikiPageIds: string[] = [];
    const relatedWikiTitles: string[] = [];
    const bulletPoints: string[] = [signal.content.trim()];

    if (this.wikiStore) {
      const searchRes = this.wikiStore.search({
        query: `${signal.title} ${signal.matter}`,
        alternates: [signal.matter, signal.title],
        limit: 4,
        factLimit: 4,
      });
      for (const summary of searchRes.summaries.slice(0, 3)) {
        relatedWikiPageIds.push(summary.pageId);
        relatedWikiTitles.push(summary.title);
        bulletPoints.push(`Wiki [${summary.category}] ${summary.title}: ${summary.summary}`);
      }
      for (const fact of searchRes.facts.slice(0, 2)) {
        bulletPoints.push(`Fact: ${fact.factText}`);
      }
    }

    const summary =
      decision === 'prepare_briefing'
        ? `Prepared read-only context for "${signal.title}" (${relatedWikiTitles.length} related Wiki notes).`
        : signal.content.trim().slice(0, 180);

    return {
      id: `brf_${Date.now().toString(36)}_${randomUUID().slice(0, 8)}`,
      signalKey,
      source: signal.source,
      matter: signal.matter.trim(),
      kind: signal.kind.trim(),
      title: signal.title.trim(),
      summary,
      bulletPoints,
      relatedWikiPageIds,
      relatedWikiTitles,
      dueAtIso: signal.dueAtIso,
      createdAt: now.toISOString(),
      decision,
    };
  }

  // ---- User Feedback & Nightly `Clue -> Rule` Dreaming + Rollback ----

  recordFeedback(input: {
    briefingId: string;
    signal: ProactiveFeedbackSignal;
    now?: Date;
  }): ProactiveFeedbackRecord | null {
    const briefing = this.briefings.find((b) => b.id === input.briefingId);
    if (!briefing) return null;
    briefing.feedback = input.signal;
    const rec: ProactiveFeedbackRecord = {
      id: `fb_${Date.now().toString(36)}_${randomUUID().slice(0, 8)}`,
      briefingId: briefing.id,
      source: briefing.source,
      matter: briefing.matter,
      kind: briefing.kind,
      signal: input.signal,
      recordedAt: (input.now ?? new Date()).toISOString(),
    };
    this.feedbackQueue.push(rec);
    return rec;
  }

  runNightlyDreaming(options: {
    todayYmd?: string;
    removedRuleIds?: string[];
    extraFeedback?: ProactiveFeedbackRecord[];
  } = {}): NightlyDreamResult {
    const todayYmd = options.todayYmd ?? formatLocalYmd(new Date());
    const previousVersion = this.version;
    const batch = [...this.feedbackQueue, ...(options.extraFeedback ?? [])];
    this.feedbackQueue.length = 0;

    // 1. Prune clues older than 14 days
    const clueMap = new Map<string, ProactiveClue>();
    for (const clue of this.clues) {
      if (daysBetweenYmd(clue.lastSeenDate, todayYmd) <= DEFAULT_CLUE_RETENTION_DAYS) {
        clueMap.set(`${clue.matter.toLowerCase()}\u0000${clue.kind.toLowerCase()}`, { ...clue });
      }
    }

    // 2. Fold new feedback signals into clues
    for (const fb of batch) {
      const key = `${fb.matter.toLowerCase()}\u0000${fb.kind.toLowerCase()}`;
      const leaning = feedbackToLeaning(fb.signal);
      const existing = clueMap.get(key);
      if (existing && existing.leaning === leaning) {
        existing.seen += 1;
        existing.lastSeenDate = todayYmd;
      } else if (existing) {
        // User changed preference: reset seen to 1 with new leaning
        clueMap.set(key, {
          matter: fb.matter,
          kind: fb.kind,
          leaning,
          seen: 1,
          lastSeenDate: todayYmd,
        });
      } else {
        clueMap.set(key, {
          matter: fb.matter,
          kind: fb.kind,
          leaning,
          seen: 1,
          lastSeenDate: todayYmd,
        });
      }
    }

    // 3. Remove ONLY explicitly named rules (non-destructive merge)
    const removedSet = new Set(options.removedRuleIds ?? []);
    const nextRules = this.rules.filter((r) => !removedSet.has(r.id)).map((r) => ({ ...r }));
    const promotedRules: LearnedProactiveRule[] = [];

    // 4. Promote clues with seen >= 2 within 14-day window into rules (cap = 20)
    const remainingClues: ProactiveClue[] = [];
    for (const clue of clueMap.values()) {
      if (clue.seen >= DEFAULT_PROMOTION_SEEN_THRESHOLD) {
        const existingIdx = nextRules.findIndex(
          (r) => r.matter.toLowerCase() === clue.matter.toLowerCase() && r.kind.toLowerCase() === clue.kind.toLowerCase(),
        );
        const ruleText = this.formatRuleText(clue);
        const promoted: LearnedProactiveRule = {
          id: existingIdx >= 0 ? nextRules[existingIdx]!.id : `prule_${Date.now().toString(36)}_${randomUUID().slice(0, 6)}`,
          matter: clue.matter,
          kind: clue.kind,
          leaning: clue.leaning,
          text: ruleText,
          enabled: true,
          createdAt: new Date().toISOString(),
        };
        if (existingIdx >= 0) {
          nextRules[existingIdx] = promoted;
        } else if (nextRules.length < DEFAULT_MAX_SPECIFIC_RULES) {
          nextRules.unshift(promoted);
        }
        promotedRules.push(promoted);
      } else {
        remainingClues.push(clue);
      }
    }

    this.rules = nextRules.slice(0, DEFAULT_MAX_SPECIFIC_RULES);
    this.clues = remainingClues
      .sort((a, b) => b.lastSeenDate.localeCompare(a.lastSeenDate))
      .slice(0, DEFAULT_MAX_CLUES);
    this.version += 1;

    const changeNote =
      promotedRules.length > 0
        ? `Promoted ${promotedRules.length} rule(s) from repeated clues (${todayYmd}).`
        : `Updated ${this.clues.length} active clue(s) (${todayYmd}).`;

    this.history.push({
      version: this.version,
      rules: this.rules.map((r) => ({ ...r })),
      clues: this.clues.map((c) => ({ ...c })),
      changeNote,
      createdAt: new Date().toISOString(),
    });

    return {
      previousVersion,
      newVersion: this.version,
      promotedRules,
      activeCluesCount: this.clues.length,
      totalRulesCount: this.rules.length,
      changeNote,
    };
  }

  rollbackGuideline(targetVersion: number): boolean {
    const snap = this.history.find((h) => h.version === targetVersion);
    if (!snap) return false;
    this.rules = snap.rules.map((r) => ({ ...r }));
    this.clues = snap.clues.map((c) => ({ ...c }));
    this.version = snap.version;
    return true;
  }

  private formatRuleText(clue: ProactiveClue): string {
    switch (clue.leaning) {
      case 'stay_silent':
        return `Stay silent for "${clue.matter}" (${clue.kind}) unless explicitly requested.`;
      case 'track_for_follow_up':
        return `Track "${clue.matter}" (${clue.kind}) quietly for later follow-up instead of interrupting.`;
      case 'remind_directly':
        return `Prioritize reminding & preparing context for "${clue.matter}" (${clue.kind}).`;
    }
  }
}
