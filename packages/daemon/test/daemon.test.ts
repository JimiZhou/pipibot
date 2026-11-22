/**
 * @pipibot/daemon integration test suite (`node:test` + `node:assert/strict`)
 */

import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { get as httpGet } from 'node:http';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { after, before, describe, test } from 'node:test';
import { fileURLToPath } from 'node:url';

import { parseCliArgs } from '../src/cli.ts';
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
});
