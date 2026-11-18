/**
 * @pipibot/cloudflare-edge - worker.ts
 *
 * Production-ready $0/month Cloudflare Free-Tier Edge Relay for PipiBot:
 * - Zero Trust validation (Cloudflare Access JWT + JWKS RS256 / Service Tokens / Node HMAC)
 * - KV Presence Cache + Throttled D1 PipiFleet Registry (Mac, iOS, VPS, Windows, Embedded)
 * - Mac <-> iOS Tunnel Relay (HTTPS/WebSocket/SSE) with seamless Offline Webhook Queue fallback
 * - R2 Zero-Egress Artifact Upload, Free-Tier Quota Guard, HMAC Signed URLs & Range Streaming
 * - Devin-style Needs-You Decision Inbox + Nightly Evolution Diff Sync + APNs ES256 Push Bridge
 * - Scheduled 15m Cron cleanup within 100k req/day Free Tier
 */

import type {
  AccessIdentityContext,
  ApnsPushPayload,
  ArtifactPresignResponse,
  CloudflareRelayEnvelope,
  EvolutionSummary,
  FleetNodeTelemetry,
  NeedsYouDecision,
  OfflineWebhookItem,
  TunnelPresenceRecord,
} from '@pipibot/protocol';

// ---------------------------------------------------------------------------
// 1. Minimal Ambient Cloudflare Worker Bindings (Zero external @types deps)
// ---------------------------------------------------------------------------

interface D1Result<T = Record<string, unknown>> {
  results: T[];
  success: boolean;
  meta: { changes?: number; duration?: number };
}

interface D1PreparedStatement {
  bind(...values: unknown[]): D1PreparedStatement;
  first<T = Record<string, unknown>>(colName?: string): Promise<T | null>;
  all<T = Record<string, unknown>>(): Promise<D1Result<T>>;
  run(): Promise<D1Result>;
}

interface D1Database {
  prepare(query: string): D1PreparedStatement;
}

interface KVNamespace {
  get(key: string, type?: 'text' | 'json'): Promise<unknown>;
  put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void>;
  delete(key: string): Promise<void>;
}

interface R2ObjectBody {
  key: string;
  size: number;
  etag: string;
  httpMetadata?: { contentType?: string };
  body: ReadableStream<Uint8Array> | null;
}

interface R2Bucket {
  put(
    key: string,
    value: ReadableStream<Uint8Array> | ArrayBuffer | string | null,
    options?: { httpMetadata?: { contentType?: string }; customMetadata?: Record<string, string> },
  ): Promise<unknown>;
  get(key: string, options?: { range?: { offset?: number; length?: number; suffix?: number } }): Promise<R2ObjectBody | null>;
  delete(keys: string | string[]): Promise<void>;
}

interface ExecutionContext {
  waitUntil(promise: Promise<unknown>): void;
  passThroughOnException(): void;
}

interface ScheduledController {
  cron: string;
  scheduledTime: number;
}

interface CfWebSocket extends WebSocket {
  accept(): void;
}

declare const WebSocketPair: {
  new (): { 0: CfWebSocket; 1: CfWebSocket };
};

export interface Env {
  DB: D1Database;
  PRESENCE_KV: KVNamespace;
  ARTIFACTS_R2: R2Bucket;

  CF_ACCESS_TEAM_DOMAIN: string;
  CF_ACCESS_AUD?: string;
  ARTIFACT_HMAC_SECRET?: string;
  NODE_SHARED_SECRET?: string;

  APNS_KEY_PEM?: string;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_BUNDLE_ID?: string;

  PRESENCE_TTL_SEC?: string;
  D1_HEARTBEAT_SYNC_MIN_SEC?: string;
  ARTIFACT_SIGNING_TTL_SEC?: string;
  MAX_ARTIFACT_BYTES?: string;
  R2_FREE_TIER_SOFT_CAP_BYTES?: string;
  QUEUE_DEFAULT_TTL_SEC?: string;
  ALLOW_DEV_BYPASS?: string;
}

// ---------------------------------------------------------------------------
// 2. Encoding, Crypto & Response Helpers
// ---------------------------------------------------------------------------

const textEncoder = new TextEncoder();

function jsonResponse(data: unknown, status = 200, extraHeaders: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      ...extraHeaders,
    },
  });
}

function errorResponse(code: string, message: string, status = 400): Response {
  return jsonResponse({ error: { code, message } }, status);
}

function base64UrlToBytes(input: string): Uint8Array {
  const padded = input.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((input.length + 3) % 4);
  const binary = atob(padded);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    out[i] = binary.charCodeAt(i);
  }
  return out;
}

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.length; i += 1) {
    binary += String.fromCharCode(bytes[i] ?? 0);
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

async function importHmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey('raw', textEncoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, [
    'sign',
    'verify',
  ]);
}

async function signHmacHex(secret: string, message: string): Promise<string> {
  const key = await importHmacKey(secret);
  const sig = await crypto.subtle.sign('HMAC', key, textEncoder.encode(message));
  return bytesToHex(new Uint8Array(sig));
}

async function verifyHmacHex(secret: string, message: string, hexSig: string): Promise<boolean> {
  if (!/^[a-f0-9]{64}$/i.test(hexSig)) return false;
  const sigBytes = new Uint8Array(32);
  for (let i = 0; i < 32; i += 1) {
    sigBytes[i] = Number.parseInt(hexSig.slice(i * 2, i * 2 + 2), 16);
  }
  const key = await importHmacKey(secret);
  return crypto.subtle.verify('HMAC', key, sigBytes, textEncoder.encode(message));
}

