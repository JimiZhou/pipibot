/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/daemon - cloud-browser.ts
 * Per-Teammate Isolated Cloud Browser Manager:
 * - Gives every AI teammate its own persistent Chrome/Chromium profile (`--user-data-dir`),
 *   dedicated CDP port, optional per-teammate proxy, and cookie/session isolation.
 * - Designed for 24/7 cloud workflows on LinkedIn, Reddit, X, GitHub, and web apps.
 * - Supports Interactive Login Handoff (`needs_login` -> owner signs in once -> cookies persist)
 *   and Social Platform External-Effect Safety Guardrails (blocks autonomous Post/DM/Follow
 *   unless explicitly approved by the owner).
 *
 * Runtime dependencies: strictly Node built-ins (`node:*`) only.
 */

import { spawn, type ChildProcess } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';

import type { CloudBrowserStatus, TeammateBrowserProfile } from '@pipibot/protocol';

export interface CloudBrowserConfigureInput {
  botId: string;
  botName: string;
  enabled?: boolean;
  proxyUrl?: string;
  platforms?: string[];
  requireApprovalBeforePost?: boolean;
  cdpPort?: number;
}

export interface SocialActionRiskVerdict {
  requiresApproval: boolean;
  isHardDenied: boolean;
  platform: string;
  reason?: string;
}

export interface CloudBrowserLaunchResult {
  cdpEndpoint: string;
  liveViewUrl?: string;
  pid?: number;
  process?: ChildProcess;
}

export interface CloudBrowserLauncher {
  launch(profile: TeammateBrowserProfile): Promise<CloudBrowserLaunchResult>;
  stop(botId: string, proc?: ChildProcess): Promise<void>;
  probe(profile: TeammateBrowserProfile): Promise<{ reachable: boolean; currentUrl?: string; currentTitle?: string }>;
  navigate(profile: TeammateBrowserProfile, url: string): Promise<{ url: string; title: string }>;
}

const SOCIAL_EXTERNAL_PUBLISH_PATTERNS = [
  'post',
  'publish',
  'reply',
  'repost',
  'retweet',
  'send message',
  'send dm',
  'direct message',
  'connect',
  'follow',
  'comment',
  'submit',
  '发布',
  '发布笔记',
  '发布视频',
  '发布动态',
  '发表',
  '发表评论',
  '群发',
  '发帖',
  '投稿',
  '写回答',
  '立即发布',
  '确认发布',
  '回复',
  '转发',
  '私信',
  '发送私信',
  '发送消息',
  '关注',
  '评论',
];

const PAYMENT_OR_ACCOUNT_DANGER_PATTERNS = [
  'delete account',
  'deactivate',
  'pay now',
  'place order',
  'confirm payment',
  'wire transfer',
  '注销账号',
  '永久删除',
  '立即支付',
  '确认付款',
];

export const SUPPORTED_SOCIAL_PLATFORMS = [
  'xiaohongshu',
  'wechat_mp',
  'douyin',
  'weibo',
  'zhihu',
  'bilibili',
  'jike',
  'x',
  'linkedin',
  'reddit',
  'github',
  'gmail',
] as const;

export function defaultLoginUrlForSocialPlatform(slug: string): string {
  switch (slug.toLowerCase()) {
    case 'xiaohongshu':
    case 'xhs':
      return 'https://creator.xiaohongshu.com/login';
    case 'wechat_mp':
    case 'weixin_mp':
      return 'https://mp.weixin.qq.com/';
    case 'douyin':
      return 'https://creator.douyin.com/';
    case 'weibo':
      return 'https://weibo.com/login.php';
    case 'zhihu':
      return 'https://www.zhihu.com/signin';
    case 'bilibili':
    case 'bili':
      return 'https://passport.bilibili.com/login';
    case 'jike':
      return 'https://web.okjike.com/';
    case 'x':
    case 'twitter':
      return 'https://x.com/i/flow/login';
    case 'linkedin':
      return 'https://www.linkedin.com/login';
    case 'reddit':
      return 'https://www.reddit.com/login';
    case 'github':
      return 'https://github.com/login';
    case 'gmail':
      return 'https://mail.google.com';
    default:
      return 'https://www.xiaohongshu.com/';
  }
}

