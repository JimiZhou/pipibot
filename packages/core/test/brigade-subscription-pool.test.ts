import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import {
  PipiSubscriptionAccountPool,
  classifySubscriptionError,
  defaultBaseUrlForSubscriptionProvider,
  subscriptionConfigDirEnvKey,
} from '../src/subscription-pool.ts';

test('Brigade Subscription Pool: stacks Claude & ChatGPT accounts with isolated dirs and scrubs API keys', () => {
  const dir = mkdtempSync(join(tmpdir(), 'pipibot-subpool-'));
  try {
    const pool = new PipiSubscriptionAccountPool({ dataDir: dir });

    const claude1 = pool.addAccount({
      label: 'Claude Max Primary',
      provider: 'claude_subscription',
      useSystemDefaultProfile: true,
      priority: 1,
    });
    const claude2 = pool.addAccount({
      label: 'Claude Pro Secondary',
      provider: 'claude_subscription',
      priority: 2,
    });
    const codex1 = pool.addAccount({
      label: 'ChatGPT Pro #1',
      provider: 'chatgpt_subscription',
      priority: 1,
    });

    assert.equal(claude1.useSystemDefaultProfile, true);
    assert.equal(claude1.profileDir, undefined);
    assert.ok(claude2.profileDir?.includes('subscriptions/claude/'));
    assert.ok(codex1.profileDir?.includes('subscriptions/chatgpt/'));

    const claude2Env = pool.buildCliEnvironment(claude2, {
      PATH: '/usr/bin',
      ANTHROPIC_API_KEY: 'sk-ant-should-be-stripped',
      OPENAI_API_KEY: 'sk-openai-untouched',
    });
    assert.equal(claude2Env[subscriptionConfigDirEnvKey('claude_subscription')], claude2.profileDir);
    assert.equal(claude2Env.ANTHROPIC_API_KEY, undefined);
    assert.equal(claude2Env.OPENAI_API_KEY, 'sk-openai-untouched');

    const codex1Env = pool.buildCliEnvironment(codex1, {
      PATH: '/usr/bin',
      OPENAI_API_KEY: 'sk-openai-should-be-stripped',
    });
    assert.equal(codex1Env.CODEX_HOME, codex1.profileDir);
    assert.equal(codex1Env.OPENAI_API_KEY, undefined);

    const loginCmd = pool.buildInteractiveLoginCommand(codex1);
    assert.ok(loginCmd.includes('CODEX_HOME=') && loginCmd.includes('codex login'));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('Brigade Subscription Pool: classifies usage limits, rotates mid-task on 429, and recovers after cooldown', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'pipibot-subfailover-'));
  try {
    let clock = Date.parse('2026-11-26T00:00:00.000Z');
    const pool = new PipiSubscriptionAccountPool({ dataDir: dir, nowMs: () => clock });

    const acc1 = pool.addAccount({ label: 'Claude #1', provider: 'claude_subscription', priority: 1 });
    const acc2 = pool.addAccount({ label: 'Claude #2', provider: 'claude_subscription', priority: 2 });

    const limitCheck = classifySubscriptionError('HTTP 429: You hit your usage limit. Try again in 30 minutes.');
    assert.equal(limitCheck.isRateLimited, true);
    assert.equal(limitCheck.cooldownMs, 30 * 60_000);

    const authCheck = classifySubscriptionError('401 Unauthorized: session expired, please log in');
    assert.equal(authCheck.isAuthExpired, true);

    const failovers: Array<{ from: string; to: string }> = [];
    const execRes = await pool.executeWithFailover(
      'claude_subscription',
      async ({ account }) => {
        if (account.id === acc1.id) {
          throw new Error('429 rate limit exceeded — resets in 20 minutes');
        }
        return { value: `completed-by-${account.label}`, estimatedTokens: 1200 };
      },
      {
        onFailover: (from, to) => failovers.push({ from: from.id, to: to.id }),
      },
    );

    assert.equal(execRes.value, 'completed-by-Claude #2');
    assert.equal(execRes.accountUsed.id, acc2.id);
    assert.equal(execRes.attempts, 2);
    assert.deepEqual(execRes.rotatedFromIds, [acc1.id]);
    assert.deepEqual(failovers, [{ from: acc1.id, to: acc2.id }]);

    const after1 = pool.getAccount(acc1.id)!;
    assert.equal(after1.status, 'rate_limited');
    assert.equal(after1.failoverCount, 1);

    // Advance virtual clock by 21 minutes -> acc1 automatically recovers to ready!
    clock += 21 * 60_000;
    const recovered = pool.getAccount(acc1.id)!;
    assert.equal(recovered.status, 'ready');
    assert.equal(recovered.cooldownUntil, undefined);

    // Round-robin & least-used selection
    pool.setStrategy('round_robin');
    const rr1 = pool.selectAccount('claude_subscription')!;
    const rr2 = pool.selectAccount('claude_subscription')!;
    assert.notEqual(rr1.id, rr2.id);

    pool.setStrategy('least_used');
    const lu = pool.selectAccount('claude_subscription')!;
    assert.equal(lu.id, acc1.id); // acc1 has 0 completed requests vs acc2's 1

    // Persistence across fresh instance
    const reloaded = new PipiSubscriptionAccountPool({ dataDir: dir, nowMs: () => clock });
    assert.equal(reloaded.getStrategy(), 'least_used');
    assert.equal(reloaded.listAccounts('claude_subscription').length, 2);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('Brigade Account Pool: stacks Mainland China & third-party OpenAI-compatible relays without persisting raw API keys', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'pipibot-cnpool-'));
  try {
    const pool = new PipiSubscriptionAccountPool({ dataDir: dir });

    assert.equal(defaultBaseUrlForSubscriptionProvider('kimi'), 'https://api.moonshot.cn/v1');
    assert.equal(defaultBaseUrlForSubscriptionProvider('zhipu'), 'https://open.bigmodel.cn/api/paas/v4');
    assert.equal(defaultBaseUrlForSubscriptionProvider('qwen'), 'https://dashscope.aliyuncs.com/compatible-mode/v1');
    assert.equal(defaultBaseUrlForSubscriptionProvider('minimax'), 'https://api.minimaxi.com/v1');
    assert.equal(defaultBaseUrlForSubscriptionProvider('volcengine'), 'https://ark.cn-beijing.volces.com/api/v3');
    assert.equal(defaultBaseUrlForSubscriptionProvider('siliconflow'), 'https://api.siliconflow.cn/v1');

    const relay1 = pool.addAccount({
      label: 'OneAPI Relay #1',
      provider: 'openai_compatible',
      baseUrl: 'https://relay-a.example.cn/v1',
      modelId: 'deepseek-chat',
      apiKey: 'sk-super-secret-relay-1',
      priority: 1,
    });
    const relay2 = pool.addAccount({
      label: 'OneAPI Relay #2',
      provider: 'openai_compatible',
      baseUrl: 'https://relay-b.example.cn/v1',
      modelId: 'deepseek-chat',
      apiKey: 'sk-super-secret-relay-2',
      priority: 2,
    });

    // Raw secrets must never be serialized to disk
    const persistedRaw = readFileSync(join(dir, 'subscription-pool.json'), 'utf8');
    assert.equal(persistedRaw.includes('sk-super-secret-relay-1'), false);
    assert.equal(persistedRaw.includes('sk-super-secret-relay-2'), false);

    // Failover automatically on Chinese quota / balance error (402 余额不足)
    const res = await pool.executeWithFailover('openai_compatible', async ({ account }) => {
      const reqCfg = pool.buildOpenAICompatibleRequestConfig(account, 'qwen3-coder-plus');
      if (account.id === relay1.id) {
        assert.equal(reqCfg.baseUrl, 'https://relay-a.example.cn/v1');
        assert.equal(reqCfg.headers.Authorization, 'Bearer sk-super-secret-relay-1');
        throw new Error('HTTP 402: 账户余额不足，请充值');
      }
      assert.equal(reqCfg.baseUrl, 'https://relay-b.example.cn/v1');
      assert.equal(reqCfg.modelId, 'qwen3-coder-plus');
      assert.equal(reqCfg.headers.Authorization, 'Bearer sk-super-secret-relay-2');
      return { value: `served-by-${account.label}`, estimatedTokens: 800 };
    });

    assert.equal(res.accountUsed.id, relay2.id);
    assert.equal(res.attempts, 2);
    assert.deepEqual(res.rotatedFromIds, [relay1.id]);
    assert.equal(pool.getAccount(relay1.id)?.status, 'rate_limited');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
