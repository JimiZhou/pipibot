/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/daemon - relay-agent-host.ts
 * Herdr-style CLI Agent Takeover Host + Unified Account Device Login (`pipibot login` / `pipibot up`):
 * - Authenticates via Device Flow against `https://pipibot.jimizhou.com` (Email OTP / Apple / GitHub / Google).
 * - Auto-detects installed CLI coding agents (`claude`, `codex`, `opencode`, `pi`, `ollama`).
 * - Maintains a persistent, auto-reconnecting Zero-Knowledge E2EE WebSocket to the free public relay.
 * - Exposes remote agent listing, task execution, live output observation, and `--takeover` ownership control.
 */

import { execFile, execFileSync, spawn, type ChildProcess } from 'node:child_process';
import { createECDH, createHash, createCipheriv, createDecipheriv, hkdfSync, randomBytes, randomUUID } from 'node:crypto';
import { setDefaultResultOrder } from 'node:dns';
import { chmodSync, existsSync, mkdirSync, openSync, readdirSync, readFileSync, renameSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { arch, cpus, freemem, homedir, hostname, platform, tmpdir, totalmem, uptime } from 'node:os';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

try {
  setDefaultResultOrder('ipv4first');
} catch {
  // Ignore on runtimes without ipv4first
}

const execFileAsync = promisify(execFile);

/**
 * Resilient JSON HTTP helper:
 * Uses Node native `fetch()` first, and transparently falls back to `curl`
 * when the host relies on `HTTP_PROXY`/`HTTPS_PROXY`/`ALL_PROXY` or has IPv6/undici quirks.
 */
async function resilientJsonFetch<T = Record<string, unknown>>(
  url: string,
  options?: { method?: string; headers?: Record<string, string>; body?: string },
): Promise<{ ok: boolean; status: number; data: T }> {
  const method = (options?.method ?? 'GET').toUpperCase();
  const headers = options?.headers ?? {};
  try {
    const resp = await fetch(url, { method, headers, body: options?.body });
    const text = await resp.text();
    const data = (text ? JSON.parse(text) : {}) as T;
    return { ok: resp.ok, status: resp.status, data };
  } catch (fetchErr) {
    // Fallback to curl (honors system proxy env vars & Happy Eyeballs IPv4 fallback)
    try {
      const args = ['-sS', '-X', method, '-w', '\n%{http_code}'];
      for (const [k, v] of Object.entries(headers)) {
        args.push('-H', `${k}: ${v}`);
      }
      if (options?.body !== undefined) {
        args.push('--data-raw', options.body);
      }
      args.push(url);
      const { stdout } = await execFileAsync('curl', args, { timeout: 20_000, maxBuffer: 4 * 1024 * 1024 });
      const lastNl = stdout.lastIndexOf('\n');
      const status = lastNl >= 0 ? Number(stdout.slice(lastNl + 1).trim()) : 200;
      const bodyStr = lastNl >= 0 ? stdout.slice(0, lastNl) : stdout;
      const data = (bodyStr.trim() ? JSON.parse(bodyStr) : {}) as T;
      return { ok: status >= 200 && status < 300, status, data };
    } catch (curlErr) {
      const cause = (fetchErr as { cause?: { message?: string; code?: string } })?.cause;
      const detail = cause?.code || cause?.message || (fetchErr instanceof Error ? fetchErr.message : String(fetchErr));
      const curlDetail = curlErr instanceof Error ? curlErr.message : String(curlErr);
      throw new Error(`网络请求失败 (${url}): ${detail} | curl fallback: ${curlDetail}`);
    }
  }
}

export const DEFAULT_RELAY_ORIGIN = 'https://pipibot.jimizhou.com';
export const PIPIBOT_CLI_VERSION = '0.13.4';

/**
 * Resilient plain-text HTTP GET helper with curl proxy fallback (used by CLI auto-upgrade).
 */
async function resilientTextFetch(url: string): Promise<{ ok: boolean; status: number; text: string }> {
  try {
    const resp = await fetch(url, { method: 'GET' });
    const text = await resp.text();
    return { ok: resp.ok, status: resp.status, text };
  } catch (fetchErr) {
    try {
      const { stdout } = await execFileAsync('curl', ['-fsSL', url], { timeout: 25_000, maxBuffer: 8 * 1024 * 1024 });
      return { ok: true, status: 200, text: stdout };
    } catch (curlErr) {
      const detail = fetchErr instanceof Error ? fetchErr.message : String(fetchErr);
      const curlDetail = curlErr instanceof Error ? curlErr.message : String(curlErr);
      throw new Error(`下载失败 (${url}): ${detail} | curl fallback: ${curlDetail}`);
    }
  }
}

export interface CliUpgradeResult {
  ok: boolean;
  updated: boolean;
  currentVersion: string;
  latestVersion: string;
  localSha256: string;
  remoteSha256: string;
  reason?: string;
  restarted?: boolean;
}

function sha256Hex(content: string | Buffer): string {
  return createHash('sha256').update(content).digest('hex');
}

function isInsideGitSourceCheckout(scriptPath: string): boolean {
  const normalized = scriptPath.replace(/\\/g, '/');
  return normalized.includes('/packages/daemon/src/relay-agent-host.ts') && existsSync(join(dirname(scriptPath), '../../../.git'));
}

export function isAutoUpgradeEnabled(): boolean {
  const raw = (process.env.PIPIBOT_AUTO_UPGRADE ?? '1').trim().toLowerCase();
  return !['0', 'false', 'no', 'off'].includes(raw);
}

/**
 * Checks `${relayOrigin}/cli/version.json`, verifies SHA-256 & TypeScript syntax, and atomically
 * replaces the installed PiPiBot CLI bundle (`~/.pipibot/bin/pipibot.ts`).
 */
export async function checkAndUpgradeCli(options?: {
  relayOrigin?: string;
  scriptPath?: string;
  force?: boolean;
  dryRun?: boolean;
  restartDaemon?: boolean;
}): Promise<CliUpgradeResult> {
  const relayOrigin = (options?.relayOrigin ?? process.env.PIPIBOT_RELAY_ORIGIN ?? DEFAULT_RELAY_ORIGIN).replace(/\/+$/, '');
  const scriptPath = options?.scriptPath ?? fileURLToPath(import.meta.url);
  const force = Boolean(options?.force);
  const dryRun = Boolean(options?.dryRun);

  let localSha256 = '';
  try {
    if (existsSync(scriptPath)) {
      localSha256 = sha256Hex(readFileSync(scriptPath));
    }
  } catch {
    localSha256 = '';
  }

  if (!force && !dryRun && isInsideGitSourceCheckout(scriptPath)) {
    return {
      ok: true,
      updated: false,
      currentVersion: PIPIBOT_CLI_VERSION,
      latestVersion: PIPIBOT_CLI_VERSION,
      localSha256,
      remoteSha256: localSha256,
      reason: 'git_source_checkout_protected',
    };
  }

  const manifestResp = await resilientJsonFetch<{
    version?: string;
    artifacts?: { node?: { url?: string; sha256?: string; bytes?: number } | null };
  }>(`${relayOrigin}/cli/version.json`);

  if (!manifestResp.ok || !manifestResp.data?.artifacts?.node) {
    return {
      ok: false,
      updated: false,
      currentVersion: PIPIBOT_CLI_VERSION,
      latestVersion: PIPIBOT_CLI_VERSION,
      localSha256,
      remoteSha256: '',
      reason: `manifest_unavailable_http_${manifestResp.status}`,
    };
  }

  const latestVersion = String(manifestResp.data.version || PIPIBOT_CLI_VERSION);
  const remoteSha256 = String(manifestResp.data.artifacts.node.sha256 || '');
  const downloadUrl = String(manifestResp.data.artifacts.node.url || `${relayOrigin}/cli/pipibot.ts`);

  if (remoteSha256 && localSha256 && remoteSha256 === localSha256 && !force) {
    return {
      ok: true,
      updated: false,
      currentVersion: PIPIBOT_CLI_VERSION,
      latestVersion,
      localSha256,
      remoteSha256,
      reason: 'already_up_to_date',
    };
  }

  if (dryRun) {
    return {
      ok: true,
      updated: false,
      currentVersion: PIPIBOT_CLI_VERSION,
      latestVersion,
      localSha256,
      remoteSha256,
      reason: 'update_available',
    };
  }

  const dl = await resilientTextFetch(downloadUrl);
  if (!dl.ok || !dl.text.includes('PIPIBOT_CLI_VERSION')) {
    return {
      ok: false,
      updated: false,
      currentVersion: PIPIBOT_CLI_VERSION,
      latestVersion,
      localSha256,
      remoteSha256,
      reason: `download_invalid_http_${dl.status}`,
    };
  }

  const actualSha = sha256Hex(dl.text);
  if (remoteSha256 && actualSha !== remoteSha256) {
    return {
      ok: false,
      updated: false,
      currentVersion: PIPIBOT_CLI_VERSION,
      latestVersion,
      localSha256,
      remoteSha256,
      reason: `sha256_mismatch_expected_${remoteSha256.slice(0, 8)}_got_${actualSha.slice(0, 8)}`,
    };
  }

  mkdirSync(dirname(scriptPath), { recursive: true });
  // Must end with `.ts` so Node's `--experimental-strip-types --check` parses TypeScript syntax!
  const tmpPath = join(dirname(scriptPath), `.pipibot-upgrade-${process.pid}-${Date.now()}.ts`);
  try {
    writeFileSync(tmpPath, dl.text, 'utf8');
    // Verify TypeScript bundle parses cleanly before swapping into place
    try {
      await execFileAsync(process.execPath, ['--experimental-strip-types', '--no-warnings', '--check', tmpPath], {
        timeout: 12_000,
      });
    } catch (syntaxErr) {
      try { unlinkSync(tmpPath); } catch { /* ignore */ }
      return {
        ok: false,
        updated: false,
        currentVersion: PIPIBOT_CLI_VERSION,
        latestVersion,
        localSha256,
        remoteSha256,
        reason: `syntax_check_failed: ${syntaxErr instanceof Error ? syntaxErr.message : String(syntaxErr)}`,
      };
    }
    try { chmodSync(tmpPath, 0o755); } catch { /* ignore */ }
    renameSync(tmpPath, scriptPath);
  } catch (err) {
    try { unlinkSync(tmpPath); } catch { /* ignore */ }
    return {
      ok: false,
      updated: false,
      currentVersion: PIPIBOT_CLI_VERSION,
      latestVersion,
      localSha256,
      remoteSha256,
      reason: `atomic_swap_failed: ${err instanceof Error ? err.message : String(err)}`,
    };
  }

  let restarted = false;
  if (options?.restartDaemon) {
    restarted = triggerRunningDaemonRestart(scriptPath);
  }

  return {
    ok: true,
    updated: true,
    currentVersion: PIPIBOT_CLI_VERSION,
    latestVersion,
    localSha256: actualSha,
    remoteSha256: remoteSha256 || actualSha,
    reason: 'upgraded',
    restarted,
  };
}

function triggerRunningDaemonRestart(scriptPath: string): boolean {
  const scope = detectSystemdServiceScope();
  if (scope) {
    try {
      const sysArgs = scope === 'user' ? ['--user', 'restart', SYSTEMD_SERVICE_NAME] : ['restart', SYSTEMD_SERVICE_NAME];
      execFileSync('systemctl', sysArgs, { stdio: 'ignore' });
      return true;
    } catch {
      return false;
    }
  }
  const pid = readRunningDaemonPid();
  if (pid && pid !== process.pid) {
    try {
      process.kill(pid, 'SIGTERM');
      try { unlinkSync(daemonPidPath()); } catch { /* ignore */ }
    } catch {
      // ignore
    }
    try {
      mkdirSync(dirname(daemonLogPath()), { recursive: true });
      const logFd = openSync(daemonLogPath(), 'a');
      const child = spawn(
        process.execPath,
        ['--dns-result-order=ipv4first', '--experimental-strip-types', '--no-warnings', scriptPath, 'up'],
        {
          detached: true,
          stdio: ['ignore', logFd, logFd],
          env: { ...process.env, NODE_USE_ENV_PROXY: '1' },
        },
      );
      child.unref();
      if (child.pid) {
        writeFileSync(daemonPidPath(), `${child.pid}\n`, 'utf8');
        return true;
      }
    } catch {
      return false;
    }
  }
  return false;
}

export interface SavedCliAuth {
  relayOrigin: string;
  accessToken: string;
  user: { id: string; email?: string; displayName: string };
  hostId: string;
  hostPrivateKeyB64Url: string;
  hostPublicKeyB64Url: string;
  updatedAt: string;
}

export interface ManagedAgentSession {
  id: string;
  harnessId: string;
  agent: string;
  mode: 'acp' | 'tui' | 'cli';
  model: string;
  cwd: string;
  status: 'running' | 'exited';
  ownerClientId: string | null;
  startedAt: string;
  exitCode: number | null;
  outputLines: string[];
  rawBuffer: string;
  streamSeq: number;
  subscribers: Set<string>;
  pendingStreamChunk: string;
  flushTimer?: ReturnType<typeof setTimeout>;
  proc?: ChildProcess;
}

export interface RemoteBrowserTabInfo {
  id: string;
  title: string;
  url: string;
  webSocketDebuggerUrl?: string;
}

interface RemoteBrowserState {
  running: boolean;
  attachedExternal: boolean;
  cdpPort: number;
  width: number;
  height: number;
  url: string;
  title: string;
  targetId: string;
  lastFrame: string;
  lastFrameAt: number;
  proc?: ChildProcess;
  cdpWs?: WebSocket;
  cdpSeq: number;
  cdpPending: Map<number, { resolve: (val: Record<string, unknown>) => void; reject: (err: Error) => void }>;
  subscribers: Set<string>;
}

export function cliAuthFilePath(): string {
  return process.env.PIPIBOT_CLI_AUTH_FILE ?? join(homedir(), '.pipibot', 'cli-auth.json');
}

function generateP256Identity(): { hostId: string; privateKeyB64Url: string; publicKeyB64Url: string } {
  const ecdh = createECDH('prime256v1');
  ecdh.generateKeys();
  const priv = ecdh.getPrivateKey();
  const pub = ecdh.getPublicKey(undefined, 'uncompressed');
  const hostId = createHash('sha256').update(pub).digest('hex').slice(0, 16);
  return {
    hostId,
    privateKeyB64Url: priv.toString('base64url'),
    publicKeyB64Url: pub.toString('base64url'),
  };
}

export function loadCliAuth(): SavedCliAuth | null {
  const path = cliAuthFilePath();
  if (!existsSync(path)) return null;
  try {
    return JSON.parse(readFileSync(path, 'utf8')) as SavedCliAuth;
  } catch {
    return null;
  }
}

export function saveCliAuth(auth: SavedCliAuth): void {
  const path = cliAuthFilePath();
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, JSON.stringify(auth, null, 2), 'utf8');
  try {
    chmodSync(path, 0o600);
  } catch {
    // Ignore on non-POSIX
  }
}

