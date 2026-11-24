/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/relay - server.ts
 * Zero-Knowledge E2EE Relay Server + Encrypted WebRTC Signaling + Optional UDP STUN Reflector
 * + Universal Mobile 5-Tab PWA Static Host (`https://pipibot.jimizhou.com`).
 *
 * Security & Multi-Tenant Protections:
 * - Zero plaintext access: forwards opaque AES-256-GCM envelopes only (`hostId` + `clientId` + `ct`).
 * - Honors `CF-Connecting-IP` / `X-Forwarded-For` behind Cloudflare Tunnel (`127.0.0.1:9191`).
 * - Per-IP concurrent connection cap, per-host client cap, sliding-window message rate limit,
 *   frame size cap (512KB), heartbeat idle reaper, and optional invite keys (`PIPIBOT_RELAY_INVITE_KEYS`).
 */

import { createHash, randomUUID } from 'node:crypto';
import dgram, { type Socket as UdpSocket } from 'node:dgram';
import { existsSync, readFileSync } from 'node:fs';
import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { PipiAuthService, type AuthServiceOptions, type DevicePlatformKind, type OAuthProviderKind } from './auth.ts';
import { PIPIBOT_EDGE_CLI_VERSION, renderAdaptiveInstallScript, renderPosixEdgeAgent, renderPythonLiteAgent } from './edge-bundle.ts';
import { renderBrandDownloadHTML, renderBrandFeaturesHTML, renderBrandLandingHTML } from './landing-page.ts';
import { renderLoginAndDevicesHTML } from './login-page.ts';
import { renderUniversalIconSVG, renderUniversalManifest, renderUniversalPWAHTML } from './pwa-bundle.ts';
import { acceptWebSocketUpgrade, extractClientIp, type MinimalWebSocket } from './ws-minimal.ts';

const PUBLIC_ASSET_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', 'public');
const STATIC_ASSET_MIME: Record<string, string> = {
  png: 'image/png',
  svg: 'image/svg+xml; charset=utf-8',
  webp: 'image/webp',
  jpg: 'image/jpeg',
};

export interface RelayServerOptions {
  host?: string;
  port?: number;
  stunUdpPort?: number; // 0 or undefined = disabled; e.g. 3478 to enable built-in RFC 5389 UDP STUN binding reflector
  maxConnectionsPerIp?: number;
  maxClientsPerHost?: number;
  maxMessagesPerMinutePerConn?: number;
  maxFrameBytes?: number;
  inviteKeys?: string[];
  idleTimeoutMs?: number;
  auth?: AuthServiceOptions;
}

interface HostRoom {
  hostId: string;
  hostSocket: MinimalWebSocket | null;
  clients: Map<string, MinimalWebSocket>;
  lastActiveAt: number;
}

interface ConnMeta {
  ws: MinimalWebSocket;
  ip: string;
  role?: 'host' | 'client';
  hostId?: string;
  clientId?: string;
  windowStartMs: number;
  windowMsgCount: number;
  lastSeenAt: number;
}

interface EdgeTask {
  id: string;
  command: string;
  timeoutMs: number;
  cwd?: string;
  resolve: (res: { ok: boolean; exitCode: number; stdout: string; stderr: string }) => void;
  timer: ReturnType<typeof setTimeout>;
}

interface EdgeNodeState {
  hostId: string;
  userId: string;
  hostName: string;
  arch: string;
  memMB: number;
  uptimeSeconds: number;
  workspacePath: string;
  mode: 'lite' | 'edge';
  lastSeenAt: number;
  queue: EdgeTask[];
  inflight: Map<string, EdgeTask>;
  waiter?: (task: EdgeTask | null) => void;
}

export class PipiE2EERelayServer {
  private readonly options: Required<Omit<RelayServerOptions, 'auth'>>;
  private readonly auth: PipiAuthService;
  private readonly rooms = new Map<string, HostRoom>();
  private readonly edgeNodes = new Map<string, EdgeNodeState>();
  private readonly conns = new Map<string, ConnMeta>();
  private readonly ipConnCount = new Map<string, number>();
  private readonly inviteKeySet: Set<string>;
  private httpServer: Server | null = null;
  private stunSocket: UdpSocket | null = null;
  private reaperTimer: ReturnType<typeof setInterval> | null = null;
  private totalEnvelopesRelayed = 0;
  private totalRateLimited = 0;

  constructor(options?: RelayServerOptions) {
    this.options = {
      host: options?.host ?? '127.0.0.1',
      port: options?.port ?? 9191,
      stunUdpPort: options?.stunUdpPort ?? 0,
      maxConnectionsPerIp: options?.maxConnectionsPerIp ?? 24,
      maxClientsPerHost: options?.maxClientsPerHost ?? 12,
      maxMessagesPerMinutePerConn: options?.maxMessagesPerMinutePerConn ?? 3000,
      maxFrameBytes: options?.maxFrameBytes ?? 512 * 1024,
      inviteKeys: options?.inviteKeys ?? [],
      idleTimeoutMs: options?.idleTimeoutMs ?? 120_000,
    };
    this.auth = new PipiAuthService(options?.auth);
    this.inviteKeySet = new Set(this.options.inviteKeys.map((k) => k.trim()).filter(Boolean));
  }

  getAuthService(): PipiAuthService {
    return this.auth;
  }

