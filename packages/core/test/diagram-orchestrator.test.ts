import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import {
  extractDiagramBlocks,
  renderMermaidToAscii,
  renderMermaidToSvg,
  renderDiagramToStandaloneHtml,
  sanitizeSvg,
} from '../src/diagram-canvas.ts';
import {
  executeOrchestrationPlan,
  parseOrchestrationPlanFromText,
  parseStructuredTurnVerdict,
  validateOrchestrationPlan,
  type OrchestrationPlan,
} from '../src/agent-orchestrator.ts';
import { parseAndValidateTeamMd } from '../src/team-protocol.ts';
import { runPipiBotCli } from '../src/pipibot-cli.ts';
import {
  buildBoundedStreamContext,
  evaluateTopicBoundary,
  type StreamChatMessage,
} from '../src/stream-topic-context.ts';

test('diagram-canvas: extracts fenced svg/mermaid/chart and standalone raw svg with sanitization', () => {
  const md = [
    '## Architecture',
    '```mermaid title="Pipeline"',
    'flowchart LR',
    '  A["VPSS chn2<br/>480x270 Y"] -->|Y plane| B["Phase Corr"]',
    '  B -->|dx, dy| C["Path Filter"]:::warn',
    '  C -->|cx, cy| D["VGS Crop"]',
    '```',
    'And raw inline vector:',
    '<svg viewBox="0 0 100 40" onload="alert(1)"><title>Waveform</title><script>evil()</script><path d="M0 20 L100 20"/></svg>',
  ].join('\n');

  const blocks = extractDiagramBlocks(md);
  assert.equal(blocks.length, 2);
  assert.equal(blocks[0]?.kind, 'mermaid');
  assert.equal(blocks[0]?.title, 'Pipeline');
  assert.equal(blocks[1]?.kind, 'svg');
  assert.equal(blocks[1]?.title, 'Waveform');
  assert.equal(blocks[1]?.source.includes('<script>'), false);
  assert.equal(blocks[1]?.source.includes('onload='), false);

  const svg = renderMermaidToSvg(blocks[0]!.source, 'dark');
  assert.ok(svg.includes('<svg'));
  assert.ok(svg.includes('VPSS chn2'));
  assert.ok(svg.includes('Path Filter'));

  const ascii = renderMermaidToAscii(blocks[0]!.source);
  assert.ok(ascii.includes('VPSS chn2'));
  assert.ok(ascii.includes('──▶'));

  const html = renderDiagramToStandaloneHtml({ kind: 'mermaid', source: blocks[0]!.source, title: 'Pipeline', theme: 'light' });
  assert.ok(html.includes('<!doctype html>'));
  assert.ok(html.includes('Pipeline'));
});

test('diagram-canvas: sanitizes javascript href and foreignObject vectors', () => {
  const dirty = '<svg><foreignObject><div>x</div></foreignObject><a href="javascript:alert(1)">ok</a></svg>';
  const clean = sanitizeSvg(dirty);
  assert.equal(clean.includes('foreignObject'), false);
  assert.equal(clean.includes('javascript:'), false);
});

test('agent-orchestrator: validates DAG waves, detects cycles, and auto-isolates parallel write lanes', () => {
  const plan: OrchestrationPlan = {
    planId: 'plan_test_1',
    goal: 'Refactor video pipeline and add tests',
    supervisorId: 'bot_lead',
    synthesizeFinal: true,
    maxConcurrency: 3,
    autoWorktreeOnParallelWrite: true,
    nodes: [
      { id: 'scout', title: 'Inspect codebase', prompt: 'Find pipeline files', rolePreset: 'scout', dependsOn: [] },
      { id: 'code_a', title: 'Update filter', prompt: 'Edit filter.ts', rolePreset: 'coder', harness: 'codex', dependsOn: ['scout'] },
      { id: 'code_b', title: 'Update renderer', prompt: 'Edit render.ts', rolePreset: 'coder', harness: 'claude-code', dependsOn: ['scout'] },
      { id: 'review', title: 'Audit diffs', prompt: 'Review both changes', rolePreset: 'reviewer', dependsOn: ['code_a', 'code_b'] },
    ],
  };

  const v = validateOrchestrationPlan(plan);
  assert.equal(v.valid, true);
  assert.deepEqual(v.waves, [['scout'], ['code_a', 'code_b'], ['review']]);
  assert.deepEqual(v.autoIsolatedNodeIds.sort(), ['code_a', 'code_b']);

  const cyclic: OrchestrationPlan = {
    ...plan,
    nodes: [
      { id: 'a', title: 'A', prompt: 'A', rolePreset: 'coder', dependsOn: ['b'] },
      { id: 'b', title: 'B', prompt: 'B', rolePreset: 'coder', dependsOn: ['a'] },
    ],
  };
  const vc = validateOrchestrationPlan(cyclic);
  assert.equal(vc.valid, false);
  assert.ok(vc.issues.some((i) => i.code === 'orch_cycle_detected'));
});