export function clearCliAuth(): void {
  const path = cliAuthFilePath();
  if (existsSync(path)) {
    writeFileSync(path, '{}', 'utf8');
  }
}

export interface DetectedCliHarness {
  id: string;
  name: string;
  binary: string;
  defaultModel: string;
  models: string[];
  configSource?: string;
  supportedModes: Array<'cli' | 'tui' | 'acp'>;
}

function readJsonSafe(filePath: string): Record<string, unknown> | null {
  try {
    if (!existsSync(filePath)) return null;
    return JSON.parse(readFileSync(filePath, 'utf8')) as Record<string, unknown>;
  } catch {
    return null;
  }
}

function candidateHomeDirs(): string[] {
  const dirs: string[] = [homedir()];
  const cwd = process.cwd();
  const m = /^(\/home\/[^/]+|\/Users\/[^/]+)/.exec(cwd);
  if (m?.[1] && !dirs.includes(m[1])) dirs.push(m[1]);
  const sudoUser = process.env.SUDO_USER;
  if (sudoUser && sudoUser !== 'root') {
    const uHome = platform() === 'darwin' ? `/Users/${sudoUser}` : `/home/${sudoUser}`;
    if (existsSync(uHome) && !dirs.includes(uHome)) dirs.push(uHome);
  }
  return dirs;
}

function readHarnessModels(id: string): { defaultModel: string; models: string[]; configSource?: string } {
  const homes = candidateHomeDirs();
  const dedupe = (list: Array<string | undefined | null>) =>
    [...new Set(list.map((x) => (x ?? '').trim()).filter(Boolean))];

  if (id === 'claude-code') {
    let configured: string | undefined;
    let source: string | undefined;
    const extra: string[] = [];
    for (const home of homes) {
      for (const cfgPath of [join(home, '.claude', 'settings.json'), join(home, '.claude', 'settings.local.json'), join(home, '.claude.json')]) {
        const cfg = readJsonSafe(cfgPath);
        if (!cfg) continue;
        if (!source) source = cfgPath;
        const env = (cfg.env as Record<string, unknown> | undefined) ?? {};
        const cModel = (cfg.model as string | undefined) || (env.ANTHROPIC_MODEL as string | undefined) || (env.ANTHROPIC_DEFAULT_SONNET_MODEL as string | undefined);
        if (cModel && !configured) configured = cModel;
        for (const k of ['ANTHROPIC_MODEL', 'ANTHROPIC_DEFAULT_OPUS_MODEL', 'ANTHROPIC_DEFAULT_SONNET_MODEL', 'ANTHROPIC_DEFAULT_HAIKU_MODEL']) {
          if (typeof env[k] === 'string') extra.push(String(env[k]));
        }
        if (Array.isArray(cfg.availableModels)) {
          for (const am of cfg.availableModels) if (typeof am === 'string') extra.push(am);
        }
      }
    }
    const models = dedupe([configured, ...extra]);
    if (models.length) return { defaultModel: models[0]!, models, configSource: source };
    return { defaultModel: '', models: ['(跟随 Claude 默认配置)'], configSource: source };
  }

  if (id === 'codex') {
    let configured: string | undefined;
    let source: string | undefined;
    const extra: string[] = [];
    for (const home of homes) {
      const cfgPath = join(home, '.codex', 'config.toml');
      if (!existsSync(cfgPath)) continue;
      if (!source) source = cfgPath;
      try {
        const raw = readFileSync(cfgPath, 'utf8');
        const m = /^\s*model\s*=\s*["']([^"']+)["']/m.exec(raw);
        if (m?.[1] && !configured) configured = m[1];
        for (const match of raw.matchAll(/\bmodel\s*=\s*["']([^"']+)["']/g)) {
          if (match[1]) extra.push(match[1]);
        }
      } catch {
        // ignore
      }
    }
    const models = dedupe([configured, ...extra]);
    if (models.length) return { defaultModel: models[0]!, models, configSource: source };
    return { defaultModel: '', models: ['(跟随 Codex 默认配置)'], configSource: source };
  }

  if (id === 'pi' || id === 'omp') {
    let configured: string | undefined;
    let source: string | undefined;
    const extra: string[] = [];
    for (const home of homes) {
      const paths =
        id === 'omp'
          ? [join(home, '.omp', 'config.json'), join(home, '.config', 'omp', 'config.json'), join(home, '.pi', 'agent', 'settings.json'), join(home, '.pi', 'agent', 'models.json')]
          : [join(home, '.pi', 'agent', 'settings.json'), join(home, '.pi', 'agent', 'models.json')];
      for (const p of paths) {
        const cfg = readJsonSafe(p);
        if (!cfg) continue;
        if (!source) source = p;
        const defaultProvider = typeof cfg.defaultProvider === 'string' ? cfg.defaultProvider : '';
        const defaultModel = typeof cfg.defaultModel === 'string' ? cfg.defaultModel : (typeof cfg.model === 'string' ? cfg.model : '');
        if (defaultModel && !configured) {
          configured = defaultProvider && !defaultModel.includes('/') ? `${defaultProvider}/${defaultModel}` : defaultModel;
        }
        if (Array.isArray(cfg.models)) {
          for (const item of cfg.models) {
            if (typeof item === 'string') extra.push(item);
            else if (item && typeof item === 'object' && typeof (item as Record<string, unknown>).id === 'string') {
              extra.push(String((item as Record<string, unknown>).id));
            }
          }
        }
        if (cfg.providers && typeof cfg.providers === 'object') {
          for (const [prov, pCfg] of Object.entries(cfg.providers as Record<string, unknown>)) {
            const pModels = (pCfg as Record<string, unknown> | null)?.models;
            if (Array.isArray(pModels)) {
              for (const pm of pModels) {
                const mid = typeof pm === 'string' ? pm : (pm as Record<string, unknown> | null)?.id;
                if (typeof mid === 'string') extra.push(`${prov}/${mid}`);
              }
            }
          }
        }
      }
    }
    const models = dedupe([configured, ...extra]);
    if (models.length) return { defaultModel: models[0]!, models, configSource: source };
    return { defaultModel: '', models: ['(跟随 Pi 默认配置)'], configSource: source };
  }

  if (id === 'agy') {
    let configured: string | undefined;
    let source: string | undefined;
    const extra: string[] = [];
    for (const home of homes) {
      for (const p of [join(home, '.gemini', 'antigravity', 'config.json'), join(home, '.config', 'agy', 'config.json')]) {
        const cfg = readJsonSafe(p);
        if (!cfg) continue;
        if (!source) source = p;
        if (typeof cfg.model === 'string' && !configured) configured = cfg.model;
        else if (typeof cfg.defaultModel === 'string' && !configured) configured = cfg.defaultModel;
        if (Array.isArray(cfg.models)) {
          for (const m of cfg.models) if (typeof m === 'string') extra.push(m);
        }
      }
    }
    const models = dedupe([configured, ...extra]);
    if (models.length) return { defaultModel: models[0]!, models, configSource: source };
    return { defaultModel: '', models: ['(跟随 AGY 默认配置)'], configSource: source };
  }

  if (id === 'opencode') {
    let configured: string | undefined;
    let source: string | undefined;
    const extra: string[] = [];
    for (const home of homes) {
      const cfgPath = join(home, '.config', 'opencode', 'opencode.json');
      const cfg = readJsonSafe(cfgPath);
      if (!cfg) continue;
      if (!source) source = cfgPath;
      if (typeof cfg.model === 'string' && !configured) configured = cfg.model;
      if (cfg.provider && typeof cfg.provider === 'object') {
        for (const [prov, pCfg] of Object.entries(cfg.provider as Record<string, unknown>)) {
          const pModels = (pCfg as Record<string, unknown> | null)?.models;
          if (pModels && typeof pModels === 'object') {
            for (const mKey of Object.keys(pModels as Record<string, unknown>)) {
              extra.push(`${prov}/${mKey}`);
            }
          }
        }
      }
    }
    const models = dedupe([configured, ...extra]);
    if (models.length) return { defaultModel: models[0]!, models, configSource: source };
    return { defaultModel: '', models: ['(跟随 OpenCode 默认配置)'], configSource: source };
  }

  return { defaultModel: '', models: ['(默认配置)'] };
}

export function detectLocalCliAgents(): DetectedCliHarness[] {
  const searchDirs = [
    ...(process.env.PATH ?? '').split(':'),
    '/opt/homebrew/bin',
    '/usr/local/bin',
    join(homedir(), '.local', 'bin'),
    join(homedir(), '.npm-global', 'bin'),
  ].filter(Boolean);

  const candidates: Array<{ id: string; name: string; bin: string; modes: Array<'cli' | 'tui' | 'acp'> }> = [
    { id: 'claude-code', name: 'Claude Code', bin: 'claude', modes: ['cli', 'tui', 'acp'] },
    { id: 'codex', name: 'OpenAI Codex', bin: 'codex', modes: ['cli', 'tui', 'acp'] },
    { id: 'pi', name: 'Pi Agent', bin: 'pi', modes: ['cli', 'tui', 'acp'] },
    { id: 'agy', name: 'AGY (Antigravity)', bin: 'agy', modes: ['cli', 'tui', 'acp'] },
    { id: 'omp', name: 'OMP (Oh-My-Pi)', bin: 'omp', modes: ['cli', 'tui'] },
    { id: 'opencode', name: 'OpenCode', bin: 'opencode', modes: ['cli', 'tui', 'acp'] },
    { id: 'ollama', name: 'Ollama', bin: 'ollama', modes: ['cli'] },
  ];

  const found: DetectedCliHarness[] = [];
  for (const c of candidates) {
    for (const dir of searchDirs) {
      const full = join(dir, c.bin);
      if (existsSync(full)) {
        const modelInfo = readHarnessModels(c.id);
        found.push({
          id: c.id,
          name: c.name,
          binary: full,
          defaultModel: modelInfo.defaultModel,
          models: modelInfo.models,
          configSource: modelInfo.configSource,
          supportedModes: c.modes,
        });
        break;
      }
    }
  }
  return found;
}

export async function runCliDeviceLogin(relayOrigin = DEFAULT_RELAY_ORIGIN): Promise<SavedCliAuth> {
  const origin = relayOrigin.replace(/\/+$/, '');
  const startResp = await resilientJsonFetch<{
    deviceCode: string;
    userCode: string;
    verificationUrl: string;
    expiresIn: number;
    interval: number;
  }>(`${origin}/api/auth/device/start`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ clientLabel: `CLI · ${hostname()}` }),
  });
  if (!startResp.ok) {
    throw new Error(`无法连接认证服务 (${startResp.status})`);
  }
  const flow = startResp.data;

  console.log('\n🔐 PiPiBot 统一账号登录');
  console.log(`   授权码：${flow.userCode}`);
  console.log(`   请在浏览器打开并确认：${flow.verificationUrl}\n`);

  // Try opening browser automatically only when a desktop display is available (skip on headless SSH/Linux)
  try {
    const isLinuxDesktop = platform() === 'linux' && Boolean(process.env.DISPLAY || process.env.WAYLAND_DISPLAY);
    const opener = platform() === 'darwin' ? 'open' : isLinuxDesktop ? 'xdg-open' : null;
    if (opener) {
      const p = spawn(opener, [flow.verificationUrl], { stdio: 'ignore', detached: true });
      p.on('error', () => {
        // Non-fatal if opener binary is unavailable
      });
      p.unref();
    }
  } catch {
    // Non-fatal in headless SSH
  }

  const deadline = Date.now() + flow.expiresIn * 1000;
  const intervalMs = Math.max(1500, (flow.interval || 2) * 1000);

  while (Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, intervalMs));
    let pollResp: {
      ok: boolean;
      data: {
        status: 'pending' | 'approved' | 'expired';
        accessToken?: string;
        user?: { id: string; email?: string; displayName: string };
      };
    };
    try {
      pollResp = await resilientJsonFetch(`${origin}/api/auth/device/poll`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ deviceCode: flow.deviceCode }),
      });
    } catch {
      continue;
    }
    if (!pollResp.ok) continue;
    const poll = pollResp.data;
    if (poll.status === 'expired') {
      throw new Error('登录授权已过期，请重新运行 pipibot login');
    }
    if (poll.status === 'approved' && poll.accessToken && poll.user) {
      const existing = loadCliAuth();
      const identity =
        existing?.hostId && existing?.hostPrivateKeyB64Url && existing?.hostPublicKeyB64Url
          ? {
              hostId: existing.hostId,
              privateKeyB64Url: existing.hostPrivateKeyB64Url,
              publicKeyB64Url: existing.hostPublicKeyB64Url,
            }
          : generateP256Identity();

      const saved: SavedCliAuth = {
        relayOrigin: origin,
        accessToken: poll.accessToken,
        user: poll.user,
        hostId: identity.hostId,
        hostPrivateKeyB64Url: identity.privateKeyB64Url,
        hostPublicKeyB64Url: identity.publicKeyB64Url,
        updatedAt: new Date().toISOString(),
      };
      saveCliAuth(saved);
      console.log(`✅ 登录成功！欢迎 ${poll.user.email || poll.user.displayName}`);
      console.log(`   下一步：运行 \`pipibot up\` 将本机接入免费加密中转，手机/网页端即可随时接管本机 Agent。\n`);
      return saved;
    }
  }
  throw new Error('登录超时，请重试');
}

