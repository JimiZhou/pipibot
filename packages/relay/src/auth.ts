/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/relay - auth.ts
 * Unified Lightweight Account & Device Directory for PiPiBot (Zero-Knowledge E2EE preserved):
 * - Email 6-digit OTP (passwordless, works globally & in China with zero ICP/enterprise gate)
 * - Sign in with Apple OAuth
 * - GitHub OAuth
 * - Google OAuth
 * - RFC-style Device Flow (`pipibot login` CLI & macOS App browser sign-in)
 * - Unified Device Registry (`Mac`, `Linux`, `Windows`, `iOS`, `Web`) with public-key discovery
 *
 * Zero external npm dependencies (Node 22 built-in `crypto` + atomic JSON state file).
 */

import { createHash, createSign, randomBytes, randomInt, randomUUID } from 'node:crypto';
import { chmodSync, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';

export type OAuthProviderKind = 'apple' | 'github' | 'google';
export type DevicePlatformKind = 'macos' | 'linux' | 'windows' | 'ios' | 'web';

export interface PipiUserRecord {
  id: string;
  email?: string;
  displayName: string;
  avatarUrl?: string;
  providers: string[];
  createdAt: string;
  updatedAt: string;
}

export interface PipiOAuthLink {
  provider: OAuthProviderKind;
  providerUserId: string;
  userId: string;
  email?: string;
  linkedAt: string;
}

export interface PipiSessionRecord {
  tokenHash: string;
  userId: string;
  clientLabel: string;
  createdAt: string;
  expiresAt: number;
}

export interface PipiDeviceRecord {
  id: string;
  userId: string;
  name: string;
  platform: DevicePlatformKind;
  hostId: string;
  hostPubKey: string;
  capabilities: string[];
  workspacePath?: string;
  lastSeenAt: string;
  createdAt: string;
}

interface PersistedAuthState {
  version: number;
  users: PipiUserRecord[];
  oauthLinks: PipiOAuthLink[];
  sessions: PipiSessionRecord[];
  devices: PipiDeviceRecord[];
}

interface PendingEmailOTP {
  email: string;
  codeHash: string;
  expiresAt: number;
  attempts: number;
}

interface PendingDeviceFlow {
  deviceCode: string;
  userCode: string;
  clientLabel: string;
  expiresAt: number;
  status: 'pending' | 'approved';
  approvedUserId?: string;
  issuedToken?: string;
}

interface PendingOAuthState {
  provider: OAuthProviderKind;
  createdAt: number;
  userCode?: string;
  redirectTo: string;
}

export interface AuthServiceOptions {
  stateFilePath?: string;
  inMemory?: boolean;
  publicOrigin?: string;
  exposeDevOtp?: boolean;
  resendApiKey?: string;
  emailFrom?: string;
  githubClientId?: string;
  githubClientSecret?: string;
  googleClientId?: string;
  googleClientSecret?: string;
  appleClientId?: string;
  appleTeamId?: string;
  appleKeyId?: string;
  applePrivateKey?: string;
}

const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 days
const OTP_TTL_MS = 10 * 60 * 1000; // 10 minutes
const DEVICE_FLOW_TTL_MS = 10 * 60 * 1000; // 10 minutes

function sha256Hex(input: string): string {
  return createHash('sha256').update(input).digest('hex');
}

function normalizeEmail(raw: string): string {
  return raw.trim().toLowerCase();
}

function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) && email.length <= 254;
}

function generateUserCode(): string {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let suffix = '';
  for (let i = 0; i < 6; i += 1) {
    suffix += alphabet[randomInt(0, alphabet.length)];
  }
  return `PIPI-${suffix.slice(0, 3)}${suffix.slice(3)}`;
}

export class PipiAuthService {
  private readonly stateFilePath: string;
  private readonly inMemory: boolean;
  private readonly publicOrigin: string;
  private readonly exposeDevOtp: boolean;
  private readonly resendApiKey: string;
  private readonly emailFrom: string;
  private readonly githubClientId: string;
  private readonly githubClientSecret: string;
  private readonly googleClientId: string;
  private readonly googleClientSecret: string;
  private readonly appleClientId: string;
  private readonly appleTeamId: string;
  private readonly appleKeyId: string;
  private readonly applePrivateKey: string;