test('agent-orchestrator: executes DAG with selective blackboard, fallback harness retry, verifier gate & synthesis', async () => {
  const plan: OrchestrationPlan = {
    planId: 'plan_exec_1',
    goal: 'Ship diagram rendering',
    supervisorId: 'bot_lead',
    synthesizeFinal: true,
    maxConcurrency: 2,
    autoWorktreeOnParallelWrite: true,
    nodes: [
      { id: 't1', title: 'Scout', prompt: 'Scan files', rolePreset: 'scout', actorId: 'bot_scout', dependsOn: [] },
      {
        id: 't2',
        title: 'Implement',
        prompt: 'Write parser',
        rolePreset: 'coder',
        actorId: 'bot_coder',
        harness: 'codex',
        fallbackHarnesses: ['claude-code'],
        maxRetries: 2,
        verifyWithActorId: 'bot_verifier',
        dependsOn: ['t1'],
      },
    ],
  };

  let coderAttempts = 0;
  let verifierCalls = 0;
  let sawUpstreamForCoder = false;

  const result = await executeOrchestrationPlan(plan, {
    async runNode(req) {
      if (req.node.id === 't1') {
        return { output: 'Found PipiMarkdownParser.swift', succeeded: true, harnessUsed: 'pi' };
      }
      if (req.node.id === 't2') {
        coderAttempts += 1;
        sawUpstreamForCoder = req.upstreamContext.some((a) => a.fromNodeId === 't1');
        if (coderAttempts === 1) {
          return { output: '', succeeded: false, errorMessage: 'codex rate limit' };
        }
        return {
          output: `Implemented parser via ${req.effectiveHarness}`,
          succeeded: true,
          harnessUsed: req.effectiveHarness,
          worktreeBranch: 'pipi/parser-1',
        };
      }
      if (req.node.rolePreset === 'verifier') {
        verifierCalls += 1;
        return { output: 'Checked edge cases. VERDICT: APPROVE', succeeded: true };
      }
      return { output: 'ok', succeeded: true };
    },
    async runSynthesis(req) {
      return `Synthesized ${req.nodeResults.length} nodes for ${req.goal}`;
    },
  });

  assert.equal(result.completed, true);
  assert.equal(result.wavesExecuted, 2);
  assert.equal(coderAttempts, 2);
  assert.equal(verifierCalls, 1);
  assert.equal(sawUpstreamForCoder, true);
  assert.equal(result.nodeOutcomes[1]?.harnessUsed, 'claude-code');
  assert.equal(result.nodeOutcomes[1]?.verifiedApproved, true);
  assert.ok(result.finalOutput.includes('Synthesized 2 nodes'));
});

test('agent-orchestrator: parses @Member DAG tags, structured verdicts, and extended team.md attributes', () => {
  const leadReply = [
    'Plan:',
    '@Scout: Inspect parser [id: t1] [role: scout]',
    '@Coder: Add SVG block [id: t2] [depends: t1] [role: coder] [harness: codex] [worktree]',
  ].join('\n');

  const plan = parseOrchestrationPlanFromText({
    text: leadReply,
    goal: 'Add inline SVG',
    supervisorId: 'bot_lead',
    candidates: [
      { id: 'bot_scout', name: 'Scout' },
      { id: 'bot_coder', name: 'Coder' },
    ],
  });
  assert.ok(plan);
  assert.equal(plan.nodes.length, 2);
  assert.deepEqual(plan.nodes[1]?.dependsOn, ['t1']);
  assert.equal(plan.nodes[1]?.harness, 'codex');
  assert.equal(plan.nodes[1]?.isolateWorktree, true);

  const v1 = parseStructuredTurnVerdict('Looks solid.\nVERDICT: APPROVE\nSTATUS: DONE');
  assert.equal(v1.approved, true);
  assert.equal(v1.done, true);

  const v2 = parseStructuredTurnVerdict('Missing test.\nVERDICT: REVISE\nSELECT: bot_coder', ['bot_writer', 'bot_coder']);
  assert.equal(v2.approved, false);
  assert.equal(v2.selectedActorId, 'bot_coder');

  const teamMd = [
    '---',
    'collaborate_pattern: fan-out-and-synthesize',
    '---',
    '# Task Goal',
    'Ship v0.14',
    '# Orchestrator',
    '## Lead',
    '- Actor ID: bot_lead',
    '- Role: Coordinator',
    '- Report to: none',
    '- Receive from: Coder',
    '# Team Members',
    '## Coder',
    '- Actor ID: bot_coder',
    '- Role: Implementer',
    '- Harness: codex',
    '- Model: gpt-5',
    '- Worktree: true',
    '- Receive from: Lead',
    '- Report to: Lead',
  ].join('\n');
  const tv = parseAndValidateTeamMd(teamMd);
  assert.equal(tv.valid, true);
  assert.equal(tv.document?.members[0]?.harness, 'codex');
  assert.equal(tv.document?.members[0]?.model, 'gpt-5');
  assert.equal(tv.document?.members[0]?.worktree, true);
});