export function detectSystemChromiumBinary(): string | null {
  const fromEnv = process.env.PIPIBOT_CHROME_PATH?.trim();
  if (fromEnv && existsSync(fromEnv)) return fromEnv;

  const candidates =
    process.platform === 'darwin'
      ? [
          '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
          '/Applications/Chromium.app/Contents/MacOS/Chromium',
          '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
          '/opt/homebrew/bin/chromium',
          '/usr/local/bin/chromium',
        ]
      : [
          '/usr/bin/chromium',
          '/usr/bin/chromium-browser',
          '/usr/bin/google-chrome',
          '/usr/bin/google-chrome-stable',
          '/snap/bin/chromium',
        ];

  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }
  return null;
}

export function detectSocialPlatformFromUrl(rawUrl: string): string {
  const lower = rawUrl.toLowerCase();
  if (lower.includes('xiaohongshu.com') || lower.includes('xhslink.com')) return 'xiaohongshu';
  if (lower.includes('mp.weixin.qq.com') || lower.includes('weixin.qq.com')) return 'wechat_mp';
  if (lower.includes('douyin.com')) return 'douyin';
  if (lower.includes('weibo.com') || lower.includes('weibo.cn')) return 'weibo';
  if (lower.includes('zhihu.com')) return 'zhihu';
  if (lower.includes('bilibili.com') || lower.includes('b23.tv')) return 'bilibili';
  if (lower.includes('okjike.com')) return 'jike';
  if (lower.includes('linkedin.com')) return 'linkedin';
  if (lower.includes('x.com') || lower.includes('twitter.com')) return 'x';
  if (lower.includes('reddit.com')) return 'reddit';
  if (lower.includes('github.com')) return 'github';
  if (lower.includes('mail.google.com')) return 'gmail';
  return 'web';
}

const GUARDED_SOCIAL_PLATFORMS = new Set([
  'xiaohongshu',
  'wechat_mp',
  'douyin',
  'weibo',
  'zhihu',
  'bilibili',
  'jike',
  'linkedin',
  'x',
  'reddit',
]);

/**
 * Evaluates whether a cloud browser action on Mainland China & global social platforms
 * (小红书 / 公众号 / 抖音 / 微博 / 知乎 / B站 / 即刻 / LinkedIn / X / Reddit) requires
 * owner confirmation ("Needs You") before executing.
 */
export function evaluateSocialBrowserActionRisk(input: {
  url: string;
  actionType: 'navigate' | 'click' | 'type' | 'submit' | 'scroll' | 'snapshot';
  targetLabel?: string;
  requireApprovalBeforePost?: boolean;
}): SocialActionRiskVerdict {
  const platform = detectSocialPlatformFromUrl(input.url);

  if (input.url && /^\s*(javascript:|file:|chrome:)/i.test(input.url)) {
    return {
      requiresApproval: true,
      isHardDenied: true,
      platform,
      reason: 'Blocked forbidden browser URL scheme (javascript:/file:/chrome:).',
    };
  }

  if (input.actionType === 'navigate' || input.actionType === 'scroll' || input.actionType === 'snapshot') {
    return { requiresApproval: false, isHardDenied: false, platform };
  }

  const label = (input.targetLabel ?? '').trim().toLowerCase();
  if (PAYMENT_OR_ACCOUNT_DANGER_PATTERNS.some((p) => label.includes(p))) {
    return {
      requiresApproval: true,
      isHardDenied: false,
      platform,
      reason: `High-risk action "${input.targetLabel ?? input.actionType}" requires owner approval.`,
    };
  }

  const isSocialPlatform = GUARDED_SOCIAL_PLATFORMS.has(platform);
  if (
    (input.requireApprovalBeforePost !== false) &&
    (input.actionType === 'submit' || (isSocialPlatform && input.actionType === 'click' && SOCIAL_EXTERNAL_PUBLISH_PATTERNS.some((p) => label.includes(p))))
  ) {
    return {
      requiresApproval: true,
      isHardDenied: false,
      platform,
      reason: `External ${platform} action ("${input.targetLabel ?? input.actionType}") routed to Needs You approval queue.`,
    };
  }

  return { requiresApproval: false, isHardDenied: false, platform };
}

