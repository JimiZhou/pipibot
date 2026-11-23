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

import dgram, { type Socket as UdpSocket } from 'node:dgram';
import { existsSync, readFileSync } from 'node:fs';
import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { PipiAuthService, type AuthServiceOptions, type DevicePlatformKind, type OAuthProviderKind } from './auth.ts';
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

export class PipiE2EERelayServer {
  private readonly options: Required<Omit<RelayServerOptions, 'auth'>>;
  private readonly auth: PipiAuthService;
  private readonly rooms = new Map<string, HostRoom>();
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
      maxMessagesPerMinutePerConn: options?.maxMessagesPerMinutePerConn ?? 240,
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
    for (const room of this.rooms.values()) {
      if (room.hostSocket && room.hostSocket.readyState === 'open') {
        online.add(room.hostId);
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

    if (path === '/install.sh') {
      const origin = this.publicOrigin || 'https://pipibot.jimizhou.com';
      const script = `#!/usr/bin/env bash
set -euo pipefail

ORIGIN="\${PIPIBOT_RELAY_ORIGIN:-${origin}}"
INSTALL_DIR="\${HOME}/.pipibot/bin"
TARGET_TS="\${INSTALL_DIR}/pipibot.ts"

echo "==> 正在安装 PiPiBot CLI（零依赖独立版）..."

if ! command -v node >/dev/null 2>&1; then
  echo "❌ 未检测到 Node.js。请先安装 Node.js >= 22.6：" >&2
  echo "   curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt-get install -y nodejs" >&2
  exit 1
fi

NODE_MAJOR="\$(node -p 'process.versions.node.split(".")[0]')"
if [ "\${NODE_MAJOR}" -lt 22 ]; then
  echo "❌ 当前 Node.js 版本过低 (\$(node -v))，需要 >= 22.6。" >&2
  exit 1
fi

mkdir -p "\${INSTALL_DIR}"
curl -fsSL "\${ORIGIN}/cli/pipibot.ts" -o "\${TARGET_TS}"

if [ -w "/usr/local/bin" ]; then
  BIN_PATH="/usr/local/bin/pipibot"
  cat > "\${BIN_PATH}" <<EOF
#!/usr/bin/env bash
export NODE_USE_ENV_PROXY=1
exec node --dns-result-order=ipv4first --experimental-strip-types --no-warnings "\${TARGET_TS}" "\\\$@"
EOF
  chmod +x "\${BIN_PATH}"
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  BIN_PATH="/usr/local/bin/pipibot"
  sudo tee "\${BIN_PATH}" >/dev/null <<EOF
#!/usr/bin/env bash
export NODE_USE_ENV_PROXY=1
exec node --dns-result-order=ipv4first --experimental-strip-types --no-warnings "\${TARGET_TS}" "\\\$@"
EOF
  sudo chmod +x "\${BIN_PATH}"
else
  mkdir -p "\${HOME}/.local/bin"
  BIN_PATH="\${HOME}/.local/bin/pipibot"
  cat > "\${BIN_PATH}" <<EOF
#!/usr/bin/env bash
export NODE_USE_ENV_PROXY=1
exec node --dns-result-order=ipv4first --experimental-strip-types --no-warnings "\${TARGET_TS}" "\\\$@"
EOF
  chmod +x "\${BIN_PATH}"
  for rc in "\${HOME}/.bashrc" "\${HOME}/.zshrc"; do
    if [ -f "\$rc" ] && ! grep -q '\.local/bin' "\$rc" 2>/dev/null; then
      echo 'export PATH="\$HOME/.local/bin:\$PATH"' >> "\$rc"
    fi
  done
fi

echo "✅ PiPiBot CLI 已安装到 \${BIN_PATH}"
if ! command -v pipibot >/dev/null 2>&1; then
  echo "💡 请先执行：export PATH=\\"\${HOME}/.local/bin:\\\$PATH\\""
fi
echo ""
echo "下一步：运行以下命令完成登录并以后台 systemd 常驻接入（自动上报本机 Agent Harness）："
echo "  pipibot login && pipibot up -d"
echo ""
`;
      res.writeHead(200, {
        'Content-Type': 'text/x-shellscript; charset=utf-8',
        'Cache-Control': 'no-store',
      });
      res.end(script);
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
      res.writeHead(200, {
        'Content-Type': 'text/plain; charset=utf-8',
        'Cache-Control': 'no-store',
      });
      res.end(readFileSync(found, 'utf8'));
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
