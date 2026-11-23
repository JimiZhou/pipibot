/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/relay - login-page.ts
 * Consumer-grade Apple-craft Sign-In, CLI/Desktop Device Approval (`/login?code=...`),
 * and Ovis-inspired "My Devices & Agents" Control Hub (`/login` & `/devices`).
 */

export function renderLoginAndDevicesHTML(): string {
  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover" />
  <title>登录 PiPiBot — 你的私人 AI 管家</title>
  <link rel="icon" type="image/png" href="/assets/app-icon.png" />
  <link rel="apple-touch-icon" href="/apple-touch-icon.png" />
  <style>
    :root {
      --bg: #f5f5f7;
      --bg-glow: radial-gradient(60% 45% at 50% 0%, rgba(255, 255, 255, 0.95) 0%, rgba(245, 245, 247, 0) 100%);
      --card: rgba(255, 255, 255, 0.88);
      --card-solid: #ffffff;
      --surface: #f2f2f4;
      --surface-hover: #eaeaeD;
      --ink: #111113;
      --secondary: #52525b;
      --muted: #86868b;
      --border: rgba(17, 17, 19, 0.08);
      --border-strong: rgba(17, 17, 19, 0.16);
      --specular: rgba(255, 255, 255, 0.92);
      --ok: #059669;
      --ok-soft: rgba(5, 150, 105, 0.12);
      --err: #dc2626;
      --err-soft: rgba(220, 38, 38, 0.08);
      --shadow-card: 0 1px 2px rgba(0,0,0,0.04), 0 18px 48px -12px rgba(0,0,0,0.08);
      --shadow-btn: 0 1px 2px rgba(0,0,0,0.06);
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #090a0c;
        --bg-glow: radial-gradient(65% 45% at 50% 0%, rgba(255, 255, 255, 0.06) 0%, rgba(9, 10, 12, 0) 100%);
        --card: rgba(22, 23, 27, 0.82);
        --card-solid: #16171b;
        --surface: #1e2026;
        --surface-hover: #262932;
        --ink: #f5f5f7;
        --secondary: #a1a1aa;
        --muted: #71717a;
        --border: rgba(255, 255, 255, 0.08);
        --border-strong: rgba(255, 255, 255, 0.16);
        --specular: rgba(255, 255, 255, 0.14);
        --ok: #10b981;
        --ok-soft: rgba(16, 185, 129, 0.15);
        --err: #f87171;
        --err-soft: rgba(248, 113, 113, 0.12);
        --shadow-card: 0 1px 2px rgba(0,0,0,0.5), 0 24px 60px -12px rgba(0,0,0,0.65);
        --shadow-btn: 0 1px 2px rgba(0,0,0,0.35);
      }
    }
    * { box-sizing: border-box; }
    html, body { height: 100%; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "PingFang SC", "Helvetica Neue", sans-serif;
      background-color: var(--bg);
      background-image: var(--bg-glow);
      color: var(--ink);
      display: flex;
      flex-direction: column;
      align-items: center;
      -webkit-font-smoothing: antialiased;
    }

    /* Top Nav */
    .topbar {
      width: 100%;
      max-width: 960px;
      height: 60px;
      padding: 0 20px;
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .brand {
      display: inline-flex;
      align-items: center;
      gap: 9px;
      text-decoration: none;
      color: var(--ink);
      font-weight: 650;
      font-size: 15.5px;
      letter-spacing: -0.02em;
    }
    .brand img {
      width: 26px;
      height: 26px;
      border-radius: 7px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.12);
    }
    .nav-right {
      display: flex;
      align-items: center;
      gap: 10px;
      font-size: 13px;
      color: var(--secondary);
    }
    .enroll-section {
      margin-top: 22px;
      padding-top: 20px;
      border-top: 1px solid var(--border);
    }
    .enroll-title {
      font-size: 13.5px;
      font-weight: 650;
      color: var(--ink);
      margin: 0 0 12px;
    }
    .enroll-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 12px;
    }
    .enroll-card {
      padding: 16px;
      border-radius: 14px;
      border: 1px solid var(--border);
      background: var(--surface);
      display: flex;
      flex-direction: column;
      gap: 10px;
    }
    .enroll-card-head {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
      font-size: 13.5px;
      font-weight: 650;
      color: var(--ink);
    }
    .enroll-steps {
      margin: 0;
      padding-left: 16px;
      font-size: 12.5px;
      color: var(--secondary);
      line-height: 1.65;
    }
    .cmd-box {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
      padding: 8px 10px;
      border-radius: 10px;
      background: var(--card-solid);
      border: 1px solid var(--border);
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 11.5px;
      color: var(--ink);
      overflow: hidden;
    }
    .cmd-box span {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    @media (max-width: 640px) {
      .enroll-grid { grid-template-columns: 1fr; }
    }
    .nav-link {
      color: var(--secondary);
      text-decoration: none;
      padding: 6px 10px;
      border-radius: 8px;
      transition: background 0.15s, color 0.15s;
    }
    .nav-link:hover { background: var(--surface); color: var(--ink); }

    /* Center Stage */
    .stage {
      flex: 1;
      width: 100%;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 20px 16px 56px;
    }
    .shell { width: 100%; max-width: 420px; transition: max-width 0.25s ease; }
    .shell.wide { max-width: 720px; }

    /* Tactile Frosted Card */
    .card {
      position: relative;
      background: var(--card);
      backdrop-filter: blur(24px) saturate(160%);
      -webkit-backdrop-filter: blur(24px) saturate(160%);
      border: 1px solid var(--border);
      border-radius: 22px;
      padding: 32px 28px 28px;
      box-shadow: var(--shadow-card), inset 0 1px 0 var(--specular);
    }

    .hero-head {
      text-align: center;
      margin-bottom: 24px;
    }
    .hero-logo {
      width: 56px;
      height: 56px;
      border-radius: 15px;
      margin: 0 auto 14px;
      display: block;
      box-shadow: 0 4px 14px rgba(0,0,0,0.12);
    }
    .hero-head h1 {
      margin: 0 0 6px;
      font-size: 22px;
      font-weight: 700;
      letter-spacing: -0.025em;
    }
    .hero-head p {
      margin: 0;
      color: var(--secondary);
      font-size: 13.5px;
      line-height: 1.55;
    }

    /* OAuth Primary Buttons */
    .oauth-stack {
      display: flex;
      flex-direction: column;
      gap: 10px;
    }
    .btn {
      height: 44px;
      padding: 0 16px;
      border-radius: 12px;
      border: 1px solid var(--border-strong);
      background: var(--card-solid);
      color: var(--ink);
      font-size: 14px;
      font-weight: 600;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 10px;
      text-decoration: none;
      white-space: nowrap;
      box-shadow: var(--shadow-btn);
      transition: transform 0.12s ease, background 0.15s ease, border-color 0.15s ease, opacity 0.15s ease;
    }
    .btn:hover { background: var(--surface); border-color: var(--border-strong); }
    .btn:active { transform: scale(0.985); }
    .btn.primary {
      background: var(--ink);
      color: var(--card-solid);
      border-color: var(--ink);
    }
    .btn.primary:hover { opacity: 0.9; background: var(--ink); }
    .btn.full { width: 100%; }
    .btn.sm { height: 34px; padding: 0 13px; font-size: 13px; border-radius: 10px; }
    .btn.ghost {
      background: transparent;
      border-color: transparent;
      box-shadow: none;
      color: var(--secondary);
    }
    .btn.ghost:hover { background: var(--surface); color: var(--ink); }
    .btn:disabled { opacity: 0.48; cursor: not-allowed; }
    .btn svg { width: 18px; height: 18px; flex-shrink: 0; }

    .divider {
      display: flex;
      align-items: center;
      gap: 12px;
      color: var(--muted);
      font-size: 12px;
      margin: 20px 0 18px;
    }
    .divider::before, .divider::after { content: ""; flex: 1; height: 1px; background: var(--border); }

    .input-group {
      display: flex;
      flex-direction: column;
      gap: 10px;
    }
    .field-row {
      display: flex;
      gap: 8px;
    }
    input[type="email"], input[type="text"] {
      width: 100%;
      height: 44px;
      padding: 0 14px;
      border-radius: 12px;
      border: 1px solid var(--border-strong);
      background: var(--surface);
      color: var(--ink);
      font-size: 14px;
      outline: none;
      transition: border-color 0.15s, background 0.15s, box-shadow 0.15s;
    }
    input:focus {
      background: var(--card-solid);
      border-color: var(--ink);
      box-shadow: 0 0 0 3px rgba(128,128,128,0.12);
    }
    #otpInput {
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 17px;
      font-weight: 600;
      letter-spacing: 0.25em;
      text-align: center;
    }

    .msg {
      margin-top: 14px;
      padding: 11px 14px;
      border-radius: 11px;
      font-size: 13px;
      line-height: 1.5;
      background: var(--surface);
      color: var(--ink);
      display: none;
    }
    .msg.show { display: block; }
    .msg.err { background: var(--err-soft); color: var(--err); }
    .msg.ok { background: var(--ok-soft); color: var(--ok); }

    .trust-note {
      margin-top: 20px;
      padding-top: 16px;
      border-top: 1px solid var(--border);
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 10px;
      font-size: 12px;
      color: var(--muted);
    }
    .trust-note a {
      color: var(--ink);
      text-decoration: none;
      font-weight: 600;
    }
    .trust-note a:hover { text-decoration: underline; }

    /* Device Authorization Banner (CLI / Mac App) */
    .code-banner {
      padding: 16px 18px;
      border-radius: 16px;
      border: 1px solid var(--border-strong);
      background: var(--card);
      backdrop-filter: blur(18px);
      box-shadow: var(--shadow-card);
      margin-bottom: 16px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 14px;
    }
    .code-val {
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 20px;
      font-weight: 700;
      letter-spacing: 0.1em;
      margin-top: 2px;
    }

    /* Authenticated Ovis-style Devices Dashboard */
    .dash-head {
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      gap: 12px;
      margin-bottom: 20px;
    }
    .dash-head h1 { margin: 0 0 4px; font-size: 20px; font-weight: 700; letter-spacing: -0.02em; }
    .dash-head p { margin: 0; font-size: 13.5px; color: var(--secondary); }

    .device-list { display: flex; flex-direction: column; gap: 10px; }
    .device-item {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 14px;
      padding: 16px 18px;
      border-radius: 16px;
      border: 1px solid var(--border);
      background: var(--surface);
      transition: border-color 0.15s, background 0.15s;
    }
    .device-item:hover { border-color: var(--border-strong); }
    .device-left { display: flex; align-items: center; gap: 13px; min-width: 0; }
    .device-icon {
      width: 40px;
      height: 40px;
      border-radius: 11px;
      background: var(--card-solid);
      border: 1px solid var(--border);
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 18px;
      flex-shrink: 0;
    }
    .device-name-row {
      display: flex;
      align-items: center;
      gap: 8px;
      font-weight: 650;
      font-size: 14.5px;
    }
    .dot {
      width: 8px;
      height: 8px;
      border-radius: 99px;
      display: inline-block;
      background: var(--muted);
    }
    .dot.on {
      background: var(--ok);
      box-shadow: 0 0 0 3px var(--ok-soft);
    }
    .device-meta { font-size: 12px; color: var(--muted); margin-top: 2px; }
    .caps { display: flex; flex-wrap: wrap; gap: 5px; margin-top: 7px; }
    .cap {
      font-size: 11px;
      font-weight: 500;
      padding: 2px 8px;
      border-radius: 99px;
      background: var(--card-solid);
      border: 1px solid var(--border);
      color: var(--secondary);
    }
    .empty-box {
      padding: 24px 20px;
      border-radius: 16px;
      background: var(--surface);
      border: 1px dashed var(--border-strong);
      font-size: 13.5px;
      color: var(--secondary);
      line-height: 1.7;
    }
    .empty-box code {
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 12.5px;
      padding: 2px 6px;
      border-radius: 6px;
      background: var(--card-solid);
      border: 1px solid var(--border);
      color: var(--ink);
    }
    .dash-footer {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 10px;
      margin-top: 20px;
      padding-top: 16px;
      border-top: 1px solid var(--border);
      flex-wrap: wrap;
    }
    @media (max-width: 520px) {
      .card { padding: 24px 18px 22px; border-radius: 18px; }
      .device-item { flex-direction: column; align-items: stretch; }
    }
  </style>