// ---------------------------------------------------------------------------
// 3. Cloudflare Access Zero Trust Verification (JWT JWKS + Service Token + Node HMAC)
// ---------------------------------------------------------------------------

interface AccessJwtHeader {
  alg?: string;
  kid?: string;
}

interface AccessJwtPayload {
  aud?: string | string[];
  email?: string;
  sub?: string;
  iss?: string;
  exp?: number;
  nbf?: number;
  common_name?: string;
}

interface AccessJwk {
  kid: string;
  kty: string;
  n: string;
  e: string;
}

async function fetchAccessJwks(env: Env): Promise<AccessJwk[]> {
  const cacheKey = `cf_access_jwks:${env.CF_ACCESS_TEAM_DOMAIN}`;
  const cached = (await env.PRESENCE_KV.get(cacheKey, 'json')) as { keys?: AccessJwk[] } | null;
  if (cached?.keys && cached.keys.length > 0) {
    return cached.keys;
  }

  const certsUrl = `https://${env.CF_ACCESS_TEAM_DOMAIN}/cdn-cgi/access/certs`;
  const res = await fetch(certsUrl, { headers: { Accept: 'application/json' } });
  if (!res.ok) {
    throw new Error(`Failed to load Cloudflare Access JWKS: ${res.status}`);
  }
  const body = (await res.json()) as { keys?: AccessJwk[] };
  const keys = body.keys ?? [];
  if (keys.length > 0) {
    await env.PRESENCE_KV.put(cacheKey, JSON.stringify({ keys }), { expirationTtl: 3600 });
  }
  return keys;
}

async function verifyAccessJwt(token: string, env: Env): Promise<AccessIdentityContext | null> {
  const parts = token.split('.');
  const headerB64 = parts[0];
  const payloadB64 = parts[1];
  const sigB64 = parts[2];
  if (parts.length !== 3 || !headerB64 || !payloadB64 || !sigB64) return null;
  let header: AccessJwtHeader;
  let payload: AccessJwtPayload;
  try {
    header = JSON.parse(new TextDecoder().decode(base64UrlToBytes(headerB64))) as AccessJwtHeader;
    payload = JSON.parse(new TextDecoder().decode(base64UrlToBytes(payloadB64))) as AccessJwtPayload;
  } catch {
    return null;
  }

  const nowSec = Math.floor(Date.now() / 1000);
  if (typeof payload.exp !== 'number' || payload.exp < nowSec) return null;
  if (typeof payload.nbf === 'number' && payload.nbf > nowSec + 30) return null;

  const expectedIssuer = `https://${env.CF_ACCESS_TEAM_DOMAIN}`;
  if (payload.iss && payload.iss !== expectedIssuer) return null;

  if (env.CF_ACCESS_AUD) {
    const audList = Array.isArray(payload.aud) ? payload.aud : payload.aud ? [payload.aud] : [];
    if (!audList.includes(env.CF_ACCESS_AUD)) return null;
  }

  if (header.alg !== 'RS256' || !header.kid) return null;

  const jwks = await fetchAccessJwks(env);
  const matchingJwk = jwks.find((k) => k.kid === header.kid && k.kty === 'RSA');
  if (!matchingJwk) return null;

  const publicKey = await crypto.subtle.importKey(
    'jwk',
    { kty: 'RSA', n: matchingJwk.n, e: matchingJwk.e, alg: 'RS256', ext: true },
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify'],
  );

  const verified = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    publicKey,
    base64UrlToBytes(sigB64),
    textEncoder.encode(`${headerB64}.${payloadB64}`),
  );

  if (!verified) return null;

  return {
    authenticated: true,
    authKind: 'cf_access_jwt',
    email: payload.email ?? payload.common_name,
    subject: payload.sub,
    issuer: payload.iss,
  };
}

async function authenticateRequest(request: Request, env: Env, url: URL): Promise<AccessIdentityContext | null> {
  // 1. Cloudflare Access User JWT (Edge Proxy / iOS OIDC WebSession)
  const accessJwt = request.headers.get('Cf-Access-Jwt-Assertion');
  if (accessJwt) {
    const verified = await verifyAccessJwt(accessJwt, env);
    if (verified) return verified;
  }

  // 2. Cloudflare Access Service Token (validated by CF Access perimeter, attested via headers)
  const clientId = request.headers.get('Cf-Access-Client-Id');
  const accessEmail = request.headers.get('Cf-Access-Authenticated-User-Email');
  if (clientId && accessEmail) {
    return {
      authenticated: true,
      authKind: 'cf_service_token',
      clientId,
      email: accessEmail,
    };
  }

  // 3. Node HMAC Signature (for Mac / VPS / Embedded fleet daemons calling Worker directly)
  const nodeId = request.headers.get('X-Pipi-Node-Id');
  const timestampStr = request.headers.get('X-Pipi-Timestamp');
  const signature = request.headers.get('X-Pipi-Signature');
  if (nodeId && timestampStr && signature && env.NODE_SHARED_SECRET) {
    const ts = Number(timestampStr);
    const nowSec = Math.floor(Date.now() / 1000);
    if (Number.isFinite(ts) && Math.abs(nowSec - ts) <= 300) {
      const canonical = `${request.method}:${url.pathname}:${nodeId}:${timestampStr}`;
      const ok = await verifyHmacHex(env.NODE_SHARED_SECRET, canonical, signature);
      if (ok) {
        return {
          authenticated: true,
          authKind: 'node_hmac',
          subject: nodeId,
        };
      }
    }
  }

  // 4. Strict explicit dev bypass only (off in production)
  if (env.ALLOW_DEV_BYPASS === 'true') {
    return {
      authenticated: true,
      authKind: 'dev_bypass',
      email: 'dev@localhost',
    };
  }

  return null;
}