class DefaultChromiumLauncher implements CloudBrowserLauncher {
  async launch(profile: TeammateBrowserProfile): Promise<CloudBrowserLaunchResult> {
    const bin = detectSystemChromiumBinary();
    if (!bin) {
      throw new Error('No Chrome/Chromium binary found. Install chromium or set PIPIBOT_CHROME_PATH.');
    }

    mkdirSync(profile.profileDir, { recursive: true, mode: 0o700 });
    const args = [
      '--headless=new',
      `--remote-debugging-port=${profile.cdpPort}`,
      '--remote-debugging-address=127.0.0.1',
      `--user-data-dir=${profile.profileDir}`,
      '--window-size=1280,820',
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-background-networking',
      '--disable-default-apps',
      '--disable-sync',
      '--disable-dev-shm-usage',
      '--disable-blink-features=AutomationControlled',
      ...(process.platform === 'linux' && process.getuid?.() === 0 ? ['--no-sandbox'] : []),
      ...(profile.proxyUrl ? [`--proxy-server=${profile.proxyUrl}`] : []),
      profile.currentUrl || 'about:blank',
    ];

    const proc = spawn(bin, args, {
      stdio: ['ignore', 'ignore', 'ignore'],
      detached: false,
    });

    // Wait up to 6 seconds for CDP HTTP endpoint
    const endpointBase = `http://127.0.0.1:${profile.cdpPort}`;
    for (let i = 0; i < 30; i += 1) {
      if (proc.exitCode !== null) {
        throw new Error(`Chromium exited immediately with code ${proc.exitCode}`);
      }
      const probed = await this.probe(profile);
      if (probed.reachable) {
        return {
          cdpEndpoint: endpointBase,
          liveViewUrl: `${endpointBase}/json/list`,
          pid: proc.pid,
          process: proc,
        };
      }
      await new Promise((r) => setTimeout(r, 200));
    }

    try {
      proc.kill('SIGTERM');
    } catch {
      // ignore
    }
    throw new Error(`Timed out waiting for teammate Chromium CDP on port ${profile.cdpPort}`);
  }

  async stop(_botId: string, proc?: ChildProcess): Promise<void> {
    if (proc && proc.exitCode === null) {
      try {
        proc.kill('SIGTERM');
      } catch {
        // ignore
      }
    }
  }

  async probe(profile: TeammateBrowserProfile): Promise<{ reachable: boolean; currentUrl?: string; currentTitle?: string }> {
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 1200);
      try {
        const resp = await fetch(`http://127.0.0.1:${profile.cdpPort}/json/list`, { signal: controller.signal });
        if (!resp.ok) return { reachable: false };
        const targets = (await resp.json()) as Array<{ type?: string; url?: string; title?: string }>;
        const page = targets.find((t) => t.type === 'page') ?? targets[0];
        return {
          reachable: true,
          currentUrl: page?.url ?? profile.currentUrl,
          currentTitle: page?.title ?? profile.currentTitle,
        };
      } finally {
        clearTimeout(timer);
      }
    } catch {
      return { reachable: false };
    }
  }

  async navigate(profile: TeammateBrowserProfile, url: string): Promise<{ url: string; title: string }> {
    // Open a new page target on the isolated CDP instance or fallback metadata update
    try {
      const resp = await fetch(`http://127.0.0.1:${profile.cdpPort}/json/new?${encodeURIComponent(url)}`, {
        method: 'PUT',
      });
      if (resp.ok) {
        const json = (await resp.json()) as { url?: string; title?: string };
        return { url: json.url || url, title: json.title || detectSocialPlatformFromUrl(url) };
      }
    } catch {
      // fallback below
    }
    return { url, title: `${profile.botName} · ${detectSocialPlatformFromUrl(url)}` };
  }
}