</head>
<body>
  <header class="topbar">
    <a class="brand" href="/">
      <img src="/assets/app-icon.png" alt="PiPiBot" />
      <span>PiPiBot</span>
    </a>
    <div class="nav-right">
      <a class="nav-link" href="/download">下载客户端</a>
      <div id="userChip" style="display:none;align-items:center;gap:8px;">
        <span id="userLabel" style="font-weight:500;color:var(--ink);"></span>
        <button class="btn sm ghost" onclick="logout()">退出</button>
      </div>
    </div>
  </header>

  <main class="stage">
    <div id="shell" class="shell">
      <div id="deviceCodeBanner" class="code-banner" style="display:none;">
        <div>
          <div style="font-size:12px;color:var(--secondary);">正在授权你的 Mac / 终端设备</div>
          <div id="deviceCodeDisplay" class="code-val"></div>
        </div>
        <button id="approveDeviceBtn" class="btn primary sm" style="display:none;" onclick="approveDeviceCode()">确认授权</button>
      </div>

      <!-- C-End Consumer Sign-In Card -->
      <section id="loginCard" class="card">
        <div class="hero-head">
          <img class="hero-logo" src="/assets/app-icon.png" alt="PiPiBot" />
          <h1>欢迎回到 PiPiBot</h1>
          <p>登录统一账号，手机与网页随时安全连接你的 Mac 与电脑助手</p>
        </div>

        <div id="oauthStack" class="oauth-stack">
          <button class="btn full" id="btnGoogle" onclick="startOAuth('google')">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/><path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/><path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/><path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/></svg>
            <span>使用 Google 继续</span>
          </button>
          <button class="btn full" id="btnGithub" onclick="startOAuth('github')">
            <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 .5C5.65.5.5 5.65.5 12c0 5.08 3.29 9.39 7.86 10.91.57.1.78-.25.78-.55 0-.27-.01-1.16-.02-2.1-3.2.7-3.88-1.36-3.88-1.36-.52-1.33-1.28-1.68-1.28-1.68-1.05-.72.08-.7.08-.7 1.16.08 1.77 1.19 1.77 1.19 1.03 1.76 2.7 1.25 3.36.96.1-.75.4-1.25.73-1.54-2.55-.29-5.24-1.28-5.24-5.69 0-1.26.45-2.29 1.19-3.09-.12-.29-.52-1.46.11-3.05 0 0 .97-.31 3.18 1.18a11.03 11.03 0 0 1 5.79 0c2.21-1.49 3.18-1.18 3.18-1.18.63 1.59.23 2.76.11 3.05.74.8 1.19 1.83 1.19 3.09 0 4.42-2.69 5.39-5.26 5.68.41.36.78 1.06.78 2.14 0 1.55-.01 2.79-.01 3.17 0 .31.21.66.79.55A11.51 11.51 0 0 0 23.5 12C23.5 5.65 18.35.5 12 .5z"/></svg>
            <span>使用 GitHub 继续</span>
          </button>
          <button class="btn full" id="btnApple" style="display:none;" onclick="startOAuth('apple')">
            <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M16.365 1.43c0 1.14-.493 2.27-1.177 3.08-.744.9-1.99 1.57-2.987 1.57-.12 0-.23-.02-.3-.03-.01-.06-.04-.22-.04-.39 0-1.15.572-2.27 1.206-2.98.804-.94 2.142-1.64 3.248-1.68.03.13.05.28.05.43zm4.565 15.71c-.03.07-.463 1.58-1.518 3.12-.945 1.34-1.94 2.71-3.43 2.71-1.517 0-1.9-.88-3.63-.88-1.698 0-2.302.91-3.67.91-1.377 0-2.332-1.26-3.428-2.8-1.287-1.82-2.323-4.63-2.323-7.28 0-4.28 2.797-6.55 5.552-6.55 1.448 0 2.675.95 3.6.95.865 0 2.222-1.01 3.902-1.01.613 0 2.886.06 4.374 2.19-.13.09-2.383 1.37-2.383 4.19 0 3.26 2.854 4.42 2.955 4.45z"/></svg>
            <span>使用 Apple 继续</span>
          </button>
        </div>

        <div class="divider">或使用邮箱验证码</div>

        <div class="input-group">
          <div class="field-row">
            <input id="emailInput" type="email" placeholder="输入邮箱（QQ / 163 / 企业邮箱 / Gmail）" autocomplete="email" />
            <button id="sendOtpBtn" class="btn" style="min-width:108px;" onclick="sendOtp()">获取验证码</button>
          </div>
          <div id="otpRow" class="field-row" style="display:none;">
            <input id="otpInput" type="text" inputmode="numeric" maxlength="6" placeholder="6 位验证码" />
            <button id="verifyOtpBtn" class="btn primary" style="min-width:108px;" onclick="verifyOtp()">立即登录</button>
          </div>
        </div>

        <div id="loginMsg" class="msg"></div>

        <div class="trust-note">
          <span>🔒 全程端到端加密 · 对话与文件仅存本机</span>
          <a href="/download">下载 Mac 客户端 →</a>
        </div>
      </section>

      <!-- Authenticated Ovis-style My Devices Dashboard -->
      <section id="devicesCard" class="card" style="display:none;">
        <div class="dash-head">
          <div>
            <h1>我的设备</h1>
            <p>选择任意在线主机，即可通过端到端加密通道远程对话、审阅文件或接管 Agent。</p>
          </div>
          <button class="btn sm" onclick="refreshMe()">刷新状态</button>
        </div>

        <div id="deviceList" class="device-list"></div>

        <div id="emptyDevices" class="empty-box" style="display:none;">
          当前账号下暂无已纳管设备，按照下方桌面端或 CLI 端步骤 30 秒即可上线。
        </div>

        <div id="devicesMsg" class="msg"></div>

        <!-- Always-available Enrollment Guide: Desktop vs CLI -->
        <div class="enroll-section">
          <div class="enroll-title">纳管新设备</div>
          <div class="enroll-grid">
            <div class="enroll-card">
              <div class="enroll-card-head">
                <span>💻 桌面端纳管（Mac 主力机）</span>
                <a class="btn sm" href="/download">下载 Mac 版</a>
              </div>
              <ol class="enroll-steps">
                <li>下载并打开 PiPiBot Mac 客户端</li>
                <li>进入 <b>设置 → 远程互联</b> 登录当前账号</li>
                <li>自动常驻免费加密中转并出现在上方列表</li>
              </ol>
            </div>

            <div class="enroll-card">
              <div class="enroll-card-head">
                <span>🖥️ CLI 端纳管（Linux / 远程开发机）</span>
                <button class="btn sm" id="copyCliBtn" onclick="copyCliCmd()">复制命令</button>
              </div>
              <div class="cmd-box">
                <span id="cliInstallCmd">curl -fsSL https://pipibot.jimizhou.com/install.sh | bash &amp;&amp; pipibot login &amp;&amp; pipibot up -d</span>
              </div>
              <div style="font-size:12px;color:var(--muted);line-height:1.55;">
                Linux 下 <code>-d</code> 自动注册 <code>systemd</code> 常驻服务（开机自启 &amp; 异常自动拉起），可随时 <code>pipibot status</code> / <code>logs</code> / <code>down</code>。
              </div>
            </div>
          </div>
        </div>

        <div class="dash-footer">
          <span style="font-size:12px;color:var(--muted);">🔒 免费公共加密中转 · pipibot.jimizhou.com</span>
          <a class="btn sm" href="/app">打开移动 WebUI</a>
        </div>
      </section>
    </div>
  </main>

  <script>
    const params = new URLSearchParams(location.search);
    const pendingUserCode = (params.get('code') || '').trim().toUpperCase();
    const justApproved = params.get('approved') === '1';
    let resendCooldown = 0;
    let resendTimer = null;

    if (pendingUserCode) {
      document.getElementById('deviceCodeBanner').style.display = 'flex';
      document.getElementById('deviceCodeDisplay').textContent = pendingUserCode;
    }

    function showMsg(id, text, kind) {
      const el = document.getElementById(id);
      el.textContent = text;
      el.className = 'msg show' + (kind ? ' ' + kind : '');
    }

    async function loadProviders() {
      try {
        const res = await fetch('/api/auth/providers');
        const p = await res.json();
        document.getElementById('btnApple').style.display = p.apple ? 'inline-flex' : 'none';
        document.getElementById('btnGithub').style.display = p.github ? 'inline-flex' : 'none';
        document.getElementById('btnGoogle').style.display = p.google ? 'inline-flex' : 'none';
      } catch {}
    }

    function startResendCooldown() {
      resendCooldown = 60;
      const btn = document.getElementById('sendOtpBtn');
      btn.disabled = true;
      btn.textContent = resendCooldown + 's 后重发';
      clearInterval(resendTimer);
      resendTimer = setInterval(() => {
        resendCooldown -= 1;
        if (resendCooldown <= 0) {
          clearInterval(resendTimer);
          btn.disabled = false;
          btn.textContent = '重新发送';
        } else {
          btn.textContent = resendCooldown + 's 后重发';
        }
      }, 1000);
    }

    async function sendOtp() {
      const email = document.getElementById('emailInput').value.trim();
      if (!email) return showMsg('loginMsg', '请先输入有效的邮箱地址', 'err');
      const btn = document.getElementById('sendOtpBtn');
      btn.disabled = true;
      btn.textContent = '发送中…';
      try {
        const res = await fetch('/api/auth/email/send', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email })
        });
        const data = await res.json();
        if (!data.ok) {
          btn.disabled = false;
          btn.textContent = '获取验证码';
          showMsg('loginMsg', data.error || '发送失败，请稍后重试', 'err');
        } else {
          document.getElementById('otpRow').style.display = 'flex';
          document.getElementById('otpInput').focus();
          startResendCooldown();
          const extra = data.devCode ? '（测试码：' + data.devCode + '）' : '';
          showMsg('loginMsg', '6 位验证码已发送至你的邮箱，10 分钟内有效' + extra, 'ok');
        }
      } catch {
        btn.disabled = false;
        btn.textContent = '获取验证码';
        showMsg('loginMsg', '网络连接异常，请稍后重试', 'err');
      }
    }

    async function verifyOtp() {
      const email = document.getElementById('emailInput').value.trim();
      const code = document.getElementById('otpInput').value.trim();
      if (!code) return showMsg('loginMsg', '请输入 6 位邮箱验证码', 'err');
      const btn = document.getElementById('verifyOtpBtn');
      btn.disabled = true;
      try {
        const res = await fetch('/api/auth/email/verify', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email, code, clientLabel: 'Web Browser' })
        });
        const data = await res.json();
        if (!data.ok) {
          showMsg('loginMsg', data.error || '验证码不正确', 'err');
        } else {
          localStorage.setItem('pipibot_access_token', data.accessToken);
          await refreshMe();
          if (pendingUserCode) {
            await approveDeviceCode();
          }
        }
      } catch {
        showMsg('loginMsg', '验证请求失败，请重试', 'err');
      } finally {
        btn.disabled = false;
      }
    }

    function startOAuth(provider) {
      const q = new URLSearchParams({ redirect: '/login' });
      if (pendingUserCode) q.set('code', pendingUserCode);
      location.href = '/api/auth/oauth/' + provider + '/start?' + q.toString();
    }

    async function approveDeviceCode() {
      if (!pendingUserCode) return;
      const token = localStorage.getItem('pipibot_access_token') || '';
      const res = await fetch('/api/auth/device/approve', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(token ? { Authorization: 'Bearer ' + token } : {})
        },
        body: JSON.stringify({ userCode: pendingUserCode })
      });
      const data = await res.json();
      if (data.ok) {
        document.getElementById('approveDeviceBtn').style.display = 'none';
        showMsg('devicesMsg', '设备 ' + pendingUserCode + ' 已授权成功！请切回 Mac 客户端或终端继续使用。', 'ok');
      } else {
        showMsg('devicesMsg', data.error || '授权失败', 'err');
      }
    }

    function platformEmoji(p) {
      if (p === 'macos') return '💻';
      if (p === 'linux') return '🖥️';
      if (p === 'windows') return '🪟';
      if (p === 'ios') return '📱';
      return '🌐';
    }

    async function refreshMe() {
      const token = localStorage.getItem('pipibot_access_token') || '';
      const res = await fetch('/api/auth/me', {
        headers: token ? { Authorization: 'Bearer ' + token } : {}
      });
      if (!res.ok) {
        document.getElementById('loginCard').style.display = 'block';
        document.getElementById('devicesCard').style.display = 'none';
        document.getElementById('userChip').style.display = 'none';
        document.getElementById('shell').className = 'shell';
        return;
      }
      const data = await res.json();
      document.getElementById('loginCard').style.display = 'none';
      document.getElementById('devicesCard').style.display = 'block';
      document.getElementById('userChip').style.display = 'flex';
      document.getElementById('userLabel').textContent = data.user.email || data.user.displayName;
      document.getElementById('shell').className = 'shell wide';

      if (pendingUserCode && !justApproved) {
        document.getElementById('approveDeviceBtn').style.display = 'inline-flex';
      } else if (justApproved && pendingUserCode) {
        showMsg('devicesMsg', '设备 ' + pendingUserCode + ' 已授权成功，可返回客户端继续使用。', 'ok');
      }

      const listEl = document.getElementById('deviceList');
      const emptyEl = document.getElementById('emptyDevices');
      const devices = data.devices || [];
      listEl.innerHTML = '';
      if (!devices.length) {
        emptyEl.style.display = 'block';
      } else {
        emptyEl.style.display = 'none';
        for (const dev of devices) {
          const item = document.createElement('div');
          item.className = 'device-item';
          const connectUrl = '/c/' + encodeURIComponent(dev.hostId) + '#k=' + encodeURIComponent(dev.hostPubKey || '');
          const capsHtml = (dev.capabilities || []).map(c => '<span class="cap">' + escapeHtml(c) + '</span>').join('');
          item.innerHTML =
            '<div class="device-left">' +
              '<div class="device-icon">' + platformEmoji(dev.platform) + '</div>' +
              '<div style="min-width:0;">' +
                '<div class="device-name-row">' +
                  '<span class="dot ' + (dev.isOnline ? 'on' : '') + '"></span>' +
                  '<span>' + escapeHtml(dev.name) + '</span>' +
                '</div>' +
                '<div class="device-meta">' + escapeHtml(dev.platform.toUpperCase()) + ' · ' + (dev.isOnline ? '已在线 · 加密中转就绪' : '当前离线') + '</div>' +
                (capsHtml ? '<div class="caps">' + capsHtml + '</div>' : '') +
              '</div>' +
            '</div>' +
            '<div style="display:flex;gap:8px;align-items:center;flex-shrink:0;">' +
              (dev.isOnline ? '<a class="btn primary sm" href="' + connectUrl + '">连接接管</a>' : '<span style="font-size:12px;color:var(--muted);padding:0 6px;">离线</span>') +
              '<button class="btn sm ghost" onclick="removeDevice(\\'' + dev.id + '\\')">移除</button>' +
            '</div>';
          listEl.appendChild(item);
        }
      }
    }

    async function removeDevice(id) {
      const token = localStorage.getItem('pipibot_access_token') || '';
      await fetch('/api/devices/' + encodeURIComponent(id), {
        method: 'DELETE',
        headers: token ? { Authorization: 'Bearer ' + token } : {}
      });
      refreshMe();
    }

    async function logout() {
      const token = localStorage.getItem('pipibot_access_token') || '';
      await fetch('/api/auth/logout', {
        method: 'POST',
        headers: token ? { Authorization: 'Bearer ' + token } : {}
      });
      localStorage.removeItem('pipibot_access_token');
      refreshMe();
    }

    function escapeHtml(s) {
      return String(s || '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    }

    async function copyCliCmd() {
      const el = document.getElementById('cliInstallCmd');
      const cmd = (el && el.textContent ? el.textContent.trim() : '') || 'curl -fsSL https://pipibot.jimizhou.com/install.sh | bash && pipibot login && pipibot up';
      try {
        await navigator.clipboard.writeText(cmd);
        const btn = document.getElementById('copyCliBtn');
        btn.textContent = '已复制 ✓';
        setTimeout(() => { btn.textContent = '复制命令'; }, 2000);
      } catch {}
    }

    document.getElementById('otpInput').addEventListener('keydown', (e) => {
      if (e.key === 'Enter') verifyOtp();
    });

    loadProviders();
    refreshMe();
  </script>
</body>
</html>`;
}