  private getOnlineHostIds(): Set<string> {
    const online = new Set<string>();
    const now = Date.now();
    for (const room of this.rooms.values()) {
      if (room.hostSocket && room.hostSocket.readyState === 'open') {
        online.add(room.hostId);
      }
    }
    for (const edge of this.edgeNodes.values()) {
      if (now - edge.lastSeenAt < 45_000) {
        online.add(edge.hostId);
      }
    }
    return online;
  }

  getStats(): {
    onlineHosts: number;
    onlineClients: number;
    activeConnections: number;
    totalEnvelopesRelayed: number;
    totalRateLimited: number;
    inviteOnly: boolean;
  } {
    let onlineHosts = 0;
    let onlineClients = 0;
    for (const room of this.rooms.values()) {
      if (room.hostSocket && room.hostSocket.readyState === 'open') onlineHosts += 1;
      onlineClients += room.clients.size;
    }
    return {
      onlineHosts,
      onlineClients,
      activeConnections: this.conns.size,
      totalEnvelopesRelayed: this.totalEnvelopesRelayed,
      totalRateLimited: this.totalRateLimited,
      inviteOnly: this.inviteKeySet.size > 0,
    };
  }

  async start(): Promise<{ host: string; port: number; stunPort: number }> {
    const server = createServer((req, res) => {
      void this.handleHttp(req, res);
    });

    server.on('upgrade', (req, socket, head) => {
      const url = new URL(req.url ?? '/', 'http://localhost');
      if (url.pathname !== '/ws') {
        socket.write('HTTP/1.1 404 Not Found\r\n\r\n');
        socket.destroy();
        return;
      }

      const ip = extractClientIp(req);
      const currentForIp = this.ipConnCount.get(ip) ?? 0;
      if (currentForIp >= this.options.maxConnectionsPerIp) {
        this.totalRateLimited += 1;
        socket.write('HTTP/1.1 429 Too Many Requests\r\n\r\n');
        socket.destroy();
        return;
      }

      const ws = acceptWebSocketUpgrade(req, socket, head, this.options.maxFrameBytes);
      if (!ws) return;

      this.ipConnCount.set(ip, currentForIp + 1);
      const meta: ConnMeta = {
        ws,
        ip,
        windowStartMs: Date.now(),
        windowMsgCount: 0,
        lastSeenAt: Date.now(),
      };
      this.conns.set(ws.id, meta);

      ws.onMessage((text) => this.handleWsMessage(meta, text));
      ws.onClose(() => this.handleWsClose(meta));
    });

    await new Promise<void>((resolve, reject) => {
      server.once('error', reject);
      server.listen(this.options.port, this.options.host, () => {
        server.off('error', reject);
        resolve();
      });
    });

    this.httpServer = server;
    const addr = server.address() as AddressInfo;

    let boundStunPort = 0;
    if (this.options.stunUdpPort > 0) {
      boundStunPort = await this.startStunReflector(this.options.stunUdpPort);
    }

    this.reaperTimer = setInterval(() => {
      this.reapIdleConnections();
    }, 30_000);
    this.reaperTimer.unref?.();

    return { host: this.options.host, port: addr.port, stunPort: boundStunPort };
  }

  async stop(): Promise<void> {
    if (this.reaperTimer) {
      clearInterval(this.reaperTimer);
      this.reaperTimer = null;
    }
    for (const meta of this.conns.values()) {
      meta.ws.close(1001, 'Relay shutting down');
    }
    for (const edge of this.edgeNodes.values()) {
      if (edge.waiter) edge.waiter(null);
      for (const t of edge.queue) clearTimeout(t.timer);
      for (const t of edge.inflight.values()) clearTimeout(t.timer);
    }
    this.edgeNodes.clear();
    this.conns.clear();
    this.rooms.clear();
    this.ipConnCount.clear();

    if (this.stunSocket) {
      await new Promise<void>((resolve) => this.stunSocket!.close(() => resolve()));
      this.stunSocket = null;
    }
    if (this.httpServer) {
      await new Promise<void>((resolve) => this.httpServer!.close(() => resolve()));
      this.httpServer = null;
    }
  }

  private extractSessionToken(req: IncomingMessage): string | null {
    const authHeader = String(req.headers.authorization ?? '').trim();
    if (authHeader.toLowerCase().startsWith('bearer ')) {
      return authHeader.slice(7).trim() || null;
    }
    const cookieHeader = String(req.headers.cookie ?? '');
    for (const part of cookieHeader.split(';')) {
      const [k, ...rest] = part.trim().split('=');
      if (k === 'pipibot_session') {
        return decodeURIComponent(rest.join('='));
      }
    }
    return null;
  }

  private async readBodyText(req: IncomingMessage, maxBytes = 64 * 1024): Promise<string> {
    return await new Promise((resolve, reject) => {
      let total = 0;
      const chunks: Buffer[] = [];
      req.on('data', (chunk: Buffer) => {
        total += chunk.length;
        if (total > maxBytes) {
          reject(new Error('body_too_large'));
          return;
        }
        chunks.push(chunk);
      });
      req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
      req.on('error', reject);
    });
  }

  private async readJsonBody(req: IncomingMessage): Promise<Record<string, unknown>> {
    try {
      const text = await this.readBodyText(req);
      if (!text.trim()) return {};
      return JSON.parse(text) as Record<string, unknown>;
    } catch {
      return {};
    }
  }

  private sendJson(res: ServerResponse, status: number, body: unknown, extraHeaders?: Record<string, string>): void {
    res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', ...(extraHeaders ?? {}) });
    res.end(JSON.stringify(body));
  }

