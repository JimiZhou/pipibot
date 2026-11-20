/**
 * @pipibot/core — local-llm-gateway.ts (Wave 4 · #07)
 *
 * Clean-room MIT implementation of PiPiBot's unified loopback LLM Gateway
 * (`127.0.0.1`) and Isolated CLI Agent Reverse-Injection Environment Overlays.
 *
 * Key capabilities:
 * - Serves BOTH OpenAI-compatible (`/v1/chat/completions`, `/v1/models`) and
 *   Anthropic-compatible (`/v1/messages`, `/anthropic/v1/messages`) routes on
 *   loopback `127.0.0.1` only (zero LAN exposure), with per-instance bearer /
 *   `x-api-key` authentication.
 * - Auto-detects upstream API dialect (`openai` vs `anthropic`) and performs
 *   lossless OpenAI <-> Anthropic JSON & SSE streaming translation so Claude
 *   Code, Codex, Pi, and OpenCode can run transparently against local models
 *   (PolyStrata / llama.cpp / Ollama / MLX) or any BYOK endpoint.
 * - Reverse-injects into local CLI agents via isolated overlay directories
 *   (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `PI_CODING_AGENT_DIR`,
 *   `OPENCODE_CONFIG_DIR`) with `0700`/`0600` permissions — NEVER touching or
 *   mutating the user's personal `~/.claude`, `~/.codex`, or `~/.pi`.
 *
 * Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
 * Linger Open Source License; zero source code, prompts, or assets copied).
 * Optional MIT backend target: simplexai-labs/PolyStrata (MIT License). See root NOTICE.
 *
 * Runtime dependencies: strictly Node built-ins (`node:*`) only.
 */

import { randomBytes, timingSafeEqual } from 'node:crypto';
import { chmod, mkdir, writeFile } from 'node:fs/promises';
import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import { join, resolve } from 'node:path';

import type { ModelSourceMode } from '@pipibot/protocol';

// ---------------------------------------------------------------------------
// 1. Types & Contracts
// ---------------------------------------------------------------------------

export type GatewayUpstreamDialect = 'openai' | 'anthropic';

export type ReverseInjectedCliTarget = 'claude-code' | 'codex' | 'pi' | 'opencode';

export interface LocalGatewayUpstreamConfig {
  id: string;
  label: string;
  sourceMode: ModelSourceMode;
  dialect: GatewayUpstreamDialect;
  baseUrl: string;
  modelId: string;
  /** Kept in-memory / owner-only `0600` file or Keychain; never exposed in logs. */
  apiKey?: string;
  contextWindow?: number;
}

export interface LocalGatewayOptions {
  host?: string;
  port?: number;
  gatewayToken?: string;
  upstream: LocalGatewayUpstreamConfig;
  fetchImpl?: typeof fetch;
  onUnloadLocalModel?: () => Promise<void> | void;
}

export interface IsolatedCliOverlayResult {
  cli: ReverseInjectedCliTarget;
  overlayDir: string;
  configFilesWritten: string[];
  env: Record<string, string>;
  gatewayBaseUrl: string;
  modelId: string;
  /** Proves user's global `~/.claude` / `~/.codex` / `~/.pi` are left untouched. */
  untouchedGlobalHomeDirs: string[];
}

export interface ModelSourceSwitchRequest {
  targetMode: ModelSourceMode;
  newUpstream?: LocalGatewayUpstreamConfig;
  activeRunsCount: number;
  confirmedInterruptActiveRuns?: boolean;
}

export interface ModelSourceSwitchOutcome {
  switched: boolean;
  requiresConfirmation: boolean;
  previousMode: ModelSourceMode;
  currentMode: ModelSourceMode;
  unloadedLocalModel: boolean;
  message: string;
}

// ---------------------------------------------------------------------------
// 2. OpenAI <-> Anthropic Translation Helpers (Pure & Deterministic)
// ---------------------------------------------------------------------------

interface AnthropicMessageBlock {
  type: 'text' | 'tool_use' | 'tool_result';
  text?: string;
  id?: string;
  name?: string;
  input?: Record<string, unknown>;
  tool_use_id?: string;
  content?: string;
}

