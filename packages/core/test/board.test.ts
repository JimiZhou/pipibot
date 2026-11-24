/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * Phase 2 Tests: PipiBoardEngine (Channels -> Threads -> Tasks, Atomic Claims & Leases,
 * Dependency Unlocking, Scheduled Follow-Ups, Persistence, and Unified `pipibot board` CLI).
 */

import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { PipiBoardEngine, normalizeChannelSlug } from '../src/board-engine.ts';
import { PipiOperationLedger } from '../src/permission-guardrail.ts';
import { runPipiBotCli } from '../src/pipibot-cli.ts';

test('Phase 2: PipiBoardEngine atomic claims, TTL lease expiry & escalation, dependency unlocking, and follow-ups', () => {
  let fakeNow = Date.parse('2026-11-24T10:00:00.000Z');
  const dir = mkdtempSync(join(tmpdir(), 'pipibot-board-engine-'));
  try {
    const engine = new PipiBoardEngine({ dataDir: dir, nowFn: () => fakeNow });
    const events: string[] = [];
    engine.onEvent((ev) => events.push(ev.kind));

    assert.equal(normalizeChannelSlug('#Dev / PiPiBot!'), 'dev/pipibot');
    const customCh = engine.ensureChannel('#dev/pipibot', 'PiPiBot Dev');
    assert.equal(customCh.slug, 'dev/pipibot');

    const owner = { id: 'human:owner', name: 'Owner', kind: 'human' as const };
    const coder = { id: 'harness:codex', name: 'Codex', kind: 'harness' as const, harness: 'codex' as const };
    const claude = { id: 'harness:claude', name: 'Claude Code', kind: 'harness' as const, harness: 'claude-code' as const };
    const writer = { id: 'bot:writer', name: 'Writer', kind: 'bot' as const };

    // 1. Create prerequisite task + dependent blocked task
    const fixTask = engine.createThread({
      channelSlug: 'dev/pipibot',
      title: 'Fix E2EE relay rate limiter',
      body: 'Add per-IP token bucket and regression tests.',
      priority: 'high',
      labels: ['security', 'relay'],
      maxClaimRetries: 2,
      author: owner,
    });
    assert.equal(fixTask.status, 'open');

    const releaseNotesTask = engine.createThread({
      channelSlug: 'dev/pipibot',
      title: 'Draft v0.16 release notes',
      body: 'Summarize security fix once merged.',
      priority: 'normal',
      blockedBy: [fixTask.id],
      author: owner,
    });
    assert.equal(releaseNotesTask.status, 'blocked');

    // Cannot claim a blocked task
    const blockedClaim = engine.claimTask(releaseNotesTask.id, { actor: writer });
    assert.equal(blockedClaim.ok, false);
    assert.equal(blockedClaim.reason, 'blocked');
    assert.deepEqual(blockedClaim.unresolvedBlockers, [fixTask.id]);

    // 2. Atomic claim + conflict rejection for second agent
    const firstClaim = engine.claimTask(fixTask.id, { actor: coder, leaseMs: 10_000, note: 'Investigating rate limiter' });
    assert.equal(firstClaim.ok, true);
    assert.equal(firstClaim.thread?.status, 'claimed');
    assert.ok(firstClaim.claim?.leaseToken);

    const conflictClaim = engine.claimTask(fixTask.id, { actor: claude });
    assert.equal(conflictClaim.ok, false);
    assert.equal(conflictClaim.reason, 'already_claimed');
    assert.equal(conflictClaim.conflictClaim?.actor.id, 'harness:codex');

    // 3. Lease renewal with valid token succeeds; wrong token fails
    const badRenew = engine.renewLease(fixTask.id, {
      actorId: coder.id,
      leaseToken: 'lease_invalid',
    });
    assert.equal(badRenew.ok, false);
    assert.equal(badRenew.reason, 'token_mismatch');

    fakeNow += 6_000;
    const goodRenew = engine.renewLease(fixTask.id, {
      actorId: coder.id,
      leaseToken: firstClaim.claim!.leaseToken,
      leaseMs: 10_000,
    });
    assert.equal(goodRenew.ok, true);
    assert.equal(goodRenew.claim?.renewCount, 1);

    // 4. Advance clock past lease expiry -> claim_lost returns task to open queue
    fakeNow += 12_000;
    const expired1 = engine.sweepExpiredLeases();
    assert.equal(expired1.length, 1);
    assert.equal(expired1[0]!.status, 'open');
    assert.equal(expired1[0]!.claimLostCount, 1);

    // Claim again by Claude and let it expire a second time -> hits maxClaimRetries (2) -> escalates to needs_you
    const secondClaim = engine.claimNextTask({ actor: claude, channelSlug: 'dev/pipibot', leaseMs: 10_000 });
    assert.equal(secondClaim.ok, true);
    assert.equal(secondClaim.thread?.id, fixTask.id);
    fakeNow += 12_000;
    const expired2 = engine.sweepExpiredLeases();
    assert.equal(expired2.length, 1);
    assert.equal(expired2[0]!.status, 'needs_you');
    assert.equal(expired2[0]!.claimLostCount, 2);

    // 5. Schedule follow-up and collect when due
    const fup = engine.scheduleFollowUp(fixTask.id, {
      actor: claude,
      prompt: 'Re-check CI benchmark run',
      inMs: 30_000,
    });
    assert.ok(fup);
    assert.equal(engine.collectDueFollowUps().length, 0);
    fakeNow += 31_000;
    const triggered = engine.collectDueFollowUps();
    assert.equal(triggered.length, 1);
    assert.equal(triggered[0]!.status, 'triggered');

    // 6. Complete fixTask -> automatically unlocks releaseNotesTask
    const completed = engine.completeTask(fixTask.id, {
      actor: coder,
      summary: 'Rate limiter patched and verified.',
      deliverableRef: 'worktree:pipi/wt-relay-audit',
    });
    assert.equal(completed.ok, true);
    assert.equal(completed.thread?.status, 'done');
    assert.deepEqual(completed.unblockedThreadIds, [releaseNotesTask.id]);
    assert.equal(engine.getThread(releaseNotesTask.id)?.status, 'open');

    // Now Writer can claim releaseNotesTask via claimNextTask
    const writerClaim = engine.claimNextTask({ actor: writer, channelSlug: 'dev/pipibot' });
    assert.equal(writerClaim.ok, true);
    assert.equal(writerClaim.thread?.id, releaseNotesTask.id);

    // 7. Live inspect report & disk persistence round-trip
    const inspect = engine.inspect({ channelSlug: 'dev/pipibot' });
    assert.equal(inspect.activeLeases.length, 1);
    assert.equal(inspect.activeLeases[0]!.actor.id, writer.id);
    assert.ok(events.includes('task_unblocked'));
    assert.ok(events.includes('claim_lost'));
    assert.ok(events.includes('followup_triggered'));

    const reloaded = new PipiBoardEngine({ dataDir: dir, nowFn: () => fakeNow });
    assert.equal(reloaded.getThread(fixTask.id)?.status, 'done');
    assert.equal(reloaded.getThread(releaseNotesTask.id)?.status, 'claimed');
    assert.equal(reloaded.getThread(releaseNotesTask.id)?.claim?.actor.id, writer.id);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('Phase 2: Unified `pipibot board` CLI supports post, claim, renew, followup, complete, list, and inspect', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'pipibot-board-cli-'));
  const ledger = new PipiOperationLedger();
  try {
    const post1 = await runPipiBotCli(
      [
        '--root', dir,
        'board', 'post',
        '--channel', 'dev',
        '--title', 'Audit protocol parity',
        '--body', 'Ensure all Board enums match JSON Schema, TS, and Swift.',
        '--priority', 'high',
        '--operation-id', 'op_board_1',
      ],
      { ledger },
    );
    assert.equal(post1.exitCode, 0, post1.stderr);
    const created1 = JSON.parse(post1.stdout) as { thread: { id: string; status: string } };
    assert.equal(created1.thread.status, 'open');

    // Idempotent replay with same --operation-id returns exact same thread
    const post1Replay = await runPipiBotCli(
      [
        '--root', dir,
        'board', 'post',
        '--channel', 'dev',
        '--title', 'Audit protocol parity',
        '--body', 'Ensure all Board enums match JSON Schema, TS, and Swift.',
        '--operation-id', 'op_board_1',
      ],
      { ledger },
    );
    assert.equal(post1Replay.exitCode, 0);
    assert.equal(post1Replay.replayedIdempotent, true);
    const replayed = JSON.parse(post1Replay.stdout) as { idempotentReplay: boolean; result: { thread: { id: string } } };
    assert.equal(replayed.idempotentReplay, true);
    assert.equal(replayed.result.thread.id, created1.thread.id);

    // Create downstream blocked task
    const post2 = await runPipiBotCli([
      '--root', dir,
      'board', 'post',
      '--channel', 'dev',
      '--title', 'Cut release DMG',
      '--body', 'Build signed macOS DMG after parity audit.',
      '--blocked-by', created1.thread.id,
      '--operation-id', 'op_board_2',
    ]);
    assert.equal(post2.exitCode, 0);
    const created2 = JSON.parse(post2.stdout) as { thread: { id: string; status: string } };
    assert.equal(created2.thread.status, 'blocked');

    // Claim via queue pop
    const claim = await runPipiBotCli([
      '--root', dir,
      'board', 'claim',
      '--channel', 'dev',
      '--actor', 'codex',
      '--lease-sec', '600',
    ]);
    assert.equal(claim.exitCode, 0, claim.stderr);
    const claimed = JSON.parse(claim.stdout) as { ok: boolean; thread: { id: string }; claim: { leaseToken: string } };
    assert.equal(claimed.ok, true);
    assert.equal(claimed.thread.id, created1.thread.id);

    // Renew lease
    const renew = await runPipiBotCli([
      '--root', dir,
      'board', 'renew',
      '--thread', created1.thread.id,
      '--actor', 'codex',
      '--token', claimed.claim.leaseToken,
      '--lease-sec', '900',
    ]);
    assert.equal(renew.exitCode, 0, renew.stderr);

    // Schedule follow-up
    const fup = await runPipiBotCli([
      '--root', dir,
      'board', 'followup',
      '--thread', created1.thread.id,
      '--actor', 'codex',
      '--in-sec', '120',
      '--prompt', 'Check swift test output',
    ]);
    assert.equal(fup.exitCode, 0, fup.stderr);

    // Complete -> unblocks created2
    const complete = await runPipiBotCli([
      '--root', dir,
      'board', 'complete',
      '--thread', created1.thread.id,
      '--actor', 'codex',
      '--token', claimed.claim.leaseToken,
      '--summary', 'All 39 enums match 1:1.',
      '--deliverable', 'audit:green',
    ]);
    assert.equal(complete.exitCode, 0, complete.stderr);
    const completed = JSON.parse(complete.stdout) as { ok: boolean; unblockedThreadIds: string[] };
    assert.deepEqual(completed.unblockedThreadIds, [created2.thread.id]);

    // Inspect & list
    const inspect = await runPipiBotCli(['--root', dir, 'board', 'inspect', '--channel', 'dev']);
    assert.equal(inspect.exitCode, 0, inspect.stderr);
    const report = JSON.parse(inspect.stdout) as { counts: { done: number; open: number }; recentEvents: unknown[] };
    assert.equal(report.counts.done, 1);
    assert.equal(report.counts.open, 1);
    assert.ok(report.recentEvents.length >= 4);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