// ---------------------------------------------------------------------------
// 4. APNs Push Notification Bridge (ES256 JWT via Web Crypto)
// ---------------------------------------------------------------------------

async function buildApnsBearerJwt(env: Env): Promise<string | null> {
  if (!env.APNS_KEY_PEM || !env.APNS_KEY_ID || !env.APNS_TEAM_ID) return null;

  const pemBody = env.APNS_KEY_PEM
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s+/g, '');

  const derBinary = atob(pemBody);
  const derBytes = new Uint8Array(derBinary.length);
  for (let i = 0; i < derBinary.length; i += 1) {
    derBytes[i] = derBinary.charCodeAt(i);
  }

  const key = await crypto.subtle.importKey(
    'pkcs8',
    derBytes,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );

  const headerB64 = bytesToBase64Url(textEncoder.encode(JSON.stringify({ alg: 'ES256', kid: env.APNS_KEY_ID })));
  const claimsB64 = bytesToBase64Url(
    textEncoder.encode(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) })),
  );
  const signingInput = `${headerB64}.${claimsB64}`;
  const sigBuf = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, textEncoder.encode(signingInput));
  return `${signingInput}.${bytesToBase64Url(new Uint8Array(sigBuf))}`;
}

async function sendApnsAlert(env: Env, payload: ApnsPushPayload): Promise<number> {
  const jwt = await buildApnsBearerJwt(env);
  if (!jwt || !env.APNS_BUNDLE_ID) return 0;

  const rows = await env.DB.prepare('SELECT apns_token, environment FROM apns_device_tokens').all<{
    apns_token: string;
    environment: 'production' | 'sandbox';
  }>();

  let sent = 0;
  for (const row of rows.results) {
    const host = row.environment === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
    const res = await fetch(`https://${host}/3/device/${row.apns_token}`, {
      method: 'POST',
      headers: {
        authorization: `bearer ${jwt}`,
        'apns-topic': env.APNS_BUNDLE_ID,
        'apns-push-type': 'alert',
        'apns-priority': payload.category === 'NEEDS_YOU_DECISION' ? '10' : '5',
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        aps: {
          alert: { title: payload.title, subtitle: payload.subtitle, body: payload.body },
          sound: payload.category === 'NEEDS_YOU_DECISION' ? 'default' : undefined,
          category: payload.category,
          badge: payload.badgeCount,
          'thread-id': payload.threadId,
        },
        decisionId: payload.decisionId,
        digestId: payload.digestId,
      }),
    });
    if (res.ok) sent += 1;
  }
  return sent;
}

// ---------------------------------------------------------------------------
// 5. Route Handlers: Fleet Presence, Relay, Offline Queue, R2, Decisions
// ---------------------------------------------------------------------------

async function writeAuditLog(
  env: Env,
  identity: AccessIdentityContext,
  action: string,
  resourceId: string | null,
  detail: Record<string, unknown> = {},
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO audit_log (id, actor_email, auth_kind, action, resource_id, detail_json, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      crypto.randomUUID(),
      identity.email ?? identity.subject ?? 'unknown',
      identity.authKind,
      action,
      resourceId,
      JSON.stringify(detail),
      new Date().toISOString(),
    )
    .run();
}

async function handleFleetHeartbeat(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
): Promise<Response> {
  const body = (await request.json()) as FleetNodeTelemetry & { tunnelUrl?: string };
  if (!body.nodeId || !body.kind) {
    return errorResponse('INVALID_PAYLOAD', 'nodeId and kind are required', 400);
  }

  const nowIso = new Date().toISOString();
  const presenceTtl = Number(env.PRESENCE_TTL_SEC ?? '90');
  const d1SyncMinSec = Number(env.D1_HEARTBEAT_SYNC_MIN_SEC ?? '300');

  const presenceRecord: TunnelPresenceRecord = {
    nodeId: body.nodeId,
    kind: body.kind,
    displayName: body.displayName || body.nodeId,
    vitality: body.vitality ?? 'alive',
    tunnelUrl: body.tunnelUrl,
    activeSessionsCount: body.activeSessionsCount ?? 0,
    tunnelRttMs: body.tunnelRttMs,
    batteryPct: body.batteryPct,
    lastSeenAt: nowIso,
  };

  // Hot path: write presence to KV (expires automatically after TTL)
  await env.PRESENCE_KV.put(`presence:${body.nodeId}`, JSON.stringify(presenceRecord), {
    expirationTtl: presenceTtl,
  });

  // Cold path throttling: only write D1 when vitality changes or sync window expires
  const syncMarkerKey = `d1sync:${body.nodeId}`;
  const lastSyncMarker = (await env.PRESENCE_KV.get(syncMarkerKey, 'text')) as string | null;
  const shouldSyncD1 = lastSyncMarker !== body.vitality;

  if (shouldSyncD1) {
    ctx.waitUntil(
      (async () => {
        await env.DB.prepare(
          `INSERT INTO fleet_nodes (
             node_id, display_name, kind, os_version, arch, vitality, tunnel_url,
             cpu_load_pct, memory_used_pct, battery_pct, tunnel_rtt_ms,
             active_sessions_count, capabilities_json, tags_json, last_seen_at, created_at, updated_at
           ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(node_id) DO UPDATE SET
             display_name = excluded.display_name,
             vitality = excluded.vitality,
             tunnel_url = COALESCE(excluded.tunnel_url, fleet_nodes.tunnel_url),
             cpu_load_pct = excluded.cpu_load_pct,
             memory_used_pct = excluded.memory_used_pct,
             battery_pct = excluded.battery_pct,
             tunnel_rtt_ms = excluded.tunnel_rtt_ms,
             active_sessions_count = excluded.active_sessions_count,
             capabilities_json = excluded.capabilities_json,
             tags_json = excluded.tags_json,
             last_seen_at = excluded.last_seen_at,
             updated_at = excluded.updated_at`,
        )
          .bind(
            body.nodeId,
            body.displayName || body.nodeId,
            body.kind,
            body.osVersion ?? 'unknown',
            body.arch ?? 'unknown',
            body.vitality ?? 'alive',
            body.tunnelUrl ?? null,
            body.cpuLoadPct ?? 0,
            body.memoryUsedPct ?? 0,
            body.batteryPct ?? null,
            body.tunnelRttMs ?? null,
            body.activeSessionsCount ?? 0,
            JSON.stringify(body.capabilities ?? {}),
            JSON.stringify(body.tags ?? []),
            nowIso,
            nowIso,
            nowIso,
          )
          .run();
        await env.PRESENCE_KV.put(syncMarkerKey, body.vitality ?? 'alive', {
          expirationTtl: d1SyncMinSec,
        });
      })(),
    );
  }

  return jsonResponse({ ok: true, nodeId: body.nodeId, syncedD1: shouldSyncD1, timestamp: nowIso });
}