interface AnthropicRequestBody {
  model?: string;
  system?: string | Array<{ type: string; text?: string }>;
  messages?: Array<{
    role: 'user' | 'assistant';
    content: string | AnthropicMessageBlock[];
  }>;
  max_tokens?: number;
  temperature?: number;
  stream?: boolean;
}

interface OpenAIChatRequestBody {
  model?: string;
  messages?: Array<{
    role: 'system' | 'user' | 'assistant' | 'tool';
    content: string | Array<{ type: string; text?: string }>;
  }>;
  max_tokens?: number;
  temperature?: number;
  stream?: boolean;
}

export function flattenAnthropicText(
  content: string | AnthropicMessageBlock[] | Array<{ type: string; text?: string }> | undefined,
): string {
  if (!content) return '';
  if (typeof content === 'string') return content;
  return content
    .map((block) => {
      if (typeof block.text === 'string') return block.text;
      if ('content' in block && typeof block.content === 'string') return block.content;
      return '';
    })
    .filter(Boolean)
    .join('\n');
}

export function translateAnthropicToOpenAIRequest(
  body: AnthropicRequestBody,
  resolvedModel: string,
): OpenAIChatRequestBody {
  const messages: NonNullable<OpenAIChatRequestBody['messages']> = [];
  const sysText = flattenAnthropicText(body.system);
  if (sysText.trim().length > 0) {
    messages.push({ role: 'system', content: sysText });
  }
  for (const msg of body.messages ?? []) {
    messages.push({
      role: msg.role,
      content: flattenAnthropicText(msg.content),
    });
  }
  return {
    model: resolvedModel,
    messages,
    max_tokens: body.max_tokens ?? 2048,
    temperature: body.temperature,
    stream: Boolean(body.stream),
  };
}

export function translateOpenAIResponseToAnthropic(
  openaiPayload: Record<string, unknown>,
  fallbackModel: string,
): Record<string, unknown> {
  const choices = Array.isArray(openaiPayload.choices) ? openaiPayload.choices : [];
  const first = (choices[0] ?? {}) as Record<string, unknown>;
  const message = (first.message ?? {}) as Record<string, unknown>;
  const text = typeof message.content === 'string' ? message.content : '';
  const usage = (openaiPayload.usage ?? {}) as Record<string, unknown>;

  return {
    id: typeof openaiPayload.id === 'string' ? `msg_${openaiPayload.id}` : `msg_${randomBytes(6).toString('hex')}`,
    type: 'message',
    role: 'assistant',
    model: typeof openaiPayload.model === 'string' ? openaiPayload.model : fallbackModel,
    content: [{ type: 'text', text }],
    stop_reason: first.finish_reason === 'length' ? 'max_tokens' : 'end_turn',
    stop_sequence: null,
    usage: {
      input_tokens: typeof usage.prompt_tokens === 'number' ? usage.prompt_tokens : 0,
      output_tokens: typeof usage.completion_tokens === 'number' ? usage.completion_tokens : Math.ceil(text.length / 4),
    },
  };
}

export function translateOpenAIToAnthropicRequest(
  body: OpenAIChatRequestBody,
  resolvedModel: string,
): AnthropicRequestBody {
  const systemParts: string[] = [];
  const messages: NonNullable<AnthropicRequestBody['messages']> = [];
  for (const msg of body.messages ?? []) {
    const text = flattenAnthropicText(msg.content);
    if (msg.role === 'system') {
      if (text) systemParts.push(text);
    } else {
      messages.push({
        role: msg.role === 'assistant' ? 'assistant' : 'user',
        content: text,
      });
    }
  }
  return {
    model: resolvedModel,
    system: systemParts.length > 0 ? systemParts.join('\n\n') : undefined,
    messages,
    max_tokens: body.max_tokens ?? 2048,
    temperature: body.temperature,
    stream: Boolean(body.stream),
  };
}