  private users = new Map<string, PipiUserRecord>();
  private oauthLinks: PipiOAuthLink[] = [];
  private sessions = new Map<string, PipiSessionRecord>();
  private devices = new Map<string, PipiDeviceRecord>();

  private readonly pendingOtps = new Map<string, PendingEmailOTP>();
  private readonly deviceFlowsByDeviceCode = new Map<string, PendingDeviceFlow>();
  private readonly deviceFlowsByUserCode = new Map<string, PendingDeviceFlow>();
  private readonly oauthStates = new Map<string, PendingOAuthState>();

  constructor(options?: AuthServiceOptions) {
    this.inMemory = options?.inMemory ?? false;
    this.stateFilePath =
      options?.stateFilePath ??
      process.env.PIPIBOT_RELAY_AUTH_STATE ??
      join(homedir(), '.pipibot-relay', 'auth-state.json');
    this.publicOrigin = (
      options?.publicOrigin ??
      process.env.PIPIBOT_RELAY_ORIGIN ??
      'https://pipibot.jimizhou.com'
    ).replace(/\/+$/, '');
    this.exposeDevOtp = options?.exposeDevOtp ?? process.env.PIPIBOT_AUTH_DEV_MODE === '1';
    this.resendApiKey = (options?.resendApiKey ?? process.env.PIPIBOT_RESEND_API_KEY ?? '').trim();
    this.emailFrom = (options?.emailFrom ?? process.env.PIPIBOT_EMAIL_FROM ?? 'PiPiBot <noreply@pipibot.jimizhou.com>').trim();
    this.githubClientId = (options?.githubClientId ?? process.env.PIPIBOT_GITHUB_CLIENT_ID ?? '').trim();
    this.githubClientSecret = (options?.githubClientSecret ?? process.env.PIPIBOT_GITHUB_CLIENT_SECRET ?? '').trim();
    this.googleClientId = (options?.googleClientId ?? process.env.PIPIBOT_GOOGLE_CLIENT_ID ?? '').trim();
    this.googleClientSecret = (options?.googleClientSecret ?? process.env.PIPIBOT_GOOGLE_CLIENT_SECRET ?? '').trim();
    this.appleClientId = (options?.appleClientId ?? process.env.PIPIBOT_APPLE_CLIENT_ID ?? '').trim();
    this.appleTeamId = (options?.appleTeamId ?? process.env.PIPIBOT_APPLE_TEAM_ID ?? '').trim();
    this.appleKeyId = (options?.appleKeyId ?? process.env.PIPIBOT_APPLE_KEY_ID ?? '').trim();
    this.applePrivateKey = (options?.applePrivateKey ?? process.env.PIPIBOT_APPLE_PRIVATE_KEY ?? '').replace(/\\n/g, '\n').trim();

    if (!this.inMemory) {
      this.load();
    }
  }

  getEnabledProviders(): {
    email: boolean;
    apple: boolean;
    github: boolean;
    google: boolean;
    origin: string;
  } {
    return {
      email: true,
      apple: Boolean(this.appleClientId && this.appleTeamId && this.appleKeyId && this.applePrivateKey),
      github: Boolean(this.githubClientId && this.githubClientSecret),
      google: Boolean(this.googleClientId && this.googleClientSecret),
      origin: this.publicOrigin,
    };
  }

  // MARK: - Persistence

  private load(): void {
    if (!existsSync(this.stateFilePath)) return;
    try {
      const raw = readFileSync(this.stateFilePath, 'utf8');
      const parsed = JSON.parse(raw) as Partial<PersistedAuthState>;
      for (const u of parsed.users ?? []) {
        if (u?.id) this.users.set(u.id, u);
      }
      this.oauthLinks = Array.isArray(parsed.oauthLinks) ? parsed.oauthLinks : [];
      const now = Date.now();
      for (const s of parsed.sessions ?? []) {
        if (s?.tokenHash && s.expiresAt > now) {
          this.sessions.set(s.tokenHash, s);
        }
      }
      for (const d of parsed.devices ?? []) {
        if (d?.id) this.devices.set(d.id, d);
      }
    } catch {
      // Keep clean state if file is unreadable
    }
  }