test('pipibot CLI: diagram.render, diagram.extract, and orchestrate.validate work end-to-end', async () => {
  const tmp = await mkdtemp(join(tmpdir(), 'pipibot-diag-cli-'));
  try {
    const resAscii = await runPipiBotCli([
      'diagram',
      'render',
      '--kind',
      'mermaid',
      '--format',
      'ascii',
      '--source',
      'flowchart LR\nA[Input] --> B[Output]',
    ]);
    assert.equal(resAscii.exitCode, 0);
    assert.ok(resAscii.stdout.includes('Input'));

    const resSvg = await runPipiBotCli([
      'diagram',
      'render',
      '--kind',
      'mermaid',
      '--format',
      'svg',
      '--source',
      'flowchart LR\nA[Input] --> B[Output]',
    ]);
    assert.equal(resSvg.exitCode, 0);
    assert.ok(resSvg.stdout.includes('<svg'));

    const mdFile = join(tmp, 'note.md');
    await writeFile(mdFile, '# Note\n```mermaid title="Flow"\nflowchart TD\nA --> B\n```\n', 'utf8');
    const resExtract = await runPipiBotCli(['diagram', 'extract', '--file', mdFile]);
    assert.equal(resExtract.exitCode, 0);
    const parsedExtract = JSON.parse(resExtract.stdout) as { diagrams: Array<{ kind: string; title?: string }> };
    assert.equal(parsedExtract.diagrams.length, 1);
    assert.equal(parsedExtract.diagrams[0]?.title, 'Flow');

    const planFile = join(tmp, 'plan.json');
    await writeFile(
      planFile,
      JSON.stringify({
        planId: 'p1',
        goal: 'Test CLI validation',
        supervisorId: 'lead',
        synthesizeFinal: true,
        maxConcurrency: 2,
        autoWorktreeOnParallelWrite: true,
        nodes: [
          { id: 'a', title: 'A', prompt: 'A', rolePreset: 'coder', dependsOn: [] },
          { id: 'b', title: 'B', prompt: 'B', rolePreset: 'coder', dependsOn: [] },
        ],
      }),
      'utf8',
    );
    const resOrch = await runPipiBotCli(['orchestrate', 'validate', '--file', planFile]);
    assert.equal(resOrch.exitCode, 0);
    const parsedOrch = JSON.parse(resOrch.stdout) as { valid: boolean; autoIsolatedNodeIds: string[] };
    assert.equal(parsedOrch.valid, true);
    assert.deepEqual(parsedOrch.autoIsolatedNodeIds.sort(), ['a', 'b']);
  } finally {
    await rm(tmp, { recursive: true, force: true });
  }
});

test('stream-topic-context: detects time-gap / explicit topic shifts and strictly bounds infinite stream context', () => {
  const existing: StreamChatMessage[] = [
    { role: 'user', content: '帮我看看推特上面最近有什么新闻', createdAt: '2026-11-25T00:11:22Z' },
    { role: 'assistant', content: 'HTTP 500 error', createdAt: '2026-11-25T00:11:25Z', isError: true },
  ];

  const dGap = evaluateTopicBoundary({
    existingMessages: existing,
    activeTopicStartIndex: 0,
    incomingUserText: 'https://www.patreon.com/MagicLumix/posts/lumix-s9-raw',
    nowMs: Date.parse('2026-11-25T00:57:56Z'),
  });
  assert.equal(dGap.shouldSplit, true);
  assert.equal(dGap.reason, 'time_gap');

  const dCue = evaluateTopicBoundary({
    existingMessages: [
      { role: 'user', content: 'S9 固件能解锁什么', createdAt: '2026-11-25T01:00:00Z' },
      { role: 'assistant', content: '解锁 6K XPAN 48fps', createdAt: '2026-11-25T01:00:10Z' },
    ],
    activeTopicStartIndex: 0,
    incomingUserText: '顺便问一个问题，OMP 为什么移除了登录方式',
    nowMs: Date.parse('2026-11-25T01:02:00Z'),
  });
  assert.equal(dCue.shouldSplit, true);
  assert.equal(dCue.reason, 'explicit_cue');

  const longStream: StreamChatMessage[] = Array.from({ length: 60 }, (_, i) => ({
    role: i % 2 === 0 ? 'user' : 'assistant',
    content: `Turn ${i}: ` + '详细对话内容。'.repeat(25),
    createdAt: new Date(Date.parse('2026-11-25T01:00:00Z') + i * 20_000).toISOString(),
  }));
  const bounded = buildBoundedStreamContext({
    messages: longStream,
    topicSegments: [],
    activeTopicStartIndex: 0,
    maxVerbatimMessages: 10,
    maxChars: 6000,
  });
  assert.ok(bounded.messages.length <= 11);
  assert.ok(bounded.foldedActiveMessageCount >= 50);
  assert.ok(bounded.estimatedChars < 7500);
});