export async function listAccountDevices(relayOrigin?: string): Promise<void> {
  const auth = loadCliAuth();
  if (!auth?.accessToken) {
    console.log('尚未登录，请先运行：pipibot login');
    return;
  }
  const origin = (relayOrigin ?? auth.relayOrigin ?? DEFAULT_RELAY_ORIGIN).replace(/\/+$/, '');
  const resp = await resilientJsonFetch<{
    devices: Array<{ id: string; name: string; platform: string; hostId: string; isOnline: boolean; capabilities: string[] }>;
  }>(`${origin}/api/devices`, {
    headers: { Authorization: `Bearer ${auth.accessToken}` },
  });
  if (!resp.ok) {
    console.log(`获取设备列表失败 (${resp.status})，请重新登录：pipibot login`);
    return;
  }
  const data = resp.data;
  if (!data.devices.length) {
    console.log('当前账号下暂无已注册设备。在本机运行 `pipibot up` 即可上线。');
    return;
  }
  console.log(`\n📱 我的 PiPiBot 设备（${auth.user.email || auth.user.displayName}）：`);
  for (const d of data.devices) {
    const status = d.isOnline ? '🟢 在线' : '⚪ 离线';
    const caps = d.capabilities?.length ? ` [${d.capabilities.join(', ')}]` : '';
    console.log(`  ${status}  ${d.name} (${d.platform}) · hostId=${d.hostId}${caps}`);
  }
  console.log('');
}

// MARK: - Herdr-style Local Agent Supervisor + E2EE Relay Host

export class PipiCliAgentRelayHost {
  private readonly auth: SavedCliAuth;
  private readonly deviceName: string;
  private readonly workspacePath: string;
  private readonly detectedAgents: DetectedCliHarness[];
  private readonly sessions = new Map<string, ManagedAgentSession>();
  private readonly chatMessages: Array<{ id: string; role: 'user' | 'assistant'; author?: string; content: string; createdAt: string }> = [];
  private readonly clientKeys = new Map<string, { key: Buffer; txSeq: number }>();
  private readonly verifiedPeerTokens = new Set<string>();
  private readonly browser: RemoteBrowserState = {
    running: false,
    attachedExternal: false,
    cdpPort: 9222,
    width: 1280,
    height: 800,
    url: 'about:blank',
    title: '',
    targetId: '',
    lastFrame: '',
    lastFrameAt: 0,
    cdpSeq: 0,
    cdpPending: new Map(),
    subscribers: new Set(),
  };
  private ws: WebSocket | null = null;
  private stopped = false;
  private autoUpgradeStartupTimer: ReturnType<typeof setTimeout> | null = null;
  private autoUpgradeIntervalTimer: ReturnType<typeof setInterval> | null = null;
  private pendingUpgradeRestart = false;

  constructor(auth: SavedCliAuth, options?: { deviceName?: string; workspacePath?: string }) {
    this.auth = auth;
    this.deviceName = options?.deviceName?.trim() || hostname();
    this.workspacePath = options?.workspacePath?.trim() || process.cwd();
    this.detectedAgents = detectLocalCliAgents();
  }

  private deriveSessionKey(clientPubKeyB64Url: string, sid: string): Buffer {
    const ecdh = createECDH('prime256v1');
    ecdh.setPrivateKey(Buffer.from(this.auth.hostPrivateKeyB64Url, 'base64url'));
    const shared = ecdh.computeSecret(Buffer.from(clientPubKeyB64Url, 'base64url'));
    return Buffer.from(
      hkdfSync(
        'sha256',
        shared,
        Buffer.from(`pipibot-e2ee-v1:${this.auth.hostId}`, 'utf8'),
        Buffer.from(`pipibot-aes256gcm-session:${sid}`, 'utf8'),
        32,
      ),
    );
  }

  private openEnvelope(env: {
    sid: string;
    dir: string;
    seq: number;
    nonce: string;
    ct: string;
    clientId: string;
    clientPubKey?: string;
  }): { key: Buffer; plaintext: Record<string, unknown> } | null {
    try {
      const sessKey = `${env.clientId}:${env.sid}`;
      let entry = this.clientKeys.get(sessKey);
      if (!entry && env.clientPubKey) {
        entry = { key: this.deriveSessionKey(env.clientPubKey, env.sid), txSeq: 0 };
        this.clientKeys.set(sessKey, entry);
      }
      if (!entry) return null;
      const nonce = Buffer.from(env.nonce, 'base64url');
      const combined = Buffer.from(env.ct, 'base64url');
      const ct = combined.subarray(0, combined.length - 16);
      const tag = combined.subarray(combined.length - 16);
      const aad = Buffer.from(`v1|${env.sid}|${env.dir}|${env.seq}`, 'utf8');
      const decipher = createDecipheriv('aes-256-gcm', entry.key, nonce);
      decipher.setAAD(aad);
      decipher.setAuthTag(tag);
      const plainBuf = Buffer.concat([decipher.update(ct), decipher.final()]);
      return { key: entry.key, plaintext: JSON.parse(plainBuf.toString('utf8')) as Record<string, unknown> };
    } catch {
      return null;
    }
  }

  private sendEncryptedResponse(clientId: string, sid: string, payload: unknown): void {
    const entry = this.clientKeys.get(`${clientId}:${sid}`);
    if (!entry || !this.ws || this.ws.readyState !== WebSocket.OPEN) return;
    entry.txSeq += 1;
    const seq = entry.txSeq;
    const nonce = randomBytes(12);
    const aad = Buffer.from(`v1|${sid}|h2c|${seq}`, 'utf8');
    const cipher = createCipheriv('aes-256-gcm', entry.key, nonce);
    cipher.setAAD(aad);
    const plain = Buffer.from(JSON.stringify(payload), 'utf8');
    const enc = Buffer.concat([cipher.update(plain), cipher.final()]);
    const tag = cipher.getAuthTag();
    this.ws.send(
      JSON.stringify({
        type: 'envelope',
        v: 1,
        hostId: this.auth.hostId,
        clientId,
        sid,
        dir: 'h2c',
        seq,
        nonce: nonce.toString('base64url'),
        ct: Buffer.concat([enc, tag]).toString('base64url'),
      }),
    );
  }

  private async verifyPeerToken(token: string | undefined): Promise<boolean> {
    const trimmed = (token ?? '').trim();
    if (!trimmed) return false;
    if (trimmed === this.auth.accessToken || this.verifiedPeerTokens.has(trimmed)) {
      return true;
    }
    try {
      const resp = await resilientJsonFetch<{ ok?: boolean; user?: { id?: string } }>(`${this.auth.relayOrigin}/api/auth/me`, {
        headers: { Authorization: `Bearer ${trimmed}` },
      });
      if (!resp.ok) return false;
      const data = resp.data;
      if (data.ok && data.user?.id && data.user.id === this.auth.user.id) {
        this.verifiedPeerTokens.add(trimmed);
        return true;
      }
      return false;
    } catch {
      return false;
    }
  }

  private resolveTargetPath(inputPath?: string): string {
    const raw = (inputPath ?? '').trim();
    if (!raw) return this.workspacePath;
    if (raw.startsWith('~/')) {
      return join(homedir(), raw.slice(2));
    }
    return isAbsolute(raw) ? resolve(raw) : resolve(this.workspacePath, raw);
  }

  private static stripAnsi(input: string): string {
    // Remove ANSI CSI/OSC escape sequences for clean terminal transcript rendering
    return input
      .replace(/\x1B\[[0-9;?]*[ -/]*[@-~]/g, '')
      .replace(/\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)/g, '')
      .replace(/\r/g, '');
  }