async function handleListFleetNodes(env: Env): Promise<Response> {
  const rows = await env.DB.prepare(
    `SELECT node_id, display_name, kind, os_version, arch, vitality, tunnel_url,
            cpu_load_pct, memory_used_pct, battery_pct, tunnel_rtt_ms,
            active_sessions_count, capabilities_json, tags_json, last_seen_at
     FROM fleet_nodes ORDER BY last_seen_at DESC`,
  ).all<Record<string, unknown>>();

  const merged = await Promise.all(
    rows.results.map(async (row) => {
      const nodeId = String(row.node_id);
      const live = (await env.PRESENCE_KV.get(`presence:${nodeId}`, 'json')) as TunnelPresenceRecord | null;
      return {
        nodeId,
        displayName: live?.displayName ?? String(row.display_name),
        kind: row.kind,
        osVersion: row.os_version,
        arch: row.arch,
        vitality: live?.vitality ?? 'offline',
        tunnelUrl: live?.tunnelUrl ?? row.tunnel_url,
        cpuLoadPct: row.cpu_load_pct,
        memoryUsedPct: row.memory_used_pct,
        batteryPct: live?.batteryPct ?? row.battery_pct,
        tunnelRttMs: live?.tunnelRttMs ?? row.tunnel_rtt_ms,
        activeSessionsCount: live?.activeSessionsCount ?? row.active_sessions_count,
        capabilities: JSON.parse(String(row.capabilities_json || '{}')),
        tags: JSON.parse(String(row.tags_json || '[]')),
        lastSeenAt: live?.lastSeenAt ?? row.last_seen_at,
      };
    }),
  );

  return jsonResponse({ nodes: merged, count: merged.length });
}

async function enqueueOfflineItem(
  env: Env,
  item: {
    idempotencyKey: string;
    targetNodeId: string;
    source: OfflineWebhookItem['source'];
    eventType: string;
    payload: Record<string, unknown>;
    ttlSeconds?: number;
  },
): Promise<{ id: string; deduplicated: boolean }> {
  const nowMs = Date.now();
  const ttlSec = item.ttlSeconds ?? Number(env.QUEUE_DEFAULT_TTL_SEC ?? '259200');
  const id = crypto.randomUUID();
  const createdAt = new Date(nowMs).toISOString();
  const expiresAt = new Date(nowMs + ttlSec * 1000).toISOString();

  const existing = await env.DB.prepare(
    'SELECT id FROM offline_webhook_queue WHERE idempotency_key = ?',
  )
    .bind(item.idempotencyKey)
    .first<{ id: string }>();

  if (existing) {
    return { id: existing.id, deduplicated: true };
  }

  await env.DB.prepare(
    `INSERT INTO offline_webhook_queue (
       id, idempotency_key, target_node_id, source, event_type, payload_json,
       status, retry_count, created_at, expires_at
     ) VALUES (?, ?, ?, ?, ?, ?, 'pending', 0, ?, ?)`,
  )
    .bind(
      id,
      item.idempotencyKey,
      item.targetNodeId,
      item.source,
      item.eventType,
      JSON.stringify(item.payload),
      createdAt,
      expiresAt,
    )
    .run();

  return { id, deduplicated: false };
}

async function handleRelaySend(request: Request, env: Env): Promise<Response> {
  const envelope = (await request.json()) as CloudflareRelayEnvelope<Record<string, unknown>>;
  if (!envelope.targetNodeId || !envelope.type) {
    return errorResponse('INVALID_ENVELOPE', 'targetNodeId and type are required', 400);
  }

  const presence = (await env.PRESENCE_KV.get(
    `presence:${envelope.targetNodeId}`,
    'json',
  )) as TunnelPresenceRecord | null;

  if (presence && presence.vitality !== 'offline' && presence.tunnelUrl) {
    try {
      const targetUrl = `${presence.tunnelUrl.replace(/\/+$/, '')}/pipibot/relay`;
      const headers: Record<string, string> = { 'Content-Type': 'application/json' };
      if (env.NODE_SHARED_SECRET) {
        const ts = String(Math.floor(Date.now() / 1000));
        headers['X-Pipi-Edge-Timestamp'] = ts;
        headers['X-Pipi-Edge-Signature'] = await signHmacHex(
          env.NODE_SHARED_SECRET,
          `POST:/pipibot/relay:${envelope.targetNodeId}:${ts}`,
        );
      }

      const forwardRes = await fetch(targetUrl, {
        method: 'POST',
        headers,
        body: JSON.stringify(envelope),
      });

      if (forwardRes.ok) {
        return jsonResponse({
          delivered: true,
          mode: 'direct_cloudflared_tunnel',
          targetNodeId: envelope.targetNodeId,
        });
      }
    } catch {
      // Tunnel unreachable: fall through seamlessly to offline durable queue
    }
  }

  const queued = await enqueueOfflineItem(env, {
    idempotencyKey: envelope.messageId || crypto.randomUUID(),
    targetNodeId: envelope.targetNodeId,
    source: 'ios_client',
    eventType: envelope.type,
    payload: { envelope },
  });

  return jsonResponse({
    delivered: false,
    queued: true,
    queueId: queued.id,
    deduplicated: queued.deduplicated,
    reason: 'target_sleeping_or_unreachable',
  }, 202);
}