  private resolveRequestOrigin(req: IncomingMessage): string {
    const proto = String(req.headers['x-forwarded-proto'] ?? '').split(',')[0]?.trim() || 'http';
    const host = String(req.headers['x-forwarded-host'] ?? req.headers.host ?? '127.0.0.1').split(',')[0]?.trim();
    return `${proto}://${host}`;
  }

  private async handleHttp(req: IncomingMessage, res: ServerResponse): Promise<void> {
    const url = new URL(req.url ?? '/', 'http://localhost');
    const path = url.pathname;
    const method = (req.method ?? 'GET').toUpperCase();

    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');

    if (path === '/healthz') {
      this.sendJson(res, 200, { ok: true, service: 'pipibot-relay', zeroKnowledgeE2EE: true, ...this.getStats() });
      return;
    }

    if (path === '/api/relay/stats') {
      this.sendJson(res, 200, this.getStats());
      return;
    }

    // --- Unified Account & Device Registry API ---
    if (path === '/api/auth/providers' && method === 'GET') {
      this.sendJson(res, 200, this.auth.getEnabledProviders());
      return;
    }

    if (path === '/api/auth/email/send' && method === 'POST') {
      const body = await this.readJsonBody(req);
      const result = await this.auth.sendEmailOtp(String(body.email ?? ''));
      this.sendJson(res, result.ok ? 200 : 400, result);
      return;
    }

    if (path === '/api/auth/email/verify' && method === 'POST') {
      const body = await this.readJsonBody(req);
      const result = this.auth.verifyEmailOtp(
        String(body.email ?? ''),
        String(body.code ?? ''),
        String(body.clientLabel ?? 'Web'),
      );
      if (result.ok && result.accessToken) {
        const cookie = `pipibot_session=${encodeURIComponent(result.accessToken)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000`;
        this.sendJson(res, 200, result, { 'Set-Cookie': cookie });
      } else {
        this.sendJson(res, 400, result);
      }
      return;
    }

    const oauthStartMatch = /^\/api\/auth\/oauth\/(apple|github|google)\/start$/.exec(path);
    if (oauthStartMatch && method === 'GET') {
      const provider = oauthStartMatch[1] as OAuthProviderKind;
      const result = this.auth.buildOAuthStartUrl(provider, {
        userCode: url.searchParams.get('code') ?? undefined,
        redirectTo: url.searchParams.get('redirect') ?? '/login',
        originOverride: this.resolveRequestOrigin(req),
      });
      if (result.ok && result.url) {
        res.writeHead(302, { Location: result.url });
        res.end();
      } else {
        this.sendJson(res, 400, result);
      }
      return;
    }

    const oauthCbMatch = /^\/api\/auth\/oauth\/(apple|github|google)\/callback$/.exec(path);
    if (oauthCbMatch && (method === 'GET' || method === 'POST')) {
      const provider = oauthCbMatch[1] as OAuthProviderKind;
      let code = url.searchParams.get('code') ?? undefined;
      let state = url.searchParams.get('state') ?? undefined;
      if (method === 'POST') {
        const raw = await this.readBodyText(req);
        const form = new URLSearchParams(raw);
        code = code ?? form.get('code') ?? undefined;
        state = state ?? form.get('state') ?? undefined;
      }
      const result = await this.auth.handleOAuthCallback(provider, {
        code,
        state,
        originOverride: this.resolveRequestOrigin(req),
      });
      if (result.ok && result.accessToken) {
        const cookie = `pipibot_session=${encodeURIComponent(result.accessToken)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000`;
        res.writeHead(302, { Location: result.redirectTo || '/login', 'Set-Cookie': cookie });
        res.end();
      } else {
        res.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8' });
        res.end(result.error || 'OAuth callback failed');
      }
      return;
    }

    if (path === '/api/auth/device/start' && method === 'POST') {
      const body = await this.readJsonBody(req);
      const flow = this.auth.startDeviceFlow(
        String(body.clientLabel ?? 'PiPiBot CLI'),
        this.resolveRequestOrigin(req),
      );
      this.sendJson(res, 200, flow);
      return;
    }

    if (path === '/api/auth/device/approve' && method === 'POST') {
      const user = this.auth.authenticateToken(this.extractSessionToken(req));
      if (!user) {
        this.sendJson(res, 401, { ok: false, error: '请先登录账号' });
        return;
      }
      const body = await this.readJsonBody(req);
      const result = this.auth.approveDeviceFlow(String(body.userCode ?? ''), user.id);
      this.sendJson(res, result.ok ? 200 : 400, result);
      return;
    }

    if (path === '/api/auth/device/poll' && method === 'POST') {
      const body = await this.readJsonBody(req);
      const result = this.auth.pollDeviceFlow(String(body.deviceCode ?? ''));
      this.sendJson(res, 200, result);
      return;
    }

    if (path === '/api/auth/me' && method === 'GET') {
      const token = this.extractSessionToken(req);
      const user = this.auth.authenticateToken(token);
      if (!user) {
        this.sendJson(res, 401, { ok: false, error: 'unauthenticated' });
        return;
      }
      const devices = this.auth.listDevices(user.id, this.getOnlineHostIds());
      this.sendJson(res, 200, { ok: true, user, devices, accessToken: token });
      return;
    }

    if (path === '/api/auth/logout' && method === 'POST') {
      this.auth.revokeToken(this.extractSessionToken(req));
      this.sendJson(res, 200, { ok: true }, { 'Set-Cookie': 'pipibot_session=; Path=/; HttpOnly; Max-Age=0' });
      return;
    }

    if (path === '/api/devices/register' && method === 'POST') {
      const user = this.auth.authenticateToken(this.extractSessionToken(req));
      if (!user) {
        this.sendJson(res, 401, { ok: false, error: 'unauthenticated' });
        return;
      }
      const body = await this.readJsonBody(req);
      const hostId = String(body.hostId ?? '').trim();
      if (!hostId) {
        this.sendJson(res, 400, { ok: false, error: 'missing_host_id' });
        return;
      }
      const rawPlatform = String(body.platform ?? 'macos').toLowerCase();
      const platform: DevicePlatformKind =
        rawPlatform === 'linux' || rawPlatform === 'windows' || rawPlatform === 'ios' || rawPlatform === 'web'
          ? rawPlatform
          : 'macos';
      const device = this.auth.registerDevice(user.id, {
        name: String(body.name ?? 'My Machine'),
        platform,
        hostId,
        hostPubKey: String(body.hostPubKey ?? ''),
        capabilities: Array.isArray(body.capabilities) ? body.capabilities.map(String) : [],
        workspacePath: typeof body.workspacePath === 'string' ? body.workspacePath : undefined,
      });
      this.sendJson(res, 200, { ok: true, device });
      return;
    }

    if (path === '/api/devices' && method === 'GET') {
      const user = this.auth.authenticateToken(this.extractSessionToken(req));
      if (!user) {
        this.sendJson(res, 401, { ok: false, error: 'unauthenticated' });
        return;
      }
      this.sendJson(res, 200, { ok: true, devices: this.auth.listDevices(user.id, this.getOnlineHostIds()) });
      return;
    }

    const delDevMatch = /^\/api\/devices\/([a-zA-Z0-9_-]+)$/.exec(path);
    if (delDevMatch && method === 'DELETE') {
      const user = this.auth.authenticateToken(this.extractSessionToken(req));
      if (!user) {
        this.sendJson(res, 401, { ok: false, error: 'unauthenticated' });
        return;
      }
      const removed = this.auth.removeDevice(user.id, delDevMatch[1]!);
      this.sendJson(res, removed ? 200 : 404, { ok: removed });
      return;
    }

    // --- Embedded / Low-Resource Edge Device Bridge (Python3 Lite & POSIX Shell Edge) ---
    if (path === '/api/edge/heartbeat' && method === 'POST') {
      const user = this.auth.authenticateToken(this.extractSessionToken(req));
      if (!user) {
        this.sendJson(res, 401, { ok: false, error: 'unauthenticated' });
        return;
      }
      const body = await this.readJsonBody(req);
      const hostId = String(body.hostId ?? '').trim();
      if (!hostId) {
        this.sendJson(res, 400, { ok: false, error: 'missing_host_id' });
        return;
      }
      let edge = this.edgeNodes.get(hostId);
      if (!edge) {
        edge = {
          hostId,
          userId: user.id,
          hostName: String(body.hostName ?? hostId),
          arch: String(body.arch ?? 'unknown'),
          memMB: Number(body.memMB) || 0,
          uptimeSeconds: Number(body.uptimeSeconds) || 0,
          workspacePath: String(body.workspacePath ?? '/'),
          mode: body.mode === 'edge' ? 'edge' : 'lite',
          lastSeenAt: Date.now(),
          queue: [],
          inflight: new Map(),
        };
        this.edgeNodes.set(hostId, edge);
      } else if (edge.userId !== user.id) {
        this.sendJson(res, 403, { ok: false, error: 'forbidden' });
        return;
      }
      edge.lastSeenAt = Date.now();
      if (typeof body.hostName === 'string' && body.hostName) edge.hostName = body.hostName;
      if (typeof body.arch === 'string' && body.arch) edge.arch = body.arch;
      if (typeof body.memMB === 'number') edge.memMB = body.memMB;
      if (typeof body.uptimeSeconds === 'number') edge.uptimeSeconds = body.uptimeSeconds;
      if (typeof body.workspacePath === 'string' && body.workspacePath) edge.workspacePath = body.workspacePath;
      this.auth.touchDeviceByHostId(user.id, hostId);

      // Immediate dequeue if a command is already waiting
      const nextTask = edge.queue.shift();
      if (nextTask) {
        edge.inflight.set(nextTask.id, nextTask);
        this.sendJson(res, 200, {
          ok: true,
          task: { id: nextTask.id, command: nextTask.command, timeoutMs: nextTask.timeoutMs, cwd: nextTask.cwd },
        });
        return;
      }

      // Long-poll up to 20s waiting for a command
      const awaited = await new Promise<EdgeTask | null>((resolvePromise) => {
        const timer = setTimeout(() => {
          if (edge!.waiter === onTask) edge!.waiter = undefined;
          resolvePromise(null);
        }, 20_000);
        const onTask = (t: EdgeTask | null) => {
          clearTimeout(timer);
          edge!.waiter = undefined;
          resolvePromise(t);
        };
        if (edge!.waiter) edge!.waiter(null);
        edge!.waiter = onTask;
      });

      edge.lastSeenAt = Date.now();
      if (awaited) {
        edge.inflight.set(awaited.id, awaited);
        this.sendJson(res, 200, {
          ok: true,
          task: { id: awaited.id, command: awaited.command, timeoutMs: awaited.timeoutMs, cwd: awaited.cwd },
        });
      } else {
        this.sendJson(res, 200, { ok: true, task: null });
      }
      return;
    }

    if (path === '/api/edge/result' && method === 'POST') {
      const user = this.auth.authenticateToken(this.extractSessionToken(req));
      if (!user) {
        this.sendJson(res, 401, { ok: false, error: 'unauthenticated' });
        return;
      }
      const body = await this.readJsonBody(req);
      const hostId = String(body.hostId ?? '').trim();
      const taskId = String(body.taskId ?? '').trim();
      const edge = this.edgeNodes.get(hostId);
      if (!edge || edge.userId !== user.id) {
        this.sendJson(res, 404, { ok: false, error: 'edge_node_not_found' });
        return;
      }
      edge.lastSeenAt = Date.now();
      const task = edge.inflight.get(taskId);
      if (task) {
        edge.inflight.delete(taskId);
        clearTimeout(task.timer);
        task.resolve({
          ok: Number(body.exitCode ?? 0) === 0,
          exitCode: Number(body.exitCode ?? 0),
          stdout: String(body.stdout ?? ''),
          stderr: String(body.stderr ?? ''),
        });
      }
      this.sendJson(res, 200, { ok: true });
      return;
    }

    if (path === '/api/edge/snapshot' && method === 'GET') {
      const user = this.auth.authenticateToken(this.extractSessionToken(req));
      if (!user) {
        this.sendJson(res, 401, { ok: false, error: 'unauthenticated' });
        return;
      }
      const hostId = (url.searchParams.get('hostId') ?? '').trim();
      const edge = this.edgeNodes.get(hostId);
      if (!edge || edge.userId !== user.id) {
        this.sendJson(res, 200, {
          hostName: hostId,
          platform: 'linux',
          workspacePath: '/',
          harnesses: [],
          sessions: [],
          edgeMode: true,
          online: false,
        });
        return;
      }
      this.sendJson(res, 200, {
        hostName: edge.hostName,
        platform: `linux (${edge.arch} · ${edge.mode})`,
        arch: edge.arch,
        memMB: edge.memMB,
        uptimeSeconds: edge.uptimeSeconds,
        workspacePath: edge.workspacePath,
        harnesses: [],
        sessions: [
          {
            id: `edge_shell_${hostId}`,
            harnessId: 'shell',
            agent: `Edge Shell (${edge.arch} · ${edge.memMB ? edge.memMB + 'MB' : edge.mode})`,
            mode: 'cli',
            model: '',
            cwd: edge.workspacePath,
            status: Date.now() - edge.lastSeenAt < 45_000 ? 'running' : 'exited',
            exitCode: null,
            outputLines: [],
          },
        ],
        edgeMode: true,
        online: Date.now() - edge.lastSeenAt < 45_000,
      });
      return;
    }

    if (path === '/api/edge/exec' && method === 'POST') {
      const user = this.auth.authenticateToken(this.extractSessionToken(req));
      if (!user) {
        this.sendJson(res, 401, { ok: false, error: 'unauthenticated' });
        return;
      }
      const body = await this.readJsonBody(req);
      const hostId = String(body.hostId ?? '').trim();
      const command = String(body.command ?? '').trim();
      if (!hostId || !command) {
        this.sendJson(res, 400, { ok: false, error: 'missing_host_or_command' });
        return;
      }
      const edge = this.edgeNodes.get(hostId);
      if (!edge || edge.userId !== user.id || Date.now() - edge.lastSeenAt >= 45_000) {
        this.sendJson(res, 503, { ok: false, error: 'edge_node_offline' });
        return;
      }
      const timeoutMs = Math.max(2000, Math.min(30_000, Number(body.timeoutMs) || 20_000));
      const result = await new Promise<{ ok: boolean; exitCode: number; stdout: string; stderr: string }>((resolvePromise) => {
        const taskId = `et_${randomUUID().slice(0, 8)}`;
        const timer = setTimeout(() => {
          edge.inflight.delete(taskId);
          const qIdx = edge.queue.findIndex((t) => t.id === taskId);
          if (qIdx >= 0) edge.queue.splice(qIdx, 1);
          resolvePromise({ ok: false, exitCode: 124, stdout: '', stderr: '嵌入式节点执行超时' });
        }, timeoutMs + 4000);
        const task: EdgeTask = {
          id: taskId,
          command,
          timeoutMs,
          cwd: typeof body.cwd === 'string' ? body.cwd : undefined,
          resolve: resolvePromise,
          timer,
        };
        if (edge.waiter) {
          edge.waiter(task);
        } else {
          edge.queue.push(task);
        }
      });
      this.sendJson(res, 200, result);
      return;
    }

    if (path === '/cli/version.json') {
      const origin = this.resolveRequestOrigin(req) || 'https://pipibot.jimizhou.com';
      const sha = (content: string) => createHash('sha256').update(content, 'utf8').digest('hex');
      const nodeCandidates = [
        join(dirname(fileURLToPath(import.meta.url)), '../cli/pipibot.ts'),
        join(dirname(fileURLToPath(import.meta.url)), '../../daemon/src/relay-agent-host.ts'),
      ];
      const nodeFound = nodeCandidates.find((p) => existsSync(p));
      const nodeSrc = nodeFound ? readFileSync(nodeFound, 'utf8') : '';
      const liteSrc = renderPythonLiteAgent(origin);
      const edgeSrc = renderPosixEdgeAgent(origin);
      const versionMatch = nodeSrc.match(/PIPIBOT_CLI_VERSION\s*=\s*['"]([^'"]+)['"]/);
      const cliVersion = versionMatch?.[1] || PIPIBOT_EDGE_CLI_VERSION;
      this.sendJson(res, 200, {
        version: cliVersion,
        updatedAt: new Date().toISOString(),
        artifacts: {
          node: nodeSrc
            ? { url: `${origin}/cli/pipibot.ts`, sha256: sha(nodeSrc), bytes: Buffer.byteLength(nodeSrc, 'utf8') }
            : null,
          lite: { url: `${origin}/cli/pipibot-lite.py`, sha256: sha(liteSrc), bytes: Buffer.byteLength(liteSrc, 'utf8') },
          edge: { url: `${origin}/cli/pipibot-edge.sh`, sha256: sha(edgeSrc), bytes: Buffer.byteLength(edgeSrc, 'utf8') },
        },
      });
      return;
    }

    if (path === '/install.sh') {
      const origin = this.resolveRequestOrigin(req) || 'https://pipibot.jimizhou.com';
      const script = renderAdaptiveInstallScript(origin);
      res.writeHead(200, {
        'Content-Type': 'text/x-shellscript; charset=utf-8',
        'Cache-Control': 'no-store',
        'X-PipiBot-CLI-Version': PIPIBOT_EDGE_CLI_VERSION,
      });
      res.end(script);
      return;
    }

    if (path === '/cli/pipibot-lite.py') {
      const origin = this.resolveRequestOrigin(req) || 'https://pipibot.jimizhou.com';
      const body = renderPythonLiteAgent(origin);
      const digest = createHash('sha256').update(body, 'utf8').digest('hex');
      res.writeHead(200, {
        'Content-Type': 'text/x-python; charset=utf-8',
        'Cache-Control': 'no-store',
        'X-PipiBot-CLI-Version': PIPIBOT_EDGE_CLI_VERSION,
        'X-PipiBot-CLI-SHA256': digest,
      });
      res.end(body);
      return;
    }

    if (path === '/cli/pipibot-edge.sh') {
      const origin = this.resolveRequestOrigin(req) || 'https://pipibot.jimizhou.com';
      const body = renderPosixEdgeAgent(origin);
      const digest = createHash('sha256').update(body, 'utf8').digest('hex');
      res.writeHead(200, {
        'Content-Type': 'text/x-shellscript; charset=utf-8',
        'Cache-Control': 'no-store',
        'X-PipiBot-CLI-Version': PIPIBOT_EDGE_CLI_VERSION,
        'X-PipiBot-CLI-SHA256': digest,
      });
      res.end(body);
      return;
    }

    if (path === '/cli/pipibot.ts') {
      const candidates = [
        join(dirname(fileURLToPath(import.meta.url)), '../cli/pipibot.ts'),
        join(dirname(fileURLToPath(import.meta.url)), '../../daemon/src/relay-agent-host.ts'),
      ];
      const found = candidates.find((p) => existsSync(p));
      if (!found) {
        this.sendJson(res, 404, { error: 'cli_bundle_not_found' });
        return;
      }
      const body = readFileSync(found, 'utf8');
      const digest = createHash('sha256').update(body, 'utf8').digest('hex');
      const versionMatch = body.match(/PIPIBOT_CLI_VERSION\s*=\s*['"]([^'"]+)['"]/);
      res.writeHead(200, {
        'Content-Type': 'text/plain; charset=utf-8',
        'Cache-Control': 'no-store',
        'X-PipiBot-CLI-Version': versionMatch?.[1] || PIPIBOT_EDGE_CLI_VERSION,
        'X-PipiBot-CLI-SHA256': digest,
      });
      res.end(body);
      return;
    }

    if (path === '/login' || path === '/devices') {
      res.writeHead(200, {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-store',
      });
      res.end(renderLoginAndDevicesHTML());
      return;
    }

    if (path === '/manifest.webmanifest' || path === '/manifest.json') {
      res.writeHead(200, { 'Content-Type': 'application/manifest+json; charset=utf-8' });
      res.end(renderUniversalManifest());
      return;
    }

    if (path === '/icon.svg' || path === '/icon-192.svg') {
      res.writeHead(200, { 'Content-Type': 'image/svg+xml; charset=utf-8', 'Cache-Control': 'public, max-age=300' });
      res.end(renderUniversalIconSVG());
      return;
    }

    if (path === '/apple-touch-icon.png') {
      const iconPath = join(PUBLIC_ASSET_DIR, 'app-icon.png');
      if (existsSync(iconPath)) {
        res.writeHead(200, { 'Content-Type': 'image/png', 'Cache-Control': 'public, max-age=300' });
        res.end(readFileSync(iconPath));
        return;
      }
    }

    const assetMatch = /^\/assets\/([a-z0-9._-]+\.(png|svg|webp|jpg))$/i.exec(path);
    if (assetMatch) {
      const fileName = assetMatch[1]!;
      const ext = assetMatch[2]!.toLowerCase();
      const mime = STATIC_ASSET_MIME[ext];
      const fullPath = join(PUBLIC_ASSET_DIR, fileName);
      if (mime && !fileName.includes('..') && existsSync(fullPath)) {
        res.writeHead(200, { 'Content-Type': mime, 'Cache-Control': 'public, max-age=300' });
        res.end(readFileSync(fullPath));
        return;
      }
      res.writeHead(404, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ error: 'asset_not_found' }));
      return;
    }

    // Dedicated brand website routes: `/` (Overview), `/features`, `/download`
    if (path === '/') {
      res.writeHead(200, {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'public, max-age=120',
      });
      res.end(renderBrandLandingHTML());
      return;
    }

    if (path === '/features') {
      res.writeHead(200, {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'public, max-age=120',
      });
      res.end(renderBrandFeaturesHTML());
      return;
    }

    if (path === '/download') {
      res.writeHead(200, {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'public, max-age=120',
      });
      res.end(renderBrandDownloadHTML());
      return;
    }

    // Companion PWA entry points: /app, /pair, /c/<hostId> serve the consumer-grade 5-Tab E2EE Mobile PWA
    if (path === '/app' || path === '/pair' || /^\/c\/[a-zA-Z0-9_-]{4,64}$/.test(path)) {
      res.writeHead(200, {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-store',
      });
      res.end(renderUniversalPWAHTML({ relayMode: true }));
      return;
    }

    res.writeHead(404, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ error: 'not_found' }));
  }

  private handleWsMessage(meta: ConnMeta, rawText: string): void {
    const now = Date.now();
    meta.lastSeenAt = now;

    // Sliding-window rate limit per connection
    if (now - meta.windowStartMs >= 60_000) {
      meta.windowStartMs = now;
      meta.windowMsgCount = 0;
    }
    meta.windowMsgCount += 1;
    if (meta.windowMsgCount > this.options.maxMessagesPerMinutePerConn) {
      this.totalRateLimited += 1;
      meta.ws.sendText(JSON.stringify({ type: 'error', code: 'rate_limited' }));
      return;
    }

    let msg: Record<string, unknown>;
    try {
      msg = JSON.parse(rawText) as Record<string, unknown>;
    } catch {
      meta.ws.sendText(JSON.stringify({ type: 'error', code: 'invalid_json' }));
      return;
    }

    const type = String(msg.type ?? '');
    if (type === 'ping') {
      meta.ws.sendText(JSON.stringify({ type: 'pong', ts: now }));
      return;
    }

    if (type === 'host_register') {
      const hostId = String(msg.hostId ?? '').trim();
      const inviteKey = String(msg.inviteKey ?? '').trim();
      if (!/^[a-zA-Z0-9_-]{8,64}$/.test(hostId)) {
        meta.ws.sendText(JSON.stringify({ type: 'error', code: 'invalid_host_id' }));
        return;
      }
      if (this.inviteKeySet.size > 0 && !this.inviteKeySet.has(inviteKey)) {
        meta.ws.sendText(JSON.stringify({ type: 'error', code: 'invite_key_required' }));
        meta.ws.close(4003, 'Invite key required');
        return;
      }

      let room = this.rooms.get(hostId);
      if (!room) {
        room = { hostId, hostSocket: null, clients: new Map(), lastActiveAt: now };
        this.rooms.set(hostId, room);
      }
      if (room.hostSocket && room.hostSocket.id !== meta.ws.id) {
        room.hostSocket.close(4009, 'Replaced by newer host connection');
      }
      room.hostSocket = meta.ws;
      room.lastActiveAt = now;
      meta.role = 'host';
      meta.hostId = hostId;

      // Optional unified-account auto-registration when host supplies an accessToken
      const accessToken = typeof msg.accessToken === 'string' ? msg.accessToken : undefined;
      if (accessToken) {
        const user = this.auth.authenticateToken(accessToken);
        if (user) {
          if (typeof msg.hostPubKey === 'string' && msg.hostPubKey.trim()) {
            const rawPlat = String(msg.platform ?? 'macos').toLowerCase();
            const platform: DevicePlatformKind =
              rawPlat === 'linux' || rawPlat === 'windows' || rawPlat === 'ios' || rawPlat === 'web' ? rawPlat : 'macos';
            this.auth.registerDevice(user.id, {
              name: String(msg.deviceName ?? hostId),
              platform,
              hostId,
              hostPubKey: msg.hostPubKey,
              capabilities: Array.isArray(msg.capabilities) ? msg.capabilities.map(String) : [],
              workspacePath: typeof msg.workspacePath === 'string' ? msg.workspacePath : undefined,
            });
          } else {
            this.auth.touchDeviceByHostId(user.id, hostId);
          }
        }
      }

      meta.ws.sendText(JSON.stringify({ type: 'registered', hostId, clientsOnline: room.clients.size }));
      for (const clientWs of room.clients.values()) {
        clientWs.sendText(JSON.stringify({ type: 'host_status', hostId, online: true }));
      }
      return;
    }

    if (type === 'client_join') {
      const hostId = String(msg.hostId ?? '').trim();
      const clientId = String(msg.clientId ?? '').trim();
      if (!/^[a-zA-Z0-9_-]{8,64}$/.test(hostId) || !/^[a-zA-Z0-9_-]{4,64}$/.test(clientId)) {
        meta.ws.sendText(JSON.stringify({ type: 'error', code: 'invalid_join_params' }));
        return;
      }
      let room = this.rooms.get(hostId);
      if (!room) {
        room = { hostId, hostSocket: null, clients: new Map(), lastActiveAt: now };
        this.rooms.set(hostId, room);
      }
      if (room.clients.size >= this.options.maxClientsPerHost && !room.clients.has(clientId)) {
        this.totalRateLimited += 1;
        meta.ws.sendText(JSON.stringify({ type: 'error', code: 'host_client_limit_reached' }));
        meta.ws.close(4029, 'Host client limit reached');
        return;
      }
      room.clients.set(clientId, meta.ws);
      room.lastActiveAt = now;
      meta.role = 'client';
      meta.hostId = hostId;
      meta.clientId = clientId;
      const hostOnline = Boolean(room.hostSocket && room.hostSocket.readyState === 'open');
      meta.ws.sendText(JSON.stringify({ type: 'joined', hostId, clientId, hostOnline }));
      if (hostOnline && room.hostSocket) {
        room.hostSocket.sendText(JSON.stringify({ type: 'client_status', clientId, online: true }));
      }
      return;
    }

    if (type === 'envelope') {
      // Strictly zero-knowledge forwarding: never inspect, log, or alter `ct` / `nonce`.
      const hostId = meta.hostId ?? String(msg.hostId ?? '').trim();
      const clientId = String(msg.clientId ?? meta.clientId ?? '').trim();
      const room = this.rooms.get(hostId);
      if (!room) {
        meta.ws.sendText(JSON.stringify({ type: 'error', code: 'host_not_found' }));
        return;
      }
      room.lastActiveAt = now;

      if (meta.role === 'client') {
        if (!room.hostSocket || room.hostSocket.readyState !== 'open') {
          meta.ws.sendText(JSON.stringify({ type: 'error', code: 'host_offline' }));
          return;
        }
        room.hostSocket.sendText(rawText);
        this.totalEnvelopesRelayed += 1;
      } else if (meta.role === 'host') {
        const target = room.clients.get(clientId);
        if (target && target.readyState === 'open') {
          target.sendText(rawText);
          this.totalEnvelopesRelayed += 1;
        }
      }
    }
  }

  private handleWsClose(meta: ConnMeta): void {
    this.conns.delete(meta.ws.id);
    const curIpCount = this.ipConnCount.get(meta.ip) ?? 0;
    if (curIpCount <= 1) this.ipConnCount.delete(meta.ip);
    else this.ipConnCount.set(meta.ip, curIpCount - 1);

    if (!meta.hostId) return;
    const room = this.rooms.get(meta.hostId);
    if (!room) return;

    if (meta.role === 'host' && room.hostSocket?.id === meta.ws.id) {
      room.hostSocket = null;
      for (const clientWs of room.clients.values()) {
        clientWs.sendText(JSON.stringify({ type: 'host_status', hostId: room.hostId, online: false }));
      }
    } else if (meta.role === 'client' && meta.clientId) {
      room.clients.delete(meta.clientId);
      if (room.hostSocket && room.hostSocket.readyState === 'open') {
        room.hostSocket.sendText(JSON.stringify({ type: 'client_status', clientId: meta.clientId, online: false }));
      }
    }

    if (!room.hostSocket && room.clients.size === 0) {
      this.rooms.delete(meta.hostId);
    }
  }

  private reapIdleConnections(): void {
    const now = Date.now();
    for (const meta of this.conns.values()) {
      if (now - meta.lastSeenAt > this.options.idleTimeoutMs) {
        meta.ws.close(1000, 'Idle timeout');
      } else {
        meta.ws.ping();
      }
    }
  }

  /**
   * Optional RFC 5389 UDP STUN Binding Request reflector (XOR-MAPPED-ADDRESS)
   * to assist direct WebRTC ICE candidate discovery without external STUN servers.
   */
  private startStunReflector(port: number): Promise<number> {
    return new Promise((resolve, reject) => {
      const sock = dgram.createSocket('udp4');
      sock.on('message', (msg, rinfo) => {
        // STUN Binding Request: type 0x0001, magic cookie 0x2112A442 at bytes 4..7, min 20 bytes
        if (msg.length < 20) return;
        if (msg.readUInt16BE(0) !== 0x0001) return;
        if (msg.readUInt32BE(4) !== 0x2112a442) return;

        const ipParts = rinfo.address.split('.').map((n) => Number(n));
        if (ipParts.length !== 4 || ipParts.some((n) => !Number.isInteger(n) || n < 0 || n > 255)) return;

        // Build Binding Success Response (0x0101) with XOR-MAPPED-ADDRESS (0x0020)
        const resp = Buffer.alloc(32);
        resp.writeUInt16BE(0x0101, 0); // Binding Success
        resp.writeUInt16BE(12, 2); // Attr length
        resp.writeUInt32BE(0x2112a442, 4); // Magic Cookie
        msg.copy(resp, 8, 8, 20); // Transaction ID

        // XOR-MAPPED-ADDRESS attr header
        resp.writeUInt16BE(0x0020, 20);
        resp.writeUInt16BE(8, 22);
        resp[24] = 0x00;
        resp[25] = 0x01; // IPv4
        resp.writeUInt16BE(rinfo.port ^ 0x2112, 26);
        const ipInt = ((ipParts[0]! << 24) | (ipParts[1]! << 16) | (ipParts[2]! << 8) | ipParts[3]!) >>> 0;
        resp.writeUInt32BE((ipInt ^ 0x2112a442) >>> 0, 28);
        sock.send(resp, rinfo.port, rinfo.address);
      });
      sock.once('error', reject);
      sock.bind(port, '0.0.0.0', () => {
        sock.off('error', reject);
        this.stunSocket = sock;
        resolve(sock.address().port);
      });
    });
  }
}
