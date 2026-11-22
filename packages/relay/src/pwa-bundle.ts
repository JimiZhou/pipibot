/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/relay - pwa-bundle.ts
 * Consumer-grade, Apple Fluid Interface 5-Tab Mobile PWA Companion served by:
 *   - https://pipibot.jimizhou.com/c/<hostId>, /pair, /app (Oracle VPS Zero-Knowledge E2EE Relay)
 *   - PiPiBot Mac App local server
 *   - PiPiBot Linux/macOS Daemon Hub (/mobile)
 *
 * UX & Security Highlights:
 * - Vellum Light / Obsidian Dark native PiPiBot Design Tokens + frosted glass navigation & floating dock
 * - Pointer-down tactile micro-feedback, spring-feel bottom sheet for E2EE link diagnostics & theme switch
 * - Built-in lightweight Markdown renderer (code blocks, inline code, bold, lists) & syntax-colored Unified Diff viewer
 * - Starter prompt cards, Bot switcher strip, draft "Edit + Add Harness Rule", toast notifications
 * - WebCrypto P-256 ECDH + HKDF-SHA256 + AES-256-GCM E2EE + 3-tier transport (LAN -> WebRTC P2P -> WSS E2EE)
 */

export function renderUniversalManifest(): string {
  return JSON.stringify(
    {
      name: 'PiPiBot Companion',
      short_name: 'PiPiBot',
      description: '零知识端到端加密的个人 AI 管家团队随身控制台',
      start_url: '/app',
      scope: '/',
      display: 'standalone',
      background_color: '#FDFCF9',
      theme_color: '#5B4CE4',
      orientation: 'portrait',
      icons: [
        {
          src: '/icon.svg?v=2',
          sizes: 'any',
          type: 'image/svg+xml',
          purpose: 'any maskable',
        },
      ],
    },
    null,
    2,
  );
}

/**
 * Official "PiPi Halo" Hardware-Robot SVG Icon — 1:1 vector match with `scripts/generate-app-icons.swift`
 * & `PipiBotMarkView.swift` (Porcelain Ceramic chassis with concave crown notch, Sapphire-Indigo visor,
 * twin Arctic-Cyan optical lenses & crown telemetry pip).
 */
