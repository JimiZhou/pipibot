/**
 * @pipibot/core - harness-router.ts
 *
 * Pi-based Universal Harness Router (`PipiHarnessRouter`), `RoutedMcpBridge`,
 * 250ms Activity Pulse heartbeats, Local CLI Detection (`pi`, `claude-code`,
 * `codex`, `opencode`), BYOK `pi-ai`-compatible routing, and crash-safe Atomic
 * Transcript Persistence with Pi-style tree branching.
 *
 * Runtime dependencies: strictly Node built-ins (`node:*`) only.
 */

import { spawn, type ChildProcess } from 'node:child_process';
import { randomBytes, randomUUID } from 'node:crypto';
import { constants as fsConstants } from 'node:fs';
import { access, mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import { homedir, tmpdir } from 'node:os';
import { delimiter, dirname, join } from 'node:path';

import type {
  ActionKind,
  ActionSourceTrust,
  AvatarState53,
  ByokProviderConfig,
  GuardrailVerdict,
  HarnessActivityPulse,
  HarnessExecutionPhase,
  HarnessProbeResult,
  HarnessProvider,
  RoutedMcpToolDefinition,
} from '@pipibot/protocol';
import { PipiPermissionGuardrail } from './permission-guardrail.ts';

// ---------------------------------------------------------------------------
// Constants & Shared Types
// ---------------------------------------------------------------------------

export const ACTIVITY_PULSE_INTERVAL_MS = 250 as const;

export interface TranscriptEntry {
  id: string;
  parentEntryId: string | null;
  branchId: string;
  sessionId: string;
  seq: number;
  role: 'system' | 'user' | 'assistant' | 'tool_call' | 'tool_result' | 'meta';
  provider: HarnessProvider;
  modelId?: string;
  content: string;
  toolName?: string;
  toolCallId?: string;
  toolArgs?: Record<string, unknown>;
  isError?: boolean;
  tokensEstimated?: number;
  createdAt: string;
}

export interface SessionManifest {
  sessionId: string;
  activeBranchId: string;
  headEntryId: string | null;
  provider: HarnessProvider;
  modelId?: string;
  workspacePath: string;
  entryCount: number;
  createdAt: string;
  updatedAt: string;
}

export interface RoutedMcpToolContext {
  sessionId: string;
  subSessionId?: string;
  provider: HarnessProvider;
  workspacePath: string;
  projectId?: string;
  operationId?: string;
  sourceTrust?: ActionSourceTrust;
  trustedUserMessages?: string[];
  untrustedContextSnippets?: string[];
  signal?: AbortSignal;
}

export interface RoutedMcpToolResult {
  content: Array<{ type: 'text'; text: string }>;
  isError?: boolean;
  structuredContent?: Record<string, unknown>;
}

export type RoutedMcpToolHandler = (
  args: Record<string, unknown>,
  ctx: RoutedMcpToolContext,
) => Promise<RoutedMcpToolResult> | RoutedMcpToolResult;

interface RegisteredMcpTool {
  definition: RoutedMcpToolDefinition;
  handler: RoutedMcpToolHandler;
}

export interface HarnessTurnRequest {
  sessionId: string;
  subSessionId?: string;
  branchId?: string;
  parentEntryId?: string | null;
  prompt: string;
  systemPrompt?: string;
  memoryContextBlock?: string;
  workspacePath: string;
  preferredProvider: HarnessProvider;
  fallbackProviders?: HarnessProvider[];
  byokConfig?: ByokProviderConfig;
  modelId?: string;
  maxToolIterations?: number;
  allowMcpBridge?: boolean;
  autoApproveReadOnlyTools?: boolean;
  openCodeServerUrl?: string;
  signal?: AbortSignal;
  onPulse?: (pulse: HarnessActivityPulse) => void;
  onEvent?: (event: HarnessStreamEvent) => void;
}

export type HarnessStreamEvent =
  | { type: 'session_started'; sessionId: string; provider: HarnessProvider; modelId?: string }
  | { type: 'text_delta'; delta: string }
  | { type: 'reasoning_delta'; delta: string }
  | { type: 'tool_start'; toolCallId: string; toolName: string; args: Record<string, unknown> }
  | { type: 'tool_end'; toolCallId: string; toolName: string; isError: boolean; output: string }
  | { type: 'provider_fallback'; from: HarnessProvider; to: HarnessProvider; reason: string }
  | { type: 'pulse'; pulse: HarnessActivityPulse }
  | { type: 'turn_complete'; text: string; provider: HarnessProvider; modelId?: string; usage?: TokenUsage };

export interface TokenUsage {
  inputTokens: number;
  outputTokens: number;
  estimated: boolean;
}

export interface HarnessTurnResult {
  sessionId: string;
  branchId: string;
  assistantEntryId: string;
  providerUsed: HarnessProvider;
  modelId?: string;
  text: string;
  toolCallsExecuted: number;
  usage: TokenUsage;
  durationMs: number;
}

export interface PiExtensionHookContext {
  sessionId: string;
  workspacePath: string;
  provider: HarnessProvider;
  toolName?: string;
  toolArgs?: Record<string, unknown>;
}

export interface PiExtensionHooks {
  beforeTurn?: (ctx: PiExtensionHookContext, prompt: string) => Promise<string> | string;
  beforeToolCall?: (
    ctx: PiExtensionHookContext,
  ) => Promise<{ allow: boolean; reason?: string; mutatedArgs?: Record<string, unknown> }> | {
    allow: boolean;
    reason?: string;
    mutatedArgs?: Record<string, unknown>;
  };
  afterToolCall?: (ctx: PiExtensionHookContext, result: RoutedMcpToolResult) => Promise<void> | void;
  afterTurn?: (ctx: PiExtensionHookContext, result: HarnessTurnResult) => Promise<void> | void;
}

// ---------------------------------------------------------------------------
// 1. Atomic Transcript Persistence (Crash-Safe JSONL + Tree Branching)
// ---------------------------------------------------------------------------

async function atomicWriteFile(filePath: string, data: string): Promise<void> {
  await mkdir(dirname(filePath), { recursive: true });
  const tempPath = `${filePath}.tmp.${process.pid}.${randomBytes(6).toString('hex')}`;
  await writeFile(tempPath, data, 'utf8');
  await rename(tempPath, filePath);
}

export class AtomicTranscriptStore {
  private readonly baseDir: string;

  constructor(baseDir = join(homedir(), '.pipibot', 'transcripts')) {
    this.baseDir = baseDir;
  }

  private manifestPath(sessionId: string): string {
    return join(this.baseDir, sessionId, 'manifest.json');
  }

  private logPath(sessionId: string): string {
    return join(this.baseDir, sessionId, 'entries.jsonl');
  }

  async loadManifest(sessionId: string): Promise<SessionManifest | null> {
    try {
      const raw = await readFile(this.manifestPath(sessionId), 'utf8');
      return JSON.parse(raw) as SessionManifest;
    } catch {
      return null;
    }
  }

  async loadEntries(sessionId: string, branchId?: string): Promise<TranscriptEntry[]> {
    let raw = '';
    try {
      raw = await readFile(this.logPath(sessionId), 'utf8');
    } catch {
      return [];
    }

    const allEntries = raw
      .split('\n')
      .map((line) => line.trim())
      .filter((line) => line.length > 0)
      .map((line) => JSON.parse(line) as TranscriptEntry);

    if (!branchId) {
      return allEntries;
    }

    const byId = new Map<string, TranscriptEntry>();
    for (const entry of allEntries) {
      byId.set(entry.id, entry);
    }

    const branchHeads = allEntries.filter((e) => e.branchId === branchId);
    if (branchHeads.length === 0) {
      return [];
    }

    const lineage: TranscriptEntry[] = [];
    const seen = new Set<string>();
    let cursor: TranscriptEntry | undefined = branchHeads[branchHeads.length - 1];
    while (cursor && !seen.has(cursor.id)) {
      seen.add(cursor.id);
      lineage.push(cursor);
      cursor = cursor.parentEntryId ? byId.get(cursor.parentEntryId) : undefined;
    }
    return lineage.reverse();
  }

  async appendEntry(
    input: Omit<TranscriptEntry, 'id' | 'seq' | 'createdAt'> & {
      id?: string;
      createdAt?: string;
      workspacePath?: string;
    },
  ): Promise<TranscriptEntry> {
    const existingEntries = await this.loadEntries(input.sessionId);
    const existingManifest = await this.loadManifest(input.sessionId);
    const now = input.createdAt ?? new Date().toISOString();

    const entry: TranscriptEntry = {
      id: input.id ?? `tr_${randomUUID()}`,
      parentEntryId: input.parentEntryId,
      branchId: input.branchId,
      sessionId: input.sessionId,
      seq: existingEntries.length + 1,
      role: input.role,
      provider: input.provider,
      modelId: input.modelId,
      content: input.content,
      toolName: input.toolName,
      toolCallId: input.toolCallId,
      toolArgs: input.toolArgs,
      isError: input.isError,
      tokensEstimated: input.tokensEstimated,
      createdAt: now,
    };

    // Atomically rewrite temp + rename so partial crash never corrupts JSONL
    const nextContent =
      existingEntries.map((item) => JSON.stringify(item)).join('\n') +
      (existingEntries.length > 0 ? '\n' : '') +
      JSON.stringify(entry) +
      '\n';

    await atomicWriteFile(this.logPath(input.sessionId), nextContent);

    const nextManifest: SessionManifest = {
      sessionId: input.sessionId,
      activeBranchId: input.branchId,
      headEntryId: entry.id,
      provider: input.provider,
      modelId: input.modelId ?? existingManifest?.modelId,
      workspacePath: input.workspacePath ?? existingManifest?.workspacePath ?? process.cwd(),
      entryCount: entry.seq,
      createdAt: existingManifest?.createdAt ?? now,
      updatedAt: now,
    };

    await atomicWriteFile(this.manifestPath(input.sessionId), JSON.stringify(nextManifest, null, 2));
    return entry;
  }

  async forkBranch(sessionId: string, fromEntryId: string, newBranchId: string): Promise<SessionManifest> {
    const manifest = await this.loadManifest(sessionId);
    if (!manifest) {
      throw new Error(`Cannot fork unknown session: ${sessionId}`);
    }
    const updated: SessionManifest = {
      ...manifest,
      activeBranchId: newBranchId,
      headEntryId: fromEntryId,
      updatedAt: new Date().toISOString(),
    };
    await atomicWriteFile(this.manifestPath(sessionId), JSON.stringify(updated, null, 2));
    return updated;
  }
}

// ---------------------------------------------------------------------------
// 2. 250ms Activity Pulse Controller
// ---------------------------------------------------------------------------

function mapPhaseToAvatarState(phase: HarnessExecutionPhase, provider: HarnessProvider): AvatarState53 {
  switch (phase) {
    case 'initializing':
    case 'recalling_memory':
      return 'memory-recall';
    case 'streaming_model':
      if (provider === 'byok') return 'byok-streaming';
      return 'deep-reasoning';
    case 'executing_tool':
      if (provider === 'pi') return 'pi-coding';
      if (provider === 'claude-code') return 'claude-routing';
      if (provider === 'codex') return 'codex-routing';
      if (provider === 'opencode') return 'opencode-routing';
      return 'pi-bash-running';
    case 'awaiting_mcp_relay':
      return 'mcp-bridging';
    case 'awaiting_human':
      return 'needs-you';
    case 'reflecting':
      return 'persona-updating';
    case 'completed':
      return 'synthesizing';
    case 'failed':
    case 'aborted':
      return 'fleet-degraded';
  }
}

export class ActivityPulseEmitter {
  private readonly sessionId: string;
  private readonly subSessionId?: string;
  private readonly provider: HarnessProvider;
  private readonly modelId?: string;
  private readonly onPulse?: (pulse: HarnessActivityPulse) => void;
  private readonly startedAt = Date.now();
  private seq = 0;
  private phase: HarnessExecutionPhase = 'initializing';
  private activeToolName?: string;
  private tokensEstimated = 0;
  private timer?: ReturnType<typeof setInterval>;

  constructor(params: {
    sessionId: string;
    subSessionId?: string;
    provider: HarnessProvider;
    modelId?: string;
    onPulse?: (pulse: HarnessActivityPulse) => void;
  }) {
    this.sessionId = params.sessionId;
    this.subSessionId = params.subSessionId;
    this.provider = params.provider;
    this.modelId = params.modelId;
    this.onPulse = params.onPulse;
  }

  start(): void {
    if (this.timer) return;
    this.emitNow();
    this.timer = setInterval(() => {
      this.emitNow();
    }, ACTIVITY_PULSE_INTERVAL_MS);
    if (typeof this.timer.unref === 'function') {
      this.timer.unref();
    }
  }

  update(patch: {
    phase?: HarnessExecutionPhase;
    activeToolName?: string;
    addTokens?: number;
  }): void {
    if (patch.phase !== undefined) this.phase = patch.phase;
    if (patch.activeToolName !== undefined) this.activeToolName = patch.activeToolName;
    if (patch.addTokens !== undefined) this.tokensEstimated += Math.max(0, patch.addTokens);
  }

  stop(finalPhase: HarnessExecutionPhase): HarnessActivityPulse {
    this.phase = finalPhase;
    this.activeToolName = undefined;
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = undefined;
    }
    return this.emitNow();
  }

  private emitNow(): HarnessActivityPulse {
    this.seq += 1;
    const pulse: HarnessActivityPulse = {
      sessionId: this.sessionId,
      subSessionId: this.subSessionId,
      provider: this.provider,
      modelId: this.modelId,
      phase: this.phase,
      pulseIntervalMs: ACTIVITY_PULSE_INTERVAL_MS,
      seq: this.seq,
      elapsedMs: Date.now() - this.startedAt,
      activeToolName: this.activeToolName,
      tokensEstimated: this.tokensEstimated,
      suggestedAvatarState: mapPhaseToAvatarState(this.phase, this.provider),
      timestamp: new Date().toISOString(),
    };
    this.onPulse?.(pulse);
    return pulse;
  }
}

