/**
 * @pipibot/daemon - server.ts
 *
 * `PipiResidentServer`: Zero-external-dependency `node:http` REST + 250ms SSE API
 * for the V1 macOS Always-On Resident Daemon (`0.2.0-beta`), uniting:
 * - `@pipibot/core` (`PipiHarnessRouter`, `RoutedMcpBridge`, `PipiMemoryEngine`, `PipiEvolutionLoop`)
 * - `PipiOutcomeEngine` (Devin-style Outcome Responsibilities & Needs-You Inbox)
 * - `PipiCueSensor` & `PipiFleetManager` (Manus Cue + live `node:os` + Multi-Node Dots + Cloudflare Tunnel)
 * - Static hosting for `/design-system/*` and `/ios` (`apps/ios-web/*`)
 */

import { randomUUID } from 'node:crypto';
import { readFile, stat, statfs } from 'node:fs/promises';
import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import * as os from 'node:os';
import { extname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

import type {
  AvatarExpression9,
  AvatarState53,
  ByokProviderConfig,
  EvolutionSummary,
  FleetNodeTelemetry,
  HarnessActivityPulse,
  HarnessProbeResult,
  HarnessProvider,
  MemoryDomain,
  OutcomeDomain,
  OutcomeStatus,
} from '../../protocol/src/index.ts';
import {
  ACTIVITY_PULSE_INTERVAL_MS,
  AtomicTranscriptStore,
  PipiHarnessRouter,
  RoutedMcpBridge,
  detectLocalHarnesses,
  type HarnessDriver,
} from '../../core/src/harness-router.ts';
import { PipiEvolutionLoop, PipiMemoryEngine } from '../../core/src/memory-engine.ts';
import { PipiCueSensor, PipiFleetManager } from './cue-fleet-sensor.ts';
import { PipiOutcomeEngine } from './outcome-engine.ts';

export const DAEMON_VERSION = '0.2.0-beta' as const;
export const DEFAULT_DAEMON_PORT = 4242;

export interface PipiResidentServerOptions {
  host?: string;
  port?: number;
  repoRoot?: string;
  dataDir?: string;
  workspacePath?: string;
  byokConfigs?: ByokProviderConfig[];
  pulseIntervalMs?: number;
  seedMemoryIfEmpty?: boolean;
  seedDefaults?: boolean;
  seedFleet?: boolean;
}

const MIME_TYPES: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.txt': 'text/plain; charset=utf-8',
};

function expressionForAvatarState(state: AvatarState53): AvatarExpression9 {
  if (state === 'needs-you' || state === 'needs-you-urgent' || state === 'fleet-degraded') return 'alert';
  if (state === 'manus-cue' || state === 'memory-recall' || state === 'thinking') return 'curious';
  if (state === 'evolving' || state === 'skill-synthesizing') return 'evolving';
  if (state === 'sleeping' || state === 'dreaming-consolidating') return 'sleepy';
  if (state === 'evolution-proud' || state === 'synthesizing' || state === 'git-committing') return 'proud';
  if (state === 'byok-streaming' || state === 'voice-interrupted') return 'listening';
  if (
    state === 'pi-coding' ||
    state === 'pi-bash-running' ||
    state === 'claude-routing' ||
    state === 'codex-routing' ||
    state === 'opencode-routing' ||
    state === 'mcp-bridging' ||
    state === 'deep-reasoning'
  ) {
    return 'focused';
  }
  return 'neutral';
}

function createSimulatedFallbackDrivers(): Record<HarnessProvider, HarnessDriver> {
  const makeDriver = (provider: HarnessProvider): HarnessDriver => ({
    provider,
    async execute(ctx) {
      ctx.pulse.update({ phase: 'recalling_memory' });
      const recallResult = await ctx.mcpBridge.executeRoutedMcpTool(
        'pipibot_memory_recall',
        { query: ctx.request.prompt.slice(0, 120), limit: 4 },
        {
          sessionId: ctx.request.sessionId,
          subSessionId: ctx.request.subSessionId,
          provider,
          workspacePath: ctx.request.workspacePath,
        },
      );
      ctx.pulse.update({ phase: 'streaming_model', addTokens: 48 });

      const modelId =
        ctx.request.modelId ??
        ctx.request.byokConfig?.modelId ??
        (provider === 'pi'
          ? 'pi-core-4tool'
          : provider === 'claude-code'
            ? 'claude-sonnet-4-5'
            : provider === 'codex'
              ? 'gpt-5-codex'
              : provider === 'opencode'
                ? 'opencode-acp'
                : 'byok-openrouter');

      const recallPreview = recallResult.content[0]?.text ?? '{}';
      const reply = [
        `[${provider} · ${modelId}] Processed turn via PipiHarnessRouter + RoutedMcpBridge.`,
        `Prompt: "${ctx.request.prompt.slice(0, 140)}"`,
        `Memory Bridge Status: ${recallPreview.slice(0, 180)}`,
      ].join('\n');

      ctx.request.onEvent?.({ type: 'text_delta', delta: reply });
      return {
        text: reply,
        modelId,
        toolCallsExecuted: 1,
        usage: {
          inputTokens: Math.max(12, Math.ceil(ctx.compiledPrompt.length / 4)),
          outputTokens: Math.max(18, Math.ceil(reply.length / 4)),
          estimated: true,
        },
      };
    },
  });

  return {
    pi: makeDriver('pi'),
    'claude-code': makeDriver('claude-code'),
    codex: makeDriver('codex'),
    opencode: makeDriver('opencode'),
    byok: makeDriver('byok'),
  };
}