async function handleQueueDrain(url: URL, env: Env): Promise<Response> {
  const nodeId = url.searchParams.get('nodeId');
  const limit = Math.min(50, Math.max(1, Number(url.searchParams.get('limit') ?? '20')));
  if (!nodeId) {
    return errorResponse('MISSING_NODE_ID', 'nodeId query parameter is required', 400);
  }

  const nowIso = new Date().toISOString();
  const rows = await env.DB.prepare(
    `SELECT id, idempotency_key, target_node_id, source, event_type, payload_json, retry_count, created_at, expires_at
     FROM offline_webhook_queue
     WHERE target_node_id = ? AND status = 'pending' AND expires_at > ?
     ORDER BY created_at ASC
     LIMIT ?`,
  )
    .bind(nodeId, nowIso, limit)
    .all<Record<string, unknown>>();

  const items: OfflineWebhookItem[] = rows.results.map((r) => ({
    id: String(r.id),
    idempotencyKey: String(r.idempotency_key),
    targetNodeId: String(r.target_node_id),
    source: r.source as OfflineWebhookItem['source'],
    eventType: String(r.event_type),
    payload: JSON.parse(String(r.payload_json || '{}')) as Record<string, unknown>,
    status: 'delivered',
    retryCount: Number(r.retry_count ?? 0),
    createdAt: String(r.created_at),
    expiresAt: String(r.expires_at),
  }));

  for (const item of items) {
    await env.DB.prepare(
      `UPDATE offline_webhook_queue
       SET status = 'delivered', delivered_at = ?, retry_count = retry_count + 1
       WHERE id = ?`,
    )
      .bind(nowIso, item.id)
      .run();
  }

  return jsonResponse({ items, count: items.length });
}

async function handleQueueAck(request: Request, env: Env): Promise<Response> {
  const body = (await request.json()) as { ids?: string[] };
  const ids = body.ids ?? [];
  const nowIso = new Date().toISOString();

  for (const id of ids) {
    await env.DB.prepare(
      `UPDATE offline_webhook_queue SET status = 'acked', acked_at = ? WHERE id = ?`,
    )
      .bind(nowIso, id)
      .run();
  }

  return jsonResponse({ acked: ids.length });
}

async function handleArtifactUpload(request: Request, env: Env, url: URL): Promise<Response> {
  const r2Key = url.searchParams.get('key');
  const nodeId = url.searchParams.get('nodeId') ?? 'unknown';
  const sessionId = url.searchParams.get('sessionId');
  const kind = (url.searchParams.get('kind') ?? 'screenshot') as
    | 'screenshot'
    | 'video'
    | 'encrypted_memory_backup'
    | 'html_preview'
    | 'log';

  if (!r2Key || r2Key.includes('..')) {
    return errorResponse('INVALID_R2_KEY', 'Valid key query parameter is required', 400);
  }

  const maxBytes = Number(env.MAX_ARTIFACT_BYTES ?? '26214400');
  const softCap = Number(env.R2_FREE_TIER_SOFT_CAP_BYTES ?? '9663676416');
  const contentLength = Number(request.headers.get('Content-Length') ?? '0');
  if (contentLength > maxBytes) {
    return errorResponse('ARTIFACT_TOO_LARGE', `Exceeds max size ${maxBytes} bytes`, 413);
  }

  const usageRow = await env.DB.prepare(
    'SELECT COALESCE(SUM(size_bytes), 0) AS total_bytes FROM artifacts_index',
  ).first<{ total_bytes: number }>();

  const rawBuffer = await request.arrayBuffer();
  if (rawBuffer.byteLength > maxBytes) {
    return errorResponse('ARTIFACT_TOO_LARGE', `Exceeds max size ${maxBytes} bytes`, 413);
  }
  if ((usageRow?.total_bytes ?? 0) + rawBuffer.byteLength > softCap) {
    return errorResponse('R2_FREE_TIER_CAP', 'R2 10GB free-tier soft cap reached; prune old artifacts first', 507);
  }

  const contentType = request.headers.get('Content-Type') ?? 'application/octet-stream';
  const digestBuf = await crypto.subtle.digest('SHA-256', rawBuffer);
  const sha256Hex = bytesToHex(new Uint8Array(digestBuf));

  await env.ARTIFACTS_R2.put(r2Key, rawBuffer, {
    httpMetadata: { contentType },
    customMetadata: { nodeId, kind, sha256Hex },
  });

  const artifactId = crypto.randomUUID();
  const nowMs = Date.now();
  const createdAt = new Date(nowMs).toISOString();
  const expiresAt =
    kind === 'encrypted_memory_backup' ? null : new Date(nowMs + 14 * 24 * 3600 * 1000).toISOString();

  await env.DB.prepare(
    `INSERT INTO artifacts_index (
       artifact_id, r2_key, node_id, session_id, kind, content_type, size_bytes, sha256_hex, created_at, expires_at
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(r2_key) DO UPDATE SET
       size_bytes = excluded.size_bytes,
       sha256_hex = excluded.sha256_hex,
       expires_at = excluded.expires_at`,
  )
    .bind(artifactId, r2Key, nodeId, sessionId, kind, contentType, rawBuffer.byteLength, sha256Hex, createdAt, expiresAt)
    .run();

  return jsonResponse({ artifactId, r2Key, sizeBytes: rawBuffer.byteLength, sha256Hex }, 201);
}