export class PipiCloudBrowserManager {
  private readonly dataDir: string;
  private readonly statePath: string;
  private readonly basePort: number;
  private readonly launcher: CloudBrowserLauncher;
  private readonly profiles = new Map<string, TeammateBrowserProfile>();
  private readonly runningProcs = new Map<string, ChildProcess>();

  constructor(options: {
    dataDir?: string;
    basePort?: number;
    launcher?: CloudBrowserLauncher;
    persist?: boolean;
  } = {}) {
    this.dataDir = options.dataDir ?? join(homedir(), '.pipibot');
    this.statePath = options.persist === false ? '' : join(this.dataDir, 'cloud-browsers.json');
    this.basePort = options.basePort ?? 29300;
    this.launcher = options.launcher ?? new DefaultChromiumLauncher();
    this.load();
  }

  listProfiles(): TeammateBrowserProfile[] {
    return Array.from(this.profiles.values())
      .sort((a, b) => a.cdpPort - b.cdpPort || a.botId.localeCompare(b.botId))
      .map((p) => ({ ...p, platforms: [...p.platforms] }));
  }

  getProfile(botId: string): TeammateBrowserProfile | undefined {
    const p = this.profiles.get(botId);
    return p ? { ...p, platforms: [...p.platforms] } : undefined;
  }

  configureProfile(input: CloudBrowserConfigureInput): TeammateBrowserProfile {
    const existing = this.profiles.get(input.botId);
    const safeSlug = input.botId.replace(/[^a-zA-Z0-9._-]/g, '_');
    const profileDir = existing?.profileDir ?? join(this.dataDir, 'cloud-browsers', safeSlug, 'profile');
    const cdpPort = input.cdpPort ?? existing?.cdpPort ?? this.allocatePort();

    const profile: TeammateBrowserProfile = {
      botId: input.botId,
      botName: input.botName.trim() || existing?.botName || input.botId,
      enabled: input.enabled ?? existing?.enabled ?? true,
      status: existing?.status ?? 'stopped',
      profileDir,
      cdpPort,
      cdpEndpoint: existing?.cdpEndpoint,
      liveViewUrl: existing?.liveViewUrl,
      proxyUrl: input.proxyUrl !== undefined ? (input.proxyUrl.trim() || undefined) : existing?.proxyUrl,
      platforms: input.platforms ? Array.from(new Set(input.platforms.map((s) => s.trim().toLowerCase()).filter(Boolean))) : (existing?.platforms ?? ['x', 'linkedin', 'reddit']),
      currentUrl: existing?.currentUrl ?? 'about:blank',
      currentTitle: existing?.currentTitle ?? `${input.botName} Browser`,
      requireApprovalBeforePost: input.requireApprovalBeforePost ?? existing?.requireApprovalBeforePost ?? true,
      lastActiveAt: existing?.lastActiveAt,
      lastError: existing?.lastError,
    };

    this.profiles.set(input.botId, profile);
    this.save();
    return { ...profile, platforms: [...profile.platforms] };
  }

  async startBrowser(botId: string, fallbackName?: string): Promise<TeammateBrowserProfile> {
    let profile = this.profiles.get(botId);
    if (!profile) {
      profile = this.configureProfile({ botId, botName: fallbackName ?? botId, enabled: true });
    }
    if (profile.status === 'running') {
      const probed = await this.launcher.probe(profile);
      if (probed.reachable) {
        profile.lastActiveAt = new Date().toISOString();
        this.save();
        return { ...profile, platforms: [...profile.platforms] };
      }
    }

    profile.status = 'starting';
    profile.lastError = undefined;
    this.save();

    try {
      const launched = await this.launcher.launch(profile);
      if (launched.process) {
        this.runningProcs.set(botId, launched.process);
        launched.process.once('exit', () => {
          this.runningProcs.delete(botId);
          const current = this.profiles.get(botId);
          if (current && current.status === 'running') {
            current.status = 'stopped';
            this.save();
          }
        });
      }
      profile.status = 'running';
      profile.cdpEndpoint = launched.cdpEndpoint;
      profile.liveViewUrl = launched.liveViewUrl;
      profile.lastActiveAt = new Date().toISOString();
      this.save();
      return { ...profile, platforms: [...profile.platforms] };
    } catch (err) {
      profile.status = 'error';
      profile.lastError = err instanceof Error ? err.message : String(err);
      this.save();
      throw err;
    }
  }

