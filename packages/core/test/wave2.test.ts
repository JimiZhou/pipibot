/**
 * @pipibot/core - test/wave2.test.ts
 *
 * Deterministic offline verification suite for Wave 2:
 * - #01 Personal Entity Wiki + SQLite WAL + Dual-Channel Zero-Embedding Search + Soft Time-Window RRF
 * - #02 Per-Bot Isolated Experiential Memory + 5-run / 6h-idle / Compaction Cadence + Prompt-Cache-Safe Recall
 * - #03 Native Proactive Anti-Fatigue Guardrails + Prepare Pre-Briefing + Nightly Clue -> Rule Dreaming & Rollback
 */

import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { PipiBotMemoryEngine } from '../src/bot-memory.ts';
import { PipiPersonalWikiStore, expandTokensWithCjkBigrams } from '../src/personal-wiki.ts';
import { PipiProactiveEngine } from '../src/proactive-engine.ts';

// ---------------------------------------------------------------------------
// #01 Personal Entity Wiki + Dual-Channel Zero-Embedding Search + SQLite WAL
// ---------------------------------------------------------------------------

test('#01 Personal Wiki: SQLite WAL, CJK bigram dual-channel zero-embedding search & Markdown projection', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'pipibot-wiki-'));
  const dbPath = join(dir, 'wiki.sqlite');
  const wiki = new PipiPersonalWikiStore({ dbPath, markdownRootDir: dir });

  try {
    assert.equal(wiki.getJournalMode(), 'wal');

    const tokens = expandTokensWithCjkBigrams('周末露营装备清单 SwiftUI');
    assert.ok(tokens.includes('露营'));
    assert.ok(tokens.includes('装备'));
    assert.ok(tokens.includes('swiftui'));

    const page1 = await wiki.upsertPage({
      category: 'life',
      title: '秋季川西露营计划',
      aliases: ['川西自驾', '露营清单'],
      summary: '整理川西高原露营所需的防寒装备、电源方案与路线笔记',
      bodyMarkdown: '## 装备\n带上 -10℃ 羽绒睡袋、户外电源与便携咖啡壶。\n注意不要泄漏 sk-proj-1234567890abcdefghijklmno。',
      eventDate: '2026-10-18',
      facts: [
        { factText: '川西露营优先携带 -10℃ 睡袋与便携咖啡壶', eventDate: '2026-10-18', confidence: 0.92 },
      ],
    });

    await wiki.upsertPage({
      category: 'life',
      title: '春季杭州露营记录',
      aliases: ['春游露营'],
      summary: '杭州周边露营营地与便携咖啡壶体验总结',
      bodyMarkdown: '## 营地\n杭州郊外草坪营地很适合周末放松，带便携咖啡壶即可。',
      eventDate: '2026-04-12',
      facts: [
        { factText: '杭州露营草坪营地适合轻装便携咖啡壶', eventDate: '2026-04-12', confidence: 0.9 },
      ],
    });

    await wiki.upsertPage({
      category: 'repos',
      title: 'PiPiBot 桌面端架构',
      aliases: ['pipibot', 'Swift6 Host'],
      summary: '基于 Swift 6 与本地 SQLite WAL 的个人智能体工作台',
      bodyMarkdown: '## 架构\n支持 7 级模型调度与双层安全护栏。',
      eventDate: '2026-11-20',
    });

    // Verify Markdown projection scrubbed secret and wrote YAML frontmatter
    const projectedPath = join(dir, 'knowledge', 'life', `${page1.slug}.md`);
    const mdText = await readFile(projectedPath, 'utf8');
    assert.ok(mdText.includes('pipibot_wiki_version: "1.0"'));
    assert.ok(mdText.includes('category: life'));
    assert.ok(!mdText.includes('sk-proj-1234567890abcdefghijklmno'));
    assert.ok(mdText.includes('[REDACTED:OPENAI_OR_SK_KEY:'));

    // Dual-channel zero-embedding search with >6 alternates (clamped to 6) + soft time-window RRF
    const res = wiki.search({
      query: '露营咖啡壶',
      alternates: ['川西自驾', '睡袋', '户外电源', '营地', '高原', '防寒', '第七个会被截断'],
      startDate: '2026-10-01',
      endDate: '2026-10-31',
      scope: 'all',
    });

    assert.equal(res.usedVectorChannel, false);
    assert.equal(res.effectiveQueries.length, 7); // 1 primary + max 6 alternates
    assert.ok(res.chunks.length >= 2, 'soft window should keep out-of-window relevant hit too');
    assert.equal(res.chunks[0]?.pageId, page1.id, 'in-window October camp page should rank #1 via soft time-window RRF');
    assert.equal(res.chunks[0]?.inTimeWindow, true);
    assert.ok(res.facts.length >= 1, 'independent facts channel returns matching atomic facts');
    assert.equal(res.facts[0]?.pageId, page1.id);
    assert.ok(res.summaries.length >= 1, 'summaries channel returns entity pages');

    // Scope = summaries must omit chunks & facts
    const summaryOnly = wiki.search({ query: 'Swift6 Host', scope: 'summaries' });
    assert.equal(summaryOnly.chunks.length, 0);
    assert.equal(summaryOnly.facts.length, 0);
    assert.equal(summaryOnly.summaries[0]?.category, 'repos');
  } finally {
    wiki.close();
    await rm(dir, { recursive: true, force: true });
  }
});