export class PipiResidentServer {
  readonly host: string;
  readonly requestedPort: number;
  readonly repoRoot: string;
  readonly dataDir: string;
  readonly workspacePath: string;
  readonly byokConfigs: ByokProviderConfig[];

  readonly memoryEngine: PipiMemoryEngine;
  readonly evolutionLoop: PipiEvolutionLoop;
  readonly transcriptStore: AtomicTranscriptStore;
  readonly mcpBridge: RoutedMcpBridge;
  readonly harnessRouter: PipiHarnessRouter;
  readonly localFallbackRouter: PipiHarnessRouter;
  readonly outcomeEngine: PipiOutcomeEngine;
  readonly cueSensor: PipiCueSensor;
  readonly fleetManager: PipiFleetManager;

  private server?: Server;
  private boundPort = 0;
  private startedAtMs = Date.now();
  private activeAvatarState: AvatarState53 = 'ambient-breathe';
  private activeAvatarExpression: AvatarExpression9 = 'happy';
  private cachedProbes: HarnessProbeResult[] = [];
  private sseClients = new Set<ServerResponse>();
  private pulseTimer?: ReturnType<typeof setInterval>;
  private pulseSeq = 0;
  private readonly pulseIntervalMs: number;
  private readonly seedMemoryIfEmpty: boolean;
  private defaultSessionId = 'pipibot-resident-main';