export function renderOfficialBrandMarkSVG(size = 28): string {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 1024 1024" aria-hidden="true">
  <defs>
    <linearGradient id="pipiField" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#FDFCF9"/>
      <stop offset="55%" stop-color="#F5F2EC"/>
      <stop offset="100%" stop-color="#E8E3D9"/>
    </linearGradient>
    <radialGradient id="pipiHalo" cx="50%" cy="49%" r="44%">
      <stop offset="0%" stop-color="#38BDF8" stop-opacity="0.16"/>
      <stop offset="52%" stop-color="#63F5E6" stop-opacity="0.07"/>
      <stop offset="100%" stop-color="#F5F2EC" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="pipiChassis" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#FFFFFF"/>
      <stop offset="56%" stop-color="#F4F1EA"/>
      <stop offset="100%" stop-color="#DCD6C9"/>
    </linearGradient>
    <linearGradient id="pipiRim" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.95"/>
      <stop offset="50%" stop-color="#C5BEB2" stop-opacity="0.88"/>
      <stop offset="100%" stop-color="#A79F93" stop-opacity="0.82"/>
    </linearGradient>
    <linearGradient id="pipiVisor" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#1E3A8A"/>
      <stop offset="55%" stop-color="#172554"/>
      <stop offset="100%" stop-color="#0F172A"/>
    </linearGradient>
    <radialGradient id="pipiLensAura" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#67E8F9" stop-opacity="0.52"/>
      <stop offset="55%" stop-color="#38BDF8" stop-opacity="0.16"/>
      <stop offset="100%" stop-color="#172554" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="pipiLensCore" cx="46%" cy="40%" r="58%">
      <stop offset="0%" stop-color="#F7FDFF"/>
      <stop offset="52%" stop-color="#67E8F9"/>
      <stop offset="100%" stop-color="#06B6D4"/>
    </radialGradient>
  </defs>
  <rect x="44" y="44" width="936" height="936" rx="212" fill="url(#pipiField)" stroke="#171717" stroke-opacity="0.10" stroke-width="8"/>
  <circle cx="512" cy="504" r="430" fill="url(#pipiHalo)"/>
  <path d="M365.04 160 L396.5 160 C448.48 160 468.11 185.34 512 185.34 C555.89 185.34 575.52 160 627.5 160 L658.96 160 C751.96 160 842 250.04 842 343.04 L842 680.96 C842 773.96 751.96 864 658.96 864 L365.04 864 C272.04 864 182 773.96 182 680.96 L182 343.04 C182 250.04 272.04 160 365.04 160 Z" fill="url(#pipiChassis)" stroke="url(#pipiRim)" stroke-width="14"/>
  <rect x="484" y="292" width="56" height="11" rx="5.5" fill="#B9B2A6" fill-opacity="0.82"/>
  <rect x="498" y="293.5" width="28" height="8" rx="4" fill="#0284C7"/>
  <rect x="244.7" y="394.8" width="534.6" height="260.5" rx="130.25" fill="url(#pipiVisor)" stroke="#3B4A7A" stroke-width="10"/>
  <line x1="369" y1="410" x2="655" y2="410" stroke="#FFFFFF" stroke-opacity="0.28" stroke-width="7" stroke-linecap="round"/>
  <ellipse cx="376.7" cy="525" rx="108" ry="116" fill="url(#pipiLensAura)"/>
  <ellipse cx="647.3" cy="525" rx="108" ry="116" fill="url(#pipiLensAura)"/>
  <ellipse cx="376.7" cy="525" rx="70.95" ry="84.15" fill="url(#pipiLensCore)"/>
  <ellipse cx="647.3" cy="525" rx="70.95" ry="84.15" fill="url(#pipiLensCore)"/>
  <ellipse cx="352" cy="488" rx="18" ry="12" fill="#FFFFFF" fill-opacity="0.88"/>
  <ellipse cx="622.6" cy="488" rx="18" ry="12" fill="#FFFFFF" fill-opacity="0.88"/>
</svg>`;
}

export function renderUniversalIconSVG(): string {
  return renderOfficialBrandMarkSVG(192);
}

export function renderUniversalPWAHTML(options?: {
  relayMode?: boolean;
  defaultHostTitle?: string;
  stunUrls?: string[];
}): string {
  const relayMode = options?.relayMode ?? true;
  const hostTitle = options?.defaultHostTitle ?? 'PiPiBot';
  const stunUrls = JSON.stringify(
    options?.stunUrls ?? ['stun:stun.l.google.com:19302', 'stun:stun.cloudflare.com:3478'],
  );

  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover" />
  <meta name="apple-mobile-web-app-capable" content="yes" />
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent" />
  <meta name="apple-mobile-web-app-title" content="PiPiBot" />
  <link rel="manifest" href="/manifest.webmanifest" />
  <link rel="apple-touch-icon" href="/icon.svg?v=2" />
  <link rel="icon" type="image/svg+xml" href="/icon.svg?v=2" />
  <title>${hostTitle} · Companion</title>
  <style>
    :root {
      --canvas: #FDFCF9;
      --surface: #FFFFFF;
      --surface-soft: #F7F5F0;
      --surface-hover: #F1EDE4;
      --glass: rgba(253, 252, 249, 0.82);
      --border: rgba(23, 22, 20, 0.09);
      --border-strong: rgba(23, 22, 20, 0.16);
      --ink: #171614;
      --ink-2: #5E5B55;
      --ink-3: #8B867D;
      --soul: #5B4CE4;
      --soul-soft: rgba(91, 76, 228, 0.11);
      --soul-glow: rgba(91, 76, 228, 0.22);
      --ok: #047857;
      --ok-soft: rgba(4, 120, 87, 0.12);
      --warn: #B45309;
      --warn-soft: rgba(180, 83, 9, 0.12);
      --err: #B91C1C;
      --err-soft: rgba(185, 28, 28, 0.11);
      --diff-add: rgba(4, 120, 87, 0.11);
      --diff-del: rgba(185, 28, 28, 0.10);
      --shadow-sm: 0 2px 10px rgba(23, 22, 20, 0.04);
      --shadow-md: 0 12px 32px rgba(23, 22, 20, 0.10);
      --radius: 18px;
    }
    [data-theme="dark"] {
      --canvas: #08090B;
      --surface: #121418;
      --surface-soft: #171A20;
      --surface-hover: #1E222B;
      --glass: rgba(14, 16, 20, 0.82);
      --border: rgba(244, 245, 247, 0.09);
      --border-strong: rgba(244, 245, 247, 0.18);
      --ink: #F4F5F7;
      --ink-2: #A1A7B3;
      --ink-3: #6C7382;
      --soul: #7C6CF6;
      --soul-soft: rgba(124, 108, 246, 0.16);
      --soul-glow: rgba(124, 108, 246, 0.30);
      --ok: #10B981;
      --ok-soft: rgba(16, 185, 129, 0.16);
      --warn: #F59E0B;
      --warn-soft: rgba(245, 158, 11, 0.16);
      --err: #F87171;
      --err-soft: rgba(248, 113, 113, 0.16);
      --diff-add: rgba(16, 185, 129, 0.16);
      --diff-del: rgba(248, 113, 113, 0.15);
      --shadow-sm: 0 2px 12px rgba(0, 0, 0, 0.3);
      --shadow-md: 0 16px 40px rgba(0, 0, 0, 0.55);
    }
    @media (prefers-color-scheme: dark) {
      :root:not([data-theme="light"]) {
        --canvas: #08090B;
        --surface: #121418;
        --surface-soft: #171A20;
        --surface-hover: #1E222B;
        --glass: rgba(14, 16, 20, 0.82);
        --border: rgba(244, 245, 247, 0.09);
        --border-strong: rgba(244, 245, 247, 0.18);
        --ink: #F4F5F7;
        --ink-2: #A1A7B3;
        --ink-3: #6C7382;
        --soul: #7C6CF6;
        --soul-soft: rgba(124, 108, 246, 0.16);
        --soul-glow: rgba(124, 108, 246, 0.30);
        --ok: #10B981;
        --ok-soft: rgba(16, 185, 129, 0.16);
        --warn: #F59E0B;
        --warn-soft: rgba(245, 158, 11, 0.16);
        --err: #F87171;
        --err-soft: rgba(248, 113, 113, 0.16);
        --diff-add: rgba(16, 185, 129, 0.16);
        --diff-del: rgba(248, 113, 113, 0.15);
        --shadow-sm: 0 2px 12px rgba(0, 0, 0, 0.3);
        --shadow-md: 0 16px 40px rgba(0, 0, 0, 0.55);
      }
    }

    * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
    html, body {
      margin: 0; padding: 0; height: 100%; background: var(--canvas); color: var(--ink);
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", sans-serif;
      -webkit-font-smoothing: antialiased;
    }
    .app {
      position: relative; display: flex; flex-direction: column; height: 100dvh; max-width: 760px; margin: 0 auto;
    }

    /* Frosted Top Navigation */
    .topbar {
      position: sticky; top: 0; z-index: 20;
      display: flex; align-items: center; justify-content: space-between; gap: 10px;
      padding: calc(env(safe-area-inset-top) + 10px) 16px 11px;
      background: var(--glass);
      backdrop-filter: saturate(180%) blur(22px);
      -webkit-backdrop-filter: saturate(180%) blur(22px);
      border-bottom: 1px solid var(--border);
    }
    .brand { display: flex; align-items: center; gap: 10px; min-width: 0; }
    .avatar-orb {
      width: 36px; height: 36px; border-radius: 10px; flex-shrink: 0;
      display: grid; place-items: center; overflow: hidden;
    }
    .avatar-orb.pulse { animation: orbBreathe 2.6s ease-in-out infinite; }
    @keyframes orbBreathe { 0%,100% { transform: scale(1); } 50% { transform: scale(1.06); } }
    .brand-title { font-size: 15.5px; font-weight: 700; letter-spacing: -0.02em; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .brand-sub { font-size: 11.5px; color: var(--ink-2); display: flex; align-items: center; gap: 5px; margin-top: 1px; }
    .dot { width: 7px; height: 7px; border-radius: 50%; background: var(--warn); }
    .dot.ok { background: var(--ok); box-shadow: 0 0 0 3px var(--ok-soft); }
    .dot.err { background: var(--err); }

    .status-pill {
      border: 1px solid var(--border); background: var(--surface); color: var(--ink);
      padding: 6px 11px; border-radius: 999px; font-size: 11.5px; font-weight: 650;
      display: inline-flex; align-items: center; gap: 6px; cursor: pointer;
      box-shadow: var(--shadow-sm); transition: transform 100ms ease-out;
    }
    .status-pill:active { transform: scale(0.95); }
    .status-pill.ok { color: var(--ok); border-color: var(--ok-soft); background: var(--ok-soft); }

    /* Install Banner */
    .pwa-banner {
      display: none; align-items: center; justify-content: space-between; gap: 10px;
      padding: 9px 16px; font-size: 12px; color: var(--ink); background: var(--soul-soft);
      border-bottom: 1px solid var(--border);
    }
    .pwa-banner.show { display: flex; }

    /* Bot Switcher Strip */
    .bot-strip {
      display: none; gap: 7px; overflow-x: auto; padding: 9px 16px 4px; scrollbar-width: none;
    }
    .bot-strip::-webkit-scrollbar { display: none; }
    .bot-strip.show { display: flex; }
    .bot-chip {
      border: 1px solid var(--border); background: var(--surface); color: var(--ink-2);
      padding: 6px 12px; border-radius: 999px; font-size: 12px; font-weight: 600;
      white-space: nowrap; cursor: pointer; transition: transform 100ms ease-out, background 140ms ease;
    }
    .bot-chip:active { transform: scale(0.95); }
    .bot-chip.active { background: var(--ink); color: var(--canvas); border-color: transparent; }

    /* Main Scroll Canvas */
    .main {
      flex: 1; overflow-y: auto; -webkit-overflow-scrolling: touch;
      padding: 14px 16px 24px; display: flex; flex-direction: column; gap: 12px;
    }

    /* Cards & Typography */
    .card {
      background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius);
      padding: 15px 16px; display: flex; flex-direction: column; gap: 10px; box-shadow: var(--shadow-sm);
    }
    .row { display: flex; align-items: center; justify-content: space-between; gap: 8px; flex-wrap: wrap; }
    .card-title { font-size: 14.5px; font-weight: 700; letter-spacing: -0.015em; }
    .sub { font-size: 12.5px; color: var(--ink-2); line-height: 1.5; }
    .badge {
      font-size: 11px; font-weight: 650; padding: 3px 9px; border-radius: 999px;
      background: var(--soul-soft); color: var(--soul);
    }
    .badge.ok { background: var(--ok-soft); color: var(--ok); }
    .badge.warn { background: var(--warn-soft); color: var(--warn); }
    .badge.err { background: var(--err-soft); color: var(--err); }

    /* KPI 2x2 Grid */
    .kpi-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px; }
    .kpi {
      background: var(--surface); border: 1px solid var(--border); border-radius: 16px;
      padding: 13px 14px; display: flex; flex-direction: column; gap: 4px; box-shadow: var(--shadow-sm);
    }
    .kpi-val { font-size: 22px; font-weight: 760; letter-spacing: -0.03em; }
    .kpi-label { font-size: 11.5px; color: var(--ink-2); font-weight: 500; }

    /* Chat Messages + Rich Markdown */
    .msg-wrap { display: flex; flex-direction: column; gap: 3px; }
    .msg-wrap.user { align-items: flex-end; }
    .msg-wrap.assistant { align-items: flex-start; }
    .msg-author { font-size: 11px; font-weight: 600; color: var(--ink-3); padding: 0 6px; }
    .msg {
      max-width: 88%; padding: 11px 14px; border-radius: 18px; font-size: 14.5px; line-height: 1.55;
      word-break: break-word;
    }
    .msg.user {
      background: var(--soul); color: #FFFFFF; border-bottom-right-radius: 5px;
      box-shadow: 0 6px 18px var(--soul-glow);
    }
    .msg.assistant {
      background: var(--surface); border: 1px solid var(--border); color: var(--ink);
      border-bottom-left-radius: 5px; box-shadow: var(--shadow-sm);
    }
    .msg pre {
      margin: 8px 0; padding: 10px 12px; border-radius: 10px; background: var(--surface-soft);
      border: 1px solid var(--border); overflow-x: auto; font-size: 12px; line-height: 1.45;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace; color: var(--ink);
    }
    .msg code {
      padding: 1px 5px; border-radius: 5px; background: var(--surface-soft);
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.9em;
    }
    .msg.user code { background: rgba(255,255,255,0.2); }

    /* Starter Prompts */
    .welcome-hero { text-align: center; padding: 24px 8px 10px; display: flex; flex-direction: column; align-items: center; gap: 10px; }
    .starter-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 9px; width: 100%; margin-top: 8px; }
    .starter-btn {
      text-align: left; padding: 12px 13px; border-radius: 15px; border: 1px solid var(--border);
      background: var(--surface); color: var(--ink); cursor: pointer; box-shadow: var(--shadow-sm);
      display: flex; flex-direction: column; gap: 4px; transition: transform 100ms ease-out;
    }
    .starter-btn:active { transform: scale(0.96); }
    .starter-btn strong { font-size: 13px; }
    .starter-btn span { font-size: 11.5px; color: var(--ink-2); }

    /* Syntax-Colored Unified Diff */
    .diff-box {
      border-radius: 12px; overflow: hidden; border: 1px solid var(--border); background: var(--surface-soft);
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 11.5px; max-height: 240px; overflow: auto;
    }
    .diff-line { padding: 2px 10px; white-space: pre; }
    .diff-line.add { background: var(--diff-add); color: var(--ok); }
    .diff-line.del { background: var(--diff-del); color: var(--err); }
    .diff-line.hunk { color: var(--soul); font-weight: 600; background: var(--soul-soft); }
    .proof-bar { height: 6px; border-radius: 999px; background: var(--surface-hover); overflow: hidden; }
    .proof-fill { height: 100%; background: linear-gradient(90deg, var(--soul), var(--ok)); border-radius: 999px; }

    /* Buttons & Inputs */
    .btn {
      border: 1px solid var(--border); background: var(--surface-soft); color: var(--ink);
      padding: 8px 14px; border-radius: 11px; font-size: 13px; font-weight: 650; cursor: pointer;
      display: inline-flex; align-items: center; justify-content: center; gap: 6px;
      transition: transform 100ms ease-out, opacity 120ms ease;
    }
    .btn:active { transform: scale(0.95); }
    .btn.primary { background: var(--ink); color: var(--canvas); border-color: transparent; }
    .btn.soul { background: var(--soul); color: #FFFFFF; border-color: transparent; box-shadow: 0 5px 16px var(--soul-glow); }
    .btn.ok { background: var(--ok); color: #FFFFFF; border-color: transparent; }
    .btn.danger { background: var(--err-soft); color: var(--err); border-color: transparent; }
    .btn:disabled { opacity: 0.45; }
    input.field {
      width: 100%; border: 1px solid var(--border-strong); border-radius: 12px; padding: 11px 13px;
      background: var(--canvas); color: var(--ink); font-size: 14px; outline: none; font-family: inherit;
    }
    input.field:focus { border-color: var(--soul); box-shadow: 0 0 0 3px var(--soul-soft); }

    /* Composer */
    .composer-wrap {
      padding: 8px 14px 8px; background: var(--glass);
      backdrop-filter: saturate(180%) blur(22px); -webkit-backdrop-filter: saturate(180%) blur(22px);
      border-top: 1px solid var(--border);
    }
    .composer-box {
      display: flex; align-items: flex-end; gap: 8px; padding: 6px 6px 6px 12px;
      background: var(--surface); border: 1px solid var(--border-strong); border-radius: 22px;
      box-shadow: var(--shadow-sm);
    }
    .composer-box textarea {
      flex: 1; resize: none; min-height: 28px; max-height: 150px; overflow-y: auto; border: 0;
      padding: 6px 0; font-size: 14.5px; line-height: 1.45; background: transparent; color: var(--ink);
      outline: none; font-family: inherit;
    }
    .send-btn {
      width: 34px; height: 34px; border-radius: 50%; border: 0; flex-shrink: 0;
      background: var(--soul); color: #FFFFFF; font-size: 16px; font-weight: 700; cursor: pointer;
      display: grid; place-items: center; transition: transform 100ms ease-out, opacity 140ms ease;
    }
    .send-btn:active { transform: scale(0.90); }
    .send-btn:disabled { opacity: 0.35; }

    /* Frosted Bottom Tab Bar */
    .tabbar {
      display: grid; grid-template-columns: repeat(5, 1fr); gap: 4px;
      padding: 7px 10px calc(env(safe-area-inset-bottom) + 8px);
      background: var(--glass);
      backdrop-filter: saturate(180%) blur(24px); -webkit-backdrop-filter: saturate(180%) blur(24px);
      border-top: 1px solid var(--border);
    }
    .tab {
      position: relative; border: 0; background: transparent; color: var(--ink-3);
      font-size: 10.5px; font-weight: 600; padding: 6px 2px; border-radius: 12px; cursor: pointer;
      display: flex; flex-direction: column; align-items: center; gap: 3px;
      transition: transform 100ms ease-out, color 140ms ease, background 140ms ease;
    }
    .tab:active { transform: scale(0.93); }
    .tab.active { color: var(--soul); background: var(--soul-soft); }
    .tab svg { width: 20px; height: 20px; stroke: currentColor; fill: none; stroke-width: 1.9; stroke-linecap: round; stroke-linejoin: round; }
    .tab-dot {
      position: absolute; top: 4px; right: 16px; min-width: 16px; height: 16px; padding: 0 4px;
      border-radius: 999px; background: var(--err); color: #FFF; font-size: 10px; font-weight: 700;
      display: none; align-items: center; justify-content: center;
    }
    .tab-dot.show { display: inline-flex; }

    /* Bottom Sheet Modal */
    .sheet-backdrop {
      position: fixed; inset: 0; z-index: 50; background: rgba(0,0,0,0.42);
      display: none; align-items: flex-end; justify-content: center;
    }
    .sheet-backdrop.show { display: flex; }
    .sheet {
      width: 100%; max-width: 540px; background: var(--surface); border-radius: 26px 26px 0 0;
      padding: 12px 20px calc(env(safe-area-inset-bottom) + 22px);
      border-top: 1px solid var(--border); box-shadow: var(--shadow-md);
      display: flex; flex-direction: column; gap: 14px;
    }
    .sheet-handle { width: 40px; height: 4.5px; border-radius: 999px; background: var(--border-strong); margin: 0 auto 2px; }

    /* Toast */
    .toast {
      position: fixed; top: calc(env(safe-area-inset-top) + 64px); left: 50%; transform: translateX(-50%) translateY(-10px);
      z-index: 60; padding: 9px 16px; border-radius: 999px; background: var(--ink); color: var(--canvas);
      font-size: 12.5px; font-weight: 600; opacity: 0; pointer-events: none; transition: all 180ms ease;
      box-shadow: var(--shadow-md);
    }
    .toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }

    .empty { text-align: center; color: var(--ink-2); font-size: 13.5px; padding: 36px 18px; line-height: 1.6; }
  </style>
</head>
<body>
<div class="app">
  <header class="topbar">
    <div class="brand">
      <div class="avatar-orb pulse" id="avatar-orb">
        <img src="/icon.svg?v=2" alt="PiPiBot" width="36" height="36" style="display:block;width:100%;height:100%" />
      </div>
      <div style="min-width:0">
        <div class="brand-title" id="host-title">${hostTitle}</div>
        <div class="brand-sub"><span class="dot" id="conn-dot"></span><span id="conn-text">初始化中…</span></div>
      </div>
    </div>
    <button class="status-pill" id="btn-status-sheet" type="button">
      <span id="transport-badge">E2EE</span>
    </button>
  </header>

  <div class="pwa-banner" id="pwa-banner">
    <span>点击 Safari 分享 →「添加到主屏幕」，即可作为全屏 iOS App 长期使用。</span>
    <button class="btn" id="btn-dismiss-pwa" type="button" style="padding:5px 10px;font-size:11.5px">知道了</button>
  </div>

  <div class="bot-strip" id="bot-strip"></div>

  <main class="main" id="main-view"></main>

  <div class="composer-wrap" id="composer-bar" style="display:none">
    <div class="composer-box">
      <textarea id="chat-input" rows="1" placeholder="发消息给 PiPiBot（群聊可直接说或 @成员）…"></textarea>
      <button class="send-btn" id="btn-send" type="button" aria-label="发送">↑</button>
    </div>
  </div>

  <nav class="tabbar">
    <button class="tab active" data-tab="chat" type="button">
      <svg viewBox="0 0 24 24"><path d="M21 12a8.5 8.5 0 0 1-12.6 7.4L3 21l1.6-5.4A8.5 8.5 0 1 1 21 12Z"/></svg>
      <span>对话</span>
    </button>
    <button class="tab" data-tab="mission" type="button">
      <svg viewBox="0 0 24 24"><rect x="3" y="4" width="7" height="7" rx="2"/><rect x="14" y="4" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/></svg>
      <span>任务台</span>
    </button>
    <button class="tab" data-tab="approvals" type="button">
      <span class="tab-dot" id="badge-approvals"></span>
      <svg viewBox="0 0 24 24"><path d="M12 3 4 7v6c0 5 3.5 7.5 8 8 4.5-.5 8-3 8-8V7l-8-4Z"/><path d="m9 12 2 2 4-4"/></svg>
      <span>审批</span>
    </button>
    <button class="tab" data-tab="diff" type="button">
      <span class="tab-dot" id="badge-diff"></span>
      <svg viewBox="0 0 24 24"><circle cx="6" cy="6" r="2.5"/><circle cx="18" cy="18" r="2.5"/><circle cx="18" cy="6" r="2.5"/><path d="M6 8.5v7A2.5 2.5 0 0 0 8.5 18H15.5"/><path d="M18 8.5V15.5"/></svg>
      <span>Diff</span>
    </button>
    <button class="tab" data-tab="bots" type="button">
      <svg viewBox="0 0 24 24"><circle cx="12" cy="8" r="4"/><path d="M4 20a8 8 0 0 1 16 0"/></svg>
      <span>智能体</span>
    </button>
  </nav>
</div>

<div class="sheet-backdrop" id="status-sheet">
  <div class="sheet">
    <div class="sheet-handle"></div>
    <div class="row">
      <div class="card-title">端到端加密连接详情</div>
      <span class="badge ok">P-256 · AES-256-GCM</span>
    </div>
    <div class="sub" id="sheet-detail"></div>
    <div class="row">
      <button class="btn" id="btn-toggle-theme" type="button">切换亮/暗主题</button>
      <a class="btn" href="/">访问官网</a>
      <button class="btn danger" id="btn-disconnect" type="button">解除本机配对</button>
    </div>
  </div>
</div>

<div class="toast" id="toast"></div>

<script>
(function () {
  const IS_RELAY_MODE = ${relayMode ? 'true' : 'false'};
  const STUN_URLS = ${stunUrls};
  const STORAGE_KEY = 'pipibot_universal_session_v1';

  const savedTheme = localStorage.getItem('pipibot_theme');
  if (savedTheme) document.documentElement.setAttribute('data-theme', savedTheme);

  const b64uEncode = (buf) => {
    const bytes = new Uint8Array(buf);
    let bin = '';
    for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    return btoa(bin).replace(/\\+/g, '-').replace(/\\//g, '_').replace(/=+$/g, '');
  };
  const b64uDecode = (str) => {
    const norm = str.replace(/-/g, '+').replace(/_/g, '/');
    const pad = norm + '='.repeat((4 - (norm.length % 4)) % 4);
    const bin = atob(pad);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  };
  const randHex = (n) => {
    const b = new Uint8Array(n);
    crypto.getRandomValues(b);
    return Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
  };

  function showToast(msg) {
    const el = document.getElementById('toast');
    el.textContent = msg;
    el.classList.add('show');
    clearTimeout(el._t);
    el._t = setTimeout(() => el.classList.remove('show'), 2200);
  }

  function parseCurrentLink() {
    const segs = location.pathname.split('/').filter(Boolean);
    const pathHostId = (segs[0] === 'c' && segs[1]) ? decodeURIComponent(segs[1]) : '';
    const hash = new URLSearchParams(location.hash.replace(/^#/, ''));
    const oneTimeToken = hash.get('t') || '';
    const hostPubKey = hash.get('k') || '';
    const lanHint = hash.get('lan') || '';
    if (oneTimeToken || hostPubKey) {
      const cleanPath = pathHostId ? ('/c/' + encodeURIComponent(pathHostId)) : '/app';
      history.replaceState({}, '', cleanPath);
    }
    return { pathHostId, oneTimeToken, hostPubKey, lanHint };
  }

  function loadSavedSession(hostId) {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return null;
      const parsed = JSON.parse(raw);
      if (hostId && parsed.hostId && parsed.hostId !== hostId) return null;
      return parsed;
    } catch { return null; }
  }
  function saveSession(s) { localStorage.setItem(STORAGE_KEY, JSON.stringify(s)); }

  class E2EERelayTransport {
    constructor(cfg) {
      this.hostId = cfg.hostId;
      this.hostPubKey = cfg.hostPubKey;
      this.lanHint = cfg.lanHint || '';
      this.deviceToken = cfg.deviceToken || '';
      this.oneTimeToken = cfg.oneTimeToken || '';
      this.clientId = 'web_' + randHex(6);
      this.sid = 's_' + randHex(8);
      this.txSeq = 0;
      this.rxSeq = 0;
      this.mode = 'connecting';
      this.ws = null;
      this.pc = null;
      this.dc = null;
      this.pending = new Map();
      this.onStatus = () => {};
    }

    async initCrypto() {
      const kp = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
      this.clientPubKeyB64Url = b64uEncode(await crypto.subtle.exportKey('raw', kp.publicKey));
      const peerRaw = b64uDecode(this.hostPubKey);
      const peerKey = await crypto.subtle.importKey('raw', peerRaw, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
      const sharedBits = await crypto.subtle.deriveBits({ name: 'ECDH', public: peerKey }, kp.privateKey, 256);
      const baseKey = await crypto.subtle.importKey('raw', sharedBits, 'HKDF', false, ['deriveKey']);
      const enc = new TextEncoder();
      this.aesKey = await crypto.subtle.deriveKey(
        {
          name: 'HKDF',
          hash: 'SHA-256',
          salt: enc.encode('pipibot-e2ee-v1:' + this.hostId),
          info: enc.encode('pipibot-aes256gcm-session:' + this.sid),
        },
        baseKey,
        { name: 'AES-GCM', length: 256 },
        false,
        ['encrypt', 'decrypt']
      );
    }

    async seal(obj) {
      this.txSeq += 1;
      const nonce = new Uint8Array(12);
      crypto.getRandomValues(nonce);
      const enc = new TextEncoder();
      const aad = enc.encode('v1|' + this.sid + '|c2h|' + this.txSeq);
      const pt = enc.encode(JSON.stringify(obj));
      const ct = await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce, additionalData: aad }, this.aesKey, pt);
      const env = {
        type: 'envelope', v: 1, hostId: this.hostId, clientId: this.clientId, sid: this.sid,
        dir: 'c2h', seq: this.txSeq, nonce: b64uEncode(nonce), ct: b64uEncode(ct),
      };
      if (this.txSeq === 1) env.clientPubKey = this.clientPubKeyB64Url;
      return env;
    }

    async open(env) {
      if (env.seq <= this.rxSeq) throw new Error('Replay detected');
      const nonce = b64uDecode(env.nonce);
      const ct = b64uDecode(env.ct);
      const enc = new TextEncoder();
      const aad = enc.encode('v1|' + env.sid + '|' + env.dir + '|' + env.seq);
      const pt = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: nonce, additionalData: aad }, this.aesKey, ct);
      this.rxSeq = env.seq;
      return JSON.parse(new TextDecoder().decode(pt));
    }

    async connect() {
      if (this.lanHint && !IS_RELAY_MODE) {
        try {
          const ctrl = new AbortController();
          setTimeout(() => ctrl.abort(), 800);
          const res = await fetch(this.lanHint + '/api/v1/health', { signal: ctrl.signal });
          if (res.ok) { this.mode = 'lan'; this.onStatus('ok', 'LAN 直连'); return; }
        } catch {}
      }
      if (!IS_RELAY_MODE && !this.hostPubKey) {
        this.mode = 'lan'; this.onStatus('ok', '本机直连'); return;
      }

      await this.initCrypto();
      const wsProto = location.protocol === 'https:' ? 'wss:' : 'ws:';
      const wsUrl = wsProto + '//' + location.host + '/ws';

      await new Promise((resolve, reject) => {
        const ws = new WebSocket(wsUrl);
        this.ws = ws;
        const timer = setTimeout(() => reject(new Error('中继连接超时')), 8000);
        ws.onopen = () => {
          ws.send(JSON.stringify({ type: 'client_join', hostId: this.hostId, clientId: this.clientId }));
        };
        ws.onmessage = async (ev) => {
          let msg;
          try { msg = JSON.parse(ev.data); } catch { return; }
          if (msg.type === 'joined') {
            clearTimeout(timer);
            this.mode = 'relay';
            this.onStatus(msg.hostOnline ? 'ok' : 'warn', msg.hostOnline ? 'E2EE 中继' : '主机离线');
            if (msg.hostOnline) this.tryUpgradeWebRTC();
            resolve();
            return;
          }
          if (msg.type === 'host_status') {
            this.onStatus(msg.online ? 'ok' : 'warn', msg.online ? (this.mode === 'p2p' ? 'P2P 打洞' : 'E2EE 中继') : '主机离线');
            return;
          }
          if (msg.type === 'envelope') {
            try { this.handleInnerMessage(await this.open(msg)); } catch {}
          }
        };
        ws.onerror = () => { clearTimeout(timer); reject(new Error('WSS 连接失败')); };
        ws.onclose = () => { this.onStatus('err', '已断开'); };
      });

      if (this.oneTimeToken && !this.deviceToken) {
        const pairRes = await this.request('POST', '/api/v1/auth/pair', {
          code: this.oneTimeToken,
          label: navigator.userAgent.includes('iPhone') ? 'iPhone Safari PWA' : 'Web Companion',
          clientPublicKey: this.clientPubKeyB64Url,
        });
        if (pairRes && pairRes.token) {
          this.deviceToken = pairRes.token;
          this.oneTimeToken = '';
          saveSession({ hostId: this.hostId, hostPubKey: this.hostPubKey, lanHint: this.lanHint, deviceToken: this.deviceToken });
          showToast('已建立端到端加密配对 ✓');
        }
      }
    }

    async tryUpgradeWebRTC() {
      if (typeof RTCPeerConnection === 'undefined') return;
      try {
        const pc = new RTCPeerConnection({ iceServers: [{ urls: STUN_URLS }] });
        this.pc = pc;
        const dc = pc.createDataChannel('pipibot-e2ee', { ordered: true });
        this.dc = dc;
        const p2pTimer = setTimeout(() => {
          if (this.mode !== 'p2p') { try { pc.close(); } catch {} this.pc = null; this.dc = null; }
        }, 2200);
        dc.onopen = () => { clearTimeout(p2pTimer); this.mode = 'p2p'; this.onStatus('ok', 'P2P 打洞'); showToast('已升级为 WebRTC P2P 直连 ⚡'); };
        dc.onmessage = async (ev) => {
          try {
            const env = JSON.parse(ev.data);
            if (env.type === 'envelope') this.handleInnerMessage(await this.open(env));
          } catch {}
        };
        pc.onicecandidate = async (ev) => {
          if (ev.candidate && this.ws && this.ws.readyState === 1) {
            this.ws.send(JSON.stringify(await this.seal({ kind: 'rtc_ice', candidate: ev.candidate.toJSON() })));
          }
        };
        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        if (this.ws && this.ws.readyState === 1) {
          this.ws.send(JSON.stringify(await this.seal({ kind: 'rtc_offer', sdp: offer.sdp })));
        }
      } catch {}
    }

    handleInnerMessage(inner) {
      if (inner.kind === 'rtc_answer' && this.pc && inner.sdp) { this.pc.setRemoteDescription({ type: 'answer', sdp: inner.sdp }).catch(() => {}); return; }
      if (inner.kind === 'rtc_ice' && this.pc && inner.candidate) { this.pc.addIceCandidate(inner.candidate).catch(() => {}); return; }
      if (inner.kind === 'http_res' && inner.reqId && this.pending.has(inner.reqId)) {
        const { resolve } = this.pending.get(inner.reqId);
        this.pending.delete(inner.reqId);
        resolve(inner.body);
      }
    }

    async request(method, path, body) {
      if (this.mode === 'lan') {
        const headers = { 'Content-Type': 'application/json' };
        if (this.deviceToken) headers['Authorization'] = 'Bearer ' + this.deviceToken;
        const base = this.lanHint && IS_RELAY_MODE ? this.lanHint : '';
        const res = await fetch(base + path, { method, headers, body: body !== undefined ? JSON.stringify(body) : undefined });
        return res.json();
      }
      const reqId = 'r_' + randHex(6);
      const env = await this.seal({ kind: 'http_req', reqId, method, path, token: this.deviceToken, body: body ?? null });
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => { this.pending.delete(reqId); reject(new Error('请求超时')); }, 25000);
        this.pending.set(reqId, { resolve: (val) => { clearTimeout(timer); resolve(val); } });
        const wire = JSON.stringify(env);
        if (this.mode === 'p2p' && this.dc && this.dc.readyState === 'open') this.dc.send(wire);
        else if (this.ws && this.ws.readyState === 1) this.ws.send(wire);
        else { clearTimeout(timer); this.pending.delete(reqId); reject(new Error('未连接到主机')); }
      });
    }
  }

  const state = {
    tab: 'chat',
    selectedBotId: '',
    transport: null,
    statusLabel: '等待配对',
    snapshot: {
      hostName: 'PiPiBot',
      messages: [],
      bots: [],
      approvals: [],
      draftGates: [],
      evolutions: [],
      worktrees: [],
      sentinelIssues: [],
      triggers: [],
      usageSummary: null,
    },
  };

  const mainEl = document.getElementById('main-view');
  const composerEl = document.getElementById('composer-bar');
  const botStripEl = document.getElementById('bot-strip');
  const inputEl = document.getElementById('chat-input');
  const connDot = document.getElementById('conn-dot');
  const connText = document.getElementById('conn-text');
  const badgeEl = document.getElementById('transport-badge');
  const statusPill = document.getElementById('btn-status-sheet');

  inputEl.addEventListener('input', () => {
    inputEl.style.height = 'auto';
    inputEl.style.height = Math.min(150, Math.max(28, inputEl.scrollHeight)) + 'px';
  });

  const isStandalone = window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true;
  if (!isStandalone && !localStorage.getItem('pipibot_pwa_hint_dismissed')) {
    document.getElementById('pwa-banner').classList.add('show');
  }
  document.getElementById('btn-dismiss-pwa').onclick = () => {
    document.getElementById('pwa-banner').classList.remove('show');
    localStorage.setItem('pipibot_pwa_hint_dismissed', '1');
  };

  function setStatus(level, label) {
    state.statusLabel = label;
    connDot.className = 'dot ' + (level === 'ok' ? 'ok' : level === 'err' ? 'err' : '');
    connText.textContent = label;
    badgeEl.textContent = label;
    statusPill.className = 'status-pill ' + (level === 'ok' ? 'ok' : '');
  }

  function esc(str) {
    return String(str ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  }

  function renderMarkdown(raw) {
    let html = esc(raw);
    html = html.replace(/\`\`\`[a-zA-Z0-9_-]*\\n([\\s\\S]*?)\`\`\`/g, '<pre>$1</pre>');
    html = html.replace(/\`([^\`\\n]+)\`/g, '<code>$1</code>');
    html = html.replace(/\\*\\*([^\\*\\n]+)\\*\\*/g, '<strong>$1</strong>');
    html = html.replace(/\\n/g, '<br/>');
    return html;
  }

  function renderColoredDiff(diffText) {
    const lines = String(diffText || '').slice(0, 3200).split('\\n');
    return '<div class="diff-box">' + lines.map((line) => {
      let cls = 'diff-line';
      if (line.startsWith('+') && !line.startsWith('+++')) cls += ' add';
      else if (line.startsWith('-') && !line.startsWith('---')) cls += ' del';
      else if (line.startsWith('@@')) cls += ' hunk';
      return '<div class="' + cls + '">' + esc(line) + '</div>';
    }).join('') + '</div>';
  }

  async function refreshSnapshot() {
    if (!state.transport) return;
    try {
      const data = await state.transport.request('GET', '/api/v1/mobile/snapshot');
      if (data && !data.error) {
        state.snapshot = Object.assign(state.snapshot, data);
        if (data.hostName) document.getElementById('host-title').textContent = data.hostName;
        const pend = (state.snapshot.approvals?.length || 0) + (state.snapshot.draftGates?.length || 0) + (state.snapshot.evolutions?.length || 0);
        const appBadge = document.getElementById('badge-approvals');
        appBadge.textContent = pend > 9 ? '9+' : String(pend);
        appBadge.classList.toggle('show', pend > 0);
        const diffs = state.snapshot.worktrees?.length || 0;
        const diffBadge = document.getElementById('badge-diff');
        diffBadge.textContent = String(diffs);
        diffBadge.classList.toggle('show', diffs > 0);
        render();
      }
    } catch {}
  }

  function renderConnectPrompt() {
    composerEl.style.display = 'none';
    botStripEl.classList.remove('show');
    mainEl.innerHTML = \`
      <div class="welcome-hero">
        <div class="avatar-orb pulse" style="width:68px;height:68px;border-radius:18px">
          <img src="/icon.svg?v=2" alt="PiPiBot" width="68" height="68" style="display:block;width:100%;height:100%" />
        </div>
        <div style="font-size:20px;font-weight:760;letter-spacing:-0.025em">连接你的 PiPiBot 主机</div>
        <div class="sub" style="max-width:340px">在 Mac 任务台点击「开启中继并生成链接」，用手机相机扫二维码或粘贴统一链接，即刻建立零知识端到端加密通道。</div>
      </div>
      <div class="card">
        <div class="card-title">粘贴统一配对链接</div>
        <input class="field" id="pair-url-input" placeholder="https://pipibot.jimizhou.com/c/xxxx#t=...&k=..." />
        <button class="btn soul" id="btn-pair-connect" type="button" style="width:100%;padding:11px">建立端到端加密连接</button>
      </div>
      <div class="card">
        <div class="card-title">还没有安装 Mac / Linux 端？</div>
        <div class="sub">PiPiBot 100% 开源免费（MIT），支持原生 macOS 应用与 Linux 无界面多机集群。</div>
        <div class="row">
          <a class="btn primary" href="/">查看品牌官网</a>
          <a class="btn" href="https://github.com/JimiZhou/pipibot" target="_blank" rel="noopener">GitHub 源码</a>
        </div>
      </div>
    \`;
    document.getElementById('btn-pair-connect').onclick = () => {
      const raw = document.getElementById('pair-url-input').value.trim();
      if (raw) location.href = raw;
      else showToast('请先粘贴完整的配对链接');
    };
  }

  async function sendChatText(text) {
    const clean = text.trim();
    if (!clean || !state.transport) return;
    inputEl.value = '';
    inputEl.style.height = '28px';
    state.snapshot.messages.push({ role: 'user', content: clean });
    render();
    try {
      await state.transport.request('POST', '/api/v1/mobile/chat', { text: clean, botId: state.selectedBotId || undefined });
      showToast('已加密送达主机');
      setTimeout(refreshSnapshot, 1200);
    } catch (e) {
      state.snapshot.messages.push({ role: 'assistant', author: '系统', content: '发送失败：' + e.message });
      render();
    }
  }

  function render() {
    if (!state.transport) { renderConnectPrompt(); return; }
    const s = state.snapshot;
    composerEl.style.display = state.tab === 'chat' ? 'block' : 'none';

    if (state.tab === 'chat' && (s.bots || []).length > 0) {
      botStripEl.classList.add('show');
      botStripEl.innerHTML = '<button class="bot-chip ' + (!state.selectedBotId ? 'active' : '') + '" data-bot="">✨ 当前管家</button>' +
        s.bots.slice(0, 8).map((b) => '<button class="bot-chip ' + (state.selectedBotId === b.id ? 'active' : '') + '" data-bot="' + esc(b.id) + '">' + esc(b.name) + '</button>').join('');
      botStripEl.querySelectorAll('.bot-chip').forEach((c) => {
        c.onclick = () => { state.selectedBotId = c.dataset.bot; render(); };
      });
    } else {
      botStripEl.classList.remove('show');
    }

    if (state.tab === 'chat') {
      const msgs = s.messages || [];
      if (msgs.length === 0) {
        mainEl.innerHTML = \`
          <div class="welcome-hero">
            <div style="font-size:18px;font-weight:720;letter-spacing:-0.02em">随时派活给你的数字团队</div>
            <div class="sub">端到端加密通道已就绪，选一张卡片或直接发消息：</div>
            <div class="starter-grid">
              <button class="starter-btn" data-prompt="帮我整理今天最重要的 3 件事和待处理项目状态"><strong>📋 今日待办巡检</strong><span>汇总进展与优先事项</span></button>
              <button class="starter-btn" data-prompt="帮我检查当前项目的 Git 状态和最近变更"><strong>🌿 检查代码状态</strong><span>快速扫描工作区变更</span></button>
              <button class="starter-btn" data-prompt="帮我新建一个自动化定时巡检 Bot"><strong>🥚 访谈建新 Bot</strong><span>召唤蛋宝生成蓝图</span></button>
              <button class="starter-btn" data-prompt="列出当前在线的多机节点和运行中的触发器"><strong>🖥️ 集群状态总览</strong><span>查看多机与触发器</span></button>
            </div>
          </div>
        \`;
        mainEl.querySelectorAll('.starter-btn').forEach((b) => {
          b.onclick = () => sendChatText(b.dataset.prompt);
        });
        return;
      }
      mainEl.innerHTML = msgs.map((m) => \`
        <div class="msg-wrap \${m.role === 'user' ? 'user' : 'assistant'}">
          \${m.role !== 'user' && m.author ? '<div class="msg-author">' + esc(m.author) + '</div>' : ''}
          <div class="msg \${m.role === 'user' ? 'user' : 'assistant'}">\${renderMarkdown(m.content)}</div>
        </div>
      \`).join('');
      mainEl.scrollTop = mainEl.scrollHeight;
      return;
    }

    if (state.tab === 'mission') {
      const issues = s.sentinelIssues || [];
      const u = s.usageSummary;
      const pend = (s.approvals?.length || 0) + (s.draftGates?.length || 0) + (s.evolutions?.length || 0);
      mainEl.innerHTML = \`
        <div class="kpi-grid">
          <div class="kpi"><div class="kpi-val">\${(s.bots || []).length}</div><div class="kpi-label">活跃智能体</div></div>
          <div class="kpi"><div class="kpi-val">\${pend}</div><div class="kpi-label">待你确认项</div></div>
          <div class="kpi"><div class="kpi-val">\${(s.worktrees || []).length}</div><div class="kpi-label">待审阅 Diff</div></div>
          <div class="kpi"><div class="kpi-val">$\${Number(u?.todayCostUSD || 0).toFixed(2)}</div><div class="kpi-label">今日估算消耗（仅提醒）</div></div>
        </div>
        <div class="card">
          <div class="row"><div class="card-title">Sentinel 零 LLM 健康哨兵</div><span class="badge \${issues.length ? 'warn' : 'ok'}">\${issues.length ? (issues.length + ' 项聚类') : '健康'}</span></div>
          \${issues.length === 0
            ? '<div class="sub">零重复工具报错或队列阻塞。Credential Broker 与 Bot Box 隔离运行中。</div>'
            : issues.map((it) => '<div class="row"><span class="sub">[' + it.count + 'x] ' + esc(it.normalizedTitle) + '</span><span class="badge ' + (it.severity === 'high' ? 'err' : 'warn') + '">' + esc(it.severity) + '</span></div>').join('')}
        </div>
      \`;
      return;
    }

    if (state.tab === 'approvals') {
      const blocks = [];
      for (const a of (s.approvals || [])) {
        blocks.push(\`<div class="card">
          <div class="row"><div class="card-title">\${esc(a.title)}</div><span class="badge warn">高危工具审批</span></div>
          <div class="sub">\${esc(a.summary || '')}</div>
          <div class="row"><button class="btn ok" data-act="approve" data-id="\${esc(a.id)}">允许执行</button><button class="btn danger" data-act="deny" data-id="\${esc(a.id)}">拒绝</button></div>
        </div>\`);
      }
      for (const d of (s.draftGates || [])) {
        blocks.push(\`<div class="card">
          <div class="row"><div class="card-title">Day-Shift 外发草稿门控</div><span class="badge">Draft Gate</span></div>
          <div class="sub">\${esc(d.draftContent || '')}</div>
          <div class="row"><button class="btn ok" data-act="draft-approve" data-id="\${esc(d.id)}">批准发送</button><button class="btn danger" data-act="draft-reject" data-id="\${esc(d.id)}">驳回</button></div>
        </div>\`);
      }
      for (const e of (s.evolutions || [])) {
        blocks.push(\`<div class="card">
          <div class="row"><div class="card-title">Blueprint 自进化提案</div><span class="badge ok">EvolutionDiff</span></div>
          <div class="sub">\${esc(e.rationale || e.proposedRule || '')}</div>
          <div class="row"><button class="btn ok" data-act="evo-approve" data-id="\${esc(e.id)}">采纳规则</button><button class="btn danger" data-act="evo-reject" data-id="\${esc(e.id)}">忽略</button></div>
        </div>\`);
      }
      mainEl.innerHTML = blocks.length ? blocks.join('') : '<div class="empty">✨ 当前没有任何待审批操作或进化提案，一切井井有条。</div>';
      mainEl.querySelectorAll('button[data-act]').forEach((btn) => {
        btn.onclick = async () => {
          btn.disabled = true;
          await state.transport.request('POST', '/api/v1/mobile/action', { action: btn.dataset.act, id: btn.dataset.id });
          showToast('已提交决策 ✓');
          await refreshSnapshot();
        };
      });
      return;
    }

    if (state.tab === 'diff') {
      const wts = s.worktrees || [];
      if (!wts.length) {
        mainEl.innerHTML = '<div class="empty">🌿 当前没有待审阅的隔离 Worktree 分支。<br/>当智能体在独立分支完成代码修改与验证后会出现在这里。</div>';
        return;
      }
      mainEl.innerHTML = wts.map((w) => {
        const score = Number(w.proofScore ?? 0);
        return \`<div class="card">
          <div class="row"><div class="card-title">\${esc(w.branchName)}</div><span class="badge \${score >= 80 ? 'ok' : 'warn'}">Proof \${score}%</span></div>
          <div class="proof-bar"><div class="proof-fill" style="width:\${Math.min(100, Math.max(8, score))}%"></div></div>
          <div class="sub">\${esc(w.summary || '')}</div>
          \${renderColoredDiff(w.diffText)}
          <div class="row">
            <button class="btn ok" data-wt="merge" data-id="\${esc(w.id)}">Squash 合入并清理</button>
            <button class="btn danger" data-wt="discard" data-id="\${esc(w.id)}">放弃分支</button>
          </div>
        </div>\`;
      }).join('');
      mainEl.querySelectorAll('button[data-wt]').forEach((btn) => {
        btn.onclick = async () => {
          btn.disabled = true;
          await state.transport.request('POST', '/api/v1/mobile/action', { action: 'worktree-' + btn.dataset.wt, id: btn.dataset.id });
          showToast(btn.dataset.wt === 'merge' ? '已合入并清理 Worktree ✓' : '已放弃该隔离分支');
          await refreshSnapshot();
        };
      });
      return;
    }

    if (state.tab === 'bots') {
      const bots = s.bots || [];
      const triggers = s.triggers || [];
      mainEl.innerHTML = \`
        <div class="card">
          <div class="row"><div class="card-title">智能体团队</div><span class="badge">\${bots.length} 位</span></div>
          \${bots.map((b) => '<div class="row" style="padding:6px 0;border-top:1px solid var(--border)"><div><div style="font-size:13.5px;font-weight:650">' + esc(b.name) + '</div><div class="sub">' + esc(b.role || '') + '</div></div><span class="badge ' + (b.isolation === 'sandbox_box' ? 'ok' : '') + '">' + (b.isolation === 'sandbox_box' ? 'Bot Box' : 'Host') + '</span></div>').join('') || '<div class="sub">等待主机同步…</div>'}
        </div>
        <div class="card">
          <div class="row"><div class="card-title">自动化触发器</div><span class="badge">\${triggers.length} 条</span></div>
          \${triggers.map((t) => '<div class="row" style="padding:5px 0;border-top:1px solid var(--border)"><span style="font-size:13px;font-weight:500">' + esc(t.title) + '</span><span class="badge ' + (t.enabled ? 'ok' : 'warn') + '">' + (t.enabled ? '运行中' : '已暂停') + '</span></div>').join('') || '<div class="sub">暂无自动化触发器</div>'}
        </div>
      \`;
    }
  }

  document.querySelectorAll('.tab').forEach((el) => {
    el.onclick = () => {
      document.querySelectorAll('.tab').forEach((t) => t.classList.remove('active'));
      el.classList.add('active');
      state.tab = el.dataset.tab;
      render();
    };
  });

  document.getElementById('btn-send').onclick = () => sendChatText(inputEl.value);
  inputEl.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
      e.preventDefault();
      sendChatText(inputEl.value);
    }
  });

  // Bottom sheet interactions
  const sheetBackdrop = document.getElementById('status-sheet');
  statusPill.onclick = () => {
    const t = state.transport;
    document.getElementById('sheet-detail').innerHTML = t
      ? ('当前传输通道：<strong>' + esc(state.statusLabel) + '</strong><br/>主机指纹：<code>' + esc(t.hostId || 'local') + '</code><br/>所有业务载荷与 WebRTC 信令均经端到端 AES-256-GCM 加密，中继节点全程零明文可见。')
      : '当前尚未绑定任何 PiPiBot 主机。';
    sheetBackdrop.classList.add('show');
  };
  sheetBackdrop.onclick = (e) => { if (e.target === sheetBackdrop) sheetBackdrop.classList.remove('show'); };
  document.getElementById('btn-toggle-theme').onclick = () => {
    const cur = document.documentElement.getAttribute('data-theme');
    const next = cur === 'dark' ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', next);
    localStorage.setItem('pipibot_theme', next);
    sheetBackdrop.classList.remove('show');
  };
  document.getElementById('btn-disconnect').onclick = () => {
    localStorage.removeItem(STORAGE_KEY);
    location.href = '/pair';
  };

  async function boot() {
    const link = parseCurrentLink();
    const saved = loadSavedSession(link.pathHostId);
    const hostId = link.pathHostId || saved?.hostId || '';
    const hostPubKey = link.hostPubKey || saved?.hostPubKey || '';
    const lanHint = link.lanHint || saved?.lanHint || '';
    const deviceToken = saved?.deviceToken || '';

    if (IS_RELAY_MODE && (!hostId || !hostPubKey)) {
      setStatus('warn', '等待配对');
      renderConnectPrompt();
      return;
    }

    const transport = new E2EERelayTransport({ hostId, hostPubKey, lanHint, deviceToken, oneTimeToken: link.oneTimeToken });
    transport.onStatus = setStatus;
    state.transport = transport;
    render();
    try {
      await transport.connect();
      await refreshSnapshot();
      setInterval(refreshSnapshot, 5000);
    } catch (e) {
      setStatus('err', e.message || '连接失败');
    }
  }

  boot();
})();
</script>
</body>
</html>`;
}