// ---------------------------------------------------------------------------
// #02 Per-Bot Isolated Memory + Cadence + Prompt-Cache-Safe Recall
// ---------------------------------------------------------------------------

test('#02 Per-Bot Memory: strict isolation, 5-run extraction, 6h idle / compaction consolidation & Prompt-Cache safety', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'pipibot-botmem-'));
  const engine = new PipiBotMemoryEngine({
    rootDir: dir,
    cadence: {
      extractEveryRuns: 5,
      idleConsolidationHours: 6,
      maxUnconsolidatedBytes: 64 * 1024,
      maxChatsBeforeConsolidation: 30,
    },
  });

  try {
    const t0 = Date.parse('2026-11-20T09:00:00Z');

    // First 4 runs for bot_coder should NOT trigger extraction yet
    for (let i = 1; i <= 4; i += 1) {
      const r = await engine.recordSuccessfulRun({
        botId: 'bot_coder',
        sessionId: 'sess_1',
        userPrompt: `Review Swift module #${i}`,
        assistantReply: `Always verify Sendable conformance and avoid raw hex colors in SwiftUI view #${i}.`,
        nowMs: t0 + i * 60_000,
      });
      assert.equal(r.extractedCandidates.length, 0);
      assert.equal(r.consolidated, false);
    }

    // 5th run triggers extraction!
    const run5 = await engine.recordSuccessfulRun({
      botId: 'bot_coder',
      sessionId: 'sess_1',
      userPrompt: 'Review Swift module #5',
      assistantReply: 'Prefer deterministic offline unit tests with injected test executors.',
      nowMs: t0 + 5 * 60_000,
    });
    assert.ok(run5.extractedCandidates.length >= 1, '5th successful run must extract candidate lessons');
    assert.equal(run5.state.successfulRunsSinceLastExtract, 0);
    assert.equal(run5.consolidated, false, 'should wait for idle 6h or compaction/threshold');

    // 3 hours idle -> NOT yet due
    const check3h = await engine.consolidateIfDue('bot_coder', { nowMs: t0 + 3 * 3_600_000 });
    assert.equal(check3h.consolidated, false);

    // 7 hours idle -> consolidates into bot_coder/memory/summary.md!
    const check7h = await engine.consolidateIfDue('bot_coder', { nowMs: t0 + 7 * 3_600_000 });
    assert.equal(check7h.consolidated, true);
    assert.equal(check7h.reason, 'idle_timeout');
    assert.ok(check7h.summary.includes('Sendable conformance'));
    assert.equal(check7h.state.revision, 1);

    // Strict isolation: bot_writer must have empty summary & never see bot_coder's lessons
    const writerSummary = await engine.readSummary('bot_writer');
    assert.equal(writerSummary, '');
    const writerRecall = await engine.buildPromptCacheSafeRecall({
      botId: 'bot_writer',
      sessionId: 'sess_writer_1',
      compactionGeneration: 0,
    });
    assert.equal(writerRecall.injected, false);
    assert.equal(writerRecall.reason, 'empty_memory');

    // Prompt-Cache-Safe recall on bot_coder:
    // Turn 1 of new session -> injects hidden note
    const turn1 = await engine.buildPromptCacheSafeRecall({
      botId: 'bot_coder',
      sessionId: 'sess_2',
      compactionGeneration: 0,
    });
    assert.equal(turn1.injected, true);
    assert.equal(turn1.reason, 'first_turn');
    assert.ok(turn1.hiddenNote?.includes('<pipibot_bot_memory'));
    assert.ok(turn1.hiddenNote?.includes('Sendable conformance'));

    // Turn 2 of SAME session (same compactionGeneration) -> SKIPPED to preserve Prompt Cache!
    const turn2 = await engine.buildPromptCacheSafeRecall({
      botId: 'bot_coder',
      sessionId: 'sess_2',
      compactionGeneration: 0,
    });
    assert.equal(turn2.injected, false);
    assert.equal(turn2.reason, 'skipped_cache_preserved');
    assert.equal(turn2.hiddenNote, null);

    // Explicit compaction triggers consolidation of buffered run & increments compactionGeneration -> re-injects!
    await engine.recordSuccessfulRun({
      botId: 'bot_coder',
      sessionId: 'sess_2',
      userPrompt: 'Check macOS packaging',
      assistantReply: 'Always keep iOS Simulator build green alongside macOS.',
      nowMs: t0 + 8 * 3_600_000,
    });
    const compCons = await engine.consolidateIfDue('bot_coder', {
      nowMs: t0 + 8 * 3_600_000 + 1000,
      trigger: 'compaction',
    });
    assert.equal(compCons.consolidated, true);
    assert.equal(compCons.reason, 'compaction');
    assert.ok(compCons.summary.includes('iOS Simulator'));

    const postCompactTurn = await engine.buildPromptCacheSafeRecall({
      botId: 'bot_coder',
      sessionId: 'sess_2',
      compactionGeneration: 1,
    });
    assert.equal(postCompactTurn.injected, true);
    assert.equal(postCompactTurn.reason, 'post_compaction');
    assert.ok(postCompactTurn.hiddenNote?.includes('iOS Simulator'));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

// ---------------------------------------------------------------------------
// #03 Native Proactive Anti-Fatigue + Prepare + Clue -> Rule Dreaming & Rollback
// ---------------------------------------------------------------------------

test('#03 Proactive Engine: quiet hours, daily cap, 3m chat silence, Prepare + Wiki enrichment & Clue -> Rule rollback', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'pipibot-proactive-'));
  const wiki = new PipiPersonalWikiStore({ dbPath: join(dir, 'wiki.sqlite') });

  try {
    await wiki.upsertPage({
      category: 'people',
      title: '林远',
      aliases: ['Lin Yuan'],
      summary: '资深 SwiftUI 动效设计师，最近在合作打磨桌面端组件规范',
      bodyMarkdown: '## 合作背景\n偏好克制的无边框卡片与弹簧动效。',
      eventDate: '2026-11-19',
    });

    const engine = new PipiProactiveEngine({
      wikiStore: wiki,
      policy: {
        quietHoursEnabled: true,
        quietHoursStart: 22,
        quietHoursEnd: 8,
        maxDailyNotifications: 2,
        chatSilenceSeconds: 180,
        prepareLeadMinutes: 120,
      },
    });

    const daytime = new Date('2026-11-20T10:30:00');
    const quietNight = new Date('2026-11-20T23:15:00');

    // 1. Quiet hours (23:15) blocks non-urgent proactive nudge
    const quietRes = engine.evaluateSignal(
      {
        source: 'calendar_eventkit',
        kind: 'upcoming_event',
        matter: '林远设计评审',
        title: '和林远对齐组件动效',
        content: '11:30 讨论 SwiftUI 动效与设计令牌',
        dueAtIso: '2026-11-20T11:30:00',
      },
      { now: quietNight, localHourOverride: 23 },
    );
    assert.equal(quietRes.notifiedUser, false);
    assert.equal(quietRes.deferredReason, 'quiet_hours');

    // 2. Active chat within 3 minutes defers nudge (chat_active_silence)
    engine.recordUserChatActivity(daytime.getTime() - 60_000); // 1 min ago
    const silenceRes = engine.evaluateSignal(
      {
        source: 'calendar_eventkit',
        kind: 'upcoming_event',
        matter: '林远设计评审',
        title: '和林远对齐组件动效',
        content: '11:30 讨论 SwiftUI 动效与设计令牌',
        dueAtIso: '2026-11-20T11:30:00',
      },
      { now: daytime, localHourOverride: 10 },
    );
    assert.equal(silenceRes.notifiedUser, false);
    assert.equal(silenceRes.deferredReason, 'chat_active_silence');

    // 3. After 3+ minutes of chat silence -> triggers Prepare briefing enriched with Personal Wiki!
    const afterSilence = new Date(daytime.getTime() + 240_000);
    const prepRes = engine.evaluateSignal(
      {
        source: 'calendar_eventkit',
        kind: 'upcoming_event',
        matter: '林远设计评审',
        title: '和林远对齐组件动效',
        content: '讨论 SwiftUI 动效与设计令牌',
        dueAtIso: new Date(afterSilence.getTime() + 45 * 60_000).toISOString(),
      },
      { now: afterSilence, localHourOverride: 10 },
    );
    assert.equal(prepRes.decision, 'prepare_briefing');
    assert.equal(prepRes.notifiedUser, true);
    assert.ok(prepRes.briefing);
    assert.ok(prepRes.briefing.relatedWikiTitles.includes('林远'), 'Prepare briefing must pull related Personal Wiki context');

    // 4. Same signal on the same day is deduplicated
    const dupRes = engine.evaluateSignal(
      {
        source: 'calendar_eventkit',
        kind: 'upcoming_event',
        matter: '林远设计评审',
        title: '和林远对齐组件动效',
        content: '讨论 SwiftUI 动效与设计令牌',
      },
      { now: afterSilence, localHourOverride: 10 },
    );
    assert.equal(dupRes.deferredReason, 'duplicate_today');

    // 5. Second distinct notification succeeds, third hits daily cap (maxDailyNotifications = 2)
    const gitRes = engine.evaluateSignal(
      {
        source: 'git_workspace',
        kind: 'dirty_repo',
        matter: '周报汇总提醒',
        title: 'pipibot 仓库有未推送提交',
        content: 'main 分支 ahead 2 commits',
      },
      { now: afterSilence, localHourOverride: 10 },
    );
    assert.equal(gitRes.notifiedUser, true);
    assert.ok(gitRes.briefing);

    const capRes = engine.evaluateSignal(
      {
        source: 'device_telemetry',
        kind: 'memory_pressure',
        matter: '内存占用偏高',
        title: '内存占用 88%',
        content: '当前活跃进程较多',
      },
      { now: afterSilence, localHourOverride: 10 },
    );
    assert.equal(capRes.notifiedUser, false);
    assert.equal(capRes.deferredReason, 'daily_cap_reached');

    // 6. Clue -> Rule Nightly Dreaming (seen = 1 stays clue; seen >= 2 promotes to rule; rollback works!)
    engine.recordFeedback({ briefingId: gitRes.briefing.id, signal: 'dismissed', now: afterSilence });
    const dream1 = engine.runNightlyDreaming({ todayYmd: '2026-11-20' });
    assert.equal(dream1.promotedRules.length, 0, 'first dismissal records clue only (seen = 1)');
    assert.equal(dream1.activeCluesCount, 1);

    // Day 2: second dismissal of same (matter, kind) promotes to permanent stay_silent rule!
    const day2 = new Date('2026-11-21T10:30:00');
    const gitResDay2 = engine.evaluateSignal(
      {
        source: 'git_workspace',
        kind: 'dirty_repo',
        matter: '周报汇总提醒',
        title: 'pipibot 仓库有未推送提交',
        content: 'main 分支 ahead 3 commits',
      },
      { now: day2, localHourOverride: 10 },
    );
    assert.ok(gitResDay2.briefing);
    engine.recordFeedback({ briefingId: gitResDay2.briefing.id, signal: 'muted_topic', now: day2 });
    const dream2 = engine.runNightlyDreaming({ todayYmd: '2026-11-21' });
    assert.equal(dream2.promotedRules.length, 1, 'seen >= 2 within 14 days must promote to rule');
    assert.equal(dream2.promotedRules[0]?.leaning, 'stay_silent');

    // Day 3: learned stay_silent rule suppresses future signal automatically!
    const day3 = new Date('2026-11-22T10:30:00');
    const suppressed = engine.evaluateSignal(
      {
        source: 'git_workspace',
        kind: 'dirty_repo',
        matter: '周报汇总提醒',
        title: 'pipibot 仓库有未推送提交',
        content: 'main 分支 ahead 4 commits',
      },
      { now: day3, localHourOverride: 10 },
    );
    assert.equal(suppressed.decision, 'stay_silent');
    assert.equal(suppressed.deferredReason, 'muted_by_rule');

    // Rollback to version before promotion (v2) removes the promoted rule cleanly!
    const rolledBack = engine.rollbackGuideline(dream1.newVersion);
    assert.equal(rolledBack, true);
    assert.equal(engine.getGuidelineState().rules.length, 0);
  } finally {
    wiki.close();
    await rm(dir, { recursive: true, force: true });
  }
});