  private static shellQuote(arg: string): string {
    return `'${arg.replace(/'/g, `'\\''`)}'`;
  }

  private static parseStructuredAcpLine(rawLine: string): string | null {
    const trimmed = rawLine.trim();
    if (!trimmed) return null;
    if (!trimmed.startsWith('{')) return trimmed;
    try {
      const obj = JSON.parse(trimmed) as Record<string, unknown>;
      // Claude Code stream-json & streaming deltas
      if (obj.type === 'stream_event' && obj.event && typeof obj.event === 'object') {
        const ev = obj.event as Record<string, unknown>;
        if (ev.type === 'content_block_delta' && ev.delta && typeof ev.delta === 'object') {
          const d = ev.delta as Record<string, unknown>;
          if (typeof d.text === 'string' && d.text) return d.text;
          if (typeof d.thinking === 'string' && d.thinking) return d.thinking;
        }
        return null;
      }
      if (obj.type === 'content_block_delta' && obj.delta && typeof obj.delta === 'object') {
        const d = obj.delta as Record<string, unknown>;
        if (typeof d.text === 'string' && d.text) return d.text;
        return null;
      }
      if (obj.type === 'assistant' && obj.message && typeof obj.message === 'object') {
        const content = (obj.message as Record<string, unknown>).content;
        if (Array.isArray(content)) {
          const parts: string[] = [];
          for (const block of content) {
            if (!block || typeof block !== 'object') continue;
            const b = block as Record<string, unknown>;
            if (b.type === 'text' && typeof b.text === 'string') parts.push(b.text);
            else if (b.type === 'tool_use' && typeof b.name === 'string') parts.push(`🔧 调用工具 \`${b.name}\``);
          }
          return parts.length ? parts.join('\n') : null;
        }
      }
      if (obj.type === 'result' && typeof obj.result === 'string' && obj.result.trim()) {
        return obj.result.trim();
      }
      // Codex exec --json
      if (obj.type === 'item.completed' && obj.item && typeof obj.item === 'object') {
        const item = obj.item as Record<string, unknown>;
        if (typeof item.text === 'string' && item.text.trim()) return item.text.trim();
        if (item.type === 'command_execution' && typeof item.command === 'string') {
          return `⚡ \`${item.command}\`${typeof item.aggregated_output === 'string' && item.aggregated_output.trim() ? '\n```\n' + item.aggregated_output.trim().slice(0, 1200) + '\n```' : ''}`;
        }
      }
      // Generic ACP / Pi / OpenCode JSON events
      if (typeof obj.text === 'string' && obj.text.trim()) return obj.text.trim();
      if (typeof obj.content === 'string' && obj.content.trim()) return obj.content.trim();
      if (typeof obj.delta === 'string' && obj.delta) return obj.delta;
      if (obj.error) return `⚠️ ${typeof obj.error === 'string' ? obj.error : JSON.stringify(obj.error)}`;
      return null;
    } catch {
      return trimmed;
    }
  }

  private static serializeSession(sess: ManagedAgentSession): Record<string, unknown> {
    return {
      id: sess.id,
      harnessId: sess.harnessId,
      agent: sess.agent,
      mode: sess.mode,
      model: sess.model,
      cwd: sess.cwd,
      status: sess.status,
      ownerClientId: sess.ownerClientId,
      startedAt: sess.startedAt,
      exitCode: sess.exitCode,
      outputLines: sess.outputLines.slice(-80),
      streamSeq: sess.streamSeq,
    };
  }

  private broadcastToSubscribers(subscribers: Set<string>, payload: unknown): void {
    for (const subKey of [...subscribers]) {
      if (!this.clientKeys.has(subKey)) {
        subscribers.delete(subKey);
        continue;
      }
      const sep = subKey.indexOf(':');
      if (sep <= 0) continue;
      const clientId = subKey.slice(0, sep);
      const sid = subKey.slice(sep + 1);
      this.sendEncryptedResponse(clientId, sid, payload);
    }
  }

  private flushSessionStream(session: ManagedAgentSession): void {
    if (session.flushTimer) {
      clearTimeout(session.flushTimer);
      session.flushTimer = undefined;
    }
    if (!session.pendingStreamChunk) return;
    const chunk = session.pendingStreamChunk;
    session.pendingStreamChunk = '';
    session.streamSeq += 1;
    const streamKind = session.mode === 'tui' ? 'pty' : session.mode === 'acp' ? 'acp' : 'stdout';
    this.broadcastToSubscribers(session.subscribers, {
      kind: 'agent_stream',
      sessionId: session.id,
      seq: session.streamSeq,
      stream: streamKind,
      chunk,
      status: session.status,
      exitCode: session.exitCode,
    });
  }

  private queueSessionStream(session: ManagedAgentSession, chunk: string): void {
    if (!chunk) return;
    session.rawBuffer += chunk;
    if (session.rawBuffer.length > 131072) {
      session.rawBuffer = session.rawBuffer.slice(session.rawBuffer.length - 131072);
    }
    if (session.subscribers.size === 0) return;
    session.pendingStreamChunk += chunk;
    if (session.pendingStreamChunk.length >= 8192) {
      this.flushSessionStream(session);
      return;
    }
    if (!session.flushTimer) {
      session.flushTimer = setTimeout(() => this.flushSessionStream(session), 35);
    }
  }

  startAgentSession(
    agentId: string,
    prompt: string,
    ownerClientId: string | null,
    cwdOverride?: string,
    modelOverride?: string,
    modeOverride?: string,
    initialSubscriberKey?: string,
  ): ManagedAgentSession {
    const id = `agt_${randomUUID().slice(0, 8)}`;
    const normalized = agentId.trim().toLowerCase();
    const isShell = normalized === 'shell' || normalized === 'sh' || normalized === 'bash' || normalized === 'zsh';
    const found = isShell
      ? null
      : this.detectedAgents.find(
          (a) =>
            a.id.toLowerCase() === normalized ||
            a.name.toLowerCase() === normalized ||
            (normalized === 'claude' && a.id === 'claude-code') ||
            (normalized === 'openai codex' && a.id === 'codex'),
        );
    const targetCwd = this.resolveTargetPath(cwdOverride);
    const selectedModel = isShell ? '' : ((modelOverride ?? '').trim() || found?.defaultModel || '');
    const rawMode = (modeOverride ?? (isShell ? 'tui' : 'cli')).trim().toLowerCase();
    const selectedMode: 'acp' | 'tui' | 'cli' = isShell
      ? 'tui'
      : rawMode === 'acp'
        ? 'acp'
        : rawMode === 'tui'
          ? 'tui'
          : 'cli';
    const modeTag = selectedMode === 'acp' ? 'ACP' : selectedMode === 'tui' ? 'TUI PTY' : 'CLI';
    const displayAgentName = isShell ? 'Interactive Shell' : (found?.name ?? agentId);
    const label = `${displayAgentName}${selectedModel ? ` · ${selectedModel}` : ''} [${modeTag}]`;
    const cleanPrompt = prompt.trim();
    const headerLine = `[${new Date().toLocaleTimeString()}] 启动 ${label}${cleanPrompt ? `: ${cleanPrompt}` : ''}`;
    const subscribers = new Set<string>();
    if (initialSubscriberKey) subscribers.add(initialSubscriberKey);
    const session: ManagedAgentSession = {
      id,
      harnessId: isShell ? 'shell' : (found?.id ?? agentId),
      agent: label,
      mode: selectedMode,
      model: selectedModel,
      cwd: targetCwd,
      status: 'running',
      ownerClientId,
      startedAt: new Date().toISOString(),
      exitCode: null,
      outputLines: [headerLine],
      rawBuffer: selectedMode === 'tui' ? `\x1b[2m${headerLine}\x1b[0m\r\n` : `${headerLine}\n`,
      streamSeq: 0,
      subscribers,
      pendingStreamChunk: '',
    };
    this.sessions.set(id, session);

    if (isShell || found) {
      let binary = found?.binary ?? '';
      let args: string[] = [];
      if (isShell) {
        binary = platform() === 'win32' ? 'cmd.exe' : (process.env.SHELL || '/bin/bash');
        args = platform() === 'win32' ? [] : ['-i'];
      } else if (found) {
        if (selectedMode === 'acp') {
          // Structured ACP / JSON-stream protocol
          if (found.id === 'claude-code') {
            args = selectedModel
              ? ['--output-format', 'stream-json', '--verbose', '--include-partial-messages', '--model', selectedModel, '-p', cleanPrompt]
              : ['--output-format', 'stream-json', '--verbose', '--include-partial-messages', '-p', cleanPrompt];
          } else if (found.id === 'codex') {
            args = selectedModel ? ['exec', '--json', '-m', selectedModel, cleanPrompt] : ['exec', '--json', cleanPrompt];
          } else if (found.id === 'pi' || found.id === 'omp') {
            args = selectedModel ? ['--mode', 'json', '--model', selectedModel, '-p', cleanPrompt] : ['--mode', 'json', '-p', cleanPrompt];
          } else if (found.id === 'opencode') {
            args = selectedModel ? ['run', '--format', 'json', '-m', selectedModel, cleanPrompt] : ['run', '--format', 'json', cleanPrompt];
          } else if (found.id === 'agy') {
            args = selectedModel ? ['--model', selectedModel, '-p', cleanPrompt] : ['-p', cleanPrompt];
          } else {
            args = cleanPrompt ? [cleanPrompt] : [];
          }
        } else if (selectedMode === 'tui') {
          // Interactive TUI invocation inside a real POSIX PTY (supports empty prompt for direct interactive TUI!)
          if (found.id === 'claude-code') {
            args = [...(selectedModel ? ['--model', selectedModel] : []), ...(cleanPrompt ? [cleanPrompt] : [])];
          } else if (found.id === 'codex') {
            args = [...(selectedModel ? ['-m', selectedModel] : []), ...(cleanPrompt ? [cleanPrompt] : [])];
          } else if (found.id === 'pi' || found.id === 'omp') {
            args = [...(selectedModel ? ['--model', selectedModel] : []), ...(cleanPrompt ? [cleanPrompt] : [])];
          } else if (found.id === 'opencode') {
            args = [...(selectedModel ? ['-m', selectedModel] : []), ...(cleanPrompt ? [cleanPrompt] : [])];
          } else if (found.id === 'agy') {
            args = [...(selectedModel ? ['--model', selectedModel] : []), ...(cleanPrompt ? ['-i', cleanPrompt] : [])];
          } else {
            args = cleanPrompt ? [cleanPrompt] : [];
          }
        } else {
          // Headless CLI mode (default for PiPiBot autonomous orchestration)
          if (found.id === 'claude-code') {
            args = selectedModel ? ['--model', selectedModel, '-p', cleanPrompt] : ['-p', cleanPrompt];
          } else if (found.id === 'codex') {
            args = selectedModel ? ['exec', '-m', selectedModel, cleanPrompt] : ['exec', cleanPrompt];
          } else if (found.id === 'pi' || found.id === 'omp') {
            args = selectedModel ? ['--model', selectedModel, '-p', cleanPrompt] : ['-p', cleanPrompt];
          } else if (found.id === 'agy') {
            args = selectedModel ? ['--model', selectedModel, '-p', cleanPrompt] : ['-p', cleanPrompt];
          } else {
            args = cleanPrompt ? [cleanPrompt] : [];
          }
        }
      }

      let proc: ChildProcess;
      if (selectedMode === 'tui' && platform() !== 'win32') {
        const ptyEnv = { ...process.env, TERM: 'xterm-256color', COLORTERM: 'truecolor', COLUMNS: '120', LINES: '36' };
        if (platform() === 'darwin') {
          proc = spawn('script', ['-q', '/dev/null', binary, ...args], {
            cwd: targetCwd,
            stdio: ['pipe', 'pipe', 'pipe'],
            env: ptyEnv,
          });
        } else {
          const fullCmd = [binary, ...args].map((a) => PipiCliAgentRelayHost.shellQuote(a)).join(' ');
          proc = spawn('script', ['-qefc', fullCmd, '/dev/null'], {
            cwd: targetCwd,
            stdio: ['pipe', 'pipe', 'pipe'],
            env: ptyEnv,
          });
        }
      } else {
        proc = spawn(binary, args, {
          cwd: targetCwd,
          stdio: ['pipe', 'pipe', 'pipe'],
          env: { ...process.env, FORCE_COLOR: '1' },
        });
      }

      session.proc = proc;
      if (isShell && cleanPrompt && proc.stdin?.writable) {
        setTimeout(() => {
          if (proc.stdin?.writable) proc.stdin.write(`${cleanPrompt}\r`);
        }, 120);
      }

      let lineBuf = '';
      const append = (chunk: Buffer) => {
        const rawText = chunk.toString('utf8');
        if (selectedMode === 'acp') {
          lineBuf += rawText;
          const parts = lineBuf.split(/\r?\n/);
          lineBuf = parts.pop() ?? '';
          for (const p of parts) {
            const parsed = PipiCliAgentRelayHost.parseStructuredAcpLine(p);
            if (parsed) {
              session.outputLines.push(parsed);
              const needsNl = !parsed.endsWith('\n') && parsed.length > 24;
              this.queueSessionStream(session, needsNl ? `${parsed}\n` : parsed);
            }
          }
        } else if (selectedMode === 'tui') {
          // Preserve raw ANSI sequences for native terminal rendering!
          this.queueSessionStream(session, rawText);
          const stripped = PipiCliAgentRelayHost.stripAnsi(rawText);
          const lines = stripped.split(/\r?\n/).filter((l) => l.trim().length > 0);
          if (lines.length) session.outputLines.push(...lines);
        } else {
          this.queueSessionStream(session, rawText);
          const lines = rawText.split(/\r?\n/).filter((l) => l.trim().length > 0);
          if (lines.length) session.outputLines.push(...lines);
        }
        if (session.outputLines.length > 400) {
          session.outputLines.splice(0, session.outputLines.length - 400);
        }
      };
      proc.stdout?.on('data', append);
      proc.stderr?.on('data', append);
      proc.on('exit', (code) => {
        if (selectedMode === 'acp' && lineBuf.trim()) {
          const parsed = PipiCliAgentRelayHost.parseStructuredAcpLine(lineBuf);
          if (parsed) {
            session.outputLines.push(parsed);
            this.queueSessionStream(session, `${parsed}\n`);
          }
          lineBuf = '';
        }
        this.flushSessionStream(session);
        session.status = 'exited';
        session.exitCode = code ?? 0;
        session.proc = undefined;
        session.streamSeq += 1;
        this.broadcastToSubscribers(session.subscribers, {
          kind: 'agent_stream',
          sessionId: session.id,
          seq: session.streamSeq,
          stream: 'status',
          chunk: '',
          status: 'exited',
          exitCode: session.exitCode,
        });
      });
    } else {
      session.status = 'exited';
      session.exitCode = 127;
      session.outputLines.push(`未在本机检测到 Agent：${agentId}`);
      session.rawBuffer += `未在本机检测到 Agent：${agentId}\n`;
    }
    return session;
  }

  private async runShellExec(
    command: string,
    cwdOverride?: string,
    timeoutMsRaw?: number,
  ): Promise<{ ok: boolean; exitCode: number; stdout: string; stderr: string; cwd: string; durationMs: number }> {
    const cwd = this.resolveTargetPath(cwdOverride);
    const timeoutMs = Math.max(1000, Math.min(30_000, Number(timeoutMsRaw) || 15_000));
    const startedAt = Date.now();
    const shell = platform() === 'win32' ? 'cmd.exe' : '/bin/sh';
    const shellArgs = platform() === 'win32' ? ['/c', command] : ['-lc', command];
    const maxBytes = 32 * 1024;

    return await new Promise((resolvePromise) => {
      let stdout = '';
      let stderr = '';
      let settled = false;
      const proc = spawn(shell, shellArgs, { cwd, stdio: ['ignore', 'pipe', 'pipe'] });

      const finish = (exitCode: number) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        resolvePromise({
          ok: exitCode === 0,
          exitCode,
          stdout: stdout.slice(0, maxBytes),
          stderr: stderr.slice(0, maxBytes),
          cwd,
          durationMs: Date.now() - startedAt,
        });
      };

      const timer = setTimeout(() => {
        stderr += `\n[pipibot-daemon] 命令超时（>${timeoutMs}ms）已终止`;
        proc.kill('SIGTERM');
        finish(124);
      }, timeoutMs);

      proc.stdout?.on('data', (chunk: Buffer) => {
        if (stdout.length < maxBytes) stdout += chunk.toString('utf8');
      });
      proc.stderr?.on('data', (chunk: Buffer) => {
        if (stderr.length < maxBytes) stderr += chunk.toString('utf8');
      });
      proc.on('error', (err) => {
        stderr += err.message;
        finish(1);
      });
      proc.on('exit', (code) => {
        finish(code ?? 0);
      });
    });
  }

  private async collectSystemInfo(): Promise<Record<string, unknown>> {
    let gitBranch: string | null = null;
    let gitDirtyCount: number | null = null;
    try {
      const { stdout: branchOut } = await execFileAsync('git', ['rev-parse', '--abbrev-ref', 'HEAD'], {
        cwd: this.workspacePath,
        timeout: 2000,
      });
      gitBranch = branchOut.trim() || null;
      const { stdout: statusOut } = await execFileAsync('git', ['status', '--porcelain'], {
        cwd: this.workspacePath,
        timeout: 2000,
      });
      gitDirtyCount = statusOut.trim() ? statusOut.trim().split(/\r?\n/).length : 0;
    } catch {
      // Not a git repo or git unavailable
    }

    let cliSha256 = '';
    try {
      cliSha256 = sha256Hex(readFileSync(fileURLToPath(import.meta.url))).slice(0, 12);
    } catch {
      // ignore
    }

    return {
      deviceName: this.deviceName,
      hostname: hostname(),
      platform: platform(),
      arch: arch(),
      cliVersion: PIPIBOT_CLI_VERSION,
      cliSha256,
      autoUpgradeEnabled: isAutoUpgradeEnabled(),
      uptimeSeconds: Math.floor(uptime()),
      cpuCount: cpus().length,
      totalMemoryMB: Math.round(totalmem() / (1024 * 1024)),
      freeMemoryMB: Math.round(freemem() / (1024 * 1024)),
      workspacePath: this.workspacePath,
      gitBranch,
      gitDirtyCount,
      installedAgents: this.detectedAgents,
      activeSessions: [...this.sessions.values()].filter((s) => s.status === 'running').length,
    };
  }

  // MARK: - Remote Headless Browser CDP Screencast (Gemini Spark / Mariner-style Live Viewport)

  private static detectChromeBinary(): string | null {
    const envPath = (process.env.PIPIBOT_CHROME_PATH ?? process.env.CHROME_PATH ?? '').trim();
    if (envPath && existsSync(envPath)) return envPath;

    const candidates =
      platform() === 'darwin'
        ? [
            '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
            '/Applications/Chromium.app/Contents/MacOS/Chromium',
            '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
            '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
          ]
        : [
            '/usr/bin/google-chrome',
            '/usr/bin/google-chrome-stable',
            '/usr/bin/chromium',
            '/usr/bin/chromium-browser',
            '/snap/bin/chromium',
            '/usr/bin/microsoft-edge',
          ];

    for (const p of candidates) {
      if (existsSync(p)) return p;
    }

    // Check PATH via `which`
    for (const bin of ['google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser']) {
      try {
        const resolved = execFileSync(platform() === 'win32' ? 'where' : 'which', [bin], {
          encoding: 'utf8',
          stdio: ['ignore', 'pipe', 'ignore'],
          timeout: 1500,
        })
          .trim()
          .split(/\r?\n/)[0];
        if (resolved && existsSync(resolved)) return resolved;
      } catch {
        // ignore
      }
    }

    // Check Playwright-installed Chromium cache
    const pwRoots = [
      join(homedir(), '.cache', 'ms-playwright'),
      join(homedir(), 'Library', 'Caches', 'ms-playwright'),
    ];
    for (const root of pwRoots) {
      if (!existsSync(root)) continue;
      try {
        const dirs = readdirSync(root).filter((d) => d.startsWith('chromium-')).sort().reverse();
        for (const d of dirs) {
          const bins = [
            join(root, d, 'chrome-linux', 'chrome'),
            join(root, d, 'chrome-mac', 'Chromium.app', 'Contents', 'MacOS', 'Chromium'),
            join(root, d, 'chrome-mac-arm64', 'Google Chrome for Testing.app', 'Contents', 'MacOS', 'Google Chrome for Testing'),
          ];
          for (const b of bins) {
            if (existsSync(b)) return b;
          }
        }
      } catch {
        // ignore
      }
    }
    return null;
  }

  private async fetchCdpTabs(port: number): Promise<RemoteBrowserTabInfo[]> {
    try {
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), 1500);
      const res = await fetch(`http://127.0.0.1:${port}/json/list`, { signal: ctrl.signal });
      clearTimeout(timer);
      if (!res.ok) return [];
      const arr = (await res.json()) as Array<Record<string, unknown>>;
      return arr
        .filter((t) => t.type === 'page' && typeof t.webSocketDebuggerUrl === 'string')
        .map((t) => ({
          id: String(t.id ?? ''),
          title: String(t.title ?? ''),
          url: String(t.url ?? ''),
          webSocketDebuggerUrl: String(t.webSocketDebuggerUrl ?? ''),
        }));
    } catch {
      return [];
    }
  }

  private sendCdp(method: string, params?: Record<string, unknown>): Promise<Record<string, unknown>> {
    const ws = this.browser.cdpWs;
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      return Promise.reject(new Error('browser_cdp_not_connected'));
    }
    this.browser.cdpSeq += 1;
    const id = this.browser.cdpSeq;
    return new Promise((resolvePromise, rejectPromise) => {
      const timer = setTimeout(() => {
        this.browser.cdpPending.delete(id);
        rejectPromise(new Error(`cdp_timeout:${method}`));
      }, 8000);
      this.browser.cdpPending.set(id, {
        resolve: (val) => {
          clearTimeout(timer);
          resolvePromise(val);
        },
        reject: (err) => {
          clearTimeout(timer);
          rejectPromise(err);
        },
      });
      ws.send(JSON.stringify({ id, method, params: params ?? {} }));
    });
  }

  private async connectCdpTarget(tab: RemoteBrowserTabInfo): Promise<void> {
    if (this.browser.cdpWs) {
      try {
        this.browser.cdpWs.close();
      } catch {
        // ignore
      }
      this.browser.cdpWs = undefined;
    }
    if (!tab.webSocketDebuggerUrl) throw new Error('missing_cdp_ws_url');

    await new Promise<void>((resolvePromise, rejectPromise) => {
      const cdpWs = new WebSocket(tab.webSocketDebuggerUrl!);
      const timer = setTimeout(() => {
        try {
          cdpWs.close();
        } catch {
          // ignore
        }
        rejectPromise(new Error('cdp_ws_connect_timeout'));
      }, 5000);

      cdpWs.addEventListener('open', () => {
        clearTimeout(timer);
        this.browser.cdpWs = cdpWs;
        this.browser.targetId = tab.id;
        this.browser.url = tab.url || this.browser.url;
        this.browser.title = tab.title || this.browser.title;
        resolvePromise();
      });

      cdpWs.addEventListener('error', () => {
        clearTimeout(timer);
        rejectPromise(new Error('cdp_ws_error'));
      });

      cdpWs.addEventListener('close', () => {
        if (this.browser.cdpWs === cdpWs) {
          this.browser.cdpWs = undefined;
          for (const p of this.browser.cdpPending.values()) {
            p.reject(new Error('cdp_closed'));
          }
          this.browser.cdpPending.clear();
        }
      });

      cdpWs.addEventListener('message', (ev) => {
        let msg: Record<string, unknown>;
        try {
          msg = JSON.parse(String(ev.data)) as Record<string, unknown>;
        } catch {
          return;
        }
        if (typeof msg.id === 'number' && this.browser.cdpPending.has(msg.id)) {
          const pending = this.browser.cdpPending.get(msg.id)!;
          this.browser.cdpPending.delete(msg.id);
          if (msg.error) {
            pending.reject(new Error(JSON.stringify(msg.error)));
          } else {
            pending.resolve((msg.result as Record<string, unknown>) ?? {});
          }
          return;
        }
        if (msg.method === 'Page.frameNavigated' && msg.params && typeof msg.params === 'object') {
          const frame = (msg.params as Record<string, unknown>).frame as Record<string, unknown> | undefined;
          if (frame && !frame.parentId && typeof frame.url === 'string') {
            this.browser.url = frame.url;
          }
          return;
        }
        if (msg.method === 'Page.screencastFrame' && msg.params && typeof msg.params === 'object') {
          const params = msg.params as { data?: string; sessionId?: number; metadata?: Record<string, unknown> };
          if (typeof params.sessionId === 'number') {
            void this.sendCdp('Page.screencastFrameAck', { sessionId: params.sessionId }).catch(() => {});
          }
          if (typeof params.data === 'string' && params.data.length > 0 && params.data.length < 440_000) {
            this.browser.lastFrame = params.data;
            const now = Date.now();
            if (now - this.browser.lastFrameAt >= 95) {
              this.browser.lastFrameAt = now;
              this.broadcastToSubscribers(this.browser.subscribers, {
                kind: 'browser_frame',
                data: params.data,
                url: this.browser.url,
                title: this.browser.title,
                width: this.browser.width,
                height: this.browser.height,
                ts: now,
              });
            }
          }
        }
      });
    });

    await this.sendCdp('Page.enable').catch(() => {});
    await this.sendCdp('Emulation.setDeviceMetricsOverride', {
      width: this.browser.width,
      height: this.browser.height,
      deviceScaleFactor: 1,
      mobile: false,
    }).catch(() => {});
    await this.sendCdp('Page.startScreencast', {
      format: 'jpeg',
      quality: 65,
      maxWidth: this.browser.width,
      maxHeight: this.browser.height,
      everyNthFrame: 1,
    }).catch(() => {});
  }

  private async launchOrAttachBrowser(opts: {
    url?: string;
    width?: number;
    height?: number;
    cdpPort?: number;
    attachOnly?: boolean;
    subscriberKey?: string;
  }): Promise<Record<string, unknown>> {
    if (opts.subscriberKey) this.browser.subscribers.add(opts.subscriberKey);
    const width = Math.max(480, Math.min(1920, Number(opts.width) || this.browser.width || 1280));
    const height = Math.max(360, Math.min(1200, Number(opts.height) || this.browser.height || 800));
    this.browser.width = width;
    this.browser.height = height;

    const requestedPort = Number(opts.cdpPort) || 0;
    const probePort = requestedPort || (this.browser.running ? this.browser.cdpPort : 9222);

    // 1. Try attaching to an already running CDP browser (e.g. started by agent/Playwright or existing session)
    let tabs = await this.fetchCdpTabs(probePort);
    if (tabs.length > 0) {
      this.browser.cdpPort = probePort;
      this.browser.running = true;
      if (!this.browser.proc) this.browser.attachedExternal = true;
      const targetTab = tabs.find((t) => t.id === this.browser.targetId) ?? tabs[0]!;
      await this.connectCdpTarget(targetTab);
      if (opts.url && opts.url.trim()) {
        const navUrl = /^https?:\/\//i.test(opts.url.trim()) ? opts.url.trim() : `https://${opts.url.trim()}`;
        await this.sendCdp('Page.navigate', { url: navUrl }).catch(() => {});
        this.browser.url = navUrl;
      }
      return {
        ok: true,
        running: true,
        attachedExternal: this.browser.attachedExternal,
        cdpPort: this.browser.cdpPort,
        url: this.browser.url,
        title: this.browser.title,
        width: this.browser.width,
        height: this.browser.height,
        tabs: tabs.map(({ id, title, url }) => ({ id, title, url })),
        lastFrame: this.browser.lastFrame,
      };
    }

    if (opts.attachOnly) {
      return {
        ok: false,
        error: `未在端口 ${probePort} 检测到已运行的 Chrome CDP 实例`,
        chromeAvailable: Boolean(PipiCliAgentRelayHost.detectChromeBinary()),
      };
    }

    // 2. Spawn a dedicated headless Chrome/Chromium instance with remote debugging
    const chromeBin = PipiCliAgentRelayHost.detectChromeBinary();
    if (!chromeBin) {
      return {
        ok: false,
        error: '当前节点未检测到 Chrome / Chromium（可安装 chromium 或设置 PIPIBOT_CHROME_PATH）',
        chromeAvailable: false,
      };
    }

    const spawnPort = requestedPort || 9333;
    const profileDir = join(tmpdir(), `pipibot-chrome-${spawnPort}`);
    mkdirSync(profileDir, { recursive: true });
    const startUrl = opts.url?.trim()
      ? (/^https?:\/\//i.test(opts.url.trim()) ? opts.url.trim() : `https://${opts.url.trim()}`)
      : 'about:blank';

    const chromeArgs = [
      '--headless=new',
      `--remote-debugging-port=${spawnPort}`,
      '--remote-debugging-address=127.0.0.1',
      `--window-size=${width},${height}`,
      `--user-data-dir=${profileDir}`,
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-gpu',
      '--disable-dev-shm-usage',
      ...(platform() === 'linux' ? ['--no-sandbox'] : []),
      startUrl,
    ];

    const proc = spawn(chromeBin, chromeArgs, {
      stdio: ['ignore', 'ignore', 'ignore'],
      detached: false,
    });
    this.browser.proc = proc;
    this.browser.attachedExternal = false;
    this.browser.cdpPort = spawnPort;
    proc.on('exit', () => {
      if (this.browser.proc === proc) {
        this.browser.proc = undefined;
        this.browser.running = false;
        this.browser.cdpWs = undefined;
      }
    });

    // Wait up to 6s for CDP HTTP endpoint to become ready
    const deadline = Date.now() + 6000;
    while (Date.now() < deadline) {
      tabs = await this.fetchCdpTabs(spawnPort);
      if (tabs.length > 0) break;
      await new Promise((r) => setTimeout(r, 200));
    }
    if (tabs.length === 0) {
      try {
        proc.kill('SIGTERM');
      } catch {
        // ignore
      }
      this.browser.proc = undefined;
      return { ok: false, error: '无头浏览器启动超时，请检查本机 Chromium 依赖' };
    }

    this.browser.running = true;
    await this.connectCdpTarget(tabs[0]!);
    return {
      ok: true,
      running: true,
      attachedExternal: false,
      cdpPort: spawnPort,
      url: this.browser.url,
      title: this.browser.title,
      width: this.browser.width,
      height: this.browser.height,
      tabs: tabs.map(({ id, title, url }) => ({ id, title, url })),
      lastFrame: this.browser.lastFrame,
    };
  }

  private async handleBrowserAction(body: Record<string, unknown>): Promise<Record<string, unknown>> {
    if (!this.browser.running || !this.browser.cdpWs) {
      return { ok: false, error: 'browser_not_running' };
    }
    const type = String(body.type ?? '').toLowerCase();
    try {
      if (type === 'navigate') {
        const rawUrl = String(body.url ?? '').trim();
        if (!rawUrl) return { ok: false, error: 'empty_url' };
        const url = /^[a-zA-Z]+:\/\//.test(rawUrl) ? rawUrl : `https://${rawUrl}`;
        await this.sendCdp('Page.navigate', { url });
        this.browser.url = url;
        return { ok: true, url };
      }
      if (type === 'click') {
        const x = Math.round(Number(body.x) || 0);
        const y = Math.round(Number(body.y) || 0);
        await this.sendCdp('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y });
        await this.sendCdp('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
        await this.sendCdp('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
        return { ok: true };
      }
      if (type === 'wheel') {
        const x = Math.round(Number(body.x) || this.browser.width / 2);
        const y = Math.round(Number(body.y) || this.browser.height / 2);
        const deltaX = Math.round(Number(body.deltaX) || 0);
        const deltaY = Math.round(Number(body.deltaY) || 240);
        await this.sendCdp('Input.dispatchMouseEvent', { type: 'mouseWheel', x, y, deltaX, deltaY });
        return { ok: true };
      }
      if (type === 'type') {
        const text = String(body.text ?? '');
        if (text) await this.sendCdp('Input.insertText', { text });
        return { ok: true };
      }
      if (type === 'key') {
        const key = String(body.key ?? 'Enter');
        const keyMap: Record<string, { code: string; windowsVirtualKeyCode: number; text?: string }> = {
          Enter: { code: 'Enter', windowsVirtualKeyCode: 13, text: '\r' },
          Backspace: { code: 'Backspace', windowsVirtualKeyCode: 8 },
          Tab: { code: 'Tab', windowsVirtualKeyCode: 9 },
          Escape: { code: 'Escape', windowsVirtualKeyCode: 27 },
          ArrowUp: { code: 'ArrowUp', windowsVirtualKeyCode: 38 },
          ArrowDown: { code: 'ArrowDown', windowsVirtualKeyCode: 40 },
          ArrowLeft: { code: 'ArrowLeft', windowsVirtualKeyCode: 37 },
          ArrowRight: { code: 'ArrowRight', windowsVirtualKeyCode: 39 },
        };
        const mapped = keyMap[key] ?? { code: key, windowsVirtualKeyCode: 0, text: key.length === 1 ? key : undefined };
        await this.sendCdp('Input.dispatchKeyEvent', {
          type: 'keyDown',
          key,
          code: mapped.code,
          windowsVirtualKeyCode: mapped.windowsVirtualKeyCode,
          text: mapped.text,
        });
        await this.sendCdp('Input.dispatchKeyEvent', {
          type: 'keyUp',
          key,
          code: mapped.code,
          windowsVirtualKeyCode: mapped.windowsVirtualKeyCode,
        });
        return { ok: true };
      }
      if (type === 'reload') {
        await this.sendCdp('Page.reload', { ignoreCache: false });
        return { ok: true };
      }
      if (type === 'back' || type === 'forward') {
        const hist = (await this.sendCdp('Page.getNavigationHistory')) as {
          currentIndex?: number;
          entries?: Array<{ id: number }>;
        };
        const cur = hist.currentIndex ?? 0;
        const nextIdx = type === 'back' ? cur - 1 : cur + 1;
        const entry = hist.entries?.[nextIdx];
        if (entry) {
          await this.sendCdp('Page.navigateToHistoryEntry', { entryId: entry.id });
        }
        return { ok: true };
      }
      if (type === 'click-ref') {
        const ref = String(body.ref ?? '').replace(/"/g, '');
        if (!ref) return { ok: false, error: 'missing_ref' };
        const evalRes = (await this.sendCdp('Runtime.evaluate', {
          expression: `(() => {
            const el = (window.__pipiRefs || {})["${ref}"];
            if (!el || !el.isConnected) return null;
            el.scrollIntoView({ block: 'center', inline: 'center', behavior: 'instant' });
            const r = el.getBoundingClientRect();
            if (r.width <= 0 || r.height <= 0) return null;
            return JSON.stringify({ x: r.left + r.width / 2, y: r.top + r.height / 2 });
          })()`,
          returnByValue: true,
        })) as { result?: { value?: string } };
        const raw = evalRes.result?.value;
        if (!raw) return { ok: false, error: `element_not_found:${ref}` };
        const coords = JSON.parse(raw) as { x: number; y: number };
        await this.sendCdp('Input.dispatchMouseEvent', { type: 'mouseMoved', x: coords.x, y: coords.y });
        await this.sendCdp('Input.dispatchMouseEvent', { type: 'mousePressed', x: coords.x, y: coords.y, button: 'left', clickCount: 1 });
        await this.sendCdp('Input.dispatchMouseEvent', { type: 'mouseReleased', x: coords.x, y: coords.y, button: 'left', clickCount: 1 });
        return { ok: true, ref, x: coords.x, y: coords.y };
      }
      if (type === 'switch-tab') {
        const targetId = String(body.targetId ?? '');
        const tabs = await this.fetchCdpTabs(this.browser.cdpPort);
        const foundTab = tabs.find((t) => t.id === targetId);
        if (!foundTab) return { ok: false, error: 'tab_not_found' };
        await this.connectCdpTarget(foundTab);
        return { ok: true, url: this.browser.url, title: this.browser.title };
      }
      return { ok: false, error: 'unknown_browser_action' };
    } catch (err) {
      return { ok: false, error: err instanceof Error ? err.message : 'browser_action_failed' };
    }
  }

  private async captureBrowserSnapshot(includeScreenshot = true): Promise<Record<string, unknown>> {
    if (!this.browser.running || !this.browser.cdpWs) {
      return { ok: false, error: 'browser_not_running' };
    }
    try {
      const domScript = `(() => {
        window.__pipiRefs = {};
        const vw = window.innerWidth || 1280;
        const vh = window.innerHeight || 800;
        const nodes = Array.from(document.querySelectorAll('a, button, input, textarea, select, [role="button"], [role="link"], [role="tab"], [role="menuitem"], summary'));
        const elements = [];
        let idx = 0;
        for (const el of nodes) {
          if (elements.length >= 45) break;
          const style = window.getComputedStyle(el);
          if (!style || style.display === 'none' || style.visibility === 'hidden' || parseFloat(style.opacity || '1') === 0) continue;
          const r = el.getBoundingClientRect();
          if (r.width < 6 || r.height < 6) continue;
          if (r.bottom < -120 || r.top > vh + 240 || r.right < 0 || r.left > vw) continue;
          const tag = (el.tagName || '').toLowerCase();
          const role = el.getAttribute('role') || (tag === 'a' ? 'link' : tag);
          const label = (el.getAttribute('aria-label') || el.innerText || el.getAttribute('placeholder') || el.getAttribute('title') || el.value || '').replace(/\\s+/g, ' ').trim();
          const href = tag === 'a' ? (el.getAttribute('href') || '') : '';
          if (!label && !href && tag !== 'input' && tag !== 'textarea') continue;
          idx += 1;
          const ref = 'e' + idx;
          window.__pipiRefs[ref] = el;
          elements.push({ ref, tag, role, label: label.slice(0, 96), href: href ? href.slice(0, 140) : null, inputType: tag === 'input' ? (el.getAttribute('type') || 'text') : null, x: Math.round(r.left + r.width / 2), y: Math.round(r.top + r.height / 2), width: Math.round(r.width), height: Math.round(r.height) });
        }
        const mainRoot = document.querySelector('main, article, [role="main"]') || document.body;
        const rawText = (mainRoot && mainRoot.innerText ? mainRoot.innerText : (document.body ? document.body.innerText : '')) || '';
        const visibleText = rawText.replace(/\\r/g, '').replace(/[ \\t]+/g, ' ').replace(/\\n{3,}/g, '\\n\\n').trim().slice(0, 6800);
        return JSON.stringify({ url: location.href, title: document.title || '', scrollY: Math.round(window.scrollY || 0), scrollHeight: Math.round(document.documentElement ? document.documentElement.scrollHeight : 0), viewportHeight: Math.round(vh), visibleText, elements });
      })()`;
      const evalRes = (await this.sendCdp('Runtime.evaluate', {
        expression: domScript,
        returnByValue: true,
      })) as { result?: { value?: string } };
      const parsed = evalRes.result?.value ? (JSON.parse(evalRes.result.value) as Record<string, unknown>) : {};
      let screenshotBase64: string | undefined;
      if (includeScreenshot) {
        const shot = (await this.sendCdp('Page.captureScreenshot', { format: 'jpeg', quality: 70, fromSurface: true }).catch(() => null)) as { data?: string } | null;
        if (shot?.data) screenshotBase64 = shot.data;
      }
      return { ok: true, ...parsed, screenshotBase64 };
    } catch (err) {
      return { ok: false, error: err instanceof Error ? err.message : 'browser_snapshot_failed' };
    }
  }

  private stopBrowser(): void {
    if (this.browser.cdpWs) {
      try {
        void this.sendCdp('Page.stopScreencast').catch(() => {});
        this.browser.cdpWs.close();
      } catch {
        // ignore
      }
      this.browser.cdpWs = undefined;
    }
    if (this.browser.proc && !this.browser.attachedExternal) {
      try {
        this.browser.proc.kill('SIGTERM');
      } catch {
        // ignore
      }
      this.browser.proc = undefined;
    }
    this.browser.running = false;
    this.browser.attachedExternal = false;
    this.browser.lastFrame = '';
  }

  private async handleRpc(
    clientId: string,
    sid: string,
    req: { id?: string; method?: string; path?: string; token?: string; body?: Record<string, unknown> },
  ): Promise<Record<string, unknown>> {
    const method = (req.method ?? 'GET').toUpperCase();
    const path = req.path ?? '/';
    const body = req.body ?? {};
    const subKey = `${clientId}:${sid}`;

    // Privileged endpoints require same-account token verification
    const requiresAuth =
      path === '/api/shell/exec' ||
      path === '/api/agents/run' ||
      path === '/api/v1/mobile/chat' ||
      path === '/api/files/read' ||
      path === '/api/files/list' ||
      path.startsWith('/api/browser/') ||
      path.includes('/attach') ||
      path.includes('/input') ||
      path.includes('/stop') ||
      path.includes('/takeover');

    if (requiresAuth) {
      const authorized = await this.verifyPeerToken(req.token);
      if (!authorized) {
        return { status: 401, body: { error: 'unauthorized_same_account_required' } };
      }
    }

    // WebUI Companion `/api/v1/mobile/snapshot` compatibility for Linux/CLI nodes
    if (path === '/api/v1/mobile/snapshot' && method === 'GET') {
      const bots = this.detectedAgents.map((a) => ({
        id: a.id,
        name: a.name,
        role: `纯外接 CLI Harness · ${a.defaultModel}`,
        kind: 'harness',
        defaultModel: a.defaultModel,
        models: a.models,
        configSource: a.configSource,
        supportedModes: a.supportedModes,
      }));
      return {
        status: 200,
        body: {
          hostName: this.deviceName,
          platform: platform(),
          workspacePath: this.workspacePath,
          bots,
          harnesses: this.detectedAgents,
          messages: this.chatMessages.slice(-80),
          approvals: [],
          draftGates: [],
          evolutions: [],
          worktrees: [],
          triggers: [],
          sentinelIssues: [],
          usageSummary: { todayCostUSD: 0 },
          sessions: [...this.sessions.values()].map((s) => PipiCliAgentRelayHost.serializeSession(s)),
          browser: {
            running: this.browser.running,
            url: this.browser.url,
            title: this.browser.title,
            cdpPort: this.browser.cdpPort,
            chromeAvailable: Boolean(PipiCliAgentRelayHost.detectChromeBinary()),
          },
        },
      };
    }

    if (path === '/api/v1/mobile/chat' && method === 'POST') {
      const text = String(body.text ?? '').trim();
      if (!text) return { status: 400, body: { error: 'empty_text' } };
      const harnessId = String(body.botId ?? body.agent ?? this.detectedAgents[0]?.id ?? 'claude-code');
      const model = typeof body.model === 'string' ? body.model : undefined;
      const mode = typeof body.mode === 'string' ? body.mode : 'acp';
      this.chatMessages.push({
        id: `m_${randomUUID().slice(0, 8)}`,
        role: 'user',
        content: text,
        createdAt: new Date().toISOString(),
      });
      const sess = this.startAgentSession(harnessId, text, clientId, undefined, model, mode, subKey);
      const replyMsg = {
        id: `m_${randomUUID().slice(0, 8)}`,
        role: 'assistant' as const,
        author: sess.agent,
        content: `⏳ 正在 ${this.deviceName} 上通过 ${sess.agent} 执行…`,
        createdAt: new Date().toISOString(),
      };
      this.chatMessages.push(replyMsg);
      const syncOutput = () => {
        const bodyLines = sess.outputLines.slice(1);
        replyMsg.content = bodyLines.length
          ? bodyLines.join('\n')
          : (sess.status === 'running' ? `⏳ 正在 ${this.deviceName} 上通过 ${sess.agent} 执行…` : '（执行完成，无输出）');
      };
      if (sess.proc) {
        sess.proc.stdout?.on('data', syncOutput);
        sess.proc.stderr?.on('data', syncOutput);
        sess.proc.on('exit', syncOutput);
      } else {
        syncOutput();
      }
      return { status: 200, body: { ok: true, sessionId: sess.id, session: PipiCliAgentRelayHost.serializeSession(sess) } };
    }

    // Remote Headless Browser CDP endpoints
    if (path === '/api/browser/status' && method === 'GET') {
      const tabs = this.browser.running ? await this.fetchCdpTabs(this.browser.cdpPort) : [];
      return {
        status: 200,
        body: {
          ok: true,
          running: this.browser.running,
          attachedExternal: this.browser.attachedExternal,
          cdpPort: this.browser.cdpPort,
          url: this.browser.url,
          title: this.browser.title,
          width: this.browser.width,
          height: this.browser.height,
          chromeAvailable: Boolean(PipiCliAgentRelayHost.detectChromeBinary()),
          tabs: tabs.map(({ id, title, url }) => ({ id, title, url })),
        },
      };
    }

    if (path === '/api/browser/attach' && method === 'POST') {
      this.browser.subscribers.add(subKey);
      const tabs = this.browser.running ? await this.fetchCdpTabs(this.browser.cdpPort) : [];
      return {
        status: 200,
        body: {
          ok: true,
          running: this.browser.running,
          attachedExternal: this.browser.attachedExternal,
          cdpPort: this.browser.cdpPort,
          url: this.browser.url,
          title: this.browser.title,
          width: this.browser.width,
          height: this.browser.height,
          chromeAvailable: Boolean(PipiCliAgentRelayHost.detectChromeBinary()),
          tabs: tabs.map(({ id, title, url }) => ({ id, title, url })),
          lastFrame: this.browser.lastFrame,
        },
      };
    }

    if (path === '/api/browser/launch' && method === 'POST') {
      const res = await this.launchOrAttachBrowser({
        url: typeof body.url === 'string' ? body.url : undefined,
        width: typeof body.width === 'number' ? body.width : undefined,
        height: typeof body.height === 'number' ? body.height : undefined,
        cdpPort: typeof body.cdpPort === 'number' ? body.cdpPort : undefined,
        attachOnly: Boolean(body.attachOnly),
        subscriberKey: subKey,
      });
      return { status: res.ok ? 200 : 400, body: res };
    }

    if (path === '/api/browser/navigate' && method === 'POST') {
      const res = await this.handleBrowserAction({ type: 'navigate', url: body.url });
      return { status: res.ok ? 200 : 400, body: res };
    }

    if (path === '/api/browser/action' && method === 'POST') {
      const res = await this.handleBrowserAction(body);
      return { status: res.ok ? 200 : 400, body: res };
    }

    if (path === '/api/browser/snapshot' && (method === 'GET' || method === 'POST')) {
      const includeScreenshot = body.includeScreenshot !== false;
      const res = await this.captureBrowserSnapshot(includeScreenshot);
      return { status: res.ok ? 200 : 400, body: res };
    }

    if (path === '/api/browser/stop' && method === 'POST') {
      this.stopBrowser();
      return { status: 200, body: { ok: true } };
    }

    if (path === '/api/system/info' && method === 'GET') {
      const info = await this.collectSystemInfo();
      return { status: 200, body: info };
    }

    if (path === '/api/system/upgrade' && method === 'POST') {
      const force = Boolean(body.force);
      const dryRun = Boolean(body.checkOnly);
      const res = await checkAndUpgradeCli({
        relayOrigin: this.auth.relayOrigin,
        force,
        dryRun,
        restartDaemon: false,
      });
      if (res.updated && !dryRun) {
        this.scheduleGracefulRestartForUpgrade();
      }
      return {
        status: res.ok ? 200 : 500,
        body: {
          ...res,
          restartScheduled: res.updated && !dryRun,
        },
      };
    }

    if (path === '/api/shell/exec' && method === 'POST') {
      const command = String(body.command ?? '').trim();
      if (!command) return { status: 400, body: { error: 'empty_command' } };
      const result = await this.runShellExec(
        command,
        typeof body.cwd === 'string' ? body.cwd : undefined,
        typeof body.timeoutMs === 'number' ? body.timeoutMs : undefined,
      );
      return { status: 200, body: result };
    }

    if (path === '/api/files/list' && (method === 'GET' || method === 'POST')) {
      const targetDir = this.resolveTargetPath(typeof body.path === 'string' ? body.path : undefined);
      try {
        const entries = readdirSync(targetDir, { withFileTypes: true })
          .slice(0, 120)
          .map((e) => {
            let size = 0;
            try {
              if (e.isFile()) size = statSync(join(targetDir, e.name)).size;
            } catch {
              // ignore
            }
            return { name: e.name, isDirectory: e.isDirectory(), size };
          });
        return { status: 200, body: { path: targetDir, entries } };
      } catch (err) {
        return { status: 400, body: { error: err instanceof Error ? err.message : 'list_failed' } };
      }
    }

    if (path === '/api/files/read' && method === 'POST') {
      const filePath = this.resolveTargetPath(typeof body.path === 'string' ? body.path : '');
      const maxBytes = Math.max(512, Math.min(64 * 1024, Number(body.maxBytes) || 24 * 1024));
      try {
        const content = readFileSync(filePath, 'utf8').slice(0, maxBytes);
        return { status: 200, body: { path: filePath, content } };
      } catch (err) {
        return { status: 400, body: { error: err instanceof Error ? err.message : 'read_failed' } };
      }
    }

    if (path === '/api/agents' && method === 'GET') {
      return {
        status: 200,
        body: {
          deviceName: this.deviceName,
          workspacePath: this.workspacePath,
          installedAgents: this.detectedAgents,
          sessions: [...this.sessions.values()].map((s) => PipiCliAgentRelayHost.serializeSession(s)),
        },
      };
    }

    const singleSessionMatch = /^\/api\/agents\/([a-zA-Z0-9_-]+)$/.exec(path);
    if (singleSessionMatch && method === 'GET') {
      const sess = this.sessions.get(singleSessionMatch[1]!);
      if (!sess) return { status: 404, body: { error: 'session_not_found' } };
      return { status: 200, body: { ok: true, session: PipiCliAgentRelayHost.serializeSession(sess) } };
    }

    if (path === '/api/agents/run' && method === 'POST') {
      const agent = String(body.agent ?? this.detectedAgents[0]?.id ?? 'shell');
      const mode = typeof body.mode === 'string' ? body.mode : (agent === 'shell' ? 'tui' : 'tui');
      const model = typeof body.model === 'string' ? body.model : undefined;
      const prompt = String(body.prompt ?? '').trim();
      if (!prompt && mode !== 'tui' && agent !== 'shell') {
        return { status: 400, body: { error: 'empty_prompt' } };
      }
      const sess = this.startAgentSession(
        agent,
        prompt,
        clientId,
        typeof body.cwd === 'string' ? body.cwd : undefined,
        model,
        mode,
        subKey,
      );
      const waitMs = Math.max(0, Math.min(25_000, Number(body.waitMs) || 0));
      if (waitMs > 0 && sess.status === 'running') {
        const deadline = Date.now() + waitMs;
        while (sess.status === 'running' && Date.now() < deadline) {
          await new Promise((r) => setTimeout(r, 250));
        }
      }
      return {
        status: 200,
        body: {
          ok: true,
          session: PipiCliAgentRelayHost.serializeSession(sess),
          rawBuffer: sess.rawBuffer,
          streamSeq: sess.streamSeq,
        },
      };
    }

    const attachMatch = /^\/api\/agents\/([a-zA-Z0-9_-]+)\/attach$/.exec(path);
    if (attachMatch && method === 'POST') {
      const sess = this.sessions.get(attachMatch[1]!);
      if (!sess) return { status: 404, body: { error: 'session_not_found' } };
      sess.subscribers.add(subKey);
      return {
        status: 200,
        body: {
          ok: true,
          session: PipiCliAgentRelayHost.serializeSession(sess),
          rawBuffer: sess.rawBuffer,
          streamSeq: sess.streamSeq,
        },
      };
    }

    const detachMatch = /^\/api\/agents\/([a-zA-Z0-9_-]+)\/detach$/.exec(path);
    if (detachMatch && method === 'POST') {
      const sess = this.sessions.get(detachMatch[1]!);
      if (sess) sess.subscribers.delete(subKey);
      return { status: 200, body: { ok: true } };
    }

    const takeoverMatch = /^\/api\/agents\/([a-zA-Z0-9_-]+)\/takeover$/.exec(path);
    if (takeoverMatch && method === 'POST') {
      const sess = this.sessions.get(takeoverMatch[1]!);
      if (!sess) return { status: 404, body: { error: 'session_not_found' } };
      const previousOwner = sess.ownerClientId;
      sess.ownerClientId = clientId;
      sess.subscribers.add(subKey);
      return { status: 200, body: { ok: true, sessionId: sess.id, previousOwner, ownerClientId: clientId } };
    }

    const inputMatch = /^\/api\/agents\/([a-zA-Z0-9_-]+)\/input$/.exec(path);
    if (inputMatch && method === 'POST') {
      const sess = this.sessions.get(inputMatch[1]!);
      if (!sess) return { status: 404, body: { error: 'session_not_found' } };
      if (sess.ownerClientId && sess.ownerClientId !== clientId && !body.forceTakeover) {
        return { status: 409, body: { error: 'owned_by_another_client', ownerClientId: sess.ownerClientId } };
      }
      sess.ownerClientId = clientId;
      sess.subscribers.add(subKey);
      if (sess.proc?.stdin?.writable) {
        if (typeof body.raw === 'string') {
          sess.proc.stdin.write(body.raw);
          return { status: 200, body: { ok: true } };
        }
        const text = String(body.text ?? '');
        const eol = sess.mode === 'tui' ? '\r' : '\n';
        sess.proc.stdin.write(`${text}${eol}`);
        if (text) sess.outputLines.push(`> ${text}`);
        return { status: 200, body: { ok: true } };
      }
      return { status: 400, body: { error: 'session_not_running' } };
    }

    const stopMatch = /^\/api\/agents\/([a-zA-Z0-9_-]+)\/stop$/.exec(path);
    if (stopMatch && method === 'POST') {
      const sess = this.sessions.get(stopMatch[1]!);
      if (!sess) return { status: 404, body: { error: 'session_not_found' } };
      sess.proc?.kill('SIGTERM');
      sess.status = 'exited';
      return { status: 200, body: { ok: true } };
    }

    // Default snapshot compatible with PiPiBot mobile PWA `/api/state`
    return {
      status: 200,
      body: {
        hostName: this.deviceName,
        platform: platform(),
        workspacePath: this.workspacePath,
        installedAgents: this.detectedAgents,
        sessions: [...this.sessions.values()].map((s) => PipiCliAgentRelayHost.serializeSession(s)),
      },
    };
  }

  async start(): Promise<void> {
    const wsUrl = this.auth.relayOrigin.replace(/^http/, 'ws') + '/ws';
    const plat = platform() === 'darwin' ? 'macos' : platform() === 'win32' ? 'windows' : 'linux';

    console.log(`\n🚀 PiPiBot CLI 远程主机已启动（Herdr 模式）`);
    console.log(`   设备名称：${this.deviceName} (${plat})`);
    console.log(`   工作目录：${this.workspacePath}`);
    console.log(`   已检测 Agent：${this.detectedAgents.map((a) => a.name).join(' · ') || '无（可安装 claude / codex / opencode）'}`);
    console.log(`   手机 / 网页访问：${this.auth.relayOrigin}/login\n`);

    const connect = () => {
      if (this.stopped) return;
      const ws = new WebSocket(wsUrl);
      this.ws = ws;

      ws.addEventListener('open', () => {
        ws.send(
          JSON.stringify({
            type: 'host_register',
            hostId: this.auth.hostId,
            accessToken: this.auth.accessToken,
            deviceName: this.deviceName,
            platform: plat,
            hostPubKey: this.auth.hostPublicKeyB64Url,
            capabilities: this.detectedAgents.map((a) => a.name),
            workspacePath: this.workspacePath,
          }),
        );
        console.log(`[pipibot-up] 🟢 已加密连接至 ${this.auth.relayOrigin} (hostId=${this.auth.hostId})`);
      });

      ws.addEventListener('message', async (event) => {
        try {
          const msg = JSON.parse(String(event.data)) as Record<string, unknown>;
          if (msg.type === 'client_status' && msg.online === false && typeof msg.clientId === 'string') {
            const prefix = `${msg.clientId}:`;
            for (const key of [...this.clientKeys.keys()]) {
              if (key.startsWith(prefix)) this.clientKeys.delete(key);
            }
            for (const s of this.sessions.values()) {
              for (const sub of [...s.subscribers]) {
                if (sub.startsWith(prefix)) s.subscribers.delete(sub);
              }
            }
            for (const sub of [...this.browser.subscribers]) {
              if (sub.startsWith(prefix)) this.browser.subscribers.delete(sub);
            }
            return;
          }
          if (msg.type === 'envelope') {
            const opened = this.openEnvelope(msg as Parameters<PipiCliAgentRelayHost['openEnvelope']>[0]);
            if (opened) {
              const clientId = String(msg.clientId ?? '');
              const sid = String(msg.sid ?? '');
              const response = await this.handleRpc(
                clientId,
                sid,
                opened.plaintext as { id?: string; reqId?: string; method?: string; path?: string; token?: string; body?: Record<string, unknown> },
              );
              const reqId = opened.plaintext.reqId ?? opened.plaintext.id;
              this.sendEncryptedResponse(clientId, sid, {
                kind: 'http_res',
                id: reqId,
                reqId,
                ...response,
              });
            }
          }
        } catch {
          // Ignore malformed frame
        }
      });

      ws.addEventListener('close', () => {
        if (!this.stopped) {
          console.log('[pipibot-up] 连接断开，3 秒后自动重连...');
          setTimeout(connect, 3000);
        }
      });

      ws.addEventListener('error', () => {
        // Handled by close reconnect
      });
    };

    connect();
    this.startAutoUpgradeLoop();
  }

  private hasActiveRunningSessions(): boolean {
    return [...this.sessions.values()].some((s) => s.status === 'running');
  }

  private scheduleGracefulRestartForUpgrade(): void {
    this.pendingUpgradeRestart = true;
    const attemptRestart = () => {
      if (this.stopped) return;
      if (this.hasActiveRunningSessions()) {
        setTimeout(attemptRestart, 5_000);
        return;
      }
      const scriptPath = fileURLToPath(import.meta.url);
      console.log('[pipibot-upgrade] 🔄 正在无缝热重启至新版 CLI...');
      const scope = detectSystemdServiceScope();
      if (scope) {
        // Under systemd (Restart=always), exiting cleanly brings up the upgraded bundle immediately
        this.stop();
        process.exit(0);
      }
      // Detached non-systemd daemon: spawn upgraded replacement process before exiting
      try {
        mkdirSync(dirname(daemonLogPath()), { recursive: true });
        const logFd = openSync(daemonLogPath(), 'a');
        const child = spawn(
          process.execPath,
          ['--dns-result-order=ipv4first', '--experimental-strip-types', '--no-warnings', scriptPath, 'up', '--workspace', this.workspacePath, '--name', this.deviceName],
          {
            cwd: this.workspacePath,
            detached: true,
            stdio: ['ignore', logFd, logFd],
            env: { ...process.env, NODE_USE_ENV_PROXY: '1' },
          },
        );
        child.unref();
        if (child.pid) {
          writeFileSync(daemonPidPath(), `${child.pid}\n`, 'utf8');
        }
      } catch (err) {
        console.error('[pipibot-upgrade] 热重启失败：', err instanceof Error ? err.message : String(err));
        return;
      }
      this.stop();
      process.exit(0);
    };
    setTimeout(attemptRestart, 800);
  }

  private startAutoUpgradeLoop(): void {
    if (!isAutoUpgradeEnabled()) return;
    const scriptPath = fileURLToPath(import.meta.url);
    if (isInsideGitSourceCheckout(scriptPath)) return;

    const runCheck = async () => {
      if (this.stopped || this.pendingUpgradeRestart) return;
      try {
        const res = await checkAndUpgradeCli({
          relayOrigin: this.auth.relayOrigin,
          scriptPath,
          force: false,
          dryRun: false,
          restartDaemon: false,
        });
        if (res.updated) {
          console.log(`[pipibot-upgrade] ⬆️ 已自动下载并校验新版 CLI v${res.latestVersion} (${res.localSha256.slice(0, 8)})`);
          this.scheduleGracefulRestartForUpgrade();
        }
      } catch {
        // Silent retry on next interval
      }
    };

    const intervalMs = Math.max(60_000, Number(process.env.PIPIBOT_AUTO_UPGRADE_INTERVAL_MS) || 6 * 60 * 60 * 1000);
    this.autoUpgradeStartupTimer = setTimeout(() => { void runCheck(); }, 45_000);
    this.autoUpgradeStartupTimer.unref?.();
    this.autoUpgradeIntervalTimer = setInterval(() => { void runCheck(); }, intervalMs);
    this.autoUpgradeIntervalTimer.unref?.();
  }

  stop(): void {
    this.stopped = true;
    if (this.autoUpgradeStartupTimer) {
      clearTimeout(this.autoUpgradeStartupTimer);
      this.autoUpgradeStartupTimer = null;
    }
    if (this.autoUpgradeIntervalTimer) {
      clearInterval(this.autoUpgradeIntervalTimer);
      this.autoUpgradeIntervalTimer = null;
    }
    this.ws?.close();
    this.stopBrowser();
    for (const s of this.sessions.values()) {
      if (s.flushTimer) clearTimeout(s.flushTimer);
      s.proc?.kill('SIGTERM');
    }
  }
}

// MARK: - Standalone Zero-Dependency CLI Entrypoint (`pipibot login` / `pipibot up [-d]` / `pipibot down` / `pipibot status` / `pipibot devices` / `pipibot agents`)

function daemonPidPath(): string {
  return join(homedir(), '.pipibot', 'daemon.pid');
}

function daemonLogPath(): string {
  return join(homedir(), '.pipibot', 'daemon.log');
}

const SYSTEMD_SERVICE_NAME = 'pipibot-node.service';

function hasSystemd(): boolean {
  if (platform() !== 'linux' || !existsSync('/run/systemd/system')) return false;
  try {
    execFileSync('systemctl', ['--version'], { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

function isRootUser(): boolean {
  return typeof process.getuid === 'function' && process.getuid() === 0;
}

function buildSystemdUnit(execBin: string, scriptPath: string, workspaceDir: string, extraArgs: string[]): string {
  const envLines: string[] = [
    `Environment=HOME=${homedir()}`,
    `Environment=NODE_USE_ENV_PROXY=1`,
    `Environment=PATH=${process.env.PATH || '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'}`,
  ];
  for (const key of ['HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY', 'http_proxy', 'https_proxy', 'all_proxy', 'no_proxy', 'PIPIBOT_RELAY_ORIGIN']) {
    const val = process.env[key];
    if (val) {
      envLines.push(`Environment=${key}=${val}`);
    }
  }
  const argStr = extraArgs.map((a) => JSON.stringify(a)).join(' ');
  const execCmd = `${execBin} --dns-result-order=ipv4first --experimental-strip-types --no-warnings ${JSON.stringify(scriptPath)} up --workspace ${JSON.stringify(workspaceDir)}${argStr ? ' ' + argStr : ''}`;
  return `[Unit]
Description=PiPiBot Remote Agent Node (E2EE Relay Daemon)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${workspaceDir}
${envLines.join('\n')}
ExecStart=${execCmd}
Restart=always
RestartSec=3
KillSignal=SIGTERM
TimeoutStopSec=10

[Install]
WantedBy=${isRootUser() ? 'multi-user.target' : 'default.target'}
`;
}

function tryInstallAndStartSystemd(scriptPath: string, workspaceDir: string, extraArgs: string[]): { ok: boolean; scope?: 'system' | 'user'; unitPath?: string; error?: string } {
  if (!hasSystemd()) return { ok: false };
  const unitContent = buildSystemdUnit(process.execPath, scriptPath, workspaceDir, extraArgs);
  if (isRootUser()) {
    const unitPath = `/etc/systemd/system/${SYSTEMD_SERVICE_NAME}`;
    try {
      writeFileSync(unitPath, unitContent, 'utf8');
      execFileSync('systemctl', ['daemon-reload'], { stdio: 'ignore' });
      execFileSync('systemctl', ['enable', '--now', SYSTEMD_SERVICE_NAME], { stdio: 'ignore' });
      return { ok: true, scope: 'system', unitPath };
    } catch (err) {
      return { ok: false, error: err instanceof Error ? err.message : String(err) };
    }
  }
  // Non-root user: attempt systemd --user
  try {
    const userUnitDir = join(homedir(), '.config', 'systemd', 'user');
    const unitPath = join(userUnitDir, SYSTEMD_SERVICE_NAME);
    mkdirSync(userUnitDir, { recursive: true });
    writeFileSync(unitPath, unitContent, 'utf8');
    execFileSync('systemctl', ['--user', 'daemon-reload'], { stdio: 'ignore' });
    execFileSync('systemctl', ['--user', 'enable', '--now', SYSTEMD_SERVICE_NAME], { stdio: 'ignore' });
    return { ok: true, scope: 'user', unitPath };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : String(err) };
  }
}

function detectSystemdServiceScope(): 'system' | 'user' | null {
  if (!hasSystemd()) return null;
  if (existsSync(`/etc/systemd/system/${SYSTEMD_SERVICE_NAME}`)) return 'system';
  if (existsSync(join(homedir(), '.config', 'systemd', 'user', SYSTEMD_SERVICE_NAME))) return 'user';
  return null;
}

function readRunningDaemonPid(): number | null {
  const pidFile = daemonPidPath();
  if (!existsSync(pidFile)) return null;
  try {
    const pid = Number(readFileSync(pidFile, 'utf8').trim());
    if (!Number.isInteger(pid) || pid <= 0) return null;
    process.kill(pid, 0);
    return pid;
  } catch {
    return null;
  }
}

async function runStandaloneCli(argv: string[]): Promise<void> {
  const [cmd = 'help', ...rest] = argv;
  const flag = (name: string): string | undefined => {
    const idx = rest.indexOf(name);
    return idx >= 0 && idx + 1 < rest.length ? rest[idx + 1] : undefined;
  };
  const hasFlag = (name: string): boolean => rest.includes(name);
  const relayOrigin = flag('--relay') ?? process.env.PIPIBOT_RELAY_ORIGIN ?? DEFAULT_RELAY_ORIGIN;

  if (cmd === 'version' || cmd === '--version' || cmd === '-v') {
    let shortSha = '';
    try {
      shortSha = sha256Hex(readFileSync(fileURLToPath(import.meta.url))).slice(0, 8);
    } catch {
      // ignore
    }
    console.log(`PiPiBot Node CLI v${PIPIBOT_CLI_VERSION}${shortSha ? ` (${shortSha})` : ''} · autoUpgrade=${isAutoUpgradeEnabled() ? 'on' : 'off'}`);
    return;
  }
  if (cmd === 'upgrade' || cmd === 'update') {
    const checkOnly = hasFlag('--check');
    const force = hasFlag('--force');
    console.log(`🔍 正在向 ${relayOrigin} 检查 PiPiBot CLI 更新...`);
    const res = await checkAndUpgradeCli({
      relayOrigin,
      force,
      dryRun: checkOnly,
      restartDaemon: !checkOnly,
    });
    if (!res.ok) {
      console.error(`❌ 升级失败：${res.reason ?? 'unknown_error'}`);
      process.exit(1);
    }
    if (res.reason === 'already_up_to_date') {
      console.log(`✅ 当前已是最新版本：v${res.currentVersion} (${res.localSha256.slice(0, 8)})`);
    } else if (res.reason === 'update_available') {
      console.log(`⬆️ 发现新版本：v${res.currentVersion} -> v${res.latestVersion} (${res.remoteSha256.slice(0, 8)})，运行 \`pipibot upgrade\` 立即升级。`);
    } else if (res.reason === 'git_source_checkout_protected') {
      console.log('ℹ️ 当前运行在 Git 源码目录中，已跳过覆盖；请使用 `git pull` 或加 `--force` 强制覆盖。');
    } else if (res.updated) {
      console.log(`✅ PiPiBot CLI 已升级至 v${res.latestVersion} (${res.localSha256.slice(0, 8)})${res.restarted ? '，后台守护进程已无缝重启' : ''}。`);
    }
    return;
  }
  if (cmd === 'login') {
    await runCliDeviceLogin(relayOrigin);
    return;
  }
  if (cmd === 'logout') {
    clearCliAuth();
    console.log('✅ 已退出 PiPiBot 统一账号登录。');
    return;
  }
  if (cmd === 'devices') {
    await listAccountDevices(relayOrigin);
    return;
  }
  if (cmd === 'agents') {
    const found = detectLocalCliAgents();
    if (!found.length) {
      console.log('未在本机检测到已安装的 CLI Agent Harness（支持 claude / codex / opencode / pi / ollama）。');
      return;
    }
    console.log('\n🤖 本机已检测到的 Agent Harness：');
    for (const a of found) {
      console.log(`  • ${a.name} (${a.id}) -> ${a.binary}`);
    }
    console.log('');
    return;
  }
  if (cmd === 'status') {
    const scope = detectSystemdServiceScope();
    const auth = loadCliAuth();
    if (scope) {
      const sysArgs = scope === 'user' ? ['--user', 'is-active', SYSTEMD_SERVICE_NAME] : ['is-active', SYSTEMD_SERVICE_NAME];
      let active = 'inactive';
      try {
        active = execFileSync('systemctl', sysArgs, { encoding: 'utf8' }).trim();
      } catch {
        active = 'inactive';
      }
      console.log(`守护进程状态：${active === 'active' ? `🟢 systemd 常驻运行中 (${SYSTEMD_SERVICE_NAME}, ${scope})` : `⚪ systemd 未运行 (${active})`}`);
    } else {
      const pid = readRunningDaemonPid();
      console.log(`守护进程状态：${pid ? `🟢 后台运行中 (PID=${pid})` : '⚪ 未在后台运行'}`);
      console.log(`日志文件：${daemonLogPath()}`);
    }
    if (auth?.user) {
      console.log(`当前账号：${auth.user.email || auth.user.displayName} (hostId=${auth.hostId})`);
    }
    return;
  }
  if (cmd === 'logs') {
    const scope = detectSystemdServiceScope();
    if (scope) {
      const jArgs = scope === 'user' ? ['--user', '-u', SYSTEMD_SERVICE_NAME, '-n', '60', '--no-pager'] : ['-u', SYSTEMD_SERVICE_NAME, '-n', '60', '--no-pager'];
      try {
        const out = execFileSync('journalctl', jArgs, { encoding: 'utf8' });
        console.log(out);
        return;
      } catch {
        // fallback to file log
      }
    }
    const logFile = daemonLogPath();
    if (!existsSync(logFile)) {
      console.log('暂无后台日志。使用 `pipibot up -d` 启动后台守护进程。');
      return;
    }
    const lines = readFileSync(logFile, 'utf8').split(/\r?\n/);
    console.log(lines.slice(-60).join('\n'));
    return;
  }
  if (cmd === 'down' || cmd === 'stop') {
    const scope = detectSystemdServiceScope();
    if (scope) {
      try {
        const sysArgs = scope === 'user' ? ['--user', 'disable', '--now', SYSTEMD_SERVICE_NAME] : ['disable', '--now', SYSTEMD_SERVICE_NAME];
        execFileSync('systemctl', sysArgs, { stdio: 'ignore' });
        console.log(`✅ 已停止并关闭 systemd 常驻服务 (${SYSTEMD_SERVICE_NAME})。`);
        return;
      } catch (err) {
        console.error('❌ 停止 systemd 服务失败：', err instanceof Error ? err.message : String(err));
      }
    }
    const pid = readRunningDaemonPid();
    if (!pid) {
      console.log('当前没有在后台运行的 PiPiBot 守护进程。');
      return;
    }
    try {
      process.kill(pid, 'SIGTERM');
      try { unlinkSync(daemonPidPath()); } catch { /* ignore */ }
      console.log(`✅ 已停止后台守护进程 (PID=${pid})。`);
    } catch (err) {
      console.error('❌ 停止失败：', err instanceof Error ? err.message : String(err));
    }
    return;
  }
  if (cmd === 'up') {
    let auth = loadCliAuth();
    if (!auth?.accessToken) {
      console.log('尚未登录 PiPiBot 账号，正在启动统一账号登录...');
      auth = await runCliDeviceLogin(relayOrigin);
    }
    const isDaemon = hasFlag('-d') || hasFlag('--daemon');
    if (isDaemon) {
      const workspaceDir = flag('--workspace') ?? process.cwd();
      const scriptPath = fileURLToPath(import.meta.url);
      const forwardArgs = rest.filter((a) => a !== '-d' && a !== '--daemon');
      // On Linux with systemd, automatically install & enable systemd service for 24/7 health + auto-restart
      const sysRes = tryInstallAndStartSystemd(scriptPath, workspaceDir, forwardArgs);
      if (sysRes.ok) {
        // Stop any legacy detached PID if present
        const oldPid = readRunningDaemonPid();
        if (oldPid) {
          try { process.kill(oldPid, 'SIGTERM'); } catch { /* ignore */ }
          try { unlinkSync(daemonPidPath()); } catch { /* ignore */ }
        }
        console.log(`✅ PiPiBot 已自动注册为 systemd 常驻服务（开机自启 + 异常自动拉起）`);
        console.log(`   服务单元：${sysRes.unitPath} (${sysRes.scope})`);
        console.log(`   查看状态：pipibot status`);
        console.log(`   查看日志：pipibot logs`);
        console.log(`   停止服务：pipibot down`);
        return;
      }

      const existingPid = readRunningDaemonPid();
      if (existingPid) {
        console.log(`ℹ️ PiPiBot 守护进程已在后台运行 (PID=${existingPid})。如需重启请先执行 \`pipibot down\`。`);
        return;
      }
      mkdirSync(dirname(daemonLogPath()), { recursive: true });
      const logFd = openSync(daemonLogPath(), 'a');
      const child = spawn(
        process.execPath,
        ['--dns-result-order=ipv4first', '--experimental-strip-types', '--no-warnings', scriptPath, 'up', ...forwardArgs],
        {
          cwd: workspaceDir,
          detached: true,
          stdio: ['ignore', logFd, logFd],
          env: { ...process.env, NODE_USE_ENV_PROXY: '1' },
        },
      );
      child.unref();
      if (child.pid) {
        writeFileSync(daemonPidPath(), `${child.pid}\n`, 'utf8');
        console.log(`✅ PiPiBot 已转入后台常驻运行 (PID=${child.pid})`);
        console.log(`   查看状态：pipibot status`);
        console.log(`   查看日志：pipibot logs`);
        console.log(`   停止服务：pipibot down`);
      }
      return;
    }

    const host = new PipiCliAgentRelayHost(auth, {
      deviceName: flag('--name'),
      workspacePath: flag('--workspace') ?? process.cwd(),
    });
    const shutdown = () => {
      console.log('\n[pipibot-up] 正在优雅关闭...');
      host.stop();
      process.exit(0);
    };
    process.on('SIGINT', shutdown);
    process.on('SIGTERM', shutdown);
    await host.start();
    return;
  }

  console.log(`PiPiBot CLI — 统一账号设备纳管 & Agent Harness 远程主机

用法:
  pipibot login                     使用统一账号授权登录（支持 Google / GitHub / 邮箱验证码）
  pipibot up [-d] [--name 名称] [--workspace 目录]
                                    接入端到端加密中转并上报本机 Agent Harness（加 -d 后台常驻）
  pipibot status                    查看后台守护进程运行状态
  pipibot logs                      查看后台守护进程最近日志
  pipibot down                      停止后台常驻守护进程
  pipibot upgrade [--check|--force] 检查并热升级到最新 CLI（后台守护每 6 小时自动检测升级）
  pipibot version                   查看当前 CLI 版本与 SHA-256 校验值
  pipibot devices                   查看账号下所有已纳管设备与在线状态
  pipibot agents                    扫描本机已安装的 Agent Harness（Claude Code / Codex / OpenCode / Pi / Ollama）
  pipibot logout                    退出当前登录账号
`);
}

const isDirectExecution = (() => {
  try {
    return process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
})();

if (isDirectExecution) {
  runStandaloneCli(process.argv.slice(2)).catch((err) => {
    console.error('❌', err instanceof Error ? err.message : String(err));
    process.exit(1);
  });
}