export function translateAnthropicResponseToOpenAI(
  anthropicPayload: Record<string, unknown>,
  fallbackModel: string,
): Record<string, unknown> {
  const contentBlocks = Array.isArray(anthropicPayload.content)
    ? (anthropicPayload.content as AnthropicMessageBlock[])
    : [];
  const text = flattenAnthropicText(contentBlocks);
  const usage = (anthropicPayload.usage ?? {}) as Record<string, unknown>;
  const promptTokens = typeof usage.input_tokens === 'number' ? usage.input_tokens : 0;
  const completionTokens =
    typeof usage.output_tokens === 'number' ? usage.output_tokens : Math.ceil(text.length / 4);

  return {
    id: typeof anthropicPayload.id === 'string' ? `chatcmpl_${anthropicPayload.id}` : `chatcmpl_${randomBytes(6).toString('hex')}`,
    object: 'chat.completion',
    created: Math.floor(Date.now() / 1000),
    model: typeof anthropicPayload.model === 'string' ? anthropicPayload.model : fallbackModel,
    choices: [
      {
        index: 0,
        message: { role: 'assistant', content: text },
        finish_reason: anthropicPayload.stop_reason === 'max_tokens' ? 'length' : 'stop',
      },
    ],
    usage: {
      prompt_tokens: promptTokens,
      completion_tokens: completionTokens,
      total_tokens: promptTokens + completionTokens,
    },
  };
}

export function detectUpstreamDialectFromUrl(baseUrl: string): GatewayUpstreamDialect {
  const lower = baseUrl.trim().toLowerCase();
  if (lower.includes('api.anthropic.com') || lower.endsWith('/anthropic') || lower.includes('/anthropic/')) {
    return 'anthropic';
  }
  return 'openai';
}

// ---------------------------------------------------------------------------
// 3. Isolated CLI Agent Reverse-Injection Overlay Generator
// ---------------------------------------------------------------------------

/**
 * Materializes an isolated configuration overlay for a local CLI agent (`claude`,
 * `codex`, `pi`, `opencode`) pointing strictly to PiPiBot's local loopback Gateway
 * (`127.0.0.1:<port>`). Never touches the user's real `~/.claude`, `~/.codex`, or `~/.pi`.
 */