// ---------------------------------------------------------------------------
// 3. Routed MCP Bridge (`routed-mcp-bridge.ts` Pattern + HTTP JSON-RPC Server)
// ---------------------------------------------------------------------------

export interface RoutedMcpBridgeOptions {
  bindHost?: string;
  port?: number;
  guardrail?: PipiPermissionGuardrail;
  onToolActivity?: (info: { toolName: string; phase: 'start' | 'end'; isError?: boolean }) => void;
  onGuardrailBlocked?: (verdict: GuardrailVerdict, toolName: string) => void;
}

export class RoutedMcpBridge {
  private readonly tools = new Map<string, RegisteredMcpTool>();
  private readonly authToken = randomBytes(24).toString('hex');
  private readonly bindHost: string;
  private readonly requestedPort: number;
  readonly guardrail: PipiPermissionGuardrail;
  private readonly onToolActivity?: RoutedMcpBridgeOptions['onToolActivity'];
  private readonly onGuardrailBlocked?: RoutedMcpBridgeOptions['onGuardrailBlocked'];
  private server?: Server;
  private activePort?: number;

  constructor(options: RoutedMcpBridgeOptions = {}) {
    this.bindHost = options.bindHost ?? '127.0.0.1';
    this.requestedPort = options.port ?? 0;
    this.guardrail = options.guardrail ?? new PipiPermissionGuardrail();
    this.onToolActivity = options.onToolActivity;
    this.onGuardrailBlocked = options.onGuardrailBlocked;
    this.registerDefaultPipiTools();
  }