async function handleArtifactSign(request: Request, env: Env, url: URL): Promise<Response> {
  if (!env.ARTIFACT_HMAC_SECRET) {
    return errorResponse('MISCONFIGURED', 'ARTIFACT_HMAC_SECRET is not set', 500);
  }
  const body = (await request.json()) as { r2Key?: string; ttlSeconds?: number };
  if (!body.r2Key) {
    return errorResponse('INVALID_KEY', 'r2Key is required', 400);
  }

  const row = await env.DB.prepare('SELECT artifact_id FROM artifacts_index WHERE r2_key = ?')
    .bind(body.r2Key)
    .first<{ artifact_id: string }>();

  const ttl = Math.min(3600, Math.max(60, body.ttlSeconds ?? Number(env.ARTIFACT_SIGNING_TTL_SEC ?? '900')));
  const expSec = Math.floor(Date.now() / 1000) + ttl;
  const sig = await signHmacHex(env.ARTIFACT_HMAC_SECRET, `${body.r2Key}:${expSec}`);

  const signedUrl = new URL(`${url.origin}/v1/artifacts/download`);
  signedUrl.searchParams.set('key', body.r2Key);
  signedUrl.searchParams.set('exp', String(expSec));
  signedUrl.searchParams.set('sig', sig);

  const response: ArtifactPresignResponse = {
    artifactId: row?.artifact_id ?? crypto.randomUUID(),
    r2Key: body.r2Key,
    signedDownloadUrl: signedUrl.toString(),
    expiresAt: new Date(expSec * 1000).toISOString(),
  };

  return jsonResponse(response);
}

async function handleArtifactDownload(request: Request, env: Env, url: URL): Promise<Response> {
  if (!env.ARTIFACT_HMAC_SECRET) {
    return errorResponse('MISCONFIGURED', 'ARTIFACT_HMAC_SECRET is not set', 500);
  }
  const r2Key = url.searchParams.get('key');
  const expStr = url.searchParams.get('exp');
  const sig = url.searchParams.get('sig');

  if (!r2Key || !expStr || !sig) {
    return errorResponse('UNAUTHORIZED', 'Missing signed URL parameters', 401);
  }

  const expSec = Number(expStr);
  if (!Number.isFinite(expSec) || expSec < Math.floor(Date.now() / 1000)) {
    return errorResponse('EXPIRED_URL', 'Signed artifact URL has expired', 403);
  }

  const valid = await verifyHmacHex(env.ARTIFACT_HMAC_SECRET, `${r2Key}:${expStr}`, sig);
  if (!valid) {
    return errorResponse('INVALID_SIGNATURE', 'Artifact URL signature verification failed', 403);
  }

  const rangeHeader = request.headers.get('Range');
  let obj: R2ObjectBody | null = null;
  if (rangeHeader && rangeHeader.startsWith('bytes=')) {
    const [startStr, endStr] = rangeHeader.slice(6).split('-');
    const offset = startStr ? Number(startStr) : 0;
    const end = endStr ? Number(endStr) : undefined;
    const length = end !== undefined && Number.isFinite(end) ? end - offset + 1 : undefined;
    obj = await env.ARTIFACTS_R2.get(r2Key, { range: { offset, length } });
  } else {
    obj = await env.ARTIFACTS_R2.get(r2Key);
  }

  if (!obj || !obj.body) {
    return errorResponse('NOT_FOUND', 'Artifact object not found in R2', 404);
  }

  return new Response(obj.body, {
    status: rangeHeader ? 206 : 200,
    headers: {
      'Content-Type': obj.httpMetadata?.contentType ?? 'application/octet-stream',
      ETag: obj.etag,
      'Accept-Ranges': 'bytes',
      'Cache-Control': 'private, max-age=300',
    },
  });
}

async function handleCreateDecision(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
): Promise<Response> {
  const decision = (await request.json()) as NeedsYouDecision;
  const nowIso = decision.createdAt || new Date().toISOString();

  await env.DB.prepare(
    `INSERT INTO needs_you_decisions (
       id, outcome_id, session_id, source_node_id, severity, category, title, summary,
       recommended_option_id, options_json, evidence_json, status, created_at
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?)`,
  )
    .bind(
      decision.id || crypto.randomUUID(),
      decision.outcomeId ?? null,
      decision.sessionId,
      decision.sourceNodeId,
      decision.severity,
      decision.category,
      decision.title,
      decision.summary,
      decision.recommendedOptionId,
      JSON.stringify(decision.options ?? []),
      JSON.stringify(decision.evidence ?? []),
      nowIso,
    )
    .run();

  ctx.waitUntil(
    sendApnsAlert(env, {
      title: `Needs You · ${decision.severity.toUpperCase()}`,
      subtitle: decision.title,
      body: decision.summary.slice(0, 140),
      category: 'NEEDS_YOU_DECISION',
      decisionId: decision.id,
      threadId: decision.sessionId,
    }),
  );

  return jsonResponse({ ok: true, id: decision.id }, 201);
}

