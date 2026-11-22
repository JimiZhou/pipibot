/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/daemon - credential-broker.ts
 * Loopback-only HTTP Credential Broker & Foreign Secret Environment Scrubber.
 * Child processes receive ephemeral per-process tokens (`pipi_brk_...`) revoked on exit;
 * real provider API keys never enter child environments.
 */

import { randomBytes } from 'node:crypto';
import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';

export interface BrokerUpstreamBinding {
  provider: 'openai' | 'anthropic' | 'gemini';
  upstreamBaseUrl: string;
  realSecret: string;
  authHeaderName?: string;
  authHeaderPrefix?: string;
}

export interface BrokerLease {
  token: string;
  provider: BrokerUpstreamBinding['provider'];
  proxyBaseUrl: string;
  expiresAt: number;
}

export const SENSITIVE_FOREIGN_ENV_KEYS = new Set([
  'OPENAI_API_KEY',
  'ANTHROPIC_API_KEY',
  'ANTHROPIC_AUTH_TOKEN',
  'GEMINI_API_KEY',
  'GOOGLE_API_KEY',
  'XAI_API_KEY',
  'DEEPSEEK_API_KEY',
  'OPENROUTER_API_KEY',
  'PIPIBOT_HUB_TOKEN',
  'PIPIBOT_REMOTE_TOKEN',
  'PIPIBOT_MASTER_SECRET',
]);

interface StoredLease {
  token: string;
  binding: BrokerUpstreamBinding;
  expiresAt: number;
}

export function buildScrubbedChildEnv(
  baseEnv: NodeJS.ProcessEnv,
  leases: BrokerLease[] = [],
  extraAllowed: Record<string, string> = {},
): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(baseEnv)) {
    if (v === undefined) continue;
    if (SENSITIVE_FOREIGN_ENV_KEYS.has(k) || k.startsWith('PIPIBOT_')) continue;
    out[k] = v;
  }
  for (const [k, v] of Object.entries(extraAllowed)) {
    if (SENSITIVE_FOREIGN_ENV_KEYS.has(k)) continue;
    out[k] = v;
  }
  for (const lease of leases) {
    if (lease.provider === 'openai') {
      out.OPENAI_API_KEY = lease.token;
      out.OPENAI_BASE_URL = lease.proxyBaseUrl;
    } else if (lease.provider === 'anthropic') {
      out.ANTHROPIC_API_KEY = lease.token;
      out.ANTHROPIC_BASE_URL = lease.proxyBaseUrl;
    } else if (lease.provider === 'gemini') {
      out.GEMINI_API_KEY = lease.token;
      out.GOOGLE_GEMINI_BASE_URL = lease.proxyBaseUrl;
    }
  }
  return out;
}

export class PipiCredentialBrokerServer {
  private server: Server | null = null;
  private port = 0;
  private readonly leases = new Map<string, StoredLease>();

  async start(): Promise<number> {
    if (this.server && this.port > 0) return this.port;
    const srv = createServer((req, res) => {
      void this.handleRequest(req, res);
    });
    await new Promise<void>((resolve, reject) => {
      srv.once('error', reject);
      srv.listen(0, '127.0.0.1', () => {
        srv.off('error', reject);
        resolve();
      });
    });
    this.server = srv;
    this.port = (srv.address() as AddressInfo).port;
    return this.port;
  }

  async stop(): Promise<void> {
    this.leases.clear();
    if (this.server) {
      await new Promise<void>((resolve) => this.server!.close(() => resolve()));
      this.server = null;
      this.port = 0;
    }
  }

  async issueLease(binding: BrokerUpstreamBinding, ttlSeconds = 3600): Promise<BrokerLease> {
    const activePort = await this.start();
    const token = `pipi_brk_${randomBytes(16).toString('hex')}`;
    const expiresAt = Date.now() + Math.max(60, Math.min(86_400, ttlSeconds)) * 1000;
    this.leases.set(token, { token, binding, expiresAt });
    return {
      token,
      provider: binding.provider,
      proxyBaseUrl: `http://127.0.0.1:${activePort}/b/${token}/${binding.provider}`,
      expiresAt,
    };
  }

  revokeLease(token: string): void {
    this.leases.delete(token);
  }

  activeLeaseCount(): number {
    const now = Date.now();
    for (const [k, v] of this.leases.entries()) {
      if (v.expiresAt <= now) this.leases.delete(k);
    }
    return this.leases.size;
  }

  private async handleRequest(req: IncomingMessage, res: ServerResponse): Promise<void> {
    const rawPath = req.url ?? '/';
    const match = rawPath.match(/^\/b\/([^/]+)\/([^/]+)(\/.*)?$/);
    if (!match) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'invalid_broker_path' }));
      return;
    }
    const [, token, provider, tail = '/'] = match;
    const stored = this.leases.get(token!);
    if (!stored || stored.expiresAt <= Date.now() || stored.binding.provider !== provider) {
      res.writeHead(401, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'invalid_or_revoked_broker_token' }));
      return;
    }

    const chunks: Buffer[] = [];
    for await (const chunk of req) {
      chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
    }
    const body = Buffer.concat(chunks);
    const upstreamUrl = `${stored.binding.upstreamBaseUrl.replace(/\/+$/, '')}${tail}`;
    const headers: Record<string, string> = {};
    for (const [k, v] of Object.entries(req.headers)) {
      if (typeof v !== 'string') continue;
      const lower = k.toLowerCase();
      if (['host', 'authorization', 'x-api-key', 'x-goog-api-key', 'content-length'].includes(lower)) continue;
      headers[k] = v;
    }
    const authHeader = stored.binding.authHeaderName ?? 'Authorization';
    const authPrefix = stored.binding.authHeaderPrefix ?? 'Bearer ';
    headers[authHeader] = `${authPrefix}${stored.binding.realSecret}`;

    try {
      const upstreamRes = await fetch(upstreamUrl, {
        method: req.method ?? 'POST',
        headers,
        body: ['GET', 'HEAD'].includes((req.method ?? 'POST').toUpperCase()) ? undefined : body,
      });
      const respBuf = Buffer.from(await upstreamRes.arrayBuffer());
      res.writeHead(upstreamRes.status, {
        'Content-Type': upstreamRes.headers.get('content-type') ?? 'application/json',
      });
      res.end(respBuf);
    } catch {
      res.writeHead(502, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'upstream_unreachable' }));
    }
  }
}