  private registerDefaultPipiTools(): void {
    this.registerTool(
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
            limit: { type: 'number', description: 'Maximum items to return (default 6)' },
          },
          required: ['query'],
          additionalProperties: false,
        },
        readOnlyHint: true,
      },
      async (args) => ({
        content: [
          {
            type: 'text',
            text: JSON.stringify({
              status: 'ok',
              query: String(args.query ?? ''),
              hint: 'Attach PipiMemoryEngine recall handler to override default stub.',
              items: [],
            }),
          },
        ],
      }),
    );

    this.registerTool(
      {
        name: 'pipibot_needs_you_escalate',
        description:
          'Escalate a high-impact decision (production infra mutation, force push, external message) to the user Needs-You Inbox on Mac and iOS.',
        inputSchema: {
          type: 'object',
          properties: {
            title: { type: 'string', description: 'Short decision title' },
            summary: { type: 'string', description: 'Context, risk, and verification evidence' },
            severity: { type: 'string', enum: ['info', 'warning', 'critical'] },
            recommendedOption: { type: 'string', description: 'Recommended action label' },
          },
          required: ['title', 'summary', 'severity'],
          additionalProperties: false,
        },
        requiresApproval: true,
      },
      async (args) => ({
        content: [
          {
            type: 'text',
            text: JSON.stringify({
              decisionId: `dec_${randomUUID()}`,
              status: 'pending_human_decision',
              title: args.title,
              severity: args.severity,
            }),
          },
        ],
      }),
    );

    this.registerTool(
      {
        name: 'pipibot_fleet_exec',
        description:
          'Execute an allowlisted diagnostic or outcome command on a PipiFleet node (mac, ios, vps, windows, embedded).',
        inputSchema: {
          type: 'object',
          properties: {
            nodeId: { type: 'string', description: 'Target node ID such as mac-studio or vps-hk-01' },
            command: { type: 'string', description: 'Command or capability action' },
          },
          required: ['nodeId', 'command'],
          additionalProperties: false,
        },
        requiresApproval: true,
      },
      async (args, ctx) => ({
        content: [
          {
            type: 'text',
            text: JSON.stringify({
              dispatched: true,
              sessionId: ctx.sessionId,
              nodeId: args.nodeId,
              command: args.command,
            }),
          },
        ],
      }),
    );

    this.registerTool(
      {
        name: 'pipibot_outcome_spawn',
        description: 'Delegate an isolated Sub-Session for parallel code verification or outcome investigation.',
        inputSchema: {
          type: 'object',
          properties: {
            role: { type: 'string', description: 'Sub-session role (e.g. verifier, triage)' },
            objective: { type: 'string', description: 'Outcome objective and acceptance criteria' },
            provider: { type: 'string', enum: ['pi', 'claude-code', 'codex', 'opencode', 'byok'] },
          },
          required: ['role', 'objective'],
          additionalProperties: false,
        },
      },
      async (args, ctx) => ({
        content: [
          {
            type: 'text',
            text: JSON.stringify({
              subSessionId: `sub_${randomUUID()}`,
              parentSessionId: ctx.sessionId,
              role: args.role,
              status: 'queued',
            }),
          },
        ],
      }),
    );

    this.registerTool(
      {
        name: 'pipibot_avatar_signal',
        description: 'Update the PipiAvatar procedural SVG state and expression on Mac MenuBar and iOS Dynamic Island.',
        inputSchema: {
          type: 'object',
          properties: {
            state: { type: 'string', description: 'One of the 53 AvatarState53 identifiers' },
            note: { type: 'string', description: 'Optional status whisper' },
          },
          required: ['state'],
          additionalProperties: false,
        },
      },
      async (args) => ({
        content: [{ type: 'text', text: JSON.stringify({ acknowledged: true, state: args.state }) }],
      }),
    );
  }

  registerTool(definition: RoutedMcpToolDefinition, handler: RoutedMcpToolHandler): void {
    this.tools.set(definition.name, { definition, handler });
  }

  listRoutedMcpTools(): RoutedMcpToolDefinition[] {
    return Array.from(this.tools.values()).map((item) => item.definition);
  }

  async executeRoutedMcpTool(
    toolName: string,
    args: Record<string, unknown>,
    ctx: RoutedMcpToolContext,
  ): Promise<RoutedMcpToolResult> {
    const entry = this.tools.get(toolName);
    if (!entry) {
      return {
        isError: true,
        content: [{ type: 'text', text: `Unknown routed MCP tool: ${toolName}` }],
      };
    }

    // Two-tier static guardrail + idempotency ledger check before running non-card tools
    const isProductCardTool = toolName === 'pipibot_needs_you_escalate' || toolName === 'pipibot_avatar_signal';
    const operationId = ctx.operationId ?? (typeof args.operationId === 'string' ? args.operationId : `op_${randomUUID().slice(0, 8)}`);
    if (!isProductCardTool) {
      const actionKind: ActionKind = entry.definition.readOnlyHint
        ? 'read_only'
        : entry.definition.requiresApproval
          ? 'external_effect'
          : 'local_write';
      const target = String(args.nodeId ?? args.path ?? args.target ?? ctx.workspacePath ?? '');
      const verdict = await this.guardrail.evaluate({
        operationId,
        toolName,
        actionKind,
        target,
        payloadSummary: JSON.stringify(args),
        isPreparatoryOnly: Boolean(entry.definition.readOnlyHint),
        sessionId: ctx.sessionId,
        projectId: ctx.projectId,
        sourceTrust: ctx.sourceTrust ?? 'trusted_user',
        trustedUserMessages: ctx.trustedUserMessages ?? [],
        untrustedContextSnippets: ctx.untrustedContextSnippets,
      });

      if (verdict.ruleId === 'idempotency.already_completed') {
        const prior = this.guardrail.ledger.get(operationId);
        return {
          content: [
            {
              type: 'text',
              text: prior?.cachedResultSummary ?? JSON.stringify({ status: 'idempotent_replay', operationId }),
            },
          ],
          structuredContent: { idempotentReplay: true, operationId, verdict },
        };
      }

      if (verdict.decision !== 'allow') {
        this.onGuardrailBlocked?.(verdict, toolName);
        if (verdict.decision === 'deny') {
          this.guardrail.ledger.markDenied(operationId);
        }
        return {
          isError: true,
          content: [
            {
              type: 'text',
              text: JSON.stringify({
                blockedByGuardrail: true,
                decision: verdict.decision,
                riskLevel: verdict.riskLevel,
                rationale: verdict.rationale,
                operationId: verdict.operationId,
              }),
            },
          ],
          structuredContent: { blockedByGuardrail: true, verdict },
        };
      }

      if (!entry.definition.readOnlyHint) {
        this.guardrail.ledger.markInFlight(operationId);
      }
    }

    this.onToolActivity?.({ toolName, phase: 'start' });
    try {
      const result = await entry.handler(args, ctx);
      if (!isProductCardTool && !entry.definition.readOnlyHint && !result.isError) {
        const firstText = result.content[0]?.text;
        this.guardrail.ledger.markCompleted(operationId, firstText);
      }
      this.onToolActivity?.({ toolName, phase: 'end', isError: Boolean(result.isError) });
      return result;
    } catch (error) {
      if (!isProductCardTool && !entry.definition.readOnlyHint) {
        this.guardrail.ledger.markUnknownOutcome(operationId, error instanceof Error ? error.message : String(error));
      }
      this.onToolActivity?.({ toolName, phase: 'end', isError: true });
      const message = error instanceof Error ? error.message : String(error);
      return {
        isError: true,
        content: [{ type: 'text', text: `Tool ${toolName} failed: ${message}` }],
      };
    }
  }

  getMcpUrl(): string | null {
    if (!this.activePort) return null;
    return `http://${this.bindHost}:${this.activePort}/mcp`;
  }

  async start(): Promise<string> {
    if (this.server && this.activePort) {
      return this.getMcpUrl()!;
    }

    this.server = createServer((req, res) => {
      void this.handleHttpRequest(req, res);
    });

    await new Promise<void>((resolve, reject) => {
      this.server!.once('error', reject);
      this.server!.listen(this.requestedPort, this.bindHost, () => {
        const address = this.server!.address();
        if (address && typeof address === 'object') {
          this.activePort = address.port;
        }
        resolve();
      });
    });

    return this.getMcpUrl()!;
  }

  async stop(): Promise<void> {
    if (!this.server) return;
    await new Promise<void>((resolve) => {
      this.server!.close(() => resolve());
    });
    this.server = undefined;
    this.activePort = undefined;
  }

  getMcpServerConfig(sessionId: string): Record<string, unknown> {
    const url = this.getMcpUrl();
    if (!url) {
      throw new Error('RoutedMcpBridge HTTP server is not running; call start() first.');
    }
    return {
      mcpServers: {
        'pipibot-routed-bridge': {
          type: 'http',
          url,
          headers: {
            Authorization: `Bearer ${this.authToken}`,
            'X-PipiBot-Session-Id': sessionId,
          },
        },
      },
    };
  }

  async writeMcpConfigFile(sessionId: string): Promise<string> {
    const configPath = join(tmpdir(), `pipibot-mcp-${sessionId}-${randomBytes(4).toString('hex')}.json`);
    await writeFile(configPath, JSON.stringify(this.getMcpServerConfig(sessionId), null, 2), 'utf8');
    return configPath;
  }

  private async handleHttpRequest(req: IncomingMessage, res: ServerResponse): Promise<void> {
    if (req.url !== '/mcp' || req.method !== 'POST') {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Not Found' }));
      return;
    }

    const authHeader = req.headers.authorization;
    if (authHeader !== `Bearer ${this.authToken}`) {
      res.writeHead(401, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Unauthorized' }));
      return;
    }

    const rawBody = await new Promise<string>((resolve, reject) => {
      const chunks: Buffer[] = [];
      req.on('data', (chunk: Buffer) => chunks.push(chunk));
      req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
      req.on('error', reject);
    });

    let rpc: { id?: string | number | null; method?: string; params?: Record<string, unknown> };
    try {
      rpc = JSON.parse(rawBody) as typeof rpc;
    } catch {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Parse error' } }));
      return;
    }

    const sessionId = String(req.headers['x-pipibot-session-id'] ?? 'mcp-http');

    if (rpc.method === 'initialize') {
      this.sendJsonRpc(res, rpc.id ?? null, {
        protocolVersion: '2025-03-26',
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: 'pipibot-routed-mcp-bridge', version: '0.1.0' },
      });
      return;
    }

    if (rpc.method === 'notifications/initialized' || rpc.method === 'ping') {
      this.sendJsonRpc(res, rpc.id ?? null, {});
      return;
    }

    if (rpc.method === 'tools/list') {
      this.sendJsonRpc(res, rpc.id ?? null, { tools: this.listRoutedMcpTools() });
      return;
    }

    if (rpc.method === 'tools/call') {
      const name = String(rpc.params?.name ?? '');
      const args = (rpc.params?.arguments ?? {}) as Record<string, unknown>;
      const result = await this.executeRoutedMcpTool(name, args, {
        sessionId,
        provider: 'claude-code',
        workspacePath: process.cwd(),
      });
      this.sendJsonRpc(res, rpc.id ?? null, result);
      return;
    }

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(
      JSON.stringify({
        jsonrpc: '2.0',
        id: rpc.id ?? null,
        error: { code: -32601, message: `Method not found: ${String(rpc.method)}` },
      }),
    );
  }

  private sendJsonRpc(res: ServerResponse, id: string | number | null, result: unknown): void {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ jsonrpc: '2.0', id, result }));
  }
}