  constructor(options: PipiResidentServerOptions = {}) {
    this.host = options.host ?? '127.0.0.1';
    this.requestedPort = options.port ?? Number(process.env.PIPIBOT_PORT ?? DEFAULT_DAEMON_PORT);

    const moduleDir = fileURLToPath(new URL('.', import.meta.url));
    this.repoRoot = resolve(options.repoRoot ?? join(moduleDir, '..', '..', '..'));
    this.dataDir = options.dataDir ?? join(os.homedir(), '.pipibot');
    this.workspacePath = options.workspacePath ?? this.repoRoot;
    this.byokConfigs = options.byokConfigs ?? [];
    this.pulseIntervalMs = options.pulseIntervalMs ?? ACTIVITY_PULSE_INTERVAL_MS;
    this.seedMemoryIfEmpty = options.seedMemoryIfEmpty !== false;

    this.memoryEngine = new PipiMemoryEngine({ rootDir: this.dataDir });
    this.evolutionLoop = new PipiEvolutionLoop(this.memoryEngine);
    this.transcriptStore = new AtomicTranscriptStore(join(this.dataDir, 'transcripts'));
    this.mcpBridge = new RoutedMcpBridge();

    // Wire real memory recall into RoutedMcpBridge
    this.mcpBridge.registerTool(
      {
        name: 'pipibot_memory_recall',
        description:
          'Recall relevant L1 episodic memories, L2 user persona facts, and L3 Pi skills using 4D salience scoring.',
        inputSchema: {
          type: 'object',
          properties: {
            query: { type: 'string', description: 'Semantic or keyword search query' },
            domain: {
              type: 'string',
              enum: ['coding_convention', 'communication_pref', 'daily_life', 'work_context', 'infra_topology'],
            },
            limit: { type: 'number', description: 'Maximum items to return' },
          },
          required: ['query'],
          additionalProperties: false,
        },
        readOnlyHint: true,
      },
      async (args) => {
        const result = await this.memoryEngine.recall({
          query: String(args.query ?? ''),
          domain: args.domain as MemoryDomain | undefined,
          limit: typeof args.limit === 'number' ? args.limit : 6,
        });
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({
                status: 'ok',
                episodicCount: result.episodic.length,
                factCount: result.facts.length,
                skillCount: result.skills.length,
                topMemories: result.episodic.slice(0, 3).map((e) => ({ id: e.id, title: e.title, domain: e.domain })),
              }),
            },
          ],
        };
      },
    );

    this.harnessRouter = new PipiHarnessRouter({
      transcriptStore: this.transcriptStore,
      mcpBridge: this.mcpBridge,
    });

    this.localFallbackRouter = new PipiHarnessRouter({
      transcriptStore: this.transcriptStore,
      mcpBridge: this.mcpBridge,
      drivers: createSimulatedFallbackDrivers(),
    });

    this.outcomeEngine = new PipiOutcomeEngine({ seedDefaults: options.seedDefaults !== false });
    this.cueSensor = new PipiCueSensor({ memory: this.memoryEngine, workspacePath: this.workspacePath });
    this.fleetManager = new PipiFleetManager({ memory: this.memoryEngine, seedFleet: options.seedFleet !== false });

    this.outcomeEngine.onEvent((evt) => {
      if (evt.type === 'decision.needs_you') {
        this.setAvatarState('needs-you');
      } else if (evt.type === 'decision.resolved') {
        this.setAvatarState('evolution-proud');
      }
      this.broadcastSse(evt.type, evt.payload);
    });

    this.cueSensor.onEvent((evt) => {
      if (evt.type === 'cue.suggestion') {
        this.setAvatarState('manus-cue');
      }
      this.broadcastSse(evt.type, evt.payload);
    });

    this.fleetManager.onEvent((evt) => {
      this.broadcastSse(evt.type, evt.payload);
    });
  }

  get port(): number {
    return this.boundPort;
  }

  get baseUrl(): string {
    return `http://${this.host}:${this.boundPort}`;
  }

  setAvatarState(state: AvatarState53): void {
    this.activeAvatarState = state;
    this.activeAvatarExpression = expressionForAvatarState(state);
  }

  async start(): Promise<string> {
    if (this.server) return this.baseUrl;
    this.startedAtMs = Date.now();

    await this.memoryEngine.init();
    if (this.seedMemoryIfEmpty) {
      await this.seedInitialCognitiveMemory();
    }
    await this.cueSensor.captureCue({
      activeAppName: 'PipiBot Studio',
      windowTitle: 'pipibot (main)',
      workspacePath: this.workspacePath,
    });
    this.cachedProbes = await detectLocalHarnesses(this.byokConfigs);
    this.fleetManager.refreshLocalMacTelemetrySync(
      this.cachedProbes.filter((p) => p.installed).map((p) => p.provider),
    );
    await this.fleetManager.refreshCloudflareProbe();

    this.server = createServer((req, res) => {
      void this.handleRequest(req, res);
    });

    await new Promise<void>((resolveListen, rejectListen) => {
      this.server!.once('error', rejectListen);
      this.server!.listen(this.requestedPort, this.host, () => {
        const addr = this.server!.address();
        if (addr && typeof addr === 'object') {
          this.boundPort = addr.port;
        }
        resolveListen();
      });
    });

    return this.baseUrl;
  }

  async stop(): Promise<void> {
    if (this.pulseTimer) {
      clearInterval(this.pulseTimer);
      this.pulseTimer = undefined;
    }
    for (const client of this.sseClients) {
      client.end();
    }
    this.sseClients.clear();
    await this.mcpBridge.stop();

    if (this.server) {
      await new Promise<void>((resolveClose) => {
        this.server!.close(() => resolveClose());
      });
      this.server = undefined;
    }
    this.boundPort = 0;
  }

  // -------------------------------------------------------------------------
  // SSE Event Broadcasting & 250ms Activity Pulse
  // -------------------------------------------------------------------------

  private ensurePulseHeartbeat(): void {
    if (this.pulseTimer || this.sseClients.size === 0) return;
    this.pulseTimer = setInterval(() => {
      if (this.sseClients.size === 0) {
        if (this.pulseTimer) {
          clearInterval(this.pulseTimer);
          this.pulseTimer = undefined;
        }
        return;
      }
      this.emitActivityPulse('pi', 'initializing');
    }, this.pulseIntervalMs);

    if (typeof this.pulseTimer.unref === 'function') {
      this.pulseTimer.unref();
    }
  }

  private emitActivityPulse(
    provider: HarnessProvider,
    phase: HarnessActivityPulse['phase'],
    activeToolName?: string,
  ): void {
    this.pulseSeq += 1;
    const pulse: HarnessActivityPulse = {
      sessionId: this.defaultSessionId,
      provider,
      phase,
      pulseIntervalMs: ACTIVITY_PULSE_INTERVAL_MS,
      seq: this.pulseSeq,
      elapsedMs: Date.now() - this.startedAtMs,
      activeToolName,
      tokensEstimated: 0,
      suggestedAvatarState: this.activeAvatarState,
      timestamp: new Date().toISOString(),
    };
    this.broadcastSse('harness.pulse', pulse);
  }

  private broadcastSse(eventType: string, payload: unknown): void {
    if (this.sseClients.size === 0) return;
    const wire = `event: ${eventType}\ndata: ${JSON.stringify(payload)}\n\n`;
    for (const client of this.sseClients) {
      try {
        client.write(wire);
      } catch {
        this.sseClients.delete(client);
      }
    }
  }

  // -------------------------------------------------------------------------
  // HTTP Router
  // -------------------------------------------------------------------------

  private async handleRequest(req: IncomingMessage, res: ServerResponse): Promise<void> {
    const method = req.method ?? 'GET';
    const rawTarget = (req.url ?? '/').split('?')[0] ?? '/';
    if (/(?:^|\/)(?:\.\.|%2e%2e|%2e\.|\.%2e)(?:\/|$)/i.test(rawTarget)) {
      this.sendJson(res, 403, { error: 'Forbidden path traversal' });
      return;
    }

    const reqUrl = new URL(req.url ?? '/', `http://${req.headers.host ?? `${this.host}:${this.boundPort}`}`);
    const pathname = reqUrl.pathname;

    if (method === 'OPTIONS') {
      res.writeHead(204, this.corsHeaders());
      res.end();
      return;
    }

    try {
      // Discovery index
      if (method === 'GET' && pathname === '/') {
        this.sendJson(res, 200, {
          name: 'pipibot-daemon',
          version: DAEMON_VERSION,
          status: 'ok',
          endpoints: {
            status: '/api/v1/status',
            events: '/api/v1/events',
            outcomes: '/api/v1/outcomes',
            decisions: '/api/v1/decisions',
            cue: '/api/v1/cue',
            fleet: '/api/v1/fleet',
            chat: '/api/v1/chat/turn',
            memory: '/api/v1/memory',
            launchdPlist: '/api/v1/launchd-plist',
            resources: '/api/v1/resources',
            designSystem: '/design-system/',
            iosCompanion: '/ios/',
          },
        });
        return;
      }

      // SSE Events
      if (method === 'GET' && pathname === '/api/v1/events') {
        this.handleSseConnection(req, res);
        return;
      }

      // Status
      if (method === 'GET' && pathname === '/api/v1/status') {
        const previousOverall =
          this.memoryEngine.getLastEvolutionSummary()?.understandingScore.overall ?? 72;
        const understandingScore = this.evolutionLoop.computeUnderstandingScore(previousOverall);
        const nodes = this.fleetManager.getNodes();
        const decisions = this.outcomeEngine.listDecisions('pending');
        const outcomes = this.outcomeEngine.listOutcomes();
        const subSessions = this.outcomeEngine.listSubSessions();

        this.sendJson(res, 200, {
          version: DAEMON_VERSION,
          uptimeSeconds: Number(((Date.now() - this.startedAtMs) / 1000).toFixed(2)),
          avatarState: this.activeAvatarState,
          avatarExpression: this.activeAvatarExpression,
          harnesses: this.cachedProbes,
          cloudflare: this.fleetManager.getCloudflareTunnelStatus(),
          understandingScore,
          counts: {
            outcomes: outcomes.length,
            pendingDecisions: decisions.length,
            activeSubSessions: subSessions.filter(
              (s) => s.status === 'running' || s.status === 'waiting_tool' || s.status === 'needs_you',
            ).length,
            fleetOnline: nodes.filter((n) => n.vitality === 'alive' || n.vitality === 'busy').length,
          },
        });
        return;
      }

      if (method === 'GET' && pathname === '/api/v1/resources') {
        this.sendJson(res, 200, await this.readResourceSnapshot());
        return;
      }

      // Outcomes
      if (method === 'GET' && pathname === '/api/v1/outcomes') {
        this.sendJson(res, 200, {
          outcomes: this.outcomeEngine.listOutcomes(),
          subSessions: this.outcomeEngine.listSubSessions(),
        });
        return;
      }

      if (method === 'POST' && pathname === '/api/v1/outcomes') {
        const body = await this.readJsonBody<{
          title?: string;
          domain?: OutcomeDomain;
          goal?: string;
          constraints?: string[];
          successMetrics?: string[];
          preferredHarness?: HarnessProvider;
          dailyBudgetUsd?: number;
        }>(req);

        if (!body.title || !body.goal) {
          this.sendJson(res, 400, { error: 'title and goal are required' });
          return;
        }
        const outcome = this.outcomeEngine.createOutcome({
          title: body.title,
          domain: body.domain ?? 'dev',
          goal: body.goal,
          constraints: body.constraints,
          successMetrics: body.successMetrics,
          preferredHarness: body.preferredHarness,
          dailyBudgetUsd: body.dailyBudgetUsd,
        });
        this.sendJson(res, 201, { outcome });
        return;
      }

      const evalMatch = pathname.match(/^\/api\/v1\/outcomes\/([^/]+)\/evaluate$/);
      if (method === 'POST' && evalMatch?.[1]) {
        const body = await this.readJsonBody<{
          requireHumanSignOff?: boolean;
          useLiveHarness?: boolean;
        }>(req);
        this.setAvatarState('plan-structuring');
        const evalRes = await this.outcomeEngine.evaluateOutcome(decodeURIComponent(evalMatch[1]), {
          triggerKind: 'manual',
          workspacePath: this.workspacePath,
          useLiveHarness: Boolean(body.useLiveHarness),
          harnessRouter: this.harnessRouter,
          requireHumanSignOff: Boolean(body.requireHumanSignOff),
        });
        if (!evalRes) {
          this.sendJson(res, 404, { error: 'Outcome not found' });
          return;
        }
        this.setAvatarState(evalRes.createdDecision ? 'needs-you' : 'synthesizing');
        this.sendJson(res, 200, evalRes);
        return;
      }

      const statusMatch = pathname.match(/^\/api\/v1\/outcomes\/([^/]+)\/status$/);
      if (method === 'POST' && statusMatch?.[1]) {
        const body = await this.readJsonBody<{ status?: OutcomeStatus }>(req);
        if (!body.status) {
          this.sendJson(res, 400, { error: 'status is required' });
          return;
        }
        const updated = this.outcomeEngine.updateOutcomeStatus(decodeURIComponent(statusMatch[1]), body.status);
        if (!updated) {
          this.sendJson(res, 404, { error: 'Outcome not found' });
          return;
        }
        this.sendJson(res, 200, { outcome: updated });
        return;
      }

      // Decisions (Needs You Inbox)
      if (method === 'GET' && pathname === '/api/v1/decisions') {
        const statusParam = reqUrl.searchParams.get('status') as 'pending' | 'resolved' | 'expired' | 'all' | null;
        const decisions = this.outcomeEngine.listDecisions(statusParam ?? 'all');
        this.sendJson(res, 200, {
          decisions,
          pendingCount: decisions.filter((d) => d.status === 'pending').length,
        });
        return;
      }

      const resolveDecMatch = pathname.match(/^\/api\/v1\/decisions\/([^/]+)\/resolve$/);
      if (method === 'POST' && resolveDecMatch?.[1]) {
        const body = await this.readJsonBody<{
          chosenOptionId?: string;
          userNote?: string;
          resolvedBy?: string;
        }>(req);
        if (!body.chosenOptionId) {
          this.sendJson(res, 400, { error: 'chosenOptionId is required' });
          return;
        }
        const resolved = this.outcomeEngine.resolveDecision(decodeURIComponent(resolveDecMatch[1]), {
          chosenOptionId: body.chosenOptionId,
          userNote: body.userNote,
          resolvedBy: body.resolvedBy,
        });
        if (!resolved) {
          this.sendJson(res, 404, { error: 'Decision not found' });
          return;
        }
        this.sendJson(res, 200, { decision: resolved });
        return;
      }

      // Manus Cue
      if (method === 'GET' && pathname === '/api/v1/cue') {
        this.sendJson(res, 200, {
          latest: this.cueSensor.getLatestCue() ?? null,
          cues: this.cueSensor.listCues(),
        });
        return;
      }

      if (method === 'POST' && pathname === '/api/v1/cue/refresh') {
        const body = await this.readJsonBody<{
          activeAppName?: string;
          activeAppBundleId?: string;
          windowTitle?: string;
          workspacePath?: string;
          gitBranch?: string;
        }>(req);
        const cue = await this.cueSensor.captureCue(body);
        this.sendJson(res, 200, { cue });
        return;
      }

      const cueExecMatch = pathname.match(/^\/api\/v1\/cue\/([^/]+)\/execute$/);
      if (method === 'POST' && cueExecMatch?.[1]) {
        const cueId = decodeURIComponent(cueExecMatch[1]);
        const body = await this.readJsonBody<{ actionId?: string }>(req);
        const cue = this.cueSensor.listCues().find((c) => c.id === cueId);
        if (!cue) {
          this.sendJson(res, 404, { error: 'Cue not found' });
          return;
        }
        const action = cue.actions.find((a) => a.id === body.actionId) ?? cue.actions[0];
        if (!action) {
          this.sendJson(res, 400, { error: 'No action available for this cue' });
          return;
        }
        await this.cueSensor.recordFeedback(cueId, 'accepted', action.label);
        const turnResult = await this.executeChatTurn({
          prompt: action.promptTemplate,
          provider: action.harness,
          sessionId: this.defaultSessionId,
          useLiveHarness: false,
        });
        this.sendJson(res, 200, {
          cue,
          action,
          executed: true,
          turnResult,
        });
        return;
      }

      const cueFeedbackMatch = pathname.match(/^\/api\/v1\/cue\/([^/]+)\/feedback$/);
      if (method === 'POST' && cueFeedbackMatch?.[1]) {
        const body = await this.readJsonBody<{
          feedback?: 'accepted' | 'dismissed' | 'ignored';
          actionLabel?: string;
        }>(req);
        if (!body.feedback) {
          this.sendJson(res, 400, { error: 'feedback is required' });
          return;
        }
        const cue = await this.cueSensor.recordFeedback(
          decodeURIComponent(cueFeedbackMatch[1]),
          body.feedback,
          body.actionLabel,
        );
        if (!cue) {
          this.sendJson(res, 404, { error: 'Cue not found' });
          return;
        }
        this.sendJson(res, 200, { cue });
        return;
      }

      // PipiFleet
      if (method === 'GET' && pathname === '/api/v1/fleet') {
        this.sendJson(res, 200, {
          nodes: this.fleetManager.getNodes(),
          cloudflare: this.fleetManager.getCloudflareTunnelStatus(),
        });
        return;
      }

      if (method === 'POST' && pathname === '/api/v1/fleet/heartbeat') {
        const body = await this.readJsonBody<Partial<FleetNodeTelemetry> & { nodeId?: string }>(req);
        if (!body.nodeId) {
          this.sendJson(res, 400, { error: 'nodeId is required' });
          return;
        }
        const node = this.fleetManager.ingestHeartbeat({ ...body, nodeId: body.nodeId });
        this.sendJson(res, 200, { node });
        return;
      }

      // Multi-Harness Chat
      if (method === 'GET' && pathname === '/api/v1/chat/transcript') {
        const sessionId = reqUrl.searchParams.get('sessionId') ?? this.defaultSessionId;
        const entries = await this.transcriptStore.loadEntries(sessionId);
        const manifest = await this.transcriptStore.loadManifest(sessionId);
        this.sendJson(res, 200, { sessionId, entries, manifest });
        return;
      }

      if (method === 'POST' && pathname === '/api/v1/chat/turn') {
        const body = await this.readJsonBody<{
          prompt?: string;
          sessionId?: string;
          provider?: HarnessProvider;
          modelId?: string;
          byokConfig?: ByokProviderConfig;
          useLiveHarness?: boolean;
        }>(req);
        if (!body.prompt || body.prompt.trim().length === 0) {
          this.sendJson(res, 400, { error: 'prompt is required' });
          return;
        }
        const result = await this.executeChatTurn({
          prompt: body.prompt,
          sessionId: body.sessionId ?? this.defaultSessionId,
          provider: body.provider ?? 'pi',
          modelId: body.modelId,
          byokConfig: body.byokConfig,
          useLiveHarness: Boolean(body.useLiveHarness),
        });
        this.sendJson(res, 200, result);
        return;
      }

      // Cognitive Memory & Self-Evolution
      if (method === 'GET' && pathname === '/api/v1/memory') {
        await this.memoryEngine.init();
        const lastDigest = this.memoryEngine.getLastEvolutionSummary() ?? null;
        const previousOverall = lastDigest?.understandingScore.overall ?? 72;
        this.sendJson(res, 200, {
          episodic: this.memoryEngine.getEpisodicEvents().slice(-30).reverse(),
          facts: this.memoryEngine.getPersonaFacts(),
          skills: this.memoryEngine.getSynthesizedSkills(),
          lastDigest,
          understandingScore: this.evolutionLoop.computeUnderstandingScore(previousOverall),
        });
        return;
      }

      if (method === 'POST' && pathname === '/api/v1/memory/search') {
        const body = await this.readJsonBody<{
          query?: string;
          domain?: MemoryDomain;
          limit?: number;
        }>(req);
        if (!body.query) {
          this.sendJson(res, 400, { error: 'query is required' });
          return;
        }
        this.setAvatarState('memory-recall');
        const result = await this.memoryEngine.recall({
          query: body.query,
          domain: body.domain,
          limit: body.limit ?? 8,
        });
        this.sendJson(res, 200, result);
        return;
      }

      if (method === 'POST' && pathname === '/api/v1/memory/dream') {
        this.setAvatarState('dreaming-consolidating');
        const summary = await this.evolutionLoop.runNightlyDreamingCycle({ cycle: 'nightly_dreaming' });
        this.setAvatarState(summary.requiresUserReviewCount > 0 ? 'persona-updating' : 'evolution-proud');
        this.broadcastSse('evolution.digest_ready', summary);
        this.sendJson(res, 200, { summary });
        return;
      }

      const diffReviewMatch = pathname.match(/^\/api\/v1\/memory\/diffs\/([^/]+)\/review$/);
      if (method === 'POST' && diffReviewMatch?.[1]) {
        const body = await this.readJsonBody<{
          action?: 'approve' | 'edit' | 'revert';
          editedValue?: string;
        }>(req);
        if (!body.action) {
          this.sendJson(res, 400, { error: 'action is required' });
          return;
        }
        const current = this.memoryEngine.getLastEvolutionSummary();
        if (!current) {
          this.sendJson(res, 404, { error: 'No EvolutionSummary available yet; run /api/v1/memory/dream first.' });
          return;
        }
        const updated: EvolutionSummary = await this.evolutionLoop.applyEvolutionDecision(
          current,
          decodeURIComponent(diffReviewMatch[1]),
          body.action,
          body.editedValue,
        );
        this.setAvatarState(body.action === 'revert' ? 'memory-pruning' : 'evolution-proud');
        this.broadcastSse('evolution.digest_ready', updated);
        this.sendJson(res, 200, { summary: updated });
        return;
      }

      if (method === 'GET' && pathname === '/api/v1/memory/soul') {
        const paths = await this.memoryEngine.syncPersonaMarkdownFiles();
        const [soulMd, userMd, memoryMd] = await Promise.all([
          readFile(paths.soulMdPath, 'utf8'),
          readFile(paths.userMdPath, 'utf8'),
          readFile(paths.memoryMdPath, 'utf8'),
        ]);
        this.sendJson(res, 200, {
          paths,
          soulMd,
          userMd,
          memoryMd,
        });
        return;
      }

      // macOS launchd plist generator
      if (method === 'GET' && pathname === '/api/v1/launchd-plist') {
        const plistXml = this.buildLaunchdPlist();
        if (reqUrl.searchParams.get('format') === 'json') {
          this.sendJson(res, 200, { label: 'ai.pipibot.daemon', plistXml });
          return;
        }
        res.writeHead(200, {
          ...this.corsHeaders(),
          'Content-Type': 'application/xml; charset=utf-8',
        });
        res.end(plistXml);
        return;
      }

      // Static routes: /design-system/* and /ios/*
      if (method === 'GET' && (pathname === '/design-system' || pathname.startsWith('/design-system/'))) {
        await this.serveStaticDirectory(res, join(this.repoRoot, 'design-system'), pathname.slice('/design-system'.length));
        return;
      }

      if (method === 'GET' && (pathname === '/ios' || pathname.startsWith('/ios/'))) {
        await this.serveStaticDirectory(res, join(this.repoRoot, 'apps', 'ios-web'), pathname.slice('/ios'.length));
        return;
      }

      this.sendJson(res, 404, { error: `Route not found: ${method} ${pathname}` });
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      this.sendJson(res, 500, { error: msg });
    }
  }

  private async readResourceSnapshot(): Promise<{
    sampledAt: string;
    cpu: { usagePercent: number; load1m: number; coreCount: number };
    memory: { totalBytes: number; usedBytes: number; usedPercent: number };
    disk: { path: string; totalBytes: number; availableBytes: number; usedPercent: number };
  }> {
    const totalMemory = os.totalmem();
    const freeMemory = os.freemem();
    const coreCount = Math.max(1, os.cpus().length);
    const load1m = os.loadavg()[0] ?? 0;
    const usagePercent = Math.min(100, Math.max(0, (load1m / coreCount) * 100));
    const disk = await statfs(this.workspacePath);
    const totalBytes = Number(disk.blocks) * Number(disk.bsize);
    const availableBytes = Number(disk.bavail) * Number(disk.bsize);
    const usedBytes = Math.max(0, totalBytes - availableBytes);

    return {
      sampledAt: new Date().toISOString(),
      cpu: {
        usagePercent: Number(usagePercent.toFixed(1)),
        load1m: Number(load1m.toFixed(2)),
        coreCount,
      },
      memory: {
        totalBytes: totalMemory,
        usedBytes: totalMemory - freeMemory,
        usedPercent: Number((((totalMemory - freeMemory) / totalMemory) * 100).toFixed(1)),
      },
      disk: {
        path: this.workspacePath,
        totalBytes,
        availableBytes,
        usedPercent: totalBytes > 0 ? Number(((usedBytes / totalBytes) * 100).toFixed(1)) : 0,
      },
    };
  }

  private async executeChatTurn(params: {
    prompt: string;
    sessionId: string;
    provider: HarnessProvider;
    modelId?: string;
    byokConfig?: ByokProviderConfig;
    useLiveHarness: boolean;
  }) {
    this.setAvatarState('memory-recall');
    const recall = await this.memoryEngine.recall({ query: params.prompt, limit: 5 });

    const router = params.useLiveHarness ? this.harnessRouter : this.localFallbackRouter;
    const result = await router.runTurn({
      sessionId: params.sessionId,
      prompt: params.prompt,
      memoryContextBlock: recall.promptContextBlock,
      workspacePath: this.workspacePath,
      preferredProvider: params.provider,
      fallbackProviders: params.useLiveHarness ? ['byok', 'pi'] : undefined,
      modelId: params.modelId,
      byokConfig: params.byokConfig,
      onPulse: (pulse) => {
        this.setAvatarState(pulse.suggestedAvatarState);
        this.broadcastSse('harness.pulse', pulse);
      },
    });

    const reflection = await this.evolutionLoop.runMicroReflection({
      sessionId: params.sessionId,
      userPrompt: params.prompt,
      assistantResponse: result.text,
      harnessProvider: result.providerUsed,
      nodeId: 'mac-resident',
      toolSequence: result.toolCallsExecuted > 0 ? ['pipibot_memory_recall', `${result.providerUsed}:turn`] : undefined,
      outcomeSuccess: true,
    });

    this.setAvatarState(reflection.explicitPreferenceDetected ? 'evolving' : 'synthesizing');

    return {
      ...result,
      recalledCount: recall.episodic.length + recall.facts.length,
      reflection,
    };
  }

  private handleSseConnection(req: IncomingMessage, res: ServerResponse): void {
    res.writeHead(200, {
      ...this.corsHeaders(),
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
    });

    this.sseClients.add(res);
    res.write('retry: 2000\n');
    res.write(`event: connected\ndata: ${JSON.stringify({ version: DAEMON_VERSION, avatarState: this.activeAvatarState })}\n\n`);
    this.emitActivityPulse('pi', 'initializing');
    this.ensurePulseHeartbeat();

    req.on('close', () => {
      this.sseClients.delete(res);
      if (this.sseClients.size === 0 && this.pulseTimer) {
        clearInterval(this.pulseTimer);
        this.pulseTimer = undefined;
      }
    });
  }

  private async serveStaticDirectory(res: ServerResponse, rootDir: string, subPath: string): Promise<void> {
    let decodedSub = subPath;
    try {
      decodedSub = decodeURIComponent(subPath);
    } catch {
      this.sendJson(res, 400, { error: 'Malformed URI encoding' });
      return;
    }

    const cleanRel = decodedSub === '' || decodedSub === '/' ? 'index.html' : decodedSub.replace(/^\/+/, '');
    const resolvedRoot = resolve(rootDir);
    let filePath = resolve(resolvedRoot, cleanRel);
    if (filePath !== resolvedRoot && !filePath.startsWith(resolvedRoot + sep)) {
      this.sendJson(res, 403, { error: 'Forbidden path traversal' });
      return;
    }

    try {
      const info = await stat(filePath);
      if (info.isDirectory()) {
        filePath = resolve(filePath, 'index.html');
      }
      const bytes = await readFile(filePath);
      const mime = MIME_TYPES[extname(filePath).toLowerCase()] ?? 'application/octet-stream';
      res.writeHead(200, {
        ...this.corsHeaders(),
        'Content-Type': mime,
        'Cache-Control': 'no-cache',
      });
      res.end(bytes);
    } catch {
      this.sendJson(res, 404, { error: `Static asset not found: ${cleanRel}` });
    }
  }

  buildLaunchdPlist(portOverride?: number): string {
    const cliPath = join(this.repoRoot, 'packages', 'daemon', 'src', 'cli.ts');
    const logDir = join(this.dataDir, 'logs');
    const nodePath = process.execPath;
    const effectivePort = portOverride ?? (this.boundPort || this.requestedPort || DEFAULT_DAEMON_PORT);
    return [
      '<?xml version="1.0" encoding="UTF-8"?>',
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
      '<plist version="1.0">',
      '<dict>',
      '  <key>Label</key>',
      '  <string>ai.pipibot.daemon</string>',
      '  <key>ProgramArguments</key>',
      '  <array>',
      `    <string>${nodePath}</string>`,
      '    <string>--experimental-strip-types</string>',
      `    <string>${cliPath}</string>`,
      '    <string>--port</string>',
      `    <string>${effectivePort}</string>`,
      '  </array>',
      '  <key>WorkingDirectory</key>',
      `  <string>${this.repoRoot}</string>`,
      '  <key>RunAtLoad</key>',
      '  <true/>',
      '  <key>KeepAlive</key>',
      '  <true/>',
      '  <key>StandardOutPath</key>',
      `  <string>${join(logDir, 'pipibot-daemon.stdout.log')}</string>`,
      '  <key>StandardErrorPath</key>',
      `  <string>${join(logDir, 'pipibot-daemon.stderr.log')}</string>`,
      '</dict>',
      '</plist>',
      '',
    ].join('\n');
  }

  private async seedInitialCognitiveMemory(): Promise<void> {
    if (this.memoryEngine.getEpisodicEvents().length > 0) return;

    const e1 = await this.memoryEngine.appendEpisodic({
      domain: 'coding_convention',
      sourceKind: 'conversation_turn',
      title: 'Zero external runtime deps for TypeScript core & protocol',
      content: 'User prefers zero third-party runtime packages in @pipibot/protocol, @pipibot/core, and @pipibot/daemon so Node 22 strip-types runs directly.',
      toolSignature: 'read:package.json->edit:src/index.ts->bash:npm_verify',
      outcomeSuccess: true,
      importanceBase: 0.9,
      explicitSignal: true,
    });

    const e2 = await this.memoryEngine.appendEpisodic({
      domain: 'infra_topology',
      sourceKind: 'infra_event',
      title: 'Cloudflare Free-Tier Relay + HK VPS Nginx Keepalive',
      content: 'Use $0/month Cloudflare Tunnel + D1 + KV + R2 for Mac <-> iOS mesh; require Needs-You confirmation before reloading HK VPS Nginx.',
      toolSignature: 'fleet:vps-hk-01->read:nginx.conf->needs_you:reload',
      outcomeSuccess: true,
      importanceBase: 0.85,
      explicitSignal: true,
    });

    const e3 = await this.memoryEngine.appendEpisodic({
      domain: 'daily_life',
      sourceKind: 'life_log',
      title: 'Tue/Thu evening gym block & concise morning digest',
      content: 'Keep 19:30–21:00 Tue/Thu clear for gym; defer non-critical dev alerts to morning iOS Evolution Diff card.',
      outcomeSuccess: true,
      importanceBase: 0.8,
      explicitSignal: true,
    });

    await this.memoryEngine.upsertPersonaFact({
      subject: 'user',
      predicate: 'typescript_runtime',
      objectValue: 'Node >=22 (--experimental-strip-types) or Bun, zero external runtime dependencies',
      domain: 'coding_convention',
      confidence: 0.94,
      importance: 0.92,
      evidenceEventIds: [e1.id],
      explicitSignal: true,
    });

    await this.memoryEngine.upsertPersonaFact({
      subject: 'user',
      predicate: 'communication_style',
      objectValue: 'Direct technical conclusions + clickable diffs; ask Needs-You before destructive infra/git mutations',
      domain: 'communication_pref',
      confidence: 0.9,
      importance: 0.88,
      evidenceEventIds: [e1.id, e2.id],
      explicitSignal: true,
    });

    await this.memoryEngine.upsertPersonaFact({
      subject: 'user',
      predicate: 'evening_gym_schedule',
      objectValue: 'Tuesday & Thursday 19:30-21:00 quiet focus / gym window',
      domain: 'daily_life',
      confidence: 0.88,
      importance: 0.82,
      evidenceEventIds: [e3.id],
      explicitSignal: true,
    });

    await this.memoryEngine.upsertPersonaFact({
      subject: 'node:vps-hk-01',
      predicate: 'edge_topology',
      objectValue: 'HK Ubuntu 24.04 VPS + Docker/Nginx fronted by Cloudflare $0/mo Tunnel + Access',
      domain: 'infra_topology',
      confidence: 0.91,
      importance: 0.86,
      evidenceEventIds: [e2.id],
      explicitSignal: true,
    });

    await this.memoryEngine.upsertPersonaFact({
      subject: 'repo:pipibot',
      predicate: 'design_governance',
      objectValue: 'OpenPencil 5-rule system, 3-tier tokens, 6 canonical blocks, zero raw hex in views',
      domain: 'work_context',
      confidence: 0.9,
      importance: 0.88,
      evidenceEventIds: [e1.id],
      explicitSignal: true,
    });

    await this.memoryEngine.appendEpisodic({
      domain: 'work_context',
      sourceKind: 'conversation_turn',
      title: 'Candidate insight: automate weekly design audit on pre-push',
      content: 'Observed repeated check of audit-design-system before commits.',
      importanceBase: 0.65,
      explicitSignal: false,
    });

    await this.memoryEngine.upsertPersonaFact({
      subject: 'repo:pipibot',
      predicate: 'pre_push_audit_habit',
      objectValue: 'Run audit-design-system and npm run verify before pushing to GitHub',
      domain: 'work_context',
      confidence: 0.6,
      importance: 0.72,
      evidenceEventIds: [e1.id],
      explicitSignal: false,
    });

    await this.evolutionLoop.runNightlyDreamingCycle({ cycle: 'nightly_dreaming' });
  }

  private corsHeaders(): Record<string, string> {
    return {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };
  }

  private sendJson(res: ServerResponse, status: number, payload: unknown): void {
    res.writeHead(status, {
      ...this.corsHeaders(),
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
    });
    res.end(JSON.stringify(payload));
  }

  private async readJsonBody<T>(req: IncomingMessage): Promise<T> {
    const chunks: Buffer[] = [];
    for await (const chunk of req) {
      chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk as Uint8Array));
    }
    const raw = Buffer.concat(chunks).toString('utf8').trim();
    if (!raw) return {} as T;
    return JSON.parse(raw) as T;
  }
}

export function createResidentServer(options: PipiResidentServerOptions = {}): PipiResidentServer {
  return new PipiResidentServer(options);
}
