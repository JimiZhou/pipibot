/**
 * @pipibot/core - test/wave3.test.ts
 *
 * Deterministic offline verification suite for Wave 3:
 * - #05 Meta / AlterEgo autonomous background delegation, isolated playground + same-session read-only sharing, steer, cancel & resume
 * - #06 Structured `team.md` parser/validator, DAG cycle checking, all 5 collaboration topologies & Dynamic Bot Invite/Create proposals
 * - #11 Unified `pipibot` CLI (single-source --help/--schema/--permissions + operation-id idempotency),
 *       versioned read-only SHA-256 builtin skill packs, daily Pocket Notes (5m silence reconciliation) & editable docs
 */

import assert from 'node:assert/strict';
import { chmod, mkdtemp, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import {
  PipiAlterEgoCoordinator,
  extractDelegationDirective,
  shouldAutoDelegatePrompt,
} from '../src/alter-ego.ts';
import {
  BUILTIN_SKILL_PACKS,
  projectBuiltinSkillsReadOnly,
  verifyProjectedSkillsIntegrity,
} from '../src/builtin-skills.ts';
import { PipiModelScheduler } from '../src/model-scheduler.ts';
import { PipiOperationLedger } from '../src/permission-guardrail.ts';
import { PipiPersonalWikiStore } from '../src/personal-wiki.ts';
import { PIPIBOT_CLI_COMMANDS, runPipiBotCli } from '../src/pipibot-cli.ts';
import { PipiPocketNotesEngine } from '../src/pocket-notes.ts';
import {
  buildDynamicBotProposals,
  executeTeamProtocol,
  parseAndValidateTeamMd,
  renderTeamMdTemplate,
} from '../src/team-protocol.ts';

// ---------------------------------------------------------------------------
// #05 Meta / AlterEgo Background Delegation
// ---------------------------------------------------------------------------

test('#05 AlterEgo: autonomous detection, isolated playground + same-session read-only sharing, steer, cancel & resume', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'pipibot-w3-alterego-'));
  try {
    assert.equal(shouldAutoDelegatePrompt('请帮我做一次深度调研并整理完整竞品分析报告').delegate, true);
    assert.equal(shouldAutoDelegatePrompt('hi').delegate, false);

    const parsedDir = extractDelegationDirective(
      '好的，我先派分身后台处理：\n<pipibot_delegate>{"title":"SQLite Benchmark","goal":"Compare WAL vs journal mode"}</pipibot_delegate>',
    );
    assert.equal(parsedDir?.title, 'SQLite Benchmark');

    const scheduler = new PipiModelScheduler({ defaultPool: { initialLimit: 2, maxLimit: 2 } });
    const coord = new PipiAlterEgoCoordinator({ rootDir: dir, scheduler });

    // Task A in session_1 writes an artifact
    const taskA = await coord.spawnTask({
      sessionId: 'session_1',
      botId: 'bot_coder',
      title: 'Research Notes',
      goal: 'Gather benchmark findings',
      runner: async (ctx) => {
        ctx.reportStep('Writing findings.md', 'running');
        await ctx.writeArtifact('findings.md', '# Findings\nWAL mode is 4x faster under concurrent reads.');
        ctx.reportStep('Completed findings', 'succeeded');
        return { summary: 'Wrote findings.md' };
      },
    });
    await coord.waitForTask(taskA.id);
    assert.equal(taskA.status, 'completed');
    assert.deepEqual(taskA.artifacts, ['findings.md']);

    // Task B in SAME session_1 can read Task A's playground read-only, while rejecting path traversal
    let sharedContent = '';
    const taskB = await coord.spawnTask({
      sessionId: 'session_1',
      botId: 'bot_writer',
      title: 'Draft Summary',
      goal: 'Summarize findings from sibling AlterEgo',
      runner: async (ctx) => {
        sharedContent = await ctx.readSessionArtifact(taskA.id, 'findings.md');
        await assert.rejects(() => ctx.writeArtifact('../escape.txt', 'nope'), /Path traversal/);
        await ctx.writeArtifact('summary.md', `Based on sibling: ${sharedContent}`);
        return { summary: 'Drafted summary.md' };
      },
    });
    await coord.waitForTask(taskB.id);
    assert.equal(taskB.status, 'completed');
    assert.ok(sharedContent.includes('WAL mode is 4x faster'));

    // Task C in DIFFERENT session_2 is strictly blocked from reading session_1 artifacts
    const taskC = await coord.spawnTask({
      sessionId: 'session_2',
      botId: 'bot_coder',
      title: 'Other Session Task',
      goal: 'Verify cross-session isolation',
      runner: async (ctx) => {
        await assert.rejects(() => ctx.readSessionArtifact(taskA.id, 'findings.md'), /cross_session_denied/);
        return { summary: 'Isolation verified' };
      },
    });
    await coord.waitForTask(taskC.id);
    assert.equal(taskC.status, 'completed');

    // Cancel mid-flight, steer, and resume preserving playground!
    let markCheckpointWritten!: () => void;
    const checkpointWritten = new Promise<void>((res) => {
      markCheckpointWritten = res;
    });
    let releaseBlocker!: () => void;
    const blocker = new Promise<void>((res) => {
      releaseBlocker = res;
    });
    const taskD = await coord.spawnTask({
      sessionId: 'session_1',
      botId: 'bot_coder',
      title: 'Cancellable Task',
      goal: 'Long work',
      runner: async (ctx) => {
        await ctx.writeArtifact('checkpoint.txt', 'step1');
        markCheckpointWritten();
        if (ctx.signal.aborted) return { summary: 'Cancelled early' };
        ctx.signal.addEventListener('abort', () => releaseBlocker(), { once: true });
        await blocker;
        return { summary: 'Should have been cancelled' };
      },
    });
    await checkpointWritten;
    const cancelled = coord.cancelTask(taskD.id);
    assert.equal(cancelled, true);
    await coord.waitForTask(taskD.id);
    assert.equal(taskD.status, 'cancelled');

    // Resume with mid-flight steer instruction
    let capturedSteers: string[] = [];
    await coord.resumeTask(taskD.id, {
      additionalInstruction: 'Focus on Swift 6 concurrency edge cases',
      runner: async (ctx) => {
        capturedSteers = ctx.consumeSteerInstructions();
        const prev = await ctx.readSessionArtifact(taskD.id, 'checkpoint.txt');
        await ctx.writeArtifact('final.md', `${prev} + ${capturedSteers.join('; ')}`);
        return { summary: 'Resumed and completed' };
      },
    });
    await coord.waitForTask(taskD.id);
    assert.equal(taskD.status, 'completed');
    assert.deepEqual(capturedSteers, ['Focus on Swift 6 concurrency edge cases']);
    assert.ok(taskD.artifacts.includes('checkpoint.txt'));
    assert.ok(taskD.artifacts.includes('final.md'));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

// ---------------------------------------------------------------------------
// #06 Structured `team.md` All 5 Topologies + DAG Validation + Dynamic Bot Proposals
// ---------------------------------------------------------------------------

test('#06 team.md: parser/DAG cycle rejection, all 5 topologies execution & Dynamic Bot Invite/Create proposals', async () => {
  // 1. Cycle detection on fan-out-and-synthesize MUST fail
  const cyclicMd = `---
collaborate_pattern: fan-out-and-synthesize
---

# Task Goal
Ship release safely

# Orchestrator
## Lead
- Actor ID: bot_lead
- Role: Coordinator
- Report to: none
- Receive from: Alice, Bob

# Team Members
## Alice
- Actor ID: bot_alice
- Role: Coder
- Receive from: Bob
- Report to: Lead

## Bob
- Actor ID: bot_bob
- Role: Tester
- Receive from: Alice
- Report to: Lead
`;
  const cyclicValidation = parseAndValidateTeamMd(cyclicMd, {
    roomMemberActorIds: ['bot_lead', 'bot_alice', 'bot_bob'],
  });
  assert.equal(cyclicValidation.valid, false);
  assert.ok(cyclicValidation.issues.some((i) => i.code === 'team_md_cycle_detected'));

  // 2. Dynamic Bot Invite & Create Proposals for non-room members
  const dynamicMd = renderTeamMdTemplate({
    pattern: 'fan-out-and-synthesize',
    taskGoal: 'Audit security and write docs',
    orchestrator: { name: 'PiPi Lead', actorId: 'bot_pipi' },
    members: [
      { name: 'Coder', actorId: 'bot_coder', role: 'Swift 6 Engineer' },
      { name: 'Security Auditor', actorId: 'bot_sec_new', role: 'Threat modeling & static audit' },
    ],
  });
  const dynCheck = parseAndValidateTeamMd(dynamicMd, { roomMemberActorIds: ['bot_pipi'] });
  assert.equal(dynCheck.valid, false);
  assert.deepEqual(dynCheck.missingMemberActorIds, ['bot_coder', 'bot_sec_new']);
  assert.ok(dynCheck.document);

  const proposals = buildDynamicBotProposals({
    groupId: 'grp_1',
    document: dynCheck.document,
    groupMemberIds: ['bot_pipi'],
    allKnownBots: [
      { id: 'bot_pipi', name: 'PiPi Lead', role: 'Lead' },
      { id: 'bot_coder', name: 'Coder', role: 'Swift 6 Engineer' },
    ],
  });
  assert.equal(proposals.length, 2);
  assert.equal(proposals[0]?.action, 'invite_existing');
  assert.equal(proposals[0]?.existingBotId, 'bot_coder');
  assert.equal(proposals[1]?.action, 'create_and_invite');
  assert.equal(proposals[1]?.requestedActorId, 'bot_sec_new');

  // 3. Execute ALL 5 patterns deterministically
  const baseOrch = { name: 'Lead', actorId: 'bot_lead' };
  const baseMembers = [
    { name: 'Coder', actorId: 'bot_coder', role: 'Coding' },
    { name: 'Critic', actorId: 'bot_critic', role: 'Verification' },
  ];

  // (a) classify-and-act
  const p1 = parseAndValidateTeamMd(
    renderTeamMdTemplate({ pattern: 'classify-and-act', taskGoal: 'Route task', orchestrator: baseOrch, members: baseMembers }),
  ).document!;
  const r1 = await executeTeamProtocol(p1, 'Fix memory leak', async (req) =>
    req.phase === 'classify'
      ? { output: 'Routing to Coder', selectedActorId: 'bot_coder' }
      : { output: `Solved by ${req.actorId}` },
  );
  assert.equal(r1.winnerActorId, 'bot_coder');
  assert.equal(r1.finalOutput, 'Solved by bot_coder');

  // (b) fan-out-and-synthesize
  const p2 = parseAndValidateTeamMd(
    renderTeamMdTemplate({ pattern: 'fan-out-and-synthesize', taskGoal: 'Parallel research', orchestrator: baseOrch, members: baseMembers }),
  ).document!;
  const r2 = await executeTeamProtocol(p2, 'Compare options', async (req) => ({
    output: req.phase === 'synthesize' ? `Merged ${req.upstreamOutputs.length} inputs` : `Output from ${req.actorId}`,
  }));
  assert.equal(r2.finalOutput, 'Merged 2 inputs');

  // (c) adversarial-verification (reject round 1, approve round 2)
  const p3 = parseAndValidateTeamMd(
    renderTeamMdTemplate({
      pattern: 'adversarial-verification',
      taskGoal: 'Zero bugs',
      orchestrator: baseOrch,
      members: baseMembers,
      maxRounds: 3,
    }),
  ).document!;
  const r3 = await executeTeamProtocol(p3, 'Write parser', async (req) => {
    if (req.phase === 'verify') {
      return req.round === 1
        ? { output: 'Missing edge case handling', approved: false }
        : { output: 'All edge cases verified', approved: true };
    }
    return { output: `Draft v${req.round}` };
  });
  assert.equal(r3.roundsExecuted, 2);
  assert.equal(r3.verifiedApproved, true);
  assert.equal(r3.finalOutput, 'Draft v2');

  // (d) tournament
  const p4 = parseAndValidateTeamMd(
    renderTeamMdTemplate({ pattern: 'tournament', taskGoal: 'Pick best architecture', orchestrator: baseOrch, members: baseMembers }),
  ).document!;
  const r4 = await executeTeamProtocol(p4, 'Design cache', async (req) =>
    req.phase === 'judge'
      ? { output: 'Critic won on simplicity', selectedActorId: 'bot_critic' }
      : { output: `Proposal by ${req.actorId}` },
  );
  assert.equal(r4.winnerActorId, 'bot_critic');

  // (e) loop-until-done
  const p5 = parseAndValidateTeamMd(
    renderTeamMdTemplate({
      pattern: 'loop-until-done',
      taskGoal: 'Pass all tests',
      orchestrator: baseOrch,
      members: [baseMembers[0]!],
      maxRounds: 4,
    }),
  ).document!;
  const r5 = await executeTeamProtocol(p5, 'Fix tests', async (req) => ({
    output: `Iteration ${req.round}`,
    done: req.round >= 3,
  }));
  assert.equal(r5.roundsExecuted, 3);
  assert.equal(r5.completed, true);
});

// ---------------------------------------------------------------------------
// #11 Unified `pipibot` CLI + Builtin Versioned Skills + Pocket Notes & Docs
// ---------------------------------------------------------------------------

test('#11 CLI, Builtin Skills (SHA-256 read-only projection) & Pocket Notes (5m silence + editable docs)', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'pipibot-w3-cli-'));
  try {
    // 1. Builtin versioned read-only skills projection + tamper detection + auto-repair
    assert.equal(BUILTIN_SKILL_PACKS.length, 8);
    const receipts = await projectBuiltinSkillsReadOnly(dir);
    assert.equal(receipts.length, 8);
    assert.ok(receipts.every((r) => r.status === 'projected'));

    const skillFile = receipts[0]!.filePath;
    const mode = (await stat(skillFile)).mode & 0o777;
    assert.equal(mode, 0o444, 'Projected builtin skill must be read-only (0444)');

    const okIntegrity = await verifyProjectedSkillsIntegrity(dir);
    assert.equal(okIntegrity.valid, true);

    // Simulate tampering -> integrity check catches it -> re-projection auto-repairs it!
    await chmod(skillFile, 0o644);
    await writeFile(skillFile, 'TAMPERED CONTENT', 'utf8');
    const tampered = await verifyProjectedSkillsIntegrity(dir);
    assert.equal(tampered.valid, false);
    assert.equal(tampered.mismatches[0]?.slug, receipts[0]!.slug);

    const repaired = await projectBuiltinSkillsReadOnly(dir);
    assert.equal(repaired.find((r) => r.slug === receipts[0]!.slug)?.status, 'repaired');
    assert.equal((await verifyProjectedSkillsIntegrity(dir)).valid, true);

    // 2. Daily Pocket Notes (5-minute silence extraction + reconciliation) + Editable Artifact Docs + Wiki sync
    const notesEngine = new PipiPocketNotesEngine({ rootDir: dir, silenceSeconds: 300 });
    const t0 = Date.parse('2026-11-20T10:00:00Z');
    await notesEngine.saveDailyNote(
      '2026-11-20',
      '- [ ] 整理 Wave 3 演示脚本 2026-11-21\n- [ ] 预约周末体检\n待办：给父母买冬季保温杯',
      t0,
    );

    // After 2 minutes -> still waiting silence window
    const tooEarly = await notesEngine.reconcileDailyNoteIfQuiet('2026-11-20', { nowMs: t0 + 120_000 });
    assert.equal(tooEarly.extracted, false);
    assert.equal(tooEarly.reason, 'waiting_silence_window');

    // After 6 minutes -> extracts all 3 open Tracking Items
    const after5m = await notesEngine.reconcileDailyNoteIfQuiet('2026-11-20', { nowMs: t0 + 360_000 });
    assert.equal(after5m.extracted, true);
    assert.equal(after5m.added.length, 3);
    assert.equal(after5m.openItems.length, 3);

    // User removes "预约周末体检" and marks first done -> reconciliation removes unmentioned open item!
    await notesEngine.saveDailyNote(
      '2026-11-20',
      '- [x] 整理 Wave 3 演示脚本 2026-11-21\n待办：给父母买冬季保温杯',
      t0 + 400_000,
    );
    const reconciled = await notesEngine.reconcileDailyNoteIfQuiet('2026-11-20', { nowMs: t0 + 800_000 });
    assert.equal(reconciled.extracted, true);
    assert.equal(reconciled.removedOpenIds.length, 1);
    assert.equal(reconciled.openItems.length, 1);
    assert.equal(reconciled.openItems[0]?.title, '给父母买冬季保温杯');

    // Editable Artifact Document revisions & Personal Wiki sync
    const doc1 = await notesEngine.upsertDocument({
      title: '周末川西行前方案',
      kind: 'plan',
      markdown: '# 行程\nDay 1: 成都 -> 康定',
      tags: ['travel'],
    });
    assert.equal(doc1.revision, 1);
    const doc2 = await notesEngine.upsertDocument({
      id: doc1.id,
      title: '周末川西行前方案',
      kind: 'plan',
      markdown: '# 行程\nDay 1: 成都 -> 康定\nDay 2: 新都桥',
    });
    assert.equal(doc2.revision, 2);
    assert.notEqual(doc1.contentSha256, doc2.contentSha256);

    const wiki = new PipiPersonalWikiStore({ dbPath: join(dir, 'wiki.sqlite') });
    try {
      const syncedWikiId = await notesEngine.syncDocumentToPersonalWiki(doc2.id, wiki);
      assert.ok(syncedWikiId);
      const searchRes = wiki.search({ query: '新都桥' });
      assert.equal(searchRes.chunks[0]?.pageId, syncedWikiId);
    } finally {
      wiki.close();
    }

    // 3. Unified `pipibot` CLI single-source --help, --schema, --permissions + --operation-id idempotency
    const helpRes = await runPipiBotCli(['--help'], { rootDir: dir });
    assert.equal(helpRes.exitCode, 0);
    assert.ok(helpRes.stdout.includes('wiki search'));

    const schemaRes = await runPipiBotCli(['--schema'], { rootDir: dir });
    assert.equal(schemaRes.exitCode, 0);
    const schemaJson = JSON.parse(schemaRes.stdout) as { commands: Array<{ id: string }> };
    assert.equal(schemaJson.commands.length, PIPIBOT_CLI_COMMANDS.length);

    const permRes = await runPipiBotCli(['--permissions'], { rootDir: dir });
    assert.equal(permRes.exitCode, 0);
    const permJson = JSON.parse(permRes.stdout) as Array<{ commandId: string; actionKind: string }>;
    assert.equal(permJson.length, PIPIBOT_CLI_COMMANDS.length);
    assert.equal(permJson.find((p) => p.commandId === 'wiki.upsert')?.actionKind, 'local_write');

    // Write idempotency via --operation-id
    const ledger = new PipiOperationLedger();
    const firstWrite = await runPipiBotCli(
      ['docs', 'upsert', '--title', 'CLI Spec', '--kind', 'spec', '--markdown', '# Hello CLI', '--operation-id', 'op_cli_1'],
      { rootDir: dir, ledger },
    );
    assert.equal(firstWrite.exitCode, 0);
    assert.equal(firstWrite.replayedIdempotent, undefined);

    const retryWrite = await runPipiBotCli(
      ['docs', 'upsert', '--title', 'CLI Spec', '--kind', 'spec', '--markdown', '# Hello CLI', '--operation-id', 'op_cli_1'],
      { rootDir: dir, ledger },
    );
    assert.equal(retryWrite.exitCode, 0);
    assert.equal(retryWrite.replayedIdempotent, true, 'Retrying with same --operation-id must replay cached result without duplicate write');
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