async function handleResolveDecision(
  request: Request,
  env: Env,
  decisionId: string,
  identity: AccessIdentityContext,
): Promise<Response> {
  const body = (await request.json()) as { chosenOptionId: string; userNote?: string };
  if (!body.chosenOptionId) {
    return errorResponse('INVALID_RESOLUTION', 'chosenOptionId is required', 400);
  }

  const row = await env.DB.prepare(
    'SELECT source_node_id, session_id FROM needs_you_decisions WHERE id = ?',
  )
    .bind(decisionId)
    .first<{ source_node_id: string; session_id: string }>();

  if (!row) {
    return errorResponse('NOT_FOUND', `Decision ${decisionId} not found`, 404);
  }

  const nowIso = new Date().toISOString();
  const resolvedBy = identity.email ?? identity.subject ?? 'ios-user';

  await env.DB.prepare(
    `UPDATE needs_you_decisions
     SET status = 'resolved', chosen_option_id = ?, user_note = ?, resolved_by = ?, resolved_at = ?
     WHERE id = ?`,
  )
    .bind(body.chosenOptionId, body.userNote ?? null, resolvedBy, nowIso, decisionId)
    .run();

  await enqueueOfflineItem(env, {
    idempotencyKey: `decision:${decisionId}:${body.chosenOptionId}`,
    targetNodeId: row.source_node_id,
    source: 'ios_client',
    eventType: 'decision.resolved',
    payload: {
      decisionId,
      sessionId: row.session_id,
      chosenOptionId: body.chosenOptionId,
      userNote: body.userNote,
      resolvedBy,
      resolvedAt: nowIso,
    },
  });

  await writeAuditLog(env, identity, 'decision.resolved', decisionId, {
    chosenOptionId: body.chosenOptionId,
    targetNodeId: row.source_node_id,
  });

  return jsonResponse({ ok: true, decisionId, status: 'resolved', resolvedAt: nowIso });
}

async function handleWebSocketRelay(request: Request, env: Env, url: URL): Promise<Response> {
  if (request.headers.get('Upgrade')?.toLowerCase() !== 'websocket') {
    return errorResponse('UPGRADE_REQUIRED', 'Expected WebSocket upgrade', 426);
  }

  const pair = new WebSocketPair();
  const client = pair[0];
  const server = pair[1];
  const nodeId = url.searchParams.get('nodeId') ?? 'unknown';

  server.accept();
  server.send(
    JSON.stringify({
      version: '1.0',
      type: 'relay.pong',
      nodeId,
      timestamp: new Date().toISOString(),
      message: 'Connected to PipiBot Cloudflare Edge Relay',
    }),
  );

  server.addEventListener('message', (event: MessageEvent) => {
    void (async () => {
      try {
        const msg = JSON.parse(String(event.data)) as CloudflareRelayEnvelope<Record<string, unknown>>;
        if (msg.type === 'relay.ping') {
          server.send(JSON.stringify({ version: '1.0', type: 'relay.pong', timestamp: new Date().toISOString() }));
          return;
        }
        if (msg.targetNodeId) {
          await enqueueOfflineItem(env, {
            idempotencyKey: msg.messageId || crypto.randomUUID(),
            targetNodeId: msg.targetNodeId,
            source: 'ios_client',
            eventType: msg.type,
            payload: { envelope: msg },
          });
          server.send(JSON.stringify({ ack: msg.messageId, queuedForNode: msg.targetNodeId }));
        }
      } catch {
        server.send(JSON.stringify({ error: 'Malformed relay envelope' }));
      }
    })();
  });

  return new Response(null, { status: 101, webSocket: client } as ResponseInit & { webSocket: WebSocket });
}