export async function prepareIsolatedCliOverlay(params: {
  dataRootDir: string;
  cli: ReverseInjectedCliTarget;
  profileId?: string;
  gatewayOrigin: string;
  gatewayToken: string;
  modelId: string;
  contextWindow?: number;
}): Promise<IsolatedCliOverlayResult> {
  const safeProfile = (params.profileId ?? 'default').replace(/[^a-zA-Z0-9._-]/g, '_');
  const overlayDir = resolve(params.dataRootDir, 'cli-overlays', params.cli, safeProfile);
  await mkdir(overlayDir, { recursive: true, mode: 0o700 });
  await chmod(overlayDir, 0o700).catch(() => undefined);

  const origin = params.gatewayOrigin.replace(/\/+$/, '');
  const written: string[] = [];
  const env: Record<string, string> = {};

  switch (params.cli) {
    case 'claude-code': {
      const settingsPath = join(overlayDir, 'settings.json');
      const settingsPayload = {
        env: {
          ANTHROPIC_BASE_URL: `${origin}/anthropic`,
          ANTHROPIC_AUTH_TOKEN: params.gatewayToken,
          ANTHROPIC_MODEL: params.modelId,
          CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: '1',
        },
        pipibotManagedOverlay: true,
      };
      await writeFile(settingsPath, `${JSON.stringify(settingsPayload, null, 2)}\n`, { mode: 0o600 });
      await chmod(settingsPath, 0o600).catch(() => undefined);
      written.push(settingsPath);

      env.CLAUDE_CONFIG_DIR = overlayDir;
      env.ANTHROPIC_BASE_URL = `${origin}/anthropic`;
      env.ANTHROPIC_AUTH_TOKEN = params.gatewayToken;
      env.ANTHROPIC_API_KEY = params.gatewayToken;
      env.ANTHROPIC_MODEL = params.modelId;
      env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1';
      break;
    }

    case 'codex': {
      const configPath = join(overlayDir, 'config.toml');
      const toml = [
        '# Auto-generated isolated Codex overlay by PiPiBot Local LLM Gateway.',
        '# User global ~/.codex/config.toml is never modified.',
        `model = "${params.modelId}"`,
        'model_provider = "pipibot_local_gateway"',
        '',
        '[model_providers.pipibot_local_gateway]',
        'name = "PiPiBot Local Gateway"',
        `base_url = "${origin}/v1"`,
        'env_key = "OPENAI_API_KEY"',
        'wire_api = "chat"',
        '',
      ].join('\n');
      await writeFile(configPath, toml, { mode: 0o600 });
      await chmod(configPath, 0o600).catch(() => undefined);
      written.push(configPath);

      env.CODEX_HOME = overlayDir;
      env.OPENAI_BASE_URL = `${origin}/v1`;
      env.OPENAI_API_KEY = params.gatewayToken;
      env.OPENAI_MODEL = params.modelId;
      break;
    }

    case 'pi': {
      const modelsPath = join(overlayDir, 'models.json');
      const modelsPayload = {
        providers: {
          pipibot_gateway: {
            baseUrl: `${origin}/v1`,
            apiKey: params.gatewayToken,
            api: 'openai-completions',
            models: [
              {
                id: params.modelId,
                name: `${params.modelId} (PiPiBot Local Gateway)`,
                contextWindow: params.contextWindow ?? 65_536,
                maxTokens: 8192,
              },
            ],
          },
        },
      };
      await writeFile(modelsPath, `${JSON.stringify(modelsPayload, null, 2)}\n`, { mode: 0o600 });
      await chmod(modelsPath, 0o600).catch(() => undefined);
      written.push(modelsPath);

      env.PI_CODING_AGENT_DIR = overlayDir;
      env.OPENAI_BASE_URL = `${origin}/v1`;
      env.OPENAI_API_KEY = params.gatewayToken;
      break;
    }

    case 'opencode': {
      const configPath = join(overlayDir, 'opencode.json');
      const configPayload = {
        provider: {
          pipibot_gateway: {
            npm: '@ai-sdk/openai-compatible',
            options: {
              baseURL: `${origin}/v1`,
              apiKey: params.gatewayToken,
            },
            models: {
              [params.modelId]: { name: params.modelId },
            },
          },
        },
        model: `pipibot_gateway/${params.modelId}`,
      };
      await writeFile(configPath, `${JSON.stringify(configPayload, null, 2)}\n`, { mode: 0o600 });
      await chmod(configPath, 0o600).catch(() => undefined);
      written.push(configPath);

      env.OPENCODE_CONFIG_DIR = overlayDir;
      env.OPENAI_BASE_URL = `${origin}/v1`;
      env.OPENAI_API_KEY = params.gatewayToken;
      break;
    }
  }

  return {
    cli: params.cli,
    overlayDir,
    configFilesWritten: written,
    env,
    gatewayBaseUrl: params.cli === 'claude-code' ? `${origin}/anthropic` : `${origin}/v1`,
    modelId: params.modelId,
    untouchedGlobalHomeDirs: ['~/.claude', '~/.claude.json', '~/.codex', '~/.pi', '~/.config/opencode'],
  };
}

// ---------------------------------------------------------------------------
// 4. Unified Loopback LLM Gateway Server (`127.0.0.1` only)
// ---------------------------------------------------------------------------

async function readJsonBody(req: IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  for await (const chunk of req) {
    chunks.push(typeof chunk === 'string' ? Buffer.from(chunk) : chunk);
  }
  const raw = Buffer.concat(chunks).toString('utf8').trim();
  if (!raw) return {};
  return JSON.parse(raw) as Record<string, unknown>;
}

function constantTimeEquals(a: string, b: string): boolean {
  const ba = Buffer.from(a);
  const bb = Buffer.from(b);
  if (ba.length !== bb.length) return false;
  return timingSafeEqual(ba, bb);
}

export class PipiLocalLLMGateway {
  readonly #host: string;
  readonly #requestedPort: number;
  readonly #token: string;
  readonly #fetchImpl: typeof fetch;
  readonly #onUnloadLocalModel?: () => Promise<void> | void;
  #upstream: LocalGatewayUpstreamConfig;
  #server: Server | null = null;
  #boundPort = 0;
  #requestsServed = 0;

