/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/core - subscription-pool.ts
 * Multi-Account Subscription Pool & Automatic Mid-Task Quota Failover:
 * - Reuses existing paid Claude (Pro/Max via `claude` CLI) & ChatGPT (Plus/Pro via `codex` CLI)
 *   and Gemini CLI subscriptions with zero separate per-token API bill.
 * - Stacks multiple accounts per provider using isolated CLI profile directories
 *   (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `GEMINI_CLI_HOME`) or system default profiles.
 * - Detects rate-limit / usage-cap errors and seamlessly rotates to the next healthy account.
 *
 * Runtime dependencies: strictly Node built-ins (`node:*`) only.
 */

import { randomUUID } from 'node:crypto';
import { chmodSync, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';

import type {
  SubscriptionAccountRecord,
  SubscriptionAccountStatus,
  SubscriptionPoolStrategy,
  SubscriptionProviderKind,
} from '@pipibot/protocol';

export interface AddSubscriptionAccountInput {
  id?: string;
  label: string;
  provider: SubscriptionProviderKind;
  planTier?: string;
  emailHint?: string;
  useSystemDefaultProfile?: boolean;
  profileDir?: string;
  /** For Mainland China & third-party OpenAI-compatible accounts/keys */
  baseUrl?: string;
  modelId?: string;
  /** Name of environment variable storing the API key (safe to persist) */
  apiKeyEnvVar?: string;
  /** Runtime-only API key held strictly in memory (never serialized to disk) */
  apiKey?: string;
  priority?: number;
}

export interface OpenAICompatibleAccountRequestConfig {
  accountId: string;
  provider: SubscriptionProviderKind;
  baseUrl: string;
  modelId: string;
  apiKey?: string;
  headers: Record<string, string>;
}

export interface SubscriptionPoolSnapshot {
  strategy: SubscriptionPoolStrategy;
  accounts: SubscriptionAccountRecord[];
  byProvider: Record<
    SubscriptionProviderKind,
    {
      total: number;
      available: number;
      rateLimited: number;
      totalRequests: number;
      totalFailovers: number;
    }
  >;
  updatedAt: string;
}

export interface RateLimitDetectionResult {
  isRateLimited: boolean;
  isAuthExpired: boolean;
  cooldownMs: number;
  reason?: string;
}

export interface FailoverExecutionResult<T> {
  value: T;
  accountUsed: SubscriptionAccountRecord;
  attempts: number;
  rotatedFromIds: string[];
}

interface PersistedSubscriptionPool {
  version: 1;
  strategy: SubscriptionPoolStrategy;
  roundRobinCursor: Partial<Record<SubscriptionProviderKind, number>>;
  accounts: SubscriptionAccountRecord[];
  updatedAt: string;
}

const DEFAULT_COOLDOWN_MS = 15 * 60_000;
const MAX_COOLDOWN_MS = 6 * 60 * 60_000;

export const ALL_SUBSCRIPTION_PROVIDERS: readonly SubscriptionProviderKind[] = [
  'claude_subscription',
  'chatgpt_subscription',
  'gemini_subscription',
  'deepseek',
  'kimi',
  'zhipu',
  'qwen',
  'minimax',
  'volcengine',
  'siliconflow',
  'openai_compatible',
];

export function isCliSubscriptionProvider(provider: SubscriptionProviderKind): boolean {
  return (
    provider === 'claude_subscription' ||
    provider === 'chatgpt_subscription' ||
    provider === 'gemini_subscription'
  );
}

export function isOpenAICompatiblePoolProvider(provider: SubscriptionProviderKind): boolean {
  return !isCliSubscriptionProvider(provider);
}

export function defaultBaseUrlForSubscriptionProvider(provider: SubscriptionProviderKind): string | undefined {
  switch (provider) {
    case 'deepseek':
      return 'https://api.deepseek.com/v1';
    case 'kimi':
      return 'https://api.moonshot.cn/v1';
    case 'zhipu':
      return 'https://open.bigmodel.cn/api/paas/v4';
    case 'qwen':
      return 'https://dashscope.aliyuncs.com/compatible-mode/v1';
    case 'minimax':
      return 'https://api.minimaxi.com/v1';
    case 'volcengine':
      return 'https://ark.cn-beijing.volces.com/api/v3';
    case 'siliconflow':
      return 'https://api.siliconflow.cn/v1';
    case 'openai_compatible':
      return 'https://api.openai.com/v1';
    default:
      return undefined;
  }
}

export function subscriptionConfigDirEnvKey(provider: SubscriptionProviderKind): string {
  switch (provider) {
    case 'claude_subscription':
      return 'CLAUDE_CONFIG_DIR';
    case 'chatgpt_subscription':
      return 'CODEX_HOME';
    case 'gemini_subscription':
      return 'GEMINI_CLI_HOME';
    default:
      return 'OPENAI_BASE_URL';
  }
}

export function subscriptionCliBinaryName(provider: SubscriptionProviderKind): string {
  switch (provider) {
    case 'claude_subscription':
      return 'claude';
    case 'chatgpt_subscription':
      return 'codex';
    case 'gemini_subscription':
      return 'gemini';
    default:
      return 'api';
  }
}

export function defaultModelsForSubscriptionProvider(provider: SubscriptionProviderKind): string[] {
  switch (provider) {
    case 'claude_subscription':
      return ['claude-opus-4-6', 'claude-sonnet-4-6', 'claude-haiku-4-5'];
    case 'chatgpt_subscription':
      return ['gpt-5.3-codex', 'gpt-5.2-codex', 'o3', 'gpt-5'];
    case 'gemini_subscription':
      return ['gemini-2.5-pro', 'gemini-2.5-flash'];
    case 'deepseek':
      return ['deepseek-chat', 'deepseek-reasoner'];
    case 'kimi':
      return ['kimi-k2-0905-preview', 'kimi-k2-thinking', 'moonshot-v1-128k'];
    case 'zhipu':
      return ['glm-4.6', 'glm-4.5', 'glm-4.5-air', 'glm-4-plus'];
    case 'qwen':
      return ['qwen3-coder-plus', 'qwen-max', 'qwen-plus', 'qwq-plus'];
    case 'minimax':
      return ['MiniMax-M2', 'MiniMax-M1', 'MiniMax-Text-01'];
    case 'volcengine':
      return ['doubao-seed-1-6-250615', 'doubao-1-5-pro-32k-250115', 'deepseek-v3-250324'];
    case 'siliconflow':
      return ['deepseek-ai/DeepSeek-V3', 'deepseek-ai/DeepSeek-R1', 'Qwen/Qwen3-Coder-480B-A35B-Instruct'];
    case 'openai_compatible':
      return ['gpt-4o', 'claude-sonnet-4-6', 'deepseek-chat', 'qwen-max'];
  }
}

/**
 * Classifies CLI/HTTP error text to detect consumer subscription quota exhaustion
 * (Claude Pro/Max 5-hour cap, ChatGPT Plus/Pro Codex rate limits, 429/529 bursts)
 * versus expired OAuth sessions.
 */
export function classifySubscriptionError(rawError: string): RateLimitDetectionResult {
  const msg = rawError.trim();
  const lower = msg.toLowerCase();

  const isAuthExpired =
    /\b(401|unauthorized|invalid_api_key|invalid api key|authentication_error|not logged in|please log in|authentication required|session expired|token expired|invalid_grant|login required)\b|鉴权失败|密钥无效/i.test(
      lower,
    );
  if (isAuthExpired) {
    return {
      isRateLimited: false,
      isAuthExpired: true,
      cooldownMs: 0,
      reason: msg.slice(0, 200) || 'Subscription / API account authentication failed',
    };
  }

  const isRateLimited =
    /\b(429|529|402|rate[_\s-]?limit|usage[_\s-]?limit|quota[_\s-]?exceeded|insufficient[_\s-]?quota|insufficient[_\s-]?balance|too many requests|overloaded|hit your limit|cap reached|limit reached|try again in|resets in|credit balance|tpm|rpm|qps)\b|余额不足|额度已用尽|额度不足|请求过于频繁|并发超限|触发限流/i.test(
      lower,
    );
  if (!isRateLimited) {
    return { isRateLimited: false, isAuthExpired: false, cooldownMs: 0 };
  }

  // Parse explicit retry/reset duration if mentioned (e.g. "try again in 45 minutes" or "resets in 2 hours")
  let cooldownMs = DEFAULT_COOLDOWN_MS;
  const hourMatch = lower.match(/(?:try again|resets?|wait|retry)\s+(?:in\s+)?(\d+)\s*(?:h|hr|hrs|hour|hours)\b/);
  const minMatch = lower.match(/(?:try again|resets?|wait|retry)\s+(?:in\s+)?(\d+)\s*(?:m|min|mins|minute|minutes)\b/);
  const secMatch = lower.match(/(?:try again|resets?|wait|retry)\s+(?:in\s+)?(\d+)\s*(?:s|sec|secs|second|seconds)\b/);

  if (hourMatch?.[1]) {
    cooldownMs = Number(hourMatch[1]) * 60 * 60_000;
  } else if (minMatch?.[1]) {
    cooldownMs = Number(minMatch[1]) * 60_000;
  } else if (secMatch?.[1]) {
    cooldownMs = Math.max(30_000, Number(secMatch[1]) * 1000);
  }

  cooldownMs = Math.max(30_000, Math.min(MAX_COOLDOWN_MS, cooldownMs));
  return {
    isRateLimited: true,
    isAuthExpired: false,
    cooldownMs,
    reason: msg.slice(0, 200) || 'Subscription usage limit reached',
  };
}

export class PipiSubscriptionAccountPool {
  private readonly dataDir: string;
  private readonly stateFilePath: string;
  private readonly nowMs: () => number;
  private strategy: SubscriptionPoolStrategy = 'priority_failover';
  private accounts: SubscriptionAccountRecord[] = [];
  private roundRobinCursor: Partial<Record<SubscriptionProviderKind, number>> = {};
  private readonly runtimeApiKeys = new Map<string, string>();

  constructor(options: { dataDir?: string; nowMs?: () => number; persist?: boolean } = {}) {
    this.dataDir = options.dataDir ?? join(homedir(), '.pipibot');
    this.stateFilePath = options.persist === false ? '' : join(this.dataDir, 'subscription-pool.json');
    this.nowMs = options.nowMs ?? (() => Date.now());
    this.load();
  }

  getStrategy(): SubscriptionPoolStrategy {
    return this.strategy;
  }

  setStrategy(strategy: SubscriptionPoolStrategy): void {
    this.strategy = strategy;
    this.save();
  }

  listAccounts(provider?: SubscriptionProviderKind): SubscriptionAccountRecord[] {
    this.recoverExpiredCooldowns();
    const filtered = provider ? this.accounts.filter((a) => a.provider === provider) : this.accounts;
    return filtered
      .slice()
      .sort((a, b) => a.priority - b.priority || a.createdAt.localeCompare(b.createdAt))
      .map((a) => ({ ...a }));
  }

  getAccount(accountId: string): SubscriptionAccountRecord | undefined {
    this.recoverExpiredCooldowns();
    const found = this.accounts.find((a) => a.id === accountId);
    return found ? { ...found } : undefined;
  }

  addAccount(input: AddSubscriptionAccountInput): SubscriptionAccountRecord {
    const nowIso = new Date(this.nowMs()).toISOString();
    const id = input.id?.trim() || `sub_${input.provider.split('_')[0]}_${randomUUID().slice(0, 8)}`;
    const existingIdx = this.accounts.findIndex((a) => a.id === id);

    const isApiPool = isOpenAICompatiblePoolProvider(input.provider);
    const useSystemDefault = isApiPool ? false : Boolean(input.useSystemDefaultProfile);
    const providerDirSlug = input.provider.replace('_subscription', '');
    const resolvedProfileDir =
      isApiPool || useSystemDefault
        ? undefined
        : input.profileDir?.trim() || join(this.dataDir, 'subscriptions', providerDirSlug, id);

    if (resolvedProfileDir && this.stateFilePath) {
      mkdirSync(resolvedProfileDir, { recursive: true, mode: 0o700 });
    }

    if (input.apiKey && input.apiKey.trim()) {
      this.runtimeApiKeys.set(id, input.apiKey.trim());
    }

    const defaultBaseUrl = defaultBaseUrlForSubscriptionProvider(input.provider);
    const resolvedBaseUrl = isApiPool
      ? (input.baseUrl?.trim() || defaultBaseUrl)
      : undefined;
    const resolvedModelId = input.modelId?.trim() || defaultModelsForSubscriptionProvider(input.provider)[0];
    const resolvedEnvVar = input.apiKeyEnvVar?.trim() || undefined;
    const hasKey = Boolean(
      this.runtimeApiKeys.has(id) || (resolvedEnvVar && process.env[resolvedEnvVar]?.trim()),
    );

    const sameProviderCount = this.accounts.filter((a) => a.provider === input.provider).length;
    const defaultTier = isApiPool
      ? (input.provider === 'openai_compatible' ? 'OpenAI Compatible' : `${providerDirSlug.toUpperCase()} API / Plan`)
      : input.provider === 'claude_subscription'
        ? 'Claude Max/Pro'
        : input.provider === 'chatgpt_subscription'
          ? 'ChatGPT Plus/Pro'
          : 'Gemini CLI';

    const record: SubscriptionAccountRecord = {
      id,
      label: input.label.trim() || `${providerDirSlug.toUpperCase()} #${sameProviderCount + 1}`,
      provider: input.provider,
      planTier: input.planTier?.trim() || defaultTier,
      emailHint: input.emailHint?.trim() || undefined,
      profileDir: resolvedProfileDir,
      useSystemDefaultProfile: useSystemDefault,
      baseUrl: resolvedBaseUrl,
      modelId: resolvedModelId,
      apiKeyEnvVar: resolvedEnvVar,
      hasApiKeyConfigured: isApiPool ? hasKey : undefined,
      priority: input.priority ?? sameProviderCount + 1,
      status: 'ready',
      requestsCount: existingIdx >= 0 ? this.accounts[existingIdx]!.requestsCount : 0,
      estimatedTokensUsed: existingIdx >= 0 ? this.accounts[existingIdx]!.estimatedTokensUsed : 0,
      failoverCount: existingIdx >= 0 ? this.accounts[existingIdx]!.failoverCount : 0,
      lastUsedAt: existingIdx >= 0 ? this.accounts[existingIdx]!.lastUsedAt : undefined,
      createdAt: existingIdx >= 0 ? this.accounts[existingIdx]!.createdAt : nowIso,
      updatedAt: nowIso,
    };

    if (existingIdx >= 0) {
      this.accounts[existingIdx] = record;
    } else {
      this.accounts.push(record);
    }
    this.save();
    return { ...record };
  }

  removeAccount(accountId: string): boolean {
    const before = this.accounts.length;
    this.accounts = this.accounts.filter((a) => a.id !== accountId);
    this.runtimeApiKeys.delete(accountId);
    if (this.accounts.length !== before) {
      this.save();
      return true;
    }
    return false;
  }

  resolveApiKey(account: SubscriptionAccountRecord, env: NodeJS.ProcessEnv = process.env): string | undefined {
    const inMem = this.runtimeApiKeys.get(account.id);
    if (inMem) return inMem;
    if (account.apiKeyEnvVar && env[account.apiKeyEnvVar]?.trim()) {
      return env[account.apiKeyEnvVar]!.trim();
    }
    return undefined;
  }

  /**
   * Builds an OpenAI-compatible HTTP request target for Mainland China providers
   * (DeepSeek / Kimi / Zhipu GLM / Qwen / MiniMax / Volcengine Ark / SiliconFlow)
   * or any third-party OpenAI-compatible relay.
   */
  buildOpenAICompatibleRequestConfig(
    account: SubscriptionAccountRecord,
    modelOverride?: string,
    env: NodeJS.ProcessEnv = process.env,
  ): OpenAICompatibleAccountRequestConfig {
    const baseUrl = (account.baseUrl || defaultBaseUrlForSubscriptionProvider(account.provider) || 'https://api.openai.com/v1').replace(
      /\/+$/,
      '',
    );
    const modelId = modelOverride?.trim() || account.modelId || defaultModelsForSubscriptionProvider(account.provider)[0] || 'gpt-4o';
    const apiKey = this.resolveApiKey(account, env);
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      ...(apiKey ? { Authorization: `Bearer ${apiKey}` } : {}),
    };
    return {
      accountId: account.id,
      provider: account.provider,
      baseUrl,
      modelId,
      apiKey,
      headers,
    };
  }

  setAccountStatus(accountId: string, status: SubscriptionAccountStatus, note?: string): SubscriptionAccountRecord | null {
    const acc = this.accounts.find((a) => a.id === accountId);
    if (!acc) return null;
    acc.status = status;
    if (status === 'ready') {
      acc.cooldownUntil = undefined;
      acc.rateLimitReason = undefined;
    } else if (note) {
      acc.rateLimitReason = note;
    }
    acc.updatedAt = new Date(this.nowMs()).toISOString();
    this.save();
    return { ...acc };
  }

  resetCooldown(accountId?: string): number {
    let resetCount = 0;
    const nowIso = new Date(this.nowMs()).toISOString();
    for (const acc of this.accounts) {
      if (accountId && acc.id !== accountId) continue;
      if (acc.status === 'rate_limited' || acc.cooldownUntil) {
        acc.status = 'ready';
        acc.cooldownUntil = undefined;
        acc.rateLimitReason = undefined;
        acc.updatedAt = nowIso;
        resetCount += 1;
      }
    }
    if (resetCount > 0) this.save();
    return resetCount;
  }

  /**
   * Builds isolated environment variables so the official `claude` / `codex` / `gemini` CLI
   * runs against this specific stacked subscription account without leaking pay-as-you-go API keys.
   */
  buildCliEnvironment(account: SubscriptionAccountRecord, baseEnv: NodeJS.ProcessEnv = process.env): Record<string, string> {
    const env: Record<string, string> = {};
    for (const [k, v] of Object.entries(baseEnv)) {
      if (v === undefined) continue;
      // Ensure consumer subscription login is used instead of accidentally billing API keys
      if (account.provider === 'claude_subscription' && (k === 'ANTHROPIC_API_KEY' || k === 'ANTHROPIC_AUTH_TOKEN')) {
        continue;
      }
      if (account.provider === 'chatgpt_subscription' && k === 'OPENAI_API_KEY') {
        continue;
      }
      if (account.provider === 'gemini_subscription' && (k === 'GEMINI_API_KEY' || k === 'GOOGLE_API_KEY')) {
        continue;
      }
      env[k] = v;
    }
    if (!account.useSystemDefaultProfile && account.profileDir) {
      env[subscriptionConfigDirEnvKey(account.provider)] = account.profileDir;
    }
    return env;
  }

  /**
   * Returns a shell login command the user can run once to authenticate an isolated stacked account.
   */
  buildInteractiveLoginCommand(account: SubscriptionAccountRecord): string {
    if (isOpenAICompatiblePoolProvider(account.provider)) {
      const envName = account.apiKeyEnvVar || `${account.provider.toUpperCase()}_API_KEY`;
      return `export ${envName}="<your-api-key>" # ${account.baseUrl ?? defaultBaseUrlForSubscriptionProvider(account.provider) ?? ''}`.trim();
    }
    const bin = subscriptionCliBinaryName(account.provider);
    const loginSub = account.provider === 'chatgpt_subscription' ? 'login' : '/login';
    if (account.useSystemDefaultProfile || !account.profileDir) {
      return `${bin} ${loginSub}`.trim();
    }
    const envKey = subscriptionConfigDirEnvKey(account.provider);
    const escaped = account.profileDir.replace(/'/g, "'\\''");
    return `${envKey}='${escaped}' ${bin} ${loginSub}`.trim();
  }

  /**
   * Selects the best currently available account for `provider` according to `strategy`,
   * honoring an optional pinned `preferredAccountId` unless it is excluded or cooling down.
   */
  selectAccount(
    provider: SubscriptionProviderKind,
    options: { preferredAccountId?: string; excludeIds?: readonly string[] } = {},
  ): SubscriptionAccountRecord | null {
    this.recoverExpiredCooldowns();
    const exclude = new Set(options.excludeIds ?? []);
    const candidates = this.accounts
      .filter((a) => a.provider === provider && !exclude.has(a.id) && (a.status === 'ready' || a.status === 'active'))
      .sort((a, b) => a.priority - b.priority || a.createdAt.localeCompare(b.createdAt));

    if (candidates.length === 0) return null;

    if (options.preferredAccountId) {
      const pinned = candidates.find((a) => a.id === options.preferredAccountId);
      if (pinned) return { ...pinned };
    }

    if (this.strategy === 'round_robin') {
      const cursor = this.roundRobinCursor[provider] ?? 0;
      const picked = candidates[cursor % candidates.length]!;
      this.roundRobinCursor[provider] = (cursor + 1) % candidates.length;
      this.save();
      return { ...picked };
    }

    if (this.strategy === 'least_used') {
      const sorted = candidates.slice().sort((a, b) => {
        if (a.requestsCount !== b.requestsCount) return a.requestsCount - b.requestsCount;
        if (a.estimatedTokensUsed !== b.estimatedTokensUsed) return a.estimatedTokensUsed - b.estimatedTokensUsed;
        return a.priority - b.priority;
      });
      return { ...sorted[0]! };
    }

    // priority_failover (default)
    return { ...candidates[0]! };
  }

  recordSuccess(accountId: string, estimatedTokens = 0): void {
    const acc = this.accounts.find((a) => a.id === accountId);
    if (!acc) return;
    const nowIso = new Date(this.nowMs()).toISOString();
    acc.status = 'ready';
    acc.cooldownUntil = undefined;
    acc.rateLimitReason = undefined;
    acc.requestsCount += 1;
    acc.estimatedTokensUsed += Math.max(0, Math.round(estimatedTokens));
    acc.lastUsedAt = nowIso;
    acc.updatedAt = nowIso;
    this.save();
  }

  markRateLimited(accountId: string, reason: string, cooldownMs = DEFAULT_COOLDOWN_MS): SubscriptionAccountRecord | null {
    const acc = this.accounts.find((a) => a.id === accountId);
    if (!acc) return null;
    const now = this.nowMs();
    acc.status = 'rate_limited';
    acc.cooldownUntil = new Date(now + Math.max(30_000, cooldownMs)).toISOString();
    acc.rateLimitReason = reason.slice(0, 240);
    acc.failoverCount += 1;
    acc.updatedAt = new Date(now).toISOString();
    this.save();
    return { ...acc };
  }

  markAuthExpired(accountId: string, reason: string): SubscriptionAccountRecord | null {
    const acc = this.accounts.find((a) => a.id === accountId);
    if (!acc) return null;
    acc.status = 'auth_expired';
    acc.rateLimitReason = reason.slice(0, 240);
    acc.updatedAt = new Date(this.nowMs()).toISOString();
    this.save();
    return { ...acc };
  }

  /**
   * Executes a work function with automatic mid-task failover across all stacked accounts
   * for the given subscription provider whenever a quota/rate-limit or expired-auth error occurs.
   */
  async executeWithFailover<T>(
    provider: SubscriptionProviderKind,
    work: (ctx: {
      account: SubscriptionAccountRecord;
      cliEnv: Record<string, string>;
      attempt: number;
    }) => Promise<{ value: T; estimatedTokens?: number }>,
    options: {
      preferredAccountId?: string;
      onFailover?: (from: SubscriptionAccountRecord, to: SubscriptionAccountRecord, reason: string) => void;
    } = {},
  ): Promise<FailoverExecutionResult<T>> {
    const triedIds: string[] = [];
    const rotatedFromIds: string[] = [];
    let attempts = 0;
    let lastError: Error | null = null;

    while (true) {
      const account = this.selectAccount(provider, {
        preferredAccountId: attempts === 0 ? options.preferredAccountId : undefined,
        excludeIds: triedIds,
      });

      if (!account) {
        if (lastError) {
          throw new Error(
            `All stacked ${provider} subscription accounts exhausted (${triedIds.length} tried): ${lastError.message}`,
          );
        }
        throw new Error(`No available ${provider} subscription account in pool.`);
      }

      attempts += 1;
      triedIds.push(account.id);
      const cliEnv = this.buildCliEnvironment(account);

      try {
        const result = await work({ account, cliEnv, attempt: attempts });
        this.recordSuccess(account.id, result.estimatedTokens ?? 0);
        return {
          value: result.value,
          accountUsed: this.getAccount(account.id) ?? account,
          attempts,
          rotatedFromIds,
        };
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        const classified = classifySubscriptionError(message);

        if (classified.isRateLimited) {
          this.markRateLimited(account.id, classified.reason ?? message, classified.cooldownMs);
          rotatedFromIds.push(account.id);
          lastError = err instanceof Error ? err : new Error(message);
          const peekNext = this.selectAccount(provider, { excludeIds: triedIds });
          if (peekNext) {
            options.onFailover?.(account, peekNext, classified.reason ?? message);
            continue;
          }
          throw new Error(
            `All stacked ${provider} subscription accounts rate-limited (${triedIds.length} tried): ${message}`,
          );
        }

        if (classified.isAuthExpired) {
          this.markAuthExpired(account.id, classified.reason ?? message);
          rotatedFromIds.push(account.id);
          lastError = err instanceof Error ? err : new Error(message);
          const peekNext = this.selectAccount(provider, { excludeIds: triedIds });
          if (peekNext) {
            options.onFailover?.(account, peekNext, classified.reason ?? message);
            continue;
          }
          throw err;
        }

        throw err;
      }
    }
  }

  getSnapshot(): SubscriptionPoolSnapshot {
    this.recoverExpiredCooldowns();
    const byProvider = {} as SubscriptionPoolSnapshot['byProvider'];
    for (const p of ALL_SUBSCRIPTION_PROVIDERS) {
      const list = this.accounts.filter((a) => a.provider === p);
      byProvider[p] = {
        total: list.length,
        available: list.filter((a) => a.status === 'ready' || a.status === 'active').length,
        rateLimited: list.filter((a) => a.status === 'rate_limited').length,
        totalRequests: list.reduce((sum, a) => sum + a.requestsCount, 0),
        totalFailovers: list.reduce((sum, a) => sum + a.failoverCount, 0),
      };
    }

    return {
      strategy: this.strategy,
      accounts: this.listAccounts(),
      byProvider,
      updatedAt: new Date(this.nowMs()).toISOString(),
    };
  }

  private recoverExpiredCooldowns(): void {
    const now = this.nowMs();
    let changed = false;
    for (const acc of this.accounts) {
      if (acc.status === 'rate_limited' && acc.cooldownUntil) {
        const until = Date.parse(acc.cooldownUntil);
        if (Number.isFinite(until) && now >= until) {
          acc.status = 'ready';
          acc.cooldownUntil = undefined;
          acc.rateLimitReason = undefined;
          acc.updatedAt = new Date(now).toISOString();
          changed = true;
        }
      }
    }
    if (changed) this.save();
  }

  private load(): void {
    if (!this.stateFilePath || !existsSync(this.stateFilePath)) return;
    try {
      const raw = readFileSync(this.stateFilePath, 'utf8');
      const parsed = JSON.parse(raw) as Partial<PersistedSubscriptionPool>;
      if (parsed.strategy) this.strategy = parsed.strategy;
      if (parsed.roundRobinCursor) this.roundRobinCursor = parsed.roundRobinCursor;
      if (Array.isArray(parsed.accounts)) this.accounts = parsed.accounts;
    } catch {
      // Corrupt or unreadable state file falls back to empty pool cleanly
    }
  }

  private save(): void {
    if (!this.stateFilePath) return;
    try {
      mkdirSync(dirname(this.stateFilePath), { recursive: true, mode: 0o700 });
      const payload: PersistedSubscriptionPool = {
        version: 1,
        strategy: this.strategy,
        roundRobinCursor: this.roundRobinCursor,
        accounts: this.accounts,
        updatedAt: new Date(this.nowMs()).toISOString(),
      };
      const tmp = `${this.stateFilePath}.tmp-${process.pid}-${randomUUID().slice(0, 6)}`;
      writeFileSync(tmp, `${JSON.stringify(payload, null, 2)}\n`, { mode: 0o600 });
      try {
        chmodSync(tmp, 0o600);
      } catch {
        // ignore chmod failures on non-POSIX filesystems
      }
      renameSync(tmp, this.stateFilePath);
    } catch {
      // Persistence errors must never crash scheduling
    }
  }
}