  async stopBrowser(botId: string): Promise<TeammateBrowserProfile | null> {
    const profile = this.profiles.get(botId);
    if (!profile) return null;
    const proc = this.runningProcs.get(botId);
    await this.launcher.stop(botId, proc);
    this.runningProcs.delete(botId);
    profile.status = 'stopped';
    profile.cdpEndpoint = undefined;
    this.save();
    return { ...profile, platforms: [...profile.platforms] };
  }

  async stopAll(): Promise<void> {
    for (const botId of Array.from(this.runningProcs.keys())) {
      await this.stopBrowser(botId);
    }
  }

  /**
   * Pauses automation on a teammate's isolated browser and marks it `needs_login`
   * so the human owner can sign into LinkedIn / X / Reddit once and persist cookies.
   */
  async requestLoginHandoff(botId: string, loginUrl: string): Promise<TeammateBrowserProfile> {
    const profile = await this.startBrowser(botId);
    const nav = await this.launcher.navigate(profile, loginUrl);
    const stored = this.profiles.get(botId)!;
    stored.status = 'needs_login';
    stored.currentUrl = nav.url;
    stored.currentTitle = nav.title;
    stored.lastActiveAt = new Date().toISOString();
    this.save();
    return { ...stored, platforms: [...stored.platforms] };
  }

  completeLoginHandoff(botId: string): TeammateBrowserProfile | null {
    const stored = this.profiles.get(botId);
    if (!stored) return null;
    stored.status = 'running';
    stored.lastActiveAt = new Date().toISOString();
    this.save();
    return { ...stored, platforms: [...stored.platforms] };
  }

  async navigate(
    botId: string,
    url: string,
  ): Promise<{ profile: TeammateBrowserProfile; risk: SocialActionRiskVerdict }> {
    const risk = evaluateSocialBrowserActionRisk({ url, actionType: 'navigate' });
    if (risk.isHardDenied) {
      throw new Error(risk.reason ?? 'Navigation blocked by browser guardrail.');
    }
    const profile = await this.startBrowser(botId);
    const nav = await this.launcher.navigate(profile, url);
    const stored = this.profiles.get(botId)!;
    stored.currentUrl = nav.url;
    stored.currentTitle = nav.title;
    stored.lastActiveAt = new Date().toISOString();
    this.save();
    return { profile: { ...stored, platforms: [...stored.platforms] }, risk };
  }

  private allocatePort(): number {
    const used = new Set(Array.from(this.profiles.values()).map((p) => p.cdpPort));
    let port = this.basePort;
    while (used.has(port)) port += 1;
    return port;
  }

  private load(): void {
    if (!this.statePath || !existsSync(this.statePath)) return;
    try {
      const raw = readFileSync(this.statePath, 'utf8');
      const parsed = JSON.parse(raw) as { profiles?: TeammateBrowserProfile[] };
      if (Array.isArray(parsed.profiles)) {
        for (const p of parsed.profiles) {
          // On cold boot, no previous Chromium child process is attached yet
          this.profiles.set(p.botId, { ...p, status: 'stopped' as CloudBrowserStatus });
        }
      }
    } catch {
      // ignore corrupted file
    }
  }

  private save(): void {
    if (!this.statePath) return;
    try {
      mkdirSync(dirname(this.statePath), { recursive: true, mode: 0o700 });
      const tmp = `${this.statePath}.tmp-${process.pid}`;
      writeFileSync(
        tmp,
        `${JSON.stringify({ version: 1, profiles: Array.from(this.profiles.values()), updatedAt: new Date().toISOString() }, null, 2)}\n`,
        { mode: 0o600 },
      );
      renameSync(tmp, this.statePath);
    } catch {
      // ignore
    }
  }
}