  private persist(): void {
    if (this.inMemory) return;
    try {
      mkdirSync(dirname(this.stateFilePath), { recursive: true });
      const payload: PersistedAuthState = {
        version: 1,
        users: [...this.users.values()],
        oauthLinks: this.oauthLinks,
        sessions: [...this.sessions.values()].filter((s) => s.expiresAt > Date.now()),
        devices: [...this.devices.values()],
      };
      const tmp = `${this.stateFilePath}.tmp.${process.pid}`;
      writeFileSync(tmp, JSON.stringify(payload, null, 2), 'utf8');
      try {
        chmodSync(tmp, 0o600);
      } catch {
        // Ignore on non-POSIX filesystems
      }
      renameSync(tmp, this.stateFilePath);
    } catch {
      // Ignore transient disk errors
    }
  }

  // MARK: - Email 6-Digit OTP

  async sendEmailOtp(rawEmail: string): Promise<{
    ok: boolean;
    error?: string;
    delivery?: 'resend' | 'dev_preview';
    devCode?: string;
    expiresIn?: number;
  }> {
    const email = normalizeEmail(rawEmail);
    if (!isValidEmail(email)) {
      return { ok: false, error: '请输入有效的邮箱地址' };
    }

    const code = String(randomInt(100000, 1000000));
    this.pendingOtps.set(email, {
      email,
      codeHash: sha256Hex(`${email}:${code}`),
      expiresAt: Date.now() + OTP_TTL_MS,
      attempts: 0,
    });

    if (this.resendApiKey) {
      try {
        const resp = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${this.resendApiKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            from: this.emailFrom,
            to: [email],
            subject: `PiPiBot 登录验证码：${code}`,
            html: `<div style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;max-width:460px;margin:24px auto;padding:24px;border:1px solid #e5e7eb;border-radius:14px;">
              <h2 style="margin:0 0 12px;font-size:18px;color:#111827;">PiPiBot 登录验证码</h2>
              <p style="margin:0 0 18px;color:#4b5563;font-size:14px;">您正在登录 PiPiBot 统一账号，10 分钟内有效：</p>
              <div style="font-size:32px;font-weight:700;letter-spacing:6px;color:#111827;background:#f3f4f6;padding:14px 20px;border-radius:10px;text-align:center;">${code}</div>
              <p style="margin:18px 0 0;color:#9ca3af;font-size:12px;">如非本人操作，请忽略此邮件。您的所有对话与本地文件均采用端到端加密，中转服务器无法读取。</p>
            </div>`,
          }),
        });
        if (!resp.ok) {
          const text = await resp.text().catch(() => '');
          return { ok: false, error: `邮件发送失败 (${resp.status}): ${text.slice(0, 120)}` };
        }
        return { ok: true, delivery: 'resend', expiresIn: Math.floor(OTP_TTL_MS / 1000) };
      } catch (err) {
        return { ok: false, error: `邮件服务连接失败: ${(err as Error).message}` };
      }
    }

    // Fallback when no email provider key is configured yet
    console.error(`[pipibot-auth] Email OTP for ${email}: ${code} (valid 10m)`);
    return {
      ok: true,
      delivery: 'dev_preview',
      devCode: this.exposeDevOtp ? code : undefined,
      expiresIn: Math.floor(OTP_TTL_MS / 1000),
    };
  }

  verifyEmailOtp(
    rawEmail: string,
    rawCode: string,
    clientLabel = 'Web',
  ): { ok: boolean; error?: string; accessToken?: string; user?: PipiUserRecord } {
    const email = normalizeEmail(rawEmail);
    const code = rawCode.trim();
    const record = this.pendingOtps.get(email);
    if (!record || record.expiresAt < Date.now()) {
      this.pendingOtps.delete(email);
      return { ok: false, error: '验证码已过期，请重新获取' };
    }
    if (record.attempts >= 5) {
      this.pendingOtps.delete(email);
      return { ok: false, error: '尝试次数过多，请重新获取验证码' };
    }
    record.attempts += 1;

    if (sha256Hex(`${email}:${code}`) !== record.codeHash) {
      return { ok: false, error: '验证码不正确，请重试' };
    }

    this.pendingOtps.delete(email);
    const user = this.findOrCreateUserByEmail(email, 'email');
    const accessToken = this.issueSession(user.id, clientLabel);
    return { ok: true, accessToken, user };
  }

  // MARK: - OAuth (Apple / GitHub / Google)

  buildOAuthStartUrl(
    provider: OAuthProviderKind,
    options?: { userCode?: string; redirectTo?: string; originOverride?: string },
  ): { ok: boolean; url?: string; error?: string } {
    const origin = (options?.originOverride ?? this.publicOrigin).replace(/\/+$/, '');
    const state = randomBytes(18).toString('base64url');
    this.oauthStates.set(state, {
      provider,
      createdAt: Date.now(),
      userCode: options?.userCode?.trim().toUpperCase() || undefined,
      redirectTo: options?.redirectTo || '/app',
    });

    const callbackUrl = `${origin}/api/auth/oauth/${provider}/callback`;

    if (provider === 'github') {
      if (!this.githubClientId || !this.githubClientSecret) {
        return { ok: false, error: 'GitHub OAuth 尚未配置（请设置 PIPIBOT_GITHUB_CLIENT_ID / SECRET）' };
      }
      const params = new URLSearchParams({
        client_id: this.githubClientId,
        redirect_uri: callbackUrl,
        scope: 'read:user user:email',
        state,
      });
      return { ok: true, url: `https://github.com/login/oauth/authorize?${params.toString()}` };
    }

    if (provider === 'google') {
      if (!this.googleClientId || !this.googleClientSecret) {
        return { ok: false, error: 'Google OAuth 尚未配置（请设置 PIPIBOT_GOOGLE_CLIENT_ID / SECRET）' };
      }
      const params = new URLSearchParams({
        client_id: this.googleClientId,
        redirect_uri: callbackUrl,
        response_type: 'code',
        scope: 'openid email profile',
        access_type: 'online',
        prompt: 'select_account',
        state,
      });
      return { ok: true, url: `https://accounts.google.com/o/oauth2/v2/auth?${params.toString()}` };
    }

    if (provider === 'apple') {
      if (!this.appleClientId || !this.appleTeamId || !this.appleKeyId || !this.applePrivateKey) {
        return { ok: false, error: 'Apple 登录尚未配置（请设置 PIPIBOT_APPLE_CLIENT_ID / TEAM_ID / KEY_ID / PRIVATE_KEY）' };
      }
      const params = new URLSearchParams({
        client_id: this.appleClientId,
        redirect_uri: callbackUrl,
        response_type: 'code',
        response_mode: 'form_post',
        scope: 'name email',
        state,
      });
      return { ok: true, url: `https://appleid.apple.com/auth/authorize?${params.toString()}` };
    }

    return { ok: false, error: '不支持的登录方式' };
  }

  async handleOAuthCallback(
    provider: OAuthProviderKind,
    params: { code?: string; state?: string; originOverride?: string },
  ): Promise<{
    ok: boolean;
    error?: string;
    accessToken?: string;
    user?: PipiUserRecord;
    redirectTo?: string;
    approvedUserCode?: string;
  }> {
    const state = params.state?.trim() ?? '';
    const code = params.code?.trim() ?? '';
    const pending = this.oauthStates.get(state);
    if (!pending || pending.provider !== provider || Date.now() - pending.createdAt > 10 * 60 * 1000) {
      return { ok: false, error: '登录状态已过期，请重新发起登录' };
    }
    this.oauthStates.delete(state);
    if (!code) {
      return { ok: false, error: '未收到第三方授权码' };
    }

    const origin = (params.originOverride ?? this.publicOrigin).replace(/\/+$/, '');
    const callbackUrl = `${origin}/api/auth/oauth/${provider}/callback`;

    try {
      let profile: { providerUserId: string; email?: string; displayName: string; avatarUrl?: string };
      if (provider === 'github') {
        profile = await this.exchangeGitHubCode(code, callbackUrl);
      } else if (provider === 'google') {
        profile = await this.exchangeGoogleCode(code, callbackUrl);
      } else {
        profile = await this.exchangeAppleCode(code, callbackUrl);
      }

      const user = this.findOrCreateUserByOAuth(provider, profile);
      const accessToken = this.issueSession(user.id, `OAuth:${provider}`);

      let approvedUserCode: string | undefined;
      if (pending.userCode) {
        const res = this.approveDeviceFlow(pending.userCode, user.id);
        if (res.ok) approvedUserCode = pending.userCode;
      }

      return {
        ok: true,
        accessToken,
        user,
        redirectTo: approvedUserCode ? `/login?approved=1&code=${encodeURIComponent(approvedUserCode)}` : pending.redirectTo,
        approvedUserCode,
      };
    } catch (err) {
      return { ok: false, error: `第三方登录失败: ${(err as Error).message}` };
    }
  }

  private async exchangeGitHubCode(
    code: string,
    redirectUri: string,
  ): Promise<{ providerUserId: string; email?: string; displayName: string; avatarUrl?: string }> {
    const tokenResp = await fetch('https://github.com/login/oauth/access_token', {
      method: 'POST',
      headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
      body: JSON.stringify({
        client_id: this.githubClientId,
        client_secret: this.githubClientSecret,
        code,
        redirect_uri: redirectUri,
      }),
    });
    const tokenJson = (await tokenResp.json()) as { access_token?: string; error_description?: string };
    if (!tokenJson.access_token) {
      throw new Error(tokenJson.error_description || 'GitHub token exchange failed');
    }

    const userResp = await fetch('https://api.github.com/user', {
      headers: { Authorization: `Bearer ${tokenJson.access_token}`, 'User-Agent': 'PiPiBot-Relay' },
    });
    const userJson = (await userResp.json()) as { id?: number; login?: string; name?: string; email?: string; avatar_url?: string };
    let email = userJson.email ?? undefined;
    if (!email) {
      const emailResp = await fetch('https://api.github.com/user/emails', {
        headers: { Authorization: `Bearer ${tokenJson.access_token}`, 'User-Agent': 'PiPiBot-Relay' },
      });
      if (emailResp.ok) {
        const list = (await emailResp.json()) as Array<{ email: string; primary: boolean; verified: boolean }>;
        email = list.find((e) => e.primary && e.verified)?.email ?? list.find((e) => e.verified)?.email;
      }
    }
    return {
      providerUserId: String(userJson.id ?? ''),
      email: email ? normalizeEmail(email) : undefined,
      displayName: userJson.name || userJson.login || 'GitHub User',
      avatarUrl: userJson.avatar_url,
    };
  }

  private async exchangeGoogleCode(
    code: string,
    redirectUri: string,
  ): Promise<{ providerUserId: string; email?: string; displayName: string; avatarUrl?: string }> {
    const tokenResp = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: this.googleClientId,
        client_secret: this.googleClientSecret,
        code,
        redirect_uri: redirectUri,
        grant_type: 'authorization_code',
      }),
    });
    const tokenJson = (await tokenResp.json()) as { access_token?: string; error_description?: string };
    if (!tokenJson.access_token) {
      throw new Error(tokenJson.error_description || 'Google token exchange failed');
    }

    const userResp = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
      headers: { Authorization: `Bearer ${tokenJson.access_token}` },
    });
    const userJson = (await userResp.json()) as { sub?: string; email?: string; name?: string; picture?: string };
    return {
      providerUserId: String(userJson.sub ?? ''),
      email: userJson.email ? normalizeEmail(userJson.email) : undefined,
      displayName: userJson.name || userJson.email?.split('@')[0] || 'Google User',
      avatarUrl: userJson.picture,
    };
  }

  private async exchangeAppleCode(
    code: string,
    redirectUri: string,
  ): Promise<{ providerUserId: string; email?: string; displayName: string; avatarUrl?: string }> {
    const clientSecret = this.buildAppleClientSecretJwt();
    const tokenResp = await fetch('https://appleid.apple.com/auth/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: this.appleClientId,
        client_secret: clientSecret,
        code,
        redirect_uri: redirectUri,
        grant_type: 'authorization_code',
      }),
    });
    const tokenJson = (await tokenResp.json()) as { id_token?: string; error?: string };
    if (!tokenJson.id_token) {
      throw new Error(tokenJson.error || 'Apple token exchange failed');
    }
    const payloadSegment = tokenJson.id_token.split('.')[1] ?? '';
    const payload = JSON.parse(Buffer.from(payloadSegment, 'base64url').toString('utf8')) as {
      sub?: string;
      email?: string;
    };
    const email = payload.email ? normalizeEmail(payload.email) : undefined;
    return {
      providerUserId: String(payload.sub ?? ''),
      email,
      displayName: email ? email.split('@')[0] : 'Apple User',
    };
  }

  private buildAppleClientSecretJwt(): string {
    const now = Math.floor(Date.now() / 1000);
    const header = Buffer.from(JSON.stringify({ alg: 'ES256', kid: this.appleKeyId })).toString('base64url');
    const claims = Buffer.from(
      JSON.stringify({
        iss: this.appleTeamId,
        iat: now,
        exp: now + 300,
        aud: 'https://appleid.apple.com',
        sub: this.appleClientId,
      }),
    ).toString('base64url');
    const signingInput = `${header}.${claims}`;
    const signer = createSign('SHA256');
    signer.update(signingInput);
    signer.end();
    const sig = signer.sign({ key: this.applePrivateKey, dsaEncoding: 'ieee-p1363' }).toString('base64url');
    return `${signingInput}.${sig}`;
  }

  // MARK: - Device Flow (CLI `pipibot login` & macOS App OAuth sign-in)

  startDeviceFlow(clientLabel = 'PiPiBot CLI', originOverride?: string): {
    deviceCode: string;
    userCode: string;
    verificationUrl: string;
    expiresIn: number;
    interval: number;
  } {
    const deviceCode = randomBytes(24).toString('base64url');
    const userCode = generateUserCode();
    const flow: PendingDeviceFlow = {
      deviceCode,
      userCode,
      clientLabel,
      expiresAt: Date.now() + DEVICE_FLOW_TTL_MS,
      status: 'pending',
    };
    this.deviceFlowsByDeviceCode.set(deviceCode, flow);
    this.deviceFlowsByUserCode.set(userCode, flow);
    const origin = (originOverride ?? this.publicOrigin).replace(/\/+$/, '');
    return {
      deviceCode,
      userCode,
      verificationUrl: `${origin}/login?code=${encodeURIComponent(userCode)}`,
      expiresIn: Math.floor(DEVICE_FLOW_TTL_MS / 1000),
      interval: 2,
    };
  }

  approveDeviceFlow(userCodeRaw: string, userId: string): { ok: boolean; error?: string } {
    const userCode = userCodeRaw.trim().toUpperCase();
    const flow = this.deviceFlowsByUserCode.get(userCode);
    if (!flow || flow.expiresAt < Date.now()) {
      return { ok: false, error: '设备授权码已过期或不存在' };
    }
    const token = this.issueSession(userId, flow.clientLabel);
    flow.status = 'approved';
    flow.approvedUserId = userId;
    flow.issuedToken = token;
    return { ok: true };
  }

  pollDeviceFlow(deviceCode: string): {
    status: 'pending' | 'approved' | 'expired';
    accessToken?: string;
    user?: PipiUserRecord;
  } {
    const flow = this.deviceFlowsByDeviceCode.get(deviceCode.trim());
    if (!flow || flow.expiresAt < Date.now()) {
      return { status: 'expired' };
    }
    if (flow.status !== 'approved' || !flow.issuedToken || !flow.approvedUserId) {
      return { status: 'pending' };
    }
    const user = this.users.get(flow.approvedUserId);
    const token = flow.issuedToken;
    this.deviceFlowsByDeviceCode.delete(flow.deviceCode);
    this.deviceFlowsByUserCode.delete(flow.userCode);
    return { status: 'approved', accessToken: token, user };
  }

  // MARK: - Sessions & Users

  authenticateToken(rawToken: string | null | undefined): PipiUserRecord | null {
    const token = rawToken?.trim();
    if (!token) return null;
    const hash = sha256Hex(token);
    const sess = this.sessions.get(hash);
    if (!sess) return null;
    if (sess.expiresAt < Date.now()) {
      this.sessions.delete(hash);
      this.persist();
      return null;
    }
    return this.users.get(sess.userId) ?? null;
  }

  revokeToken(rawToken: string | null | undefined): void {
    const token = rawToken?.trim();
    if (!token) return;
    if (this.sessions.delete(sha256Hex(token))) {
      this.persist();
    }
  }

  private issueSession(userId: string, clientLabel: string): string {
    const token = `pipi_sess_${randomBytes(28).toString('base64url')}`;
    this.sessions.set(sha256Hex(token), {
      tokenHash: sha256Hex(token),
      userId,
      clientLabel,
      createdAt: new Date().toISOString(),
      expiresAt: Date.now() + SESSION_TTL_MS,
    });
    this.persist();
    return token;
  }

  private findOrCreateUserByEmail(email: string, provider: string): PipiUserRecord {
    const existing = [...this.users.values()].find((u) => u.email === email);
    const now = new Date().toISOString();
    if (existing) {
      if (!existing.providers.includes(provider)) {
        existing.providers.push(provider);
      }
      existing.updatedAt = now;
      this.persist();
      return existing;
    }
    const created: PipiUserRecord = {
      id: `usr_${randomUUID().slice(0, 12)}`,
      email,
      displayName: email.split('@')[0] || 'PiPi User',
      providers: [provider],
      createdAt: now,
      updatedAt: now,
    };
    this.users.set(created.id, created);
    this.persist();
    return created;
  }

  private findOrCreateUserByOAuth(
    provider: OAuthProviderKind,
    profile: { providerUserId: string; email?: string; displayName: string; avatarUrl?: string },
  ): PipiUserRecord {
    const now = new Date().toISOString();
    const existingLink = this.oauthLinks.find(
      (l) => l.provider === provider && l.providerUserId === profile.providerUserId,
    );
    if (existingLink) {
      const u = this.users.get(existingLink.userId);
      if (u) {
        u.displayName = u.displayName || profile.displayName;
        if (profile.avatarUrl && !u.avatarUrl) u.avatarUrl = profile.avatarUrl;
        u.updatedAt = now;
        this.persist();
        return u;
      }
    }

    let user: PipiUserRecord | undefined;
    if (profile.email) {
      user = [...this.users.values()].find((u) => u.email === profile.email);
    }
    if (!user) {
      user = {
        id: `usr_${randomUUID().slice(0, 12)}`,
        email: profile.email,
        displayName: profile.displayName,
        avatarUrl: profile.avatarUrl,
        providers: [provider],
        createdAt: now,
        updatedAt: now,
      };
      this.users.set(user.id, user);
    } else if (!user.providers.includes(provider)) {
      user.providers.push(provider);
      user.updatedAt = now;
    }

    this.oauthLinks.push({
      provider,
      providerUserId: profile.providerUserId,
      userId: user.id,
      email: profile.email,
      linkedAt: now,
    });
    this.persist();
    return user;
  }

  // MARK: - Unified Device Registry

  registerDevice(
    userId: string,
    input: {
      name: string;
      platform: DevicePlatformKind;
      hostId: string;
      hostPubKey: string;
      capabilities?: string[];
      workspacePath?: string;
    },
  ): PipiDeviceRecord {
    const now = new Date().toISOString();
    const existing = [...this.devices.values()].find(
      (d) => d.userId === userId && d.hostId === input.hostId,
    );
    if (existing) {
      existing.name = input.name.trim() || existing.name;
      existing.platform = input.platform;
      existing.hostPubKey = input.hostPubKey || existing.hostPubKey;
      existing.capabilities = input.capabilities ?? existing.capabilities;
      existing.workspacePath = input.workspacePath ?? existing.workspacePath;
      existing.lastSeenAt = now;
      this.persist();
      return existing;
    }
    const created: PipiDeviceRecord = {
      id: `dev_${randomUUID().slice(0, 10)}`,
      userId,
      name: input.name.trim() || 'My Device',
      platform: input.platform,
      hostId: input.hostId,
      hostPubKey: input.hostPubKey,
      capabilities: input.capabilities ?? [],
      workspacePath: input.workspacePath,
      lastSeenAt: now,
      createdAt: now,
    };
    this.devices.set(created.id, created);
    this.persist();
    return created;
  }

  touchDeviceByHostId(userId: string, hostId: string): void {
    const dev = [...this.devices.values()].find((d) => d.userId === userId && d.hostId === hostId);
    if (dev) {
      dev.lastSeenAt = new Date().toISOString();
      this.persist();
    }
  }

  listDevices(
    userId: string,
    onlineHostIds: ReadonlySet<string>,
  ): Array<PipiDeviceRecord & { isOnline: boolean }> {
    return [...this.devices.values()]
      .filter((d) => d.userId === userId)
      .map((d) => ({
        ...d,
        isOnline: onlineHostIds.has(d.hostId),
      }))
      .sort((a, b) => {
        if (a.isOnline !== b.isOnline) return a.isOnline ? -1 : 1;
        return b.lastSeenAt.localeCompare(a.lastSeenAt);
      });
  }

  removeDevice(userId: string, deviceId: string): boolean {
    const dev = this.devices.get(deviceId);
    if (!dev || dev.userId !== userId) return false;
    this.devices.delete(deviceId);
    this.persist();
    return true;
  }
}