// ---------------------------------------------------------------------------
// 4. Local CLI Detection (`pi`, `claude`, `codex`, `opencode`, `byok`)
// ---------------------------------------------------------------------------

async function pathExists(targetPath: string, executable = false): Promise<boolean> {
  try {
    await access(targetPath, executable ? fsConstants.X_OK : fsConstants.F_OK);
    return true;
  } catch {
    return false;
  }
}

async function resolveExecutableInPath(binaryName: string): Promise<string | undefined> {
  const envPath = process.env.PATH ?? '';
  const searchDirs = envPath.split(delimiter).filter(Boolean);
  const candidates = process.platform === 'win32'
    ? [binaryName, `${binaryName}.exe`, `${binaryName}.cmd`]
    : [binaryName];

  for (const dir of searchDirs) {
    for (const candidate of candidates) {
      const fullPath = join(dir, candidate);
      if (await pathExists(fullPath, true)) {
        return fullPath;
      }
    }
  }
  return undefined;
}

async function readVersionSafe(binaryPath: string): Promise<string | undefined> {
  return new Promise((resolve) => {
    const child = spawn(binaryPath, ['--version'], { stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    const timeout = setTimeout(() => {
      child.kill('SIGKILL');
      resolve(undefined);
    }, 2000);

    child.stdout.on('data', (chunk: Buffer) => {
      stdout += chunk.toString('utf8');
    });
    child.on('error', () => {
      clearTimeout(timeout);
      resolve(undefined);
    });
    child.on('close', (code) => {
      clearTimeout(timeout);
      if (code === 0) {
        resolve(stdout.trim().split('\n')[0]?.slice(0, 80));
      } else {
        resolve(undefined);
      }
    });
  });
}

export async function detectLocalHarnesses(byokConfigs: ByokProviderConfig[] = []): Promise<HarnessProbeResult[]> {
  const home = homedir();
  const now = new Date().toISOString();

  const specs: Array<{
    provider: Exclude<HarnessProvider, 'byok'>;
    binary: string;
    authPaths: string[];
    envVars: string[];
    supportsMcp: boolean;
  }> = [
    {
      provider: 'pi',
      binary: 'pi',
      authPaths: [join(home, '.pi', 'agent', 'auth.json'), join(home, '.pi', 'agent', 'models.json')],
      envVars: ['ANTHROPIC_API_KEY', 'OPENAI_API_KEY', 'GEMINI_API_KEY', 'OPENROUTER_API_KEY'],
      supportsMcp: false, // Pi uses native TypeScript extensions; PipiBot exposes bridge tools via extension hooks
    },
    {
      provider: 'claude-code',
      binary: 'claude',
      authPaths: [join(home, '.claude', '.credentials.json'), join(home, '.claude.json')],
      envVars: ['ANTHROPIC_API_KEY', 'CLAUDE_CODE_OAUTH_TOKEN'],
      supportsMcp: true,
    },
    {
      provider: 'codex',
      binary: 'codex',
      authPaths: [join(home, '.codex', 'auth.json'), join(home, '.codex', 'config.toml')],
      envVars: ['OPENAI_API_KEY'],
      supportsMcp: true,
    },
    {
      provider: 'opencode',
      binary: 'opencode',
      authPaths: [join(home, '.local', 'share', 'opencode', 'auth.json'), join(home, '.config', 'opencode', 'opencode.json')],
      envVars: ['OPENAI_API_KEY', 'ANTHROPIC_API_KEY', 'OPENROUTER_API_KEY'],
      supportsMcp: true,
    },
  ];

  const probes = await Promise.all(
    specs.map(async (spec): Promise<HarnessProbeResult> => {
      const binaryPath = await resolveExecutableInPath(spec.binary);
      const installed = Boolean(binaryPath);
      const version = binaryPath ? await readVersionSafe(binaryPath) : undefined;

      let authSource: string | undefined;
      for (const p of spec.authPaths) {
        if (await pathExists(p)) {
          authSource = p;
          break;
        }
      }
      if (!authSource) {
        for (const envKey of spec.envVars) {
          if (process.env[envKey]) {
            authSource = `env:${envKey}`;
            break;
          }
        }
      }

      return {
        provider: spec.provider,
        installed,
        authenticated: Boolean(authSource),
        binaryPath,
        version,
        authSource,
        supportsMcp: spec.supportsMcp,
        checkedAt: now,
      };
    }),
  );

  const hasByok = byokConfigs.some(
    (cfg) => Boolean(cfg.apiKey) || Boolean(cfg.apiKeyEnvVar && process.env[cfg.apiKeyEnvVar]) || cfg.vendor === 'ollama',
  );

  probes.push({
    provider: 'byok',
    installed: true,
    authenticated: hasByok,
    authSource: hasByok ? 'byok-config' : undefined,
    supportsMcp: true,
    checkedAt: now,
  });

  return probes;
}

// ---------------------------------------------------------------------------
// 5. Harness Drivers (Pi, Claude Code, Codex, OpenCode, BYOK pi-ai)
// ---------------------------------------------------------------------------

interface DriverExecutionContext {
  request: HarnessTurnRequest;
  pulse: ActivityPulseEmitter;
  mcpBridge: RoutedMcpBridge;
  extensions: PiExtensionHooks[];
  compiledPrompt: string;
}

interface DriverExecutionResult {
  text: string;
  modelId?: string;
  toolCallsExecuted: number;
  usage: TokenUsage;
}

export interface HarnessDriver {
  readonly provider: HarnessProvider;
  execute(ctx: DriverExecutionContext): Promise<DriverExecutionResult>;
}

function estimateTokens(text: string): number {
  return Math.max(1, Math.ceil(text.length / 4));
}

function spawnStreamingCli(params: {
  binary: string;
  args: string[];
  cwd: string;
  env?: Record<string, string | undefined>;
  stdinText?: string;
  signal?: AbortSignal;
  onLine: (line: string) => void;
  onStderr?: (chunk: string) => void;
}): Promise<{ exitCode: number; stderr: string }> {
  return new Promise((resolve, reject) => {
    const child: ChildProcess = spawn(params.binary, params.args, {
      cwd: params.cwd,
      env: { ...process.env, ...params.env },
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    let buffer = '';
    let stderr = '';

    const abortHandler = () => {
      child.kill('SIGTERM');
      setTimeout(() => {
        if (!child.killed) child.kill('SIGKILL');
      }, 1500);
    };

    if (params.signal) {
      if (params.signal.aborted) {
        abortHandler();
        reject(new Error('Harness execution aborted before start'));
        return;
      }
      params.signal.addEventListener('abort', abortHandler, { once: true });
    }

    child.stdout?.on('data', (chunk: Buffer) => {
      buffer += chunk.toString('utf8');
      let newlineIdx = buffer.indexOf('\n');
      while (newlineIdx !== -1) {
        const line = buffer.slice(0, newlineIdx).trim();
        buffer = buffer.slice(newlineIdx + 1);
        if (line.length > 0) params.onLine(line);
        newlineIdx = buffer.indexOf('\n');
      }
    });

    child.stderr?.on('data', (chunk: Buffer) => {
      const text = chunk.toString('utf8');
      stderr += text;
      params.onStderr?.(text);
    });

    child.on('error', (err) => {
      params.signal?.removeEventListener('abort', abortHandler);
      reject(err);
    });

    child.on('close', (code) => {
      params.signal?.removeEventListener('abort', abortHandler);
      const trailing = buffer.trim();
      if (trailing.length > 0) params.onLine(trailing);
      resolve({ exitCode: code ?? 1, stderr });
    });

    if (params.stdinText !== undefined && child.stdin) {
      child.stdin.write(params.stdinText);
      child.stdin.end();
    } else {
      child.stdin?.end();
    }
  });
}

/**
 * Driver 1: Native Pi Harness (`pi --mode json` / RPC event stream)
 * Respects Pi's 4-tool core (read, write, edit, bash) + TypeScript Extension Hooks.
 */
export class PiHarnessDriver implements HarnessDriver {
  readonly provider = 'pi' as const;

  async execute(ctx: DriverExecutionContext): Promise<DriverExecutionResult> {
    const binary = await resolveExecutableInPath('pi');
    if (!binary) {
      throw new Error('Pi CLI (`pi`) not found in PATH. Install `@mariozechner/pi-coding-agent` or switch harness.');
    }

    const args = ['--mode', 'json', '-p', ctx.compiledPrompt];
    if (ctx.request.modelId) {
      args.push('--model', ctx.request.modelId);
    }

    let text = '';
    let toolCallsExecuted = 0;

    ctx.pulse.update({ phase: 'streaming_model' });
    const { exitCode, stderr } = await spawnStreamingCli({
      binary,
      args,
      cwd: ctx.request.workspacePath,
      signal: ctx.request.signal,
      onLine: (line) => {
        try {
          const evt = JSON.parse(line) as Record<string, unknown>;
          if (evt.type === 'message_update' && typeof evt.delta === 'string') {
            text += evt.delta;
            ctx.pulse.update({ phase: 'streaming_model', addTokens: estimateTokens(evt.delta) });
            ctx.request.onEvent?.({ type: 'text_delta', delta: evt.delta });
          } else if (evt.type === 'tool_execution_start') {
            toolCallsExecuted += 1;
            const toolName = String(evt.toolName ?? 'bash');
            ctx.pulse.update({ phase: 'executing_tool', activeToolName: toolName });
            ctx.request.onEvent?.({
              type: 'tool_start',
              toolCallId: String(evt.toolCallId ?? randomUUID()),
              toolName,
              args: (evt.args as Record<string, unknown>) ?? {},
            });
          } else if (evt.type === 'tool_execution_end') {
            ctx.pulse.update({ phase: 'streaming_model', activeToolName: undefined });
            ctx.request.onEvent?.({
              type: 'tool_end',
              toolCallId: String(evt.toolCallId ?? ''),
              toolName: String(evt.toolName ?? 'bash'),
              isError: Boolean(evt.isError),
              output: String(evt.result ?? ''),
            });
          } else if (typeof evt.text === 'string' && evt.type === 'turn_end') {
            text = evt.text;
          }
        } catch {
          text += `${line}\n`;
          ctx.request.onEvent?.({ type: 'text_delta', delta: `${line}\n` });
        }
      },
    });

    if (exitCode !== 0 && text.trim().length === 0) {
      throw new Error(`Pi harness exited with code ${exitCode}: ${stderr.trim()}`);
    }

    return {
      text: text.trim(),
      modelId: ctx.request.modelId ?? 'pi-default',
      toolCallsExecuted,
      usage: {
        inputTokens: estimateTokens(ctx.compiledPrompt),
        outputTokens: estimateTokens(text),
        estimated: true,
      },
    };
  }
}

/**
 * Driver 2: Claude Code Adapter (`claude -p --output-format stream-json --mcp-config`)
 */
export class ClaudeCodeHarnessDriver implements HarnessDriver {
  readonly provider = 'claude-code' as const;

  async execute(ctx: DriverExecutionContext): Promise<DriverExecutionResult> {
    const binary = await resolveExecutableInPath('claude');
    if (!binary) {
      throw new Error('Claude Code CLI (`claude`) not found in PATH.');
    }

    let mcpConfigFile: string | undefined;
    const args = ['-p', ctx.compiledPrompt, '--output-format', 'stream-json', '--verbose'];
    if (ctx.request.modelId) {
      args.push('--model', ctx.request.modelId);
    }

    if (ctx.request.allowMcpBridge !== false) {
      await ctx.mcpBridge.start();
      mcpConfigFile = await ctx.mcpBridge.writeMcpConfigFile(ctx.request.sessionId);
      args.push('--mcp-config', mcpConfigFile);
    }

    let finalText = '';
    let streamedText = '';
    let toolCallsExecuted = 0;

    try {
      ctx.pulse.update({ phase: 'streaming_model' });
      const { exitCode, stderr } = await spawnStreamingCli({
        binary,
        args,
        cwd: ctx.request.workspacePath,
        signal: ctx.request.signal,
        onLine: (line) => {
          try {
            const evt = JSON.parse(line) as Record<string, unknown>;
            if (evt.type === 'assistant') {
              const message = evt.message as { content?: Array<Record<string, unknown>> } | undefined;
              for (const block of message?.content ?? []) {
                if (block.type === 'text' && typeof block.text === 'string') {
                  streamedText += block.text;
                  ctx.pulse.update({ phase: 'streaming_model', addTokens: estimateTokens(block.text) });
                  ctx.request.onEvent?.({ type: 'text_delta', delta: block.text });
                } else if (block.type === 'tool_use') {
                  toolCallsExecuted += 1;
                  const toolName = String(block.name ?? 'tool');
                  ctx.pulse.update({ phase: 'executing_tool', activeToolName: toolName });
                  ctx.request.onEvent?.({
                    type: 'tool_start',
                    toolCallId: String(block.id ?? randomUUID()),
                    toolName,
                    args: (block.input as Record<string, unknown>) ?? {},
                  });
                }
              }
            } else if (evt.type === 'result' && typeof evt.result === 'string') {
              finalText = evt.result;
            }
          } catch {
            // Ignore non-JSON diagnostic lines from CLI
          }
        },
      });

      const resolvedText = (finalText || streamedText).trim();
      if (exitCode !== 0 && resolvedText.length === 0) {
        throw new Error(`Claude Code CLI exited with code ${exitCode}: ${stderr.trim()}`);
      }

      return {
        text: resolvedText,
        modelId: ctx.request.modelId ?? 'claude-code-local',
        toolCallsExecuted,
        usage: {
          inputTokens: estimateTokens(ctx.compiledPrompt),
          outputTokens: estimateTokens(resolvedText),
          estimated: true,
        },
      };
    } finally {
      if (mcpConfigFile) {
        await rm(mcpConfigFile, { force: true }).catch(() => undefined);
      }
    }
  }
}

/**
 * Driver 3: Codex CLI Adapter (`codex exec --json`)
 */
export class CodexHarnessDriver implements HarnessDriver {
  readonly provider = 'codex' as const;

  async execute(ctx: DriverExecutionContext): Promise<DriverExecutionResult> {
    const binary = await resolveExecutableInPath('codex');
    if (!binary) {
      throw new Error('Codex CLI (`codex`) not found in PATH.');
    }

    const args = ['exec', '--json', ctx.compiledPrompt];
    if (ctx.request.modelId) {
      args.push('--model', ctx.request.modelId);
    }

    let text = '';
    let toolCallsExecuted = 0;
    ctx.pulse.update({ phase: 'streaming_model' });

    const { exitCode, stderr } = await spawnStreamingCli({
      binary,
      args,
      cwd: ctx.request.workspacePath,
      signal: ctx.request.signal,
      onLine: (line) => {
        try {
          const evt = JSON.parse(line) as Record<string, unknown>;
          const item = evt.item as Record<string, unknown> | undefined;
          if (evt.type === 'item.completed' && item?.type === 'agent_message' && typeof item.text === 'string') {
            text += item.text;
            ctx.pulse.update({ phase: 'streaming_model', addTokens: estimateTokens(item.text) });
            ctx.request.onEvent?.({ type: 'text_delta', delta: item.text });
          } else if (evt.type === 'item.started' && item?.type === 'command_execution') {
            toolCallsExecuted += 1;
            ctx.pulse.update({ phase: 'executing_tool', activeToolName: 'codex_shell' });
            ctx.request.onEvent?.({
              type: 'tool_start',
              toolCallId: String(item.id ?? randomUUID()),
              toolName: 'codex_shell',
              args: { command: item.command },
            });
          } else if (typeof evt.delta === 'string') {
            text += evt.delta;
            ctx.request.onEvent?.({ type: 'text_delta', delta: evt.delta });
          }
        } catch {
          text += `${line}\n`;
        }
      },
    });

    if (exitCode !== 0 && text.trim().length === 0) {
      throw new Error(`Codex CLI exited with code ${exitCode}: ${stderr.trim()}`);
    }

    return {
      text: text.trim(),
      modelId: ctx.request.modelId ?? 'codex-local',
      toolCallsExecuted,
      usage: {
        inputTokens: estimateTokens(ctx.compiledPrompt),
        outputTokens: estimateTokens(text),
        estimated: true,
      },
    };
  }
}

/**
 * Driver 4: OpenCode Adapter (HTTP/ACP server or `opencode run --format json`)
 */
export class OpenCodeHarnessDriver implements HarnessDriver {
  readonly provider = 'opencode' as const;

  async execute(ctx: DriverExecutionContext): Promise<DriverExecutionResult> {
    if (ctx.request.openCodeServerUrl) {
      return this.executeViaHttp(ctx, ctx.request.openCodeServerUrl);
    }

    const binary = await resolveExecutableInPath('opencode');
    if (!binary) {
      throw new Error('OpenCode CLI (`opencode`) not found in PATH and no openCodeServerUrl configured.');
    }

    const args = ['run', '--format', 'json', ctx.compiledPrompt];
    if (ctx.request.modelId) {
      args.push('--model', ctx.request.modelId);
    }

    let text = '';
    let toolCallsExecuted = 0;
    ctx.pulse.update({ phase: 'streaming_model' });

    const { exitCode, stderr } = await spawnStreamingCli({
      binary,
      args,
      cwd: ctx.request.workspacePath,
      signal: ctx.request.signal,
      onLine: (line) => {
        try {
          const evt = JSON.parse(line) as Record<string, unknown>;
          if (typeof evt.text === 'string') {
            text += evt.text;
            ctx.pulse.update({ phase: 'streaming_model', addTokens: estimateTokens(evt.text) });
            ctx.request.onEvent?.({ type: 'text_delta', delta: evt.text });
          } else if (evt.type === 'tool_use') {
            toolCallsExecuted += 1;
            ctx.pulse.update({ phase: 'executing_tool', activeToolName: String(evt.name ?? 'opencode_tool') });
          }
        } catch {
          text += `${line}\n`;
        }
      },
    });

    if (exitCode !== 0 && text.trim().length === 0) {
      throw new Error(`OpenCode CLI exited with code ${exitCode}: ${stderr.trim()}`);
    }

    return {
      text: text.trim(),
      modelId: ctx.request.modelId ?? 'opencode-local',
      toolCallsExecuted,
      usage: {
        inputTokens: estimateTokens(ctx.compiledPrompt),
        outputTokens: estimateTokens(text),
        estimated: true,
      },
    };
  }

  private async executeViaHttp(ctx: DriverExecutionContext, baseUrl: string): Promise<DriverExecutionResult> {
    ctx.pulse.update({ phase: 'streaming_model' });
    const cleanBase = baseUrl.replace(/\/+$/, '');
    const res = await fetch(`${cleanBase}/session/${encodeURIComponent(ctx.request.sessionId)}/message`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        parts: [{ type: 'text', text: ctx.compiledPrompt }],
        model: ctx.request.modelId,
      }),
      signal: ctx.request.signal,
    });

    if (!res.ok) {
      throw new Error(`OpenCode HTTP endpoint returned ${res.status}: ${await res.text()}`);
    }

    const data = (await res.json()) as { parts?: Array<{ type: string; text?: string }>; text?: string };
    const text =
      data.text ??
      (data.parts ?? [])
        .filter((part) => part.type === 'text' && typeof part.text === 'string')
        .map((part) => part.text)
        .join('');

    ctx.request.onEvent?.({ type: 'text_delta', delta: text });

    return {
      text,
      modelId: ctx.request.modelId ?? 'opencode-http',
      toolCallsExecuted: 0,
      usage: {
        inputTokens: estimateTokens(ctx.compiledPrompt),
        outputTokens: estimateTokens(text),
        estimated: true,
      },
    };
  }
}

/**
 * Driver 5: BYOK `pi-ai`-Compatible Direct API Router
 * Supports OpenAI-compatible (OpenAI, DeepSeek, X.AI, OpenRouter, vLLM, Ollama),
 * Anthropic Messages, and Google Gemini with multi-turn RoutedMcpBridge tool loop.
 */
export class ByokDirectHarnessDriver implements HarnessDriver {
  readonly provider = 'byok' as const;

  async execute(ctx: DriverExecutionContext): Promise<DriverExecutionResult> {
    const cfg = ctx.request.byokConfig;
    if (!cfg) {
      throw new Error('BYOK harness requires byokConfig.');
    }

    const apiKey = cfg.apiKey ?? (cfg.apiKeyEnvVar ? process.env[cfg.apiKeyEnvVar] : undefined);
    if (!apiKey && cfg.vendor !== 'ollama' && cfg.vendor !== 'vllm') {
      throw new Error(`Missing BYOK API key for vendor=${cfg.vendor} (env=${cfg.apiKeyEnvVar ?? 'unset'}).`);
    }

    if (cfg.api === 'anthropic-messages') {
      return this.runAnthropicLoop(ctx, cfg, apiKey!);
    }
    if (cfg.api === 'google-generative-ai') {
      return this.runGeminiRequest(ctx, cfg, apiKey!);
    }
    return this.runOpenAiCompatibleLoop(ctx, cfg, apiKey);
  }

  private async runOpenAiCompatibleLoop(
    ctx: DriverExecutionContext,
    cfg: ByokProviderConfig,
    apiKey?: string,
  ): Promise<DriverExecutionResult> {
    const maxIters = ctx.request.maxToolIterations ?? 16;
    const tools = cfg.supportsTools
      ? ctx.mcpBridge.listRoutedMcpTools().map((t) => ({
          type: 'function',
          function: { name: t.name, description: t.description, parameters: t.inputSchema },
        }))
      : undefined;

    const messages: Array<Record<string, unknown>> = [];
    if (ctx.request.systemPrompt) {
      messages.push({ role: 'system', content: ctx.request.systemPrompt });
    }
    messages.push({ role: 'user', content: ctx.compiledPrompt });

    let totalInput = 0;
    let totalOutput = 0;
    let toolCallsExecuted = 0;
    let finalText = '';

    for (let iter = 0; iter < maxIters; iter += 1) {
      ctx.pulse.update({ phase: 'streaming_model' });
      const endpoint = `${cfg.baseUrl.replace(/\/+$/, '')}/chat/completions`;
      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        ...(cfg.headers ?? {}),
      };
      if (apiKey) headers.Authorization = `Bearer ${apiKey}`;

      const res = await fetch(endpoint, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          model: ctx.request.modelId ?? cfg.modelId,
          messages,
          tools,
          max_tokens: cfg.maxOutputTokens,
        }),
        signal: ctx.request.signal,
      });

      if (!res.ok) {
        throw new Error(`BYOK ${cfg.vendor} HTTP ${res.status}: ${await res.text()}`);
      }

      const payload = (await res.json()) as {
        choices?: Array<{
          message?: {
            content?: string | null;
            tool_calls?: Array<{ id: string; function: { name: string; arguments: string } }>;
          };
        }>;
        usage?: { prompt_tokens?: number; completion_tokens?: number };
      };

      totalInput += payload.usage?.prompt_tokens ?? estimateTokens(ctx.compiledPrompt);
      totalOutput += payload.usage?.completion_tokens ?? 0;

      const msg = payload.choices?.[0]?.message;
      const content = msg?.content ?? '';
      if (content) {
        finalText = content;
        ctx.pulse.update({ addTokens: estimateTokens(content) });
        ctx.request.onEvent?.({ type: 'text_delta', delta: content });
      }

      const toolCalls = msg?.tool_calls ?? [];
      if (toolCalls.length === 0) {
        break;
      }

      messages.push({ role: 'assistant', content: content || null, tool_calls: toolCalls });

      for (const tc of toolCalls) {
        toolCallsExecuted += 1;
        let parsedArgs: Record<string, unknown> = {};
        try {
          parsedArgs = JSON.parse(tc.function.arguments || '{}') as Record<string, unknown>;
        } catch {
          parsedArgs = {};
        }

        const guarded = await this.runBeforeToolHooks(ctx, tc.function.name, parsedArgs);
        let result: RoutedMcpToolResult;

        if (!guarded.allow) {
          result = {
            isError: true,
            content: [{ type: 'text', text: `Blocked by Pi extension hook: ${guarded.reason ?? 'denied'}` }],
          };
        } else {
          ctx.pulse.update({ phase: 'executing_tool', activeToolName: tc.function.name });
          ctx.request.onEvent?.({
            type: 'tool_start',
            toolCallId: tc.id,
            toolName: tc.function.name,
            args: guarded.args,
          });
          result = await ctx.mcpBridge.executeRoutedMcpTool(tc.function.name, guarded.args, {
            sessionId: ctx.request.sessionId,
            subSessionId: ctx.request.subSessionId,
            provider: 'byok',
            workspacePath: ctx.request.workspacePath,
            signal: ctx.request.signal,
          });
        }

        await this.runAfterToolHooks(ctx, tc.function.name, result);
        const textOut = result.content.map((c) => c.text).join('\n');
        ctx.request.onEvent?.({
          type: 'tool_end',
          toolCallId: tc.id,
          toolName: tc.function.name,
          isError: Boolean(result.isError),
          output: textOut,
        });

        messages.push({
          role: 'tool',
          tool_call_id: tc.id,
          content: textOut,
        });
      }
    }

    return {
      text: finalText,
      modelId: ctx.request.modelId ?? cfg.modelId,
      toolCallsExecuted,
      usage: {
        inputTokens: totalInput,
        outputTokens: totalOutput || estimateTokens(finalText),
        estimated: totalOutput === 0,
      },
    };
  }

  private async runAnthropicLoop(
    ctx: DriverExecutionContext,
    cfg: ByokProviderConfig,
    apiKey: string,
  ): Promise<DriverExecutionResult> {
    const endpoint = `${cfg.baseUrl.replace(/\/+$/, '')}/v1/messages`;
    const tools = cfg.supportsTools
      ? ctx.mcpBridge.listRoutedMcpTools().map((t) => ({
          name: t.name,
          description: t.description,
          input_schema: t.inputSchema,
        }))
      : undefined;

    const messages: Array<Record<string, unknown>> = [{ role: 'user', content: ctx.compiledPrompt }];
    let finalText = '';
    let toolCallsExecuted = 0;
    let inputTokens = 0;
    let outputTokens = 0;
    const maxIters = ctx.request.maxToolIterations ?? 16;

    for (let iter = 0; iter < maxIters; iter += 1) {
      ctx.pulse.update({ phase: 'streaming_model' });
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          ...(cfg.headers ?? {}),
        },
        body: JSON.stringify({
          model: ctx.request.modelId ?? cfg.modelId,
          max_tokens: cfg.maxOutputTokens,
          system: ctx.request.systemPrompt,
          messages,
          tools,
        }),
        signal: ctx.request.signal,
      });

      if (!res.ok) {
        throw new Error(`BYOK Anthropic HTTP ${res.status}: ${await res.text()}`);
      }

      const data = (await res.json()) as {
        content?: Array<{ type: string; text?: string; id?: string; name?: string; input?: Record<string, unknown> }>;
        usage?: { input_tokens?: number; output_tokens?: number };
      };
      inputTokens += data.usage?.input_tokens ?? 0;
      outputTokens += data.usage?.output_tokens ?? 0;

      const blocks = data.content ?? [];
      const toolUses = blocks.filter((b) => b.type === 'tool_use');
      const textParts = blocks.filter((b) => b.type === 'text' && b.text).map((b) => b.text!);

      if (textParts.length > 0) {
        finalText = textParts.join('\n');
        ctx.request.onEvent?.({ type: 'text_delta', delta: finalText });
      }

      if (toolUses.length === 0) {
        break;
      }

      messages.push({ role: 'assistant', content: blocks });
      const toolResults: Array<Record<string, unknown>> = [];

      for (const tu of toolUses) {
        toolCallsExecuted += 1;
        const toolName = tu.name ?? 'unknown';
        const callId = tu.id ?? randomUUID();
        ctx.pulse.update({ phase: 'executing_tool', activeToolName: toolName });
        const result = await ctx.mcpBridge.executeRoutedMcpTool(toolName, tu.input ?? {}, {
          sessionId: ctx.request.sessionId,
          subSessionId: ctx.request.subSessionId,
          provider: 'byok',
          workspacePath: ctx.request.workspacePath,
          signal: ctx.request.signal,
        });
        toolResults.push({
          type: 'tool_result',
          tool_use_id: callId,
          content: result.content.map((c) => c.text).join('\n'),
          is_error: Boolean(result.isError),
        });
      }

      messages.push({ role: 'user', content: toolResults });
    }

    return {
      text: finalText,
      modelId: ctx.request.modelId ?? cfg.modelId,
      toolCallsExecuted,
      usage: { inputTokens, outputTokens, estimated: false },
    };
  }

  private async runGeminiRequest(
    ctx: DriverExecutionContext,
    cfg: ByokProviderConfig,
    apiKey: string,
  ): Promise<DriverExecutionResult> {
    ctx.pulse.update({ phase: 'streaming_model' });
    const model = ctx.request.modelId ?? cfg.modelId;
    const base = cfg.baseUrl.replace(/\/+$/, '');
    const endpoint = `${base}/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`;

    const res = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...(cfg.headers ?? {}) },
      body: JSON.stringify({
        systemInstruction: ctx.request.systemPrompt ? { parts: [{ text: ctx.request.systemPrompt }] } : undefined,
        contents: [{ role: 'user', parts: [{ text: ctx.compiledPrompt }] }],
        generationConfig: { maxOutputTokens: cfg.maxOutputTokens },
      }),
      signal: ctx.request.signal,
    });

    if (!res.ok) {
      throw new Error(`BYOK Gemini HTTP ${res.status}: ${await res.text()}`);
    }

    const payload = (await res.json()) as {
      candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
      usageMetadata?: { promptTokenCount?: number; candidatesTokenCount?: number };
    };
    const text = (payload.candidates?.[0]?.content?.parts ?? []).map((p) => p.text ?? '').join('');
    ctx.request.onEvent?.({ type: 'text_delta', delta: text });

    return {
      text,
      modelId: model,
      toolCallsExecuted: 0,
      usage: {
        inputTokens: payload.usageMetadata?.promptTokenCount ?? estimateTokens(ctx.compiledPrompt),
        outputTokens: payload.usageMetadata?.candidatesTokenCount ?? estimateTokens(text),
        estimated: !payload.usageMetadata,
      },
    };
  }

  private async runBeforeToolHooks(
    ctx: DriverExecutionContext,
    toolName: string,
    args: Record<string, unknown>,
  ): Promise<{ allow: boolean; reason?: string; args: Record<string, unknown> }> {
    let currentArgs = args;
    for (const hook of ctx.extensions) {
      if (!hook.beforeToolCall) continue;
      const decision = await hook.beforeToolCall(
        {
          sessionId: ctx.request.sessionId,
          workspacePath: ctx.request.workspacePath,
          provider: 'byok',
          toolName,
          toolArgs: currentArgs,
        },
      );
      if (!decision.allow) {
        return { allow: false, reason: decision.reason, args: currentArgs };
      }
      if (decision.mutatedArgs) {
        currentArgs = decision.mutatedArgs;
      }
    }
    return { allow: true, args: currentArgs };
  }

  private async runAfterToolHooks(
    ctx: DriverExecutionContext,
    toolName: string,
    result: RoutedMcpToolResult,
  ): Promise<void> {
    for (const hook of ctx.extensions) {
      if (hook.afterToolCall) {
        await hook.afterToolCall(
          { sessionId: ctx.request.sessionId, workspacePath: ctx.request.workspacePath, provider: 'byok', toolName },
          result,
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// 6. PipiHarnessRouter (Unified Orchestrator + Fallback Chain)
// ---------------------------------------------------------------------------

export interface PipiHarnessRouterOptions {
  transcriptStore?: AtomicTranscriptStore;
  mcpBridge?: RoutedMcpBridge;
  extensions?: PiExtensionHooks[];
  drivers?: Partial<Record<HarnessProvider, HarnessDriver>>;
}

export class PipiHarnessRouter {
  readonly transcriptStore: AtomicTranscriptStore;
  readonly mcpBridge: RoutedMcpBridge;
  private readonly extensions: PiExtensionHooks[];
  private readonly drivers: Record<HarnessProvider, HarnessDriver>;

  constructor(options: PipiHarnessRouterOptions = {}) {
    this.transcriptStore = options.transcriptStore ?? new AtomicTranscriptStore();
    this.mcpBridge = options.mcpBridge ?? new RoutedMcpBridge();
    this.extensions = options.extensions ?? [];
    this.drivers = {
      pi: options.drivers?.pi ?? new PiHarnessDriver(),
      'claude-code': options.drivers?.['claude-code'] ?? new ClaudeCodeHarnessDriver(),
      codex: options.drivers?.codex ?? new CodexHarnessDriver(),
      opencode: options.drivers?.opencode ?? new OpenCodeHarnessDriver(),
      byok: options.drivers?.byok ?? new ByokDirectHarnessDriver(),
    };
  }

  registerExtension(hooks: PiExtensionHooks): void {
    this.extensions.push(hooks);
  }

  async runTurn(request: HarnessTurnRequest): Promise<HarnessTurnResult> {
    const startedAt = Date.now();
    const branchId = request.branchId ?? 'main';

    let promptWithHooks = request.prompt;
    for (const hook of this.extensions) {
      if (hook.beforeTurn) {
        promptWithHooks = await hook.beforeTurn(
          {
            sessionId: request.sessionId,
            workspacePath: request.workspacePath,
            provider: request.preferredProvider,
          },
          promptWithHooks,
        );
      }
    }

    const compiledPrompt = request.memoryContextBlock
      ? `${request.memoryContextBlock}\n\n---\n\n${promptWithHooks}`
      : promptWithHooks;

    const existingManifest = await this.transcriptStore.loadManifest(request.sessionId);
    const userEntry = await this.transcriptStore.appendEntry({
      sessionId: request.sessionId,
      branchId,
      parentEntryId: request.parentEntryId ?? existingManifest?.headEntryId ?? null,
      role: 'user',
      provider: request.preferredProvider,
      modelId: request.modelId,
      content: request.prompt,
      tokensEstimated: estimateTokens(request.prompt),
      workspacePath: request.workspacePath,
    });

    const candidateChain: HarnessProvider[] = [
      request.preferredProvider,
      ...(request.fallbackProviders ?? []).filter((p) => p !== request.preferredProvider),
    ];

    const errors: string[] = [];

    for (let idx = 0; idx < candidateChain.length; idx += 1) {
      const provider = candidateChain[idx];
      if (!provider) continue;
      const driver = this.drivers[provider];
      const pulse = new ActivityPulseEmitter({
        sessionId: request.sessionId,
        subSessionId: request.subSessionId,
        provider,
        modelId: request.modelId ?? request.byokConfig?.modelId,
        onPulse: (p) => {
          request.onPulse?.(p);
          request.onEvent?.({ type: 'pulse', pulse: p });
        },
      });

      request.onEvent?.({
        type: 'session_started',
        sessionId: request.sessionId,
        provider,
        modelId: request.modelId ?? request.byokConfig?.modelId,
      });

      pulse.start();
      try {
        const result = await driver.execute({
          request,
          pulse,
          mcpBridge: this.mcpBridge,
          extensions: this.extensions,
          compiledPrompt,
        });

        pulse.stop('completed');

        const assistantEntry = await this.transcriptStore.appendEntry({
          sessionId: request.sessionId,
          branchId,
          parentEntryId: userEntry.id,
          role: 'assistant',
          provider,
          modelId: result.modelId,
          content: result.text,
          tokensEstimated: result.usage.outputTokens,
          workspacePath: request.workspacePath,
        });

        const turnResult: HarnessTurnResult = {
          sessionId: request.sessionId,
          branchId,
          assistantEntryId: assistantEntry.id,
          providerUsed: provider,
          modelId: result.modelId,
          text: result.text,
          toolCallsExecuted: result.toolCallsExecuted,
          usage: result.usage,
          durationMs: Date.now() - startedAt,
        };

        request.onEvent?.({
          type: 'turn_complete',
          text: result.text,
          provider,
          modelId: result.modelId,
          usage: result.usage,
        });

        for (const hook of this.extensions) {
          if (hook.afterTurn) {
            await hook.afterTurn(
              { sessionId: request.sessionId, workspacePath: request.workspacePath, provider },
              turnResult,
            );
          }
        }

        return turnResult;
      } catch (error) {
        pulse.stop(request.signal?.aborted ? 'aborted' : 'failed');
        const msg = error instanceof Error ? error.message : String(error);
        errors.push(`${provider}: ${msg}`);

        if (request.signal?.aborted) {
          throw new Error(`Harness turn aborted: ${msg}`);
        }

        const nextProvider = candidateChain[idx + 1];
        if (nextProvider) {
          request.onEvent?.({
            type: 'provider_fallback',
            from: provider,
            to: nextProvider,
            reason: msg,
          });
        }
      }
    }

    throw new Error(`All harness providers failed: ${errors.join(' | ')}`);
  }
}