// ---------------------------------------------------------------------------
// 6. Main Worker Fetch & Cron Entrypoint
// ---------------------------------------------------------------------------

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    // Public unauthenticated health probe (zero sensitive data)
    if (request.method === 'GET' && path === '/health') {
      return jsonResponse({
        service: 'pipibot-edge-relay',
        status: 'ok',
        freeTierMode: true,
        timestamp: new Date().toISOString(),
      });
    }

    // Signed R2 artifact download validates HMAC signature directly without CF Access cookie
    if (request.method === 'GET' && path === '/v1/artifacts/download') {
      return handleArtifactDownload(request, env, url);
    }

    // All remaining endpoints require Cloudflare Access Zero Trust or Node HMAC
    const identity = await authenticateRequest(request, env, url);
    if (!identity) {
      return errorResponse('UNAUTHORIZED', 'Valid Cloudflare Access JWT, Service Token, or Node HMAC required.', 401);
    }

    if (request.method === 'POST' && path === '/v1/fleet/heartbeat') {
      return handleFleetHeartbeat(request, env, ctx);
    }
    if (request.method === 'GET' && path === '/v1/fleet/nodes') {
      return handleListFleetNodes(env);
    }

    if (request.method === 'GET' && path === '/v1/relay/ws') {
      return handleWebSocketRelay(request, env, url);
    }
    if (request.method === 'POST' && path === '/v1/relay/send') {
      return handleRelaySend(request, env);
    }

    if (request.method === 'POST' && path === '/v1/queue/enqueue') {
      const item = (await request.json()) as {
        idempotencyKey: string;
        targetNodeId: string;
        source: OfflineWebhookItem['source'];
        eventType: string;
        payload: Record<string, unknown>;
        ttlSeconds?: number;
      };
      const result = await enqueueOfflineItem(env, item);
      return jsonResponse(result, 202);
    }
    if (request.method === 'GET' && path === '/v1/queue/drain') {
      return handleQueueDrain(url, env);
    }
    if (request.method === 'POST' && path === '/v1/queue/ack') {
      return handleQueueAck(request, env);
    }

    if (request.method === 'POST' && path === '/v1/artifacts/upload') {
      return handleArtifactUpload(request, env, url);
    }
    if (request.method === 'POST' && path === '/v1/artifacts/sign') {
      return handleArtifactSign(request, env, url);
    }

    if (request.method === 'POST' && path === '/v1/decisions') {
      return handleCreateDecision(request, env, ctx);
    }
    if (request.method === 'GET' && path === '/v1/decisions') {
      const statusFilter = url.searchParams.get('status') ?? 'pending';
      const rows = await env.DB.prepare(
        'SELECT * FROM needs_you_decisions WHERE status = ? ORDER BY created_at DESC LIMIT 30',
      )
        .bind(statusFilter)
        .all();
      return jsonResponse({ decisions: rows.results });
    }
    const resolveMatch = path.match(/^\/v1\/decisions\/([^/]+)\/resolve$/);
    if (request.method === 'POST' && resolveMatch?.[1]) {
      return handleResolveDecision(request, env, decodeURIComponent(resolveMatch[1]), identity);
    }

    if (request.method === 'POST' && path === '/v1/evolution/digests') {
      const body = (await request.json()) as { nodeId: string; summary: EvolutionSummary };
      const nowIso = new Date().toISOString();
      await env.DB.prepare(
        `INSERT INTO evolution_digests (
           digest_id, node_id, cycle, understanding_score, pending_review_count, summary_json, created_at, updated_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(digest_id) DO UPDATE SET
           pending_review_count = excluded.pending_review_count,
           summary_json = excluded.summary_json,
           updated_at = excluded.updated_at`,
      )
        .bind(
          body.summary.digestId,
          body.nodeId,
          body.summary.cycle,
          body.summary.understandingScore.overall,
          body.summary.requiresUserReviewCount,
          JSON.stringify(body.summary),
          body.summary.generatedAt || nowIso,
          nowIso,
        )
        .run();

      if (body.summary.requiresUserReviewCount > 0) {
        ctx.waitUntil(
          sendApnsAlert(env, {
            title: `PipiBot 懂你指数 ${body.summary.understandingScore.overall}`,
            body: `昨晚总结出 ${body.summary.requiresUserReviewCount} 项认知演化待审阅`,
            category: 'EVOLUTION_DIGEST',
            digestId: body.summary.digestId,
          }),
        );
      }
      return jsonResponse({ ok: true, digestId: body.summary.digestId }, 201);
    }

    if (request.method === 'GET' && path === '/v1/evolution/digests') {
      const rows = await env.DB.prepare(
        'SELECT digest_id, node_id, cycle, understanding_score, pending_review_count, summary_json, created_at FROM evolution_digests ORDER BY created_at DESC LIMIT 10',
      ).all();
      return jsonResponse({ digests: rows.results });
    }

    if (request.method === 'POST' && path === '/v1/apns/register') {
      const body = (await request.json()) as {
        nodeId: string;
        apnsToken: string;
        environment?: 'production' | 'sandbox';
        liveActivityToken?: string;
      };
      if (!body.nodeId || !body.apnsToken) {
        return errorResponse('INVALID_PAYLOAD', 'nodeId and apnsToken are required', 400);
      }
      await env.DB.prepare(
        `INSERT INTO apns_device_tokens (token_id, node_id, apns_token, environment, live_activity_token, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT(apns_token) DO UPDATE SET
           node_id = excluded.node_id,
           environment = excluded.environment,
           live_activity_token = COALESCE(excluded.live_activity_token, apns_device_tokens.live_activity_token),
           updated_at = excluded.updated_at`,
      )
        .bind(
          crypto.randomUUID(),
          body.nodeId,
          body.apnsToken,
          body.environment ?? 'production',
          body.liveActivityToken ?? null,
          new Date().toISOString(),
        )
        .run();
      return jsonResponse({ ok: true });
    }

    return errorResponse('NOT_FOUND', `No route matches ${request.method} ${path}`, 404);
  },

  async scheduled(_controller: ScheduledController, env: Env, _ctx: ExecutionContext): Promise<void> {
    const nowIso = new Date().toISOString();
    const staleThresholdIso = new Date(Date.now() - 10 * 60 * 1000).toISOString();

    // 1. Mark stale pending offline queue items as expired
    await env.DB.prepare(
      `UPDATE offline_webhook_queue
       SET status = 'expired'
       WHERE status IN ('pending', 'delivered') AND expires_at <= ?`,
    )
      .bind(nowIso)
      .run();

    // 2. Mark nodes unseen for >10m as offline in D1
    await env.DB.prepare(
      `UPDATE fleet_nodes
       SET vitality = 'offline', updated_at = ?
       WHERE vitality != 'offline' AND last_seen_at < ?`,
    )
      .bind(nowIso, staleThresholdIso)
      .run();

    // 3. Clean expired ephemeral R2 artifacts to protect the 10GB free-tier ceiling
    const expiredArtifacts = await env.DB.prepare(
      'SELECT artifact_id, r2_key FROM artifacts_index WHERE expires_at IS NOT NULL AND expires_at <= ? LIMIT 100',
    )
      .bind(nowIso)
      .all<{ artifact_id: string; r2_key: string }>();

    if (expiredArtifacts.results.length > 0) {
      await env.ARTIFACTS_R2.delete(expiredArtifacts.results.map((a) => a.r2_key));
      for (const item of expiredArtifacts.results) {
        await env.DB.prepare('DELETE FROM artifacts_index WHERE artifact_id = ?').bind(item.artifact_id).run();
      }
    }
  },
};
