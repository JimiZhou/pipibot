/**
 * @pipibot/daemon integration test suite (`node:test` + `node:assert/strict`)
 */

import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { get as httpGet } from 'node:http';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { after, before, describe, test } from 'node:test';
import { fileURLToPath } from 'node:url';

import { parseCliArgs } from '../src/cli.ts';
import { computeWebhookHmac, matchesCronExpression } from '../src/event-triggers.ts';
import { DAEMON_VERSION, PipiResidentServer } from '../src/server.ts';
import { PipiMeshNodeAgent } from '../src/mesh-node.ts';

const MODULE_DIR = fileURLToPath(new URL('.', import.meta.url));
const REAL_REPO_ROOT = resolve(MODULE_DIR, '..', '..', '..');

async function requestJson<T>(
  baseUrl: string,
  path: string,
  init: RequestInit = {},
): Promise<{ status: number; headers: Headers; data: T }> {
  const res = await fetch(`${baseUrl}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(init.headers ?? {}),
    },
  });
  const data = (await res.json()) as T;
  return { status: res.status, headers: res.headers, data };
}

describe('PipiBot V1 Mac Resident Daemon (@pipibot/daemon)', () => {
  let tempDataDir: string;
  let server: PipiResidentServer;
  let baseUrl: string;

  before(async () => {
    tempDataDir = mkdtempSync(join(tmpdir(), 'pipibot-daemon-test-'));
    server = new PipiResidentServer({
      port: 0,
      host: '127.0.0.1',
      repoRoot: REAL_REPO_ROOT,
      dataDir: tempDataDir,
      workspacePath: REAL_REPO_ROOT,
      pulseIntervalMs: 80, // faster pulse in test to verify cadence deterministically without long waits
    });
    baseUrl = await server.start();
  });

  after(async () => {
    await server.stop();
    rmSync(tempDataDir, { recursive: true, force: true });
  });

  test('CLI argument parsing handles ports, hosts, workspace, and flags', () => {
    const parsed = parseCliArgs(['--port', '4343', '--host', '0.0.0.0', '--workspace', '/tmp/ws', '--print-plist', '--clean']);
    assert.equal(parsed.port, 4343);
    assert.equal(parsed.host, '0.0.0.0');
    assert.equal(parsed.workspacePath, '/tmp/ws');
    assert.equal(parsed.printPlistOnly, true);
    assert.equal(parsed.clean, true);
    assert.equal(parsed.help, false);
  });

  test('Clean mode starts without demo outcomes, decisions, or mock fleet nodes', async () => {
    const cleanDir = mkdtempSync(join(tmpdir(), 'pipibot-clean-test-'));
    const cleanServer = new PipiResidentServer({
      port: 0,
      host: '127.0.0.1',
      repoRoot: REAL_REPO_ROOT,
      dataDir: cleanDir,
      seedDefaults: false,
      seedFleet: false,
      seedMemoryIfEmpty: false,
    });
    try {
      const url = await cleanServer.start();
      const outcomesRes = await requestJson<{ outcomes: unknown[] }>(url, '/api/v1/outcomes');
      const decisionsRes = await requestJson<{ decisions: unknown[] }>(url, '/api/v1/decisions');
      assert.equal(outcomesRes.data.outcomes.length, 0);
      assert.equal(decisionsRes.data.decisions.length, 0);
    } finally {
      await cleanServer.stop();
      rmSync(cleanDir, { recursive: true, force: true });
    }
  });

  test('GET / and GET /api/v1/status return daemon metadata, CORS headers, and 53-state avatar status', async () => {
    const rootRes = await requestJson<{ name: string; version: string }>(baseUrl, '/');
    assert.equal(rootRes.status, 200);
    assert.equal(rootRes.data.name, 'pipibot-daemon');
    assert.equal(rootRes.data.version, DAEMON_VERSION);
    assert.equal(rootRes.headers.get('access-control-allow-origin'), '*');

    const optRes = await fetch(`${baseUrl}/api/v1/status`, { method: 'OPTIONS' });
    assert.equal(optRes.status, 204);

    const statusRes = await requestJson<{
      version: string;
      uptimeSeconds: number;
      avatarState: string;
      avatarExpression: string;
      harnesses: Array<{ provider: string }>;
      cloudflare: { freeTierQuota: { monthlyCostUsd: number } };
      understandingScore: { overall: number };
      counts: { outcomes: number; pendingDecisions: number; fleetOnline: number };
    }>(baseUrl, '/api/v1/status');

    assert.equal(statusRes.status, 200);
    assert.equal(statusRes.data.version, DAEMON_VERSION);
    assert.ok(statusRes.data.uptimeSeconds >= 0);
    assert.ok(statusRes.data.avatarState.length > 0);
    assert.ok(statusRes.data.harnesses.length >= 5);
    assert.equal(statusRes.data.cloudflare.freeTierQuota.monthlyCostUsd, 0);
    assert.ok(statusRes.data.understandingScore.overall > 0);
    assert.ok(statusRes.data.counts.outcomes >= 4);
    assert.ok(statusRes.data.counts.pendingDecisions >= 3);
  });

  test('GET /api/v1/events streams SSE connected, harness.pulse, and live domain events', async () => {
    const controller = new AbortController();
    const sseRes = await fetch(`${baseUrl}/api/v1/events`, { signal: controller.signal });
    assert.equal(sseRes.status, 200);
    assert.match(sseRes.headers.get('content-type') ?? '', /text\/event-stream/);
    assert.ok(sseRes.body);

    const reader = sseRes.body.getReader();
    const decoder = new TextDecoder();
    let collected = '';

    // Trigger a live domain event while SSE is connected
    const heartbeatPromise = requestJson(baseUrl, '/api/v1/fleet/heartbeat', {
      method: 'POST',
      body: JSON.stringify({ nodeId: 'vps-hk-01', vitality: 'alive', cpuLoadPct: 31.2 }),
    });

    const deadline = Date.now() + 3000;
    while (Date.now() < deadline) {
      const { value, done } = await reader.read();
      if (done) break;
      collected += decoder.decode(value, { stream: true });
      if (
        collected.includes('event: connected') &&
        collected.includes('event: harness.pulse') &&
        collected.includes('event: node.heartbeat')
      ) {
        break;
      }
    }

    await heartbeatPromise;
    controller.abort();
    await reader.cancel().catch(() => undefined);

    assert.ok(collected.includes('event: connected'), 'expected connected event');
    assert.ok(collected.includes('event: harness.pulse'), 'expected harness.pulse event');
    assert.ok(collected.includes('"pulseIntervalMs":250'), 'expected 250ms protocol pulse metadata');
    assert.ok(collected.includes('event: node.heartbeat'), 'expected live node.heartbeat event');
  });

  test('GET /api/v1/resources returns normalized CPU, memory, and disk telemetry', async () => {
    const response = await requestJson<{
      sampledAt: string;
      cpu: { usagePercent: number; load1m: number; coreCount: number };
      memory: { totalBytes: number; usedBytes: number; usedPercent: number };
      disk: { path: string; totalBytes: number; availableBytes: number; usedPercent: number };
    }>(baseUrl, '/api/v1/resources');

    assert.equal(response.status, 200);
    assert.match(response.data.sampledAt, /^\d{4}-\d{2}-\d{2}T/);
    assert.ok(response.data.cpu.coreCount > 0);
    assert.ok(response.data.cpu.usagePercent >= 0 && response.data.cpu.usagePercent <= 100);
    assert.ok(response.data.memory.totalBytes > 0);
    assert.ok(response.data.memory.usedBytes >= 0);
    assert.ok(response.data.memory.usedPercent >= 0 && response.data.memory.usedPercent <= 100);
    assert.ok(response.data.disk.totalBytes > 0);
    assert.ok(response.data.disk.availableBytes >= 0);
    assert.ok(response.data.disk.usedPercent >= 0 && response.data.disk.usedPercent <= 100);
  });

  test('Outcomes CRUD, 2-Stage Evaluator, and Needs-You Decision resolution work end-to-end', async () => {
    const listRes = await requestJson<{
      outcomes: Array<{ id: string }>;
      subSessions: Array<{ id: string }>;
    }>(baseUrl, '/api/v1/outcomes');
    assert.equal(listRes.status, 200);
    assert.equal(listRes.data.outcomes.length, 4);
    assert.equal(listRes.data.subSessions.length, 3);

    const createRes = await requestJson<{ outcome: { id: string; status: string } }>(
      baseUrl,
      '/api/v1/outcomes',
      {
        method: 'POST',
        body: JSON.stringify({
          title: 'Automated API Smoke Sentinel',
          domain: 'dev',
          goal: 'Verify daemon API health and latency on every edit',
          preferredHarness: 'pi',
          dailyBudgetUsd: 3.0,
        }),
      },
    );
    assert.equal(createRes.status, 201);
    const createdId = createRes.data.outcome.id;
    assert.equal(createRes.data.outcome.status, 'active');

    // Stage 2 evaluation with human sign-off creates a SubSession + NeedsYouDecision
    const evalRes = await requestJson<{
      stage1Passed: boolean;
      outcome: { status: string; spentTodayUsd: number };
      subSession?: { id: string; status: string };
      createdDecision?: { id: string; status: string };
    }>(baseUrl, `/api/v1/outcomes/${createdId}/evaluate`, {
      method: 'POST',
      body: JSON.stringify({ requireHumanSignOff: true }),
    });
    assert.equal(evalRes.status, 200);
    assert.equal(evalRes.data.stage1Passed, true);
    assert.equal(evalRes.data.outcome.status, 'needs_you');
    assert.ok(evalRes.data.outcome.spentTodayUsd > 0);
    assert.ok(evalRes.data.subSession?.id);
    assert.equal(evalRes.data.createdDecision?.status, 'pending');

    // Resolve the escalated decision
    const decisionId = evalRes.data.createdDecision!.id;
    const resolveRes = await requestJson<{ decision: { status: string; chosenOptionId: string } }>(
      baseUrl,
      `/api/v1/decisions/${decisionId}/resolve`,
      {
        method: 'POST',
        body: JSON.stringify({ chosenOptionId: 'approve', userNote: 'Verified in test' }),
      },
    );
    assert.equal(resolveRes.status, 200);
    assert.equal(resolveRes.data.decision.status, 'resolved');
    assert.equal(resolveRes.data.decision.chosenOptionId, 'approve');

    // Pause outcome -> Stage 1 skips cleanly
    const pauseRes = await requestJson<{ outcome: { status: string } }>(
      baseUrl,
      `/api/v1/outcomes/${createdId}/status`,
      { method: 'POST', body: JSON.stringify({ status: 'paused' }) },
    );
    assert.equal(pauseRes.status, 200);
    assert.equal(pauseRes.data.outcome.status, 'paused');

    const skippedEval = await requestJson<{ stage1Passed: boolean; skipReason?: string }>(
      baseUrl,
      `/api/v1/outcomes/${createdId}/evaluate`,
      { method: 'POST', body: JSON.stringify({}) },
    );
    assert.equal(skippedEval.status, 200);
    assert.equal(skippedEval.data.stage1Passed, false);
    assert.match(skippedEval.data.skipReason ?? '', /paused/i);
  });

  test('Manus Cue refresh, execution, and feedback log directly to cognitive memory', async () => {
    const refreshRes = await requestJson<{
      cue: { id: string; activeAppName: string; actions: Array<{ id: string }> };
    }>(baseUrl, '/api/v1/cue/refresh', {
      method: 'POST',
      body: JSON.stringify({ activeAppName: 'Xcode', windowTitle: 'PipiBotApp.swift' }),
    });
    assert.equal(refreshRes.status, 200);
    assert.equal(refreshRes.data.cue.activeAppName, 'Xcode');
    assert.ok(refreshRes.data.cue.actions.length >= 2);

    const cueId = refreshRes.data.cue.id;
    const actionId = refreshRes.data.cue.actions[0]!.id;

    const execRes = await requestJson<{
      executed: boolean;
      cue: { feedback: string };
      turnResult: { text: string };
    }>(baseUrl, `/api/v1/cue/${cueId}/execute`, {
      method: 'POST',
      body: JSON.stringify({ actionId }),
    });
    assert.equal(execRes.status, 200);
    assert.equal(execRes.data.executed, true);
    assert.equal(execRes.data.cue.feedback, 'accepted');
    assert.ok(execRes.data.turnResult.text.length > 0);

    const fbRes = await requestJson<{ cue: { feedback: string } }>(
      baseUrl,
      `/api/v1/cue/${cueId}/feedback`,
      {
        method: 'POST',
        body: JSON.stringify({ feedback: 'dismissed', actionLabel: 'Manual dismiss test' }),
      },
    );
    assert.equal(fbRes.status, 200);
    assert.equal(fbRes.data.cue.feedback, 'dismissed');
  });

  test('PipiFleet returns live macOS host telemetry, all 5 node kinds, and accepts heartbeats', async () => {
    const fleetRes = await requestJson<{
      nodes: Array<{ nodeId: string; kind: string; osVersion: string }>;
      cloudflare: { freeTierQuota: { monthlyCostUsd: number } };
    }>(baseUrl, '/api/v1/fleet');
    assert.equal(fleetRes.status, 200);

    const kinds = new Set(fleetRes.data.nodes.map((n) => n.kind));
    assert.ok(kinds.has('mac'));
    assert.ok(kinds.has('ios'));
    assert.ok(kinds.has('vps'));
    assert.ok(kinds.has('windows'));
    assert.ok(kinds.has('embedded'));
    assert.equal(fleetRes.data.cloudflare.freeTierQuota.monthlyCostUsd, 0);

    const hbRes = await requestJson<{ node: { nodeId: string; vitality: string; cpuLoadPct: number } }>(
      baseUrl,
      '/api/v1/fleet/heartbeat',
      {
        method: 'POST',
        body: JSON.stringify({
          nodeId: 'esp32-home-lab',
          vitality: 'busy',
          cpuLoadPct: 44.5,
        }),
      },
    );
    assert.equal(hbRes.status, 200);
    assert.equal(hbRes.data.node.vitality, 'busy');
    assert.equal(hbRes.data.node.cpuLoadPct, 44.5);
  });

  test('Multi-Harness Chat turn persists transcript and feeds L1 memory & Micro-Reflection', async () => {
    const turnRes = await requestJson<{
      sessionId: string;
      providerUsed: string;
      text: string;
      toolCallsExecuted: number;
      reflection: { explicitPreferenceDetected: boolean; appendedEventId: string };
    }>(baseUrl, '/api/v1/chat/turn', {
      method: 'POST',
      body: JSON.stringify({
        sessionId: 'test-chat-session',
        provider: 'claude-code',
        prompt: '记住以后永远在 TypeScript 核心包中使用 zero external deps',
      }),
    });
    assert.equal(turnRes.status, 200);
    assert.equal(turnRes.data.providerUsed, 'claude-code');
    assert.equal(turnRes.data.toolCallsExecuted, 1);
    assert.equal(turnRes.data.reflection.explicitPreferenceDetected, true);
    assert.ok(turnRes.data.text.includes('claude-code'));

    const trRes = await requestJson<{
      sessionId: string;
      entries: Array<{ role: string; content: string }>;
    }>(baseUrl, '/api/v1/chat/transcript?sessionId=test-chat-session');
    assert.equal(trRes.status, 200);
    assert.ok(trRes.data.entries.length >= 2);
  });

  test('Cognitive Memory search, Nightly Dreaming, Diff review, and SOUL/USER markdown render', async () => {
    const memRes = await requestJson<{
      episodic: unknown[];
      facts: unknown[];
      understandingScore: { overall: number };
    }>(baseUrl, '/api/v1/memory');
    assert.equal(memRes.status, 200);
    assert.ok(memRes.data.episodic.length >= 4);
    assert.ok(memRes.data.facts.length >= 5);
    assert.ok(memRes.data.understandingScore.overall > 0);

    const searchRes = await requestJson<{
      episodic: unknown[];
      facts: unknown[];
      promptContextBlock: string;
    }>(baseUrl, '/api/v1/memory/search', {
      method: 'POST',
      body: JSON.stringify({ query: 'zero external deps cloudflare vps' }),
    });
    assert.equal(searchRes.status, 200);
    assert.ok(searchRes.data.promptContextBlock.includes('<pipibot_cognitive_memory>'));

    const dreamRes = await requestJson<{
      summary: {
        digestId: string;
        diffs: Array<{ diffId: string; reviewStatus: string }>;
      };
    }>(baseUrl, '/api/v1/memory/dream', { method: 'POST', body: JSON.stringify({}) });
    assert.equal(dreamRes.status, 200);
    assert.ok(dreamRes.data.summary.digestId.startsWith('evo_'));
    assert.ok(dreamRes.data.summary.diffs.length >= 1);

    const firstDiff = dreamRes.data.summary.diffs[0]!;
    const reviewRes = await requestJson<{
      summary: { diffs: Array<{ diffId: string; reviewStatus: string }> };
    }>(baseUrl, `/api/v1/memory/diffs/${firstDiff.diffId}/review`, {
      method: 'POST',
      body: JSON.stringify({ action: 'approve' }),
    });
    assert.equal(reviewRes.status, 200);
    const reviewed = reviewRes.data.summary.diffs.find((d) => d.diffId === firstDiff.diffId);
    assert.equal(reviewed?.reviewStatus, 'approved');

    const soulRes = await requestJson<{ soulMd: string; userMd: string; memoryMd: string }>(
      baseUrl,
      '/api/v1/memory/soul',
    );
    assert.equal(soulRes.status, 200);
    assert.ok(soulRes.data.soulMd.includes('SOUL.md'));
    assert.ok(soulRes.data.userMd.includes('USER.md'));
    assert.ok(soulRes.data.memoryMd.includes('MEMORY.md'));
  });

  test('GET /api/v1/launchd-plist generates valid macOS LaunchAgent XML and JSON', async () => {
    const xmlRes = await fetch(`${baseUrl}/api/v1/launchd-plist`);
    assert.equal(xmlRes.status, 200);
    assert.match(xmlRes.headers.get('content-type') ?? '', /application\/xml/);
    const xml = await xmlRes.text();
    assert.ok(xml.includes('<string>ai.pipibot.daemon</string>'));
    assert.ok(xml.includes('--experimental-strip-types'));

    const jsonRes = await requestJson<{ label: string; plistXml: string }>(
      baseUrl,
      '/api/v1/launchd-plist?format=json',
    );
    assert.equal(jsonRes.status, 200);
    assert.equal(jsonRes.data.label, 'ai.pipibot.daemon');
  });

  test('Static hosting serves /design-system/ and /ios/ safely and blocks path traversal', async () => {
    const dsRes = await fetch(`${baseUrl}/design-system/`);
    assert.equal(dsRes.status, 200);
    const dsHtml = await dsRes.text();
    assert.ok(dsHtml.includes('PipiAvatar'));

    const jsRes = await fetch(`${baseUrl}/design-system/pipibot-avatar.js`);
    assert.equal(jsRes.status, 200);
    assert.match(jsRes.headers.get('content-type') ?? '', /javascript/);

    const parsedUrl = new URL(baseUrl);
    const travStatus = await new Promise<number>((resolveStatus, rejectStatus) => {
      const req = httpGet(
        {
          hostname: parsedUrl.hostname,
          port: Number(parsedUrl.port),
          path: '/design-system/%2e%2e/package.json',
        },
        (res) => {
          res.resume();
          resolveStatus(res.statusCode ?? 0);
        },
      );
      req.on('error', rejectStatus);
    });
    assert.equal(travStatus, 403);

    // If real apps/ios-web exists (once Wave 2 completes), assert 200 directly;
    // also verify isolated static /ios/ mounting deterministically via temp repoRoot.
    if (existsSync(join(REAL_REPO_ROOT, 'apps', 'ios-web', 'index.html'))) {
      const realIosRes = await fetch(`${baseUrl}/ios/`);
      assert.equal(realIosRes.status, 200);
    }

    const tempRepo = mkdtempSync(join(tmpdir(), 'pipibot-ios-static-'));
    const tempData = mkdtempSync(join(tmpdir(), 'pipibot-ios-data-'));
    mkdirSync(join(tempRepo, 'apps', 'ios-web'), { recursive: true });
    writeFileSync(join(tempRepo, 'apps', 'ios-web', 'index.html'), '<!doctype html><html><body>PipiIOS</body></html>');
    const iosServer = new PipiResidentServer({
      port: 0,
      repoRoot: tempRepo,
      dataDir: tempData,
      seedMemoryIfEmpty: false,
    });
    try {
      const iosUrl = await iosServer.start();
      const res = await fetch(`${iosUrl}/ios/`);
      assert.equal(res.status, 200);
      assert.ok((await res.text()).includes('PipiIOS'));

      const noSlash = await fetch(`${iosUrl}/ios`);
      assert.equal(noSlash.status, 200);
    } finally {
      await iosServer.stop();
      rmSync(tempRepo, { recursive: true, force: true });
      rmSync(tempData, { recursive: true, force: true });
    }
  });

  test('Multi-Machine Mesh Hub: 2 parallel headless nodes, cross-host artifact relay, systemd unit, and MCP/SKILL.md ecosystem sync', async () => {
    // 1. Verify Linux systemd unit endpoint
    const unitRes = await fetch(`${baseUrl}/api/v1/systemd-service?role=node&name=linux-4090`);
    assert.equal(unitRes.status, 200);
    const unitText = await unitRes.text();
    assert.ok(unitText.includes('[Service]'));
    assert.ok(unitText.includes('node join'));
    assert.ok(unitText.includes('linux-4090'));

    // 2. Spin up two independent headless Mesh Nodes connecting outbound to the Hub
    const nodeA = new PipiMeshNodeAgent({
      hubUrl: baseUrl,
      name: 'linux-4090',
      nodeId: 'node_linux_4090',
      heartbeatIntervalMs: 30_000,
      customExecutor: async (task) => {
        await new Promise((r) => setTimeout(r, 80));
        return {
          text: `GPU node completed: ${task.prompt}`,
          artifacts: [
            {
              fileName: 'gpu_report.txt',
              mimeType: 'text/plain',
              contentBase64: Buffer.from('RTX 4090 24GB VRAM OK', 'utf8').toString('base64'),
            },
          ],
        };
      },
    });
    const nodeB = new PipiMeshNodeAgent({
      hubUrl: baseUrl,
      name: 'prod-vps',
      nodeId: 'node_prod_vps',
      heartbeatIntervalMs: 30_000,
      customExecutor: async (task) => {
        await new Promise((r) => setTimeout(r, 60));
        return { text: `VPS node completed: ${task.prompt}` };
      },
    });

    try {
      await nodeA.start();
      await nodeB.start();
      await new Promise((r) => setTimeout(r, 150));

      const nodesRes = await requestJson<{ nodes: Array<{ nodeId: string; status: string }> }>(
        baseUrl,
        '/api/v1/mesh/nodes',
      );
      assert.equal(nodesRes.status, 200);
      assert.ok(nodesRes.data.nodes.some((n) => n.nodeId === 'node_linux_4090' && n.status === 'online'));
      assert.ok(nodesRes.data.nodes.some((n) => n.nodeId === 'node_prod_vps' && n.status === 'online'));

      // 3. Dispatch two tasks in parallel across both machines without blocking
      const [d1, d2] = await Promise.all([
        requestJson<{ task: { taskId: string } }>(baseUrl, '/api/v1/mesh/dispatch', {
          method: 'POST',
          body: JSON.stringify({ targetNodeId: 'linux-4090', prompt: 'check cuda', groupId: 'grp_1' }),
        }),
        requestJson<{ task: { taskId: string } }>(baseUrl, '/api/v1/mesh/dispatch', {
          method: 'POST',
          body: JSON.stringify({ targetNodeId: 'prod-vps', prompt: 'check nginx', groupId: 'grp_1' }),
        }),
      ]);
      assert.equal(d1.status, 201);
      assert.equal(d2.status, 201);

      // Wait briefly for both parallel executions to complete
      let t1Done: { status: string; outputText: string; outputArtifactIds: string[] } | undefined;
      let t2Done: { status: string; outputText: string } | undefined;
      for (let i = 0; i < 30; i += 1) {
        await new Promise((r) => setTimeout(r, 50));
        const r1 = await requestJson<{ task: { status: string; outputText: string; outputArtifactIds: string[] } }>(
          baseUrl,
          `/api/v1/mesh/tasks/${d1.data.task.taskId}`,
        );
        const r2 = await requestJson<{ task: { status: string; outputText: string } }>(
          baseUrl,
          `/api/v1/mesh/tasks/${d2.data.task.taskId}`,
        );
        if (r1.data.task.status === 'completed' && r2.data.task.status === 'completed') {
          t1Done = r1.data.task;
          t2Done = r2.data.task;
          break;
        }
      }
      assert.ok(t1Done?.outputText.includes('GPU node completed: check cuda'));
      assert.ok(t2Done?.outputText.includes('VPS node completed: check nginx'));
      assert.equal(t1Done?.outputArtifactIds.length, 1);

      // 4. Download cross-machine artifact relayed via Hub
      const artResp = await fetch(`${baseUrl}/api/v1/mesh/artifacts/${t1Done!.outputArtifactIds[0]}`);
      assert.equal(artResp.status, 200);
      assert.equal(await artResp.text(), 'RTX 4090 24GB VRAM OK');

      // 5. Ecosystem SKILL.md + MCP Server install & sync
      const skillInstall = await requestJson<{ ok: boolean; skill: { id: string; name: string } }>(
        baseUrl,
        '/api/v1/ecosystem/skills',
        {
          method: 'POST',
          body: JSON.stringify({ source: 'skill-linux-ops', scope: 'host', targetId: 'node_linux_4090' }),
        },
      );
      assert.equal(skillInstall.status, 201);
      assert.equal(skillInstall.data.skill.id, 'skill-linux-ops');

      const mcpInstall = await requestJson<{ ok: boolean; server: { id: string; name: string } }>(
        baseUrl,
        '/api/v1/ecosystem/mcp',
        {
          method: 'POST',
          body: JSON.stringify({
            id: 'mcp-fetch',
            name: 'Web Fetch MCP',
            transport: 'stdio',
            command: 'npx',
            args: ['-y', '@modelcontextprotocol/server-fetch'],
          }),
        },
      );
      assert.equal(mcpInstall.status, 201);

      const ecoRes = await requestJson<{ skills: unknown[]; mcpServers: unknown[] }>(baseUrl, '/api/v1/ecosystem');
      assert.equal(ecoRes.status, 200);
      assert.ok(ecoRes.data.skills.length >= 1);
      assert.ok(ecoRes.data.mcpServers.length >= 1);
    } finally {
      nodeA.stop();
      nodeB.stop();
    }
  });

  test('v0.13.0 Event-Driven HMAC Webhook, Cron Matcher & Live Git Worktree Diff/Merge API', async () => {
    // 1. Cron matcher verification (2026-11-23 09:30 is Monday)
    assert.equal(matchesCronExpression('30 9 * * 1-5', new Date(2026, 10, 23, 9, 30)), true);
    assert.equal(matchesCronExpression('30 9 * * 1-5', new Date(2026, 10, 22, 9, 30)), false);

    // 2. Register HMAC-protected webhook routine & test auth + cooldown
    const reg = await requestJson<{ routine: { id: string } }>(baseUrl, '/api/v1/triggers', {
      method: 'POST',
      body: JSON.stringify({
        id: 'rt_gh_pr',
        botId: 'bot_pipi_coder',
        title: 'PR Review Hook',
        prompt: 'Review PR diff',
        triggerKind: 'webhook',
        webhookSecret: 'whsec_test_99',
        cooldownSeconds: 60,
      }),
    });
    assert.equal(reg.status, 201);

    const payload = JSON.stringify({ action: 'opened', pr: 128 });
    const badHook = await fetch(`${baseUrl}/api/v1/webhooks/rt_gh_pr`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-PiPiBot-Signature': 'sha256=invalid' },
      body: payload,
    });
    assert.equal(badHook.status, 401);

    const goodSig = computeWebhookHmac('whsec_test_99', payload);
    const okHook = await fetch(`${baseUrl}/api/v1/webhooks/rt_gh_pr`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-PiPiBot-Signature': goodSig },
      body: payload,
    });
    assert.equal(okHook.status, 202);

    const cooldownHook = await fetch(`${baseUrl}/api/v1/webhooks/rt_gh_pr`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-PiPiBot-Signature': goodSig },
      body: payload,
    });
    assert.equal(cooldownHook.status, 429);

    // 3. Real temporary Git repository Worktree create -> edit -> diff -> feedback -> squash merge -> cleanup
    const gitRepo = mkdtempSync(join(tmpdir(), 'pipibot-daemon-wt-'));
    try {
      execFileSync('git', ['init', '-b', 'main'], { cwd: gitRepo });
      execFileSync('git', ['config', 'user.email', 'ci@pipibot.dev'], { cwd: gitRepo });
      execFileSync('git', ['config', 'user.name', 'PiPi CI'], { cwd: gitRepo });
      writeFileSync(join(gitRepo, 'app.ts'), 'export const v = 1;\n');
      execFileSync('git', ['add', '-A'], { cwd: gitRepo });
      execFileSync('git', ['commit', '-m', 'init'], { cwd: gitRepo });

      const created = await requestJson<{ session: { id: string; worktreePath: string; branchName: string } }>(
        baseUrl,
        '/api/v1/worktrees',
        {
          method: 'POST',
          body: JSON.stringify({ repoPath: gitRepo, taskTitle: 'Refactor Auth', botId: 'bot_pipi_coder' }),
        },
      );
      assert.equal(created.status, 201);
      const wtId = created.data.session.id;
      const wtPath = created.data.session.worktreePath;
      assert.ok(existsSync(wtPath));

      writeFileSync(join(wtPath, 'app.ts'), '// HACK temp\nexport const v = 2;\n');
      const blockedVerify = await requestJson<{ proof: { overallStatus: string; proofScore: number } }>(
        baseUrl,
        `/api/v1/worktrees/${wtId}/verify`,
        { method: 'POST', body: JSON.stringify({}) },
      );
      assert.equal(blockedVerify.status, 200);
      assert.equal(blockedVerify.data.proof.overallStatus, 'blocked');

      writeFileSync(join(wtPath, 'app.ts'), 'export const v = 2;\n');
      const passVerify = await requestJson<{ proof: { overallStatus: string; proofScore: number } }>(
        baseUrl,
        `/api/v1/worktrees/${wtId}/verify`,
        { method: 'POST', body: JSON.stringify({}) },
      );
      assert.equal(passVerify.status, 200);
      assert.equal(passVerify.data.proof.overallStatus, 'verified');
      assert.equal(passVerify.data.proof.proofScore, 100);

      // Loop Draft Gate: hard no-draft escalation + edit-and-add-rule + knowledge gaps
      const refundDraft = await requestJson<{ draft: { status: string; draftContent: string } }>(
        baseUrl,
        '/api/v1/loops/drafts',
        {
          method: 'POST',
          body: JSON.stringify({
            loopName: 'Support Loop',
            botId: 'bot_pipi_operator',
            inputSummary: 'Need a refund for duplicate charge',
            draftContent: 'should stay empty',
          }),
        },
      );
      assert.equal(refundDraft.status, 201);
      assert.equal(refundDraft.data.draft.status, 'flagged_undrafted');
      assert.equal(refundDraft.data.draft.draftContent, '');

      const normalDraft = await requestJson<{ draft: { id: string; status: string } }>(
        baseUrl,
        '/api/v1/loops/drafts',
        {
          method: 'POST',
          body: JSON.stringify({
            loopName: 'Support Loop',
            botId: 'bot_pipi_operator',
            inputSummary: 'How to reset key?',
            draftContent: 'See docs/keys.md',
          }),
        },
      );
      assert.equal(normalDraft.data.draft.status, 'pending_gate');

      const resolvedDraft = await requestJson<{ draft: { status: string }; harnessRules: string[] }>(
        baseUrl,
        `/api/v1/loops/drafts/${normalDraft.data.draft.id}/resolve`,
        {
          method: 'POST',
          body: JSON.stringify({
            action: 'edit_and_add_rule',
            editedDraft: 'Go to Settings -> Vault -> Rotate Key (docs/keys.md).',
            newRule: 'Always include exact Settings navigation path',
          }),
        },
      );
      assert.equal(resolvedDraft.status, 200);
      assert.equal(resolvedDraft.data.draft.status, 'edited_and_sent');
      assert.ok(resolvedDraft.data.harnessRules.includes('Always include exact Settings navigation path'));

      const gapRes = await requestJson<{ gap: { id: string; occurrenceCount: number } }>(
        baseUrl,
        '/api/v1/gaps',
        { method: 'POST', body: JSON.stringify({ botId: 'bot_pipi_operator', question: 'How to configure SSO?' }) },
      );
      assert.equal(gapRes.status, 201);
      assert.equal(gapRes.data.gap.occurrenceCount, 1);

      const diffRes = await requestJson<{ session: { status: string; files: unknown[]; unifiedDiff: string } }>(
        baseUrl,
        `/api/v1/worktrees/${wtId}/diff`,
        { method: 'POST', body: JSON.stringify({}) },
      );
      assert.equal(diffRes.status, 200);
      assert.equal(diffRes.data.session.status, 'ready_for_review');
      assert.equal(diffRes.data.session.files.length, 1);
      assert.ok(diffRes.data.session.unifiedDiff.includes('export const v = 2;'));

      const fbRes = await requestJson<{ session: { status: string; comments: unknown[] } }>(
        baseUrl,
        `/api/v1/worktrees/${wtId}/feedback`,
        { method: 'POST', body: JSON.stringify({ comment: 'Add JSDoc', filePath: 'app.ts', lineNumber: 1 }) },
      );
      assert.equal(fbRes.status, 200);
      assert.equal(fbRes.data.session.status, 'changes_requested');
      assert.equal(fbRes.data.session.comments.length, 1);

      const mergeRes = await requestJson<{ session: { status: string }; summary: string }>(
        baseUrl,
        `/api/v1/worktrees/${wtId}/merge`,
        { method: 'POST', body: JSON.stringify({ strategy: 'squash', commitMessage: 'feat: bump v2' }) },
      );
      assert.equal(mergeRes.status, 200);
      assert.equal(mergeRes.data.session.status, 'merged');
      assert.equal(existsSync(wtPath), false);
      assert.equal(readFileSync(join(gitRepo, 'app.ts'), 'utf8'), 'export const v = 2;\n');
    } finally {
      rmSync(gitRepo, { recursive: true, force: true });
    }
  });

  test('v0.15 Universal Pairing Link, Bounded MCP hard-block, Sentinel, Portable Templates, Group Router, Credential Broker & Bot Box', async () => {
    const { handleBoundedMCPRequest } = await import('../src/mcp-server.ts');
    const { PipiCredentialBrokerServer, buildScrubbedChildEnv } = await import('../src/credential-broker.ts');
    const { createServer } = await import('node:http');

    // 1. Universal pairing link -> redeem once -> revoke device
    const startRes = await requestJson<{ code: string; universalLink: string; hostId: string }>(
      baseUrl,
      '/api/v1/auth/pair/start',
      { method: 'POST', body: JSON.stringify({ scope: 'owner', relayOrigin: 'https://pipibot.jimizhou.com' }) },
    );
    assert.equal(startRes.status, 201);
    assert.ok(startRes.data.universalLink.startsWith(`https://pipibot.jimizhou.com/c/${startRes.data.hostId}#t=`));

    const pairRes = await requestJson<{ ok: boolean; token: string; deviceId: string }>(
      baseUrl,
      '/api/v1/auth/pair',
      { method: 'POST', body: JSON.stringify({ code: startRes.data.code, label: 'iPhone 17 Safari' }) },
    );
    assert.equal(pairRes.status, 200);
    assert.ok(pairRes.data.token.startsWith('pipi_dev_'));

    // Reusing one-time pairing code fails with 401
    const replayPair = await requestJson<{ error: string }>(baseUrl, '/api/v1/auth/pair', {
      method: 'POST',
      body: JSON.stringify({ code: startRes.data.code, label: 'Replay' }),
    });
    assert.equal(replayPair.status, 401);

    const revokeRes = await requestJson<{ ok: boolean; revoked: boolean }>(
      baseUrl,
      `/api/v1/auth/devices/${pairRes.data.deviceId}`,
      { method: 'DELETE' },
    );
    assert.equal(revokeRes.status, 200);
    assert.equal(revokeRes.data.revoked, true);

    // 2. Bounded stdio MCP server allows inspection, hard-blocks approvals/merge/delete/secrets
    const mcpList = await handleBoundedMCPRequest({ id: 1, method: 'tools/call', params: { name: 'pipibot_list_nodes', arguments: {} } }, baseUrl);
    assert.ok(!mcpList.error);
    const mcpBlocked = await handleBoundedMCPRequest({ id: 2, method: 'tools/call', params: { name: 'pipibot_approve_decision', arguments: {} } }, baseUrl);
    assert.equal(mcpBlocked.error?.code, -32003);
    assert.ok(mcpBlocked.error?.message.includes('FORBIDDEN_BOUNDED_MCP'));

    // HTTP scope guard also rejects mcp_bounded on privileged routes
    const scopeGuardRes = await fetch(`${baseUrl}/api/v1/worktrees/wt_fake/merge`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-PiPiBot-Scope': 'mcp_bounded' },
      body: JSON.stringify({}),
    });
    assert.equal(scopeGuardRes.status, 403);

    // 3. Sentinel zero-LLM clustering + recurrence >= 3 evolution proposal
    const sentRes = await requestJson<{ issues: Array<{ count: number; normalizedTitle: string; evolutionProposal?: { id: string } }> }>(
      baseUrl,
      '/api/v1/sentinel/samples',
      {
        method: 'POST',
        body: JSON.stringify({
          samples: [
            { id: 's1', kind: 'tool_error', toolName: 'read_file', rawMessage: 'ENOENT at /Users/jimizhou/a/f1.ts line 10' },
            { id: 's2', kind: 'tool_error', toolName: 'read_file', rawMessage: 'ENOENT at /Users/bob/b/f2.ts line 42' },
            { id: 's3', kind: 'tool_error', toolName: 'read_file', rawMessage: 'ENOENT at /Users/cat/c/f3.ts line 99' },
          ],
        }),
      },
    );
    assert.equal(sentRes.status, 200);
    assert.equal(sentRes.data.issues.length, 1);
    assert.equal(sentRes.data.issues[0]!.count, 3);
    assert.ok(sentRes.data.issues[0]!.evolutionProposal?.id);

    // 4. Portable template preview & apply (redacts secrets + pauses routines)
    const tplRes = await requestJson<{ applied: boolean; template: { redactedCount: number; bots: unknown[]; routines: Array<{ enabled: boolean }> } }>(
      baseUrl,
      '/api/v1/templates/apply',
      {
        method: 'POST',
        body: JSON.stringify({
          markdown: `---\nscope: team\nname: "Release Ops"\nbots:\n  - slug: ops\n    name: "Ops Bot"\n    role: "Use sk-1234567890abcdefghij at /Users/jimizhou/repo"\nroutines:\n  - title: "Nightly"\n    bot: ops\n    trigger: schedule\n    cron: "0 2 * * *"\n---\n## Bot: Ops Bot\nVerify before shipping.`,
        }),
      },
    );
    assert.equal(tplRes.status, 201);
    assert.ok(tplRes.data.template.redactedCount >= 2);
    assert.equal(tplRes.data.template.routines[0]!.enabled, false);

    // 5. Three-tier fast group auto-router
    const routeRes = await requestJson<{ decision: { tier: string; picks: Array<{ botId: string }> } }>(
      baseUrl,
      '/api/v1/groups/route',
      {
        method: 'POST',
        body: JSON.stringify({
          message: 'Please fix the swift build regression',
          leadBotId: 'lead',
          candidates: [
            { id: 'lead', name: 'PiPi', role: 'Lead', keywords: ['plan'] },
            { id: 'coder', name: 'Coder', role: 'Engineer', keywords: ['swift', 'build', 'regression'] },
          ],
        }),
      },
    );
    assert.equal(routeRes.status, 200);
    assert.equal(routeRes.data.decision.tier, 'deterministic_rule');
    assert.equal(routeRes.data.decision.picks[0]!.botId, 'coder');

    // 6. Live Credential Broker secret injection & revocation
    let seenAuth = '';
    const mockUpstream = createServer((req, res) => {
      seenAuth = String(req.headers.authorization ?? '');
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ upstreamOk: true }));
    });
    await new Promise<void>((resolve) => mockUpstream.listen(0, '127.0.0.1', () => resolve()));
    const upPort = (mockUpstream.address() as { port: number }).port;
    const broker = new PipiCredentialBrokerServer();
    try {
      const lease = await broker.issueLease({
        provider: 'openai',
        upstreamBaseUrl: `http://127.0.0.1:${upPort}`,
        realSecret: 'sk-live-secret-hidden',
      });
      const childEnv = buildScrubbedChildEnv({ PATH: '/usr/bin', ANTHROPIC_API_KEY: 'sk-ant-leak', PIPIBOT_HUB_TOKEN: 'hub-secret' }, [lease]);
      assert.equal(childEnv.OPENAI_API_KEY, lease.token);
      assert.equal(childEnv.ANTHROPIC_API_KEY, undefined);
      assert.equal(childEnv.PIPIBOT_HUB_TOKEN, undefined);

      const proxyRes = await fetch(`${lease.proxyBaseUrl}/v1/models`, {
        headers: { Authorization: `Bearer ${lease.token}` },
      });
      assert.equal(proxyRes.status, 200);
      assert.equal(seenAuth, 'Bearer sk-live-secret-hidden');

      broker.revokeLease(lease.token);
      const afterRevoke = await fetch(`${lease.proxyBaseUrl}/v1/models`);
      assert.equal(afterRevoke.status, 401);
    } finally {
      await broker.stop();
      await new Promise<void>((resolve) => mockUpstream.close(() => resolve()));
    }

    // 7. Live Bot Box OS-level self-check probe
    const boxRes = await requestJson<{ backend: string; allPassed: boolean; passedCount: number }>(
      baseUrl,
      '/api/v1/security/box-check',
    );
    assert.equal(boxRes.status, 200);
    assert.equal(boxRes.data.allPassed, true);

    // 8. Unified 5-Tab Mobile PWA served directly from Daemon Hub
    const mobileRes = await fetch(`${baseUrl}/mobile`);
    assert.equal(mobileRes.status, 200);
    const mobileHtml = await mobileRes.text();
    assert.ok(mobileHtml.includes('E2EERelayTransport') && mobileHtml.includes('PiPiBot'));
  });
});
