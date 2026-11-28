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

import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { readFile, stat, statfs } from 'node:fs/promises';
import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import * as os from 'node:os';
import { extname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

import type {
  AvatarExpression9,
  AvatarState53,
  BoardActorKind,
  BoardActorRef,
  BoardTaskPriority,
  BoardTaskStatus,
  BoardThreadKind,
  ByokProviderConfig,
  EvolutionSummary,
  FleetNodeTelemetry,
  HarnessActivityPulse,
  HarnessProbeResult,
  HarnessProvider,
  MemoryDomain,
  OutcomeDomain,
  OutcomeStatus,
  SubscriptionPoolStrategy,
  SubscriptionProviderKind,
  TeammateRuntimeMode,
} from '../../protocol/src/index.ts';
import { PipiBoardEngine } from '../../core/src/board-engine.ts';
import { PipiSubscriptionAccountPool } from '../../core/src/subscription-pool.ts';
import {
  ACTIVITY_PULSE_INTERVAL_MS,
  AtomicTranscriptStore,
  PipiHarnessRouter,
  RoutedMcpBridge,
  detectLocalHarnesses,
  type HarnessDriver,
} from '../../core/src/harness-router.ts';
import { PipiEvolutionLoop, PipiMemoryEngine } from '../../core/src/memory-engine.ts';
import { formatUniversalPairingLink, generateE2EEIdentity, type E2EEIdentity } from '../../relay/src/e2e.ts';
import { renderUniversalIconSVG, renderUniversalManifest, renderUniversalPWAHTML } from '../../relay/src/pwa-bundle.ts';
import { runBotBoxSelfCheck } from './bot-box.ts';
import { PipiCloudBrowserManager, evaluateSocialBrowserActionRisk, type CloudBrowserLauncher } from './cloud-browser.ts';
import { PipiCloudBrigadeRuntime } from './cloud-runtime.ts';
import { PipiCredentialBrokerServer } from './credential-broker.ts';
import { PipiCueSensor, PipiFleetManager } from './cue-fleet-sensor.ts';
import { EcosystemRegistry } from './ecosystem.ts';
import { DaemonEventTriggerRegistry } from './event-triggers.ts';
import { routeGroupMessage, type DecisionModelConfig, type GroupRouteCandidate } from './group-router.ts';
import { MeshHubManager, buildLinuxSystemdService, type MeshTaskEvent, type MeshTaskRequest } from './mesh-hub.ts';
import { PipiOutcomeEngine } from './outcome-engine.ts';
import { parsePortableTemplate, type PortableTemplate } from './portable-template.ts';
import { DaemonProofAndHarnessEngine } from './proof-harness.ts';
import { scanSentinelSamples, type SentinelIssue, type SentinelSample } from './sentinel.ts';
import { DaemonWorktreeManager } from './worktree.ts';

export const DAEMON_VERSION = '0.15.0' as const;
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
  hubToken?: string;
  cloudBrowserLauncher?: CloudBrowserLauncher;
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
  readonly boardEngine: PipiBoardEngine;
  readonly outcomeEngine: PipiOutcomeEngine;
  readonly cueSensor: PipiCueSensor;
  readonly fleetManager: PipiFleetManager;
  readonly meshHub: MeshHubManager;
  readonly ecosystem: EcosystemRegistry;
  readonly worktreeManager: DaemonWorktreeManager;
  readonly eventTriggers: DaemonEventTriggerRegistry;
  readonly proofHarness: DaemonProofAndHarnessEngine;
  readonly credentialBroker: PipiCredentialBrokerServer;
  readonly subscriptionPool: PipiSubscriptionAccountPool;
  readonly cloudBrowsers: PipiCloudBrowserManager;
  readonly cloudBrigade: PipiCloudBrigadeRuntime;
  readonly e2eeIdentity: E2EEIdentity;

  private pairingChallenges = new Map<string, { code: string; scope: 'owner' | 'chat' | 'mcp_bounded'; expiresAt: number; consumed: boolean }>();
  private pairedDevices = new Map<string, { id: string; label: string; scope: 'owner' | 'chat' | 'mcp_bounded'; tokenHash: string; revoked: boolean; createdAt: string }>();
  private appliedTemplates: PortableTemplate[] = [];
  private sentinelSamples: SentinelSample[] = [];
  private sentinelIssues: SentinelIssue[] = [];

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

    this.boardEngine = new PipiBoardEngine({ dataDir: this.dataDir });
    this.outcomeEngine = new PipiOutcomeEngine({ seedDefaults: options.seedDefaults !== false });
    this.cueSensor = new PipiCueSensor({ memory: this.memoryEngine, workspacePath: this.workspacePath });
    this.fleetManager = new PipiFleetManager({ memory: this.memoryEngine, seedFleet: options.seedFleet !== false });
    this.meshHub = new MeshHubManager({ storageDir: this.dataDir, hubToken: options.hubToken ?? process.env.PIPIBOT_HUB_TOKEN });
    this.ecosystem = new EcosystemRegistry(this.dataDir);
    this.worktreeManager = new DaemonWorktreeManager();
    this.eventTriggers = new DaemonEventTriggerRegistry();
    this.proofHarness = new DaemonProofAndHarnessEngine();
    this.credentialBroker = new PipiCredentialBrokerServer();
    this.subscriptionPool = new PipiSubscriptionAccountPool({ dataDir: this.dataDir });
    this.cloudBrowsers = new PipiCloudBrowserManager({
      dataDir: this.dataDir,
      launcher: options.cloudBrowserLauncher,
    });
    this.cloudBrigade = new PipiCloudBrigadeRuntime({
      dataDir: this.dataDir,
      subscriptionPool: this.subscriptionPool,
      cloudBrowsers: this.cloudBrowsers,
      seedDefaults: options.seedDefaults !== false,
    });
    this.e2eeIdentity = generateE2EEIdentity();

    this.boardEngine.onEvent((evt) => {
      if (evt.kind === 'task_needs_you') {
        this.setAvatarState('needs-you');
      } else if (evt.kind === 'task_completed') {
        this.setAvatarState('evolution-proud');
      }
      this.broadcastSse('board.event', evt);
    });

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
    this.meshHub.closeAllStreams();
    await this.cloudBrowsers.stopAll();
    await this.mcpBridge.stop();
    await this.credentialBroker.stop();

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
            systemdService: '/api/v1/systemd-service',
            meshNodes: '/api/v1/mesh/nodes',
            meshDispatch: '/api/v1/mesh/dispatch',
            meshArtifacts: '/api/v1/mesh/artifacts',
            ecosystem: '/api/v1/ecosystem',
            worktrees: '/api/v1/worktrees',
            triggers: '/api/v1/triggers',
            webhooks: '/api/v1/webhooks/:routineId',
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

      // Hard bounded MCP scope guard at router entry: external MCP clients can NEVER approve, merge, or delete.
      const callerScopeEarly = typeof req.headers['x-pipibot-scope'] === 'string' ? req.headers['x-pipibot-scope'] : '';
      if (
        callerScopeEarly === 'mcp_bounded' &&
        (pathname.endsWith('/merge') || pathname.endsWith('/resolve') || method === 'DELETE')
      ) {
        this.sendJson(res, 403, { error: 'FORBIDDEN_BOUNDED_MCP' });
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

      // Linux systemd unit generator
      if (method === 'GET' && pathname === '/api/v1/systemd-service') {
        const role = reqUrl.searchParams.get('role') === 'node' ? 'node' : 'hub';
        const unit = buildLinuxSystemdService({
          role,
          port: this.boundPort || this.requestedPort,
          hubUrl: reqUrl.searchParams.get('hub') || this.baseUrl,
          nodeName: reqUrl.searchParams.get('name') || 'linux-node',
          workspace: reqUrl.searchParams.get('workspace') || this.workspacePath,
        });
        res.writeHead(200, { ...this.corsHeaders(), 'Content-Type': 'text/plain; charset=utf-8' });
        res.end(unit);
        return;
      }

      // Multi-Machine Mesh Hub API (/api/v1/mesh/*)
      if (pathname.startsWith('/api/v1/mesh/')) {
        if (!this.meshHub.verifyToken(req.headers.authorization, reqUrl.searchParams.get('token'))) {
          this.sendJson(res, 401, { error: 'Unauthorized mesh hub token' });
          return;
        }

        if (method === 'GET' && pathname === '/api/v1/mesh/nodes') {
          this.sendJson(res, 200, {
            hubVersion: DAEMON_VERSION,
            nodes: this.meshHub.listNodes(),
            recentTasks: this.meshHub.listRecentTasks(15),
          });
          return;
        }

        if (method === 'POST' && pathname === '/api/v1/mesh/nodes/register') {
          const body = (await this.readJsonBody(req)) as Record<string, unknown>;
          const node = this.meshHub.registerNode({
            nodeId: typeof body.nodeId === 'string' ? body.nodeId : undefined,
            name: typeof body.name === 'string' ? body.name : 'remote-node',
            platform: typeof body.platform === 'string' ? body.platform : 'linux',
            arch: typeof body.arch === 'string' ? body.arch : 'x64',
            hostname: typeof body.hostname === 'string' ? body.hostname : 'unknown',
            workspacePath: typeof body.workspacePath === 'string' ? body.workspacePath : '.',
            capabilities: Array.isArray(body.capabilities) ? (body.capabilities as string[]) : undefined,
            cliAgents: Array.isArray(body.cliAgents) ? (body.cliAgents as string[]) : undefined,
            hostedAgents: Array.isArray(body.hostedAgents) ? (body.hostedAgents as never[]) : undefined,
            telemetry: (body.telemetry as Record<string, unknown> | undefined) as never,
          });
          this.broadcastSse('mesh.node.updated', node);
          this.sendJson(res, 200, { ok: true, node });
          return;
        }

        if (method === 'POST' && pathname === '/api/v1/mesh/nodes/heartbeat') {
          const body = (await this.readJsonBody(req)) as Record<string, unknown>;
          const nodeId = typeof body.nodeId === 'string' ? body.nodeId : '';
          const updated = this.meshHub.heartbeatNode({
            nodeId,
            telemetry: (body.telemetry as Record<string, unknown> | undefined) as never,
            cliAgents: Array.isArray(body.cliAgents) ? (body.cliAgents as string[]) : undefined,
            activeTaskCount: typeof body.activeTaskCount === 'number' ? body.activeTaskCount : undefined,
          });
          if (!updated) {
            this.sendJson(res, 404, { error: 'Node not registered' });
            return;
          }
          this.sendJson(res, 200, { ok: true, node: updated });
          return;
        }

        const nodeStreamMatch = pathname.match(/^\/api\/v1\/mesh\/nodes\/([^/]+)\/stream$/);
        if (method === 'GET' && nodeStreamMatch) {
          const nodeId = decodeURIComponent(nodeStreamMatch[1] ?? '');
          res.writeHead(200, {
            ...this.corsHeaders(),
            'Content-Type': 'text/event-stream; charset=utf-8',
            'Cache-Control': 'no-cache, no-transform',
            Connection: 'keep-alive',
          });
          res.write(`event: mesh.connected\ndata: ${JSON.stringify({ nodeId, version: DAEMON_VERSION })}\n\n`);
          this.meshHub.attachNodeStream(nodeId, res);
          req.on('close', () => {
            this.meshHub.detachNodeStream(nodeId, res);
          });
          return;
        }

        if (method === 'POST' && pathname === '/api/v1/mesh/dispatch') {
          const body = (await this.readJsonBody(req)) as unknown as MeshTaskRequest;
          const result = this.meshHub.dispatchTask(body);
          if (!result.ok) {
            this.sendJson(res, 400, { error: result.error });
            return;
          }
          this.broadcastSse('mesh.task.dispatched', result.task);
          this.sendJson(res, 201, { ok: true, task: result.task });
          return;
        }

        const taskEventMatch = pathname.match(/^\/api\/v1\/mesh\/tasks\/([^/]+)\/event$/);
        if (method === 'POST' && taskEventMatch) {
          const taskId = decodeURIComponent(taskEventMatch[1] ?? '');
          const body = (await this.readJsonBody(req)) as {
            type: MeshTaskEvent['type'];
            text?: string;
            stepTitle?: string;
            artifactId?: string;
            error?: string;
          };
          const updated = this.meshHub.ingestTaskEvent(taskId, body);
          if (!updated) {
            this.sendJson(res, 404, { error: 'Task not found' });
            return;
          }
          this.broadcastSse('mesh.task.event', { taskId, ...body });
          this.sendJson(res, 200, { ok: true, task: updated });
          return;
        }

        const taskEventsStreamMatch = pathname.match(/^\/api\/v1\/mesh\/tasks\/([^/]+)\/events$/);
        if (method === 'GET' && taskEventsStreamMatch) {
          const taskId = decodeURIComponent(taskEventsStreamMatch[1] ?? '');
          if (!this.meshHub.getTask(taskId)) {
            this.sendJson(res, 404, { error: 'Task not found' });
            return;
          }
          res.writeHead(200, {
            ...this.corsHeaders(),
            'Content-Type': 'text/event-stream; charset=utf-8',
            'Cache-Control': 'no-cache, no-transform',
            Connection: 'keep-alive',
          });
          this.meshHub.attachTaskStream(taskId, res);
          req.on('close', () => {
            this.meshHub.detachTaskStream(taskId, res);
          });
          return;
        }

        const taskGetMatch = pathname.match(/^\/api\/v1\/mesh\/tasks\/([^/]+)$/);
        if (method === 'GET' && taskGetMatch) {
          const taskId = decodeURIComponent(taskGetMatch[1] ?? '');
          const task = this.meshHub.getTask(taskId);
          if (!task) {
            this.sendJson(res, 404, { error: 'Task not found' });
            return;
          }
          this.sendJson(res, 200, { ok: true, task });
          return;
        }

        if (method === 'POST' && pathname === '/api/v1/mesh/artifacts') {
          const body = (await this.readJsonBody(req)) as {
            fileName?: string;
            mimeType?: string;
            contentBase64?: string;
            sourceNodeId?: string;
          };
          const meta = this.meshHub.storeArtifact({
            fileName: body.fileName ?? 'artifact.bin',
            mimeType: body.mimeType,
            contentBase64: body.contentBase64 ?? '',
            sourceNodeId: body.sourceNodeId,
          });
          this.sendJson(res, 201, { ok: true, artifact: meta });
          return;
        }

        const artGetMatch = pathname.match(/^\/api\/v1\/mesh\/artifacts\/([^/]+)$/);
        if (method === 'GET' && artGetMatch) {
          const artId = decodeURIComponent(artGetMatch[1] ?? '');
          const found = this.meshHub.readArtifact(artId);
          if (!found) {
            this.sendJson(res, 404, { error: 'Artifact not found' });
            return;
          }
          res.writeHead(200, {
            ...this.corsHeaders(),
            'Content-Type': found.meta.mimeType,
            'Content-Length': String(found.data.length),
            'X-Pipi-Filename': found.meta.fileName,
          });
          res.end(found.data);
          return;
        }
      }

      // Open-Source MCP & SKILL.md Ecosystem API (/api/v1/ecosystem*)
      if (pathname === '/api/v1/ecosystem' && method === 'GET') {
        this.sendJson(res, 200, this.ecosystem.getSnapshot());
        return;
      }
      if (pathname === '/api/v1/ecosystem/skills' && method === 'POST') {
        const body = (await this.readJsonBody(req)) as {
          source?: string;
          rawMarkdown?: string;
          name?: string;
          scope?: 'global' | 'host' | 'bot';
          targetId?: string;
        };
        const skill = body.rawMarkdown
          ? this.ecosystem.upsertSkill({
              source: body.source ?? 'inline',
              rawMarkdown: body.rawMarkdown,
              name: body.name,
              scope: body.scope,
              targetId: body.targetId,
            })
          : await this.ecosystem.installSkillFromGitHubOrSource({
              source: body.source ?? '',
              scope: body.scope,
              targetId: body.targetId,
            });
        this.sendJson(res, 201, { ok: true, skill });
        return;
      }
      if (pathname === '/api/v1/ecosystem/mcp' && method === 'POST') {
        const body = (await this.readJsonBody(req)) as {
          id?: string;
          name?: string;
          description?: string;
          transport?: 'stdio' | 'sse';
          command?: string;
          args?: string[];
          url?: string;
          env?: Record<string, string>;
          scope?: 'global' | 'host' | 'bot';
          targetId?: string;
        };
        const server = this.ecosystem.upsertMCPServer({
          id: body.id,
          name: body.name ?? 'Custom MCP',
          description: body.description,
          transport: body.transport,
          command: body.command,
          args: body.args,
          url: body.url,
          env: body.env,
          scope: body.scope,
          targetId: body.targetId,
        });
        this.sendJson(res, 201, { ok: true, server });
        return;
      }
      const ecoSkillDel = pathname.match(/^\/api\/v1\/ecosystem\/skills\/([^/]+)$/);
      if (method === 'DELETE' && ecoSkillDel) {
        const removed = this.ecosystem.removeSkill(decodeURIComponent(ecoSkillDel[1] ?? ''));
        this.sendJson(res, removed ? 200 : 404, { ok: removed });
        return;
      }
      const ecoMcpDel = pathname.match(/^\/api\/v1\/ecosystem\/mcp\/([^/]+)$/);
      if (method === 'DELETE' && ecoMcpDel) {
        const removed = this.ecosystem.removeMCPServer(decodeURIComponent(ecoMcpDel[1] ?? ''));
        this.sendJson(res, removed ? 200 : 404, { ok: removed });
        return;
      }

      // Static routes: /design-system/* and /ios/*
      if (method === 'GET' && (pathname === '/design-system' || pathname.startsWith('/design-system/'))) {
        await this.serveStaticDirectory(res, join(this.repoRoot, 'design-system'), pathname.slice('/design-system'.length));
        return;
      }

      // Event-Driven Routine Webhooks & Triggers (/api/v1/triggers, /api/v1/webhooks/:routineId)
      if (method === 'GET' && pathname === '/api/v1/triggers') {
        this.sendJson(res, 200, {
          routines: this.eventTriggers.listRoutines(),
          logs: this.eventTriggers.listLogs(),
        });
        return;
      }

      if (method === 'POST' && pathname === '/api/v1/triggers') {
        const body = await this.readJsonBody(req);
        const created = this.eventTriggers.registerRoutine({
          id: typeof body.id === 'string' ? body.id : undefined,
          botId: String(body.botId ?? 'bot_pipi_general'),
          title: String(body.title ?? 'Event Routine'),
          prompt: String(body.prompt ?? ''),
          triggerKind: (body.triggerKind as 'schedule' | 'webhook' | 'file_or_git_watch' | 'channel_message' | 'host_health') ?? 'webhook',
          cronExpression: typeof body.cronExpression === 'string' ? body.cronExpression : undefined,
          webhookSecret: typeof body.webhookSecret === 'string' ? body.webhookSecret : undefined,
          watchPath: typeof body.watchPath === 'string' ? body.watchPath : undefined,
          messageKeyword: typeof body.messageKeyword === 'string' ? body.messageKeyword : undefined,
          cooldownSeconds: typeof body.cooldownSeconds === 'number' ? body.cooldownSeconds : 60,
          enabled: body.enabled !== false,
        });
        this.sendJson(res, 201, { routine: created });
        return;
      }

      if (method === 'POST' && pathname.startsWith('/api/v1/webhooks/')) {
        const routineId = decodeURIComponent(pathname.slice('/api/v1/webhooks/'.length)).replace(/^\/+|\/+$/g, '');
        const chunks: Buffer[] = [];
        for await (const chunk of req) {
          chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
        }
        const rawBody = Buffer.concat(chunks);
        const sigHeader =
          (typeof req.headers['x-pipibot-signature'] === 'string' ? req.headers['x-pipibot-signature'] : undefined) ??
          (typeof req.headers['x-hub-signature-256'] === 'string' ? req.headers['x-hub-signature-256'] : undefined);
        const result = this.eventTriggers.fireWebhook({
          routineId,
          authorizationHeader: typeof req.headers.authorization === 'string' ? req.headers.authorization : undefined,
          signatureHeader: sigHeader,
          body: rawBody,
        });
        if (result.log) {
          this.broadcastSse('trigger.fired', result.log);
        }
        this.sendJson(res, result.status, { ok: result.status < 400, message: result.message, log: result.log });
        return;
      }

      // Git Worktree Isolation & Diff Review API (/api/v1/worktrees/*)
      if (method === 'GET' && pathname === '/api/v1/worktrees') {
        this.sendJson(res, 200, { sessions: this.worktreeManager.listSessions() });
        return;
      }

      if (method === 'POST' && pathname === '/api/v1/worktrees') {
        const body = await this.readJsonBody(req);
        const session = await this.worktreeManager.createWorktree({
          repoPath: String(body.repoPath ?? this.workspacePath),
          taskTitle: String(body.taskTitle ?? 'parallel-task'),
          botId: String(body.botId ?? 'bot_pipi_coder'),
        });
        this.sendJson(res, 201, { session });
        return;
      }

      if (method === 'POST' && /^\/api\/v1\/worktrees\/[^/]+\/diff$/.test(pathname)) {
        const id = decodeURIComponent(pathname.split('/')[4] ?? '');
        const session = await this.worktreeManager.captureDiff(id);
        this.sendJson(res, 200, { session });
        return;
      }

      if (method === 'POST' && /^\/api\/v1\/worktrees\/[^/]+\/verify$/.test(pathname)) {
        const id = decodeURIComponent(pathname.split('/')[4] ?? '');
        const session = await this.worktreeManager.captureDiff(id);
        const proof = await this.proofHarness.verifyWorktree(session);
        this.sendJson(res, 200, { session, proof });
        return;
      }

      // Knowledge Gaps Roadmap & Loop Draft Gate API (/api/v1/gaps, /api/v1/loops/drafts)
      if (method === 'GET' && pathname === '/api/v1/gaps') {
        this.sendJson(res, 200, { gaps: this.proofHarness.listGaps() });
        return;
      }

      if (method === 'POST' && pathname === '/api/v1/gaps') {
        const body = await this.readJsonBody(req);
        const gap = this.proofHarness.recordGap({
          botId: String(body.botId ?? 'bot_pipi_operator'),
          question: String(body.question ?? ''),
          sourceChannel: typeof body.sourceChannel === 'string' ? body.sourceChannel : 'support',
        });
        this.sendJson(res, 201, { gap });
        return;
      }

      if (method === 'GET' && pathname === '/api/v1/loops/drafts') {
        this.sendJson(res, 200, {
          drafts: this.proofHarness.listDrafts(),
          harnessRules: this.proofHarness.listHarnessRules(),
        });
        return;
      }

      if (method === 'POST' && pathname === '/api/v1/loops/drafts') {
        const body = await this.readJsonBody(req);
        const draft = this.proofHarness.enqueueDraft({
          loopName: String(body.loopName ?? 'Support Loop'),
          botId: String(body.botId ?? 'bot_pipi_operator'),
          inputSummary: String(body.inputSummary ?? ''),
          draftContent: String(body.draftContent ?? ''),
          citedSources: Array.isArray(body.citedSources) ? body.citedSources.map(String) : [],
        });
        this.sendJson(res, 201, { draft });
        return;
      }

      if (method === 'POST' && /^\/api\/v1\/loops\/drafts\/[^/]+\/resolve$/.test(pathname)) {
        const id = decodeURIComponent(pathname.split('/')[5] ?? '');
        const body = await this.readJsonBody(req);
        const draft = this.proofHarness.resolveDraft(id, {
          action: (body.action as 'approve' | 'edit_and_add_rule' | 'discard') ?? 'approve',
          editedDraft: typeof body.editedDraft === 'string' ? body.editedDraft : undefined,
          newRule: typeof body.newRule === 'string' ? body.newRule : undefined,
        });
        if (!draft) {
          this.sendJson(res, 404, { error: 'Draft not found' });
          return;
        }
        this.sendJson(res, 200, { draft, harnessRules: this.proofHarness.listHarnessRules() });
        return;
      }

      if (method === 'POST' && /^\/api\/v1\/worktrees\/[^/]+\/feedback$/.test(pathname)) {
        const id = decodeURIComponent(pathname.split('/')[4] ?? '');
        const body = await this.readJsonBody(req);
        const session = this.worktreeManager.addFeedback(
          id,
          String(body.comment ?? ''),
          typeof body.filePath === 'string' ? body.filePath : undefined,
          typeof body.lineNumber === 'number' ? body.lineNumber : undefined,
        );
        this.sendJson(res, 200, { session });
        return;
      }

      if (method === 'POST' && /^\/api\/v1\/worktrees\/[^/]+\/merge$/.test(pathname)) {
        const id = decodeURIComponent(pathname.split('/')[4] ?? '');
        const body = await this.readJsonBody(req);
        const result = await this.worktreeManager.mergeAndCleanup(
          id,
          (body.strategy as 'squash' | 'merge_commit' | 'keep_branch_for_pr') ?? 'squash',
          typeof body.commitMessage === 'string' ? body.commitMessage : undefined,
        );
        this.sendJson(res, 200, result);
        return;
      }

      if (method === 'DELETE' && /^\/api\/v1\/worktrees\/[^/]+$/.test(pathname)) {
        const id = decodeURIComponent(pathname.split('/')[4] ?? '');
        const session = await this.worktreeManager.discardAndCleanup(id);
        this.sendJson(res, 200, { session });
        return;
      }

      // v0.15.0 Universal Pairing, Device Revocation & Bounded MCP Scope Enforcement
      if (method === 'POST' && pathname === '/api/v1/auth/pair/start') {
        const body = await this.readJsonBody(req);
        const scope = (body.scope === 'chat' || body.scope === 'mcp_bounded' ? body.scope : 'owner') as 'owner' | 'chat' | 'mcp_bounded';
        const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        const pick = (n: number) => Array.from({ length: n }, () => alphabet[randomBytes(1)[0]! % alphabet.length]).join('');
        const code = `${pick(4)}-${pick(4)}`;
        const norm = code.replace(/-/g, '');
        const expiresAt = Date.now() + 300_000;
        this.pairingChallenges.set(norm, { code, scope, expiresAt, consumed: false });
        const relayOrigin = typeof body.relayOrigin === 'string' && body.relayOrigin.trim()
          ? body.relayOrigin.trim()
          : 'https://pipibot.jimizhou.com';
        const universalLink = formatUniversalPairingLink({
          relayOrigin,
          hostId: this.e2eeIdentity.hostId,
          hostPublicKeyB64Url: this.e2eeIdentity.publicKeyB64Url,
          oneTimeToken: code,
          lanHintURL: `http://${this.host}:${this.boundPort}`,
        });
        this.sendJson(res, 201, {
          code,
          scope,
          expiresAt: new Date(expiresAt).toISOString(),
          hostId: this.e2eeIdentity.hostId,
          universalLink,
        });
        return;
      }

      if (method === 'POST' && pathname === '/api/v1/auth/pair') {
        const body = await this.readJsonBody(req);
        const rawCode = String(body.code ?? '').toUpperCase().replace(/[-\s]/g, '');
        const challenge = this.pairingChallenges.get(rawCode);
        if (!challenge || challenge.consumed || Date.now() > challenge.expiresAt) {
          this.sendJson(res, 401, { error: 'invalid_or_expired_pairing_code' });
          return;
        }
        challenge.consumed = true;
        const rawToken = `pipi_dev_${randomBytes(18).toString('hex')}`;
        const tokenHash = createHash('sha256').update(rawToken).digest('hex');
        const device = {
          id: `dev_${randomUUID().slice(0, 8)}`,
          label: String(body.label ?? 'Remote Companion'),
          scope: challenge.scope,
          tokenHash,
          revoked: false,
          createdAt: new Date().toISOString(),
        };
        this.pairedDevices.set(device.id, device);
        this.sendJson(res, 200, {
          ok: true,
          token: rawToken,
          deviceId: device.id,
          scope: device.scope,
          hostName: os.hostname(),
        });
        return;
      }

      if (method === 'GET' && pathname === '/api/v1/auth/devices') {
        const devices = [...this.pairedDevices.values()].map((d) => ({
          id: d.id,
          label: d.label,
          scope: d.scope,
          revoked: d.revoked,
          createdAt: d.createdAt,
        }));
        this.sendJson(res, 200, { devices });
        return;
      }

      if (method === 'DELETE' && /^\/api\/v1\/auth\/devices\/[^/]+$/.test(pathname)) {
        const id = decodeURIComponent(pathname.split('/')[5] ?? '');
        const dev = this.pairedDevices.get(id);
        if (!dev) {
          this.sendJson(res, 404, { error: 'device_not_found' });
          return;
        }
        dev.revoked = true;
        this.sendJson(res, 200, { ok: true, id, revoked: true });
        return;
      }

      // Bounded MCP scope guard on privileged routes (merges, draft approvals, deletions)
      const callerScopeHeader = typeof req.headers['x-pipibot-scope'] === 'string' ? req.headers['x-pipibot-scope'] : '';
      if (
        callerScopeHeader === 'mcp_bounded' &&
        (pathname.endsWith('/merge') || pathname.endsWith('/resolve') || method === 'DELETE')
      ) {
        this.sendJson(res, 403, { error: 'FORBIDDEN_BOUNDED_MCP' });
        return;
      }

      // Sentinel Zero-LLM Health Scanner API
      if (method === 'GET' && pathname === '/api/v1/sentinel/health') {
        this.sentinelIssues = scanSentinelSamples(this.sentinelSamples);
        this.sendJson(res, 200, {
          scannedAt: new Date().toISOString(),
          issueCount: this.sentinelIssues.length,
          issues: this.sentinelIssues,
        });
        return;
      }

      if (method === 'POST' && pathname === '/api/v1/sentinel/samples') {
        const body = await this.readJsonBody(req);
        const incoming = Array.isArray(body.samples) ? (body.samples as SentinelSample[]) : [];
        this.sentinelSamples.push(...incoming);
        this.sentinelIssues = scanSentinelSamples(this.sentinelSamples);
        this.sendJson(res, 200, { issues: this.sentinelIssues });
        return;
      }

      // Bot Box OS-Level Sandbox Self-Check Probe
      if (method === 'GET' && pathname === '/api/v1/security/box-check') {
        this.sendJson(res, 200, runBotBoxSelfCheck());
        return;
      }

      // Portable Redacted Team / Bot Template API (`bot.md` / `team.md` / `team.yaml`)
      if (method === 'POST' && pathname === '/api/v1/templates/preview') {
        const body = await this.readJsonBody(req);
        const tpl = parsePortableTemplate(String(body.markdown ?? ''));
        this.sendJson(res, 200, { template: tpl });
        return;
      }

      if (method === 'POST' && pathname === '/api/v1/templates/apply') {
        const body = await this.readJsonBody(req);
        const tpl = parsePortableTemplate(String(body.markdown ?? ''));
        this.appliedTemplates.push(tpl);
        this.sendJson(res, 201, { applied: true, template: tpl, totalTeams: this.appliedTemplates.length });
        return;
      }

      // Three-Tier Fast Group Auto-Routing API
      if (method === 'POST' && pathname === '/api/v1/groups/route') {
        const body = await this.readJsonBody(req);
        const decision = await routeGroupMessage(
          String(body.message ?? ''),
          Array.isArray(body.candidates) ? (body.candidates as GroupRouteCandidate[]) : [],
          String(body.leadBotId ?? 'bot_pipi_general'),
          (body.config as DecisionModelConfig | undefined) ?? { enabled: false, providerKind: 'disabled' },
        );
        this.sendJson(res, 200, { decision });
        return;
      }

      // Unified 5-Tab Mobile PWA endpoints on Daemon Hub
      if (method === 'GET' && pathname === '/api/v1/mobile/snapshot') {
        this.sendJson(res, 200, {
          hostName: `${os.hostname()} (Daemon Hub)`,
          messages: [],
          bots: this.appliedTemplates.flatMap((t) => t.bots.map((b) => ({ id: b.slug, name: b.name, role: b.role }))),
          approvals: [],
          draftGates: this.proofHarness.listDrafts().filter((d) => d.status === 'pending_gate'),
          evolutions: [],
          worktrees: this.worktreeManager.listSessions().map((w) => ({
            id: w.id,
            branchName: w.branchName,
            summary: w.diffSummary,
            diffText: w.unifiedDiff,
            proofScore: 100,
          })),
          sentinelIssues: this.sentinelIssues,
          triggers: this.eventTriggers.listRoutines().map((r) => ({ id: r.id, title: r.title, enabled: r.enabled })),
          board: this.boardEngine.snapshot(),
          usageSummary: { todayTokens: 0, todayCostUSD: 0 },
        });
        return;
      }

      // -------------------------------------------------------------------
      // Phase 2: Vercel Board-Inspired Multi-Agent Coordination API
      // -------------------------------------------------------------------
      if (method === 'GET' && pathname === '/api/v1/board') {
        const channelSlug = reqUrl.searchParams.get('channel') ?? undefined;
        const status = (reqUrl.searchParams.get('status') ?? undefined) as BoardTaskStatus | undefined;
        const label = reqUrl.searchParams.get('label') ?? undefined;
        this.sendJson(res, 200, this.boardEngine.snapshot({ channelSlug, status, label }));
        return;
      }

      if (method === 'GET' && pathname === '/api/v1/board/inspect') {
        const channelSlug = reqUrl.searchParams.get('channel') ?? undefined;
        const limitRaw = Number(reqUrl.searchParams.get('limit') ?? '40');
        this.sendJson(
          res,
          200,
          this.boardEngine.inspect({
            channelSlug,
            limit: Number.isFinite(limitRaw) && limitRaw > 0 ? limitRaw : 40,
          }),
        );
        return;
      }

      if (method === 'POST' && pathname === '/api/v1/board/channels') {
        const body = await this.readJsonBody<{ slug?: string; title?: string; description?: string; actor?: BoardActorRef }>(req);
        if (!body.slug?.trim()) {
          this.sendJson(res, 400, { error: 'slug is required' });
          return;
        }
        const channel = this.boardEngine.ensureChannel(body.slug, body.title, body.description, body.actor);
        this.sendJson(res, 201, { channel });
        return;
      }

      if (method === 'GET' && pathname === '/api/v1/board/threads') {
        const channelSlug = reqUrl.searchParams.get('channel') ?? undefined;
        const status = (reqUrl.searchParams.get('status') ?? undefined) as BoardTaskStatus | undefined;
        const kind = (reqUrl.searchParams.get('kind') ?? undefined) as BoardThreadKind | undefined;
        const label = reqUrl.searchParams.get('label') ?? undefined;
        const claimedByActorId = reqUrl.searchParams.get('claimedBy') ?? undefined;
        this.sendJson(res, 200, {
          threads: this.boardEngine.listThreads({ channelSlug, status, kind, label, claimedByActorId }),
        });
        return;
      }

      if (method === 'POST' && pathname === '/api/v1/board/threads') {
        const body = await this.readJsonBody<{
          channelSlug?: string;
          title?: string;
          body?: string;
          kind?: BoardThreadKind;
          priority?: BoardTaskPriority;
          labels?: string[];
          blockedBy?: string[];
          maxClaimRetries?: number;
          author?: Partial<BoardActorRef>;
          linkedConversationId?: string;
          linkedWorktreeId?: string;
        }>(req);
        if (!body.title?.trim()) {
          this.sendJson(res, 400, { error: 'title is required' });
          return;
        }
        const author: BoardActorRef = {
          id: body.author?.id?.trim() || 'human:owner',
          name: body.author?.name?.trim() || 'Owner',
          kind: (body.author?.kind as BoardActorKind | undefined) ?? 'human',
          harness: body.author?.harness,
          nodeId: body.author?.nodeId,
        };
        const thread = this.boardEngine.createThread({
          channelSlug: body.channelSlug,
          title: body.title,
          body: body.body,
          kind: body.kind,
          priority: body.priority,
          labels: body.labels,
          blockedBy: body.blockedBy,
          maxClaimRetries: body.maxClaimRetries,
          author,
          linkedConversationId: body.linkedConversationId,
          linkedWorktreeId: body.linkedWorktreeId,
        });
        this.sendJson(res, 201, { thread });
        return;
      }

      if (method === 'POST' && pathname === '/api/v1/board/claim-next') {
        const body = await this.readJsonBody<{
          actor?: Partial<BoardActorRef>;
          channelSlug?: string;
          label?: string;
          leaseMs?: number;
          note?: string;
        }>(req);
        const actor: BoardActorRef = {
          id: body.actor?.id?.trim() || 'agent:anonymous',
          name: body.actor?.name?.trim() || body.actor?.id?.trim() || 'Agent',
          kind: (body.actor?.kind as BoardActorKind | undefined) ?? 'harness',
          harness: body.actor?.harness,
          nodeId: body.actor?.nodeId,
        };
        const result = this.boardEngine.claimNextTask({
          actor,
          channelSlug: body.channelSlug,
          label: body.label,
          leaseMs: body.leaseMs,
          note: body.note,
        });
        this.sendJson(res, result.ok ? 200 : 404, result);
        return;
      }

      if (method === 'POST' && pathname === '/api/v1/board/sweep') {
        const expired = this.boardEngine.sweepExpiredLeases();
        const dueFollowUps = this.boardEngine.collectDueFollowUps();
        this.sendJson(res, 200, { expiredCount: expired.length, expired, dueFollowUps });
        return;
      }

      const boardThreadMatch = pathname.match(/^\/api\/v1\/board\/threads\/([^/]+)(?:\/(messages|claim|renew|release|needs-you|complete|followups))?$/);
      if (boardThreadMatch) {
        const threadId = decodeURIComponent(boardThreadMatch[1] ?? '');
        const action = boardThreadMatch[2];

        if (method === 'GET' && !action) {
          const thread = this.boardEngine.getThread(threadId);
          if (!thread) {
            this.sendJson(res, 404, { error: `Thread not found: ${threadId}` });
            return;
          }
          this.sendJson(res, 200, { thread });
          return;
        }

        if (method === 'POST' && action === 'messages') {
          const body = await this.readJsonBody<{
            author?: Partial<BoardActorRef>;
            body?: string;
            artifactRef?: string;
            metadata?: Record<string, string>;
          }>(req);
          if (!body.body?.trim()) {
            this.sendJson(res, 400, { error: 'body is required' });
            return;
          }
          const author: BoardActorRef = {
            id: body.author?.id?.trim() || 'human:owner',
            name: body.author?.name?.trim() || 'Owner',
            kind: (body.author?.kind as BoardActorKind | undefined) ?? 'human',
            harness: body.author?.harness,
            nodeId: body.author?.nodeId,
          };
          const message = this.boardEngine.postMessage(threadId, {
            author,
            body: body.body,
            artifactRef: body.artifactRef,
            metadata: body.metadata,
          });
          if (!message) {
            this.sendJson(res, 404, { error: `Thread not found: ${threadId}` });
            return;
          }
          this.sendJson(res, 201, { message });
          return;
        }

        if (method === 'POST' && action === 'claim') {
          const body = await this.readJsonBody<{ actor?: Partial<BoardActorRef>; leaseMs?: number; note?: string }>(req);
          const actor: BoardActorRef = {
            id: body.actor?.id?.trim() || 'agent:anonymous',
            name: body.actor?.name?.trim() || body.actor?.id?.trim() || 'Agent',
            kind: (body.actor?.kind as BoardActorKind | undefined) ?? 'harness',
            harness: body.actor?.harness,
            nodeId: body.actor?.nodeId,
          };
          const result = this.boardEngine.claimTask(threadId, { actor, leaseMs: body.leaseMs, note: body.note });
          const status = result.ok ? 200 : result.reason === 'not_found' ? 404 : 409;
          this.sendJson(res, status, result);
          return;
        }

        if (method === 'POST' && action === 'renew') {
          const body = await this.readJsonBody<{ actorId?: string; leaseToken?: string; leaseMs?: number }>(req);
          if (!body.actorId || !body.leaseToken) {
            this.sendJson(res, 400, { error: 'actorId and leaseToken are required' });
            return;
          }
          const result = this.boardEngine.renewLease(threadId, {
            actorId: body.actorId,
            leaseToken: body.leaseToken,
            leaseMs: body.leaseMs,
          });
          const status = result.ok ? 200 : result.reason === 'not_found' ? 404 : 409;
          this.sendJson(res, status, result);
          return;
        }

        if (method === 'POST' && action === 'release') {
          const body = await this.readJsonBody<{ actorId?: string; leaseToken?: string; force?: boolean; reason?: string }>(req);
          const result = this.boardEngine.releaseClaim(threadId, {
            actorId: body.actorId ?? '',
            leaseToken: body.leaseToken,
            force: body.force,
            reason: body.reason,
          });
          const status = result.ok ? 200 : result.reason === 'not_found' ? 404 : 409;
          this.sendJson(res, status, result);
          return;
        }

        if (method === 'POST' && action === 'needs-you') {
          const body = await this.readJsonBody<{
            actor?: Partial<BoardActorRef>;
            summary?: string;
            decisionId?: string;
            artifactRef?: string;
          }>(req);
          const actor: BoardActorRef = {
            id: body.actor?.id?.trim() || 'agent:anonymous',
            name: body.actor?.name?.trim() || 'Agent',
            kind: (body.actor?.kind as BoardActorKind | undefined) ?? 'harness',
          };
          const thread = this.boardEngine.requestNeedsYou(threadId, {
            actor,
            summary: body.summary?.trim() || 'Human confirmation requested.',
            decisionId: body.decisionId,
            artifactRef: body.artifactRef,
          });
          if (!thread) {
            this.sendJson(res, 404, { error: `Thread not found: ${threadId}` });
            return;
          }
          this.sendJson(res, 200, { thread });
          return;
        }

        if (method === 'POST' && action === 'complete') {
          const body = await this.readJsonBody<{
            actor?: Partial<BoardActorRef>;
            summary?: string;
            deliverableRef?: string;
            leaseToken?: string;
          }>(req);
          const actor: BoardActorRef = {
            id: body.actor?.id?.trim() || 'agent:anonymous',
            name: body.actor?.name?.trim() || 'Agent',
            kind: (body.actor?.kind as BoardActorKind | undefined) ?? 'harness',
          };
          const result = this.boardEngine.completeTask(threadId, {
            actor,
            summary: body.summary,
            deliverableRef: body.deliverableRef,
            leaseToken: body.leaseToken,
          });
          const status = result.ok ? 200 : result.reason === 'not_found' ? 404 : 409;
          this.sendJson(res, status, result);
          return;
        }

        if (method === 'POST' && action === 'followups') {
          const body = await this.readJsonBody<{
            actor?: Partial<BoardActorRef>;
            prompt?: string;
            dueAt?: string;
            inMs?: number;
          }>(req);
          if (!body.prompt?.trim()) {
            this.sendJson(res, 400, { error: 'prompt is required' });
            return;
          }
          const actor: BoardActorRef = {
            id: body.actor?.id?.trim() || 'agent:anonymous',
            name: body.actor?.name?.trim() || 'Agent',
            kind: (body.actor?.kind as BoardActorKind | undefined) ?? 'harness',
          };
          const followUp = this.boardEngine.scheduleFollowUp(threadId, {
            actor,
            prompt: body.prompt,
            dueAt: body.dueAt,
            inMs: body.inMs,
          });
          if (!followUp) {
            this.sendJson(res, 404, { error: `Thread not found: ${threadId}` });
            return;
          }
          this.sendJson(res, 201, { followUp });
          return;
        }
      }

      // ---------------------------------------------------------------------
      // Brigade 24/7 Cloud Teammates, Stacked Subscriptions & Isolated Browsers
      // ---------------------------------------------------------------------

      if (method === 'GET' && pathname === '/api/v1/brigade/overview') {
        this.sendJson(res, 200, this.cloudBrigade.getOverview());
        return;
      }

      if (method === 'GET' && pathname === '/api/v1/cloud/teammates') {
        this.sendJson(res, 200, { teammates: this.cloudBrigade.listTeammates() });
        return;
      }

      if (method === 'POST' && pathname === '/api/v1/cloud/teammates') {
        const body = await this.readJsonBody<{
          botId?: string;
          name?: string;
          role?: string;
          runtimeMode?: TeammateRuntimeMode;
          reportsToBotId?: string;
          subscriptionProvider?: SubscriptionProviderKind;
          subscriptionAccountId?: string;
          modelId?: string;
          browserEnabled?: boolean;
          browserPlatforms?: string[];
          proxyUrl?: string;
          requireApprovalBeforePost?: boolean;
        }>(req);
        if (!body.botId?.trim()) {
          this.sendJson(res, 400, { error: 'botId is required' });
          return;
        }
        const teammate = this.cloudBrigade.upsertTeammate({
          botId: body.botId.trim(),
          name: body.name ?? body.botId,
          role: body.role ?? 'AI Teammate',
          runtimeMode: body.runtimeMode,
          reportsToBotId: body.reportsToBotId,
          subscriptionProvider: body.subscriptionProvider,
          subscriptionAccountId: body.subscriptionAccountId,
          modelId: body.modelId,
          browserEnabled: body.browserEnabled,
          browserPlatforms: body.browserPlatforms,
          proxyUrl: body.proxyUrl,
          requireApprovalBeforePost: body.requireApprovalBeforePost,
        });
        this.broadcastSse('brigade.teammate.updated', teammate);
        this.sendJson(res, 201, { ok: true, teammate });
        return;
      }

      const teammateDelMatch = pathname.match(/^\/api\/v1\/cloud\/teammates\/([^/]+)$/);
      if (method === 'DELETE' && teammateDelMatch?.[1]) {
        const removed = this.cloudBrigade.removeTeammate(decodeURIComponent(teammateDelMatch[1]));
        this.sendJson(res, removed ? 200 : 404, { ok: removed });
        return;
      }

      if (method === 'GET' && pathname === '/api/v1/subscriptions/accounts') {
        this.sendJson(res, 200, this.subscriptionPool.getSnapshot());
        return;
      }

      if (method === 'POST' && pathname === '/api/v1/subscriptions/accounts') {
        const body = await this.readJsonBody<{
          id?: string;
          label?: string;
          provider?: SubscriptionProviderKind;
          planTier?: string;
          emailHint?: string;
          useSystemDefaultProfile?: boolean;
          profileDir?: string;
          baseUrl?: string;
          modelId?: string;
          apiKeyEnvVar?: string;
          apiKey?: string;
          priority?: number;
        }>(req);
        if (!body.provider) {
          this.sendJson(res, 400, { error: 'provider is required' });
          return;
        }
        const account = this.subscriptionPool.addAccount({
          id: body.id,
          label: body.label ?? '',
          provider: body.provider,
          planTier: body.planTier,
          emailHint: body.emailHint,
          useSystemDefaultProfile: body.useSystemDefaultProfile,
          profileDir: body.profileDir,
          baseUrl: body.baseUrl,
          modelId: body.modelId,
          apiKeyEnvVar: body.apiKeyEnvVar,
          apiKey: body.apiKey,
          priority: body.priority,
        });
        const loginCommand = this.subscriptionPool.buildInteractiveLoginCommand(account);
        this.broadcastSse('brigade.subscription.updated', account);
        this.sendJson(res, 201, { ok: true, account, loginCommand });
        return;
      }

      const subAccountDelMatch = pathname.match(/^\/api\/v1\/subscriptions\/accounts\/([^/]+)$/);
      if (method === 'DELETE' && subAccountDelMatch?.[1]) {
        const removed = this.subscriptionPool.removeAccount(decodeURIComponent(subAccountDelMatch[1]));
        this.sendJson(res, removed ? 200 : 404, { ok: removed });
        return;
      }

      if (method === 'POST' && pathname === '/api/v1/subscriptions/strategy') {
        const body = await this.readJsonBody<{ strategy?: SubscriptionPoolStrategy }>(req);
        if (!body.strategy) {
          this.sendJson(res, 400, { error: 'strategy is required' });
          return;
        }
        this.subscriptionPool.setStrategy(body.strategy);
        this.sendJson(res, 200, this.subscriptionPool.getSnapshot());
        return;
      }

      if (method === 'POST' && pathname === '/api/v1/subscriptions/cooldown-reset') {
        const body = await this.readJsonBody<{ accountId?: string }>(req);
        const resetCount = this.subscriptionPool.resetCooldown(body.accountId);
        this.sendJson(res, 200, { ok: true, resetCount, pool: this.subscriptionPool.getSnapshot() });
        return;
      }

      if (method === 'GET' && pathname === '/api/v1/cloud/browsers') {
        this.sendJson(res, 200, { browsers: this.cloudBrowsers.listProfiles() });
        return;
      }

      if (method === 'POST' && pathname === '/api/v1/cloud/browsers') {
        const body = await this.readJsonBody<{
          botId?: string;
          botName?: string;
          enabled?: boolean;
          proxyUrl?: string;
          platforms?: string[];
          requireApprovalBeforePost?: boolean;
          cdpPort?: number;
        }>(req);
        if (!body.botId?.trim()) {
          this.sendJson(res, 400, { error: 'botId is required' });
          return;
        }
        const profile = this.cloudBrowsers.configureProfile({
          botId: body.botId.trim(),
          botName: body.botName ?? body.botId,
          enabled: body.enabled,
          proxyUrl: body.proxyUrl,
          platforms: body.platforms,
          requireApprovalBeforePost: body.requireApprovalBeforePost,
          cdpPort: body.cdpPort,
        });
        this.sendJson(res, 201, { ok: true, browser: profile });
        return;
      }

      const browserActionMatch = pathname.match(
        /^\/api\/v1\/cloud\/browsers\/([^/]+)\/(start|stop|navigate|login-handoff|login-complete|risk-check)$/,
      );
      if (method === 'POST' && browserActionMatch?.[1] && browserActionMatch?.[2]) {
        const botId = decodeURIComponent(browserActionMatch[1]);
        const action = browserActionMatch[2];

        if (action === 'start') {
          const browser = await this.cloudBrowsers.startBrowser(botId);
          this.broadcastSse('brigade.browser.updated', browser);
          this.sendJson(res, 200, { ok: true, browser });
          return;
        }
        if (action === 'stop') {
          const browser = await this.cloudBrowsers.stopBrowser(botId);
          this.sendJson(res, browser ? 200 : 404, { ok: Boolean(browser), browser });
          return;
        }
        if (action === 'navigate') {
          const body = await this.readJsonBody<{ url?: string }>(req);
          if (!body.url?.trim()) {
            this.sendJson(res, 400, { error: 'url is required' });
            return;
          }
          const result = await this.cloudBrowsers.navigate(botId, body.url.trim());
          this.broadcastSse('brigade.browser.updated', result.profile);
          this.sendJson(res, 200, { ok: true, browser: result.profile, risk: result.risk });
          return;
        }
        if (action === 'login-handoff') {
          const body = await this.readJsonBody<{ url?: string }>(req);
          const browser = await this.cloudBrowsers.requestLoginHandoff(botId, body.url?.trim() || 'https://x.com/login');
          this.broadcastSse('brigade.browser.updated', browser);
          this.sendJson(res, 200, { ok: true, browser });
          return;
        }
        if (action === 'login-complete') {
          const browser = this.cloudBrowsers.completeLoginHandoff(botId);
          this.sendJson(res, browser ? 200 : 404, { ok: Boolean(browser), browser });
          return;
        }
        if (action === 'risk-check') {
          const body = await this.readJsonBody<{
            url?: string;
            actionType?: 'navigate' | 'click' | 'type' | 'submit' | 'scroll' | 'snapshot';
            targetLabel?: string;
          }>(req);
          const existing = this.cloudBrowsers.getProfile(botId);
          const verdict = evaluateSocialBrowserActionRisk({
            url: body.url ?? existing?.currentUrl ?? '',
            actionType: body.actionType ?? 'click',
            targetLabel: body.targetLabel,
            requireApprovalBeforePost: existing?.requireApprovalBeforePost ?? true,
          });
          this.sendJson(res, 200, { ok: true, verdict });
          return;
        }
      }

      if (method === 'GET' && (pathname === '/mobile' || /^\/c\/[a-zA-Z0-9_-]{4,64}$/.test(pathname))) {
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
        res.end(renderUniversalPWAHTML({ relayMode: false, defaultHostTitle: `${os.hostname()} · PiPiBot` }));
        return;
      }

      if (method === 'GET' && (pathname === '/manifest.webmanifest' || pathname === '/manifest.json')) {
        res.writeHead(200, { 'Content-Type': 'application/manifest+json; charset=utf-8' });
        res.end(renderUniversalManifest());
        return;
      }

      if (method === 'GET' && (pathname === '/icon.svg' || pathname === '/icon-192.svg')) {
        res.writeHead(200, { 'Content-Type': 'image/svg+xml; charset=utf-8' });
        res.end(renderUniversalIconSVG());
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
