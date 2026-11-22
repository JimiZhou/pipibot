/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/daemon - group-router.ts
 * Three-Tier Fast Group Auto-Router (Explicit @ / Rules -> Lightweight Decision Model -> Fail-Open Lead).
 */

export interface GroupRouteCandidate {
  id: string;
  name: string;
  role: string;
  keywords?: string[];
}

export interface DecisionModelConfig {
  enabled: boolean;
  providerKind: 'local_fast' | 'cloudflare_workers_ai' | 'custom_openai_compat' | 'disabled';
  endpointUrl?: string;
  modelId?: string;
  accountId?: string;
  apiKey?: string;
  timeoutMs?: number;
  minConfidence?: number;
  maxAutoParallel?: number;
}

export interface GroupRouteResult {
  tier: 'explicit_mention' | 'deterministic_rule' | 'decision_model' | 'lead_fallback';
  picks: Array<{ botId: string; confidence: number; reason: string }>;
  latencyMs: number;
}

export async function routeGroupMessage(
  message: string,
  candidates: GroupRouteCandidate[],
  leadBotId: string,
  config: DecisionModelConfig,
  fetchFn: typeof fetch = fetch,
): Promise<GroupRouteResult> {
  const started = Date.now();
  const maxParallel = Math.max(1, Math.min(2, config.maxAutoParallel ?? 2));
  const minConf = config.minConfidence ?? 0.6;
  const lower = message.toLowerCase();

  // Tier 1A: Explicit @mention
  const explicit = candidates.filter(
    (c) => lower.includes(`@${c.name.toLowerCase()}`) || lower.includes(`@${c.id.toLowerCase()}`),
  );
  if (explicit.length > 0) {
    return {
      tier: 'explicit_mention',
      picks: explicit.map((c) => ({ botId: c.id, confidence: 1, reason: 'Explicit @mention' })),
      latencyMs: Date.now() - started,
    };
  }

  // Tier 1B: Deterministic keyword rules
  const ruleMatches = candidates
    .map((c) => ({
      c,
      hits: (c.keywords ?? []).filter((kw) => kw && lower.includes(kw.toLowerCase())).length,
    }))
    .filter((x) => x.hits >= 2)
    .sort((a, b) => b.hits - a.hits);

  if (ruleMatches.length > 0) {
    return {
      tier: 'deterministic_rule',
      picks: ruleMatches.slice(0, maxParallel).map((x) => ({
        botId: x.c.id,
        confidence: 0.88,
        reason: `Matched ${x.hits} domain rules`,
      })),
      latencyMs: Date.now() - started,
    };
  }

  // Tier 2: Fast Decision Model (1.5s timeout, fail-open)
  if (config.enabled && config.providerKind !== 'disabled' && config.endpointUrl) {
    try {
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), config.timeoutMs ?? 1500);
      const roster = candidates.map((c) => `- ${c.id} | ${c.name}: ${c.role}`).join('\n');
      const headers: Record<string, string> = { 'Content-Type': 'application/json' };
      if (config.apiKey) headers.Authorization = `Bearer ${config.apiKey}`;
      const res = await fetchFn(config.endpointUrl, {
        method: 'POST',
        headers,
        signal: ctrl.signal,
        body: JSON.stringify({
          model: config.modelId ?? 'qwen2.5:1.5b',
          messages: [
            {
              role: 'system',
              content: `Pick 1 to ${maxParallel} best bot IDs. Reply JSON only: {"picks":[{"botId":"...","confidence":0.9,"reason":"short"}]}\n${roster}`,
            },
            { role: 'user', content: message.slice(0, 500) },
          ],
          temperature: 0,
          max_tokens: 120,
        }),
      });
      clearTimeout(timer);
      if (res.ok) {
        const json = (await res.json()) as Record<string, unknown>;
        const rawText =
          (json.choices as Array<{ message?: { content?: string } }> | undefined)?.[0]?.message?.content ??
          (json.result as { response?: string } | undefined)?.response ??
          JSON.stringify(json);
        const startIdx = rawText.indexOf('{');
        const endIdx = rawText.lastIndexOf('}');
        if (startIdx >= 0 && endIdx > startIdx) {
          const parsed = JSON.parse(rawText.slice(startIdx, endIdx + 1)) as {
            picks?: Array<{ botId?: string; confidence?: number; reason?: string }>;
          };
          const valid = (parsed.picks ?? [])
            .filter(
              (p) =>
                p.botId &&
                (p.confidence ?? 0) >= minConf &&
                candidates.some((c) => c.id === p.botId),
            )
            .sort((a, b) => (b.confidence ?? 0) - (a.confidence ?? 0))
            .slice(0, maxParallel);
          if (valid.length > 0) {
            return {
              tier: 'decision_model',
              picks: valid.map((p) => ({
                botId: p.botId!,
                confidence: p.confidence!,
                reason: p.reason ?? 'Decision model',
              })),
              latencyMs: Date.now() - started,
            };
          }
        }
      }
    } catch {
      // Fail-open to lead fallback
    }
  }

  // Tier 3: Fail-open to Lead
  const lead = candidates.find((c) => c.id === leadBotId) ?? candidates[0];
  return {
    tier: 'lead_fallback',
    picks: lead ? [{ botId: lead.id, confidence: 0.5, reason: 'Fail-open to room lead' }] : [],
    latencyMs: Date.now() - started,
  };
}