  constructor(options: LocalGatewayOptions) {
    // Strictly bind loopback only — never open LAN listener.
    const requestedHost = options.host ?? '127.0.0.1';
    if (requestedHost !== '127.0.0.1' && requestedHost !== 'localhost' && requestedHost !== '::1') {
      throw new Error(`PipiLocalLLMGateway refuses non-loopback host: ${requestedHost}`);
    }
    this.#host = requestedHost;
    this.#requestedPort = options.port ?? 0;
    this.#token = options.gatewayToken ?? `pipi_gw_${randomBytes(16).toString('hex')}`;
    this.#upstream = { ...options.upstream };
    this.#fetchImpl = options.fetchImpl ?? globalThis.fetch;
    this.#onUnloadLocalModel = options.onUnloadLocalModel;
  }

  get token(): string {
    return this.#token;
  }

  get port(): number {
    return this.#boundPort;
  }

  get origin(): string {
    return `http://${this.#host}:${this.#boundPort}`;
  }

  get upstream(): LocalGatewayUpstreamConfig {
    return { ...this.#upstream };
  }

  get requestsServed(): number {
    return this.#requestsServed;
  }

  get isRunning(): boolean {
    return this.#server !== null && this.#boundPort > 0;
  }

  async start(): Promise<{ origin: string; port: number; token: string }> {
    if (this.#server) {
      return { origin: this.origin, port: this.#boundPort, token: this.#token };
    }
    const server = createServer((req, res) => {
      void this.#handleRequest(req, res);
    });
    await new Promise<void>((resolveStart, rejectStart) => {
      server.once('error', rejectStart);
      server.listen(this.#requestedPort, this.#host, () => {
        server.off('error', rejectStart);
        resolveStart();
      });
    });
    const addr = server.address();
    if (!addr || typeof addr === 'string') {
      server.close();
      throw new Error('Failed to resolve bound loopback TCP port for PipiLocalLLMGateway.');
    }
    this.#server = server;
    this.#boundPort = addr.port;
    return { origin: this.origin, port: this.#boundPort, token: this.#token };
  }

  async stop(): Promise<void> {
    const server = this.#server;
    this.#server = null;
    this.#boundPort = 0;
    if (!server) return;
    await new Promise<void>((resolveClose) => {
      server.close(() => resolveClose());
    });
  }

  /**
   * Switches the active computer-wide model source mode with active-run safety guard.
   * Leaving `local_model` invokes `onUnloadLocalModel` to reclaim unified RAM / VRAM.
   */
  async requestModelSourceSwitch(req: ModelSourceSwitchRequest): Promise<ModelSourceSwitchOutcome> {
    const previousMode = this.#upstream.sourceMode;
    if (req.activeRunsCount > 0 && !req.confirmedInterruptActiveRuns) {
      return {
        switched: false,
        requiresConfirmation: true,
        previousMode,
        currentMode: previousMode,
        unloadedLocalModel: false,
        message: `${req.activeRunsCount} active run(s) in flight; confirm before switching model source.`,
      };
    }

    let unloadedLocalModel = false;
    if (previousMode === 'local_model' && req.targetMode !== 'local_model') {
      await this.#onUnloadLocalModel?.();
      unloadedLocalModel = true;
    }

    if (req.newUpstream) {
      this.#upstream = { ...req.newUpstream, sourceMode: req.targetMode };
    } else {
      this.#upstream = { ...this.#upstream, sourceMode: req.targetMode };
    }

    return {
      switched: true,
      requiresConfirmation: false,
      previousMode,
      currentMode: this.#upstream.sourceMode,
      unloadedLocalModel,
      message: `Switched model source from ${previousMode} to ${this.#upstream.sourceMode}.`,
    };
  }

  async prepareCliOverlay(
    dataRootDir: string,
    cli: ReverseInjectedCliTarget,
    profileId = 'default',
  ): Promise<IsolatedCliOverlayResult> {
    if (!this.isRunning) {
      throw new Error('Start PipiLocalLLMGateway before generating isolated CLI overlays.');
    }
    return prepareIsolatedCliOverlay({
      dataRootDir,
      cli,
      profileId,
      gatewayOrigin: this.origin,
      gatewayToken: this.#token,
      modelId: this.#upstream.modelId,
      contextWindow: this.#upstream.contextWindow,
    });
  }

  #isAuthorized(req: IncomingMessage): boolean {
    const authHeader = String(req.headers.authorization ?? '');
    if (authHeader.startsWith('Bearer ')) {
      const candidate = authHeader.slice(7).trim();
      if (constantTimeEquals(candidate, this.#token)) return true;
    }
    const apiKeyHeader = String(req.headers['x-api-key'] ?? '').trim();
    if (apiKeyHeader && constantTimeEquals(apiKeyHeader, this.#token)) return true;
    return false;
  }

  async #handleRequest(req: IncomingMessage, res: ServerResponse): Promise<void> {
    const urlPath = (req.url ?? '/').split('?')[0];

    if (req.method === 'GET' && urlPath === '/healthz') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(
        JSON.stringify({
          ok: true,
          sourceMode: this.#upstream.sourceMode,
          dialect: this.#upstream.dialect,
          modelId: this.#upstream.modelId,
          requestsServed: this.#requestsServed,
        }),
      );
      return;
    }

    if (!this.#isAuthorized(req)) {
      res.writeHead(401, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: { code: 'UNAUTHORIZED', message: 'Invalid local gateway token.' } }));
      return;
    }

    try {
      if (req.method === 'GET' && (urlPath === '/v1/models' || urlPath === '/anthropic/v1/models')) {
        this.#requestsServed += 1;
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            object: 'list',
            data: [
              {
                id: this.#upstream.modelId,
                object: 'model',
                owned_by: `pipibot:${this.#upstream.sourceMode}`,
                context_window: this.#upstream.contextWindow ?? 65_536,
              },
            ],
          }),
        );
        return;
      }

      if (req.method === 'POST' && urlPath === '/v1/chat/completions') {
        this.#requestsServed += 1;
        const body = (await readJsonBody(req)) as OpenAIChatRequestBody;
        await this.#handleOpenAIChat(body, res);
        return;
      }

      if (
        req.method === 'POST' &&
        (urlPath === '/v1/messages' || urlPath === '/anthropic/v1/messages')
      ) {
        this.#requestsServed += 1;
        const body = (await readJsonBody(req)) as AnthropicRequestBody;
        await this.#handleAnthropicMessages(body, res);
        return;
      }

      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: { code: 'NOT_FOUND', message: `Unsupported route ${urlPath}` } }));
    } catch (err) {
      res.writeHead(502, { 'Content-Type': 'application/json' });
      res.end(
        JSON.stringify({
          error: {
            code: 'UPSTREAM_ERROR',
            message: err instanceof Error ? err.message : String(err),
          },
        }),
      );
    }
  }

  async #callUpstreamOpenAI(body: OpenAIChatRequestBody): Promise<Record<string, unknown>> {
    const base = this.#upstream.baseUrl.replace(/\/+$/, '');
    const url = base.endsWith('/chat/completions') ? base : `${base}/chat/completions`;
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (this.#upstream.apiKey) {
      headers.Authorization = `Bearer ${this.#upstream.apiKey}`;
    }
    const resp = await this.#fetchImpl(url, {
      method: 'POST',
      headers,
      body: JSON.stringify({ ...body, model: this.#upstream.modelId, stream: false }),
    });
    if (!resp.ok) {
      const errText = await resp.text().catch(() => '');
      throw new Error(`Upstream OpenAI HTTP ${resp.status}: ${errText.slice(0, 200)}`);
    }
    return (await resp.json()) as Record<string, unknown>;
  }

  async #callUpstreamAnthropic(body: AnthropicRequestBody): Promise<Record<string, unknown>> {
    const base = this.#upstream.baseUrl.replace(/\/+$/, '');
    const url = base.endsWith('/messages')
      ? base
      : base.endsWith('/v1')
        ? `${base}/messages`
        : `${base}/v1/messages`;
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'anthropic-version': '2023-06-01',
    };
    if (this.#upstream.apiKey) {
      headers['x-api-key'] = this.#upstream.apiKey;
    }
    const resp = await this.#fetchImpl(url, {
      method: 'POST',
      headers,
      body: JSON.stringify({ ...body, model: this.#upstream.modelId, stream: false }),
    });
    if (!resp.ok) {
      const errText = await resp.text().catch(() => '');
      throw new Error(`Upstream Anthropic HTTP ${resp.status}: ${errText.slice(0, 200)}`);
    }
    return (await resp.json()) as Record<string, unknown>;
  }

  async #handleOpenAIChat(body: OpenAIChatRequestBody, res: ServerResponse): Promise<void> {
    const openaiResponse =
      this.#upstream.dialect === 'openai'
        ? await this.#callUpstreamOpenAI(body)
        : translateAnthropicResponseToOpenAI(
            await this.#callUpstreamAnthropic(
              translateOpenAIToAnthropicRequest(body, this.#upstream.modelId),
            ),
            this.#upstream.modelId,
          );

    if (body.stream) {
      const choices = Array.isArray(openaiResponse.choices) ? openaiResponse.choices : [];
      const first = (choices[0] ?? {}) as Record<string, unknown>;
      const msg = (first.message ?? {}) as Record<string, unknown>;
      const content = typeof msg.content === 'string' ? msg.content : '';
      const id = typeof openaiResponse.id === 'string' ? openaiResponse.id : `chatcmpl_${randomBytes(4).toString('hex')}`;
      const model = typeof openaiResponse.model === 'string' ? openaiResponse.model : this.#upstream.modelId;

      res.writeHead(200, {
        'Content-Type': 'text/event-stream; charset=utf-8',
        'Cache-Control': 'no-cache',
      });
      res.write(
        `data: ${JSON.stringify({
          id,
          object: 'chat.completion.chunk',
          model,
          choices: [{ index: 0, delta: { role: 'assistant', content }, finish_reason: null }],
        })}\n\n`,
      );
      res.write(
        `data: ${JSON.stringify({
          id,
          object: 'chat.completion.chunk',
          model,
          choices: [{ index: 0, delta: {}, finish_reason: 'stop' }],
        })}\n\n`,
      );
      res.write('data: [DONE]\n\n');
      res.end();
      return;
    }

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(openaiResponse));
  }

  async #handleAnthropicMessages(body: AnthropicRequestBody, res: ServerResponse): Promise<void> {
    const anthropicResponse =
      this.#upstream.dialect === 'anthropic'
        ? await this.#callUpstreamAnthropic(body)
        : translateOpenAIResponseToAnthropic(
            await this.#callUpstreamOpenAI(
              translateAnthropicToOpenAIRequest(body, this.#upstream.modelId),
            ),
            this.#upstream.modelId,
          );

    if (body.stream) {
      const blocks = Array.isArray(anthropicResponse.content)
        ? (anthropicResponse.content as AnthropicMessageBlock[])
        : [];
      const text = flattenAnthropicText(blocks);
      const msgId = typeof anthropicResponse.id === 'string' ? anthropicResponse.id : `msg_${randomBytes(4).toString('hex')}`;
      const model = typeof anthropicResponse.model === 'string' ? anthropicResponse.model : this.#upstream.modelId;

      res.writeHead(200, {
        'Content-Type': 'text/event-stream; charset=utf-8',
        'Cache-Control': 'no-cache',
      });
      res.write(
        `event: message_start\ndata: ${JSON.stringify({
          type: 'message_start',
          message: { id: msgId, type: 'message', role: 'assistant', model, content: [] },
        })}\n\n`,
      );
      res.write(
        `event: content_block_start\ndata: ${JSON.stringify({
          type: 'content_block_start',
          index: 0,
          content_block: { type: 'text', text: '' },
        })}\n\n`,
      );
      res.write(
        `event: content_block_delta\ndata: ${JSON.stringify({
          type: 'content_block_delta',
          index: 0,
          delta: { type: 'text_delta', text },
        })}\n\n`,
      );
      res.write(
        `event: content_block_stop\ndata: ${JSON.stringify({ type: 'content_block_stop', index: 0 })}\n\n`,
      );
      res.write(
        `event: message_delta\ndata: ${JSON.stringify({
          type: 'message_delta',
          delta: { stop_reason: 'end_turn', stop_sequence: null },
          usage: anthropicResponse.usage ?? { output_tokens: Math.ceil(text.length / 4) },
        })}\n\n`,
      );
      res.write(`event: message_stop\ndata: ${JSON.stringify({ type: 'message_stop' })}\n\n`);
      res.end();
      return;
    }

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(anthropicResponse));
  }
}
